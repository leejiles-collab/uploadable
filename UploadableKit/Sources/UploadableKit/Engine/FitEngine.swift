import Foundation
import CoreGraphics

/// Makes a photo meet an upload spec, or explains exactly why it cannot.
///
/// The search is two-dimensional: dimensions on the outside, JPEG quality on
/// the inside. Compressors that only search quality can hit a byte *ceiling*
/// but have no answer at all for a byte *floor*, because the only lever they
/// have makes files smaller. Changing the pixel count answers it with real
/// image data instead of padding.
///
/// ## How the outer loop moves
///
/// A fixed ladder walked largest-first was the first attempt and it was wrong
/// twice over. It burned encodes on rungs that were obviously too big, and when
/// a spec stated no pixel bounds the rungs spread so far apart that the answer
/// fell between two of them and the fit was refused — a 4284 × 5712 photo was
/// turned down for New Zealand because the ladder went straight from full size
/// to 530 × 707.
///
/// So the ladder is now a starting suggestion, and the loop is a bracketed
/// search: measure, predict where the answer is from what was measured, keep a
/// known-too-big and known-too-small bound, and converge. Every accepted number
/// is still measured; prediction only chooses where to look next.
public actor FitEngine {

    private let workspace: TempWorkspace

    public init() throws {
        workspace = try TempWorkspace(name: "uploadable-out")
    }

    public func discardOutputs() {
        workspace.discardAll(except: nil)
    }

    public func inspect(url: URL) throws -> SourceFacts {
        try ImageNormaliser.facts(of: url)
    }

    public func fit(
        url: URL,
        to spec: UploadSpec,
        crop: CropRect? = nil,
        outputName: String? = nil,
        onStep: (@Sendable (FitStep) -> Void)? = nil
    ) async throws -> Fit {
        // Yields after every reported step. Two reasons, both of them things
        // that were broken before it did: the working screen showed no steps at
        // all, because a synchronous actor method never gives the main actor a
        // chance to draw between them; and Cancel could not interrupt anything,
        // because there was no suspension point to cancel at.
        @Sendable func report(_ step: FitStep) async {
            onStep?(step)
            await Task.yield()
        }
        let started = Date()
        var transformations: [Transformation] = []

        // 1. Normalise, always first.
        await report(.reading)
        let facts = try ImageNormaliser.facts(of: url)
        transformations.append(.decoded(from: facts.type?.localizedDescription ?? "unknown format"))

        await report(.convertingColour)
        let upright = try ImageNormaliser.normalise(url: url, facts: facts)
        transformations.append(.convertedColor(
            from: facts.profileName ?? "untagged",
            to: "sRGB IEC61966-2.1"
        ))
        await report(.removingMetadata)
        var stripped: [String] = []
        if facts.hasEXIF { stripped.append("EXIF") }
        if facts.hasGPS { stripped.append("location data") }
        transformations.append(.strippedMetadata(kinds: stripped))

        let cropped = ImageNormaliser.croppedSize(of: upright, aspect: spec.aspect, rect: crop)
        if cropped != PixelSize(width: upright.width, height: upright.height) {
            await report(.cropping(cropped.label))
            transformations.append(.cropped(
                to: cropped.label,
                from: ByteFormat.size(upright.width, upright.height)
            ))
        }

        // 2. Where the search may look, and where to start looking.
        let range = try DimensionLadder.bounds(croppedSource: cropped, spec: spec)
        let suggestions = try DimensionLadder.build(croppedSource: cropped, spec: spec)
        let aim = Targets(spec: spec)

        var encodes = 0
        var tried: [String] = []
        var seenFactors: [Double] = []
        var best: (size: PixelSize, quality: Double, bytes: Int, url: URL)?
        var compromise: (size: PixelSize, quality: Double, bytes: Int, url: URL)?
        var undershoot: (size: PixelSize, bytes: Int)?
        var overshoot: (size: PixelSize, bytes: Int)?

        // The bracket. `low` is known to undershoot the byte floor, `high` is
        // known to overshoot the ceiling; the answer lies between them.
        var low: Double?
        var high: Double?
        var factor = range.top

        // Budget for a whole size, not one encode: starting a size with two
        // encodes left produces a truncated search that looks like a finished
        // one.
        while tried.count < Config.maxSizes, encodes + Config.qualitySteps <= Config.maxEncodes {
            guard let size = DimensionLadder.size(
                forFactor: factor, croppedSource: cropped, spec: spec
            ) else { break }
            if tried.contains(size.label) { break }
            tried.append(size.label)
            seenFactors.append(factor)

            await report(.resizing(size.label))
            let rendered = try ImageNormaliser.render(
                upright, aspect: spec.aspect, to: size, crop: crop
            )
            await report(.findingQuality)
            try Task.checkCancellation()
            let probe = try await search(rendered, size: size, spec: spec, aim: aim, encodes: &encodes)

            switch probe.outcome {
            case .landed(let quality, let bytes, let file):
                if quality >= Config.acceptableQuality {
                    best = (size, quality, bytes, file)
                } else if compromise == nil || quality > compromise!.quality {
                    // Fewer pixels for the same byte budget buys quality, which
                    // is the whole reason dimensions are the outer loop.
                    compromise = (size, quality, bytes, file)
                }

            case .tooSmall(let atFullQuality):
                // The undershoot answer: more pixels, not more compression.
                undershoot = (size, atFullQuality)
                low = factor
                if factor >= range.top { break }

            case .tooBig(let atLowestQuality):
                overshoot = (size, atLowestQuality)
                high = factor
                if factor <= range.bottom { break }
            }

            if best != nil { break }

            guard let next = nextFactor(
                after: factor, probe: probe, aim: aim,
                low: low, high: high, range: range,
                suggestions: suggestions, cropped: cropped, spec: spec, seen: seenFactors
            ) else { break }
            factor = next
        }

        let hitCap = encodes >= Config.maxEncodes && best == nil && compromise == nil
        if best == nil { best = compromise }

        // The invariant, stated where it can be seen: nothing below the ship
        // floor leaves here, however it was arrived at.
        if let candidate = best, candidate.quality < Config.shipQualityFloor {
            best = nil
        }

        // 3. Nothing landed. Say which wall we hit and what would move it.
        guard let winner = best else {
            workspace.discardAll(except: nil)
            if let under = undershoot, overshoot == nil {
                throw FitFailure.belowMinimumBytes(
                    got: under.bytes, need: spec.bytes.lowerBound, atSize: under.size.label
                )
            }
            if let over = overshoot {
                throw FitFailure.aboveMaximumBytes(
                    got: over.bytes, limit: spec.bytes.upperBound, atSize: over.size.label
                )
            }
            if let under = undershoot {
                throw FitFailure.belowMinimumBytes(
                    got: under.bytes, need: spec.bytes.lowerBound, atSize: under.size.label
                )
            }
            throw FitFailure.unreadableSource("No size could be produced for this spec.")
        }

        transformations.append(.resized(to: winner.size.label))
        transformations.append(.encoded(quality: winner.quality))

        // 4. Verify by re-reading what is actually on disk.
        await report(.verifying)
        let verification = OutputVerifier.verify(winner.url, against: spec, expecting: winner.size)
        guard verification.passed else {
            workspace.discardAll(except: nil)
            throw FitFailure.verificationFailed(verification.failures)
        }

        let named = rename(winner.url, to: outputName, spec: spec)
        workspace.discardAll(except: named)

        // 5. Things that are true but that the ticks do not cover. Never a
        //    failure — the file measurably meets the spec.
        var warnings: [FitWarning] = []
        if !spec.statesPixelFloor,
           let floor = SpecCatalog.commonShortEdgeMinimum,
           min(winner.size.width, winner.size.height) < floor {
            warnings.append(.belowCommonMinimum(
                short: min(winner.size.width, winner.size.height),
                floor: floor,
                size: winner.size.label,
                cropsAfterUpload: spec.cropsAfterUpload
            ))
        }
        if winner.quality < Config.acceptableQuality {
            warnings.append(.softerThanPreferred(quality: winner.quality))
        }

        return Fit(
            url: named,
            spec: spec,
            source: facts,
            pixelWidth: winner.size.width,
            pixelHeight: winner.size.height,
            byteCount: winner.bytes,
            quality: winner.quality,
            candidatesTried: tried,
            encodeCount: encodes,
            hitEncodeCap: hitCap || encodes >= Config.maxEncodes,
            elapsed: Date().timeIntervalSince(started),
            transformations: transformations,
            verification: verification,
            warnings: warnings
        )
    }

    // MARK: - Where to look next

    /// Predicts from what was just measured, then keeps the prediction inside
    /// whatever bracket is already known.
    ///
    /// JPEG bytes track pixel count closely enough at a fixed quality that one
    /// measurement is a good guide to the next size — and a prediction that
    /// turns out wrong is caught by the next measurement, never trusted.
    private func nextFactor(
        after current: Double,
        probe: Probe,
        aim: Targets,
        low: Double?,
        high: Double?,
        range: DimensionLadder.Bounds,
        suggestions: [PixelSize],
        cropped: PixelSize,
        spec: UploadSpec,
        seen: [Double]
    ) -> Double? {
        var predicted: Double?
        if case .landed(let quality, _, _) = probe.outcome, quality < Config.acceptableQuality {
            // Landed in band, but only by compressing harder than we would like
            // to ship. Byte prediction is no help here — the bytes are already
            // on target — so the lever is pixels: fewer of them carry the same
            // byte budget at a higher quality. Step down and measure again.
            predicted = current * Config.qualityRecoveryStep
        } else if let measured = probe.reference, measured > 0 {
            // Bytes go with area, so the linear scale goes with the square root.
            let scale = (Double(aim.target) / Double(measured)).squareRoot()
            predicted = current * scale
        }

        // Keep it strictly inside the bracket, so a bad prediction cannot
        // bounce the search back to somewhere already ruled out.
        let floorBound = low ?? range.bottom
        let ceilingBound = high ?? range.top
        guard floorBound < ceilingBound else { return nil }

        var next = predicted ?? (floorBound * ceilingBound).squareRoot()
        let margin = (ceilingBound - floorBound) * 0.02
        if next <= floorBound + margin || next >= ceilingBound - margin {
            next = (floorBound * ceilingBound).squareRoot()
        }
        next = min(max(next, range.bottom), range.top)

        // Converged: the bracket is tighter than a rounding step.
        if abs(next - current) / max(current, 0.0001) < 0.01 { return nil }
        if seen.contains(where: { abs($0 - next) / max(next, 0.0001) < 0.01 }) { return nil }
        return next
    }

    // MARK: - Quality search

    private enum Outcome {
        case landed(quality: Double, bytes: Int, url: URL)
        /// Under the byte floor even at maximum quality. More pixels would fix it.
        case tooSmall(atFullQuality: Int)
        /// Over the byte ceiling even at the lowest quality we will ship.
        case tooBig(atLowestQuality: Int)
    }

    private struct Probe {
        let outcome: Outcome
        /// A measured byte count at this size, used to predict the next size.
        let reference: Int?
    }

    /// Binary-searches quality for one fixed size.
    private func search(
        _ image: CGImage,
        size: PixelSize,
        spec: UploadSpec,
        aim: Targets,
        encodes: inout Int
    ) async throws -> Probe {
        // No probes at the extremes. Two encodes per size spent establishing
        // what q0.5 and q1.0 weigh is two encodes not spent finding the answer,
        // and most sizes never go near either end. Start where a photograph
        // usually wants to be and bisect from there; the extremes get measured
        // only if the search actually arrives at one.
        var lowQuality = Config.searchQualityFloor
        var highQuality = Config.qualityCeiling
        var landed: (Double, Int, URL)?
        var quality = Config.startingQuality
        var lastBytes = 0

        for step in 0..<Config.qualitySteps {
            guard encodes < Config.maxEncodes else { break }
            let candidate = workspace.url(named: "try-\(size.width)x\(size.height)-\(step).jpg")
            let bytes = try JPEGEncoder.encode(
                image, to: candidate, quality: quality, exif: spec.exif, icc: spec.icc
            )
            encodes += 1
            lastBytes = bytes
            try Task.checkCancellation()
            await Task.yield()

            if bytes > aim.ceiling {
                highQuality = quality
            } else if bytes < aim.floor {
                lowQuality = quality
            } else {
                // In band. Keep whichever landing sits closest to the target,
                // and steer towards it rather than simply climbing.
                //
                // Climbing was the bug behind an 8.7 MB passport photo: every
                // in-band result raised the quality floor, so a band topping out
                // at 10 MB dragged the search all the way up. In band is not
                // the same as right.
                if landed == nil || abs(bytes - aim.target) < abs(landed!.1 - aim.target) {
                    landed = (quality, bytes, candidate)
                }
                if abs(Double(bytes - aim.target)) < Double(aim.target) * 0.15 { break }
                if bytes < aim.target { lowQuality = quality } else { highQuality = quality }
            }
            if highQuality - lowQuality < 0.02 { break }
            quality = ((lowQuality + highQuality) / 2 * 100).rounded() / 100
        }

        if let landed {
            return Probe(
                outcome: .landed(quality: landed.0, bytes: landed.1, url: landed.2),
                reference: landed.1
            )
        }

        // The search never found the band at this size. Which side it missed on
        // is decided by the last measurement, not by where the quality bracket
        // happened to stop — four bisection steps do not drive the bracket to
        // an edge, and reading the bracket instead of the bytes reported a
        // 2.3 MB file as being under a 240 KB floor.
        let overCeiling = lastBytes > spec.bytes.upperBound

        // Measure the relevant extreme once, so the number shown to the user is
        // one actually taken, and skip it when there is no budget left.
        if encodes < Config.maxEncodes {
            let edgeQuality = overCeiling ? Config.searchQualityFloor : Config.qualityCeiling
            let name = overCeiling ? "edge-low" : "edge-high"
            let url = workspace.url(named: "\(name)-\(size.width)x\(size.height).jpg")
            let bytes = try JPEGEncoder.encode(
                image, to: url, quality: edgeQuality, exif: spec.exif, icc: spec.icc
            )
            encodes += 1
            // The extreme may itself land in band — a size can miss on the way
            // down and still fit at the very bottom of the quality range.
            if spec.bytes.contains(bytes) {
                return Probe(
                    outcome: .landed(quality: edgeQuality, bytes: bytes, url: url),
                    reference: bytes
                )
            }
            return Probe(
                outcome: bytes > spec.bytes.upperBound
                    ? .tooBig(atLowestQuality: bytes)
                    : .tooSmall(atFullQuality: bytes),
                reference: bytes
            )
        }

        return Probe(
            outcome: overCeiling
                ? .tooBig(atLowestQuality: lastBytes)
                : .tooSmall(atFullQuality: lastBytes),
            reference: lastBytes
        )
    }

    private func rename(_ url: URL, to name: String?, spec: UploadSpec) -> URL {
        let base = name ?? "uploadable-\(spec.id)"
        let destination = workspace.url(named: base.hasSuffix(".jpg") ? base : base + ".jpg")
        if destination == url { return url }
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        } catch {
            return url
        }
    }
}

/// The byte size a fit is trying to hit, and the window it will accept.
///
/// Two shapes of spec, and they want opposite things.
///
/// **A band.** New Zealand wants 512 KB to 3.14 MB, US Passport 54 KB to 10 MB.
/// A real floor means a file can fail for being too small, so the aim goes
/// inside the band with clearance at both ends — capped by `preferredBytes`,
/// because sixty percent of the way into UK Passport's 10 MB ceiling is a
/// six-megabyte passport photo.
///
/// **A ceiling.** DS-160 says "240 KB or less" and states no minimum at all.
/// Aiming into the middle of that treats a limit as a target and throws away
/// half the allowance: the same photo landed at 768 × 768 and 127 KB when
/// 1200 × 1200 and 240 KB were permitted. Nobody is helped by a smaller file
/// here — a human inspects these for sharpness, and every pixel and every byte
/// under the cap is free. So the aim goes just under the maximum, and the
/// search does not trade resolution away for quality it does not need.
struct Targets {
    /// What to aim for.
    let target: Int
    /// The acceptable window, held clear of the band's edges.
    let floor: Int
    let ceiling: Int
    /// The spec states no byte minimum, so the band is really a limit and
    /// bigger is strictly better.
    let isCeilingOnly: Bool

    init(spec: UploadSpec) {
        let span = Double(spec.bytes.upperBound - spec.bytes.lowerBound)
        let clearance = min(span * Config.bandEdgeClearance, span / 2)
        floor = spec.bytes.lowerBound + Int(clearance)
        ceiling = spec.bytes.upperBound - Int(clearance)
        isCeilingOnly = spec.bytes.lowerBound == 0

        if isCeilingOnly {
            // Fill the allowance, staying clear of the edge.
            target = ceiling
        } else {
            let proportional = Double(spec.bytes.lowerBound) + span * Config.bandTargetFraction
            let capped = min(proportional, Double(Config.preferredBytes))
            target = max(floor, min(ceiling, Int(capped)))
        }
    }
}

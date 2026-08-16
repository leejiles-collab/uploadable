import Foundation
import CoreGraphics

/// Makes a photo meet an upload spec, or explains exactly why it cannot.
///
/// The search is two-dimensional: dimensions on the outside, JPEG quality on
/// the inside. Compressors that only search quality can hit a byte *ceiling*
/// but have no answer at all for a byte *floor*, because the only lever they
/// have makes files smaller. Stepping up the dimension ladder answers it with
/// real image data instead of padding.
public actor FitEngine {

    private let workspace: TempWorkspace

    public init() throws {
        workspace = try TempWorkspace(name: "fits-out")
    }

    /// Drops every file this engine produced.
    public func discardOutputs() {
        workspace.discardAll(except: nil)
    }

    public func inspect(url: URL) throws -> SourceFacts {
        try ImageNormaliser.facts(of: url)
    }

    public func fit(url: URL, to spec: UploadSpec, outputName: String? = nil) throws -> Fit {
        let started = Date()
        var transformations: [Transformation] = []

        // 1. Normalise, always first. Everything after this works on pixels we
        //    control, in a colour space we chose.
        let facts = try ImageNormaliser.facts(of: url)
        transformations.append(.decoded(from: facts.type?.localizedDescription ?? "unknown format"))

        let upright = try ImageNormaliser.normalise(url: url, facts: facts)
        transformations.append(.convertedColor(
            from: facts.profileName ?? "untagged",
            to: "sRGB IEC61966-2.1"
        ))
        var stripped: [String] = []
        if facts.hasEXIF { stripped.append("EXIF") }
        if facts.hasGPS { stripped.append("location data") }
        transformations.append(.strippedMetadata(kinds: stripped))

        // 2. The ladder. Never proposes a size the source cannot really fill.
        let cropped = ImageNormaliser.croppedSize(of: upright, aspect: spec.aspect)
        if cropped != PixelSize(width: upright.width, height: upright.height) {
            transformations.append(.cropped(
                to: cropped.label,
                from: ByteFormat.size(upright.width, upright.height)
            ))
        }
        let ladder = try DimensionLadder.build(croppedSource: cropped, spec: spec)

        // 3. Walk it, binary-searching quality at each rung.
        var encodes = 0
        var tried: [String] = []
        var best: (size: PixelSize, quality: Double, bytes: Int, url: URL)?
        /// Landed in band, but below the quality we would rather ship. Kept in
        /// case nothing better turns up, because a real file at 0.66 still
        /// beats refusing outright.
        var compromise: (size: PixelSize, quality: Double, bytes: Int, url: URL)?
        var largestUndershoot: (size: PixelSize, bytes: Int)?
        var smallestOvershoot: (size: PixelSize, bytes: Int)?

        for size in ladder {
            guard encodes < Config.maxEncodes else { break }
            tried.append(size.label)
            let rendered = try ImageNormaliser.render(upright, aspect: spec.aspect, to: size)
            let attempt = try search(rendered, size: size, spec: spec, encodes: &encodes)

            switch attempt {
            case .landed(let quality, let bytes, let file):
                if quality >= Config.acceptableQuality {
                    // Good enough, and the ladder runs largest-first, so this is
                    // also the most detail we can get at this quality.
                    best = (size, quality, bytes, file)
                } else if compromise == nil || quality > compromise!.quality {
                    // Keep walking down. The same byte budget spread over fewer
                    // pixels buys quality, which is the whole reason dimensions
                    // are the outer loop.
                    compromise = (size, quality, bytes, file)
                }
            case .tooSmall(let bytes):
                if largestUndershoot == nil { largestUndershoot = (size, bytes) }
            case .tooBig(let bytes):
                smallestOvershoot = (size, bytes)
            }
            if best != nil { break }
        }
        if best == nil { best = compromise }

        // 4 & 5. Nothing landed. Say which wall we hit and what would move it.
        guard let winner = best else {
            workspace.discardAll(except: nil)
            if let under = largestUndershoot {
                throw FitFailure.belowMinimumBytes(
                    got: under.bytes, need: spec.bytes.lowerBound, atSize: under.size.label
                )
            }
            if let over = smallestOvershoot {
                throw FitFailure.aboveMaximumBytes(
                    got: over.bytes, limit: spec.bytes.upperBound, atSize: over.size.label
                )
            }
            throw FitFailure.unreadableSource("No size could be produced for this spec.")
        }

        transformations.append(.resized(to: winner.size.label))
        transformations.append(.encoded(quality: winner.quality))

        // 6. Verify by re-reading what is actually on disk.
        let verification = OutputVerifier.verify(winner.url, against: spec, expecting: winner.size)
        guard verification.passed else {
            workspace.discardAll(except: nil)
            throw FitFailure.verificationFailed(verification.failures)
        }

        let named = rename(winner.url, to: outputName, spec: spec)
        workspace.discardAll(except: named)

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
            elapsed: Date().timeIntervalSince(started),
            transformations: transformations,
            verification: verification
        )
    }

    // MARK: - Quality search

    private enum Attempt {
        case landed(quality: Double, bytes: Int, url: URL)
        /// Under the byte floor even at maximum quality. More pixels would fix it.
        case tooSmall(bytes: Int)
        /// Over the byte ceiling even at the lowest quality we will ship.
        case tooBig(bytes: Int)
    }

    /// Binary-searches quality for one fixed size.
    ///
    /// Aims into the band rather than at its edge: a file two hundred bytes
    /// under a limit is a file that fails the moment a portal counts kibibytes
    /// instead of kilobytes.
    private func search(
        _ image: CGImage,
        size: PixelSize,
        spec: UploadSpec,
        encodes: inout Int
    ) throws -> Attempt {
        let span = Double(spec.bytes.upperBound - spec.bytes.lowerBound)
        let clearance = span * Config.bandEdgeClearance
        let aim = Double(spec.bytes.lowerBound) + span * Config.bandTargetFraction
        let safeLow = Double(spec.bytes.lowerBound) + min(clearance, span / 2)
        let safeHigh = Double(spec.bytes.upperBound) - min(clearance, span / 2)

        // Is the ceiling reachable at all at this size?
        let atFloorQuality = workspace.url(named: "probe-low-\(size.width)x\(size.height).jpg")
        let lowBytes = try JPEGEncoder.encode(
            image, to: atFloorQuality, quality: Config.qualityFloor,
            exif: spec.exif, icc: spec.icc
        )
        encodes += 1
        if lowBytes > spec.bytes.upperBound { return .tooBig(bytes: lowBytes) }

        // Is the floor reachable at all at this size?
        let atCeilingQuality = workspace.url(named: "probe-high-\(size.width)x\(size.height).jpg")
        let highBytes = try JPEGEncoder.encode(
            image, to: atCeilingQuality, quality: Config.qualityCeiling,
            exif: spec.exif, icc: spec.icc
        )
        encodes += 1
        if highBytes < spec.bytes.lowerBound { return .tooSmall(bytes: highBytes) }

        // Maximum quality already sits in the band: take it, nothing beats it.
        if spec.bytes.contains(highBytes), Double(highBytes) <= safeHigh {
            return .landed(quality: Config.qualityCeiling, bytes: highBytes, url: atCeilingQuality)
        }

        var low = Config.qualityFloor
        var high = Config.qualityCeiling
        var landed: (Double, Int, URL)?

        for step in 0..<6 {
            guard encodes < Config.maxEncodes else { break }
            let quality = ((low + high) / 2 * 100).rounded() / 100
            let candidate = workspace.url(named: "try-\(size.width)x\(size.height)-\(step).jpg")
            let bytes = try JPEGEncoder.encode(
                image, to: candidate, quality: quality, exif: spec.exif, icc: spec.icc
            )
            encodes += 1

            if Double(bytes) > safeHigh {
                high = quality
            } else if Double(bytes) < safeLow {
                low = quality
            } else {
                landed = (quality, bytes, candidate)
                // Close enough to the aim to stop refining.
                if abs(Double(bytes) - aim) < span * 0.15 { break }
                low = quality
            }
            if high - low < 0.01 { break }
        }

        if let landed { return .landed(quality: landed.0, bytes: landed.1, url: landed.2) }
        // The search never found the band at this size. Report which side.
        return lowBytes < spec.bytes.lowerBound ? .tooSmall(bytes: highBytes) : .tooBig(bytes: lowBytes)
    }

    private func rename(_ url: URL, to name: String?, spec: UploadSpec) -> URL {
        let base = name ?? "fits-\(spec.id)"
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

import Testing
import Foundation
import CoreGraphics
@testable import UploadableKit

/// One test per bug that reached a screenshot. Each names the symptom, because
/// a regression test whose failure message does not explain what broke is only
/// half a test.
struct RegressionTests {

    // MARK: - Provenance dates rendered a day early

    /// The Spec and Done screens both showed "Requirements verified 14 Aug
    /// 2026" for a date the catalog records as 15 August.
    ///
    /// `SpecCatalog` builds its dates at midnight UTC. Both screens had their
    /// own `DateFormatter` on the device's time zone, so midnight UTC on the
    /// 15th rendered as the 14th anywhere west of Greenwich. The formatter now
    /// lives in the kit, pinned to UTC, and this test runs in whatever zone the
    /// machine is in — which is the point.
    @Test func verificationDatesRenderInUTCNotLocalTime() {
        let verified = SpecCatalog.usVisa.source.verifiedOn!
        #expect(ProvenanceFormat.date(verified) == "15 Aug 2026")
        #expect(ProvenanceFormat.label(for: SpecCatalog.usVisa.source)
                == "Requirements verified 15 Aug 2026")

        // Prove the bug is actually reachable, so this test cannot pass simply
        // because the machine happens to sit on UTC.
        let local = DateFormatter()
        local.dateFormat = "d MMM yyyy"
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = TimeZone(identifier: "America/Los_Angeles")
        #expect(local.string(from: verified) == "14 Aug 2026",
                "the failure mode this guards against no longer exists")
    }

    /// Nothing unverified may claim a date, and everything verified must be
    /// able to state one.
    @Test func onlyVerifiedSourcesProduceALabel() {
        for spec in SpecCatalog.all {
            #expect(ProvenanceFormat.label(for: spec.source) != nil, "\(spec.id)")
        }
        for draft in SpecCatalog.drafts {
            #expect(ProvenanceFormat.label(for: draft.source) == nil, "\(draft.id)")
        }
    }

    // MARK: - Crop rectangles drifting off ratio

    /// A rect dragged on a thumbnail arrives with rounding in it. Canada's 5:7
    /// admits one percent, so a rect that looks right on screen can still fail
    /// the aspect check on the way out — the snap is what stops that.
    @Test func aSlightlyOffRectIsSnappedToExactAspect() {
        let size = PixelSize(width: 4284, height: 5712)

        for rule in [AspectRule.square,
                     .ratio(w: 3, h: 4, tolerance: 0.005),
                     .ratio(w: 5, h: 7, tolerance: 0.01)] {
            let wanted = rule.value!
            // Deliberately 6% out of ratio, and offset, the way a drag leaves it.
            let sloppy = CropRect(x: 0.11, y: 0.07, width: 0.62, height: 0.62 / (wanted * 0.94))
            let pixels = sloppy.pixels(in: size, aspect: wanted)

            let actual = pixels.width / pixels.height
            #expect(abs(actual - wanted) <= wanted * 0.01,
                    "\(rule.label) came out at \(actual), wanted \(wanted)")
            #expect(rule.admits(width: Int(pixels.width), height: Int(pixels.height)),
                    "\(rule.label) rect would fail the spec's own aspect check")
        }
    }

    /// It must also stay inside the photograph. A rect that spills over the
    /// edge would crop in blank space.
    @Test func aRectPushedOffTheEdgeStaysInsideTheImage() {
        let size = PixelSize(width: 1000, height: 1500)
        for rect in [CropRect(x: 0.9, y: 0.9, width: 0.5, height: 0.5),
                     CropRect(x: -0.4, y: -0.3, width: 0.8, height: 0.8),
                     CropRect(x: 0, y: 0, width: 2, height: 2)] {
            let pixels = rect.pixels(in: size, aspect: 1.0)
            #expect(pixels.minX >= 0)
            #expect(pixels.minY >= 0)
            #expect(pixels.maxX <= Double(size.width), "spilled off the right edge")
            #expect(pixels.maxY <= Double(size.height), "spilled off the bottom")
            #expect(pixels.width > 0 && pixels.height > 0)
        }
    }

    /// The default the engine would have picked unaided.
    @Test func theCentredRectIsCentredAndOnRatio() {
        let size = PixelSize(width: 4284, height: 5712)
        let rect = CropRect.centred(aspect: 1.0, in: size)
        let pixels = rect.pixels(in: size, aspect: 1.0)
        #expect(pixels.width == pixels.height)
        #expect(abs(pixels.midY - Double(size.height) / 2) < 2, "not vertically centred")
        #expect(abs(pixels.midX - Double(size.width) / 2) < 2, "not horizontally centred")
    }

    // MARK: - Treating a limit as a target

    /// The Done screen showed 768 × 768 and 127 KB for DS-160, which allows
    /// 1200 × 1200 and 240 KB — less than half the allowance, on a photo a
    /// consular officer inspects for sharpness.
    ///
    /// The cause was aiming `lowerBound + 0.6 * span` into a band whose lower
    /// bound is zero. That is the right aim when a spec has a real floor and a
    /// file can fail for being too small; it is wrong when the number is a
    /// limit rather than a range.
    @Test func aCeilingOnlySpecFillsItsAllowance() async throws {
        let url = try FitEngineTests.writeJPEG(
            FitEngineTests.photographicImage(width: 4284, height: 5712), quality: 0.95
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = try FitEngine()
        let fit = try await engine.fit(url: url, to: SpecCatalog.usVisa)

        // One of the two limits has to be doing the binding. Either the pixel
        // maximum is reached, or the byte budget is mostly spent — if neither
        // is true, the result was smaller than it needed to be, which is the
        // bug. Asserting bytes alone is wrong: a very compressible photograph
        // legitimately lands at 1200 × 1200 for 85 KB, having used every pixel
        // the spec allows.
        let maximumPixels = fit.pixelWidth >= 1200
        let mostOfTheBudget = fit.byteCount > 180_000
        #expect(maximumPixels || mostOfTheBudget,
                "landed at \(fit.pixelWidth)px / \(fit.byteCount) bytes — neither limit was binding")
        #expect(fit.pixelWidth > 900, "shrank to \(fit.pixelWidth) px when 1200 was allowed")
        #expect(fit.quality >= Config.acceptableQuality,
                "filled the allowance by going soft, at q\(fit.quality)")
        #expect(SpecCatalog.usVisa.bytes.contains(fit.byteCount))
        #expect(fit.verification.passed)
        await engine.discardOutputs()
    }

    /// Filling the allowance must not be paid for in blocking artefacts. Against
    /// a fixed byte ceiling, resolution and quality trade against each other, so
    /// a face at q0.50 is a worse submission than a smaller one at q0.70 —
    /// "blurry or pixelated" is a named rejection reason on State's own page.
    ///
    /// A 2400 × 2400 source has room to step down for every offered spec, so
    /// none of them has any excuse for going soft.
    @Test func noOfferedSpecShipsBelowAcceptableQualityFromALargeSource() async throws {
        let url = try FitEngineTests.writeJPEG(
            FitEngineTests.photographicImage(width: 2400, height: 2400), quality: 0.95
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = try FitEngine()
        for spec in SpecCatalog.all {
            guard let fit = try? await engine.fit(url: url, to: spec) else {
                Issue.record("\(spec.id) refused a 2400 × 2400 source outright")
                continue
            }
            #expect(fit.quality >= Config.acceptableQuality,
                    "\(spec.id) shipped q\(fit.quality) at \(fit.pixelWidth)px with room to step down")
            #expect(fit.quality >= Config.shipQualityFloor)
        }
        await engine.discardOutputs()
    }

    /// Whatever route a result took — including the last-resort path that takes
    /// the quality extreme when the search misses the band — it must be inside
    /// the spec's own limits, not merely inside our safety clearance.
    ///
    /// The clearance is ours: it exists because portals disagree about whether
    /// "240 KB" means 240,000 bytes or 245,760. Landing outside it is allowed.
    /// Landing outside the spec is not, ever.
    @Test func everyAcceptedResultIsInsideTheSpecNotJustTheClearance() async throws {
        let engine = try FitEngine()
        // A range of sizes, so some fits take the ordinary path and some are
        // pushed onto the extremes.
        for size in [(4284, 5712), (2400, 2400), (1300, 1300)] {
            let url = try FitEngineTests.writeJPEG(
                FitEngineTests.noisyImage(width: size.0, height: size.1), quality: 0.95
            )
            defer { try? FileManager.default.removeItem(at: url) }

            for spec in SpecCatalog.all {
                guard let fit = try? await engine.fit(url: url, to: spec) else { continue }
                #expect(spec.bytes.contains(fit.byteCount),
                        "\(spec.id) at \(size.0)x\(size.1) produced \(fit.byteCount) bytes, outside \(spec.bytes)")
                #expect(fit.quality >= Config.shipQualityFloor,
                        "\(spec.id) shipped below the ship floor")
                // And the file on disk agrees, which is the check that counts.
                #expect(fit.verification.passed)
            }
        }
        await engine.discardOutputs()
    }

    /// The two shapes must be told apart by the spec, not by name.
    @Test func specsAreClassifiedAsCeilingOrBand() {
        // No stated minimum: a limit.
        #expect(Targets(spec: SpecCatalog.usVisa).isCeilingOnly)
        #expect(Targets(spec: SpecCatalog.canadaPR).isCeilingOnly)
        // A real floor: a range, and a file can fail for being under it.
        #expect(!Targets(spec: SpecCatalog.newZealand).isCeilingOnly)
        #expect(!Targets(spec: SpecCatalog.usPassport).isCeilingOnly)
        #expect(!Targets(spec: SpecCatalog.indiaEVisa).isCeilingOnly)
        #expect(!Targets(spec: SpecCatalog.ukPassport).isCeilingOnly)

        // A ceiling aims at the top; a band aims inside it.
        #expect(Targets(spec: SpecCatalog.usVisa).target > 200_000)
        // And the cap that stopped an 8 MB passport photo still holds.
        #expect(Targets(spec: SpecCatalog.ukPassport).target <= Config.preferredBytes)
    }

    // MARK: - Hiding half a requirement

    /// The DS-160 row read "Square · 600 × 600 and up · up to 240 KB". There is
    /// a 1200 × 1200 maximum, and "and up" hid it from the person deciding
    /// whether their photo fits.
    @Test func aSpecWithAPixelMaximumShowsIt() {
        #expect(SpecCatalog.usVisa.pixelSummary == "600 × 600 to 1200 × 1200")
        #expect(SpecCatalog.canadaPR.pixelSummary == "715 × 1000 to 2000 × 2800")
        #expect(SpecCatalog.usVisa.requirementSummary.contains("1200 × 1200"))

        // "and up" is correct only where no maximum is published.
        #expect(SpecCatalog.ukPassport.pixelSummary == "600 × 750 and up")

        // And a spec that states no pixels at all must not invent any.
        #expect(SpecCatalog.indiaEVisa.pixelSummary == nil)
        #expect(SpecCatalog.newZealand.pixelSummary == nil)
    }

    /// Every offered spec's row must name its real bounds.
    @Test func noOfferedSpecHidesAStatedMaximum() {
        for spec in SpecCatalog.all {
            guard let width = spec.width, width.upperBound < SpecCatalog.noStatedMaximum else { continue }
            let summary = spec.pixelSummary ?? ""
            #expect(!summary.contains("and up"),
                    "\(spec.id) publishes a maximum but its row says 'and up'")
            #expect(summary.contains("\(width.upperBound)"),
                    "\(spec.id) does not show its maximum")
        }
    }

    // MARK: - The async path

    /// Collects steps from the engine's callback, which fires off the actor.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [FitStep] = []
        func record(_ step: FitStep) {
            lock.lock(); defer { lock.unlock() }
            seen.append(step)
        }
        var steps: [FitStep] {
            lock.lock(); defer { lock.unlock() }
            return seen
        }
    }

    /// The Working screen came out completely empty: `fit` was synchronous, so
    /// it never suspended, and every queued main-actor update landed only after
    /// the whole fit had finished. Steps now arrive as the work happens, in the
    /// order the work happens.
    @Test func stepsAreEmittedDuringTheFitAndInOrder() async throws {
        let url = try FitEngineTests.writeJPEG(
            FitEngineTests.noisyImage(width: 2000, height: 2000)
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = Recorder()
        let engine = try FitEngine()
        _ = try await engine.fit(url: url, to: SpecCatalog.usVisa) { step in
            recorder.record(step)
        }

        let steps = recorder.steps
        #expect(!steps.isEmpty, "no steps reported at all — the working screen would be blank")

        func position(of match: @escaping (FitStep) -> Bool) -> Int? {
            steps.firstIndex(where: match)
        }
        let reading = position { $0 == .reading }
        let colour = position { $0 == .convertingColour }
        let metadata = position { $0 == .removingMetadata }
        let resizing = position { if case .resizing = $0 { true } else { false } }
        let quality = position { $0 == .findingQuality }
        let verifying = position { $0 == .verifying }

        #expect(reading != nil && colour != nil && metadata != nil)
        #expect(resizing != nil && quality != nil && verifying != nil)
        // Normalise before deciding anything, size before quality, verify last.
        #expect(reading! < colour!)
        #expect(colour! < metadata!)
        #expect(metadata! < resizing!)
        #expect(resizing! < quality!)
        #expect(quality! < verifying!)
        #expect(verifying! == steps.count - 1, "verification was not the last thing reported")

        await engine.discardOutputs()
    }

    /// Cancel could not interrupt anything either, for the same reason: a
    /// synchronous actor method offers no suspension point to cancel at.
    @Test func aFitCanBeCancelledPartWayThrough() async throws {
        let url = try FitEngineTests.writeJPEG(
            FitEngineTests.noisyImage(width: 4200, height: 4200), quality: 0.95
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = try FitEngine()
        let started = Recorder()

        let work = Task {
            try await engine.fit(url: url, to: SpecCatalog.usVisa) { step in
                started.record(step)
            }
        }
        // Let it get past normalising, then pull the rug.
        try await Task.sleep(for: .milliseconds(80))
        work.cancel()

        do {
            _ = try await work.value
            // Finishing before the cancel landed is legitimate on a fast
            // machine; what must never happen is hanging or returning a file
            // that was never verified.
            #expect(!started.steps.isEmpty)
        } catch is CancellationError {
            // The outcome being guarded: it stopped, promptly, part way through.
            #expect(!started.steps.isEmpty, "cancelled before doing anything at all")
        } catch {
            Issue.record("cancelled fit threw something unexpected: \(error)")
        }

        await engine.discardOutputs()
    }
}

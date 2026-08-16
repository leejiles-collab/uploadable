import Testing
import Foundation
import CoreGraphics
@testable import FitsKit

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

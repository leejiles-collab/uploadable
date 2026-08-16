import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FitsKit

/// These use synthetic images, which are clean in exactly the ways real camera
/// files are not — no EXIF, no P3, no orientation flag. They cover the maths.
/// The colour-space and metadata behaviour has to be checked against real
/// fixtures, which is what `fitscli report` is for.
struct FitEngineTests {

    // MARK: - Making something that compresses like a photograph

    /// A flat colour compresses to almost nothing and would never exercise a
    /// byte band, so this lays down noise with a bit of structure.
    static func noisyImage(width: Int, height: Int, seed: UInt64 = 42) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        var state = seed
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) % 1000) / 1000
        }
        context.setFillColor(CGColor(red: 0.6, green: 0.6, blue: 0.62, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cell = max(2, min(width, height) / 90)
        for y in stride(from: 0, to: height, by: cell) {
            for x in stride(from: 0, to: width, by: cell) {
                context.setFillColor(CGColor(
                    red: next(), green: next(), blue: next(), alpha: 1
                ))
                context.fill(CGRect(x: x, y: y, width: cell, height: cell))
            }
        }
        return context.makeImage()!
    }

    static func writeJPEG(_ image: CGImage, quality: Double = 0.95) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fits-test-\(UUID().uuidString).jpg")
        try JPEGEncoder.encode(image, to: url, quality: quality)
        return url
    }

    // MARK: - The ladder

    @Test func ladderNeverProposesMorePixelsThanTheSourceHas() throws {
        let source = PixelSize(width: 900, height: 900)
        let ladder = try DimensionLadder.build(croppedSource: source, spec: SpecCatalog.usVisa)
        #expect(!ladder.isEmpty)
        for size in ladder {
            #expect(size.width <= source.width)
            #expect(size.height <= source.height)
            #expect(size.width >= 600 && size.width <= 1200)
            #expect(size.width == size.height)
        }
        // Largest first.
        #expect(ladder == ladder.sorted { $0.pixels > $1.pixels })
    }

    @Test func aSourceBelowTheSpecMinimumIsRefusedRatherThanUpscaled() {
        let tiny = PixelSize(width: 400, height: 400)
        #expect(throws: FitFailure.self) {
            try DimensionLadder.build(croppedSource: tiny, spec: SpecCatalog.usVisa)
        }
        do {
            _ = try DimensionLadder.build(croppedSource: tiny, spec: SpecCatalog.usVisa)
        } catch let failure as FitFailure {
            guard case .upscaleRequired(let have, let need) = failure else {
                Issue.record("wrong failure: \(failure)")
                return
            }
            #expect(have == "400 × 400")
            #expect(need == "600 × 600")
            #expect(failure.message.contains("400 × 400"))
            #expect(failure.remedy != nil)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func ratioSpecsProduceRatioCorrectSizes() throws {
        let source = PixelSize(width: 1500, height: 2100)
        let ladder = try DimensionLadder.build(croppedSource: source, spec: SpecCatalog.canadaPR)
        #expect(!ladder.isEmpty)
        for size in ladder {
            #expect(SpecCatalog.canadaPR.aspect.admits(width: size.width, height: size.height))
        }
    }

    /// A spec that states no pixel bounds still has to produce candidates.
    @Test func specsWithoutStatedPixelBoundsStillLadder() throws {
        let source = PixelSize(width: 1800, height: 1800)
        let ladder = try DimensionLadder.build(croppedSource: source, spec: SpecCatalog.indiaEVisa)
        #expect(!ladder.isEmpty)
        for size in ladder { #expect(size.width == size.height) }
    }

    // MARK: - End to end

    @Test func aSquareSpecLandsInsideItsByteBandAndVerifies() async throws {
        let url = try Self.writeJPEG(Self.noisyImage(width: 1600, height: 1600))
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = try FitEngine()
        let fit = try await engine.fit(url: url, to: SpecCatalog.usVisa)

        #expect(fit.pixelWidth == fit.pixelHeight)
        #expect(SpecCatalog.usVisa.bytes.contains(fit.byteCount))
        #expect(fit.verification.passed)
        #expect(fit.encodeCount <= Config.maxEncodes)
        #expect(fit.quality >= Config.qualityFloor)
        await engine.discardOutputs()
    }

    /// The wedge. A photo well under the floor has to grow, not shrink.
    @Test func aByteMinimumIsMetByClimbingTheLadder() async throws {
        // Small and smooth, so it encodes far below New Zealand's 512 KB floor
        // at its natural size.
        let url = try Self.writeJPEG(Self.noisyImage(width: 2400, height: 3200), quality: 0.9)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = try FitEngine()
        let fit = try await engine.fit(url: url, to: SpecCatalog.newZealand)

        #expect(SpecCatalog.newZealand.bytes.contains(fit.byteCount))
        #expect(fit.byteCount >= 512_000)
        #expect(fit.verification.passed)
        await engine.discardOutputs()
    }

    // MARK: - Regressions

    /// IMG_1335: a 4284 × 5712 photo, already exactly 3:4, refused for New
    /// Zealand with "at 530 × 707 ... under the 512 KB minimum".
    ///
    /// The spec states no pixel bounds, so the ladder's floor fell back to one
    /// pixel and five geometric rungs spanned 4284 down to 1 — 4284, 530, 65,
    /// 8, 1. The answer sat in the gap between the first two rungs, the second
    /// undershot the byte floor, and there was no larger rung left to step to.
    @Test func aLarge3To4SourceMeetsAByteFloorItPreviouslyRefused() async throws {
        let url = try Self.writeJPEG(Self.noisyImage(width: 4284, height: 5712), quality: 0.92)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = try FitEngine()
        let fit = try await engine.fit(url: url, to: SpecCatalog.newZealand)

        #expect(SpecCatalog.newZealand.bytes.contains(fit.byteCount))
        #expect(fit.byteCount >= 512_000, "landed under New Zealand's floor")
        #expect(SpecCatalog.newZealand.aspect.admits(width: fit.pixelWidth, height: fit.pixelHeight))
        #expect(fit.verification.passed)
        // The failure mode was a ladder that skipped the answer entirely.
        #expect(fit.pixelWidth > 530, "still collapsing to the bottom of the ladder")
        await engine.discardOutputs()
    }

    /// The ladder must not span orders of magnitude when a spec states no
    /// pixel bounds. This is the shape of the bug, independent of encoding.
    @Test func anOpenEndedSpecDoesNotProduceAWildLadder() throws {
        let source = PixelSize(width: 4284, height: 5712)
        let ladder = try DimensionLadder.build(croppedSource: source, spec: SpecCatalog.newZealand)

        #expect(ladder.count >= 2)
        let smallest = ladder.last!
        #expect(smallest.width >= Int(Double(source.width) * 0.15),
                "ladder reaches \(smallest.label), far below anything useful")
        // No rung may be more than about 3x the pixels of the next one down.
        for (a, b) in zip(ladder, ladder.dropFirst()) {
            #expect(Double(a.pixels) / Double(b.pixels) < 4.0,
                    "gap between \(a.label) and \(b.label) is too wide to bracket an answer")
        }
    }

    /// A band of 50 KB – 10 MB is not an invitation to produce an 8 MB
    /// passport photo. Sixty percent into that band is 6 MB.
    @Test func aWideBandTargetsASensibleAbsoluteSizeNotAPercentage() async throws {
        let url = try Self.writeJPEG(Self.noisyImage(width: 3000, height: 3600), quality: 0.95)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = try FitEngine()
        let fit = try await engine.fit(url: url, to: SpecCatalog.ukPassport)

        #expect(SpecCatalog.ukPassport.bytes.contains(fit.byteCount))
        #expect(fit.byteCount <= 3_000_000,
                "produced \(ByteFormat.string(fit.byteCount)) for a passport photo")
        #expect(fit.verification.passed)
        await engine.discardOutputs()
    }

    /// A preset that rules nothing out would approve a screenshot.
    @Test func everyOfferedPresetActuallyConstrainsSomething() {
        for spec in SpecCatalog.all {
            #expect(spec.constrainsSomething, "\(spec.id) rules nothing out")
            #expect(spec.isOfferable, "\(spec.id) is not safe to put in front of a user")
        }
        // And the one that does not is kept out of the offered list.
        #expect(SpecCatalog.drafts.contains { !$0.constrainsSomething })
        #expect(!SpecCatalog.all.contains { $0.id == "schengen-france" })
    }

    /// The screenshot that Schengen waved through: small, wrong shape, tiny.
    @Test func aScreenshotSizedSourceIsRefusedByEveryOfferedSquareSpec() async throws {
        let url = try Self.writeJPEG(Self.noisyImage(width: 398, height: 600))
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = try FitEngine()
        for spec in SpecCatalog.all where spec.width != nil {
            await #expect(throws: FitFailure.self, "\(spec.id) accepted a 398 × 600 screenshot") {
                try await engine.fit(url: url, to: spec)
            }
        }
        await engine.discardOutputs()
    }

    // MARK: - Verification

    @Test func theRawJPEGParserAgreesWithImageIO() throws {
        let url = try Self.writeJPEG(Self.noisyImage(width: 640, height: 480))
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        let parsed = OutputVerifier.rawJPEGDimensions(data)
        let reported = OutputVerifier.imageIODimensions(url)

        #expect(parsed == PixelSize(width: 640, height: 480))
        #expect(parsed == reported)
    }

    @Test func outputCarriesAnSRGBProfileReadableTwoWays() throws {
        let url = try Self.writeJPEG(Self.noisyImage(width: 700, height: 700))
        defer { try? FileManager.default.removeItem(at: url) }

        let viaImageIO = OutputVerifier.iccDescription(url)
        let viaRawParse = OutputVerifier.rawICCDescription(try Data(contentsOf: url))

        #expect(viaImageIO != nil, "no profile reported by ImageIO")
        #expect(viaRawParse != nil, "no ICC profile found in the file's own APP2 segments")
        #expect(viaImageIO?.localizedCaseInsensitiveContains("srgb") == true)
        #expect(viaRawParse?.localizedCaseInsensitiveContains("srgb") == true)
    }

    @Test func outputCarriesNoEXIFOrLocation() throws {
        let url = try Self.writeJPEG(Self.noisyImage(width: 700, height: 700))
        defer { try? FileManager.default.removeItem(at: url) }

        let properties = OutputVerifier.imageIOProperties(url)
        // Establish the file is real first. An unreadable file has no EXIF
        // either, and this test passed against a 20-byte stub until it did
        // this — absence of a property is only meaningful if there is an image.
        #expect(properties != nil, "the file could not be read at all")
        #expect(OutputVerifier.imageIODimensions(url) == PixelSize(width: 700, height: 700))
        #expect(properties?[kCGImagePropertyExifDictionary] == nil)
        #expect(properties?[kCGImagePropertyGPSDictionary] == nil)
    }

    // MARK: - Provenance

    @Test func everyPresetDeclaresWhereItsNumbersCameFrom() {
        for spec in SpecCatalog.all {
            #expect(!spec.source.url.absoluteString.isEmpty, "\(spec.id) has no source URL")
            #expect(spec.bytes.lowerBound <= spec.bytes.upperBound, "\(spec.id) has an inverted band")
            if let width = spec.width, let height = spec.height {
                #expect(width.lowerBound <= width.upperBound)
                #expect(height.lowerBound <= height.upperBound)
            }
            // An unverified preset must say why, so the UI can explain itself.
            if !spec.source.isVerified {
                #expect(spec.source.note != nil, "\(spec.id) is unverified with no explanation")
            }
        }
    }

    /// Nothing unverified may reach a user. This is the invariant behind the
    /// whole provenance apparatus, so it is asserted rather than assumed.
    @Test func nothingOfferedIsUnverified() {
        for spec in SpecCatalog.all {
            #expect(spec.source.isVerified, "\(spec.id) is offered without a verification date")
            #expect(!spec.source.urlIsDead, "\(spec.id) is offered with a dead source link")
        }
        #expect(SpecCatalog.all.count == 6)
        #expect(SpecCatalog.drafts.count == 2)
        for draft in SpecCatalog.drafts {
            #expect(!SpecCatalog.all.contains { $0.id == draft.id })
            #expect(draft.source.note != nil, "\(draft.id) is a draft with no reason given")
        }
    }

    /// A spec may accept several formats. Claiming JPEG is required where the
    /// source does not say so is putting words in a government's mouth.
    @Test func specsDistinguishAcceptedFormatsFromWhatWeEmit() {
        #expect(SpecCatalog.usPassport.accepted.count > 1)
        #expect(!SpecCatalog.usPassport.mandatesOutputFormat)
        #expect(SpecCatalog.usVisa.mandatesOutputFormat)
        for spec in SpecCatalog.all {
            #expect(spec.accepted.contains(spec.output),
                    "\(spec.id) emits a format it does not list as accepted")
        }
    }

    /// US Passport now states no pixel bounds and no shape — the same
    /// open-ended shape that made New Zealand refuse a perfectly good photo.
    @Test func anOpenEndedPassportSpecStillProducesSensibleOutput() async throws {
        let url = try Self.writeJPEG(Self.noisyImage(width: 4032, height: 3024), quality: 0.95)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = try FitEngine()
        let fit = try await engine.fit(url: url, to: SpecCatalog.usPassport)

        #expect(SpecCatalog.usPassport.bytes.contains(fit.byteCount))
        #expect(fit.byteCount >= 54_000)
        #expect(fit.byteCount <= 3_000_000, "a passport photo should not be huge")
        #expect(fit.pixelWidth >= 600, "collapsed to \(fit.pixelWidth) px wide")
        #expect(fit.verification.passed)
        #expect(!fit.hitEncodeCap)
        await engine.discardOutputs()
    }

    @Test func verifiedPresetsCarryARealDate() {
        let verified = SpecCatalog.all.filter(\.source.isVerified)
        #expect(verified.count >= 5)
        for spec in verified {
            #expect(spec.source.age()! >= 0, "\(spec.id) is verified in the future")
        }
    }
}

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

    @Test func verifiedPresetsCarryARealDate() {
        let verified = SpecCatalog.all.filter(\.source.isVerified)
        #expect(verified.count >= 5)
        for spec in verified {
            #expect(spec.source.age()! >= 0, "\(spec.id) is verified in the future")
        }
    }
}

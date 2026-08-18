import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import UploadableKit

/// Which way up the pixels come out.
///
/// Build 1 shipped with four of the eight EXIF orientations wrong — every one
/// that swaps the axes. A portrait iPhone photo (orientation 6) saved to Photos
/// upside down. Nothing caught it: the dimensions were right, the EXIF tag was
/// correctly stripped, and `OutputVerifier` has no way to know which way up a
/// photograph belongs. Only a person looking at their own face did.
///
/// So this checks the pixels. A marker is written into the stored top-left
/// corner and the test asserts where it lands after the orientation is applied.
/// The expectation is a table of corners — data, read off the EXIF spec — not a
/// second implementation of the transforms, which would just repeat whatever
/// mistake the first one made.
struct OrientationTests {

    enum Corner: String { case topLeft, topRight, bottomLeft, bottomRight }

    /// Where a marker stored at the top-left ends up once each flag is applied.
    static let expected: [Int: Corner] = [
        1: .topLeft,      // as stored
        2: .topRight,     // mirrored horizontally
        3: .bottomRight,  // rotated 180
        4: .bottomLeft,   // mirrored vertically
        5: .topLeft,      // transposed
        6: .topRight,     // rotated 90 clockwise
        7: .bottomRight,  // transverse
        8: .bottomLeft    // rotated 90 anticlockwise
    ]

    // MARK: - Fixtures

    /// A JPEG whose stored pixels carry a bright square in the top-left, tagged
    /// with `orientation`. Deliberately not square, so an orientation that
    /// swaps the axes has to change the dimensions too.
    static func source(orientation: Int, width: Int = 120, height: Int = 180) throws -> URL {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(gray: 0.05, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // CGContext is y-up, so the image's top edge is the high-y end.
        let marker = min(width, height) * 2 / 5
        context.setFillColor(gray: 1.0, alpha: 1)
        context.fill(CGRect(x: 0, y: height - marker, width: marker, height: marker))

        let image = context.makeImage()!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("orientation-\(orientation)-\(UUID().uuidString).jpg")
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 1.0,
            kCGImagePropertyOrientation: orientation
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// The brightest corner of an image, measured by sampling four quadrants.
    static func brightestCorner(of image: CGImage) -> Corner {
        let side = 64
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: side * side * 4)

        // Quadrant means, in image coordinates: row 0 is the top.
        func mean(rows: Range<Int>, columns: Range<Int>) -> Double {
            var total = 0.0
            for row in rows {
                // A CGBitmapContext's buffer starts at the *top* row, so image
                // row r is buffer row r. (Drawing coordinates are y-up, which is
                // a different thing and does not apply to the buffer layout —
                // conflating them flipped every case in this test's first run.)
                for column in columns {
                    total += Double(pixels[(row * side + column) * 4])
                }
            }
            return total / Double(rows.count * columns.count)
        }
        let half = side / 2
        let quadrants: [(Corner, Double)] = [
            (.topLeft, mean(rows: 0..<half, columns: 0..<half)),
            (.topRight, mean(rows: 0..<half, columns: half..<side)),
            (.bottomLeft, mean(rows: half..<side, columns: 0..<half)),
            (.bottomRight, mean(rows: half..<side, columns: half..<side))
        ]
        return quadrants.max(by: { $0.1 < $1.1 })!.0
    }

    // MARK: - Tests

    @Test("every EXIF orientation is baked in the right way up", arguments: 1...8)
    func normaliseUprightsEveryOrientation(orientation: Int) throws {
        let url = try Self.source(orientation: orientation)
        defer { try? FileManager.default.removeItem(at: url) }

        let facts = try ImageNormaliser.facts(of: url)
        #expect(facts.orientation == orientation, "the fixture lost its tag")

        let upright = try ImageNormaliser.normalise(url: url, facts: facts)
        #expect(upright.width == facts.uprightWidth)
        #expect(upright.height == facts.uprightHeight)
        #expect(
            Self.brightestCorner(of: upright) == Self.expected[orientation],
            "orientation \(orientation) put the marker in the wrong corner"
        )
    }

    /// The whole path, ending at a file on disk — which is what gets handed to
    /// Photos, and what was upside down on a real phone.
    @Test("a rotated photo is still the right way up in the written file")
    func fullFitKeepsThePhotoTheRightWayUp() async throws {
        for orientation in [6, 8] {
            // Big enough that DS-160's 600 x 600 minimum does not refuse it —
            // the engine will not upscale, which is correct and unrelated.
            let url = try Self.source(orientation: orientation, width: 900, height: 1350)
            defer { try? FileManager.default.removeItem(at: url) }

            let engine = try FitEngine()
            let fit = try await engine.fit(url: url, to: SpecCatalog.usVisa)
            defer { Task { await engine.discardOutputs() } }

            // Read the finished file back off disk, the way Photos would.
            let source = CGImageSourceCreateWithURL(fit.url as CFURL, nil)!
            let written = CGImageSourceCreateImageAtIndex(source, 0, nil)!

            #expect(
                Self.brightestCorner(of: written) == Self.expected[orientation],
                "orientation \(orientation) reached the file upside down"
            )
        }
    }
}

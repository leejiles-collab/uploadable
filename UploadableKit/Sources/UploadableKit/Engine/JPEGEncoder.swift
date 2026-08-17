import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Writes a JPEG, and nothing else.
///
/// The image handed in is already upright, already sRGB and already the right
/// size. All that is left is the quality dial and making sure no metadata comes
/// along for the ride.
public enum JPEGEncoder {

    /// Encodes and returns the byte count as measured on disk.
    ///
    /// The count comes from `FileManager` rather than from any buffer we held,
    /// because the whole point of the byte band is what the upload form will
    /// see when it stats the file.
    @discardableResult
    public static func encode(
        _ image: CGImage,
        to url: URL,
        quality: Double,
        exif: EXIFPolicy = .stripAll,
        icc: ICCPolicy = .embedSRGB
    ) throws -> Int {
        let subject = icc == .stripAll ? try untagged(image) : image

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw FitFailure.unreadableSource("Could not create a JPEG writer.")
        }

        // Metadata is removed by construction, not by request. The image was
        // drawn into a fresh CGContext upstream, so it arrives carrying nothing
        // — no EXIF, no GPS, no orientation flag, because the rotation is
        // already baked into the pixels.
        //
        // Do NOT try to strip by setting the property dictionaries to kCFNull
        // here. That is the idiom for CGImageDestinationCopyImageSource, and on
        // this path it makes ImageIO emit a 20-byte stub: still starting FFD8,
        // so it looks like a JPEG to anything that only checks the marker, but
        // with no image in it. Measured, not guessed.
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]

        CGImageDestinationAddImage(destination, subject, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw FitFailure.unreadableSource("The JPEG could not be written.")
        }

        // ImageIO leaves no ICC profile behind and adds an EXIF block of its
        // own, so the file is finished by hand. This happens before measuring:
        // the profile is about 3 KB and the solver is aiming at a byte band, so
        // the number it works with has to be the number the form will see.
        if let raw = try? Data(contentsOf: url),
           let rewritten = JPEGSegments.rewrite(
               raw, stripEXIF: exif == .stripAll, embedSRGB: icc == .embedSRGB
           ) {
            try rewritten.write(to: url, options: .atomic)
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        guard let size else {
            throw FitFailure.unreadableSource("The JPEG was written but could not be measured.")
        }
        return size
    }

    /// Redraws in device RGB so no profile is embedded.
    ///
    /// Exists only because `ICCPolicy.stripAll` is representable. No spec we
    /// have verified asks for it, so this path is unexercised in practice.
    private static func untagged(_ image: CGImage) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw FitFailure.unreadableSource("Could not allocate an untagged context.")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let out = context.makeImage() else {
            throw FitFailure.unreadableSource("Could not render untagged.")
        }
        return out
    }
}

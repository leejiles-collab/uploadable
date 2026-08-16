import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Reads what a file actually is, and turns it into pixels we control.
///
/// Everything downstream assumes an upright, sRGB, metadata-free `CGImage`.
/// Producing one is this type's whole job, and it happens before any decision
/// about size or quality is made.
public enum ImageNormaliser {

    /// What the file is, read from its bytes rather than its name.
    ///
    /// A HEIC renamed to `.jpg` is the commonest cause of "File Must Be JPEG",
    /// so the extension is never consulted.
    public static func facts(of url: URL) throws -> SourceFacts {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw FitFailure.unreadableSource("It isn't an image file we can open.")
        }
        guard CGImageSourceGetCount(source) > 0 else {
            throw FitFailure.unreadableSource("The file contains no image.")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]

        let byteCount = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let type = CGImageSourceGetType(source)
            .flatMap { UTType($0 as String) }

        return SourceFacts(
            pixelWidth: properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
            pixelHeight: properties[kCGImagePropertyPixelHeight] as? Int ?? 0,
            byteCount: byteCount,
            type: type,
            profileName: properties[kCGImagePropertyProfileName] as? String,
            hasEXIF: properties[kCGImagePropertyExifDictionary] != nil,
            hasGPS: properties[kCGImagePropertyGPSDictionary] != nil,
            orientation: properties[kCGImagePropertyOrientation] as? Int ?? 1
        )
    }

    /// Decodes and returns an upright image in sRGB with no metadata attached.
    ///
    /// The colour space comes from the context we draw into, not from a
    /// property key — handing `CGImageDestination` a P3 image and asking nicely
    /// for sRGB does nothing. Drawing P3 pixels into an sRGB context is what
    /// actually converts them.
    ///
    /// Orientation has to be baked in here too. We strip EXIF, and EXIF is
    /// where the orientation flag lives, so an image left rotated would arrive
    /// at the portal on its side.
    public static func normalise(url: URL, facts: SourceFacts) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCache: false
              ] as CFDictionary)
        else {
            throw FitFailure.unreadableSource("The image data could not be decoded.")
        }
        return try uprightSRGB(decoded, orientation: facts.orientation)
    }

    /// A small upright copy, for showing the photo before anything is decided.
    ///
    /// Goes through ImageIO's thumbnail path rather than decoding the whole
    /// image: a 4284 × 5712 source is 24 megapixels, and the crop screen needs
    /// a few hundred thousand. `WithTransform` applies the orientation, so the
    /// preview matches `SourceFacts.uprightSize` and a rect dragged on it means
    /// the same thing to the engine.
    public static func preview(url: URL, maxEdge: Int = 1400) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge
        ] as CFDictionary)
    }

    /// Draws into an sRGB context, applying the EXIF orientation as it goes.
    static func uprightSRGB(_ image: CGImage, orientation: Int) throws -> CGImage {
        let swapsAxes = (5...8).contains(orientation)
        let width = swapsAxes ? image.height : image.width
        let height = swapsAxes ? image.width : image.height

        guard let context = sRGBContext(width: width, height: height) else {
            throw FitFailure.unreadableSource("Could not allocate a drawing context.")
        }
        context.interpolationQuality = .high
        context.concatenate(transform(for: orientation, width: width, height: height))
        // After the transform the drawing space is the image's own orientation,
        // so draw at the untransformed size.
        context.draw(image, in: CGRect(
            x: 0, y: 0,
            width: swapsAxes ? height : width,
            height: swapsAxes ? width : height
        ))

        guard let out = context.makeImage() else {
            throw FitFailure.unreadableSource("Could not render the image.")
        }
        return out
    }

    /// Crops to the aspect rule and scales to an exact pixel size.
    static func render(
        _ image: CGImage, aspect: AspectRule, to size: PixelSize, crop rect: CropRect? = nil
    ) throws -> CGImage {
        let cropped = crop(image, toAspect: aspect, rect: rect) ?? image
        guard let context = sRGBContext(width: size.width, height: size.height) else {
            throw FitFailure.unreadableSource("Could not allocate a drawing context.")
        }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let out = context.makeImage() else {
            throw FitFailure.unreadableSource("Could not render at \(size.label).")
        }
        return out
    }

    /// The part of the image to keep: what the user placed, or the largest
    /// centred rect of the required shape when they placed nothing.
    static func crop(_ image: CGImage, toAspect aspect: AspectRule, rect: CropRect? = nil) -> CGImage? {
        let size = PixelSize(width: image.width, height: image.height)
        if let rect {
            let pixels = rect.pixels(in: size, aspect: aspect.value)
            // A rect covering the whole frame of a .free spec is not a crop.
            if pixels == CGRect(x: 0, y: 0, width: size.width, height: size.height) {
                return image
            }
            return image.cropping(to: pixels)
        }
        guard let wanted = aspect.value else { return image }
        let width = Double(image.width)
        let height = Double(image.height)
        let current = width / height
        if abs(current - wanted) < 0.0001 { return image }

        var rect: CGRect
        if current > wanted {
            // Too wide: take a full-height slice.
            let w = (height * wanted).rounded(.down)
            rect = CGRect(x: ((width - w) / 2).rounded(.down), y: 0, width: w, height: height)
        } else {
            // Too tall: take a full-width slice.
            let h = (width / wanted).rounded(.down)
            rect = CGRect(x: 0, y: ((height - h) / 2).rounded(.down), width: width, height: h)
        }
        return image.cropping(to: rect)
    }

    /// The size of the aspect-correct crop, in source pixels. This is the real
    /// ceiling on output resolution — anything larger is upscaling.
    static func croppedSize(of image: CGImage, aspect: AspectRule, rect: CropRect? = nil) -> PixelSize {
        guard let cropped = crop(image, toAspect: aspect, rect: rect) else {
            return PixelSize(width: image.width, height: image.height)
        }
        return PixelSize(width: cropped.width, height: cropped.height)
    }

    private static func sRGBContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        // noneSkipLast: JPEG carries no alpha, and an alpha channel here would
        // be dropped at encode time anyway.
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
    }

    /// CGContext is y-up; these are the standard EXIF orientation transforms.
    private static func transform(for orientation: Int, width: Int, height: Int) -> CGAffineTransform {
        let w = CGFloat(width), h = CGFloat(height)
        return switch orientation {
        case 2: CGAffineTransform(translationX: w, y: 0).scaledBy(x: -1, y: 1)
        case 3: CGAffineTransform(translationX: w, y: h).scaledBy(x: -1, y: -1)
        case 4: CGAffineTransform(translationX: 0, y: h).scaledBy(x: 1, y: -1)
        case 5: CGAffineTransform(rotationAngle: .pi / 2).scaledBy(x: 1, y: -1)
        case 6: CGAffineTransform(translationX: w, y: 0).rotated(by: .pi / 2)
        case 7: CGAffineTransform(translationX: w, y: h).rotated(by: .pi / 2).scaledBy(x: 1, y: -1)
        case 8: CGAffineTransform(translationX: 0, y: h).rotated(by: -.pi / 2)
        default: .identity
        }
    }
}

/// An exact output size.
public struct PixelSize: Sendable, Hashable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var label: String { ByteFormat.size(width, height) }
    public var pixels: Int { width * height }
}

import Foundation
import CoreGraphics

/// Which part of the photograph to keep, in the upright image's own coordinates.
///
/// Normalised 0–1 so it survives the difference between the thumbnail the user
/// dragged on and the full-resolution image the engine works with.
///
/// The engine centre-crops when this is nil, which is the right default and the
/// only thing it will ever decide by itself. It does not look at the picture —
/// no face detection, ever. Placing the crop is a judgement about the
/// photograph, and that belongs to the person who took it.
public struct CropRect: Sendable, Hashable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The whole frame.
    public static let full = CropRect(x: 0, y: 0, width: 1, height: 1)

    /// The largest centred rect of a given aspect ratio, which is what the
    /// engine falls back to and what the UI starts the handles at.
    public static func centred(aspect: Double?, in size: PixelSize) -> CropRect {
        guard let aspect, size.width > 0, size.height > 0 else { return .full }
        let current = Double(size.width) / Double(size.height)
        if abs(current - aspect) < 0.0001 { return .full }
        if current > aspect {
            let w = aspect / current
            return CropRect(x: (1 - w) / 2, y: 0, width: w, height: 1)
        }
        let h = current / aspect
        return CropRect(x: 0, y: (1 - h) / 2, width: 1, height: h)
    }

    /// In pixels, clamped inside the image and snapped to an exact aspect.
    ///
    /// The snap is not politeness. A rect dragged on a thumbnail arrives with
    /// rounding in it, and a spec like Canada's 5:7 has a tolerance of one
    /// percent — close enough to look right on screen and still fail the
    /// aspect check on the way out.
    public func pixels(in size: PixelSize, aspect: Double?) -> CGRect {
        let clampedX = min(max(x, 0), 1)
        let clampedY = min(max(y, 0), 1)
        var w = min(max(width, 0.01), 1 - clampedX) * Double(size.width)
        var h = min(max(height, 0.01), 1 - clampedY) * Double(size.height)

        if let aspect {
            // Shrink the longer side rather than growing the shorter one, so
            // the result can never spill outside the image.
            if w / h > aspect { w = h * aspect } else { h = w / aspect }
        }

        let originX = min(clampedX * Double(size.width), Double(size.width) - w)
        let originY = min(clampedY * Double(size.height), Double(size.height) - h)
        return CGRect(
            x: max(0, originX.rounded(.down)),
            y: max(0, originY.rounded(.down)),
            width: max(1, w.rounded(.down)),
            height: max(1, h.rounded(.down))
        )
    }
}

/// What the engine is doing, as it does it.
///
/// The working screen shows these because they *are* the product — "converting
/// to sRGB" and "finding the right quality" is the whole pitch, stated as it
/// happens. A spinner would hide the only interesting thing about the app.
public enum FitStep: Sendable, Hashable {
    case reading
    case convertingColour
    case removingMetadata
    case cropping(String)
    case resizing(String)
    case findingQuality
    case verifying

    public var label: String {
        switch self {
        case .reading: "Reading the photo"
        case .convertingColour: "Converting to sRGB"
        case .removingMetadata: "Removing location data"
        case .cropping(let size): "Cropping to \(size)"
        case .resizing(let size): "Resizing to \(size)"
        case .findingQuality: "Finding the right quality"
        case .verifying: "Checking the file"
        }
    }
}

import Foundation

/// The sizes worth trying, largest first.
///
/// Dimensions are the outer loop of the search and quality is the inner one.
/// That ordering is what makes a byte *minimum* solvable honestly: when a photo
/// comes out under the floor, the answer is more pixels, and more pixels means
/// more real image data rather than padding.
public enum DimensionLadder {

    /// How far below the source a ladder will reach when the spec states no
    /// minimum of its own.
    ///
    /// Not a detail. Several specs state a shape and a byte band and no pixel
    /// bounds at all, and a naive floor of one pixel makes the rungs span five
    /// orders of magnitude: a 4284 × 5712 source laddered 4284, 530, 65, 8, 1,
    /// leaving the entire useful range unsampled. New Zealand's 512 KB floor
    /// then fell into the gap and the fit was refused outright.
    ///
    /// The engine bisects between rungs when they bracket an answer, so this
    /// only has to be wide enough to contain one, not fine enough to hit it.
    public static let openEndedFloorFraction = 0.2

    /// The scale factors a fit may consider, relative to the aspect-correct
    /// crop of the source. `top` is 1.0 or less — never upscaling.
    public struct Bounds: Sendable {
        public let bottom: Double
        public let top: Double
    }

    public static func bounds(croppedSource: PixelSize, spec: UploadSpec) throws -> Bounds {
        let minWidth = spec.width?.lowerBound ?? 1
        let minHeight = spec.height?.lowerBound ?? 1

        // The honest stop. Enlarging invents detail, and a portal that checks
        // sharpness will reject it, so we refuse rather than pretend.
        if croppedSource.width < minWidth || croppedSource.height < minHeight {
            throw FitFailure.upscaleRequired(
                have: croppedSource.label,
                need: ByteFormat.size(minWidth, minHeight)
            )
        }

        let maxWidth = min(spec.width?.upperBound ?? croppedSource.width, croppedSource.width)
        let maxHeight = min(spec.height?.upperBound ?? croppedSource.height, croppedSource.height)

        let top = min(
            Double(maxWidth) / Double(croppedSource.width),
            Double(maxHeight) / Double(croppedSource.height),
            1.0
        )

        // When the spec states a real minimum, honour it exactly. When it
        // states none, stop somewhere useful rather than at a single pixel.
        let statedBottom = max(
            spec.width == nil ? 0 : Double(minWidth) / Double(croppedSource.width),
            spec.height == nil ? 0 : Double(minHeight) / Double(croppedSource.height)
        )
        let bottom = statedBottom > 0 ? statedBottom : min(top, openEndedFloorFraction)

        guard top >= bottom, top > 0 else {
            throw FitFailure.upscaleRequired(
                have: croppedSource.label,
                need: ByteFormat.size(minWidth, minHeight)
            )
        }
        return Bounds(bottom: bottom, top: top)
    }

    /// Never proposes a size larger than the source really has.
    public static func build(
        croppedSource: PixelSize,
        spec: UploadSpec,
        count: Int = Config.ladderSize
    ) throws -> [PixelSize] {
        let range = try bounds(croppedSource: croppedSource, spec: spec)

        var sizes: [PixelSize] = []
        let steps = max(1, count - 1)
        for i in 0...steps {
            // Geometric spacing: byte cost goes roughly with area, so even
            // steps in scale give even-ish steps in size.
            let t = Double(i) / Double(steps)
            let factor = range.top * pow(range.bottom / range.top, t)
            if let size = size(forFactor: factor, croppedSource: croppedSource, spec: spec) {
                sizes.append(size)
            }
        }

        var seen = Set<PixelSize>()
        return sizes
            .filter { seen.insert($0).inserted }
            .sorted { $0.pixels > $1.pixels }
    }

    /// Turns a scale factor into an exact size the spec would accept, or nil if
    /// no such size exists at that scale.
    public static func size(
        forFactor factor: Double,
        croppedSource source: PixelSize,
        spec: UploadSpec
    ) -> PixelSize? {
        let minWidth = spec.width?.lowerBound ?? 1
        let minHeight = spec.height?.lowerBound ?? 1
        let maxWidth = min(spec.width?.upperBound ?? source.width, source.width)
        let maxHeight = min(spec.height?.upperBound ?? source.height, source.height)

        var width = Int((Double(source.width) * factor).rounded())
        var height = Int((Double(source.height) * factor).rounded())

        switch spec.aspect {
        case .square:
            let side = min(width, height)
            width = side
            height = side
        case .ratio(let rw, let rh, _):
            // Derive height from width so the ratio is exact by construction
            // rather than by luck of rounding.
            height = Int((Double(width) * Double(rh) / Double(rw)).rounded())
        case .free:
            break
        }

        width = min(max(width, minWidth), maxWidth)
        height = min(max(height, minHeight), maxHeight)

        // Clamping can break the ratio; re-derive and give up if it still fails.
        if case .ratio(let rw, let rh, _) = spec.aspect {
            height = Int((Double(width) * Double(rh) / Double(rw)).rounded())
            if height > maxHeight {
                height = maxHeight
                width = Int((Double(height) * Double(rw) / Double(rh)).rounded())
            }
        }
        if case .square = spec.aspect {
            let side = min(width, height)
            width = side
            height = side
        }

        guard width >= minWidth, height >= minHeight,
              width <= maxWidth, height <= maxHeight,
              width <= source.width, height <= source.height,
              spec.aspect.admits(width: width, height: height)
        else { return nil }

        return PixelSize(width: width, height: height)
    }
}

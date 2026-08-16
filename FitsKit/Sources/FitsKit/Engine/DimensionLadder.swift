import Foundation

/// The sizes worth trying, largest first.
///
/// Dimensions are the outer loop of the search and quality is the inner one.
/// That ordering is what makes a byte *minimum* solvable honestly: when a photo
/// comes out under the floor, the answer is more pixels, and more pixels means
/// more real image data rather than padding.
public enum DimensionLadder {

    /// Never proposes a size larger than the source really has, so nothing here
    /// can lead to upscaling.
    public static func build(
        croppedSource: PixelSize,
        spec: UploadSpec,
        count: Int = Config.ladderSize
    ) throws -> [PixelSize] {
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

        // Scale factors relative to the cropped source.
        let topFactor = min(
            Double(maxWidth) / Double(croppedSource.width),
            Double(maxHeight) / Double(croppedSource.height),
            1.0
        )
        let bottomFactor = max(
            Double(minWidth) / Double(croppedSource.width),
            Double(minHeight) / Double(croppedSource.height),
            0.0
        )
        guard topFactor >= bottomFactor, topFactor > 0 else {
            throw FitFailure.upscaleRequired(
                have: croppedSource.label,
                need: ByteFormat.size(minWidth, minHeight)
            )
        }

        var sizes: [PixelSize] = []
        let steps = max(1, count - 1)
        for i in 0...steps {
            // Geometric spacing: the byte cost of an image goes roughly with
            // area, so even steps in scale give even-ish steps in size.
            let t = Double(i) / Double(steps)
            let factor = bottomFactor <= 0
                ? topFactor * pow(0.72, Double(i))
                : topFactor * pow(bottomFactor / topFactor, t)
            if let size = snap(
                factor: factor, source: croppedSource, spec: spec,
                minWidth: minWidth, minHeight: minHeight,
                maxWidth: maxWidth, maxHeight: maxHeight
            ) {
                sizes.append(size)
            }
        }

        // Largest first, no repeats.
        var seen = Set<PixelSize>()
        return sizes
            .filter { seen.insert($0).inserted }
            .sorted { $0.pixels > $1.pixels }
    }

    /// Turns a scale factor into an exact size the spec would accept.
    private static func snap(
        factor: Double,
        source: PixelSize,
        spec: UploadSpec,
        minWidth: Int, minHeight: Int,
        maxWidth: Int, maxHeight: Int
    ) -> PixelSize? {
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

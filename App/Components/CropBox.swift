import SwiftUI
import FitsKit

/// The photo with the crop rectangle over it: drag to move, pinch to resize.
///
/// The rectangle is locked to the spec's aspect ratio, so every position it can
/// reach is a legal one and the engine never has to correct it. For a spec that
/// states no shape there is nothing to lock, so the whole frame is shown with no
/// handles — inventing a crop where the form does not ask for one would be
/// making a decision on the user's behalf for no reason.
///
/// Why this exists at all: centre-cropping a portrait to square lands as a tight
/// head-and-shoulders frame that clips the top of the head. The file is correct
/// in every measurable way and it is the wrong part of the photograph, and no
/// measurement can catch that. See NOTES.md.
struct CropBox: View {
    let image: CGImage
    let imageSize: PixelSize
    let aspect: AspectRule
    @Binding var crop: CropRect

    @State private var dragStart: CropRect?
    @State private var pinchStart: CropRect?

    var body: some View {
        GeometryReader { geometry in
            let frame = fittedRect(in: geometry.size)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)

                if aspect.value != nil {
                    // Everything outside the crop, dimmed.
                    Canvas { context, size in
                        var outside = Path(CGRect(origin: .zero, size: size))
                        outside.addRect(viewRect(in: frame))
                        context.fill(outside, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
                    }
                    .allowsHitTesting(false)

                    CropFrame()
                        .frame(width: viewRect(in: frame).width, height: viewRect(in: frame).height)
                        .offset(x: viewRect(in: frame).minX, y: viewRect(in: frame).minY)
                        .gesture(dragGesture(in: frame))
                        .gesture(pinchGesture())
                        .accessibilityLabel("Crop area")
                        .accessibilityHint("Drag to move, pinch to resize")
                }
            }
        }
        .aspectRatio(
            CGFloat(imageSize.width) / CGFloat(max(imageSize.height, 1)),
            contentMode: .fit
        )
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }

    // MARK: - Geometry

    /// Where the image actually sits inside the view after aspect-fit.
    private func fittedRect(in container: CGSize) -> CGRect {
        let imageAspect = CGFloat(imageSize.width) / CGFloat(max(imageSize.height, 1))
        let containerAspect = container.width / max(container.height, 1)
        if imageAspect > containerAspect {
            let height = container.width / imageAspect
            return CGRect(x: 0, y: (container.height - height) / 2, width: container.width, height: height)
        }
        let width = container.height * imageAspect
        return CGRect(x: (container.width - width) / 2, y: 0, width: width, height: container.height)
    }

    private func viewRect(in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + crop.x * frame.width,
            y: frame.minY + crop.y * frame.height,
            width: crop.width * frame.width,
            height: crop.height * frame.height
        )
    }

    // MARK: - Gestures

    private func dragGesture(in frame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? crop
                if dragStart == nil { dragStart = start }
                let dx = value.translation.width / frame.width
                let dy = value.translation.height / frame.height
                crop = clamped(CropRect(
                    x: start.x + dx, y: start.y + dy,
                    width: start.width, height: start.height
                ))
            }
            .onEnded { _ in dragStart = nil }
    }

    private func pinchGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? crop
                if pinchStart == nil { pinchStart = start }
                let scale = max(0.2, min(4, value.magnification))
                // Grow about the centre, so pinching does not also shift the frame.
                let centreX = start.x + start.width / 2
                let centreY = start.y + start.height / 2
                var width = start.width / scale
                var height = start.height / scale
                width = min(width, 1)
                height = min(height, 1)
                crop = clamped(CropRect(
                    x: centreX - width / 2, y: centreY - height / 2,
                    width: width, height: height
                ))
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// Keeps the rectangle inside the photo and exactly on ratio.
    ///
    /// Both matter. A rect that leaves the frame would crop in blank space, and
    /// one that drifts off ratio by a percent still passes on screen and fails
    /// Canada's one-percent aspect check on the way out.
    private func clamped(_ rect: CropRect) -> CropRect {
        guard let wanted = aspect.value else { return .full }
        let imageAspect = Double(imageSize.width) / Double(max(imageSize.height, 1))
        // Normalised space is not square, so an on-ratio rect is only on ratio
        // once the image's own proportions are taken back out.
        let normalisedAspect = wanted / imageAspect

        var width = min(max(rect.width, 0.08), 1)
        var height = width / normalisedAspect
        if height > 1 {
            height = 1
            width = height * normalisedAspect
        }
        let x = min(max(rect.x, 0), 1 - width)
        let y = min(max(rect.y, 0), 1 - height)
        return CropRect(x: x, y: y, width: width, height: height)
    }
}

/// The rectangle itself: a light border with corner ticks, nothing decorative.
private struct CropFrame: View {
    var body: some View {
        ZStack {
            Rectangle().stroke(.white, lineWidth: 2)
            GeometryReader { geometry in
                let length = min(24, min(geometry.size.width, geometry.size.height) / 3)
                ForEach(Corner.allCases, id: \.self) { corner in
                    Path { path in
                        let point = corner.point(in: geometry.size)
                        path.move(to: CGPoint(x: point.x + corner.dx * length, y: point.y))
                        path.addLine(to: point)
                        path.addLine(to: CGPoint(x: point.x, y: point.y + corner.dy * length))
                    }
                    .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
            }
        }
        .contentShape(Rectangle())
    }

    private enum Corner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        func point(in size: CGSize) -> CGPoint {
            switch self {
            case .topLeading: CGPoint(x: 2, y: 2)
            case .topTrailing: CGPoint(x: size.width - 2, y: 2)
            case .bottomLeading: CGPoint(x: 2, y: size.height - 2)
            case .bottomTrailing: CGPoint(x: size.width - 2, y: size.height - 2)
            }
        }

        var dx: CGFloat {
            switch self {
            case .topLeading, .bottomLeading: 1
            case .topTrailing, .bottomTrailing: -1
            }
        }

        var dy: CGFloat {
            switch self {
            case .topLeading, .topTrailing: 1
            case .bottomLeading, .bottomTrailing: -1
            }
        }
    }
}

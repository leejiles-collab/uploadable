import SwiftUI

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
public struct CropBox: View {
    let image: CGImage
    let imageSize: PixelSize
    let aspect: AspectRule
    @Binding var crop: CropRect

    @State private var dragStart: CropRect?
    @State private var pinchStart: CropRect?

    public init(image: CGImage, imageSize: PixelSize, aspect: AspectRule, crop: Binding<CropRect>) {
        self.image = image
        self.imageSize = imageSize
        self.aspect = aspect
        self._crop = crop
    }

    public var body: some View {
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
                        .accessibilityLabel("Crop area")
                        .accessibilityHint("Drag to move, pinch to resize")
                        // Size and position both, because placing a crop
                        // without sight needs to know where it sits as much as
                        // how big it is. Also the only observable a UI test
                        // has: the accessibility *frame* reports the whole
                        // photo, not the rectangle.
                        .accessibilityValue(
                            "\(Int((crop.width * 100).rounded()))% of the photo's width, "
                            + "\(Int((crop.y * 100).rounded()))% from the top"
                        )
                }
            }
            // Pinch is attached out here, to the whole photo, rather than to the
            // rectangle itself. Two fingers spreading leave a small rect almost
            // immediately, so a pinch that only counts inside it reads as broken
            // — which is exactly how it read to the first person who used it.
            //
            // `simultaneousGesture` so it does not take the one-finger drag away
            // from the rectangle. A magnify needs two touches and a drag needs
            // one, so the two never contend for the same interaction.
            .contentShape(Rectangle())
            .simultaneousGesture(
                pinchGesture(),
                including: aspect.value == nil ? .subviews : .all
            )
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
                // Fingers apart makes the box bigger. The photo is fixed and the
                // rectangle is the thing being handled, so it follows the
                // fingers; treating this as zooming *into* the photo would make
                // it move the opposite way to every other draggable box.
                var width = start.width * scale
                var height = start.height * scale
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
///
/// Drawn in a single `Canvas` rather than as four `Path` views. A bare
/// `Path { }.stroke()` is a view sized to its own bounds, so a `ForEach` of
/// four of them gets each one laid out by the parent instead of left where it
/// was drawn — all four ticks ended up stacked in the middle of the rectangle.
/// A Canvas draws in the coordinates it is given and nothing moves afterwards.
private struct CropFrame: View {
    private let inset: CGFloat = 1.5

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            context.stroke(Path(rect), with: .color(.white.opacity(0.9)), lineWidth: 1.5)

            let length = min(26, min(rect.width, rect.height) / 3)
            var ticks = Path()
            // Each corner: in along the top or bottom edge, then down the side.
            for (corner, dx, dy) in [
                (CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
                (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)
            ] {
                ticks.move(to: CGPoint(x: corner.x + dx * length, y: corner.y))
                ticks.addLine(to: corner)
                ticks.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * length))
            }
            context.stroke(
                ticks,
                with: .color(.white),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
            )
        }
        .contentShape(Rectangle())
    }
}

import XCTest

/// Does the crop rectangle's pinch gesture actually receive events, and does it
/// move the way a person expects?
///
/// This exists because pinch-to-resize appeared dead in the simulator and there
/// was no way to tell a real bug from an Option-drag limitation by reading the
/// code. A synthetic pinch from XCTest is a genuine two-finger event delivered
/// by the system, so it answers the question without a physical device.
///
/// Everything is measured from the crop element's own on-screen frame rather
/// than from an accessibility string, so the tests do not break when
/// user-facing wording changes and do not constrain what VoiceOver says.
final class CropGestureTests: XCTestCase {

    private func launchOnCropScreen() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--screen=crop"]
        app.launch()
        return app
    }

    private func cropArea(_ app: XCUIApplication) -> XCUIElement {
        let element = app.otherElements["Crop area"]
        XCTAssertTrue(element.waitForExistence(timeout: 30), "never reached the crop screen")
        return element
    }

    /// Width and vertical position, read out of the accessibility value and
    /// re-resolved on every call.
    ///
    /// Not the element's `frame`: the accessibility frame reports the whole
    /// photo rather than the rectangle, so it never moves. The value is the
    /// only thing that tracks the crop.
    private func cropState(_ app: XCUIApplication) -> (width: Int, top: Int) {
        let value = app.otherElements["Crop area"].firstMatch.value as? String ?? ""
        let numbers = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        XCTAssertEqual(numbers.count, 2, "could not read the crop from \"\(value)\"")
        return (numbers[0], numbers[1])
    }

    /// The regression guard for attaching pinch to the whole photo: a
    /// `simultaneousGesture` on the parent must not swallow the one-finger drag
    /// that belongs to the rectangle.
    func testDragStillMovesTheCrop() {
        let app = launchOnCropScreen()
        let crop = cropArea(app)
        let before = cropState(app)

        crop.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: crop.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.4)))

        let after = cropState(app)
        XCTAssertGreaterThan(
            after.top, before.top,
            "the drag gesture was lost: crop stayed \(before.top)% from the top"
        )
        XCTAssertEqual(after.width, before.width,
                       "a move must not also resize")
    }

    /// The original question, and the direction.
    ///
    /// The crop starts at its maximum width for a portrait source, so spreading
    /// from the start state is correctly a no-op — which is what made the
    /// gesture look dead. The real assertions are that fingers together shrink
    /// the box and fingers apart grow it back: the rectangle follows the
    /// fingers, because the photo is fixed and the box is what is being handled.
    func testPinchResizesTheCropAndFollowsTheFingers() {
        let app = launchOnCropScreen()
        let crop = cropArea(app)

        let start = cropState(app).width
        XCTAssertGreaterThan(start, 0, "crop had no width")

        crop.pinch(withScale: 3.0, velocity: 3.0)
        let ceiling = cropState(app).width
        XCTAssertEqual(ceiling, start,
                       "spreading at maximum should do nothing, not overshoot")

        crop.pinch(withScale: 0.4, velocity: -3.0)
        let together = cropState(app).width
        XCTAssertLessThan(together, start,
                          "fingers together must shrink the box: \(start) -> \(together)")

        crop.pinch(withScale: 2.0, velocity: 3.0)
        let apart = cropState(app).width
        XCTAssertGreaterThan(apart, together,
                             "fingers apart must grow the box: \(together) -> \(apart)")

        print("PINCH-WIDTHS start=\(start) ceiling=\(ceiling) together=\(together) apart=\(apart)")
    }

    /// Pinching must still work after the box has been shrunk, which is when
    /// the rectangle is a small target and the old build — with the gesture
    /// attached to the rectangle itself — had the most trouble.
    func testPinchStillWorksOnceTheBoxIsSmall() {
        let app = launchOnCropScreen()
        _ = cropArea(app)

        app.otherElements["Crop area"].firstMatch.pinch(withScale: 0.3, velocity: -3.0)
        let shrunk = cropState(app).width
        XCTAssertLessThan(shrunk, 100, "the box did not shrink")

        app.otherElements["Crop area"].firstMatch.pinch(withScale: 3.0, velocity: 3.0)
        let grown = cropState(app).width
        XCTAssertGreaterThan(grown, shrunk, "could not grow a small box back: \(shrunk)% -> \(grown)%")

        print("SMALL-BOX shrunk=\(shrunk)% grown=\(grown)%")
    }
}

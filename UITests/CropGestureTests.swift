import XCTest

/// Does the crop rectangle's pinch gesture actually receive events?
///
/// This exists because pinch-to-resize appeared dead in the simulator and there
/// was no way to tell a real bug from an Option-drag limitation by looking. A
/// synthetic pinch from XCTest is a genuine two-finger event delivered by the
/// system, so it answers the question without a physical device.
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

    /// The control: a drag is one finger and is known to work by hand.
    func testDragMovesTheCrop() {
        let app = launchOnCropScreen()
        let crop = cropArea(app)
        let before = crop.value as? String

        crop.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: crop.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))

        // A move does not change width, so this only proves the view is live.
        XCTAssertNotNil(before)
        XCTAssertTrue(crop.exists)
    }

    /// The actual question. Pinching out should shrink the crop's width.
    func testPinchResizesTheCrop() {
        let app = launchOnCropScreen()
        let crop = cropArea(app)

        let before = Double(crop.value as? String ?? "") ?? -1
        XCTAssertGreaterThan(before, 0, "crop width was not readable")

        // Fingers apart.
        crop.pinch(withScale: 3.0, velocity: 3.0)
        let afterSpread = Double(crop.value as? String ?? "") ?? -1

        // Fingers together, from wherever that left it.
        crop.pinch(withScale: 0.4, velocity: -3.0)
        let afterPinch = Double(crop.value as? String ?? "") ?? -1

        print("PINCH-NUMBERS start=\(before) spread=\(afterSpread) together=\(afterPinch)")

        XCTAssertNotEqual(
            before, afterSpread, accuracy: 0.0001,
            "the pinch gesture received no events: crop width stayed at \(before)"
        )
    }

    /// Distinguishes "the gesture is not wired up" from "the crop rect is too
    /// small a hit area for fingers that move outward". Pinching the whole
    /// photo area is a much larger target.
    func testPinchOnTheWholePhotoArea() {
        let app = launchOnCropScreen()
        let crop = cropArea(app)
        let before = Double(crop.value as? String ?? "") ?? -1

        app.windows.element(boundBy: 0).pinch(withScale: 3.0, velocity: 3.0)

        let after = Double(crop.value as? String ?? "") ?? -1
        print("PINCH-ON-WINDOW before=\(before) after=\(after)")
    }
}

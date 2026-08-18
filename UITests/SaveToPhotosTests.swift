import XCTest

/// Exercises the real `PHPhotoLibrary.performChanges` callback, which nothing
/// else does.
///
/// The unit suite never touches Photos and the screenshot pipeline only ever
/// photographs the Done screen without pressing anything on it, so the block
/// that Photos invokes on `com.apple.PHPhotoLibrary.changes` had never once run
/// before a real person tapped Save to Photos on a real phone. It trapped
/// immediately.
///
/// Photo-library permission is granted ahead of time with
/// `xcrun simctl privacy <device> grant photos-add <bundle id>` (see
/// Tools/uitests.sh), because a permission alert would otherwise stall the tap
/// and hide the thing being tested behind a timeout.
final class SaveToPhotosTests: XCTestCase {

    func testSaveToPhotosCompletesWithoutTrapping() {
        let app = XCUIApplication()
        app.launchArguments = ["--screen=done", "--reset-exports"]
        app.launch()

        let button = app.buttons["Save to Photos"]
        XCTAssertTrue(button.waitForExistence(timeout: 40), "never reached the Done screen")
        button.tap()

        // Either outcome is a pass for the crash this guards: what must not
        // happen is the process dying inside the Photos change block.
        let saved = app.staticTexts["Saved to Photos."]
        let refused = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Couldn't save to Photos")
        ).firstMatch

        let landed = saved.waitForExistence(timeout: 30) || refused.exists

        // Checked before the outcome assertion, because this is the failure the
        // test exists for and it deserves the clearer message.
        XCTAssertEqual(app.state, .runningForeground,
                       "the app is no longer running: it trapped during the save")
        XCTAssertTrue(
            landed,
            "neither a success nor a failure message appeared. On screen: "
            + "\(app.staticTexts.allElementsBoundByIndex.map { $0.label })"
        )
    }
}

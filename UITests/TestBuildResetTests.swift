import XCTest

/// The reset affordance that makes TestFlight testing possible.
///
/// The export count survives reinstall on purpose, so without something
/// tappable the only way to clear it on a real device is a launch argument,
/// which means Xcode. `#if DEBUG` cannot provide it: Archive builds Release,
/// and the TestFlight binary is the same one the App Store ships.
///
/// So the gate is `BuildEnvironment.isTestBuild`, and this exercises the whole
/// path — spend the allowance, watch the meter hit zero, reset it, watch it come
/// back — rather than just checking that a button exists.
final class TestBuildResetTests: XCTestCase {

    func testTheMeterEmptiesAndTheResetRefillsIt() {
        let app = XCUIApplication()
        // Reaches the paywall by spending both free exports the way a person
        // would, which is what leaves the meter at zero.
        app.launchArguments = ["--screen=paywall", "--reset-exports"]
        app.launch()

        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 40), "never reached the paywall")
        close.tap()

        app.buttons["Fit another photo"].tap()

        let empty = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "0 free exports left")
        ).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 20),
                      "the test-build meter did not show an empty allowance")

        // The affordance itself: two seconds on the wordmark.
        app.staticTexts["Uploadable"].firstMatch.press(forDuration: 2.5)
        app.buttons["Reset"].tap()

        let refilled = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "2 free exports left")
        ).firstMatch
        XCTAssertTrue(refilled.waitForExistence(timeout: 20),
                      "the reset did not refill the meter")
    }
}

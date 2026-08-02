import XCTest

/// EdgeNoted is an LSUIElement (accessory) app: it has no regular windows at
/// rest, its panels are borderless NSPanels that XCUITest cannot query
/// reliably, and it must never trigger Automation permission prompts in CI.
/// The UI tests therefore verify a clean hermetic launch with fake
/// Notes/Reminders services and no real Apple Events.
final class EdgeNotedUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesWithFakeServices() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFakeServices", "YES"]
        app.launch()
        // The app must not crash on launch; accessory apps report a
        // background state, so only assert it is not "not running".
        XCTAssertNotEqual(app.state, .notRunning)
        XCTAssertEqual(app.state, .runningBackground)
    }
}

import XCTest

/// Verifies the app launches and attaches a screenshot of the first screen to the report.
/// `runsForEachTargetApplicationUIConfiguration` runs it once per UI configuration —
/// without a test plan, Xcode's four defaults (light/dark, portrait/landscape) — so the
/// report shows the list under all four without opening the simulator. A test plan with
/// locales or text sizes would add screenshots here without touching the test.
final class RickAndMortyUITestsLaunchTests: XCTestCase {
    override static var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        // Stubbed data, like the rest of the suite — otherwise the screenshot depends on
        // whether the API responds, and with what.
        app.launchArguments = [LaunchFlags.stubbedData]
        app.launch()

        XCTAssertTrue(
            app.buttons["character-1"].waitForExistence(timeout: 10),
            "The app launched but the list never appeared"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Character list"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

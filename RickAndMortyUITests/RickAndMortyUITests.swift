import XCTest

/// Same literal the app reads at launch (LaunchEnvironment.stubbedFlag). Defined once
/// for the whole UI target so it isn't scattered across every test, launch test included.
enum LaunchFlags {
    static let stubbedData = "-stubbed-data"
    // On top of the above, a pull-to-refresh fails (LaunchEnvironment.refreshFailsFlag)
    static let stubbedRefreshFails = "-stubbed-refresh-fails"
    // Largest accessibility text size, app-wide, without touching simulator settings —
    // the argument UIKit reads at launch.
    static let largestAccessibilityTextSize = [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
}

/// Real end-to-end user flows against the whole app.
///
/// Runs against in-memory stub data, not the live API — a UI test that depends on the
/// network turns red the day there's no coverage, the day the API returns 429 (any day,
/// for this project), or the day someone adds a character. None of those is an app
/// failure, and a test that fails without anyone breaking anything gets ignored, which
/// is the fastest way to lose a whole suite.
///
/// What this checks is what unit tests can't see: that the pieces are wired together.
/// The view model is fully covered in RickAndMortyTests; that tapping a cell opens the
/// right detail is not.
final class RickAndMortyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // Each test launches its own app instance — avoids storing it in an implicitly
    // unwrapped property that needs remembering to clear in tearDown.
    @MainActor
    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [LaunchFlags.stubbedData] + arguments
        app.launch()
        return app
    }

    @MainActor
    func testTheListLoadsAndShowsCharacters() throws {
        let app = launchApp()

        XCTAssertTrue(
            app.buttons["character-1"].waitForExistence(timeout: 5),
            "The first character never made it onto the screen"
        )
        XCTAssertTrue(app.buttons["character-2"].exists)
    }

    @MainActor
    func testTappingACharacterOpensItsDetail() throws {
        let app = launchApp()
        let cell = app.buttons["character-1"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))

        cell.tap()

        // The detail's name matches the tapped cell — proves value-based navigation
        // carries the right character, not just "a detail"
        XCTAssertTrue(
            app.navigationBars["Rick Sanchez"].waitForExistence(timeout: 5),
            "The detail did not open for the character that was tapped"
        )
        // And its episodes load and render: the "Episodes" header is also present during
        // the skeleton, so a row is what proves loading has finished
        XCTAssertTrue(app.staticTexts["Episodes"].exists)
        XCTAssertTrue(app.staticTexts["Episode 1"].waitForExistence(timeout: 5), "The episode list never loaded")
        XCTAssertTrue(app.staticTexts["Season 1 · Episode 1"].exists)
    }

    @MainActor
    func testScrollingToTheEndLoadsTheNextPage() throws {
        // The stub has 25 characters, paginated 20 at a time — the last 5 only exist if
        // scrolling near the end triggered the second page. End-to-end infinite scroll:
        // the cell appears, the view model requests, the grid grows.
        let app = launchApp()
        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))

        scroll(app, untilExists: app.buttons["character-25"])

        XCTAssertTrue(app.buttons["character-25"].exists, "The second page never made it onto the screen")
    }

    @MainActor
    func testComingBackFromTheDetailKeepsTheList() throws {
        // Coming back from the detail must not trigger another load: the list's .task
        // fires again on reappearance, so the view model only loads while idle. Scrolls
        // to the second page before entering because that's what makes it observable —
        // if coming back reloaded, the list would reset to page one and character 21
        // (only on page two) would vanish.
        let app = launchApp()
        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))
        let cell = app.buttons["character-21"]
        scroll(app, untilExists: cell)
        cell.tap()
        XCTAssertTrue(app.navigationBars["Supernova"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(
            app.buttons["character-21"].waitForExistence(timeout: 5),
            "Coming back from the detail lost the page the user had scrolled to"
        )
    }

    @MainActor
    func testSearchingNarrowsTheListAndClearingBringsItBack() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))

        let searchField = app.searchFields.firstMatch
        searchField.tap()
        searchField.typeText("Summer")

        // Summer Smith is character 3 — searching should leave only her and hide the rest
        XCTAssertTrue(app.buttons["character-3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["character-1"].exists)

        searchField.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testASearchWithNoMatchesShowsTheEmptyStateAndNotAnError() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))

        let searchField = app.searchFields.firstMatch
        searchField.tap()
        searchField.typeText("zzzzzzzz")

        // No results isn't a failure: the screen offers clearing the search, not
        // retrying. And it says "search", not "filters" — none were touched
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5))
        let clear = app.buttons["Clear search"]
        XCTAssertTrue(clear.exists)

        // And that button brings back the whole list
        clear.tap()
        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFilteringByStatusChangesTheList() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))

        app.navigationBars.buttons["Filters"].tap()
        let statusPicker = app.buttons["filter-status"]
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 5))
        statusPicker.tap()
        app.buttons["Dead"].tap()
        app.buttons["Done"].tap()

        // Rick is alive, so with the filter applied he can't still be in the list;
        // Bird Person, character 7, should be
        XCTAssertTrue(app.buttons["character-7"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["character-1"].exists)
    }

    @MainActor
    func testClearingTheFiltersBringsTheWholeListBack() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))

        // With nothing set, "Clear" does nothing and can't be tapped
        app.navigationBars.buttons["Filters"].tap()
        let clear = app.buttons["Clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertFalse(clear.isEnabled, "Clear must be disabled while no filter is active")

        // With a filter set it lights up, and tapping it brings the whole list back
        app.buttons["filter-status"].tap()
        app.buttons["Dead"].tap()
        XCTAssertTrue(clear.isEnabled)
        clear.tap()
        app.buttons["Done"].tap()

        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))
    }

    // MARK: - Dynamic Type

    // The three screens at the largest text size that exists. Checks that everything
    // stays on screen and tappable at that size: the cell, the detail it opens, and the
    // filter sheet's pickers.
    @MainActor
    func testTheScreensStayUsableAtTheLargestTextSize() throws {
        let app = launchApp(arguments: LaunchFlags.largestAccessibilityTextSize)

        let cell = app.buttons["character-1"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        XCTAssertTrue(cell.isHittable, "At the largest text size the first cell must still be reachable")

        cell.tap()
        XCTAssertTrue(app.navigationBars["Rick Sanchez"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["character-1"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Filters"].tap()
        let statusPicker = app.buttons["filter-status"]
        XCTAssertTrue(statusPicker.waitForExistence(timeout: 5))
        XCTAssertTrue(statusPicker.isHittable)
    }

    // MARK: - Failed refresh

    @MainActor
    func testAFailedRefreshKeepsTheListAndShowsANoticeThatCanBeDismissed() throws {
        let app = launchApp(arguments: [LaunchFlags.stubbedRefreshFails])
        let cell = app.buttons["character-1"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))

        // Pull the list down, like the user would
        let start = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = start.withOffset(CGVector(dx: 0, dy: 500))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)

        // The notice appears, says what happened and what it means, and the list stays
        let notice = app.buttons["refresh-failed"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "The refresh failure notice never appeared")
        XCTAssertTrue(notice.label.contains("No connection"))
        XCTAssertTrue(notice.label.contains("out of date"))
        XCTAssertTrue(app.buttons["character-1"].exists, "A failed refresh must not take the list away")

        // And it's dismissed by tapping it
        notice.tap()
        XCTAssertTrue(notice.waitForNonExistence(timeout: 3))
    }

    // MARK: - Helpers

    // Scrolls the grid until the requested cell exists, with a cap: the grid is lazy, so
    // a cell that hasn't been created yet doesn't exist for XCTest, and the only way to
    // reach it is scrolling like the user would. With 20 cells per page and 2 per row, 8
    // screens are plenty.
    @MainActor
    private func scroll(_ app: XCUIApplication, untilExists element: XCUIElement, maxSwipes: Int = 8) {
        for _ in 0..<maxSwipes {
            // A pause between gestures, so a page that was just requested has time to
            // render before the next one
            if element.waitForExistence(timeout: 1) { return }
            app.swipeUp()
        }
        _ = element.waitForExistence(timeout: 5)
    }
}

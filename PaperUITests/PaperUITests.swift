import XCTest

final class PaperUITests: XCTestCase {
    @MainActor
    func testNewTabPaletteAndHandbook() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES"]
        app.launch()

        let newTabSearch = app.textFields["paper.newTab.search"]
        XCTAssertTrue(newTabSearch.waitForExistence(timeout: 10))
        app.typeKey("l", modifierFlags: .command)
        let palette = app.textFields["paper.commandPalette.input"]
        XCTAssertTrue(palette.waitForExistence(timeout: 5))
        palette.typeText("Help\n")
        XCTAssertTrue(app.scrollViews["paper.handbook"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Getting Started"].exists)
    }

    @MainActor
    func testOnboardingCanBeSkipped() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "NO"]
        app.launch()
        let skip = app.buttons["Skip introduction"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.click()
        XCTAssertFalse(skip.exists)
        XCTAssertTrue(app.textFields["paper.newTab.search"].exists)
    }

    @MainActor
    func testOnboardingPracticeStaysLocal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "NO"]
        app.launch()
        app.typeKey("l", modifierFlags: .command)
        let next = app.buttons["Continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.click()
        let practice = app.textFields["paper.onboarding.practice"]
        XCTAssertTrue(practice.waitForExistence(timeout: 5))
        practice.typeText("cats\n")
        XCTAssertTrue(app.staticTexts["Try the tab commands. You can also use their keyboard shortcuts."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["paper.newTab.search"].exists)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        app.buttons["Try New tab, ⌘T"].click()
        app.buttons["Try Next tab, ⌃Tab"].click()
        app.buttons["Try Close tab, ⌘W"].click()
        XCTAssertTrue(app.buttons["Finish"].isEnabled)
        app.buttons["Finish"].click()
        let skip = app.buttons["Skip introduction"]
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: skip)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
    }

    @MainActor
    func testTabCommandsAndSearchFocus() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES"]
        app.launch()
        let search = app.textFields["paper.newTab.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.typeText("example.com\n")
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testKeyboardHandbookShortcut() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES"]
        app.launch()
        app.typeKey("/", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.scrollViews["paper.handbook"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHelpMenuOpensHandbook() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES"]
        app.launch()
        app.menuBars.menuBarItems["Help"].click()
        app.menuBars.menuItems["Paper Handbook"].click()
        XCTAssertTrue(app.scrollViews["paper.handbook"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHandbookReopensIntroduction() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES"]
        app.launch()
        app.menuBars.menuBarItems["Help"].click()
        app.menuBars.menuItems["Paper Handbook"].click()
        let replay = app.buttons["Replay the introduction"]
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        replay.click()
        XCTAssertTrue(app.buttons["Skip introduction"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testVisualSnapshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES"]
        app.launch()
        XCTAssertTrue(app.textFields["paper.newTab.search"].waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        let newTab = XCTAttachment(screenshot: window.screenshot())
        newTab.name = "Paper new tab"
        newTab.lifetime = .keepAlways
        add(newTab)

        app.menuBars.menuBarItems["Help"].click()
        app.menuBars.menuItems["Paper Handbook"].click()
        XCTAssertTrue(app.scrollViews["paper.handbook"].waitForExistence(timeout: 5))
        let handbook = XCTAttachment(screenshot: app.sheets.firstMatch.screenshot())
        handbook.name = "Paper handbook"
        handbook.lifetime = .keepAlways
        add(handbook)
    }

    @MainActor
    func testDarkAppearance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES",
                               "-paper.uiTest.dark"]
        app.launch()
        XCTAssertTrue(app.textFields["paper.newTab.search"].waitForExistence(timeout: 10))
        let snapshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        snapshot.name = "Paper new tab dark"
        snapshot.lifetime = .keepAlways
        add(snapshot)
        app.textFields["paper.newTab.search"].typeText("p")
    }
}

import XCTest

final class PaperUITests: XCTestCase {
    @MainActor
    func testPrivateTabAndPrivacyPanel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.activate()
        app.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["Paper · Private"].waitForExistence(timeout: 5))
        app.typeKey("l", modifierFlags: .command)
        let palette = app.textFields["paper.commandPalette.input"]
        XCTAssertTrue(palette.waitForExistence(timeout: 5))
        palette.typeText("Privacy\n")
        XCTAssertTrue(app.staticTexts["Private"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Private Tab"].exists)
        let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        capture.name = "Phase 2B private privacy panel"
        capture.lifetime = .keepAlways
        add(capture)
    }

    @MainActor
    func testNewTabPaletteAndHandbook() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.activate()

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
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "NO", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.activate()
        let skip = app.buttons["Skip introduction"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        let introduction = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        introduction.name = "Paper typography onboarding"
        introduction.lifetime = .keepAlways
        add(introduction)
        skip.click()
        XCTAssertFalse(skip.exists)
        XCTAssertTrue(app.textFields["paper.newTab.search"].exists)
    }

    @MainActor
    func testOnboardingPracticeStaysLocal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "NO", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.activate()
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
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.activate()
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
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.activate()
        app.typeKey("/", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.scrollViews["paper.handbook"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHelpMenuOpensHandbook() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.activate()
        app.menuBars.menuBarItems["Help"].click()
        app.menuBars.menuItems["Paper Handbook"].click()
        XCTAssertTrue(app.scrollViews["paper.handbook"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHandbookReopensIntroduction() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.activate()
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
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES", "-ApplePersistenceIgnoreState", "YES",
                               "-paper.uiTest.light"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.textFields["paper.newTab.search"].waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        let newTab = XCTAttachment(screenshot: window.screenshot())
        newTab.name = "Paper new tab focused empty light"
        newTab.lifetime = .keepAlways
        add(newTab)
        app.textFields["paper.newTab.search"].typeText("paper notes")
        let typing = XCTAttachment(screenshot: window.screenshot())
        typing.name = "Paper new tab focused typing light"
        typing.lifetime = .keepAlways
        add(typing)

        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(app.textFields["paper.commandPalette.input"].waitForExistence(timeout: 5))
        let palette = XCTAttachment(screenshot: window.screenshot())
        palette.name = "Paper typography command palette"
        palette.lifetime = .keepAlways
        add(palette)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        app.menuBars.menuBarItems["Help"].click()
        app.menuBars.menuItems["Paper Handbook"].click()
        XCTAssertTrue(app.scrollViews["paper.handbook"].waitForExistence(timeout: 5))
        let handbook = XCTAttachment(screenshot: app.sheets.firstMatch.screenshot())
        handbook.name = "Paper handbook"
        handbook.lifetime = .keepAlways
        add(handbook)
    }

    @MainActor
    func testSettingsTypographySnapshot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.textFields["paper.newTab.search"].waitForExistence(timeout: 10))
        app.typeKey(",", modifierFlags: .command)
        for _ in 0..<20 where app.windows.count < 2 { Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertGreaterThanOrEqual(app.windows.count, 2)
        let settingsWindow = app.windows["Paper Settings"]
        XCTAssertTrue(app.sliders["paper.settings.newTabTransparency"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["paper.settings.newTabTint"].exists)
        XCTAssertTrue(app.sliders["paper.settings.newTabBlur"].exists)
        let settings = XCTAttachment(screenshot: settingsWindow.exists
                                     ? settingsWindow.screenshot() : app.screenshot())
        settings.name = "Paper typography settings"
        settings.lifetime = .keepAlways
        add(settings)
    }

    @MainActor
    func testDarkAppearance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES", "-ApplePersistenceIgnoreState", "YES",
                               "-paper.uiTest.dark"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.textFields["paper.newTab.search"].waitForExistence(timeout: 10))
        let snapshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        snapshot.name = "Paper new tab focused empty dark"
        snapshot.lifetime = .keepAlways
        add(snapshot)
        app.textFields["paper.newTab.search"].typeText("paper notes")
        let typing = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        typing.name = "Paper new tab focused typing dark"
        typing.lifetime = .keepAlways
        add(typing)
        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(app.textFields["paper.commandPalette.input"].waitForExistence(timeout: 5))
        let palette = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        palette.name = "Paper typography command palette dark"
        palette.lifetime = .keepAlways
        add(palette)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        app.menuBars.menuBarItems["Help"].click()
        app.menuBars.menuItems["Paper Handbook"].click()
        XCTAssertTrue(app.scrollViews["paper.handbook"].waitForExistence(timeout: 5))
        let handbook = XCTAttachment(screenshot: app.sheets.firstMatch.screenshot())
        handbook.name = "Paper typography handbook dark"
        handbook.lifetime = .keepAlways
        add(handbook)
    }

    @MainActor
    func testTabOverviewShortcutSearchAndDismissal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.textFields["paper.newTab.search"].waitForExistence(timeout: 10))
        app.typeKey("t", modifierFlags: .command)
        app.typeKey("\\", modifierFlags: [.command, .shift])
        let search = app.textFields["paper.overview.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "Paper tab overview"
        shot.lifetime = .keepAlways
        add(shot)
        search.typeText("not-a-tab")
        XCTAssertTrue(app.staticTexts["No matching tabs"].waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertFalse(search.exists)
        XCTAssertTrue(app.textFields["paper.newTab.search"].exists)
        app.typeKey("\\", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.textFields["paper.overview.search"].waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertFalse(app.textFields["paper.overview.search"].exists)
    }

    @MainActor
    func testPaletteActionOpensOverview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.textFields["paper.newTab.search"].waitForExistence(timeout: 10))
        app.typeKey("l", modifierFlags: .command)
        let palette = app.textFields["paper.commandPalette.input"]
        XCTAssertTrue(palette.waitForExistence(timeout: 5))
        palette.typeText("overview\n")
        XCTAssertTrue(app.textFields["paper.overview.search"].waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertFalse(app.textFields["paper.overview.search"].exists)
    }
}

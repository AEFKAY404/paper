import XCTest

/// Opt-in, network-dependent visual smoke test. Create
/// /private/tmp/paper-run-real-sites before running this test target.
final class ContentBlockerRealSiteUITests: XCTestCase {
    @MainActor
    func testSignedOutSitesWithBlocker() throws {
        guard FileManager.default.fileExists(atPath: "/private/tmp/paper-run-real-sites") else {
            throw XCTSkip("Live-site visual smoke is opt-in")
        }
        let sites: [(String, String)] = [
            ("Google Search", "https://www.google.com/search?q=paper+browser"),
            ("YouTube", "https://www.youtube.com/"),
            ("Reddit", "https://www.reddit.com/"),
            ("The Guardian", "https://www.theguardian.com/international"),
            ("Wikipedia", "https://en.wikipedia.org/wiki/WebKit"),
            ("The Verge", "https://www.theverge.com/")
        ]
        let app = XCUIApplication()
        app.launchArguments = ["-paper.restoreSession", "NO", "-paper.onboarding.completed", "YES",
                               "-ApplePersistenceIgnoreState", "YES", "-paper.blocker.enabled", "YES"]
        app.launch()
        app.activate()
        // Allow the first-run bundled compilation to attach before navigation.
        Thread.sleep(forTimeInterval: 3)
        for (index, site) in sites.enumerated() {
            if index > 0 { app.typeKey("t", modifierFlags: .command) }
            let field = app.textFields["paper.newTab.search"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            field.typeText(site.1 + "\n")
            XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 7)
            let capture = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            capture.name = "Paper blocker site — " + site.0
            capture.lifetime = .keepAlways
            add(capture)
        }
    }
}

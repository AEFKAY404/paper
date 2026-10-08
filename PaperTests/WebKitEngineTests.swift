import AppKit
import Foundation
import Testing
import WebKit
@testable import Paper

@MainActor
struct WebKitEngineTests {
    @Test func browserIdentityFormattingAndPolicy() {
        let identity = BrowserIdentity(applicationVersion: "1.0", safariVersion: "27.2")
        let base = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Paper/1.0"
        #expect(identity.applicationToken == "Paper/1.0")
        #expect(identity.makeSafariCompatibleUserAgent(from: base) ==
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.2 Safari/605.1.15 Paper/1.0")
        #expect(identity.makeSafariCompatibleUserAgent(from: "Mozilla/5.0 Chrome/154") == nil)
        #expect(!identity.compatibilityPolicy.rules.contains { $0.userAgentOverride?.contains("Chrome/") == true })
        #expect(SiteCompatibilityPolicy.matches(host: "www.example.com", domain: "example.com"))
        #expect(!SiteCompatibilityPolicy.matches(host: "notexample.com", domain: "example.com"))
        let policy = SiteCompatibilityPolicy(rules: [
            .init(domain: "example.com", userAgentOverride: "Example/Test", notes: "test fixture")
        ])
        #expect(policy.resolve(URL(string: "https://sub.example.com/path")!)?.userAgentOverride == "Example/Test")
        #expect(policy.resolve(URL(string: "https://unrelated.org")!) == nil)
    }

    @Test func sessionsApplySameDesktopIdentityBeforeNavigation() async throws {
        let first = WebKitSession(websiteDataStore: .nonPersistent())
        let second = WebKitSession(websiteDataStore: .nonPersistent())
        defer { first.close(); second.close() }
        let target = try #require(URL(string: "data:text/html,%3Ctitle%3EIdentity%3C/title%3E"))
        first.load(target)
        second.load(target)
        for _ in 0..<100 where first.webView.title != "Identity" || second.webView.title != "Identity" {
            try await Task.sleep(for: .milliseconds(50))
        }
        let ua1 = try #require(first.webView.customUserAgent)
        let ua2 = try #require(second.webView.customUserAgent)
        #expect(ua1 == ua2)
        #expect(ua1.contains("Version/"))
        #expect(ua1.contains("Safari/"))
        #expect(ua1.contains("Paper/1.0"))
        #expect(!ua1.contains("Chrome/"))
        #expect(try await first.webView.evaluateJavaScript("navigator.userAgent") as? String == ua1)
        #expect(first.webView.configuration.defaultWebpagePreferences.preferredContentMode == .desktop)
    }

    @Test func restoredTabsKeepOrderAndActiveURL() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SessionStore(defaults: defaults)
        let original = BrowserController(engine: WebKitEngine(), store: store)
        original.start(restorePreviousSession: false)
        let firstID = try #require(original.activeTabID)
        original.navigate("https://example.com")
        original.newTab(url: URL(string: "https://swift.org"))
        original.activate(firstID)
        original.shutdown()

        let restored = BrowserController(engine: WebKitEngine(), store: store)
        restored.start()
        #expect(restored.tabs.map(\.url?.host) == ["example.com", "swift.org"])
        #expect(restored.activeTabID == restored.tabs.first?.id)
        #expect(restored.tabs.count == 2)
        restored.shutdown()
    }

    @Test func tabSwitchKeepsWebViewAndJavaScriptState() async throws {
        let engine = WebKitEngine()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let controller = BrowserController(engine: engine, store: SessionStore(defaults: defaults))
        controller.start(restorePreviousSession: false)
        let firstID = try #require(controller.activeTabID)
        let first = try #require(controller.activeSession as? WebKitSession)
        first.webView.loadHTMLString("<title>First Tab</title><script>window.paperTabState=17</script>", baseURL: nil)
        for _ in 0..<100 where first.webView.title != "First Tab" {
            try await Task.sleep(for: .milliseconds(50))
        }
        let secondID = controller.newTab()
        let second = try #require(controller.activeSession as? WebKitSession)
        #expect(first !== second)
        controller.activate(firstID)
        #expect((controller.activeSession as? WebKitSession) === first)
        #expect((try await first.webView.evaluateJavaScript("window.paperTabState") as? Int) == 17)
        controller.closeTab(secondID)
        #expect(controller.tabs.count == 1)
        controller.shutdown()
    }

    @Test func backAndForwardNavigation() async throws {
        let session = WebKitSession()
        defer { session.close() }
        session.load(try #require(URL(string: "data:text/html,%3Ctitle%3EFirst%3C/title%3E")))
        for _ in 0..<100 where session.webView.title != "First" {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(session.webView.title == "First")
        session.load(try #require(URL(string: "data:text/html,%3Ctitle%3ESecond%3C/title%3E")))
        for _ in 0..<100 where session.webView.title != "Second" {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(session.webView.title == "Second")
        #expect(session.webView.canGoBack)
        session.goBack()
        for _ in 0..<100 where session.webView.title != "First" {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(session.webView.title == "First")
        #expect(session.webView.canGoForward)
    }

    @Test func localHTMLAndJavaScript() async throws {
        let session = WebKitSession()
        defer { session.close() }
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/browser-fixture.html")
        let html = try String(contentsOf: fixture, encoding: .utf8)
        session.webView.loadHTMLString(html, baseURL: fixture.deletingLastPathComponent())
        for _ in 0..<100 where session.webView.title != "Paper Local Fixture" {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(session.webView.title == "Paper Local Fixture")
        let ready = try await session.webView.evaluateJavaScript("window.paperFixtureReady") as? Bool
        #expect(ready == true)
        let count = try await session.webView.evaluateJavaScript("document.querySelector('#counter').click(); document.querySelector('#counter').textContent") as? String
        #expect(count == "1")
    }

    @Test func detectsOnlyOpaqueRootOrBodyBackground() async throws {
        let session = WebKitSession(websiteDataStore: .nonPersistent())
        defer { session.close() }
        var latest: NSColor?
        var updates = 0
        session.onEvent = { event in
            if case .surfaceColorChanged(let color) = event {
                latest = color
                updates += 1
            }
        }

        session.webView.loadHTMLString("<html style='background: rgb(18, 52, 86)'><body style='background: white'>Root</body></html>", baseURL: nil)
        for _ in 0..<100 where updates == 0 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(try #require(latest?.usingColorSpace(.deviceRGB)?.redComponent) < 0.08)
        #expect(try #require(latest?.usingColorSpace(.deviceRGB)?.greenComponent) > 0.19)

        updates = 0
        session.webView.loadHTMLString("<html><body style='background: rgb(220, 30, 40)'>Body</body></html>", baseURL: nil)
        for _ in 0..<100 where updates == 0 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(try #require(latest?.usingColorSpace(.deviceRGB)?.redComponent) > 0.85)

        updates = 0
        session.webView.loadHTMLString("<html><body style='background: linear-gradient(red, blue)'>Gradient</body></html>", baseURL: nil)
        for _ in 0..<100 where updates == 0 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(latest == nil)
    }

    @Test func realHTTPSPage() async throws {
        let session = WebKitSession()
        defer { session.close() }
        var errors: [String] = []
        session.onEvent = { event in
            if case .navigationFailed(let message) = event { errors.append(message) }
        }
        let url = try #require(URL(string: "https://example.com"))
        session.load(url)
        for _ in 0..<150 where session.webView.title?.isEmpty != false && errors.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(errors.isEmpty, "Navigation errors: \(errors)")
        #expect(session.webView.url?.host == "example.com")
        #expect(session.webView.title?.isEmpty == false)
    }

    @Test func visibleWebViewProducesStaticSnapshot() async throws {
        let session = WebKitSession()
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = session.webView
        window.orderFront(nil)
        defer { session.close(); window.close() }
        let url = try #require(URL(string: "data:text/html,%3Ctitle%3ESnapshot%3C/title%3E%3Ch1%3EPaper%3C/h1%3E"))
        session.load(url)
        for _ in 0..<100 where session.webView.title != "Snapshot" || session.webView.isLoading {
            try await Task.sleep(for: .milliseconds(50))
        }
        let start = CFAbsoluteTimeGetCurrent()
        let image = await session.snapshot(maxWidth: 320)
        let milliseconds = (CFAbsoluteTimeGetCurrent() - start) * 1_000
        print("PAPER_BENCH real_snapshot_ms=\(String(format: "%.2f", milliseconds)) width=\(image?.size.width ?? 0)")
        let data = try JSONSerialization.data(withJSONObject: ["snapshotMs": milliseconds,
                                                            "width": image?.size.width ?? 0,
                                                            "height": image?.size.height ?? 0],
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("paper-phase1b-webkit-snapshot.json"))
        #expect(image != nil)
        #expect((image?.size.width ?? 0) <= 360)
    }
}

import Darwin
import Foundation
import Testing
import WebKit
@testable import Paper

@MainActor
struct PrivacyTests {
    @Test func bundledPublicSuffixRulesIdentifyHostedSites() {
        let domains = SiteIdentity.shared
        #expect(domains.domain(forHost: "news.example.co.uk") == "example.co.uk")
        #expect(domains.domain(forHost: "shop.example.com") == "example.com")
        #expect(domains.domain(forHost: "one.github.io") == "one.github.io")
        #expect(domains.domain(forHost: "two.github.io") == "two.github.io")
        #expect(domains.domain(forHost: "127.0.0.1") == "127.0.0.1")
    }

    @Test func privateTabsUseTemporarySharedStorageAndNeverRestore() async throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let engine = WebKitEngine(startBlocker: false)
        let browser = BrowserController(engine: engine, store: SessionStore(defaults: defaults))
        browser.start(restorePreviousSession: false)
        let standard = try #require(browser.activeSession as? WebKitSession)
        #expect(standard.webView.configuration.websiteDataStore.isPersistent)
        let normalID = try #require(browser.activeTabID)
        browser.navigate("https://example.com")
        let secondNormalID = browser.newTab(url: URL(string: "https://swift.org"))
        let firstPrivateID = browser.newTab(url: URL(string: "https://private.example"), privacyMode: .private)
        let firstPrivate = try #require(browser.activeSession as? WebKitSession)
        #expect(!firstPrivate.webView.configuration.websiteDataStore.isPersistent)
        #expect(firstPrivate.webView.configuration.websiteDataStore !== standard.webView.configuration.websiteDataStore)
        let ephemeralCookie = try #require(HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "private-session", .value: "one"]))
        await set(ephemeralCookie, in: firstPrivate.webView.configuration.websiteDataStore)
        let secondPrivateID = browser.newTab(privacyMode: .private)
        let secondPrivate = try #require(browser.activeSession as? WebKitSession)
        #expect(firstPrivate.webView.configuration.websiteDataStore === secondPrivate.webView.configuration.websiteDataStore)
        browser.save()
        #expect(browser.activeTab?.privacyMode == .private)
        #expect(SessionStore(defaults: defaults).load()?.urls.map { $0?.host } == ["example.com", "swift.org"])
        #expect(SessionStore(defaults: defaults).load()?.activeIndex == 1)
        browser.closeTab(firstPrivateID)
        browser.closeTab(secondPrivateID)
        let newPrivateID = browser.newTab(privacyMode: .private)
        let newPrivate = try #require(browser.activeSession as? WebKitSession)
        #expect(newPrivate.webView.configuration.websiteDataStore !== firstPrivate.webView.configuration.websiteDataStore)
        #expect(await cookieNames(in: newPrivate.webView.configuration.websiteDataStore).isEmpty)
        browser.closeTab(newPrivateID)
        #expect(browser.activeTabID == secondNormalID)
        #expect(browser.tabs.first?.id == normalID)
        browser.shutdown()
        let restored = BrowserController(engine: WebKitEngine(startBlocker: false), store: SessionStore(defaults: defaults))
        restored.start()
        #expect(restored.tabs.count == 2)
        #expect(restored.activeTab?.privacyMode == .standard)
        #expect(restored.activeTab?.url?.host == "swift.org")
        restored.shutdown()
    }

    @Test func cookiesAreIsolatedAndSiteClearIsScoped() async throws {
        let normal = WKWebsiteDataStore.nonPersistent()
        let privateStore = WKWebsiteDataStore.nonPersistent()
        let other = WKWebsiteDataStore.nonPersistent()
        let normalCookie = try #require(HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "normal", .value: "one"]))
        let privateCookie = try #require(HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "private", .value: "two"]))
        let unrelatedCookie = try #require(HTTPCookie(properties: [.domain: "other.test", .path: "/", .name: "other", .value: "three"]))
        await set(normalCookie, in: normal)
        await set(privateCookie, in: privateStore)
        await set(unrelatedCookie, in: normal)
        #expect(await cookieNames(in: normal) == ["normal", "other"])
        #expect(await cookieNames(in: privateStore) == ["private"])
        #expect(await cookieNames(in: other).isEmpty)
        await SiteDataManager(store: normal).clear(site: "example.com")
        #expect(await cookieNames(in: normal) == ["other"])
        #expect(await cookieNames(in: privateStore) == ["private"])
    }

    @Test func permissionDecisionsPersistAndRevoke() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = SitePermissionStore(defaults: defaults)
        store.set(.block, for: .camera, site: "https://news.example.co.uk")
        #expect(store.choice(.camera, for: "https://news.example.co.uk") == .block)
        #expect(store.choice(.camera, for: "https://shop.example.co.uk") == .ask)
        let reloaded = SitePermissionStore(defaults: defaults)
        #expect(reloaded.choice(.camera, for: "https://news.example.co.uk") == .block)
        reloaded.revoke(site: "https://news.example.co.uk")
        #expect(SitePermissionStore(defaults: defaults).choice(.camera, for: "https://news.example.co.uk") == .ask)
    }

    @Test func privatePermissionsIgnoreRememberedAllow() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = SitePermissionStore(defaults: defaults)
        store.set(.allow, for: .camera, site: "https://example.com")
        var standardDecision: Bool?
        store.decide([.camera], site: "https://example.com", privateTab: false, window: nil) { standardDecision = $0 }
        #expect(standardDecision == true)
        var privateDecision: Bool?
        store.decide([.camera], site: "https://example.com", privateTab: true, window: nil) { privateDecision = $0 }
        #expect(privateDecision == false)
        store.set(.block, for: .microphone, site: "https://example.com")
        var combinedDecision: Bool?
        store.decide([.camera, .microphone], site: "https://example.com", privateTab: false, window: nil) { combinedDecision = $0 }
        #expect(combinedDecision == false)
    }

    @Test func localStorageIsolatedBetweenNormalAndPrivateStores() async throws {
        let normal = WebKitSession(websiteDataStore: .default())
        let privateSession = WebKitSession(websiteDataStore: .nonPersistent(), privacyMode: .private)
        defer { normal.close(); privateSession.close() }
        let base = try #require(URL(string: "https://paper-storage-fixture.test/"))
        let key = "paper-\(UUID().uuidString)"
        normal.webView.loadHTMLString("<title>Normal storage</title>", baseURL: base)
        privateSession.webView.loadHTMLString("<title>Private storage</title>", baseURL: base)
        for _ in 0..<100 where normal.webView.isLoading || privateSession.webView.isLoading {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await normal.webView.evaluateJavaScript("localStorage.setItem('\(key)', 'normal')")
        let privateValue = try await privateSession.webView.evaluateJavaScript("localStorage.getItem('\(key)')")
        #expect(privateValue is NSNull)
        try await privateSession.webView.evaluateJavaScript("localStorage.setItem('\(key)', 'private')")
        #expect(try await normal.webView.evaluateJavaScript("localStorage.getItem('\(key)')") as? String == "normal")
        try await normal.webView.evaluateJavaScript("localStorage.removeItem('\(key)')")
    }

    @Test func dataSelectionKeepsCategoriesSeparate() {
        let selection = BrowsingDataSelection(cookies: false, localStorage: false,
                                              caches: true, otherWebsiteData: false)
        #expect(selection.types.contains(WKWebsiteDataTypeDiskCache))
        #expect(!selection.types.contains(WKWebsiteDataTypeCookies))
        #expect(!selection.types.contains(WKWebsiteDataTypeLocalStorage))
        #expect(TabPrivacyMode.private.savedDownloadNotice?.contains("remain on disk") == true)
        #expect(TabPrivacyMode.standard.savedDownloadNotice == nil)
    }

    @Test func globalClearOnlyAffectsSelectedStore() async throws {
        let standard = WKWebsiteDataStore.nonPersistent()
        let privateStore = WKWebsiteDataStore.nonPersistent()
        let cookie = try #require(HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "token", .value: "one"]))
        await set(cookie, in: standard)
        await set(cookie, in: privateStore)
        await SiteDataManager(store: standard).clearAll(BrowsingDataSelection(
            cookies: true, localStorage: false, caches: false, otherWebsiteData: false))
        #expect(await cookieNames(in: standard).isEmpty)
        #expect(await cookieNames(in: privateStore) == ["token"])
    }

    @Test func siteExceptionsPersistByRegistrableDomain() throws {
        let site = "phase2b-\(UUID().uuidString.lowercased()).co.uk"
        let domain = try #require(SiteIdentity.shared.domain(forHost: site))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("paper-privacy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ContentBlockerEngine(directory: directory)
        first.setDisabled(true, forDomain: "news." + domain)
        defer { first.setDisabled(false, forDomain: domain) }
        #expect(first.policy.disabledForDomains.contains(domain))
        let second = ContentBlockerEngine(directory: directory)
        #expect(second.policy.disabledForDomains.contains(domain))
    }

    @Test func privateCreationAndLocalRenderSample() async throws {
        var samples: [[String: Any]] = []
        for count in [1, 5, 10, 20] {
            for mode in [TabPrivacyMode.standard, .private] {
                let store: WKWebsiteDataStore = mode == .private ? .nonPersistent() : .default()
                let beforeRSS = residentBytes()
                let start = CFAbsoluteTimeGetCurrent()
                let sessions = (0..<count).map { _ in WebKitSession(websiteDataStore: store, privacyMode: mode) }
                let createMs = (CFAbsoluteTimeGetCurrent() - start) * 1_000
                let loadStart = CFAbsoluteTimeGetCurrent()
                for (index, session) in sessions.enumerated() {
                    session.webView.loadHTMLString("<title>Privacy fixture \(index)</title>", baseURL: nil)
                }
                for _ in 0..<120 where sessions.contains(where: { $0.webView.title == nil || $0.webView.isLoading }) {
                    try await Task.sleep(for: .milliseconds(25))
                }
                let loadMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1_000
                let rssDelta = Int64(residentBytes()) - Int64(beforeRSS)
                samples.append(["mode": mode.rawValue, "tabs": count, "createMs": createMs,
                                "localLoadMs": loadMs, "appRSSDeltaBytes": rssDelta])
                print("PAPER_PRIVACY_BENCH mode=\(mode.rawValue) tabs=\(count) create_ms=\(String(format: "%.1f", createMs)) local_load_ms=\(String(format: "%.1f", loadMs)) app_rss_delta_bytes=\(rssDelta)")
                #expect(sessions.allSatisfy { $0.webView.title != nil })
                sessions.forEach { $0.close() }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("paper-phase2b-benchmark.json"))
    }

    private func set(_ cookie: HTTPCookie, in store: WKWebsiteDataStore) async {
        await withCheckedContinuation { continuation in
            store.httpCookieStore.setCookie(cookie) { continuation.resume() }
        }
    }

    private func cookieNames(in store: WKWebsiteDataStore) async -> [String] {
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        return cookies.map(\.name).sorted()
    }

    private func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
}

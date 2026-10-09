import Foundation
import Testing
import WebKit
@testable import Paper

@MainActor
private final class FixtureSchemeHandler: NSObject, WKURLSchemeHandler {
    var requestedHosts: [String] = []
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let url = urlSchemeTask.request.url!
        requestedHosts.append(url.host ?? "")
        let body = Data("window.\(url.host == "tracker.test" ? "trackerLoaded" : "firstPartyLoaded") = true;".utf8)
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: "text/javascript", expectedContentLength: body.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(body)
        urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}

@MainActor
private final class CosmeticCountHandler: NSObject, WKScriptMessageHandler {
    var count: Int?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        count = (message.body as? NSNumber)?.intValue
    }
}

@MainActor
@Suite(.serialized)
struct ContentBlockerTests {
    @Test func parserClassifiesAndDeduplicatesRules() throws {
        let parsed = FilterParser.parse("""
        ! comment
        ||ads.example.com^$third-party,script,image
        ||ads.example.com^$third-party,script,image
        ||analytics.example.org^$xmlhttprequest,domain=news.example
        @@||needed.example.org^
        ||redirect.example.org^$redirect=noop.js
        ##.ad
        news.example##.sponsored
        example.com#?#div:has(.ad)
        """)
        #expect(parsed.network.count == 2)
        #expect(parsed.cosmetic.count == 2)
        #expect(parsed.duplicateCount == 1)
        #expect(parsed.networkExceptions.count == 1)
        #expect(parsed.unsupportedByReason["unapplied network exception"] == 1)
        #expect(parsed.unsupportedByReason["procedural or scriptlet cosmetic"] == 1)
        #expect(parsed.unsupportedByReason["redirect"] == 1)
        let json = try RuleCompiler.json(for: parsed.network)
        let entries = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        #expect(entries.count == 2)
        let trigger = try #require(entries.compactMap { $0["trigger"] as? [String: Any] }
            .first { ($0["resource-type"] as? [String]) == ["image", "script"] })
        #expect(trigger["load-type"] as? [String] == ["third-party"])
        #expect(trigger["resource-type"] as? [String] == ["image", "script"])
    }

    @Test func policyBypassesExactDomainAndSubdomains() {
        let policy = BlockerPolicy(enabled: true, disabledForDomains: ["example.com"])
        #expect(!policy.allowsBlocking(URL(string: "https://example.com")))
        #expect(!policy.allowsBlocking(URL(string: "https://news.example.com")))
        #expect(policy.allowsBlocking(URL(string: "https://notexample.com")))
    }

    @Test func webKitCompilesSupportedRule() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try #require(WKContentRuleListStore(url: directory))
        let rule = try #require(FilterParser.networkRule("||ads.example.com^$script,third-party"))
        let list = try #require(try await store.compileContentRuleList(forIdentifier: "paper-test", encodedContentRuleList: RuleCompiler.json(for: [rule])))
        #expect(list.identifier == "paper-test")
        let cached = try await store.contentRuleList(forIdentifier: "paper-test")
        #expect(cached?.identifier == list.identifier)
    }

    @Test func cosmeticScriptContainsSelectorsWithoutRemoteCode() throws {
        let rules = [try #require(FilterParser.cosmeticRule(domains: "", selector: ".ad")),
                     try #require(FilterParser.cosmeticRule(domains: "news.example", selector: ".sponsored"))]
        let script = try #require(CosmeticFilterEngine.script(for: rules, disabledDomains: ["broken.example"],
                                                              host: "news.example"))
        #expect(script.source.contains(".ad"))
        #expect(script.source.contains("news.example"))
        #expect(script.source.contains("display:none!important"))
        #expect(FilterParser.cosmeticRule(domains: "", selector: "div:has(script)") == nil)
    }

    @Test func webKitBlocksThirdPartyFixtureButAllowsFirstParty() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try #require(WKContentRuleListStore(url: directory))
        let rule = NetworkFilterRule(urlPattern: "tracker\\.test/track", resourceTypes: ["script"],
                                     includedDomains: [], excludedDomains: [], thirdPartyOnly: true)
        let list = try #require(try await store.compileContentRuleList(forIdentifier: "fixture", encodedContentRuleList: RuleCompiler.json(for: [rule])))
        let handler = FixtureSchemeHandler()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "paper-fixture")
        configuration.userContentController.add(list)
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        defer { view.stopLoading() }
        view.loadHTMLString("""
        <html><body><div class='ad'>Ad</div>
        <script src='paper-fixture://first.test/first.js'></script>
        <script src='paper-fixture://tracker.test/track.js'></script></body></html>
        """, baseURL: URL(string: "paper-fixture://first.test/"))
        for _ in 0..<100 where !handler.requestedHosts.contains("first.test") {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(handler.requestedHosts.contains("first.test"))
        #expect(!handler.requestedHosts.contains("tracker.test"))
        #expect(try await view.evaluateJavaScript("window.firstPartyLoaded === true") as? Bool == true)
        #expect(try await view.evaluateJavaScript("window.trackerLoaded === true") as? Bool != true)
    }

    @Test func cosmeticFixtureHidesAdAndReportsInitialMatches() async throws {
        let rule = try #require(FilterParser.cosmeticRule(domains: "news.example", selector: ".ad"))
        let controller = WKUserContentController()
        let counter = CosmeticCountHandler()
        controller.add(counter, name: CosmeticFilterEngine.messageName)
        controller.addUserScript(try #require(CosmeticFilterEngine.script(for: [rule], disabledDomains: [],
                                                                         host: "news.example")))
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        defer { view.stopLoading(); controller.removeScriptMessageHandler(forName: CosmeticFilterEngine.messageName) }
        view.loadHTMLString("<html><body><div class='ad'>Ad</div><div id='story'>Story</div></body></html>",
                            baseURL: URL(string: "https://news.example"))
        for _ in 0..<100 where counter.count == nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(counter.count == 1)
        #expect(try await view.evaluateJavaScript("getComputedStyle(document.querySelector('.ad')).display") as? String == "none")
        #expect(try await view.evaluateJavaScript("getComputedStyle(document.querySelector('#story')).display") as? String != "none")
    }

    @Test func bundledListsCompileAndReloadFromCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("paper-blocker-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = ContentBlockerEngine(directory: directory)
        let coldBegan = Date()
        await initial.start()
        let coldSeconds = Date().timeIntervalSince(coldBegan)
        #expect(initial.rules.count >= 2)
        #expect(initial.diagnostics.contains("EasyList "))
        #expect(initial.diagnostics.contains("EasyPrivacy "))
        let restored = ContentBlockerEngine(directory: directory)
        let cacheBegan = Date()
        await restored.start()
        let cacheSeconds = Date().timeIntervalSince(cacheBegan)
        #expect(restored.cacheHits == 2)
        #expect(restored.rules.count == initial.rules.count)
        await restored.install("invalid rules", for: FilterSource.defaults[0], checkedAt: Date())
        #expect(restored.rules.count == initial.rules.count)
        #expect(restored.lastError?.contains("No supported") == true)
        print(String(format: "PAPER_BLOCKER_BENCHMARK cold=%.3fs cache=%.3fs easylist_compile=%.3fs easyprivacy_compile=%.3fs\n%@",
                     coldSeconds, cacheSeconds, initial.compileDurations["easylist"] ?? -1,
                     initial.compileDurations["easyprivacy"] ?? -1, initial.diagnostics))
        if FileManager.default.fileExists(atPath: "/private/tmp/paper-run-blocker-benchmark") {
            let report: [String: Any] = [
                "coldSeconds": coldSeconds, "cacheSeconds": cacheSeconds,
                "compileSeconds": initial.compileDurations,
                "parseSeconds": initial.parseDurations,
                "attachedLists": initial.rules.count,
                "initializationSeconds": initial.initializationDuration,
                "cacheLoadSeconds": restored.cachedLoadDuration,
                "stages": initial.stageProfiles.mapValues { profile -> [String: Any] in
                    ["sourceLoad": profile.sourceLoad,
                     "preparedRead": profile.preparedRead ?? 0,
                     "scanAndDeduplicate": profile.scanAndDeduplicate,
                     "normalize": profile.normalize, "rank": profile.rank,
                     "partition": profile.partition,
                     "fingerprint": profile.fingerprint ?? 0,
                     "serialize": profile.serialize,
                     "webKitCompile": profile.webKitCompile,
                     "cacheStore": profile.cacheStore,
                     "jsonBytes": profile.jsonBytes,
                     "reusedPartitions": profile.reusedPartitions,
                     "preparedCacheHit": profile.preparedCacheHit]
                },
                "diagnostics": initial.diagnostics
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: "/private/tmp/paper-phase2d-v2-metrics.json"), options: .atomic)
        }
    }

    @Test func newSessionReceivesRulesAndBypassRemovesThem() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("paper-bypass-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = ContentBlockerEngine(directory: directory)
        let wasEnabled = blocker.policy.enabled
        blocker.setEnabled(true)
        defer { blocker.setEnabled(wasEnabled) }
        await blocker.start()
        let session = WebKitSession(websiteDataStore: .nonPersistent(), blocker: blocker)
        defer { session.close() }
        #expect(session.installedBlockerIdentifiers.count == blocker.rules.count)
        let domain = "paper-bypass-fixture.example"
        blocker.setDisabled(true, forDomain: domain)
        defer { blocker.setDisabled(false, forDomain: domain) }
        session.load(URL(string: "https://" + domain)!)
        for _ in 0..<100 where !session.installedBlockerIdentifiers.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(session.installedBlockerIdentifiers.isEmpty)
        let privateSession = WebKitSession(websiteDataStore: .nonPersistent(), blocker: blocker,
                                           privacyMode: .private)
        defer { privateSession.close() }
        #expect(blocker.policy.enabled)
        #expect(privateSession.installedBlockerIdentifiers.count == blocker.rules.count)
        privateSession.load(URL(string: "https://" + domain)!)
        for _ in 0..<100 where privateSession.installedBlockerIdentifiers.isEmpty {
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(privateSession.installedBlockerIdentifiers.count == blocker.rules.count)
        blocker.setEnabled(false)
        privateSession.updateBlocker()
        for _ in 0..<100 where !privateSession.installedBlockerIdentifiers.isEmpty {
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(privateSession.installedBlockerIdentifiers.isEmpty)
        blocker.setEnabled(true)
        privateSession.updateBlocker()
        for _ in 0..<100 where privateSession.installedBlockerIdentifiers.isEmpty {
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(privateSession.installedBlockerIdentifiers.count == blocker.rules.count)
    }
}

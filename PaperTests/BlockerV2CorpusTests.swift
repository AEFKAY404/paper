import Foundation
import Testing
import WebKit
@testable import Paper

@MainActor
private final class ExceptionProbeHandler: NSObject, WKURLSchemeHandler {
    var count = 0
    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        count += 1
        let body = Data("window.paperExceptionProbeLoaded = true;".utf8)
        task.didReceive(URLResponse(url: task.request.url!, mimeType: "text/javascript",
                                    expectedContentLength: body.count, textEncodingName: "utf-8"))
        task.didReceive(body)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

@MainActor
private final class CosmeticProbeHandler: NSObject, WKScriptMessageHandler {
    var count: Int?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        count = (message.body as? NSNumber)?.intValue
    }
}

/// Locally fixed syntax fixtures plus short, exact examples from Paper's bundled
/// EasyList/EasyPrivacy snapshot version 202610081602. Source terms:
/// https://easylist.to/pages/licence.html.
@MainActor
struct BlockerV2CorpusTests {
    private struct Case {
        let source: String
        let category: String
        let text: String
        let expected: String
    }

    private let corpus: [Case] = [
        .init(source: "EasyList", category: "host", text: "||ads.example.com^", expected: "network"),
        .init(source: "EasyList", category: "path", text: "||ads.example.com/banner*.js$script", expected: "network"),
        .init(source: "EasyList", category: "exact URL anchors", text: "|https://cdn.example.com/ad.js|$script", expected: "network"),
        .init(source: "EasyPrivacy", category: "party", text: "||metrics.example.com^$first-party,script", expected: "network"),
        .init(source: "EasyPrivacy", category: "party", text: "||metrics.example.com^$third-party,image", expected: "network"),
        .init(source: "EasyList", category: "included domain", text: "||ads.example.com^$domain=news.example.com", expected: "network"),
        .init(source: "EasyList", category: "excluded domain", text: "||ads.example.com^$domain=~shop.example.com", expected: "network"),
        .init(source: "EasyList", category: "mixed domain", text: "||ads.example.com^$domain=news.example.com|~shop.example.com", expected: "unsupported"),
        .init(source: "EasyList", category: "network exception", text: "@@||ads.example.com/banner.js$script", expected: "networkException"),
        .init(source: "EasyList", category: "cosmetic", text: "news.example.com##.ad", expected: "cosmetic"),
        .init(source: "EasyList", category: "cosmetic exclusion", text: "news.example.com,~video.example.com##.ad", expected: "cosmetic"),
        .init(source: "EasyList", category: "cosmetic exception", text: "news.example.com#@#.ad", expected: "cosmeticException"),
        .init(source: "EasyList", category: "CSS has", text: "news.example.com##div:has(.ad)", expected: "cosmetic"),
        .init(source: "EasyList", category: "scriptlet", text: "news.example.com##+js(json-prune, ad)", expected: "unsupported"),
        .init(source: "EasyList", category: "redirect", text: "||cdn.example.com^$redirect=noopjs", expected: "unsupported"),
        .init(source: "EasyPrivacy", category: "rewrite", text: "||api.example.com^$replace=/ad/noad/", expected: "unsupported"),
        .init(source: "EasyPrivacy", category: "regex form", text: "/ad[0-9]+/$script", expected: "unsupported"),
        .init(source: "EasyPrivacy", category: "procedural", text: "news.example.com#?#div:has-text(ad)", expected: "unsupported")
    ]

    private let bundledExamples: [Case] = [
        .init(source: "EasyList 202610081602", category: "host", text: "||000491b06a.com^", expected: "network"),
        .init(source: "EasyList 202610081602", category: "path", text: "||netnaija.com/s/$script", expected: "network"),
        .init(source: "EasyList 202610081602", category: "domain", text: "||bit.ly^$image,domain=tooxclusive.com", expected: "network"),
        .init(source: "EasyList 202610081602", category: "exception", text: "@@||ad.linksynergy.com^$image,domain=extrarebates.com", expected: "networkException"),
        .init(source: "EasyList 202610081602", category: "cosmetic", text: "##.-advertsSidebar", expected: "cosmetic"),
        .init(source: "EasyList 202610081602", category: "cosmetic exception", text: "dez.ro#@##ad-carousel", expected: "cosmeticException"),
        .init(source: "EasyPrivacy 202610081602", category: "host", text: "||00px.net^", expected: "network"),
        .init(source: "EasyPrivacy 202610081602", category: "path", text: "||cdn.app.cfigroup.com/webmon/$script", expected: "network"),
        .init(source: "EasyPrivacy 202610081602", category: "domain", text: "||succeedscene.com^$domain=theguardian.com", expected: "network"),
        .init(source: "EasyPrivacy 202610081602", category: "scriptlet", text: "madewell.com##+js(cookie-remover, dns_cookie)", expected: "unsupported"),
        .init(source: "EasyPrivacy 202610081602", category: "redirect", text: "||pcoptimizedsettings.com/wp-content/plugins/koko-analytics/$important,redirect=noop.js,script", expected: "unsupported")
    ]

    @Test func fixedCorpusClassifiesWithoutExecutingAdvancedRules() {
        for item in corpus + bundledExamples {
            let parsed = FilterParser.parse(item.text)
            let actual: String
            if !parsed.network.isEmpty { actual = "network" }
            else if !parsed.networkExceptions.isEmpty { actual = "networkException" }
            else if !parsed.cosmeticExceptions.isEmpty { actual = "cosmeticException" }
            else if !parsed.cosmetic.isEmpty { actual = "cosmetic" }
            else { actual = "unsupported" }
            #expect(actual == item.expected, "\(item.source): \(item.category): \(item.text)")
        }
    }

    @Test func pathPartyAndDomainCompilationIsPrecise() throws {
        let parsed = FilterParser.parse("""
        ||cdn.example.com/banner*.js$script,domain=news.example.com
        ||api.example.com/v1^$first-party,xmlhttprequest
        ||image.example.com^$third-party,image,domain=~shop.example.com
        """)
        #expect(parsed.network.count == 3)
        let json = try RuleCompiler.json(for: parsed.network)
        let entries = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        let triggers = entries.compactMap { $0["trigger"] as? [String: Any] }
        #expect(triggers.contains { ($0["load-type"] as? [String]) == ["first-party"] })
        #expect(triggers.contains { ($0["load-type"] as? [String]) == ["third-party"] })
        #expect(triggers.contains { ($0["if-domain"] as? [String]) == ["*news.example.com"] })
        #expect(triggers.contains { ($0["unless-domain"] as? [String]) == ["*shop.example.com"] })
        #expect(triggers.contains { ($0["url-filter"] as? String)?.contains("banner.*") == true })
        #expect(triggers.contains { ($0["resource-type"] as? [String]) == ["fetch", "raw"] })
        let countryCode = try #require(FilterParser.networkRule("||ads.example.co.uk^$domain=news.example.co.uk"))
        #expect(countryCode.includedDomains == ["news.example.co.uk"])
        #expect(SiteIdentity.shared.domain(forHost: "www.news.example.co.uk") == "example.co.uk")
    }

    @Test func exactExceptionsResolveBeforeChunkingAndRejectBroaderOnes() {
        let parsed = FilterParser.parse("""
        @@||cdn.example.com/script.js$script
        ||cdn.example.com/script.js$script
        ||cdn.example.com/other.js$script
        @@||cdn.example.com^$script
        """)
        #expect(parsed.network.count == 1)
        #expect(parsed.network[0].urlPattern.contains("other"))
        #expect(parsed.unsupportedByReason["unapplied network exception"] == 1)
        let reversed = FilterParser.parse("""
        ||cdn.example.com/script.js$script
        @@||cdn.example.com/script.js$script
        """)
        #expect(reversed.network.isEmpty)
        let resourceMismatch = FilterParser.parse("""
        ||cdn.example.com/script.js$script,image
        @@||cdn.example.com/script.js$script
        """)
        #expect(resourceMismatch.network.count == 1)
        #expect(resourceMismatch.unsupportedByReason["unapplied network exception"] == 1)
        let domain = FilterParser.parse("""
        ||cdn.example.com/script.js$script
        @@||cdn.example.com/script.js$script,domain=news.example.com
        """)
        #expect(domain.network.count == 1)
        #expect(domain.network[0].excludedDomains == ["news.example.com"])
    }

    @Test func exceptionResolutionPrecedesPartitionBoundaries() {
        let blocks = (0..<1_205).map { "||host\($0).example.com^$script" }
        let text = (blocks + ["@@||host1204.example.com^$script"]).joined(separator: "\n")
        let parsed = FilterParser.parse(text)
        #expect(parsed.network.count == 1_204)
        #expect(!parsed.network.contains { $0.urlPattern.contains("host1204") })
        #expect(RulePartitioner.partitions(for: parsed.network).count == 2)
    }

    @Test func partitionsAreBoundedAndKeepEveryRankedRuleOnce() {
        let rules = (0..<2_205).compactMap { index in
            FilterParser.networkRule("||host\(index).example.com^$script")
        }
        #expect(rules.count == 2_205)
        let partitions = RulePartitioner.partitions(for: RuleNormalizer.rank(rules))
        #expect(partitions.allSatisfy { !$0.rules.isEmpty && $0.rules.count <= RulePartitioner.maxRulesPerPartition })
        #expect(partitions.flatMap(\.rules).count == rules.count)
        #expect(Set(partitions.flatMap(\.rules)).count == rules.count)
        #expect(zip(partitions, partitions.dropFirst()).allSatisfy {
            $0.0.lowestPriority >= $0.1.highestPriority
        })
    }

    @Test func cosmeticExceptionsApplyAcrossSourceOrderAndSubdomains() {
        let easyList = FilterParser.parse("##.ad\nnews.example.com##.sponsored")
        let easyPrivacy = FilterParser.parse("news.example.com#@#.ad")
        let combined = easyList.cosmetic + easyPrivacy.cosmetic
        let news = CosmeticFilterEngine.selectors(for: combined, host: "www.news.example.com", disabledDomains: [])
        #expect(!news.contains(".ad"))
        #expect(news.contains(".sponsored"))
        let other = CosmeticFilterEngine.selectors(for: combined, host: "other.example.com", disabledDomains: [])
        #expect(other.contains(".ad"))
        #expect(!other.contains(".sponsored"))
        #expect(CosmeticFilterEngine.selectors(for: combined, host: "news.example.com", disabledDomains: ["news.example.com"]).isEmpty)
        let excluded = FilterParser.parse("news.example.com,~video.news.example.com##.promo")
        #expect(CosmeticFilterEngine.selectors(for: excluded.cosmetic, host: "video.news.example.com",
                                               disabledDomains: []).isEmpty)
    }

    @Test func cosmeticSelectionIsBounded() {
        let rules = (0..<1_000).map { CosmeticFilterRule(selector: ".ad\($0)", domains: []) } +
            [CosmeticFilterRule(selector: ".site-ad", domains: ["news.example.com"])]
        let selected = CosmeticFilterEngine.selectors(for: rules, host: "news.example.com", disabledDomains: [])
        #expect(selected.count <= CosmeticFilterEngine.maxSelectorsPerPage)
        #expect(selected.reduce(0) { $0 + $1.utf8.count + 25 } <= CosmeticFilterEngine.maxCSSBytes)
        #expect(selected.first == ".site-ad")
    }

    @Test func webKitSupportsNarrowHasCosmeticFixture() async throws {
        let rule = try #require(FilterParser.cosmeticRule(domains: "news.example.com", selector: "div:has(.ad)"))
        let controller = WKUserContentController()
        let handler = CosmeticProbeHandler()
        controller.add(handler, name: CosmeticFilterEngine.messageName)
        controller.addUserScript(try #require(CosmeticFilterEngine.script(for: [rule], disabledDomains: [],
                                                                         host: "news.example.com")))
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 500, height: 300), configuration: configuration)
        defer { view.stopLoading(); controller.removeScriptMessageHandler(forName: CosmeticFilterEngine.messageName) }
        view.loadHTMLString("<html><body><div id='ad-parent'><span class='ad'>Ad</span></div><p id='story'>Story</p></body></html>",
                            baseURL: URL(string: "https://news.example.com/"))
        for _ in 0..<100 where handler.count == nil {
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(handler.count == 1)
        #expect(try await view.evaluateJavaScript("getComputedStyle(document.querySelector('#ad-parent')).display") as? String == "none")
        #expect(try await view.evaluateJavaScript("getComputedStyle(document.querySelector('#story')).display") as? String != "none")
    }

    @Test func webKitCompilesPathAndFirstPartyRule() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("paper-v2-corpus-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try #require(WKContentRuleListStore(url: directory))
        let parsed = FilterParser.parse("""
        ||cdn.example.com/banner*.js$first-party,script
        ||image.example.com^$image,domain=~shop.example.com
        |https://cdn.example.com/ad.js|$script
        """)
        let json = try RuleCompiler.json(for: parsed.network)
        let list = try await store.compileContentRuleList(forIdentifier: "v2-path", encodedContentRuleList: json)
        #expect(list != nil)
    }

    @Test func webKitFirstPartyFixtureBlocksOnlyExplicitRule() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("paper-v2-party-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try #require(WKContentRuleListStore(url: directory))
        let rule = NetworkFilterRule(urlPattern: "probe\\.test/ad\\.js", resourceTypes: ["script"],
                                     includedDomains: [], excludedDomains: [], party: .firstParty)
        let list = try #require(try await store.compileContentRuleList(forIdentifier: "first-party-fixture",
                                                                    encodedContentRuleList: RuleCompiler.json(for: [rule])))
        let handler = ExceptionProbeHandler()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "paper-fixture")
        configuration.userContentController.add(list)
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 500, height: 300), configuration: configuration)
        defer { view.stopLoading() }
        view.loadHTMLString("<html><script src='paper-fixture://probe.test/ad.js'></script></html>",
                            baseURL: URL(string: "paper-fixture://probe.test/"))
        for _ in 0..<100 {
            if (try? await view.evaluateJavaScript("document.readyState")) as? String == "complete" { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(handler.count == 0)
    }

    @Test func v3CacheMigratesWithoutDroppingCompiledFallback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("paper-v2-migration-" + UUID().uuidString)
        let compiled = directory.appendingPathComponent("CompiledRules", isDirectory: true)
        try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try #require(WKContentRuleListStore(url: compiled))
        let old = try #require(try await store.compileContentRuleList(forIdentifier: "legacy-v3",
            encodedContentRuleList: RuleCompiler.json(for: [NetworkFilterRule(
                urlPattern: "legacy\\.example/", resourceTypes: ["script"],
                includedDomains: [], excludedDomains: [], party: .thirdParty)])))
        let now = Date().timeIntervalSinceReferenceDate
        let legacy: [String: Any] = ["version": 3, "sources": ["easylist": [
            "hash": "legacy", "identifiers": [old.identifier], "networkCount": 1,
            "cosmetic": [], "unsupportedByReason": [:], "omittedForLimit": 0,
            "compiledAt": now, "lastChecked": now
        ]]]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        let engine = ContentBlockerEngine(directory: directory, store: store)
        await engine.start()
        #expect(engine.cacheHits == 1)
        #expect(engine.rules.count >= 2)
        let manifestData = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        #expect(manifest["version"] as? Int == ContentBlockerEngine.cacheVersion)
    }

    @Test func webKitIgnorePreviousIsListLocalAndOrderSensitive() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("paper-v2-order-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try #require(WKContentRuleListStore(url: directory))
        let block = ["trigger": ["url-filter": "probe\\.test/ad\\.js", "resource-type": ["script"]],
                     "action": ["type": "block"]] as [String: Any]
        let allow = ["trigger": ["url-filter": "probe\\.test/ad\\.js", "resource-type": ["script"]],
                     "action": ["type": "ignore-previous-rules"]] as [String: Any]
        func compile(_ name: String, _ entries: [[String: Any]]) async throws -> WKContentRuleList {
            let data = try JSONSerialization.data(withJSONObject: entries)
            return try #require(try await store.compileContentRuleList(forIdentifier: name,
                                        encodedContentRuleList: String(decoding: data, as: UTF8.self)))
        }
        let blockThenAllow = try await compile("block-allow", [block, allow])
        let allowThenBlock = try await compile("allow-block", [allow, block])
        let blockOnly = try await compile("block-only", [block])
        let allowOnly = try await compile("allow-only", [allow])
        func requestCount(_ lists: [WKContentRuleList]) async throws -> Int {
            let handler = ExceptionProbeHandler()
            let configuration = WKWebViewConfiguration()
            configuration.setURLSchemeHandler(handler, forURLScheme: "paper-fixture")
            lists.forEach { configuration.userContentController.add($0) }
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 500, height: 300), configuration: configuration)
            view.loadHTMLString("<html><script src='paper-fixture://probe.test/ad.js'></script></html>",
                                baseURL: URL(string: "paper-fixture://site.test/"))
            for _ in 0..<100 {
                if (try? await view.evaluateJavaScript("document.readyState")) as? String == "complete" { break }
                try await Task.sleep(for: .milliseconds(30))
            }
            try await Task.sleep(for: .milliseconds(100))
            let count = handler.count
            view.stopLoading()
            return count
        }
        #expect(try await requestCount([blockThenAllow]) == 1)
        #expect(try await requestCount([allowThenBlock]) == 0)
        #expect(try await requestCount([blockOnly, allowOnly]) == 0)
    }
}

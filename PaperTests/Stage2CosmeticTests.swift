import Foundation
import Testing
import WebKit
@testable import Paper

@MainActor
struct Stage2CosmeticTests {
    @Test func validatedStaticCSSAcceptsUsefulSelectorsAndRejectsUnsafeForms() {
        let accepted = [
            "[data-testid=\"adBanner-wrapper\"]",
            ".feed-card:has(> .sponsored)",
            ".slot[class*=\"-ad-\"]",
            ".feed > .card:first-child",
            ".card:not(.editorial)"
        ]
        for selector in accepted { #expect(StaticCosmeticSelector.isSafe(selector)) }
        #expect(StaticCosmeticSelector.isSafe("shreddit-ad-post", domainScoped: true))
        #expect(!StaticCosmeticSelector.isSafe("shreddit-ad-post"))
        #expect(StaticCosmeticSelector.isSafe("[data-faceplate-tracking-context*=\"\\\"promoted\\\":true\"]",
                                             domainScoped: true))
        let rejected = [
            "body:has(.ad)", "button", ".ad{display:none}",
            ".ad[onclick=\"bad\"", ".card:has(:has(.ad))",
            ".card:has-text(sponsored)", ".card,form",
            String(repeating: ".ad > ", count: 12) + ".slot"
        ]
        for selector in rejected { #expect(!StaticCosmeticSelector.isSafe(selector)) }
        let parsed = FilterParser.parse("""
        reddit.com##.feed-card:has(> .sponsored)
        reddit.com##[data-testid="adBanner-wrapper"]
        reddit.com##shreddit-ad-post
        reddit.com##.card:has(:has(.ad))
        """)
        #expect(parsed.cosmetic.count == 3)
        #expect(parsed.unsupportedByReason["cosmetic selector"] == 1)
    }

    @Test func globalAndDomainExceptionsResolveDeterministically() {
        let rules = FilterParser.parse("""
        ##.ad
        news.example.com##.native-ad
        news.example.com#@#.ad
        #@#.native-ad
        """).cosmetic
        let news = CosmeticFilterEngine.selectors(for: rules, host: "www.news.example.com", disabledDomains: [])
        #expect(!news.contains(".ad"))
        #expect(!news.contains(".native-ad"))
        let other = CosmeticFilterEngine.selectors(for: rules, host: "other.example.com", disabledDomains: [])
        #expect(other.contains(".ad"))
        #expect(!other.contains(".native-ad"))
    }

    @Test func cachedStaticScriptHidesNewSPAElementsWithoutObserverOrControls() async throws {
        let rules = FilterParser.parse(#"""
        reddit.example##.feed-card:has(> .sponsored)
        reddit.example##[data-testid="adBanner-wrapper"]
        reddit.example##[data-faceplate-tracking-context*="\"promoted\":true"]
        """#).cosmetic
        let script = try #require(CosmeticFilterEngine.script(for: rules, disabledDomains: [],
                                                                host: "reddit.example", versionKey: "fixture-v1"))
        #expect(script.injectionTime == .atDocumentStart)
        #expect(script.isForMainFrameOnly)
        #expect(!script.source.contains("MutationObserver"))
        let repeatScript = try #require(CosmeticFilterEngine.script(for: rules, disabledDomains: [],
                                                                      host: "reddit.example", versionKey: "fixture-v1"))
        #expect(script === repeatScript)
        let changedVersion = try #require(CosmeticFilterEngine.script(for: rules, disabledDomains: [],
                                                                        host: "reddit.example", versionKey: "fixture-v2"))
        #expect(script !== changedVersion)
        let controller = WKUserContentController()
        let counter = Stage2CosmeticCountHandler()
        controller.add(counter, name: CosmeticFilterEngine.messageName)
        controller.addUserScript(script)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        defer { view.stopLoading(); controller.removeScriptMessageHandler(forName: CosmeticFilterEngine.messageName) }
        view.loadHTMLString("""
        <html><body><nav id='navigation'>Home</nav><form id='login'><button>Sign in</button></form>
        <div class='feed-card' id='sponsored'><span class='sponsored'>Sponsored</span></div>
        <div class='feed-card' id='editorial'>Story</div>
        <div data-testid='adBanner-wrapper' id='banner'>Ad</div>
        <div data-faceplate-tracking-context='{"promoted":true}' id='promoted'>Promoted</div></body></html>
        """, baseURL: URL(string: "https://reddit.example/"))
        for _ in 0..<100 where counter.count == nil { try await Task.sleep(for: .milliseconds(30)) }
        #expect(counter.count == 3)
        #expect(try await view.evaluateJavaScript("getComputedStyle(document.querySelector('#sponsored')).display") as? String == "none")
        #expect(try await view.evaluateJavaScript("getComputedStyle(document.querySelector('#promoted')).display") as? String == "none")
        #expect(try await view.evaluateJavaScript("getComputedStyle(document.querySelector('#editorial')).display") as? String != "none")
        #expect(try await view.evaluateJavaScript("getComputedStyle(document.querySelector('#navigation')).display") as? String != "none")
        #expect(try await view.evaluateJavaScript("getComputedStyle(document.querySelector('#login button')).display") as? String != "none")
        let spaHidden = try await view.evaluateJavaScript("""
        (() => {
          history.pushState({}, '', '/new-feed');
          const card = document.createElement('div'); card.className = 'feed-card'; card.id = 'spa-ad';
          card.innerHTML = '<span class="sponsored">Sponsored</span>';
          document.body.appendChild(card);
          return getComputedStyle(card).display === 'none';
        })()
        """) as? Bool
        #expect(spaHidden == true)
        #expect(try await view.evaluateJavaScript("document.querySelectorAll('#paper-cosmetic').length") as? Int == 1)
    }
}

@MainActor
private final class Stage2CosmeticCountHandler: NSObject, WKScriptMessageHandler {
    var count: Int?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        count = (message.body as? NSNumber)?.intValue
    }
}

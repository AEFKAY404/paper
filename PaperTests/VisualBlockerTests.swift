import Foundation
import Testing
import WebKit
@testable import Paper

@MainActor
struct VisualBlockerTests {
    @Test func replacesOnlyHighConfidenceRegionsAndCollapsesWithoutAdClicks() async throws {
        let fixture = try await Fixture(html: """
        <style>body{margin:0}.banner{width:300px;height:120px}shreddit-ad-post,dialog{display:block}</style>
        <div class='banner' data-ad-slot id='banner'><button id='ad-button' onclick='window.adClicks=(window.adClicks||0)+1'>Ad</button></div>
        <shreddit-ad-post class='banner' id='sponsored'><span class='sponsored'>Sponsored</span>Promotion</shreddit-ad-post>
        <dialog class='banner' open><div data-ad-slot id='modal-ad'>Account security</div></dialog>
        <div class='banner' id='editorial'>Editorial</div>
        """)
        defer { fixture.close() }
        try await fixture.waitForReplacements(2)
        #expect(try await fixture.number("document.querySelectorAll('.paper-blocked-slot').length") == 2)
        #expect(try await fixture.number("document.querySelectorAll('#modal-ad .paper-blocked-slot').length") == 0)
        #expect(try await fixture.string("document.querySelector('#editorial').textContent") == "Editorial")
        let before = try await fixture.number("document.querySelector('#banner').getBoundingClientRect().height")
        #expect(before >= 120)
        _ = try await fixture.view.evaluateJavaScript("document.querySelector('#banner .paper-blocked-slot button').click()")
        #expect(try await fixture.string("getComputedStyle(document.querySelector('#banner')).display") == "none")
        #expect(try await fixture.number("window.adClicks || 0") == 0)
        #expect(fixture.handler.collapsed == 1)
    }

    @Test func dynamicInsertionIsBoundedAndTeardownRestoresContent() async throws {
        let fixture = try await Fixture(html: "<main id='feed'>Feed</main>")
        defer { fixture.close() }
        _ = try await fixture.view.evaluateJavaScript("""
        for (let i=0;i<3;i++) {
          const ad=document.createElement('div'); ad.id='ad'+i;
          ad.setAttribute('data-ad-slot',''); ad.style.cssText='width:300px;height:100px';
          ad.textContent='Advertisement'; document.querySelector('#feed').appendChild(ad);
        }
        true
        """)
        try await fixture.waitForReplacements(3)
        #expect(try await fixture.number("document.querySelectorAll('[data-paper-blocked]').length") == 3)
        _ = try await fixture.view.evaluateJavaScript("document.querySelector('#ad0').append(document.createElement('span')); true")
        try await Task.sleep(for: .milliseconds(150))
        #expect(try await fixture.number("document.querySelectorAll('#ad0 .paper-blocked-slot').length") == 1)
        _ = try await fixture.view.evaluateJavaScript(VisualBlockerEngine.teardown + "; true")
        #expect(try await fixture.number("document.querySelectorAll('[data-paper-blocked]').length") == 0)
        #expect(try await fixture.string("document.querySelector('#ad0').textContent") == "Advertisement")
        #expect(fixture.handler.scanned <= VisualBlockerEngine.maximumCandidatesPerBatch)
    }

    @Test func exactInterstitialRestoresOnlyInlineScrollLockOnCollapse() async throws {
        let fixture = try await Fixture(html: """
        <style>#ad-interstitial{position:fixed;inset:0;width:100vw;height:100vh}</style>
        <script>document.body.style.overflow='hidden'</script>
        <div id='ad-interstitial' data-ad-interstitial>Advertisement</div>
        """)
        defer { fixture.close() }
        try await fixture.waitForReplacements(1)
        #expect(try await fixture.string("document.body.style.overflow") == "hidden")
        _ = try await fixture.view.evaluateJavaScript("document.querySelector('#ad-interstitial button').click(); true")
        #expect(try await fixture.string("document.body.style.overflow") == "")
    }

    @Test func nativePopupPolicyAllowsLinksAndSiteDecisionsButBlocksScripts() {
        let policy = PopupPolicy()
        let ordinary = URL(string: "https://example.org/story")!
        let auth = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(policy.decide(choice: .ask, navigationType: .linkActivated, url: ordinary,
                              site: "https://example.org", now: start) == .allow)
        #expect(policy.decide(choice: .ask, navigationType: .other, url: ordinary,
                              site: "https://example.org", now: start) == .block)
        #expect(policy.decide(choice: .allow, navigationType: .other, url: ordinary,
                              site: "https://example.org", now: start) == .allow)
        #expect(policy.decide(choice: .allow, navigationType: .other, url: ordinary,
                              site: "https://allowed.example.org", now: start) == .allow)
        #expect(policy.decide(choice: .allow, navigationType: .other, url: ordinary,
                              site: "https://allowed.example.org", now: start.addingTimeInterval(1)) == .allow)
        #expect(policy.decide(choice: .allow, navigationType: .other, url: ordinary,
                              site: "https://allowed.example.org", now: start.addingTimeInterval(2)) == .allow)
        #expect(policy.decide(choice: .allow, navigationType: .other, url: ordinary,
                              site: "https://allowed.example.org", now: start.addingTimeInterval(3)) == .block)
        #expect(policy.decide(choice: .block, navigationType: .linkActivated, url: ordinary,
                              site: "https://example.org", now: start) == .block)
        #expect(policy.decide(choice: .ask, navigationType: .other, url: auth,
                              site: "https://auth.example.org", now: start) == .ask)
        #expect(policy.decide(choice: .ask, navigationType: .other, url: auth,
                              site: "https://auth.example.org", now: start.addingTimeInterval(1)) == .ask)
        #expect(policy.decide(choice: .ask, navigationType: .other, url: auth,
                              site: "https://auth.example.org", now: start.addingTimeInterval(2)) == .block)
    }

    @Test func localDetectionTimingSample() async throws {
        var samples: [[String: Double]] = []
        for count in [1, 5, 10, 20] {
            let ads = (0..<count).map { "<div data-ad-slot style='width:300px;height:90px'>Ad \($0)</div>" }.joined()
            let ordinary = String(repeating: "<p>Ordinary text</p>", count: 150)
            let began = Date()
            let fixture = try await Fixture(html: ordinary + ads)
            try await fixture.waitForReplacements(count)
            let wall = Date().timeIntervalSince(began) * 1_000
            NSLog("PAPER_PHASE2E_VISUAL_PERF ads=%d scanned=%d replaced=%d scriptMs=%.2f wallMs=%.2f budgetExceeded=%d",
                  count, fixture.handler.scanned, fixture.handler.replaced, fixture.handler.elapsed,
                  wall, fixture.handler.budgetExceeded)
            samples.append(["ads": Double(count), "scanned": Double(fixture.handler.scanned),
                            "replaced": Double(fixture.handler.replaced), "scriptMs": fixture.handler.elapsed,
                            "wallMs": wall, "budgetExceeded": Double(fixture.handler.budgetExceeded)])
            #expect(fixture.handler.replaced == count)
            #expect(fixture.handler.budgetExceeded == 0)
            fixture.close()
        }
        let output = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PaperPhase2E", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("local-performance.json"), options: .atomic)
    }
}

@MainActor
private final class Fixture {
    let view: WKWebView
    let handler = VisualBlockerHandler()

    init(html: String) async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(handler, name: VisualBlockerEngine.messageName)
        configuration.userContentController.addUserScript(VisualBlockerEngine.script)
        view = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
        view.loadHTMLString("<html><body><div id='paper-fixture-root'></div>\(html)</body></html>",
                            baseURL: URL(string: "https://fixture.example/"))
        for _ in 0..<100 {
            if (try? await view.evaluateJavaScript("document.getElementById('paper-fixture-root') !== null") as? Bool) == true {
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw FixtureError.timeout
    }

    func waitForReplacements(_ count: Int) async throws {
        for _ in 0..<100 {
            if handler.replaced >= count { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        let state = (try? await view.evaluateJavaScript("""
        JSON.stringify({installed:!!window.__paperVisualBlocker,scanned:document.querySelectorAll('[data-ad-slot]').length,
          blocked:document.querySelectorAll('[data-paper-blocked]').length,
          banner:document.querySelector('#banner')?.getBoundingClientRect().height})
        """) as? String) ?? "unknown"
        throw FixtureError.diagnostic(state)
    }

    func number(_ script: String) async throws -> Int {
        guard let number = try await view.evaluateJavaScript(script) as? NSNumber else { throw FixtureError.invalidResult }
        return number.intValue
    }

    func string(_ script: String) async throws -> String {
        guard let string = try await view.evaluateJavaScript(script) as? String else { throw FixtureError.invalidResult }
        return string
    }

    func close() {
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: VisualBlockerEngine.messageName)
    }
}

private enum FixtureError: Error { case timeout, invalidResult, diagnostic(String) }

@MainActor
private final class VisualBlockerHandler: NSObject, WKScriptMessageHandler {
    var scanned = 0
    var replaced = 0
    var collapsed = 0
    var elapsed = 0.0
    var budgetExceeded = 0
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let values = message.body as? [String: Any] else { return }
        scanned = (values["scanned"] as? NSNumber)?.intValue ?? 0
        replaced = (values["replaced"] as? NSNumber)?.intValue ?? 0
        collapsed = (values["collapsed"] as? NSNumber)?.intValue ?? 0
        elapsed = (values["elapsed"] as? NSNumber)?.doubleValue ?? 0
        budgetExceeded = (values["budgetExceeded"] as? NSNumber)?.intValue ?? 0
    }
}

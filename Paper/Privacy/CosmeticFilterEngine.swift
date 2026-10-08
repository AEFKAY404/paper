import Foundation
import WebKit

enum CosmeticFilterEngine {
    static let messageName = "paperCosmeticCount"

    static func script(for rules: [CosmeticFilterRule], disabledDomains: Set<String>) -> WKUserScript? {
        guard !rules.isEmpty else { return nil }
        struct Entry: Encodable { let selector: String; let domains: [String] }
        let entries = rules.map { Entry(selector: $0.selector, domains: $0.domains) }
        guard let data = try? JSONEncoder().encode(entries),
              let json = String(data: data, encoding: .utf8),
              let bypassData = try? JSONEncoder().encode(Array(disabledDomains)),
              let bypassJSON = String(data: bypassData, encoding: .utf8) else { return nil }
        let source = """
        (() => {
          const host = location.hostname.toLowerCase();
          const matches = domain => host === domain || host.endsWith('.' + domain);
          if ((\(bypassJSON)).some(matches)) return;
          const selectors = (\(json)).filter(rule => !rule.domains.length || rule.domains.some(matches))
                                      .map(rule => rule.selector);
          if (!selectors.length) return;
          const style = document.createElement('style');
          style.id = 'paper-cosmetic';
          style.textContent = selectors.map(selector => selector + '{display:none!important}').join('\\n');
          (document.head || document.documentElement).appendChild(style);
          // Count the initial matching elements once. CSS handles later DOM changes.
          const matchesAtLoad = new Set();
          for (let index = 0; index < selectors.length; index += 100) {
            try {
              for (const element of document.querySelectorAll(selectors.slice(index, index + 100).join(','))) {
                matchesAtLoad.add(element);
              }
            } catch (_) {}
          }
          window.webkit.messageHandlers.paperCosmeticCount.postMessage(matchesAtLoad.size);
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }
}

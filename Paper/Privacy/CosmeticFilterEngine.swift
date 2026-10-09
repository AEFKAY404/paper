import Foundation
import WebKit

enum CosmeticFilterEngine {
    static let messageName = "paperCosmeticCount"
    static let compilerVersion = 2

    static let maxSelectorsPerPage = 500
    static let maxCSSBytes = 32_000
    private static let maxCachedSites = 24
    private static var cachedScripts: [String: WKUserScript] = [:]
    private static var cacheOrder: [String] = []

    static func selectors(for rules: [CosmeticFilterRule], host: String,
                          disabledDomains: Set<String>) -> [String] {
        let host = host.lowercased()
        let matches: (String) -> Bool = { host == $0 || host.hasSuffix("." + $0) }
        guard !disabledDomains.contains(where: matches) else { return [] }
        let applicable = rules.filter { rule in
            (rule.domains.isEmpty || rule.domains.contains(where: matches)) &&
            !rule.excludedDomains.contains(where: matches)
        }
        let exceptions = Set(applicable.filter(\.isException).map(\.selector))
        let hides = applicable.filter { !$0.isException && !exceptions.contains($0.selector) }
        let prioritized = hides.filter { !$0.domains.isEmpty } + hides.filter(\.domains.isEmpty)
        var result: [String] = []
        var seen: Set<String> = []
        var bytes = 0
        for rule in prioritized {
            guard seen.insert(rule.selector).inserted else { continue }
            let cost = rule.selector.utf8.count + 25
            if result.count >= maxSelectorsPerPage || bytes + cost > maxCSSBytes { break }
            result.append(rule.selector)
            bytes += cost
        }
        return result
    }

    static func script(for rules: [CosmeticFilterRule], disabledDomains: Set<String>,
                       host: String, versionKey: String? = nil) -> WKUserScript? {
        guard !rules.isEmpty else { return nil }
        let key = versionKey.map {
            "v\(compilerVersion)|\($0)|\(host.lowercased())|\(disabledDomains.sorted().joined(separator: ","))"
        }
        if let key, let cached = cachedScripts[key] {
            cacheOrder.removeAll { $0 == key }
            cacheOrder.append(key)
            return cached
        }
        let selected = selectors(for: rules, host: host, disabledDomains: disabledDomains)
        guard !selected.isEmpty,
              let data = try? JSONEncoder().encode(selected),
              let json = String(data: data, encoding: .utf8),
              let hostData = try? JSONEncoder().encode(host.lowercased()),
              let hostJSON = String(data: hostData, encoding: .utf8) else { return nil }
        let source = """
        (() => {
          if (location.hostname.toLowerCase() !== \(hostJSON)) return;
          const selectors = \(json);
          if (!selectors.length) return;
          const valid = selectors.filter(selector => {
            if (!selector.includes('[') && !selector.includes(':')) return true;
            try { return CSS.supports('selector(' + selector + ')'); } catch (_) { return false; }
          });
          if (!valid.length) return;
          const install = () => {
            if (document.getElementById('paper-cosmetic')) return;
            const style = document.createElement('style');
            style.id = 'paper-cosmetic';
            style.textContent = valid.map(selector => selector + '{display:none!important}').join('\\n');
            (document.head || document.documentElement).appendChild(style);
          };
          if (document.documentElement) install();
          else document.addEventListener('DOMContentLoaded', install, {once: true});
          const count = () => {
            const matchesAtLoad = new Set();
            for (let index = 0; index < valid.length; index += 100) {
              try {
                for (const element of document.querySelectorAll(valid.slice(index, index + 100).join(','))) {
                  matchesAtLoad.add(element);
                }
              } catch (_) {}
            }
            window.webkit.messageHandlers.paperCosmeticCount.postMessage(matchesAtLoad.size);
          };
          if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', count, {once: true});
          else count();
        })();
        """
        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        if let key {
            cachedScripts[key] = script
            cacheOrder.append(key)
            while cacheOrder.count > maxCachedSites {
                cachedScripts.removeValue(forKey: cacheOrder.removeFirst())
            }
        }
        return script
    }
}

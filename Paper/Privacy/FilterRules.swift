import Foundation

nonisolated struct FilterSource: Codable, Hashable, Sendable {
    enum Category: String, Codable, Sendable { case ads, privacy }
    let id: String
    let title: String
    let url: URL
    let licenseURL: URL
    let category: Category

    static let defaults: [FilterSource] = [
        .init(id: "easylist", title: "EasyList", url: URL(string: "https://easylist.to/easylist/easylist.txt")!,
              licenseURL: URL(string: "https://easylist.to/pages/licence.html")!, category: .ads),
        .init(id: "easyprivacy", title: "EasyPrivacy", url: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
              licenseURL: URL(string: "https://easylist.to/pages/licence.html")!, category: .privacy)
    ]
}

nonisolated struct NetworkFilterRule: Codable, Hashable, Sendable {
    let urlPattern: String
    let resourceTypes: [String]
    let includedDomains: [String]
    let excludedDomains: [String]
    let thirdPartyOnly: Bool
}

nonisolated struct CosmeticFilterRule: Codable, Hashable, Sendable {
    let selector: String
    let domains: [String]
}

nonisolated struct ParsedFilterList: Sendable {
    var network: [NetworkFilterRule] = []
    var cosmetic: [CosmeticFilterRule] = []
    var unsupportedByReason: [String: Int] = [:]
    var ignored = 0
    var duplicateCount = 0
    var omittedForLimit = 0
    var totalLines = 0
    mutating func unsupported(_ reason: String) { unsupportedByReason[reason, default: 0] += 1 }
}

/// This deliberately accepts a small, auditable subset of ABP syntax. Unknown
/// modifiers are rejected rather than silently changing the meaning of a rule.
enum FilterParser {
    nonisolated static let maxNetworkRulesPerSource = 8_000
    nonisolated static let maxCosmeticRulesPerSource = 4_000
    nonisolated static let maxGenericCosmeticRulesPerSource = 800
    nonisolated private static let resourceMap: [String: String] = [
        "image": "image", "script": "script", "stylesheet": "style-sheet",
        "font": "font", "media": "media", "xmlhttprequest": "raw",
        "other": "raw", "popup": "popup"
    ]
    nonisolated private static let allResourceTypes = ["image", "script", "style-sheet", "font", "raw", "media", "popup"]

    nonisolated static func parse(_ text: String) -> ParsedFilterList {
        var result = ParsedFilterList()
        var networkSet = Set<NetworkFilterRule>()
        var cosmeticSet = Set<CosmeticFilterRule>()
        var genericCosmeticCount = 0
        for raw in text.split(whereSeparator: \.isNewline) {
            result.totalLines += 1
            let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") {
                result.ignored += 1
                continue
            }
            if line.hasPrefix("@@") || line.contains("#@#") {
                result.unsupported("exception")
                continue
            }
            if line.contains("#?#") || line.contains("#$#") || line.contains("#%#") || line.contains("#^#") {
                result.unsupported("procedural or scriptlet cosmetic")
                continue
            }
            if let range = line.range(of: "##") {
                let domains = String(line[..<range.lowerBound])
                let selector = String(line[range.upperBound...])
                guard let rule = cosmeticRule(domains: domains, selector: selector) else {
                    result.unsupported("cosmetic selector")
                    continue
                }
                if !cosmeticSet.insert(rule).inserted { result.duplicateCount += 1; continue }
                if result.cosmetic.count >= maxCosmeticRulesPerSource ||
                    (rule.domains.isEmpty && genericCosmeticCount >= maxGenericCosmeticRulesPerSource) {
                    result.omittedForLimit += 1
                } else {
                    result.cosmetic.append(rule)
                    if rule.domains.isEmpty { genericCosmeticCount += 1 }
                }
                continue
            }
            guard let rule = networkRule(line) else {
                result.unsupported("network syntax or modifier")
                continue
            }
            if !networkSet.insert(rule).inserted { result.duplicateCount += 1; continue }
            if result.network.count < maxNetworkRulesPerSource { result.network.append(rule) }
            else { result.omittedForLimit += 1 }
        }
        return result
    }

    nonisolated static func cosmeticRule(domains: String, selector: String) -> CosmeticFilterRule? {
        let selector = selector.trimmingCharacters(in: .whitespaces)
        guard !selector.isEmpty, selector.count <= 160,
              selector.contains(".") || selector.contains("#"),
              selector.range(of: "^[A-Za-z0-9_ .#>+~:-]+$", options: .regularExpression) != nil,
              !selector.contains(":has"), !selector.contains(":not"), !selector.contains(":style"),
              !selector.contains(":remove"), !selector.contains(":matches") else { return nil }
        let domainList = domains.isEmpty ? [] : domains.split(separator: ",").map(String.init)
        guard domainList.allSatisfy({ validDomain($0) }) else { return nil }
        return CosmeticFilterRule(selector: selector, domains: domainList)
    }

    nonisolated static func networkRule(_ input: String) -> NetworkFilterRule? {
        guard input.hasPrefix("||") else { return nil }
        let parts = input.dropFirst(2).split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
        let target = String(parts[0])
        guard target.hasSuffix("^"), validDomain(String(target.dropLast())) else { return nil }
        let host = String(target.dropLast()).lowercased()
        var types = Set(allResourceTypes)
        var positiveTypes = Set<String>()
        var excludedTypes = Set<String>()
        var includedDomains: [String] = []
        var excludedDomains: [String] = []
        if parts.count == 2 {
            for option in parts[1].split(separator: ",").map(String.init) {
                if option == "third-party" { continue }
                if option.hasPrefix("domain=") {
                    let domains = option.dropFirst(7).split(separator: "|").map(String.init)
                    guard !domains.isEmpty else { return nil }
                    for domain in domains {
                        if domain.hasPrefix("~") {
                            let stripped = String(domain.dropFirst())
                            guard validDomain(stripped) else { return nil }
                            excludedDomains.append(stripped.lowercased())
                        } else {
                            guard validDomain(domain) else { return nil }
                            includedDomains.append(domain.lowercased())
                        }
                    }
                    continue
                }
                if option.hasPrefix("~"), let mapped = resourceMap[String(option.dropFirst())] {
                    excludedTypes.insert(mapped); continue
                }
                if let mapped = resourceMap[option] { positiveTypes.insert(mapped); continue }
                return nil
            }
        }
        guard includedDomains.isEmpty || excludedDomains.isEmpty else { return nil }
        if !positiveTypes.isEmpty { types = positiveTypes }
        types.subtract(excludedTypes)
        guard !types.isEmpty else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: host)
        let pattern = "^https?://([^/]*\\.)?" + escaped + "[/:?]"
        return NetworkFilterRule(urlPattern: pattern, resourceTypes: types.sorted(),
                                 includedDomains: includedDomains.sorted(), excludedDomains: excludedDomains.sorted(),
                                 thirdPartyOnly: true)
    }

    nonisolated private static func validDomain(_ input: String) -> Bool {
        input.count >= 4 && input.count <= 253 && input.contains(".") &&
        input.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil
    }
}

enum RuleCompiler {
    static func json(for rules: [NetworkFilterRule]) throws -> String {
        let entries: [[String: Any]] = rules.map { rule in
            var trigger: [String: Any] = ["url-filter": rule.urlPattern,
                                          "resource-type": rule.resourceTypes]
            if rule.thirdPartyOnly { trigger["load-type"] = ["third-party"] }
            if !rule.includedDomains.isEmpty { trigger["if-domain"] = rule.includedDomains.map { "*" + $0 } }
            if !rule.excludedDomains.isEmpty { trigger["unless-domain"] = rule.excludedDomains.map { "*" + $0 } }
            return ["trigger": trigger, "action": ["type": "block"]]
        }
        let data = try JSONSerialization.data(withJSONObject: entries)
        return String(decoding: data, as: UTF8.self)
    }
}

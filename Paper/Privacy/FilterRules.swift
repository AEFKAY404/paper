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
    enum Party: String, Codable, Sendable { case any, firstParty, thirdParty }
    let urlPattern: String
    let resourceTypes: [String]
    let includedDomains: [String]
    let excludedDomains: [String]
    let party: Party
    let isException: Bool

    init(urlPattern: String, resourceTypes: [String], includedDomains: [String],
         excludedDomains: [String], party: Party, isException: Bool = false) {
        self.urlPattern = urlPattern
        self.resourceTypes = resourceTypes
        self.includedDomains = includedDomains
        self.excludedDomains = excludedDomains
        self.party = party
        self.isException = isException
    }

    // Kept for existing local fixtures while callers move to the typed party model.
    init(urlPattern: String, resourceTypes: [String], includedDomains: [String],
         excludedDomains: [String], thirdPartyOnly: Bool) {
        self.init(urlPattern: urlPattern, resourceTypes: resourceTypes,
                  includedDomains: includedDomains, excludedDomains: excludedDomains,
                  party: thirdPartyOnly ? .thirdParty : .any)
    }
}

nonisolated struct CosmeticFilterRule: Codable, Hashable, Sendable {
    let selector: String
    let domains: [String]
    let excludedDomains: [String]
    let isException: Bool

    init(selector: String, domains: [String], excludedDomains: [String] = [], isException: Bool = false) {
        self.selector = selector
        self.domains = domains
        self.excludedDomains = excludedDomains
        self.isException = isException
    }

    private enum CodingKeys: String, CodingKey { case selector, domains, excludedDomains, isException }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(selector: try values.decode(String.self, forKey: .selector),
                  domains: try values.decode([String].self, forKey: .domains),
                  excludedDomains: try values.decodeIfPresent([String].self, forKey: .excludedDomains) ?? [],
                  isException: try values.decodeIfPresent(Bool.self, forKey: .isException) ?? false)
    }
}

nonisolated struct FilterParseTimings: Codable, Sendable {
    var scanAndDeduplicate: TimeInterval = 0
    var normalize: TimeInterval = 0
    var rank: TimeInterval = 0
}

nonisolated struct ParsedFilterList: Codable, Sendable {
    var network: [NetworkFilterRule] = []
    var cosmetic: [CosmeticFilterRule] = []
    var networkExceptions: [NetworkFilterRule] = []
    var cosmeticExceptions: [CosmeticFilterRule] = []
    var unsupportedByReason: [String: Int] = [:]
    var ignored = 0
    var duplicateCount = 0
    var omittedForLimit = 0
    var totalLines = 0
    var timings = FilterParseTimings()
    mutating func unsupported(_ reason: String) { unsupportedByReason[reason, default: 0] += 1 }
}

/// This deliberately accepts a small, auditable subset of ABP syntax. Unknown
/// modifiers are rejected rather than silently changing the meaning of a rule.
enum FilterParser {
    nonisolated static let maxNetworkRulesPerSource = 10_000
    nonisolated static let maxCosmeticRulesPerSource = 4_000
    nonisolated static let maxGenericCosmeticRulesPerSource = 800
    nonisolated static let maxCosmeticCandidatesPerSource = 24_000
    nonisolated static let maxAdvancedDomainCosmeticsPerSource = 900
    nonisolated static let maxAdvancedGenericCosmeticsPerSource = 100
    nonisolated private static let resourceMap: [String: [String]] = [
        "image": ["image"], "script": ["script"], "stylesheet": ["style-sheet"],
        "font": ["font"], "media": ["media"], "xmlhttprequest": ["raw", "fetch"],
        "other": ["other"], "popup": ["popup"]
    ]
    nonisolated private static let allResourceTypes = ["image", "script", "style-sheet", "font", "raw", "fetch", "other", "media", "popup"]

    nonisolated static func parse(_ text: String) -> ParsedFilterList {
        var result = ParsedFilterList()
        let scanBegan = Date()
        var networkSet = Set<NetworkFilterRule>()
        var cosmeticSet = Set<CosmeticFilterRule>()
        var cosmeticCandidates: [CosmeticFilterRule] = []
        var genericCosmeticCount = 0
        for raw in text.split(whereSeparator: \.isNewline) {
            result.totalLines += 1
            let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") {
                result.ignored += 1
                continue
            }
            if line.contains("##+js(") || line.contains("#%#") {
                result.unsupported(line.contains("json-prune") ? "JSON pruning" : "scriptlet")
                continue
            }
            if line.contains("#?#") || line.contains("#$#") || line.contains("#^#") {
                result.unsupported("procedural or scriptlet cosmetic")
                continue
            }
            if let range = line.range(of: "#@#") ?? line.range(of: "##") {
                let domains = String(line[..<range.lowerBound])
                let selector = String(line[range.upperBound...])
                guard let rule = cosmeticRule(domains: domains, selector: selector,
                                              isException: line[range] == "#@#") else {
                    result.unsupported("cosmetic selector")
                    continue
                }
                if !cosmeticSet.insert(rule).inserted { result.duplicateCount += 1; continue }
                if rule.isException {
                    result.cosmeticExceptions.append(rule)
                    continue
                }
                if cosmeticCandidates.count >= maxCosmeticCandidatesPerSource ||
                    (rule.domains.isEmpty && genericCosmeticCount >= maxGenericCosmeticRulesPerSource) {
                    result.omittedForLimit += 1
                } else {
                    cosmeticCandidates.append(rule)
                    if rule.domains.isEmpty { genericCosmeticCount += 1 }
                }
                continue
            }
            guard let rule = networkRule(line) else {
                let category: String
                if line.contains("redirect=") { category = "redirect" }
                else if line.contains("replace=") { category = "response rewriting" }
                else if line.hasPrefix("/") { category = "regex form" }
                else if line.contains("$") { category = "unsupported modifier" }
                else { category = "network syntax" }
                result.unsupported(category)
                continue
            }
            if !networkSet.insert(rule).inserted { result.duplicateCount += 1; continue }
            if rule.isException { result.networkExceptions.append(rule) }
            else { result.network.append(rule) }
        }
        result.timings.scanAndDeduplicate = Date().timeIntervalSince(scanBegan)
        let normalizeBegan = Date()
        result.network = RuleNormalizer.applyExactExceptions(to: result.network,
                                                              exceptions: result.networkExceptions,
                                                              unsupported: &result.unsupportedByReason)
        result.timings.normalize = Date().timeIntervalSince(normalizeBegan)
        let rankBegan = Date()
        result.network = RuleNormalizer.rank(result.network)
        if result.network.count > maxNetworkRulesPerSource {
            result.omittedForLimit += result.network.count - maxNetworkRulesPerSource
            result.network = Array(result.network.prefix(maxNetworkRulesPerSource))
        }
        let isCustomAd: (CosmeticFilterRule) -> Bool = {
            !$0.domains.isEmpty && $0.selector.split(separator: "-").contains("ad") &&
            $0.selector.range(of: "^[a-z][a-z0-9-]{2,79}$", options: .regularExpression) != nil
        }
        let isAdvanced: (CosmeticFilterRule) -> Bool = {
            $0.selector.contains("[") || $0.selector.contains(":") || isCustomAd($0)
        }
        let customAds = Array(cosmeticCandidates.filter(isCustomAd).prefix(100))
        let advancedDomain = cosmeticCandidates.filter { !$0.domains.isEmpty && isAdvanced($0) && !isCustomAd($0) }
        let advancedGeneric = cosmeticCandidates.filter { $0.domains.isEmpty && isAdvanced($0) }
        let ordinary = cosmeticCandidates.filter { !isAdvanced($0) }
        result.cosmetic = customAds +
            Array(advancedDomain.prefix(maxAdvancedDomainCosmeticsPerSource - customAds.count)) +
            Array(advancedGeneric.prefix(maxAdvancedGenericCosmeticsPerSource))
        result.cosmetic.append(contentsOf: ordinary.prefix(max(0, maxCosmeticRulesPerSource - result.cosmetic.count)))
        result.omittedForLimit += cosmeticCandidates.count - result.cosmetic.count
        result.cosmetic.append(contentsOf: result.cosmeticExceptions)
        result.timings.rank = Date().timeIntervalSince(rankBegan)
        return result
    }

    nonisolated static func cosmeticRule(domains: String, selector: String,
                                        isException: Bool = false) -> CosmeticFilterRule? {
        let selector = selector.trimmingCharacters(in: .whitespaces)
        var included: [String] = []
        var excluded: [String] = []
        for domain in domains.split(separator: ",").map(String.init) {
            if domain.hasPrefix("~") {
                let value = String(domain.dropFirst()).lowercased()
                guard validDomain(value) else { return nil }
                excluded.append(value)
            } else {
                guard validDomain(domain) else { return nil }
                included.append(domain.lowercased())
            }
        }
        guard StaticCosmeticSelector.isSafe(selector, domainScoped: !included.isEmpty) else { return nil }
        return CosmeticFilterRule(selector: selector, domains: included.sorted(),
                                  excludedDomains: excluded.sorted(), isException: isException)
    }

    nonisolated static func networkRule(_ input: String) -> NetworkFilterRule? {
        let isException = input.hasPrefix("@@")
        let input = isException ? String(input.dropFirst(2)) : input
        let prefix: String
        let body: Substring
        if input.hasPrefix("||") {
            prefix = "^https?://([^/]*\\.)?"
            body = input.dropFirst(2)
        } else if input.hasPrefix("|https://") {
            prefix = "^https://"
            body = input.dropFirst(9)
        } else if input.hasPrefix("|http://") {
            prefix = "^http://"
            body = input.dropFirst(8)
        } else { return nil }
        let parts = body.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
        let target = String(parts[0])
        let hostEnd = target.firstIndex(where: { "^/*|".contains($0) }) ?? target.endIndex
        let host = String(target[..<hostEnd]).lowercased()
        guard validDomain(host), hostEnd != target.endIndex else { return nil }
        let suffix = String(target[hostEnd...])
        guard suffix.first == "^" || suffix.first == "/" || suffix == "|",
              suffix.count <= 180,
              suffix.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "/^*|._?=&%-".contains($0)) }),
              suffix.filter({ $0 == "*" }).count <= 2 else { return nil }
        let escapedHost = host.replacingOccurrences(of: ".", with: "\\.")
        let boundary = "[/:?]"
        var pattern = prefix + escapedHost
        if suffix == "^" { pattern += boundary }
        else {
            var rest = suffix
            let endAnchor = rest.hasSuffix("|")
            if endAnchor { rest.removeLast() }
            for character in rest {
                switch character {
                case "^": pattern += "[^A-Za-z0-9_.%-]"
                case "*": pattern += ".*"
                default: pattern += NSRegularExpression.escapedPattern(for: String(character))
                }
            }
            if endAnchor { pattern += "$" }
        }
        var types = Set(allResourceTypes)
        var positiveTypes = Set<String>()
        var excludedTypes = Set<String>()
        var includedDomains: [String] = []
        var excludedDomains: [String] = []
        var party: NetworkFilterRule.Party = .thirdParty
        var explicitParty = false
        if parts.count == 2 {
            for option in parts[1].split(separator: ",").map(String.init) {
                if option == "third-party" || option == "~first-party" {
                    guard !explicitParty || party == .thirdParty else { return nil }
                    party = .thirdParty; explicitParty = true; continue
                }
                if option == "first-party" || option == "~third-party" {
                    guard !explicitParty || party == .firstParty else { return nil }
                    party = .firstParty; explicitParty = true; continue
                }
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
                    excludedTypes.formUnion(mapped); continue
                }
                if let mapped = resourceMap[option] { positiveTypes.formUnion(mapped); continue }
                return nil
            }
        }
        guard includedDomains.isEmpty || excludedDomains.isEmpty else { return nil }
        if !explicitParty && (!includedDomains.isEmpty || !excludedDomains.isEmpty) && suffix != "^" {
            party = .any
        }
        if !positiveTypes.isEmpty { types = positiveTypes }
        types.subtract(excludedTypes)
        guard !types.isEmpty else { return nil }
        return NetworkFilterRule(urlPattern: pattern, resourceTypes: types.sorted(),
                                 includedDomains: includedDomains.sorted(), excludedDomains: excludedDomains.sorted(),
                                 party: party, isException: isException)
    }

    nonisolated private static func validDomain(_ input: String) -> Bool {
        guard (4...253).contains(input.utf8.count), input.contains(".") else { return false }
        let labels = input.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            guard (1...63).contains(label.utf8.count),
                  let first = label.first, let last = label.last,
                  first.isASCII && (first.isLetter || first.isNumber),
                  last.isASCII && (last.isLetter || last.isNumber) else { return false }
            return label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}

/// Intentionally narrower than ABP exception semantics. An exception may only
/// narrow the *same* block pattern and resource-type set. It is resolved before
/// chunking, because WebKit cannot ignore rules in a different content list.
enum RuleNormalizer {
    nonisolated static func applyExactExceptions(to blocks: [NetworkFilterRule],
                                                 exceptions: [NetworkFilterRule],
                                                 unsupported: inout [String: Int]) -> [NetworkFilterRule] {
        var byKey: [String: [NetworkFilterRule]] = [:]
        for item in exceptions {
            byKey[item.urlPattern + "|" + item.party.rawValue + "|" + item.resourceTypes.joined(separator: ","), default: []].append(item)
        }
        var used = Set<NetworkFilterRule>()
        let output = blocks.compactMap { block -> NetworkFilterRule? in
            let key = block.urlPattern + "|" + block.party.rawValue + "|" + block.resourceTypes.joined(separator: ",")
            let anyPartyKey = block.urlPattern + "|" + NetworkFilterRule.Party.any.rawValue + "|" +
                block.resourceTypes.joined(separator: ",")
            let candidates = (byKey[key] ?? []) + (block.party == .any ? [] : (byKey[anyPartyKey] ?? []))
            guard !candidates.isEmpty else { return block }
            var excluded = Set(block.excludedDomains)
            for exception in candidates where exception.excludedDomains.isEmpty {
                // A same-scope global exception removes only this exact block.
                if exception.includedDomains.isEmpty {
                    used.insert(exception)
                    return nil
                }
                if !exception.includedDomains.isEmpty && block.includedDomains.isEmpty {
                    excluded.formUnion(exception.includedDomains)
                    used.insert(exception)
                } else if !exception.includedDomains.isEmpty &&
                            Set(exception.includedDomains) == Set(block.includedDomains) {
                    used.insert(exception)
                    return nil
                }
            }
            return NetworkFilterRule(urlPattern: block.urlPattern, resourceTypes: block.resourceTypes,
                                     includedDomains: block.includedDomains, excludedDomains: excluded.sorted(),
                                     party: block.party)
        }
        unsupported["unapplied network exception", default: 0] += exceptions.filter { !used.contains($0) }.count
        return output
    }

    nonisolated static func rank(_ rules: [NetworkFilterRule]) -> [NetworkFilterRule] {
        var buckets = Array(repeating: [NetworkFilterRule](), count: 8)
        for rule in rules { buckets[priority(rule)].append(rule) }
        return buckets.reversed().flatMap { $0 }
    }

    nonisolated static func priority(_ rule: NetworkFilterRule) -> Int {
        var value = 0
        if !rule.includedDomains.isEmpty { value += 4 }
        if !rule.urlPattern.hasSuffix("[/:?]") { value += 2 }
        if rule.resourceTypes.count < 9 { value += 1 }
        return value
    }
}

enum RulePartitioner {
    nonisolated struct Partition: Sendable {
        let highestPriority: Int
        let lowestPriority: Int
        let rules: [NetworkFilterRule]
    }

    static let maxRulesPerPartition = 1_000

    static func partitions(for rankedRules: [NetworkFilterRule], size: Int = maxRulesPerPartition) -> [Partition] {
        precondition(size > 0)
        var result: [Partition] = []
        for start in stride(from: 0, to: rankedRules.count, by: size) {
            let chunk = Array(rankedRules[start..<min(start + size, rankedRules.count)])
            result.append(Partition(highestPriority: RuleNormalizer.priority(chunk[0]),
                                    lowestPriority: RuleNormalizer.priority(chunk[chunk.count - 1]),
                                    rules: chunk))
        }
        return result
    }
}

enum RuleCompiler {
    nonisolated static func json(for rules: [NetworkFilterRule]) throws -> String {
        let entries: [[String: Any]] = try rules.map { rule in
            guard rule.includedDomains.isEmpty || rule.excludedDomains.isEmpty else {
                throw NSError(domain: "PaperBlocker", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "WebKit cannot combine if-domain and unless-domain"])
            }
            var trigger: [String: Any] = ["url-filter": rule.urlPattern,
                                          "resource-type": rule.resourceTypes]
            switch rule.party {
            case .thirdParty: trigger["load-type"] = ["third-party"]
            case .firstParty: trigger["load-type"] = ["first-party"]
            case .any: break
            }
            if !rule.includedDomains.isEmpty { trigger["if-domain"] = rule.includedDomains.map { "*" + $0 } }
            if !rule.excludedDomains.isEmpty { trigger["unless-domain"] = rule.excludedDomains.map { "*" + $0 } }
            return ["trigger": trigger, "action": ["type": rule.isException ? "ignore-previous-rules" : "block"]]
        }
        let data = try JSONSerialization.data(withJSONObject: entries)
        return String(decoding: data, as: UTF8.self)
    }
}

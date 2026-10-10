import Foundation

enum VoiceConfidence: String, Equatable {
    case exact, strong, ambiguous, unknown
}

struct VoiceTabChoice: Equatable, Identifiable {
    let id: UUID
    let title: String
    let detail: String
}

enum VoiceIntent: Equatable {
    case command(PaletteAction)
    case chooseTab([VoiceTabChoice])
    case none
}

struct VoiceIntentResult: Equatable {
    let intent: VoiceIntent
    let confidence: VoiceConfidence
    let extractedEntities: [String: String]
    let label: String
}

@MainActor
protocol VoiceIntentResolving {
    func resolve(_ transcript: String, tabs: [BrowserTab]) -> VoiceIntentResult
}

@MainActor
struct RuleBasedVoiceIntentResolver: VoiceIntentResolving {
    private struct PhraseGroup {
        let action: PaletteAction
        let label: String
        let phrases: [String]
    }

    private let groups: [PhraseGroup] = [
        .init(action: .newTab, label: "New tab", phrases: ["new tab", "open a new tab", "make a new tab", "open new tab"]),
        .init(action: .newPrivateTab, label: "New private tab", phrases: ["new private tab", "open a private tab", "open private tab"]),
        .init(action: .closeTab, label: "Close tab", phrases: ["close tab", "close this tab", "close current tab"]),
        .init(action: .nextTab, label: "Next tab", phrases: ["next tab", "switch to next tab"]),
        .init(action: .previousTab, label: "Previous tab", phrases: ["previous tab", "last tab", "switch to previous tab"]),
        .init(action: .back, label: "Back", phrases: ["back", "go back", "previous page"]),
        .init(action: .forward, label: "Forward", phrases: ["forward", "go forward", "next page"]),
        .init(action: .reload, label: "Reload", phrases: ["reload", "reload page", "refresh", "refresh page"]),
        .init(action: .stop, label: "Stop loading", phrases: ["stop", "stop loading", "stop page"]),
        .init(action: .overview, label: "Tab overview", phrases: ["tab overview", "show tabs", "show tab overview", "open tab overview"]),
        .init(action: .privacy, label: "Privacy", phrases: ["privacy", "open privacy", "site privacy", "open site privacy"]),
        .init(action: .accounts, label: "Accounts", phrases: ["accounts", "open accounts", "show accounts"]),
        .init(action: .settings, label: "Settings", phrases: ["settings", "open settings", "paper settings"]),
        .init(action: .handbook, label: "Paper handbook", phrases: ["handbook", "open handbook", "paper handbook", "open help"])
    ]

    func resolve(_ transcript: String, tabs: [BrowserTab]) -> VoiceIntentResult {
        let normalized = Self.normalize(transcript)
        guard !normalized.isEmpty else { return .init(intent: .none, confidence: .unknown, extractedEntities: [:], label: "Didn't understand") }
        for group in groups where group.phrases.contains(normalized) {
            return .init(intent: .command(group.action), confidence: .exact, extractedEntities: [:], label: group.label)
        }
        for prefix in ["search google for ", "search for ", "find "] where normalized.hasPrefix(prefix) {
            let query = String(normalized.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty, NavigationInput.url(for: query, searchEngine: .google) != nil else { break }
            return .init(intent: .command(.navigate(query)), confidence: .strong,
                         extractedEntities: ["query": query], label: "Search for \(query)")
        }
        for prefix in ["switch to ", "go to ", "open "] where normalized.hasPrefix(prefix) {
            var target = String(normalized.dropFirst(prefix.count))
            if target.hasPrefix("the ") { target.removeFirst(4) }
            if target.hasSuffix(" tab") { target.removeLast(4) }
            target = target.trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { break }
            let matches = rankTabs(target: target, tabs: tabs)
            if let best = matches.first {
                let choices = matches.filter { best.score - $0.score <= 4 }.prefix(5).map(\.choice)
                if choices.count > 1 {
                    return .init(intent: .chooseTab(Array(choices)), confidence: .ambiguous,
                                 extractedEntities: ["target": target], label: "Which \(target) tab?")
                }
                return .init(intent: .command(.switchTab(best.choice.id)), confidence: .strong,
                             extractedEntities: ["target": target], label: best.choice.title)
            }
            if Self.looksLikeAddress(target), NavigationInput.url(for: target, searchEngine: .google) != nil {
                return .init(intent: .command(.navigate(target)), confidence: .strong,
                             extractedEntities: ["address": target], label: "Open \(target)")
            }
        }
        return .init(intent: .none, confidence: .unknown, extractedEntities: [:], label: "Didn't understand")
    }

    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
        let words = folded.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "/" || $0 == ":" || $0 == "-" ? $0 : " " }
        var value = String(words).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while let filler = ["please ", "paper ", "could you ", "would you "].first(where: { value.hasPrefix($0) }) {
            value.removeFirst(filler.count)
        }
        if value.hasSuffix(" please") { value.removeLast(7) }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
    }

    private static func looksLikeAddress(_ target: String) -> Bool {
        target.contains("://") || (target.contains(".") && !target.contains(" ")) || target == "localhost"
    }

    private struct RankedTab {
        let choice: VoiceTabChoice
        let score: Int
    }

    private func rankTabs(target: String, tabs: [BrowserTab]) -> [RankedTab] {
        let target = Self.normalize(target)
        return tabs.compactMap { tab -> RankedTab? in
            let title = Self.normalize(tab.title)
            let host = Self.normalize(tab.url?.host ?? "")
            let site = host.split(separator: ".").first.map(String.init) ?? ""
            let score: Int
            if title == target { score = 100 }
            else if host == target || site == target || host == "www.\(target).com" || host == "\(target).com" { score = 90 }
            else if title.hasPrefix(target + " ") || title.hasPrefix(target + "-") { score = 80 }
            else if host.hasPrefix(target) || site.hasPrefix(target) { score = 70 }
            else {
                let similarity = max(Self.similarity(target, title), Self.similarity(target, site))
                guard target.count >= 4, similarity >= 0.78 else { return nil }
                score = Int(similarity * 60)
            }
            return RankedTab(choice: .init(id: tab.id, title: tab.title,
                                           detail: tab.url?.host ?? "Paper tab"), score: score)
        }.sorted { $0.score > $1.score }
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let left = Array(lhs), right = Array(rhs)
        guard left.count <= 80, right.count <= 80 else { return 0 }
        var previous = Array(0...right.count)
        for (row, character) in left.enumerated() {
            var current = [row + 1] + Array(repeating: 0, count: right.count)
            for (column, other) in right.enumerated() {
                current[column + 1] = min(previous[column + 1] + 1,
                                          current[column] + 1,
                                          previous[column] + (character == other ? 0 : 1))
            }
            previous = current
        }
        return 1 - Double(previous[right.count]) / Double(max(left.count, right.count))
    }
}

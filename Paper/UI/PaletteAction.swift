import Foundation

enum PaletteAction: Equatable {
    case handbook, settings, introduction, newTab, newPrivateTab, closeTab, nextTab, previousTab, overview, reload, stop, back, forward, privacy
    case switchTab(UUID)
    case navigate(String)
    case none

    static func resolve(_ input: String) -> PaletteAction {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .none }
        if value.caseInsensitiveCompare("help") == .orderedSame ||
            value.caseInsensitiveCompare("paper handbook") == .orderedSame {
            return .handbook
        }
        return .navigate(value)
    }
}

struct PaletteSuggestion: Identifiable {
    let title: String
    let subtitle: String
    let shortcut: String
    let action: PaletteAction
    var id: String { "\(title)-\(subtitle)" }

    static func matching(_ input: String, tabs: [BrowserTab]) -> [PaletteSuggestion] {
        let actions: [PaletteSuggestion] = [
            .init(title: "New Tab", subtitle: "Open a fresh page", shortcut: "⌘T", action: .newTab),
            .init(title: "New Private Tab", subtitle: "Browse with temporary site storage", shortcut: "⌘⇧N", action: .newPrivateTab),
            .init(title: "Privacy", subtitle: "Protection, site data, and permissions", shortcut: "", action: .privacy),
            .init(title: "Site Privacy", subtitle: "Controls for the current site", shortcut: "", action: .privacy),
            .init(title: "Privacy Settings", subtitle: "Filters, exceptions, and data clearing", shortcut: "⌘,", action: .settings),
            .init(title: "Tab Overview", subtitle: "See open tabs", shortcut: "⌘⇧\\", action: .overview),
            .init(title: "Close Tab", subtitle: "Close the current tab", shortcut: "⌘W", action: .closeTab),
            .init(title: "Next Tab", subtitle: "Switch to the next tab", shortcut: "⌃Tab", action: .nextTab),
            .init(title: "Previous Tab", subtitle: "Switch to the previous tab", shortcut: "⌃⇧Tab", action: .previousTab),
            .init(title: "Reload", subtitle: "Refresh this page", shortcut: "⌘R", action: .reload),
            .init(title: "Stop Loading", subtitle: "Stop the current page load", shortcut: "⌘.", action: .stop),
            .init(title: "Back", subtitle: "Previous page", shortcut: "⌘[", action: .back),
            .init(title: "Forward", subtitle: "Next page", shortcut: "⌘]", action: .forward),
            .init(title: "Paper Handbook", subtitle: "Learn the controls", shortcut: "⌘?", action: .handbook),
            .init(title: "Settings", subtitle: "Personalize Paper", shortcut: "⌘,", action: .settings),
            .init(title: "Replay Introduction", subtitle: "Show the welcome guide", shortcut: "", action: .introduction)
        ] + tabs.map { tab in
            .init(title: tab.title, subtitle: (tab.privacyMode == .private ? "Private · " : "") + (tab.url?.host ?? "Paper tab"), shortcut: "", action: .switchTab(tab.id))
        }
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Array(actions.prefix(7)) }
        return Array(actions.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query)
        }.prefix(8))
    }
}

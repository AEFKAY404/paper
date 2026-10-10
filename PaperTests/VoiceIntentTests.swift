import Foundation
import Testing
@testable import Paper

@MainActor
struct VoiceIntentTests {
    private let resolver = RuleBasedVoiceIntentResolver()

    @Test func normalizationAndCoreCommands() {
        #expect(RuleBasedVoiceIntentResolver.normalize("  Paper, please OPEN a NEW tab! ") == "open a new tab")
        let phrases: [(String, PaletteAction)] = [
            ("new tab", .newTab), ("open a new tab", .newTab), ("make a new tab", .newTab),
            ("close this tab", .closeTab), ("next tab", .nextTab), ("previous tab", .previousTab),
            ("go back", .back), ("previous page", .back), ("next page", .forward),
            ("refresh page", .reload), ("stop loading", .stop),
            ("show tabs", .overview), ("open privacy", .privacy),
            ("open accounts", .accounts),
            ("open settings", .settings), ("open handbook", .handbook),
            ("new private tab", .newPrivateTab)
        ]
        for (phrase, action) in phrases {
            let result = resolver.resolve(phrase, tabs: [])
            #expect(result.intent == .command(action))
            #expect(result.confidence == .exact)
        }
    }

    @Test func unknownAndUnsafePhrasesNeverExecute() {
        for phrase in ["", "close all tabs", "buy this", "submit the form", "send a message", "delete downloads"] {
            let result = resolver.resolve(phrase, tabs: [])
            #expect(result.intent == .none)
            #expect(result.confidence == .unknown)
        }
    }

    @Test func titleDomainFuzzyAndAmbiguousTabTargets() {
        let exact = tab("GitHub", "https://github.com/", id: UUID())
        let prefix = tab("GitHub Issues", "https://github.com/issues", id: UUID())
        let youtubeA = tab("YouTube — Music", "https://www.youtube.com/music", id: UUID())
        let youtubeB = tab("YouTube — WWDC", "https://www.youtube.com/watch", id: UUID())
        let tabs = [exact, prefix, youtubeA, youtubeB]
        #expect(resolver.resolve("switch to GitHub", tabs: tabs).intent == .command(.switchTab(exact.id)))
        #expect(resolver.resolve("open the GitHub Issues tab", tabs: tabs).intent == .command(.switchTab(prefix.id)))
        #expect(resolver.resolve("switch to Githob", tabs: [exact]).intent == .command(.switchTab(exact.id)))
        let ambiguous = resolver.resolve("go to YouTube", tabs: tabs)
        #expect(ambiguous.confidence == .ambiguous)
        if case .chooseTab(let choices) = ambiguous.intent {
            #expect(Set(choices.map(\.id)) == Set([youtubeA.id, youtubeB.id]))
        } else { Issue.record("Expected a tab chooser") }
    }

    @Test func searchAndAddressUseNavigationInput() {
        let search = resolver.resolve("search for macOS WebKit", tabs: [])
        #expect(search.intent == .command(.navigate("macos webkit")))
        #expect(search.extractedEntities["query"] == "macos webkit")
        #expect(NavigationInput.url(for: "macos webkit", searchEngine: .google)?.host == "www.google.com")
        let address = resolver.resolve("open github.com", tabs: [])
        #expect(address.intent == .command(.navigate("github.com")))
        #expect(NavigationInput.url(for: "github.com", searchEngine: .google)?.host == "github.com")
        #expect(resolver.resolve("open the nonexistent tab", tabs: []).intent == .none)
    }

    @Test func resolverLatencySample() {
        let tabs = (0..<20).map { tab("Example \($0)", "https://example\($0).com", id: UUID()) }
        let began = ProcessInfo.processInfo.systemUptime
        for _ in 0..<1_000 {
            _ = resolver.resolve("switch to Example 12", tabs: tabs)
        }
        let milliseconds = (ProcessInfo.processInfo.systemUptime - began) * 1_000
        let sample = String(format: "1000 resolutions against 20 tabs: %.3f ms total (%.3f ms each)\n",
                            milliseconds, milliseconds / 1_000)
        let report = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("paper-voice-resolver-sample.txt")
        try? sample.write(to: report, atomically: true, encoding: .utf8)
        #expect(milliseconds < 1_000)
    }

    private func tab(_ title: String, _ address: String, id: UUID) -> BrowserTab {
        BrowserTab(id: id, kind: .webpage, url: URL(string: address), title: title)
    }
}

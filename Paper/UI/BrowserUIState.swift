import Combine
import Foundation

@MainActor
final class BrowserUIState: ObservableObject {
    @Published var isPaletteVisible = false
    @Published var paletteInput = ""
    @Published private(set) var focusRequest = 0
    @Published var isHandbookVisible = false
    @Published var isPrivacyVisible = false
    @Published var isAccountsVisible = false
    @Published var isOverviewVisible = false
    @Published var overviewQuery = ""
    @Published var overviewSelectionID: UUID?
    @Published var feedbackText: String?
    private var feedbackTask: Task<Void, Never>?

    func openPalette(prefill: String = "") {
        isOverviewVisible = false
        paletteInput = prefill
        isPaletteVisible = true
        focusRequest += 1
    }

    func dismissPalette() {
        isPaletteVisible = false
    }

    func openHandbook() {
        dismissPalette()
        isOverviewVisible = false
        isHandbookVisible = true
    }

    func openPrivacy() {
        dismissPalette()
        isOverviewVisible = false
        isPrivacyVisible = true
    }

    func openAccounts() {
        dismissPalette()
        isOverviewVisible = false
        isAccountsVisible = true
    }

    func openOverview(browser: BrowserController) {
        dismissPalette()
        overviewQuery = ""
        overviewSelectionID = browser.activeTabID
        isOverviewVisible = true
    }

    func dismissOverview() { isOverviewVisible = false }

    func filteredTabs(_ tabs: [BrowserTab]) -> [BrowserTab] {
        let query = overviewQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tabs }
        return tabs.filter { tab in
            tab.title.localizedCaseInsensitiveContains(query) ||
            tab.url?.host?.localizedCaseInsensitiveContains(query) == true ||
            tab.url?.absoluteString.localizedCaseInsensitiveContains(query) == true
        }
    }

    func moveOverviewSelection(offset: Int, tabs: [BrowserTab]) {
        let filtered = filteredTabs(tabs)
        guard !filtered.isEmpty else { overviewSelectionID = nil; return }
        let index = filtered.firstIndex { $0.id == overviewSelectionID } ?? 0
        overviewSelectionID = filtered[(index + offset + filtered.count) % filtered.count].id
    }

    func showFeedback(_ message: String) {
        guard InteractionPreferences().feedbackEnabled else { return }
        feedbackTask?.cancel()
        feedbackText = message
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.feedbackText = nil
        }
    }
}

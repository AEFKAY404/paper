import Combine
import Foundation

enum OnboardingStep: Int {
    case navigate, search, tabs
}

enum OnboardingTabAction: Hashable {
    case newTab, nextTab, closeTab
}

@MainActor
final class OnboardingState: ObservableObject {
    @Published private(set) var step: OnboardingStep?
    @Published private(set) var triedLocation = false
    @Published private(set) var tabActions: Set<OnboardingTabAction> = []

    private let defaults: UserDefaults
    private let completionKey = "paper.onboarding.completed"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func showIfNeeded() {
        if !defaults.bool(forKey: completionKey), step == nil { step = .navigate }
    }

    func reopen() {
        triedLocation = false
        tabActions = []
        step = .navigate
    }

    func locationOpened() {
        if step == .navigate { triedLocation = true }
    }

    func continueFromLocation() {
        guard step == .navigate, triedLocation else { return }
        step = .search
    }

    func submitPractice(_ input: String) {
        guard step == .search, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        step = .tabs
    }

    func record(_ action: OnboardingTabAction) {
        if step == .tabs { tabActions.insert(action) }
    }

    func complete() {
        defaults.set(true, forKey: completionKey)
        step = nil
    }

    func skip() { complete() }
}

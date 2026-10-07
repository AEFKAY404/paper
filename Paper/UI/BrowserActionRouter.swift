import AppKit

/// One command path for the palette, keyboard monitor, and menus.
@MainActor
enum BrowserActionRouter {
    static func perform(_ action: PaletteAction, browser: BrowserController, ui: BrowserUIState,
                        onboarding: OnboardingState, searchEngine: SearchEngine = .google,
                        openSettings: (() -> Void)? = nil) {
        switch action {
        case .newTab:
            ui.dismissPalette(); ui.dismissOverview(); browser.newTab(); onboarding.record(.newTab)
        case .closeTab:
            browser.closeActiveTab(); onboarding.record(.closeTab)
        case .overview:
            ui.openOverview(browser: browser); ui.showFeedback("Tab overview")
        case .switchTab(let id):
            browser.activate(id); ui.dismissPalette(); ui.dismissOverview()
            ui.showFeedback(browser.activeTab?.title ?? "Tab")
        case .reload: browser.reload(); ui.dismissPalette()
        case .back: browser.goBack(); ui.dismissPalette()
        case .forward: browser.goForward(); ui.dismissPalette()
        case .handbook: ui.openHandbook()
        case .settings:
            ui.dismissPalette(); ui.dismissOverview(); openSettings?()
        case .introduction:
            ui.dismissPalette(); ui.dismissOverview(); onboarding.reopen()
        case .navigate(let input):
            browser.navigate(input, searchEngine: searchEngine); ui.dismissPalette()
        case .none: ui.dismissPalette()
        }
        if !ui.isPaletteVisible && !ui.isOverviewVisible && !ui.isHandbookVisible {
            DispatchQueue.main.async { browser.activeSession?.focus() }
        }
    }
}

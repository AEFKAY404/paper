import SwiftUI

@main
struct PaperApp: App {
    @NSApplicationDelegateAdaptor(PaperLifecycleDelegate.self) private var lifecycle
    @StateObject private var browser = BrowserController(engine: WebKitEngine(), store: SessionStore())
    @StateObject private var ui = BrowserUIState()
    @StateObject private var onboarding = OnboardingState()

    private var testColorScheme: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-paper.uiTest.dark") { return .dark }
        if ProcessInfo.processInfo.arguments.contains("-paper.uiTest.light") { return .light }
        return nil
        #else
        nil
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView(browser: browser, ui: ui, onboarding: onboarding)
                .preferredColorScheme(testColorScheme)
                .onAppear { lifecycle.browser = browser }
        }
        .defaultSize(width: 1100, height: 750)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { perform(.newTab) }
                    .keyboardShortcut("t")
            }
            CommandMenu("Navigate") {
                Button("Open Location") {
                    ui.openPalette(prefill: browser.activeTab?.url?.absoluteString ?? "")
                    onboarding.locationOpened()
                }
                .keyboardShortcut("l")
                Button("Back") { perform(.back) }.keyboardShortcut("[")
                Button("Forward") { perform(.forward) }.keyboardShortcut("]")
                Button("Reload") { perform(.reload) }.keyboardShortcut("r")
                Button("Stop Loading") { browser.stop() }.keyboardShortcut(".")
            }
            CommandMenu("Tabs") {
                Button("Close Tab") { perform(.closeTab) }.keyboardShortcut("w")
                Button("Tab Overview") { perform(.overview) }
                    .keyboardShortcut("\\", modifiers: [.command, .shift])
                Button("Next Tab") { browser.selectAdjacentTab(offset: 1); onboarding.record(.nextTab) }
                    .keyboardShortcut(.tab, modifiers: .control)
                Button("Previous Tab") { browser.selectAdjacentTab(offset: -1) }
                    .keyboardShortcut(.tab, modifiers: [.control, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Paper Handbook") { ui.openHandbook() }
                    .keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }

        Settings {
            PaperSettingsView(browser: browser)
        }
        .windowStyle(.hiddenTitleBar)
    }

    private func perform(_ action: PaletteAction) {
        BrowserActionRouter.perform(action, browser: browser, ui: ui, onboarding: onboarding)
    }
}

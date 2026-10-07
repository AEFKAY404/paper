import SwiftUI

@main
struct PaperApp: App {
    @NSApplicationDelegateAdaptor(PaperLifecycleDelegate.self) private var lifecycle
    @StateObject private var browser = BrowserController(engine: WebKitEngine(), store: SessionStore())
    @StateObject private var ui = BrowserUIState()
    @StateObject private var onboarding = OnboardingState()

    private var testColorScheme: ColorScheme? {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-paper.uiTest.dark") ? .dark : nil
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
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { browser.newTab(); onboarding.record(.newTab) }
                    .keyboardShortcut("t")
            }
            CommandMenu("Navigate") {
                Button("Open Location") {
                    ui.openPalette(prefill: browser.activeTab?.url?.absoluteString ?? "")
                    onboarding.locationOpened()
                }
                .keyboardShortcut("l")
                Button("Back") { browser.goBack() }.keyboardShortcut("[")
                Button("Forward") { browser.goForward() }.keyboardShortcut("]")
                Button("Reload") { browser.reload() }.keyboardShortcut("r")
                Button("Stop Loading") { browser.stop() }.keyboardShortcut(".")
            }
            CommandMenu("Tabs") {
                Button("Close Tab") { browser.closeActiveTab(); onboarding.record(.closeTab) }.keyboardShortcut("w")
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
            PaperSettingsView()
        }
    }
}

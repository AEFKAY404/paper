import SwiftUI

@main
struct PaperApp: App {
    @NSApplicationDelegateAdaptor(PaperLifecycleDelegate.self) private var lifecycle
    @StateObject private var browser = BrowserController(engine: WebKitEngine(), store: SessionStore())
    @StateObject private var ui = BrowserUIState()

    var body: some Scene {
        WindowGroup {
            ContentView(browser: browser, ui: ui)
                .onAppear { lifecycle.browser = browser }
        }
        .defaultSize(width: 1100, height: 750)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { browser.newTab(); ui.openPalette() }
                    .keyboardShortcut("t")
            }
            CommandMenu("Navigate") {
                Button("Open Location") {
                    ui.openPalette(prefill: browser.activeTab?.url?.absoluteString ?? "")
                }
                .keyboardShortcut("l")
                Button("Back") { browser.goBack() }.keyboardShortcut("[")
                Button("Forward") { browser.goForward() }.keyboardShortcut("]")
                Button("Reload") { browser.reload() }.keyboardShortcut("r")
                Button("Stop Loading") { browser.stop() }.keyboardShortcut(".")
            }
            CommandMenu("Tabs") {
                Button("Close Tab") { browser.closeActiveTab() }.keyboardShortcut("w")
                Button("Next Tab") { browser.selectAdjacentTab(offset: 1) }
                    .keyboardShortcut(.tab, modifiers: .control)
                Button("Previous Tab") { browser.selectAdjacentTab(offset: -1) }
                    .keyboardShortcut(.tab, modifiers: [.control, .shift])
            }
        }

        Settings {
            PaperSettingsView()
        }
    }
}

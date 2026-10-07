import SwiftUI

struct ContentView: View {
    @ObservedObject var browser: BrowserController
    @ObservedObject var ui: BrowserUIState
    @StateObject private var inputMonitor = BrowserInputMonitor()
    @AppStorage("paper.restoreSession") private var restoreSession = true
    @AppStorage("paper.searchEngine") private var searchEngine = SearchEngine.duckDuckGo.rawValue

    var body: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)

            if let session = browser.activeSession, let id = browser.activeTabID {
                BrowserSurface(session: session)
                    .id(id)
                    .ignoresSafeArea()
            }

            if browser.activeTab?.url == nil {
                VStack(spacing: 12) {
                    Text("Paper")
                        .font(.system(size: 42, weight: .light, design: .serif))
                    Text("Press ⌘L to open a page")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }

            if ui.isPaletteVisible {
                CommandPalette(input: $ui.paletteInput, focusRequest: ui.focusRequest) {
                    let selected = SearchEngine(rawValue: searchEngine) ?? .duckDuckGo
                    browser.navigate(ui.paletteInput, searchEngine: selected)
                    ui.dismissPalette()
                    browser.activeSession?.focus()
                } dismiss: {
                    ui.dismissPalette()
                    browser.activeSession?.focus()
                }
                .padding(.top, 32)
                .zIndex(1)
            }

            if let error = browser.activeTab?.error, !ui.isPaletteVisible {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).lineLimit(2)
                    Button("Reload") { browser.reload() }
                }
                .font(.callout)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 20)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear {
            browser.start(restorePreviousSession: restoreSession, initialURL: URL(string: "https://example.com"))
            inputMonitor.start(browser: browser, ui: ui)
        }
        .onDisappear { inputMonitor.stop() }
    }
}

private struct CommandPalette: View {
    @Binding var input: String
    let focusRequest: Int
    let submit: () -> Void
    let dismiss: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search or enter website", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($focused)
                .onSubmit(submit)
                .accessibilityIdentifier("paper.commandPalette.input")
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .frame(maxWidth: 620)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 9)
        .padding(.horizontal, 24)
        .onAppear { focused = true }
        .onChange(of: focusRequest) { _, _ in focused = true }
        .onExitCommand(perform: dismiss)
    }
}

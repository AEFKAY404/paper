import SwiftUI

struct ContentView: View {
    @ObservedObject var browser: BrowserController
    @ObservedObject var ui: BrowserUIState
    @ObservedObject var onboarding: OnboardingState
    @StateObject private var inputMonitor = BrowserInputMonitor()
    @AppStorage("paper.restoreSession") private var restoreSession = true
    @AppStorage("paper.searchEngine") private var searchEngine = SearchEngine.google.rawValue

    private var selectedSearchEngine: SearchEngine {
        SearchEngine(rawValue: searchEngine) ?? .google
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)

            if let tab = browser.activeTab {
                if tab.kind == .newTab {
                    NewTabView(tabID: tab.id, searchEngine: selectedSearchEngine,
                               mayFocus: !ui.isPaletteVisible && onboarding.step != .search) { input in
                        browser.navigate(input, searchEngine: selectedSearchEngine)
                    }
                    .id(tab.id)
                } else if let session = browser.activeSession {
                    BrowserSurface(session: session)
                        .id(tab.id)
                        .ignoresSafeArea()
                }
            }

            if ui.isPaletteVisible {
                CommandPalette(input: $ui.paletteInput, focusRequest: ui.focusRequest) {
                    switch PaletteAction.resolve(ui.paletteInput) {
                    case .handbook: ui.openHandbook()
                    case .navigate(let input):
                        browser.navigate(input, searchEngine: selectedSearchEngine)
                        ui.dismissPalette()
                        browser.activeSession?.focus()
                    case .none: ui.dismissPalette()
                    }
                } dismiss: {
                    ui.dismissPalette()
                    browser.activeSession?.focus()
                } showHandbook: {
                    ui.openHandbook()
                }
                .padding(.top, 32)
                .zIndex(2)
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
                .zIndex(1)
            }

            if onboarding.step != nil {
                OnboardingView(state: onboarding, dismissPalette: { ui.dismissPalette() },
                               newTab: { browser.newTab() },
                               nextTab: { browser.selectAdjacentTab(offset: 1) },
                               closeTab: { browser.closeActiveTab() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 94)
                    .padding(.trailing, 24)
                    .zIndex(3)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(BrowserWindowAnchor { inputMonitor.browserWindow = $0 })
        .sheet(isPresented: $ui.isHandbookVisible) {
            HandbookView {
                onboarding.reopen()
            }
        }
        .onAppear {
            browser.start(restorePreviousSession: restoreSession)
            onboarding.showIfNeeded()
            inputMonitor.start(browser: browser, ui: ui, onboarding: onboarding)
        }
        .onDisappear { inputMonitor.stop() }
    }
}

private struct CommandPalette: View {
    @Binding var input: String
    let focusRequest: Int
    let submit: () -> Void
    let dismiss: () -> Void
    let showHandbook: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
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
            if input.isEmpty || "help".contains(input.lowercased()) ||
                "paper handbook".contains(input.lowercased()) {
                Divider()
                Button(action: showHandbook) {
                    HStack {
                        Image(systemName: "book.closed")
                        Text("Paper Handbook")
                        Spacer()
                        Text("⌘?").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("paper.commandPalette.handbook")
            }
        }
        .frame(maxWidth: 620)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 9)
        .padding(.horizontal, 24)
        .task(id: focusRequest) {
            focused = false
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            focused = true
        }
        .onExitCommand(perform: dismiss)
    }
}

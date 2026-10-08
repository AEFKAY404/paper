import SwiftUI

struct ContentView: View {
    @ObservedObject var browser: BrowserController
    @ObservedObject var ui: BrowserUIState
    @ObservedObject var onboarding: OnboardingState
    @ObservedObject var blocker: ContentBlockerEngine
    @StateObject private var inputMonitor = BrowserInputMonitor()
    @StateObject private var titleBar = PaperTitleBarStyler()
    @StateObject private var previews = TabPreviewStore()
    @AppStorage("paper.restoreSession") private var restoreSession = true
    @AppStorage("paper.searchEngine") private var searchEngine = SearchEngine.google.rawValue
    @AppStorage(InteractionPreferences.reduceMotionKey) private var reduceDecorativeMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openSettings) private var openSettings

    private var selectedSearchEngine: SearchEngine {
        SearchEngine(rawValue: searchEngine) ?? .google
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(nsColor: activeSurfaceColor).ignoresSafeArea()

            if let tab = browser.activeTab {
                if tab.kind == .newTab {
                    NewTabView(tabID: tab.id,
                               mayFocus: !ui.isPaletteVisible && !ui.isOverviewVisible && !ui.isPrivacyVisible && onboarding.step != .search,
                               privacyMode: tab.privacyMode) { input in
                        browser.navigate(input, searchEngine: selectedSearchEngine)
                    }
                    .id(tab.id)
                    .accessibilityHidden(ui.isOverviewVisible || ui.isPaletteVisible || ui.isPrivacyVisible)
                } else if let session = browser.activeSession {
                    BrowserSurface(session: session)
                        .id(tab.id)
                        .accessibilityHidden(ui.isOverviewVisible || ui.isPaletteVisible || ui.isPrivacyVisible)
                }
            }

            if ui.isOverviewVisible {
                TabOverviewView(browser: browser, ui: ui, previews: previews,
                                activate: { id in perform(.switchTab(id)) },
                                close: { id in
                                    previews.removeTab(id)
                                    browser.closeTab(id)
                                    if ui.overviewSelectionID == id {
                                        ui.overviewSelectionID = ui.filteredTabs(browser.tabs).first?.id
                                    }
                                },
                                newTab: { perform(.newTab) },
                                dismiss: { dismissOverview() })
                    .zIndex(2)
                    .transition(.opacity)
            }

            if ui.isPaletteVisible {
                CommandPalette(input: $ui.paletteInput, focusRequest: ui.focusRequest,
                               tabs: browser.tabs, activeTab: browser.activeTab, perform: perform) {
                    ui.dismissPalette()
                    browser.activeSession?.focus()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(y: -60).zIndex(3)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let feedback = ui.feedbackText, !ui.isPaletteVisible && !ui.isOverviewVisible {
                Text(feedback).font(PaperTypography.metadata)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 24).allowsHitTesting(false).zIndex(4)
                    .accessibilityLabel(feedback)
                    .transition(.opacity)
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
        .animation(PaperMotion.overlay(reduceMotion: systemReduceMotion || reduceDecorativeMotion), value: ui.isOverviewVisible)
        .animation(PaperMotion.overlay(reduceMotion: systemReduceMotion || reduceDecorativeMotion), value: ui.isPaletteVisible)
        .animation(PaperMotion.feedback(reduceMotion: systemReduceMotion || reduceDecorativeMotion), value: ui.feedbackText)
        .background(BrowserWindowAnchor { window in
            inputMonitor.browserWindow = window
            titleBar.attach(window)
            updateTitleBar()
        })
        .sheet(isPresented: $ui.isHandbookVisible) {
            HandbookView {
                onboarding.reopen()
            }
        }
        .sheet(isPresented: $ui.isPrivacyVisible, onDismiss: {
            DispatchQueue.main.async { browser.activeSession?.focus() }
        }) {
            PrivacyPanelView(browser: browser, blocker: blocker, openPrivateTab: { perform(.newPrivateTab) })
        }
        .onAppear {
            InteractionPreferences().migrateLegacyGestureSetting()
            browser.start(restorePreviousSession: restoreSession)
            onboarding.showIfNeeded()
            inputMonitor.start(browser: browser, ui: ui, onboarding: onboarding)
            updateTitleBar()
        }
        .onChange(of: browser.activeTabID) { _, _ in
            updateTitleBar()
            guard !ui.isPaletteVisible && !ui.isOverviewVisible && !ui.isPrivacyVisible else { return }
            DispatchQueue.main.async { browser.activeSession?.focus() }
        }
        .onChange(of: browser.tabs.map(\.surfaceRevision)) { _, _ in updateTitleBar() }
        .onChange(of: browser.tabs.map(\.id)) { _, _ in previews.reconcile(browser: browser) }
        .onChange(of: ui.isOverviewVisible) { _, _ in updateTitleBar() }
        .onChange(of: ui.isHandbookVisible) { _, _ in updateTitleBar() }
        .onChange(of: ui.isPrivacyVisible) { _, _ in updateTitleBar() }
        .onChange(of: onboarding.step) { _, _ in updateTitleBar() }
        .onChange(of: colorScheme) { _, _ in updateTitleBar() }
        .onDisappear { inputMonitor.stop() }
    }

    private func perform(_ action: PaletteAction) {
        BrowserActionRouter.perform(action, browser: browser, ui: ui, onboarding: onboarding,
                                    searchEngine: selectedSearchEngine, openSettings: { openSettings() })
    }

    private func dismissOverview() {
        ui.dismissOverview()
        ui.showFeedback("Closed tab overview")
        DispatchQueue.main.async { browser.activeSession?.focus() }
    }

    private func updateTitleBar() {
        titleBar.update(activeSurfaceColor)
    }

    private var activeSurfaceColor: NSColor {
        let native = PaperSurfaceBackground.resolvedNativeColor(for: colorScheme)
        return ui.isOverviewVisible || ui.isHandbookVisible || ui.isPrivacyVisible || onboarding.step != nil || browser.activeTab?.kind != .webpage
            ? native : (browser.activeTab?.surfaceColor ?? native)
    }
}

private struct CommandPalette: View {
    @Binding var input: String
    let focusRequest: Int
    let tabs: [BrowserTab]
    let activeTab: BrowserTab?
    let perform: (PaletteAction) -> Void
    let dismiss: () -> Void
    @FocusState private var focused: Bool
    @State private var selection = 0

    private var suggestions: [PaletteSuggestion] { PaletteSuggestion.matching(input, tabs: tabs) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("", text: $input, prompt: Text("Search or enter website")
                    .font(PaperTypography.commandInput)
                    .foregroundStyle(PaperTypography.placeholderColor))
                    .textFieldStyle(.plain)
                    .font(PaperTypography.commandInput)
                    .focused($focused)
                    .onSubmit(submit)
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .accessibilityIdentifier("paper.commandPalette.input")
                if activeTab?.privacyMode == .private {
                    Text("PRIVATE")
                        .font(PaperTypography.status)
                        .tracking(1)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Private tab")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            if !suggestions.isEmpty {
                Divider()
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    Button { perform(suggestion.action) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title).font(PaperTypography.commandTitle)
                                Text(suggestion.subtitle).font(PaperTypography.metadata)
                                    .foregroundStyle(PaperTypography.readingColor)
                            }
                            Spacer()
                            Text(suggestion.shortcut).font(PaperTypography.metadata)
                                .foregroundStyle(PaperTypography.shortcutColor)
                        }
                        .padding(.horizontal, 16).frame(height: 44)
                        .background(index == selection ? Color.accentColor.opacity(0.12) : .clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(index == selection ? .isSelected : [])
                    .accessibilityIdentifier(suggestion.action == .handbook ? "paper.commandPalette.handbook" : "paper.commandPalette.action.\(index)")
                }
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
        .onChange(of: input) { _, _ in selection = 0 }
        .onExitCommand(perform: dismiss)
    }

    private func move(_ delta: Int) {
        guard !suggestions.isEmpty else { return }
        selection = (selection + delta + suggestions.count) % suggestions.count
    }

    private func submit() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty, suggestions.indices.contains(selection) {
            perform(suggestions[selection].action)
        } else if PaletteAction.resolve(value) == .handbook {
            perform(.handbook)
        } else if value.contains(".") || value.contains("://") {
            perform(.navigate(value))
        } else if suggestions.indices.contains(selection) {
            perform(suggestions[selection].action)
        } else {
            perform(PaletteAction.resolve(value))
        }
    }
}

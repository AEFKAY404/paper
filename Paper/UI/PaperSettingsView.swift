import SwiftUI

struct PaperSettingsView: View {
    @ObservedObject var browser: BrowserController
    @ObservedObject var blocker: ContentBlockerEngine
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("paper.searchEngine") private var searchEngine = SearchEngine.google.rawValue
    @AppStorage("paper.restoreSession") private var restoreSession = true
    @AppStorage("paper.historyGestures") private var historyGestures = true
    @AppStorage(InteractionPreferences.customGesturesKey) private var customGestures = false
    @AppStorage(InteractionPreferences.tabGestureKey) private var tabGesture = TabSwitchGesture.optionSwipe.rawValue
    @AppStorage(InteractionPreferences.feedbackKey) private var gestureFeedback = true
    @AppStorage(InteractionPreferences.reduceMotionKey) private var reduceDecorativeMotion = false
    @AppStorage("paper.blocker.enabled") private var blockerEnabled = true
    @State private var updateStatus = ""

    var body: some View {
        Form {
            Section("Browsing") {
                Picker("Search engine", selection: $searchEngine) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.title).tag(engine.rawValue)
                    }
                }
                Toggle("Restore open tabs at launch", isOn: $restoreSession)
            }
            Section("Interaction") {
                Toggle("Swipe to navigate history", isOn: $historyGestures)
                    .onChange(of: historyGestures) { _, enabled in browser.setHistorySwipe(enabled: enabled) }
                Toggle("Enable custom gestures", isOn: $customGestures)
                Picker("Switch tabs", selection: $tabGesture) {
                    ForEach(TabSwitchGesture.allCases) { gesture in
                        Text(gesture.title).tag(gesture.rawValue)
                    }
                }
                .disabled(!customGestures)
                Toggle("Show transient feedback", isOn: $gestureFeedback)
                Toggle("Reduce decorative motion", isOn: $reduceDecorativeMotion)
            }
            Section("Privacy") {
                Toggle("Block ads and trackers", isOn: $blockerEnabled)
                    .onChange(of: blockerEnabled) { _, enabled in blocker.setEnabled(enabled) }
                Text(blocker.isActive ? "Protection active" : (blockerEnabled ? "Protection unavailable — browsing remains available" : "Protection off"))
                    .font(.footnote)
                    .foregroundStyle(PaperTypography.readingColor)
                if let domain = browser.activeTab?.url?.host {
                    Toggle("Block on \(domain)", isOn: Binding(
                        get: { blocker.policy.allowsBlocking(browser.activeTab?.url) },
                        set: { blocker.setDisabled(!$0, forDomain: domain) }
                    ))
                }
                Button("Update filter lists") {
                    updateStatus = "Updating…"
                    Task {
                        await blocker.updateFilters()
                        updateStatus = blocker.lastError ?? "Filter update finished"
                    }
                }
                if !updateStatus.isEmpty { Text(updateStatus).font(.footnote) }
                Text("Changes to an open page may need a reload. Filtering and statistics stay on this Mac.")
                    .font(.footnote)
                    .foregroundStyle(PaperTypography.readingColor)
            }
            Text("Option-swipe tab switching is experimental and off until custom gestures are enabled. Native WebKit history swipes remain available independently.")
                .font(.footnote)
                .foregroundStyle(PaperTypography.readingColor)
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 520)
        .background(PaperSurfaceBackground.color)
        .background(BrowserWindowAnchor { window in
            PaperSurfaceBackground.configure(window)
            window?.backgroundColor = PaperSurfaceBackground.resolvedNativeColor(for: colorScheme)
        })
    }
}

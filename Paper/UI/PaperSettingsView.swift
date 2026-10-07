import SwiftUI

struct PaperSettingsView: View {
    @ObservedObject var browser: BrowserController
    @AppStorage("paper.searchEngine") private var searchEngine = SearchEngine.google.rawValue
    @AppStorage("paper.restoreSession") private var restoreSession = true
    @AppStorage("paper.historyGestures") private var historyGestures = true
    @AppStorage(InteractionPreferences.customGesturesKey) private var customGestures = false
    @AppStorage(InteractionPreferences.tabGestureKey) private var tabGesture = TabSwitchGesture.optionSwipe.rawValue
    @AppStorage(InteractionPreferences.feedbackKey) private var gestureFeedback = true
    @AppStorage(InteractionPreferences.reduceMotionKey) private var reduceDecorativeMotion = false

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
            Text("Option-swipe tab switching is experimental and off until custom gestures are enabled. Native WebKit history swipes remain available independently.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 420)
    }
}

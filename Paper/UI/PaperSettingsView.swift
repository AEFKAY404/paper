import SwiftUI

struct PaperSettingsView: View {
    @AppStorage("paper.searchEngine") private var searchEngine = SearchEngine.duckDuckGo.rawValue
    @AppStorage("paper.restoreSession") private var restoreSession = true
    @AppStorage("paper.historyGestures") private var historyGestures = true
    @AppStorage("paper.tabSwipe") private var tabSwipe = false

    var body: some View {
        Form {
            Picker("Search engine", selection: $searchEngine) {
                ForEach(SearchEngine.allCases) { engine in
                    Text(engine.title).tag(engine.rawValue)
                }
            }
            Toggle("Restore open tabs at launch", isOn: $restoreSession)
            Toggle("Swipe to navigate history", isOn: $historyGestures)
            Toggle("Option-swipe to switch tabs", isOn: $tabSwipe)
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 250)
    }
}

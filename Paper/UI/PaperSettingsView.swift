import SwiftUI

struct PaperSettingsView: View {
    @ObservedObject var browser: BrowserController
    @ObservedObject var blocker: ContentBlockerEngine
    @ObservedObject private var permissions = SitePermissionStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("paper.searchEngine") private var searchEngine = SearchEngine.google.rawValue
    @AppStorage("paper.restoreSession") private var restoreSession = true
    @AppStorage("paper.historyGestures") private var historyGestures = true
    @AppStorage(InteractionPreferences.customGesturesKey) private var customGestures = false
    @AppStorage(InteractionPreferences.tabGestureKey) private var tabGesture = TabSwitchGesture.optionSwipe.rawValue
    @AppStorage(InteractionPreferences.feedbackKey) private var gestureFeedback = true
    @AppStorage(InteractionPreferences.reduceMotionKey) private var reduceDecorativeMotion = false
    @AppStorage("paper.blocker.enabled") private var blockerEnabled = true
    @AppStorage("paper.blocker.cosmeticEnabled") private var cosmeticEnabled = true
    @State private var updateStatus = ""
    @State private var showClearData = false

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
                    .onChange(of: blockerEnabled) { _, enabled in blocker.setEnabled(enabled); browser.reload() }
                Toggle("Hide page elements matched by filters", isOn: $cosmeticEnabled)
                    .onChange(of: cosmeticEnabled) { _, enabled in blocker.cosmeticEnabled = enabled; browser.reload() }
                Text(blocker.isActive ? "Protection active" : (blockerEnabled ? "Protection unavailable — browsing remains available" : "Protection off"))
                    .font(.footnote)
                    .foregroundStyle(PaperTypography.readingColor)
                Text("Filters: \(blocker.sourceTitles.joined(separator: ", "))")
                    .font(.footnote).foregroundStyle(.secondary)
                if let lastUpdate = blocker.lastUpdateDate {
                    LabeledContent("Last update attempt", value: lastUpdate.formatted(date: .abbreviated, time: .shortened))
                }
                Button("Update filter lists") {
                    updateStatus = "Updating…"
                    Task {
                        await blocker.updateFilters()
                        updateStatus = blocker.lastError ?? "Filter update finished"
                    }
                }
                if !updateStatus.isEmpty { Text(updateStatus).font(.footnote) }
                if !blocker.policy.disabledForDomains.isEmpty {
                    ForEach(blocker.policy.disabledForDomains.sorted(), id: \.self) { site in
                        HStack {
                            Text("Protection off: \(site)")
                            Spacer()
                            Button("Remove") { blocker.setDisabled(false, forDomain: site) }
                        }
                    }
                }
                if !permissions.decisions.isEmpty {
                    ForEach(permissions.decisions.keys.sorted(), id: \.self) { site in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(site)
                                Text(permissions.decisions[site, default: [:]]
                                    .sorted { $0.key < $1.key }
                                    .map { "\($0.key.capitalized): \($0.value.title)" }
                                    .joined(separator: " · "))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Revoke") { permissions.revoke(site: site) }
                        }
                    }
                }
                Button("Clear Browsing Data…") { showClearData = true }
                Text("Private tabs use temporary WebKit storage and are never restored. Saved downloads remain on disk.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Changes to an open page may need a reload. Filtering and statistics stay on this Mac.")
                    .font(.footnote)
                    .foregroundStyle(PaperTypography.readingColor)
            }
            Text("Option-swipe tab switching is experimental and off until custom gestures are enabled. Native WebKit history swipes remain available independently.")
                .font(.footnote)
                .foregroundStyle(PaperTypography.readingColor)
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 650)
        .sheet(isPresented: $showClearData) { ClearBrowsingDataView() }
        .background(PaperSurfaceBackground.color)
        .background(BrowserWindowAnchor { window in
            PaperSurfaceBackground.configure(window)
            window?.backgroundColor = PaperSurfaceBackground.resolvedNativeColor(for: colorScheme)
        })
    }
}

private struct ClearBrowsingDataView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection = BrowsingDataSelection()
    @State private var confirm = false
    @State private var clearing = false

    var body: some View {
        Form {
            Section("Clear browsing data") {
                Toggle("Cookies", isOn: $selection.cookies)
                Toggle("Local storage", isOn: $selection.localStorage)
                Toggle("Caches", isOn: $selection.caches)
                Toggle("Other website data", isOn: $selection.otherWebsiteData)
            }
            Text("Clears selected categories for all sites in standard tabs. Private tabs use separate temporary stores.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Clear Data…", role: .destructive) { confirm = true }
                    .disabled(selection.types.isEmpty || clearing)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 320)
        .confirmationDialog("Clear selected browsing data for all sites?", isPresented: $confirm) {
            Button("Clear Browsing Data", role: .destructive) {
                Task {
                    clearing = true
                    await SiteDataManager().clearAll(selection)
                    clearing = false
                    dismiss()
                }
            }
        }
    }
}

import SwiftUI

struct TabOverviewView: View {
    @ObservedObject var browser: BrowserController
    @ObservedObject var ui: BrowserUIState
    @ObservedObject var previews: TabPreviewStore
    let activate: (UUID) -> Void
    let close: (UUID) -> Void
    let newTab: () -> Void
    let dismiss: () -> Void
    @FocusState private var searchFocused: Bool

    private var matchingTabs: [BrowserTab] { ui.filteredTabs(browser.tabs) }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Tabs").font(PaperTypography.overviewHeading)
                Spacer()
                Button(action: newTab) { Label("New Tab", systemImage: "plus") }
                    .accessibilityIdentifier("paper.overview.newTab")
                Button("Done", action: dismiss)
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("", text: $ui.overviewQuery, prompt: Text("Find a tab")
                    .font(PaperTypography.searchInput)
                    .foregroundStyle(PaperTypography.placeholderColor))
                    .textFieldStyle(.plain)
                    .font(PaperTypography.searchInput)
                    .focused($searchFocused)
                    .accessibilityIdentifier("paper.overview.search")
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

            GeometryReader { geometry in
                ScrollView {
                    LazyVGrid(columns: columns(for: geometry.size.width), spacing: 16) {
                        ForEach(matchingTabs) { tab in
                            card(tab)
                                .onAppear { previews.cardAppeared(tab.id, browser: browser) }
                                .onDisappear { previews.cardDisappeared(tab.id) }
                        }
                    }
                    .frame(maxWidth: gridWidth(for: geometry.size.width))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 20)
                }
            }
            if matchingTabs.isEmpty {
                Text("No matching tabs")
                    .font(PaperTypography.supporting)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            previews.present(browser: browser)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(40))
                searchFocused = true
            }
        }
        .onDisappear { previews.dismiss() }
        .onChange(of: browser.tabs.map(\.previewRevision)) { _, _ in previews.reconcile(browser: browser) }
        .onChange(of: browser.tabs.map(\.id)) { _, _ in
            previews.reconcile(browser: browser)
            if !matchingTabs.contains(where: { $0.id == ui.overviewSelectionID }) {
                ui.overviewSelectionID = matchingTabs.first?.id
            }
        }
        .onChange(of: ui.overviewQuery) { _, _ in
            if !matchingTabs.contains(where: { $0.id == ui.overviewSelectionID }) {
                ui.overviewSelectionID = matchingTabs.first?.id
            }
        }
        .onExitCommand(perform: dismiss)
    }

    private func columnCount(for width: CGFloat) -> Int {
        let fitting = max(1, Int((width + 16) / 226))
        return min(max(1, matchingTabs.count), fitting)
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 200, maximum: 320), spacing: 16),
              count: columnCount(for: width))
    }

    private func gridWidth(for width: CGFloat) -> CGFloat {
        let count = columnCount(for: width)
        return min(width, CGFloat(count) * 320 + CGFloat(count - 1) * 16)
    }

    private func card(_ tab: BrowserTab) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { activate(tab.id) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(Color(nsColor: .controlBackgroundColor))
                    if tab.kind == .newTab {
                        VStack(spacing: 9) {
                            HStack(spacing: 7) {
                                Image(systemName: "magnifyingglass")
                                Text("SEARCH or URL")
                            }
                            .font(PaperTypography.metadata)
                            .foregroundStyle(PaperTypography.readingColor)
                            .frame(maxWidth: 220, alignment: .leading)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            Text("Paper")
                                .font(PaperTypography.smallBrand)
                                .foregroundStyle(.secondary)
                        }
                    } else if let image = previews.previews[tab.id] {
                        Image(nsImage: image).resizable().scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    } else {
                        Image(systemName: tab.isLoading ? "hourglass" :
                              tab.error != nil ? "exclamationmark.triangle" : "globe")
                            .font(.system(size: 28, weight: .ultraLight)).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 150)
                .clipped()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(tab.title), \(tab.url?.host ?? "New Tab")")
            .accessibilityValue(tab.id == browser.activeTabID ? "Current tab" :
                                tab.id == ui.overviewSelectionID ? "Selected" : "")
            .accessibilityIdentifier("paper.overview.tab.\(tab.id)")

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tab.title).lineLimit(1).font(PaperTypography.tabTitle)
                    Text(tab.url?.host ?? (tab.kind == .newTab ? "Paper" : tab.url?.absoluteString ?? "Unavailable"))
                        .lineLimit(1).font(PaperTypography.metadata)
                        .foregroundStyle(PaperTypography.readingColor)
                }
                Spacer(minLength: 0)
                if tab.isLoading { ProgressView().controlSize(.small).accessibilityLabel("Loading") }
                Button { close(tab.id) } label: { Image(systemName: "xmark").font(.caption) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close \(tab.title)")
            }
            .padding(10)
        }
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(tab.id == ui.overviewSelectionID ? Color.accentColor : Color.primary.opacity(0.12),
                          lineWidth: tab.id == ui.overviewSelectionID ? 2 : 1))
        .overlay(alignment: .topLeading) {
            if tab.id == browser.activeTabID {
                Text("Current").font(PaperTypography.status).padding(5)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5)).padding(7)
            }
        }
    }
}

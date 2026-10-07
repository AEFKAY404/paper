import SwiftUI

struct HandbookView: View {
    let restartIntroduction: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("PAPER / FIELD GUIDE")
                        .font(.caption.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(.secondary)
                    Text("The web, without the browser.")
                        .font(.system(size: 44, weight: .light, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A quiet guide to moving through Paper.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                section("Getting Started", "Paper keeps the webpage in view. Open the command palette for addresses, search, tabs and browser actions.", shortcuts: [("Open command palette", "⌘L")])
                section("Searching and Navigation", "The new-tab field and command palette accept web addresses or search terms. Google is the default; you can change the provider in Settings.", shortcuts: [("Back", "⌘["), ("Forward", "⌘]"), ("Reload", "⌘R"), ("Stop loading", "⌘.")])
                section("Tabs", "Each tab retains its own page. The temporary overview shows static page previews when available. Type to filter tabs, use arrow keys to select, Return to open, or Escape to close it.", shortcuts: [("Tab overview", "⌘⇧\\"), ("New tab", "⌘T"), ("Close tab", "⌘W"), ("Next tab", "⌃Tab"), ("Previous tab", "⌃⇧Tab")])
                section("Gestures", "WebKit handles history swipes by default. Optional Option-swipe tab switching uses an app-local swipe event, is off by default, and needs physical trackpad verification. Keyboard shortcuts remain available.", shortcuts: [])
                section("Downloads", "When a page starts a download, Paper opens the macOS Save Panel. Choose a file location there. Paper does not yet show download progress or a downloads list.", shortcuts: [])
                section("Settings", "Choose a search provider, restore open tabs, control custom gestures and feedback, or reduce decorative motion. History swipe changes apply to open tabs too.", shortcuts: [("Settings", "⌘,")])
                section("Privacy", "Paper uses WebKit's default persistent website data store. Cookies and site data may persist. Paper does not currently include a private mode, content blocker, or custom tracking protection.", shortcuts: [])
                section("About Paper", "The web, without the browser.", shortcuts: [])
                Button("Replay the introduction") {
                    dismiss()
                    restartIntroduction()
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Opens the three-step introduction")
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(48)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 620, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("paper.handbook")
    }

    private func section(_ title: String, _ body: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 26, weight: .regular, design: .serif))
            Text(body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(shortcuts, id: \.0) { item in
                HStack {
                    Text(item.0)
                    Spacer()
                    Text(item.1)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .font(.callout)
                .frame(maxWidth: 420)
            }
        }
    }
}

import SwiftUI

struct HandbookView: View {
    let restartIntroduction: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("PAPER / FIELD GUIDE")
                        .font(PaperTypography.eyebrow)
                        .tracking(2)
                        .foregroundStyle(.secondary)
                    Text("Paper Handbook")
                        .font(PaperTypography.hero)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A quiet guide to moving through Paper.")
                        .font(PaperTypography.annotation)
                        .foregroundStyle(.secondary)
                }
                section("Getting Started", "Paper keeps the webpage in view. Open the command palette for addresses, search, tabs and browser actions.", shortcuts: [("Open command palette", "⌘L")])
                section("Searching and Navigation", "The new-tab field and command palette accept web addresses or search terms. Google is the default; you can change the provider in Settings.", shortcuts: [("Back", "⌘["), ("Forward", "⌘]"), ("Reload", "⌘R"), ("Stop loading", "⌘.")])
                section("Tabs", "Each tab retains its own page. The temporary overview shows static page previews when available. Type to filter tabs, use arrow keys to select, Return to open, or Escape to close it.", shortcuts: [("Tab overview", "⌘⇧\\"), ("New tab", "⌘T"), ("Close tab", "⌘W"), ("Next tab", "⌃Tab"), ("Previous tab", "⌃⇧Tab")])
                section("Gestures", "WebKit handles history swipes by default. Optional Option-swipe tab switching uses an app-local swipe event, is off by default, and needs physical trackpad verification. Keyboard shortcuts remain available.", shortcuts: [])
                section("Downloads", "When a page starts a download, Paper opens the macOS Save Panel. Choose a file location there. Paper does not yet show download progress or a downloads list.", shortcuts: [])
                section("Settings", "Choose a search provider, control gestures, filter lists, site exceptions and permissions, or clear standard browsing data. History swipe changes apply to open tabs too.", shortcuts: [("Settings", "⌘,")])
                section("Protection", "Paper uses local WebKit content rules from EasyList and EasyPrivacy subsets. Obvious ad regions may show a small Paper placeholder; its close button collapses that region without clicking the ad. WebKit does not provide exact blocker match counts. Open Privacy from the command palette or Privacy menu to review this site's state, toggle its exception and clear its data. Changing protection reloads the page.", shortcuts: [])
                section("Private Tabs", "Private tabs use a temporary WebKit data store shared only with other private tabs. Their URLs are not restored. Global blocking stays active and saved site exceptions are ignored. Private browsing does not make you anonymous to websites, networks, your ISP or employer. Downloads you save remain on disk.", shortcuts: [("New private tab", "⌘⇧N")])
                section("Permissions", "Paper asks before allowing camera, microphone or location. Direct new-tab links open normally; unsolicited scripted popups are blocked, while recognized sign-in or payment popups ask. You can change popup policy in Privacy and revoke saved choices in Settings. macOS may ask separately for device access. Notifications remain managed by WebKit.", shortcuts: [])
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
        .background(PaperSurfaceBackground.color)
        .accessibilityIdentifier("paper.handbook")
    }

    private func section(_ title: String, _ body: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(PaperTypography.sectionHeading)
            Text(body)
                .font(PaperTypography.body)
                .foregroundStyle(PaperTypography.readingColor)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(shortcuts, id: \.0) { item in
                HStack {
                    Text(item.0)
                    Spacer()
                    Text(item.1)
                        .font(PaperTypography.shortcut)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                .font(PaperTypography.supporting)
                .frame(maxWidth: 420)
            }
        }
    }
}

import SwiftUI

struct PrivacyPanelView: View {
    @ObservedObject var browser: BrowserController
    @ObservedObject var blocker: ContentBlockerEngine
    @ObservedObject private var permissions = SitePermissionStore.shared
    let openPrivateTab: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var siteData = SiteDataSummary()
    @State private var clearing = false
    @State private var confirmClear = false

    private var site: String? { SiteIdentity.shared.domain(for: browser.activeTab?.url) }
    private var permissionSite: String? { SiteIdentity.origin(for: browser.activeTab?.url) }
    private var isPrivate: Bool { browser.activeTab?.privacyMode == .private }
    private var protectedHere: Bool {
        blocker.policy.enabled && (isPrivate || blocker.policy.allowsBlocking(browser.activeTab?.url))
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Current tab", value: isPrivate ? "Private" : "Standard")
                LabeledContent("Protection", value: blocker.policy.enabled ? (blocker.isActive ? "On" : "Preparing") : "Off globally")
                if let site {
                    LabeledContent("This site", value: site)
                    if isPrivate {
                        Text("Private tabs use global protection and ignore saved site exceptions.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Site exception", value: blocker.policy.disabledForDomains.contains(site) ? "Protection disabled" : "None")
                        if blocker.policy.enabled {
                            Toggle("Protect this site", isOn: Binding(
                                get: { blocker.policy.allowsBlocking(browser.activeTab?.url) },
                                set: { enabled in
                                    blocker.setDisabled(!enabled, forDomain: site)
                                    browser.reload()
                                }
                            ))
                        }
                    }
                }
                LabeledContent("Ads & trackers", value: protectedHere && blocker.isActive ? "Blocked where supported" : "Inactive on this site")
                LabeledContent("Cosmetic filtering", value: protectedHere && blocker.cosmeticEnabled && blocker.isActive ? "On" : "Off")
            } header: { Text("Privacy") }

            if site != nil {
                Section("Site data") {
                    LabeledContent("Cookies", value: "\(siteData.cookies)")
                    LabeledContent("Local storage", value: siteData.localStorage ? "Present" : "None found")
                    LabeledContent("Cached data", value: siteData.cache ? "Present" : "None found")
                    if siteData.other { LabeledContent("Other website data", value: "Present") }
                    Button("Clear Site Data…", role: .destructive) { confirmClear = true }
                        .disabled(clearing)
                }
            }

            if let permissionSite {
                Section("Permissions · \(permissionSite)") {
                    ForEach(SitePermission.allCases) { permission in
                        if isPrivate {
                            LabeledContent(permission.title, value: "Ask")
                        } else {
                            Picker(permission.title, selection: Binding(
                                get: { permissions.choice(permission, for: permissionSite) },
                                set: { permissions.set($0, for: permission, site: permissionSite) }
                            )) {
                                ForEach(SitePermissionChoice.allCases) { choice in
                                    Text(choice.title).tag(choice)
                                }
                            }
                        }
                    }
                    LabeledContent("Notifications", value: "Managed by WebKit")
                    Text(isPrivate ? "Private tabs ask for each supported permission request and do not save decisions." : "Permission changes apply to future requests. macOS may ask separately for device access.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Private browsing") {
                Button("Open Private Tab") { dismiss(); openPrivateTab() }
                Text("Downloads you save from a private tab remain on disk.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: site == nil ? 350 : 560)
        .accessibilityIdentifier("paper.privacy.panel")
        .background(PaperSurfaceBackground.color)
        .task(id: site) { await refreshData() }
        .confirmationDialog("Clear data for \(site ?? "this site")?", isPresented: $confirmClear) {
            Button("Clear Site Data", role: .destructive) {
                Task {
                    guard let site, let session = browser.activeSession else { return }
                    clearing = true
                    await session.clearSiteData(for: site)
                    siteData = await session.siteDataSummary(for: site)
                    browser.reload()
                    clearing = false
                }
            }
        } message: {
            Text("Cookies and website data for this site will be removed. You may be signed out.")
        }
    }

    private func refreshData() async {
        guard let site, let session = browser.activeSession else { siteData = SiteDataSummary(); return }
        let summary = await session.siteDataSummary(for: site)
        guard !Task.isCancelled, self.site == site else { return }
        siteData = summary
    }
}

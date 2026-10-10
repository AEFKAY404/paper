import SwiftUI

enum AccountSignOutRequest: Equatable {
    case site(String)
    case all

    var title: String {
        switch self {
        case .site(let site): "Sign out of \(site)?"
        case .all: "Sign out of all detected accounts?"
        }
    }

    var actionTitle: String {
        switch self {
        case .site: "Sign Out"
        case .all: "Sign Out of All Detected Accounts"
        }
    }

    func message(sessionCount: Int) -> String {
        switch self {
        case .site(let site):
            "Paper will clear cookies and session storage for \(site) and its subdomains. Preferences stored there may also be removed. Other domains are not selected."
        case .all:
            "Paper will clear cookies and session storage for \(sessionCount) detected sites. Other sites are not selected."
        }
    }
}

struct AccountsView: View {
    @ObservedObject var manager: AccountSessionManager
    @ObservedObject var browser: BrowserController
    @Environment(\.dismiss) private var dismiss
    @State private var pending: AccountSignOutRequest?
    @State private var confirmSignOut = false
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Accounts").font(PaperTypography.sectionHeading)
                    Text("Active sessions detected by Paper")
                        .font(PaperTypography.metadata).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { Task { await manager.refresh() } }
                    .disabled(manager.isRefreshing || manager.isSigningOut)
                    .accessibilityIdentifier("paper.accounts.refresh")
            }

            if manager.isRefreshing && manager.sessions.isEmpty {
                ProgressView("Checking website sessions…")
                    .frame(maxWidth: .infinity, minHeight: 130)
            } else if manager.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No signed-in accounts detected.")
                        .font(PaperTypography.supporting)
                    Text("Sites you sign into can appear here when Paper can identify their session safely.")
                        .font(PaperTypography.metadata).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(manager.sessions) { session in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.providerName).font(PaperTypography.supporting)
                                    Text(session.identityLabel ?? session.registrableDomain)
                                        .font(PaperTypography.metadata).foregroundStyle(.secondary)
                                    Text("Session detected")
                                        .font(PaperTypography.status).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Sign Out") {
                                    pending = .site(session.registrableDomain)
                                    confirmSignOut = true
                                }
                                .disabled(manager.isSigningOut)
                                .accessibilityLabel("Sign out of \(session.providerName)")
                                .accessibilityIdentifier("paper.accounts.signOut.\(session.registrableDomain)")
                            }
                            .padding(.vertical, 12)
                            if session.id != manager.sessions.last?.id { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 360)
                Button("Sign Out of All Detected Accounts…", role: .destructive) {
                    pending = .all
                    confirmSignOut = true
                }
                .disabled(manager.isSigningOut)
                .accessibilityIdentifier("paper.accounts.signOutAll")
            }

            if let feedback {
                Text(feedback).font(PaperTypography.metadata)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Text("Paper does not store passwords or know every site's login state. Private tabs are excluded.")
                .font(PaperTypography.metadata).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 480)
        .background(PaperSurfaceBackground.color)
        .accessibilityIdentifier("paper.accounts.panel")
        .task { await manager.refresh() }
        .onAppear { manager.observeWhileVisible(true) }
        .onDisappear { manager.observeWhileVisible(false) }
        .onChange(of: browser.tabs.map(\.previewRevision)) { _, _ in
            if !manager.isSigningOut { Task { await manager.refresh() } }
        }
        .confirmationDialog(confirmationTitle, isPresented: $confirmSignOut) {
            Button(pending?.actionTitle ?? "Sign Out", role: .destructive) { Task { await signOut() } }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text(pending?.message(sessionCount: manager.sessions.count) ?? "")
        }
    }

    private var confirmationTitle: String {
        pending?.title ?? "Sign out?"
    }

    private func signOut() async {
        guard let pending else { return }
        let count: Int
        switch pending {
        case .site(let site):
            count = await manager.signOut(site: site, browser: browser)
            feedback = manager.sessions.contains(where: { $0.registrableDomain == site })
                ? "Some session evidence remains for \(site)."
                : "Session data cleared for \(site). \(count) open tab\(count == 1 ? "" : "s") refreshed."
        case .all:
            count = await manager.signOutAll(browser: browser)
            feedback = manager.sessions.isEmpty
                ? "Detected session data cleared. \(count) open tab\(count == 1 ? "" : "s") refreshed."
                : "Some session evidence remains."
        }
        self.pending = nil
    }
}

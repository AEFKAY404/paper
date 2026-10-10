import Combine
import Foundation

@MainActor
protocol AccountSessionInspecting {
    func cookieMetadata() async -> [AccountCookieMetadata]
    func clearSessionData(for site: String) async
    func setCookieChangeHandler(_ handler: (@MainActor () -> Void)?)
}

extension AccountSessionInspecting {
    func setCookieChangeHandler(_ handler: (@MainActor () -> Void)?) {}
}

@MainActor
final class AccountSessionManager: ObservableObject {
    @Published private(set) var sessions: [BrowserAccountSession] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSigningOut = false

    private let inspector: any AccountSessionInspecting
    private let detector: AccountDetector
    private var revision = 0
    private var refreshDebounceTask: Task<Void, Never>?

    init(inspector: any AccountSessionInspecting, detector: AccountDetector? = nil) {
        self.inspector = inspector
        self.detector = detector ?? AccountDetector()
    }

    func refresh() async {
        revision += 1
        let current = revision
        isRefreshing = true
        let cookies = await inspector.cookieMetadata()
        guard current == revision else { return }
        sessions = detector.detect(cookies)
        isRefreshing = false
    }

    func observeWhileVisible(_ visible: Bool) {
        if visible {
            inspector.setCookieChangeHandler { [weak self] in
                guard let self, !self.isSigningOut else { return }
                self.refreshDebounceTask?.cancel()
                self.refreshDebounceTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            }
        } else {
            inspector.setCookieChangeHandler(nil)
            refreshDebounceTask?.cancel()
            refreshDebounceTask = nil
        }
    }

    @discardableResult
    func signOut(site: String, browser: BrowserController) async -> Int {
        guard sessions.contains(where: { $0.registrableDomain == site }), !isSigningOut else { return 0 }
        isSigningOut = true
        revision += 1
        await inspector.clearSessionData(for: site)
        let refreshedTabs = browser.reloadStandardTabs(forSites: [site])
        await refresh()
        isSigningOut = false
        return refreshedTabs
    }

    @discardableResult
    func signOutAll(browser: BrowserController) async -> Int {
        guard !isSigningOut else { return 0 }
        let sites = Set(sessions.map(\.registrableDomain))
        guard !sites.isEmpty else { return 0 }
        isSigningOut = true
        revision += 1
        for site in sites.sorted() { await inspector.clearSessionData(for: site) }
        let refreshedTabs = browser.reloadStandardTabs(forSites: sites)
        await refresh()
        isSigningOut = false
        return refreshedTabs
    }
}

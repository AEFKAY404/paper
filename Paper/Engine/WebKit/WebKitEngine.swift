import AppKit
import WebKit

@MainActor
final class WebKitEngine: BrowserEngine {
    let blocker = ContentBlockerEngine()
    private var sessions: [WeakSession] = []
    private var privateStore: WKWebsiteDataStore?

    init(startBlocker: Bool = true) {
        blocker.onChange = { [weak self] in
            guard let self else { return }
            sessions = sessions.filter { $0.value != nil }
            sessions.forEach { $0.value?.updateBlocker() }
            if ProcessInfo.processInfo.environment["PAPER_DIAGNOSTICS"] == "1" {
                NSLog("Paper blocker: %@", blocker.diagnostics)
            }
        }
        if startBlocker { Task { await blocker.start() } }
    }

    func makeSession(privacyMode: TabPrivacyMode) -> any BrowserSession {
        let store: WKWebsiteDataStore
        if privacyMode == .private {
            if privateStore == nil { privateStore = .nonPersistent() }
            store = privateStore!
        } else { store = .default() }
        let session = WebKitSession(websiteDataStore: store, blocker: blocker, privacyMode: privacyMode)
        session.onClose = { [weak self] in
            guard let self else { return }
            if !sessions.contains(where: { $0.value?.privacyMode == .private && $0.value?.isClosed == false }) {
                privateStore = nil
            }
        }
        sessions.append(WeakSession(session))
        return session
    }

    private struct WeakSession {
        weak var value: WebKitSession?
        init(_ value: WebKitSession) { self.value = value }
    }
}

@MainActor
final class WebKitSession: NSObject, BrowserSession, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    var view: NSView { webView }
    var onEvent: ((BrowserEvent) -> Void)?

    private var observations: [NSKeyValueObservation] = []
    private var downloads: [WKDownload] = []
    private var closed = false
    var isClosed: Bool { closed }
    var onClose: (() -> Void)?
    private let identity: BrowserIdentity
    private var identityTask: Task<Void, Never>?
    private var identityReady = false
    private var standardUserAgent: String?
    private var pendingURL: URL?
    private var surfaceColorTask: Task<Void, Never>?
    private var navigationRevision = 0
    private weak var blocker: ContentBlockerEngine?
    let privacyMode: TabPrivacyMode
    private var installedBlockerRules: [WKContentRuleList] = []
    var installedBlockerIdentifiers: [String] { installedBlockerRules.map(\.identifier) }
    private var configuredBlockerRevision = -1
    private var configuredCosmeticHost: String?
    private var statistics = BlockerStatistics()
    private let popupPolicy = PopupPolicy()

    // Only solid, opaque computed CSS colors are useful for a native title bar.
    // Root takes precedence; body supplies the common transparent-root case.
    private static let surfaceColorScript = """
    (() => {
      for (const element of [document.documentElement, document.body]) {
        if (!element) continue;
        const color = getComputedStyle(element).backgroundColor;
        const match = color.match(/^rgba?\\(\\s*(\\d+(?:\\.\\d+)?)\\s*[, ]\\s*(\\d+(?:\\.\\d+)?)\\s*[, ]\\s*(\\d+(?:\\.\\d+)?)(?:\\s*[, /]\\s*(\\d*\\.?\\d+))?\\s*\\)$/i);
        if (!match || (match[4] !== undefined && Number(match[4]) < 0.999)) continue;
        return [Number(match[1]), Number(match[2]), Number(match[3])];
      }
      return null;
    })()
    """

    override convenience init() {
        self.init(websiteDataStore: .default())
    }

    convenience init(blocker: ContentBlockerEngine) {
        self.init(websiteDataStore: .default(), blocker: blocker)
    }

    init(websiteDataStore: WKWebsiteDataStore, identity: BrowserIdentity? = nil,
         blocker: ContentBlockerEngine? = nil, privacyMode: TabPrivacyMode = .standard) {
        let identity = identity ?? .shared
        self.identity = identity
        self.blocker = blocker
        self.privacyMode = privacyMode
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        identity.configure(configuration)
        if let blocker, blocker.policy.enabled {
            for list in blocker.rules { configuration.userContentController.add(list) }
            installedBlockerRules = blocker.rules
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        if blocker != nil { updateBlocker() }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = UserDefaults.standard.object(forKey: "paper.historyGestures") as? Bool ?? true

        observations = [
            webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                Task { @MainActor [weak self] in self?.onEvent?(.urlChanged(webView.url)) }
            },
            webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    let title = webView.title ?? "Untitled"
                    if ProcessInfo.processInfo.environment["PAPER_DIAGNOSTICS"] == "1" {
                        NSLog("Paper page title: %@", title)
                    }
                    self?.onEvent?(.titleChanged(title))
                }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
                Task { @MainActor [weak self] in self?.onEvent?(.loadingChanged(webView.isLoading)) }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    self?.onEvent?(.navigationChanged(canGoBack: webView.canGoBack, canGoForward: webView.canGoForward))
                }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
                Task { @MainActor [weak self] in
                    self?.onEvent?(.navigationChanged(canGoBack: webView.canGoBack, canGoForward: webView.canGoForward))
                }
            }
        ]
        identityTask = Task { [weak self] in
            guard let self else { return }
            let userAgent = await identity.effectiveUserAgent(using: webView)
            guard !closed else { return }
            standardUserAgent = userAgent
            if let userAgent { webView.customUserAgent = userAgent }
            identityReady = true
            if let pendingURL {
                self.pendingURL = nil
                load(pendingURL)
            }
        }
    }

    func load(_ url: URL) {
        guard !closed else { return }
        guard identityReady else { pendingURL = url; return }
        updateBlocker(for: url)
        applyBlocker(for: url)
        if let standardUserAgent {
            webView.customUserAgent = identity.userAgent(for: url, defaultUA: standardUserAgent)
        }
        webView.load(URLRequest(url: url))
    }
    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }
    func reload() { webView.reload() }
    func stop() { webView.stopLoading() }
    func focus() {
        guard let window = webView.window else { return }
        window.makeFirstResponder(webView)
    }
    func setHistorySwipe(enabled: Bool) {
        webView.allowsBackForwardNavigationGestures = enabled
    }
    func refreshSurfaceColor() {
        guard !closed, !webView.isLoading else { return }
        surfaceColorTask?.cancel()
        let revision = navigationRevision
        surfaceColorTask = Task { [weak self] in
            guard let self else { return }
            let result = try? await webView.evaluateJavaScript(Self.surfaceColorScript)
            guard !Task.isCancelled, !closed, navigationRevision == revision else { return }
            let color: NSColor?
            if let values = result as? [NSNumber], values.count == 3,
               values.allSatisfy({ $0.doubleValue.isFinite && (0...255).contains($0.doubleValue) }) {
                color = NSColor(srgbRed: values[0].doubleValue / 255,
                                green: values[1].doubleValue / 255,
                                blue: values[2].doubleValue / 255, alpha: 1)
            } else {
                color = nil
            }
            onEvent?(.surfaceColorChanged(color))
        }
    }
    func snapshot(maxWidth: CGFloat) async -> NSImage? {
        guard !closed, webView.url != nil, !webView.isLoading, webView.bounds.width > 0 else { return nil }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(min(360, max(120, maxWidth))))
        configuration.afterScreenUpdates = false
        let image = try? await webView.takeSnapshot(configuration: configuration)
        return closed ? nil : image
    }
    func siteDataSummary(for site: String) async -> SiteDataSummary {
        await SiteDataManager(store: webView.configuration.websiteDataStore).summary(for: site)
    }
    func clearSiteData(for site: String) async {
        await SiteDataManager(store: webView.configuration.websiteDataStore).clear(site: site)
    }
    func close() {
        guard !closed else { return }
        closed = true
        identityTask?.cancel()
        surfaceColorTask?.cancel()
        identityTask = nil
        pendingURL = nil
        webView.stopLoading()
        observations.removeAll()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: CosmeticFilterEngine.messageName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: VisualBlockerEngine.messageName)
        downloads.forEach { $0.cancel() }
        downloads.removeAll()
        onEvent = nil
        webView.removeFromSuperview()
        onClose?()
        onClose = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        surfaceColorTask?.cancel()
        if ProcessInfo.processInfo.environment["PAPER_DIAGNOSTICS"] == "1" { NSLog("Paper navigation error: %@", error.localizedDescription) }
        onEvent?(.navigationFailed(error.localizedDescription))
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        surfaceColorTask?.cancel()
        if ProcessInfo.processInfo.environment["PAPER_DIAGNOSTICS"] == "1" { NSLog("Paper provisional navigation error: %@", error.localizedDescription) }
        onEvent?(.navigationFailed(error.localizedDescription))
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        surfaceColorTask?.cancel()
        onEvent?(.navigationFailed("The webpage process stopped. Reload to try again."))
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationRevision += 1
        surfaceColorTask?.cancel()
        statistics.cosmeticMatchesAtLoad = 0
        statistics.visualRegionsReplaced = 0
        statistics.visualRegionsCollapsed = 0
        onEvent?(.blockerStatistics(statistics))
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onEvent?(.navigationSucceeded)
        refreshSurfaceColor()
        // A single follow-up handles sites that apply a theme immediately after load.
        let revision = navigationRevision
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard let self, !closed, navigationRevision == revision, !webView.isLoading else { return }
            refreshSurfaceColor()
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let site = SiteIdentity.origin(for: webView.url) ?? "This site"
        let choice: SitePermissionChoice = privacyMode == .private ? .ask : SitePermissionStore.shared.choice(.popups, for: site)
        let disposition = popupPolicy.decide(choice: choice, navigationType: navigationAction.navigationType,
                                              url: navigationAction.request.url, site: site)
        switch disposition {
        case .allow:
            if let url = navigationAction.request.url { onEvent?(.openNewTab(url)) }
        case .ask:
            SitePermissionStore.shared.decide([.popups], site: site, privateTab: privacyMode == .private,
                                              window: webView.window) { [weak self] allowed in
                if allowed, let url = navigationAction.request.url { self?.onEvent?(.openNewTab(url)) }
            }
        case .block: break
        }
        return nil
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let site = SiteIdentity.origin(scheme: origin.protocol, host: origin.host, port: origin.port) ?? origin.host
        let permissions: [SitePermission]
        switch type {
        case .camera: permissions = [.camera]
        case .microphone: permissions = [.microphone]
        case .cameraAndMicrophone: permissions = [.camera, .microphone]
        @unknown default: decisionHandler(.deny); return
        }
        SitePermissionStore.shared.decide(permissions, site: site, privateTab: privacyMode == .private,
                                          window: webView.window) { allowed in
            decisionHandler(allowed ? .grant : .deny)
        }
    }

    func webView(_ webView: WKWebView, requestGeolocationPermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let site = SiteIdentity.origin(scheme: origin.protocol, host: origin.host, port: origin.port) ?? origin.host
        SitePermissionStore.shared.decide([.geolocation], site: site, privateTab: privacyMode == .private,
                                          window: webView.window) { allowed in
            decisionHandler(allowed ? .grant : .deny)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame?.isMainFrame == true {
            updateBlocker(for: navigationAction.request.url)
            applyBlocker(for: navigationAction.request.url)
        }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == VisualBlockerEngine.messageName,
           message.frameInfo.isMainFrame, message.webView === webView,
           let values = message.body as? [String: Any],
           let replaced = values["replaced"] as? NSNumber,
           let collapsed = values["collapsed"] as? NSNumber {
            statistics.visualRegionsReplaced = min(VisualBlockerEngine.maximumOverlaysPerPage, max(0, replaced.intValue))
            statistics.visualRegionsCollapsed = min(statistics.visualRegionsReplaced, max(0, collapsed.intValue))
            if ProcessInfo.processInfo.environment["PAPER_DIAGNOSTICS"] == "1" {
                NSLog("Paper visual blocker: %@", String(describing: values))
            }
            onEvent?(.blockerStatistics(statistics))
            return
        }
        guard message.name == CosmeticFilterEngine.messageName,
              message.frameInfo.isMainFrame, message.webView === webView,
              let count = message.body as? NSNumber else { return }
        statistics.cosmeticMatchesAtLoad = max(0, count.intValue)
        if ProcessInfo.processInfo.environment["PAPER_DIAGNOSTICS"] == "1" {
            NSLog("Paper cosmetic initial matches: %d", statistics.cosmeticMatchesAtLoad)
        }
        onEvent?(.blockerStatistics(statistics))
    }

    func updateBlocker(for url: URL? = nil) {
        guard let blocker, !closed else { return }
        let controller = webView.configuration.userContentController
        let cosmeticHost = (url ?? webView.url)?.host?.lowercased()
        if configuredBlockerRevision != blocker.revision || configuredCosmeticHost != cosmeticHost {
            controller.removeScriptMessageHandler(forName: CosmeticFilterEngine.messageName)
            controller.removeScriptMessageHandler(forName: VisualBlockerEngine.messageName)
            controller.removeAllUserScripts()
            controller.add(self, name: CosmeticFilterEngine.messageName)
            controller.add(self, name: VisualBlockerEngine.messageName)
            if blocker.policy.enabled && blocker.cosmeticEnabled,
               let cosmeticHost,
               let script = CosmeticFilterEngine.script(for: blocker.cosmeticRules,
                                                       disabledDomains: privacyMode == .private ? [] : blocker.policy.disabledForDomains,
                                                       host: cosmeticHost, versionKey: blocker.cosmeticCacheKey) {
                controller.addUserScript(script)
            }
            if blocker.policy.enabled && (privacyMode == .private || blocker.policy.allowsBlocking(url ?? webView.url)) {
                controller.addUserScript(VisualBlockerEngine.script)
            }
            configuredBlockerRevision = blocker.revision
            configuredCosmeticHost = cosmeticHost
        }
        applyBlocker(for: url ?? webView.url)
        if webView.url != nil && (!allowsBlocking(webView.url, blocker: blocker) || !blocker.cosmeticEnabled) {
            webView.evaluateJavaScript("document.getElementById('paper-cosmetic')?.remove()", completionHandler: nil)
        }
        if webView.url != nil && !allowsBlocking(webView.url, blocker: blocker) {
            webView.evaluateJavaScript(VisualBlockerEngine.teardown, completionHandler: nil)
        }
    }

    private func applyBlocker(for url: URL?) {
        guard let blocker, !closed else { return }
        let target = allowsBlocking(url, blocker: blocker) ? blocker.rules : []
        guard target.map(\.identifier) != installedBlockerRules.map(\.identifier) else { return }
        let controller = webView.configuration.userContentController
        installedBlockerRules.forEach { controller.remove($0) }
        target.forEach { controller.add($0) }
        installedBlockerRules = target
    }

    private func allowsBlocking(_ url: URL?, blocker: ContentBlockerEngine) -> Bool {
        privacyMode == .private ? blocker.policy.enabled : blocker.policy.allowsBlocking(url)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        attach(download)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        attach(download)
    }
    private func attach(_ download: WKDownload) {
        downloads.append(download)
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.message = privacyMode.savedDownloadNotice
        panel.begin { result in completionHandler(result == .OK ? panel.url : nil) }
    }
    func downloadDidFinish(_ download: WKDownload) {
        downloads.removeAll { $0 === download }
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeAll { $0 === download }
        onEvent?(.navigationFailed("Download failed: \(error.localizedDescription)"))
    }
}

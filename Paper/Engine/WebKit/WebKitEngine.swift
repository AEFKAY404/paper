import AppKit
import WebKit

@MainActor
final class WebKitEngine: BrowserEngine {
    let blocker = ContentBlockerEngine()
    private var sessions: [WeakSession] = []

    init() {
        blocker.onChange = { [weak self] in
            guard let self else { return }
            sessions = sessions.filter { $0.value != nil }
            sessions.forEach { $0.value?.updateBlocker() }
            if ProcessInfo.processInfo.environment["PAPER_DIAGNOSTICS"] == "1" {
                NSLog("Paper blocker: %@", blocker.diagnostics)
            }
        }
        Task { await blocker.start() }
    }

    func makeSession() -> any BrowserSession {
        let session = WebKitSession(blocker: blocker)
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
    private let identity: BrowserIdentity
    private var identityTask: Task<Void, Never>?
    private var identityReady = false
    private var standardUserAgent: String?
    private var pendingURL: URL?
    private var surfaceColorTask: Task<Void, Never>?
    private var navigationRevision = 0
    private weak var blocker: ContentBlockerEngine?
    private var installedBlockerRules: [WKContentRuleList] = []
    var installedBlockerIdentifiers: [String] { installedBlockerRules.map(\.identifier) }
    private var configuredBlockerRevision = -1
    private var statistics = BlockerStatistics()

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
         blocker: ContentBlockerEngine? = nil) {
        let identity = identity ?? .shared
        self.identity = identity
        self.blocker = blocker
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
        downloads.forEach { $0.cancel() }
        downloads.removeAll()
        onEvent = nil
        webView.removeFromSuperview()
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
        if let url = navigationAction.request.url { onEvent?(.openNewTab(url)) }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame?.isMainFrame == true {
            applyBlocker(for: navigationAction.request.url)
        }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == CosmeticFilterEngine.messageName,
              message.frameInfo.isMainFrame, message.webView === webView,
              let count = message.body as? NSNumber else { return }
        statistics.cosmeticMatchesAtLoad = max(0, count.intValue)
        if ProcessInfo.processInfo.environment["PAPER_DIAGNOSTICS"] == "1" {
            NSLog("Paper cosmetic initial matches: %d", statistics.cosmeticMatchesAtLoad)
        }
        onEvent?(.blockerStatistics(statistics))
    }

    func updateBlocker() {
        guard let blocker, !closed else { return }
        let controller = webView.configuration.userContentController
        if configuredBlockerRevision != blocker.revision {
            controller.removeScriptMessageHandler(forName: CosmeticFilterEngine.messageName)
            controller.removeAllUserScripts()
            controller.add(self, name: CosmeticFilterEngine.messageName)
            if let script = CosmeticFilterEngine.script(for: blocker.cosmeticRules,
                                                       disabledDomains: blocker.policy.disabledForDomains) {
                controller.addUserScript(script)
            }
            configuredBlockerRevision = blocker.revision
        }
        applyBlocker(for: webView.url)
        if !blocker.policy.allowsBlocking(webView.url) {
            webView.evaluateJavaScript("document.getElementById('paper-cosmetic')?.remove()", completionHandler: nil)
        }
    }

    private func applyBlocker(for url: URL?) {
        guard let blocker, !closed else { return }
        let target = blocker.policy.allowsBlocking(url) ? blocker.rules : []
        guard target.map(\.identifier) != installedBlockerRules.map(\.identifier) else { return }
        let controller = webView.configuration.userContentController
        installedBlockerRules.forEach { controller.remove($0) }
        target.forEach { controller.add($0) }
        installedBlockerRules = target
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

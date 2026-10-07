import AppKit
import WebKit

@MainActor
final class WebKitEngine: BrowserEngine {
    func makeSession() -> any BrowserSession { WebKitSession() }
}

@MainActor
final class WebKitSession: NSObject, BrowserSession, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let webView: WKWebView
    var view: NSView { webView }
    var onEvent: ((BrowserEvent) -> Void)?

    private var observations: [NSKeyValueObservation] = []
    private var downloads: [WKDownload] = []
    private var closed = false

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
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
    }

    func load(_ url: URL) {
        guard !closed else { return }
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
    func close() {
        guard !closed else { return }
        closed = true
        webView.stopLoading()
        observations.removeAll()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        downloads.forEach { $0.cancel() }
        downloads.removeAll()
        onEvent = nil
        webView.removeFromSuperview()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        if ProcessInfo.processInfo.environment["PAPER_DIAGNOSTICS"] == "1" { NSLog("Paper navigation error: %@", error.localizedDescription) }
        onEvent?(.navigationFailed(error.localizedDescription))
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        if ProcessInfo.processInfo.environment["PAPER_DIAGNOSTICS"] == "1" { NSLog("Paper provisional navigation error: %@", error.localizedDescription) }
        onEvent?(.navigationFailed(error.localizedDescription))
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onEvent?(.navigationFailed("The webpage process stopped. Reload to try again."))
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onEvent?(.navigationSucceeded)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { onEvent?(.openNewTab(url)) }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
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

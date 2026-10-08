// Run with: DEVELOPER_DIR=<Xcode Developer path> xcrun swift tools/identity_probe.swift
import AppKit
import WebKit

@MainActor
final class Probe: NSObject, WKNavigationDelegate {
    let view: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        if let token = ProcessInfo.processInfo.environment["PAPER_IDENTITY_TOKEN"] {
            configuration.applicationNameForUserAgent = token
        }
        configuration.websiteDataStore = .nonPersistent()
        view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700),
                         configuration: configuration)
        super.init()
        if let customUA = ProcessInfo.processInfo.environment["PAPER_CUSTOM_UA"] {
            view.customUserAgent = customUA
        }
        view.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let expression = ProcessInfo.processInfo.environment["PAPER_IDENTITY_EXPR"] ??
            "JSON.stringify(window.paperIdentity)"
        let delay = Double(ProcessInfo.processInfo.environment["PAPER_IDENTITY_DELAY"] ?? "0") ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            webView.evaluateJavaScript(expression) { result, error in
                print("PAGE_URL=\(webView.url?.absoluteString ?? "nil")")
                print("JS_RESULT=\(result ?? "nil")")
                if let error { print("JS_ERROR=\(error)") }
                CFRunLoopStop(CFRunLoopGetMain())
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        print("NAVIGATION_ERROR=\(error)")
        CFRunLoopStop(CFRunLoopGetMain())
    }
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let probe = Probe()
    let address = ProcessInfo.processInfo.environment["PAPER_IDENTITY_URL"] ??
        "http://127.0.0.1:8765/redirect"
    probe.view.load(URLRequest(url: URL(string: address)!))
    CFRunLoopRun()
}

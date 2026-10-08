import AppKit
import WebKit

/// Builds a desktop WebKit identity from this machine's WebKit and Safari versions.
/// A failed probe leaves WebKit's truthful default plus the Paper app token in place.
@MainActor
final class BrowserIdentity {
    static let shared = BrowserIdentity()

    let applicationToken: String
    let safariVersion: String?
    let compatibilityPolicy: SiteCompatibilityPolicy
    private var cachedUserAgent: String?
    private var pendingResolution: Task<String?, Never>?

    init(applicationVersion: String? = nil, safariVersion: String? = nil,
         compatibilityPolicy: SiteCompatibilityPolicy? = nil) {
        let version = applicationVersion ??
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
        let safeVersion = version.range(of: #"^[0-9]+(?:\.[0-9]+){0,2}$"#, options: .regularExpression) != nil
            ? version : "1.0"
        applicationToken = "Paper/\(safeVersion)"
        self.safariVersion = safariVersion ?? Self.installedSafariVersion()
        self.compatibilityPolicy = compatibilityPolicy ?? SiteCompatibilityPolicy()
    }

    func configure(_ configuration: WKWebViewConfiguration) {
        configuration.applicationNameForUserAgent = applicationToken
        // The recommended mode is desktop on macOS; make that intent explicit.
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
    }

    func effectiveUserAgent(using webView: WKWebView) async -> String? {
        if let cachedUserAgent { return cachedUserAgent }
        if let pendingResolution { return await pendingResolution.value }
        let task = Task<String?, Never> {
            guard let base = try? await webView.evaluateJavaScript("navigator.userAgent") as? String else {
                return nil
            }
            return makeSafariCompatibleUserAgent(from: base)
        }
        pendingResolution = task
        let result = await task.value
        if let result { cachedUserAgent = result }
        pendingResolution = nil
        return result
    }

    func makeSafariCompatibleUserAgent(from observed: String) -> String? {
        guard let safariVersion,
              safariVersion.range(of: #"^[0-9]+(?:\.[0-9]+){0,2}$"#,
                                  options: .regularExpression) != nil,
              observed.hasPrefix("Mozilla/5.0 "),
              !observed.contains("Chrome/") && !observed.contains("Chromium/") else { return nil }
        let base = observed.hasSuffix(" \(applicationToken)")
            ? String(observed.dropLast(applicationToken.count + 1)) : observed
        let range = base.range(of: #"AppleWebKit/([0-9]+(?:\.[0-9]+)+)"#,
                                  options: .regularExpression)
        guard let range else { return nil }
        let engineToken = String(base[range]).replacingOccurrences(of: "AppleWebKit/", with: "")
        if base.contains(" Safari/") { return "\(base) \(applicationToken)" }
        guard base.hasSuffix("(KHTML, like Gecko)") else { return nil }
        return "\(base) Version/\(safariVersion) Safari/\(engineToken) \(applicationToken)"
    }

    func userAgent(for url: URL, defaultUA: String) -> String {
        compatibilityPolicy.resolve(url)?.userAgentOverride ?? defaultUA
    }

    private static func installedSafariVersion() -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari"),
              let bundle = Bundle(url: url) else { return nil }
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}

struct SiteCompatibilityPolicy {
    struct Rule {
        let domain: String
        let userAgentOverride: String?
        let notes: String
    }

    // Deliberately empty: every site receives the same truthful desktop WebKit identity.
    let rules: [Rule]

    init(rules: [Rule] = []) { self.rules = rules }

    func resolve(_ url: URL) -> Rule? {
        guard let host = url.host?.lowercased() else { return nil }
        return rules.first { Self.matches(host: host, domain: $0.domain) }
    }

    static func matches(host: String, domain: String) -> Bool {
        let candidate = domain.lowercased()
        return host == candidate || host.hasSuffix(".\(candidate)")
    }
}

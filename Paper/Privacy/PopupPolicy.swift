import Foundation
import WebKit

/// A conservative decision made before asking WebKit to create a new view.
/// `other` is not proof of absent user intent: OAuth/payment destinations ask.
enum PopupDisposition: Equatable {
    case allow, ask, block
}

@MainActor
final class PopupPolicy {
    private var recentScripted: [String: [Date]] = [:]
    private let interval: TimeInterval = 5
    private let maximumTrackedAttempts = 3

    func decide(choice: SitePermissionChoice, navigationType: WKNavigationType,
                url: URL?, site: String, now: Date = Date()) -> PopupDisposition {
        if choice == .block { return .block }
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return .block }
        if navigationType == .linkActivated { return .allow }
        if recentScripted.count >= 64 && recentScripted[site] == nil {
            recentScripted = recentScripted.filter { $0.value.last.map { now.timeIntervalSince($0) < interval } ?? false }
            if recentScripted.count >= 64,
               let oldest = recentScripted.min(by: { ($0.value.last ?? .distantPast) < ($1.value.last ?? .distantPast) }) {
                recentScripted.removeValue(forKey: oldest.key)
            }
        }
        let attempts = (recentScripted[site] ?? []).filter { now.timeIntervalSince($0) < interval }
        recentScripted[site] = Array((attempts + [now]).suffix(maximumTrackedAttempts))
        if choice == .allow { return attempts.count < maximumTrackedAttempts ? .allow : .block }
        if attempts.count >= 2 { return .block }
        if Self.isAuthenticationOrPayment(url) { return .ask }
        return .block
    }

    private static func isAuthenticationOrPayment(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        return ["accounts.google.com", "login.microsoftonline.com", "appleid.apple.com",
                "paypal.com", "checkout.stripe.com"].contains(host) ||
            ["/oauth", "/authorize", "/signin", "/sign-in", "/login", "/checkout", "/payment"].contains {
                path == $0 || path.hasPrefix($0 + "/")
            }
    }
}

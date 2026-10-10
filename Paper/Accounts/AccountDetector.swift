import Foundation

/// Metadata only. Cookie values never cross the WebKit adapter boundary.
struct AccountCookieMetadata: Equatable {
    let name: String
    let domain: String
    let isSecure: Bool
    let isHTTPOnly: Bool
    let isPersistent: Bool
}

enum AccountConfidence: String, Equatable {
    case high
}

struct BrowserAccountSession: Identifiable, Equatable {
    var id: String { registrableDomain }
    let registrableDomain: String
    let providerName: String
    let identityLabel: String?
    let confidence: AccountConfidence
    let lastObserved: Date
}

/// Small, source-controlled catalog. A match is evidence of a session, not proof of login.
struct AccountProviderAdapter {
    static let catalogVersion = 1
    let domain: String
    let displayName: String
    let cookieNames: Set<String>
    let minimumMatches: Int

    static let builtIn: [Self] = [
        .init(domain: "google.com", displayName: "Google",
              cookieNames: ["sid", "hsid", "ssid", "__secure-1psid", "__secure-3psid"], minimumMatches: 2),
        .init(domain: "github.com", displayName: "GitHub",
              cookieNames: ["user_session", "__host-user_session_same_site"], minimumMatches: 1),
        .init(domain: "reddit.com", displayName: "Reddit",
              cookieNames: ["reddit_session", "token_v2"], minimumMatches: 1),
        .init(domain: "apple.com", displayName: "Apple",
              cookieNames: ["myacinfo"], minimumMatches: 1),
        .init(domain: "amazon.com", displayName: "Amazon",
              cookieNames: ["at-main", "sess-at-main"], minimumMatches: 1)
    ]
}

struct AccountDetector {
    let siteIdentity: SiteIdentity
    let adapters: [AccountProviderAdapter]

    init(siteIdentity: SiteIdentity = .shared, adapters: [AccountProviderAdapter]? = nil) {
        self.siteIdentity = siteIdentity
        self.adapters = adapters ?? AccountProviderAdapter.builtIn
    }

    func detect(_ cookies: [AccountCookieMetadata], at date: Date = Date()) -> [BrowserAccountSession] {
        let grouped = Dictionary(grouping: cookies) { cookie in
            siteIdentity.domain(forHost: cookie.domain) ?? ""
        }
        return grouped.compactMap { site, cookies -> BrowserAccountSession? in
            guard site.contains("."), !cookies.isEmpty else { return nil }
            let strong = cookies.filter { $0.isSecure && $0.isHTTPOnly }
            let names = Set(strong.map { $0.name.lowercased() })
            let adapter = adapters.first { $0.domain == site }
            let knownCount = adapter.map { names.intersection($0.cookieNames).count } ?? 0
            let providerMatch = adapter.map { knownCount >= $0.minimumMatches } ?? false
            let genericMatches = names.filter(Self.isGenericAuthName)
            guard providerMatch || genericMatches.count >= 2 else { return nil }
            return BrowserAccountSession(registrableDomain: site,
                                         providerName: adapter?.displayName ?? site,
                                         identityLabel: nil,
                                         confidence: .high,
                                         lastObserved: date)
        }.sorted { $0.providerName.localizedCaseInsensitiveCompare($1.providerName) == .orderedAscending }
    }

    private nonisolated static func isGenericAuthName(_ name: String) -> Bool {
        ["auth", "login", "access_token", "refresh_token", "id_token", "user_session", "sessionid"]
            .contains { name.contains($0) }
    }
}

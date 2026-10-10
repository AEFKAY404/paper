import Foundation
import Testing
import WebKit
@testable import Paper

@MainActor
struct AccountTests {
    private let detector = AccountDetector()

    @Test func knownProvidersNeedStrongCookieMetadata() {
        let good = cookie("user_session", ".github.com")
        #expect(detector.detect([good]).map(\.registrableDomain) == ["github.com"])
        #expect(detector.detect([cookie("user_session", ".github.com", secure: false)]).isEmpty)
        #expect(detector.detect([cookie("user_session", ".github.com", httpOnly: false)]).isEmpty)
        #expect(detector.detect([cookie("_octo", ".github.com")]).isEmpty)
        #expect(detector.detect([cookie("consent", ".github.com"), cookie("analytics", ".github.com")]).isEmpty)
        #expect(detector.detect([cookie("SID", ".google.com")]).isEmpty)
        #expect(detector.detect([cookie("SID", ".google.com"), cookie("HSID", "accounts.google.com")]).count == 1)
    }

    @Test func hostedDomainsAndUnknownProvidersStaySeparate() {
        let detected = detector.detect([
            cookie("auth_session", "foo.github.io"), cookie("refresh_token", "foo.github.io"),
            cookie("auth_session", "bar.github.io"), cookie("refresh_token", "bar.github.io"),
            cookie("auth_session", "news.example.co.uk"), cookie("refresh_token", "shop.example.co.uk"),
            cookie("sessionid", "example.com")
        ])
        #expect(Set(detected.map(\.registrableDomain)) == ["foo.github.io", "bar.github.io", "example.co.uk"])
        #expect(detected.allSatisfy { $0.identityLabel == nil && $0.confidence == .high })
    }

    @Test func destructiveConfirmationsNameTheirScope() {
        let site = AccountSignOutRequest.site("github.com")
        #expect(site.title.contains("github.com"))
        #expect(site.message(sessionCount: 2).contains("Other domains are not selected"))
        let all = AccountSignOutRequest.all
        #expect(all.actionTitle == "Sign Out of All Detected Accounts")
        #expect(all.message(sessionCount: 2).contains("2 detected sites"))
        #expect(all.message(sessionCount: 2).contains("Other sites are not selected"))
    }

    @Test func inspectorNeverReturnsCookieValuesAndClearIsScoped() async throws {
        let store = WKWebsiteDataStore.nonPersistent()
        let github = try #require(HTTPCookie(properties: [.domain: ".github.com", .path: "/",
                                                               .name: "user_session", .value: "SECRET_VALUE",
                                                               .secure: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE"]))
        let unrelated = try #require(HTTPCookie(properties: [.domain: "example.com", .path: "/",
                                                                  .name: "auth_session", .value: "OTHER_SECRET"]))
        await withCheckedContinuation { continuation in
            store.httpCookieStore.setCookie(github) { continuation.resume() }
        }
        await withCheckedContinuation { continuation in
            store.httpCookieStore.setCookie(unrelated) { continuation.resume() }
        }
        let inspector = WebKitAccountInspector(store: store)
        let metadata = await inspector.cookieMetadata()
        #expect(metadata.count == 2)
        #expect(metadata.contains { $0.name == "user_session" && $0.domain == ".github.com" && $0.isSecure && $0.isHTTPOnly })
        await inspector.clearSessionData(for: "github.com")
        let remaining = await inspector.cookieMetadata()
        #expect(remaining.map(\.name) == ["auth_session"])
    }

    @Test func privateStoreIsNeverIncludedInStandardInventory() async throws {
        let standard = WKWebsiteDataStore.nonPersistent()
        let privateStore = WKWebsiteDataStore.nonPersistent()
        let privateCookie = try #require(HTTPCookie(properties: [.domain: "github.com", .path: "/",
                                                                      .name: "user_session", .value: "PRIVATE_VALUE",
                                                                      .secure: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE"]))
        await withCheckedContinuation { continuation in
            privateStore.httpCookieStore.setCookie(privateCookie) { continuation.resume() }
        }
        let standardInspector = WebKitAccountInspector(store: standard)
        #expect(await standardInspector.cookieMetadata().isEmpty)
        #expect(await WebKitAccountInspector(store: privateStore).cookieMetadata().count == 1)
    }

    private func cookie(_ name: String, _ domain: String, secure: Bool = true,
                        httpOnly: Bool = true) -> AccountCookieMetadata {
        .init(name: name, domain: domain, isSecure: secure,
              isHTTPOnly: httpOnly, isPersistent: true)
    }
}

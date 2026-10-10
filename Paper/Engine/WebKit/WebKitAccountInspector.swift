import Foundation
import WebKit

/// The only Accounts component that handles WebKit data and HTTPCookie objects.
@MainActor
final class WebKitAccountInspector: NSObject, AccountSessionInspecting, WKHTTPCookieStoreObserver {
    private let store: WKWebsiteDataStore
    private var cookieChangeHandler: (@MainActor () -> Void)?
    private var observing = false

    init(store: WKWebsiteDataStore? = nil) {
        self.store = store ?? .default()
        super.init()
    }

    func setCookieChangeHandler(_ handler: (@MainActor () -> Void)?) {
        cookieChangeHandler = handler
        if handler != nil, !observing {
            store.httpCookieStore.add(self)
            observing = true
        } else if handler == nil, observing {
            store.httpCookieStore.remove(self)
            observing = false
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        cookieChangeHandler?()
    }

    func cookieMetadata() async -> [AccountCookieMetadata] {
        let cookies = await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        return cookies.map {
            AccountCookieMetadata(name: $0.name, domain: $0.domain,
                                  isSecure: $0.isSecure, isHTTPOnly: $0.isHTTPOnly,
                                  isPersistent: $0.expiresDate != nil)
        }
    }

    func clearSessionData(for site: String) async {
        await SiteDataManager(store: store).clearSessionData(for: site)
    }
}

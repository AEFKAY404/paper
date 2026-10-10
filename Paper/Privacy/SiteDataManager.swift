import Foundation
import WebKit

struct BrowsingDataSelection: Equatable {
    var cookies = true
    var localStorage = true
    var caches = true
    var otherWebsiteData = true

    var types: Set<String> {
        var result = Set<String>()
        if cookies { result.insert(WKWebsiteDataTypeCookies) }
        if localStorage { result.insert(WKWebsiteDataTypeLocalStorage) }
        if caches { result.formUnion([WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache]) }
        if otherWebsiteData {
            result.formUnion(WKWebsiteDataStore.allWebsiteDataTypes().subtracting([
                WKWebsiteDataTypeCookies, WKWebsiteDataTypeLocalStorage,
                WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache
            ]))
        }
        return result
    }
}

@MainActor
final class SiteDataManager {
    private let store: WKWebsiteDataStore

    init(store: WKWebsiteDataStore) { self.store = store }
    convenience init() { self.init(store: .default()) }

    func summary(for site: String) async -> SiteDataSummary {
        let records = await records(for: site, types: WKWebsiteDataStore.allWebsiteDataTypes())
        let cookies = await allCookies().filter { matches($0.domain, site: site) }
        let types = records.reduce(into: Set<String>()) { $0.formUnion($1.dataTypes) }
        return SiteDataSummary(cookies: cookies.count,
                               localStorage: types.contains(WKWebsiteDataTypeLocalStorage),
                               cache: !types.isDisjoint(with: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache]),
                               other: !types.subtracting([WKWebsiteDataTypeCookies, WKWebsiteDataTypeLocalStorage,
                                                          WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache,
                                                          WKWebsiteDataTypeFetchCache]).isEmpty)
    }

    func clear(site: String) async {
        let records = await records(for: site, types: WKWebsiteDataStore.allWebsiteDataTypes())
        await withCheckedContinuation { continuation in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) {
                continuation.resume()
            }
        }
        // Cookies may have no matching data record; remove precisely scoped cookies too.
        for cookie in await allCookies() where matches(cookie.domain, site: site) {
            await withCheckedContinuation { continuation in
                store.httpCookieStore.delete(cookie) { continuation.resume() }
            }
        }
    }

    /// Clears session-bearing storage for a registrable site without removing its caches.
    func clearSessionData(for site: String) async {
        let types: Set<String> = [WKWebsiteDataTypeCookies, WKWebsiteDataTypeLocalStorage,
                                  WKWebsiteDataTypeSessionStorage, WKWebsiteDataTypeIndexedDBDatabases,
                                  WKWebsiteDataTypeServiceWorkerRegistrations, WKWebsiteDataTypeWebSQLDatabases]
        let matchingRecords = await records(for: site, types: types)
        await withCheckedContinuation { continuation in
            store.removeData(ofTypes: types, for: matchingRecords) { continuation.resume() }
        }
        // Some cookies are absent from website-data records. Delete those by domain too.
        for cookie in await allCookies() where matches(cookie.domain, site: site) {
            await withCheckedContinuation { continuation in
                store.httpCookieStore.delete(cookie) { continuation.resume() }
            }
        }
    }

    func clearAll(_ selection: BrowsingDataSelection) async {
        guard !selection.types.isEmpty else { return }
        let records = await allRecords(types: selection.types)
        await withCheckedContinuation { continuation in
            store.removeData(ofTypes: selection.types, for: records) { continuation.resume() }
        }
        if selection.cookies {
            for cookie in await allCookies() {
                await withCheckedContinuation { continuation in
                    store.httpCookieStore.delete(cookie) { continuation.resume() }
                }
            }
        }
    }

    private func records(for site: String, types: Set<String>) async -> [WKWebsiteDataRecord] {
        await allRecords(types: types).filter { matches($0.displayName, site: site) }
    }

    private func allRecords(types: Set<String>) async -> [WKWebsiteDataRecord] {
        await withCheckedContinuation { continuation in
            store.fetchDataRecords(ofTypes: types) { continuation.resume(returning: $0) }
        }
    }

    private func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    private func matches(_ host: String, site: String) -> Bool {
        SiteIdentity.shared.domain(forHost: host) == site
    }
}

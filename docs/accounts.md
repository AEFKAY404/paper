# Accounts V1

Accounts is a temporary native sheet opened from the command palette, the Accounts menu, or the voice command “Open accounts.” It lists **active website sessions detected by Paper**, not passwords or every login. The list contains standard-browsing sessions only. No account history or identity is persisted by Paper.

## Detection

`WebKitAccountInspector` reads `WKHTTPCookieStore` from WebKit's default persistent website data store and immediately converts cookies to **name, domain, Secure, HttpOnly, and persistence metadata**. Values remain inside the adapter and are never sent to the Accounts view, logged, or stored by Paper. `AccountDetector` groups names by the bundled Public Suffix List, including hosted/private suffixes such as `github.io`. A site appears only when secure, HttpOnly cookies match either the small source-controlled provider catalog (version 1: Google, GitHub, Reddit, Apple, Amazon) or at least two generic authentication-related names. Consent, analytics, and ordinary preference cookies do not qualify. The list refreshes when opened, on manual Refresh, after observed navigation while open, and on cookie change notifications while the sheet is visible. There is no idle polling.

Cookie metadata is **evidence**, not proof that a website currently considers the user signed in. Paper therefore says “Session detected.” It does not infer a username or email from cookies. No page DOM, credentials, tokens, hidden fields, or provider account APIs are inspected. A provider with multiple signed-in identities remains one domain entry unless a future safe source can distinguish them. Sites using non-cookie authentication, unknown cookie names, non-HttpOnly tokens, or one generic session cookie may be absent. The adapter catalog is deliberately small and may need updating as sites change their cookie names.

## Sign Out

Each Sign Out action requires native confirmation. Paper clears cookies plus WebKit's local storage, session storage, IndexedDB, service-worker registrations, and legacy WebSQL records for the selected **registrable domain and its subdomains**. Browser caches are left alone. Data records whose names cannot be mapped reliably to that domain are not deleted. Site preferences stored in these categories may also be removed. The action reloads affected open **standard** tabs; other domains' tabs and all private tabs remain untouched. The entry is refreshed afterward. “Sign Out of All Detected Accounts” has a separate confirmation and applies this same operation to each currently detected domain, without a global data wipe. If session evidence remains after clearing, the UI says so rather than claiming success.

This clears local browser session material. It does not call a website's logout endpoint or revoke server-side sessions, OAuth grants, or sessions on other devices. Federated sign-in can span multiple registrable domains. Clearing one domain may leave a related domain signed in or let a site establish a new cookie when an open page reloads. Paper names the exact domain scope in confirmation.

## Architecture and privacy

`AccountSessionManager` owns ephemeral engine-neutral `BrowserAccountSession` models and coordinates `AccountDetector`, the WebKit inspector, and `BrowserController.reloadStandardTabs(forSites:)`. `AccountsView` sees models and asks the manager to sign out; it never sees `HTTPCookie` or `WKWebsiteDataStore`. `SiteDataManager` performs record and cookie deletion using the existing Public Suffix List mapping. Voice and palette use the shared `BrowserActionRouter`; neither can trigger Sign Out without the native confirmation.

No Accounts information is uploaded or sent to a Paper backend, and no credential or cookie value is shown. Private tabs use a separate nonpersistent WebKit store and are never inventoried by this feature. Opening Accounts from a private tab still shows only the standard-browsing list; it does not merge private data.

## Verification

Automated fixtures cover secure/HttpOnly detection, non-auth cookie rejection, provider and unknown-domain matching, hosted-domain grouping, metadata-only inventory, domain-scoped cookie deletion, standard-tab refresh and private-tab exclusion, voice/palette routing, and the Accounts menu/sheet. These tests use synthetic cookies and no real credentials.

The signed UI test captured the [Accounts empty state](screenshots/accounts-empty.png) in light appearance. The sheet is transient and does not add browser chrome.

**Hands-on validation remains:** sign in with accounts controlled by the tester on Google, GitHub, Reddit, and another provider if practical; confirm detection, sign-out, affected-tab refresh, unrelated-site preservation, private separation, and VoiceOver focus. Real login/logout states, multiple identities, provider cookie changes, and federated sign-in behavior were not established by local fixtures.

WebKit API references: [website data stores](https://developer.apple.com/documentation/webkit/wkwebsitedatastore), [cookie stores](https://developer.apple.com/documentation/webkit/wkhttpcookiestore), [website data records](https://developer.apple.com/documentation/webkit/wkwebsitedatarecord).

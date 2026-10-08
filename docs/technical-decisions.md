# Technical decisions

## 9 October 2026 — Audit uBlock, keep Paper's blocker unchanged

The [feasibility audit](ublock-feasibility.md) found uBO Lite's compile-time/declarative separation useful as an architectural model, while its Safari WebExtension APIs are unavailable to Paper's embedded WKWebView. Paper should independently extend its Swift parser only for semantics that WebKit can execute reliably, then improve static cosmetics. The [Blocker V2 architecture](blocker-v2-architecture.md) is a staged proposal, not an implementation decision. No uBO code was copied; [licensing review](ublock-licensing.md) is required before any direct reuse. Generic scriptlets, response rewriting, exact blocker-match counts, and YouTube-specific mitigation remain unsupported.

## 7 October 2026 — WebKit is the primary macOS engine

The native macOS product needs a working browser surface, persistent tabs, and unobtrusive interaction. WebKit meets the Phase 1A requirements and fits SwiftUI/AppKit directly. The CEF investigation exposed a custom application lifecycle, helper bundles, framework packaging, signing, and maintenance costs. Paper therefore uses WebKit. The CEF findings remain in [cef-feasibility.md](cef-feasibility.md) and [cef-lifecycle-blocker.md](cef-lifecycle-blocker.md) as superseded records.

The `BrowserEngine` boundary remains. `BrowserController` and session snapshots contain no WebKit types. A future engine can implement the same session commands and events, though its capabilities and privacy behavior would still require separate assessment.

## Lifecycle and data

SwiftUI `@main` and `WindowGroup` own the app lifecycle. A narrow `NSApplicationDelegate` hook persists and closes sessions at termination. Each tab keeps its WebKit view alive until the tab is closed. Session restoration stores URLs and active index, since WebKit view objects cannot be serialized.

## Gestures and downloads

WebKit provides native history swipes. Optional tab switching uses an explicit Option-modified discrete swipe and remains off by default to avoid claiming ordinary scrolling. Downloads use `WKDownloadDelegate` and `NSSavePanel`; the app has user-selected read/write sandbox entitlement. These paths need hands-on confirmation before Phase 1A sign-off.

## 8 October 2026 — Safari-compatible desktop identity

The default embedded WebKit UA caused Google to serve a compact Search layout in controlled signed-out tests. Adding only `applicationNameForUserAgent` produced the same layout. Adding the installed Safari's `Version` and `Safari` tokens to WebKit's actual engine and platform UA produced the modern desktop layout in the same WebKit harness. Paper therefore uses that identity plus its own version token for all new WebKit sessions, with explicit desktop content mode. The site override policy remains empty. This is centralized in the adapter so a future engine can identify itself independently. Paper does not globally spoof Chrome or synthesize Chromium APIs. See [web-compatibility.md](web-compatibility.md) for the measurements, comparison limits, and cross-site observations.

## 8 October 2026 — Conservative native content blocking

Paper uses `WKContentRuleList` rather than a Swift network proxy. The installed WebKit rejected an initial URL expression with alternation; the simpler host expression was compiled and tested in WebKit. EasyList/EasyPrivacy syntax is not silently treated as equivalent to WebKit syntax. A third-party-only, non-document rule subset, explicit caps, and per-site bypass favor predictable browsing while coverage is measured. Compiled lists are versioned and source-hashed, and a new source set replaces the previous one only after all its chunks compile. A fixed local `WKUserScript` handles basic cosmetic CSS separately. No rule-match callback exists in the supported WKWebView API, so Paper reports unavailable network counters rather than estimates. See [content-blocker.md](content-blocker.md).

## 8 October 2026 — Private stores and site identity

Private tabs use a shared `WKWebsiteDataStore.nonPersistent()` while any private tab remains, and never enter the URL restoration snapshot. The store is allocated by `WebKitEngine`, not the controller. This preserves a common private session for private tabs while separating it from standard browsing. Private tabs retain global blocking but ignore persistent site exceptions and remembered permissions. Downloaded files remain user-selected filesystem artifacts.

Site settings use the bundled Public Suffix List rather than splitting a host on dots. Exact, wildcard and exception rules and the list's private section keep hosted sites distinct. The list is an offline snapshot and has no automatic update mechanism in Phase 2B. WebKit data records are filtered by this site key; ambiguous records are left alone by the current-site clear action.

Only permissions with public WebKit hooks or a Paper-owned popup routing path are offered as editable decisions. Permission choices use the requesting origin rather than the broader registrable site, preventing approval on one subdomain from granting another. Notifications remain WebKit-managed. A remembered Allow still passes through macOS device authorization. See [site-permissions.md](site-permissions.md).

## 9 October 2026 — Do not ship YouTube response rewriting

Paper's signed-out WebKit diagnostic reproduced a video ad carried alongside first-party player metadata. Test-only removal of ad arrays from `/youtubei/v1/player` responses did not stop the pre-roll. Removing the arrays from `ytInitialPlayerResponse` correlated with an approximately 26-second wait before normal playback in two runs. This is too large a playback regression for a default or opt-in product feature without broader evidence. The existing blocker stack and per-site bypass remain the only shipped controls. See [youtube-blocking.md](youtube-blocking.md).

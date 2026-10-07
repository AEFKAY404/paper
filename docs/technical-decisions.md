# Technical decisions

## 7 October 2026 — WebKit is the primary macOS engine

The native macOS product needs a working browser surface, persistent tabs, and unobtrusive interaction. WebKit meets the Phase 1A requirements and fits SwiftUI/AppKit directly. The CEF investigation exposed a custom application lifecycle, helper bundles, framework packaging, signing, and maintenance costs. Paper therefore uses WebKit. The CEF findings remain in [cef-feasibility.md](cef-feasibility.md) and [cef-lifecycle-blocker.md](cef-lifecycle-blocker.md) as superseded records.

The `BrowserEngine` boundary remains. `BrowserController` and session snapshots contain no WebKit types. A future engine can implement the same session commands and events, though its capabilities and privacy behavior would still require separate assessment.

## Lifecycle and data

SwiftUI `@main` and `WindowGroup` own the app lifecycle. A narrow `NSApplicationDelegate` hook persists and closes sessions at termination. Each tab keeps its WebKit view alive until the tab is closed. Session restoration stores URLs and active index, since WebKit view objects cannot be serialized.

## Gestures and downloads

WebKit provides native history swipes. Optional tab switching uses an explicit Option-modified discrete swipe and remains off by default to avoid claiming ordinary scrolling. Downloads use `WKDownloadDelegate` and `NSSavePanel`; the app has user-selected read/write sandbox entitlement. These paths need hands-on confirmation before Phase 1A sign-off.

# WebKit integration and future extension points

## Phase 1A adapter

`WebKitEngine` creates a `WebKitSession` for each tab. Each session owns one `WKWebView`, the default persistent `WKWebsiteDataStore`, navigation/UI/download delegates, and KVO observers for URL, title, loading, and history availability. Callbacks become engine-neutral `BrowserEvent` values. All UI and WebKit work is main-actor isolated. `BrowserSurface` hosts the existing view through `NSViewRepresentable`; view updates do not allocate a new web view.

Navigation errors are surfaced in the shell; cancelled provisional loads are ignored because they commonly arise when another navigation replaces a load. A successful load clears prior errors. `target=_blank` and other new-window requests with a URL create a controller tab. `WKDownload` asks for a destination with `NSSavePanel`. Closing a session cancels active downloads.

WebKit's `allowsBackForwardNavigationGestures` handles history swipes; the separate `GestureEngine` maps only deliberate Option swipes to tab actions. All gesture actions have keyboard commands.

## Future Phase 2 privacy investigation

WebKit offers `WKContentRuleList` / `WKContentRuleListStore` for compiled content blocking rules, `WKWebsiteDataStore` for persistent or nonpersistent storage, cookie APIs, and `WKUserScript` for page scripts. These are possible adapter extensions, not current privacy features. Private browsing would need nonpersistent data stores and explicit boundaries between private and normal sessions. Per-site permission behavior needs evaluation in the supported WebKit release.

Content rules are not a general-purpose network interception API. Filter-list syntax and semantics may need translation; cosmetic filtering and CNAME-based tracking defenses cannot be assumed equivalent to Chromium extension APIs. Fingerprinting defenses and arbitrary request modification require separate feasibility work. No Brave-like parity is claimed.

## Future Phase 3 automation investigation

A controlled `BrowserAutomation` interface could expose scoped operations for JavaScript evaluation, DOM queries/content extraction, navigation, element interaction, and screenshots. Implementations must enforce page scope, permissions, and user intent; provider integrations (Ollama, LM Studio, OpenAI-compatible and other cloud APIs) would call that interface, not `WKWebView` or native app capabilities directly. Cross-origin frames, isolated script worlds, page security policy, and permission prompts constrain automation. No AI integration is included in Phase 1A.

Apple references: [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview), [WKDownloadDelegate](https://developer.apple.com/documentation/webkit/wkdownloaddelegate), [WKContentRuleList](https://developer.apple.com/documentation/webkit/wkcontentrulelist), [WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore), [WKUserScript](https://developer.apple.com/documentation/webkit/wkuserscript).

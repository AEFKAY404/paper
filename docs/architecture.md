# Paper architecture — Phase 2A

Paper is a SwiftUI macOS app with a `WindowGroup` and a Settings scene. AppKit supplies native event monitoring, window integration, and the rendering view host. The visible shell has no permanent address bar, tab strip, or toolbar. Native SwiftUI views provide the new-tab search surface, optional introduction, and built-in handbook.

```text
PaperApp → ContentView / temporary overlays / GestureEngine
         → BrowserActionRouter (palette, menus, keyboard)
         → BrowserController → BrowserEngine → WebKitEngine
                                       session → WKWebView
         → TabPreviewStore → BrowserSession.snapshot → WKWebView.takeSnapshot
         → SessionStore (URL snapshots)
         → Privacy/ContentBlockerEngine → WKContentRuleListStore
                                      → compiled rules / cosmetic WKUserScript
```

`BrowserController` owns tab order, active tab, metadata, navigation commands, and persistence. It knows only `BrowserEngine` and `BrowserSession`, whose rendering surface is the AppKit `NSView` boundary. The SwiftUI shell sends commands to the controller; it never accesses `WKWebView`. The WebKit adapter owns one persistent `WKWebView` per tab, its delegates and observations. `BrowserSurface` attaches that view to the active tab container without recreating it during SwiftUI updates. Closing a tab stops loading, detaches delegates, cancels its downloads, and removes the view. Application termination saves the URL snapshot and closes sessions.

`SessionStore` saves ordered URLs, explicit new-tab/webpage kinds, and the active index in `UserDefaults`. It restores one session for each saved tab, then activates the saved index. Older URL-only snapshots remain readable. This intentionally does not serialize WebKit objects, form values, history, or page scripts. Website data uses WebKit's default persistent data store.

The controller records a requested URL before a load begins and ignores transient nil URL observations from WebKit. This keeps the restore snapshot valid if Paper quits during navigation.

The native window keeps its AppKit traffic lights. SwiftUI's supported hidden-title-bar style removes the title-bar backing so the content color shows through; no custom title bar or controls are created. `PaperSurfaceBackground` supplies the same semantic `NSColor.windowBackgroundColor` to native SwiftUI surfaces and the window. For webpage tabs, `WebKitSession` evaluates top-level computed CSS background colors after navigation, preferring an opaque root color and then an opaque body color. `BrowserController` stores the result per tab, and `ContentView` applies the active tab's color to the full-window background and `NSWindow.backgroundColor`. The web view stays below the native window controls. A transparent or unsupported background uses the semantic window color. Activation and one post-load recheck allow common theme changes without polling. The color is transient and is recalculated after session restoration.

Phase 1B keeps navigation and tab state in `BrowserController`. The overview is a SwiftUI overlay backed by `TabPreviewStore`; it never creates preview web views. The store asks existing sessions for asynchronous `WKWebView.takeSnapshot` images only when visible cards need them. It limits captures to two at once and caches at most 12 images or 24 MiB. A tab revision changes on navigation completion or failure, invalidating a stale preview. Dismissal and closure cancel or discard obsolete results. New tabs use a native SwiftUI preview. `BrowserActionRouter` is shared by palette, menus, and keyboard routing. `GestureEngine` only interprets optional, app-local `NSEvent.swipe` events; WebKit retains native history swipes. Live web views switch immediately, with only lightweight native feedback animated.

The app retains the original `ark.Paper` bundle identifier and App Sandbox. Outgoing network access and user-selected read/write access are enabled for browsing and Save Panel downloads.

Phase 1B.1 centralizes desktop browser identity in `BrowserIdentity`, inside the WebKit adapter. The adapter obtains its own default WebKit UA, combines its engine token with the installed Safari version and Paper version, and sets the result before the session's first URL request. `SiteCompatibilityPolicy` is an empty extension point. `BrowserController`, SwiftUI overlays, gesture routing and tab persistence do not know about UA strings. New sessions receive the current identity; live sessions are not recreated when an app update changes it. See [web-compatibility.md](web-compatibility.md) for measured behavior and diagnostic commands.

See [webkit-integration.md](webkit-integration.md) for adapter behavior and [engine-migration.md](engine-migration.md) for the migration record.

Phase 2A adds `ContentBlockerEngine` outside the controller and SwiftUI shell. It owns bundled EasyList/EasyPrivacy source metadata, conservative parsing, versioned compiled-rule caching, periodic/manual updates, and per-site policy. `WebKitEngine` attaches the current compiled rules and fixed cosmetic script to each session's `WKWebViewConfiguration`, then updates the user content controller of live sessions when rules change. `BrowserController` receives only an engine-neutral ephemeral statistics event. See [content-blocker.md](content-blocker.md) and [filter-list-compatibility.md](filter-list-compatibility.md).

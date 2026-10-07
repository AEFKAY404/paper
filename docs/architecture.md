# Paper architecture — Phase 1A

Paper is a SwiftUI macOS app with a `WindowGroup` and a Settings scene. AppKit supplies native event monitoring, window integration, and the rendering view host. The visible shell has no permanent address bar, tab strip, or toolbar. Native SwiftUI views provide the new-tab search surface, optional introduction, and built-in handbook.

```text
PaperApp → ContentView / command palette / GestureEngine
         → BrowserController → BrowserEngine → WebKitEngine
                                       session → WKWebView
         → SessionStore (URL snapshots)
```

`BrowserController` owns tab order, active tab, metadata, navigation commands, and persistence. It knows only `BrowserEngine` and `BrowserSession`, whose rendering surface is the AppKit `NSView` boundary. The SwiftUI shell sends commands to the controller; it never accesses `WKWebView`. The WebKit adapter owns one persistent `WKWebView` per tab, its delegates and observations. `BrowserSurface` attaches that view to the active tab container without recreating it during SwiftUI updates. Closing a tab stops loading, detaches delegates, cancels its downloads, and removes the view. Application termination saves the URL snapshot and closes sessions.

`SessionStore` saves ordered URLs, explicit new-tab/webpage kinds, and the active index in `UserDefaults`. It restores one session for each saved tab, then activates the saved index. Older URL-only snapshots remain readable. This intentionally does not serialize WebKit objects, form values, history, or page scripts. Website data uses WebKit's default persistent data store.

The controller records a requested URL before a load begins and ignores transient nil URL observations from WebKit. This keeps the restore snapshot valid if Paper quits during navigation.

The app retains the original `ark.Paper` bundle identifier and App Sandbox. Outgoing network access and user-selected read/write access are enabled for browsing and Save Panel downloads.

See [webkit-integration.md](webkit-integration.md) for adapter behavior and [engine-migration.md](engine-migration.md) for the migration record.

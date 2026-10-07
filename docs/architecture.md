# Current browser core

`BrowserEngine` creates `BrowserSession` objects. A session owns an AppKit rendering view and accepts navigation, focus, and close commands. It emits URL, title, loading, history-capability, error, and new-tab events. No CEF type appears in this interface.

`BrowserController` owns ordered tabs, the active tab ID, and the mapping from tab IDs to engine sessions. It dispatches navigation and tab commands and writes URL-only session snapshots through `SessionStore`. `NavigationInput` resolves HTTP(S) URLs and search queries independently of the rendering engine. Unit tests use a small mock engine.

The existing `PaperApp` and `ContentView` remain the Xcode template. The controller is not wired into the visible app because no production engine is integrated yet. Restoring URLs does not restore form state or navigation history.

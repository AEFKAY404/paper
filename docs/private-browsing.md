# Private browsing — Phase 2B

`BrowserTab.privacyMode` is engine-neutral. The WebKit adapter creates a `WKWebViewConfiguration` with `WKWebsiteDataStore.nonPersistent()` for private tabs. Private tabs share one temporary store with each other, isolated from WebKit's default persistent store. The adapter releases its reference when the last private session closes. Private tabs and their URLs are omitted from `SessionStore`; standard tabs still restore in order.

Open a private tab with `⌘⇧N`, the command palette, or the File/Privacy menu. Native new tabs and transient tab surfaces say “Private” in text. Saved standard site exceptions do not weaken private tabs; global protection and filter lists still apply. Saved permission choices are ignored in private tabs and permission prompts cannot be remembered there.

Private browsing keeps WebKit site storage temporary and excludes tab URLs from Paper's restoration snapshot. It does not make browsing anonymous to websites, networks, ISPs, or employers. Files chosen in the macOS download Save Panel remain on disk after the tab closes. Paper does not maintain a persistent download history. Session snapshots already saved by previous Paper versions are unaffected.

The nonpersistent store is process memory under WebKit's control. A site can still identify a user who signs in or fingerprints a browser. The same private store is used until the last private tab closes, after which new private tabs receive a fresh store.

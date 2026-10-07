# Known limitations — Phase 1A

- URL restoration reopens tabs and preserves their order and active index. It does not restore form state, per-tab back/forward history, scroll position, or in-memory JavaScript state after app relaunch.
- The command palette and shortcuts have an XCTest UI scenario, but automated UI execution is unreliable on this host; the outcome is recorded in [performance-benchmarks.md](performance-benchmarks.md). Webpage keyboard/mouse interaction and trackpad scrolling still need hands-on verification.
- WebKit history swipes are enabled for new sessions by default. Changing the preference affects newly created sessions; existing sessions retain their setting until recreated. Option-swipe tab switching needs physical trackpad verification.
- Save Panel downloads are implemented but an end-to-end saved-file check remains. File-overwrite behavior and server-provided filenames need manual confirmation.
- Popup requests with a URL open in a new tab. A script-created blank popup with no URL is not represented yet.
- Browser state is shared within the SwiftUI `WindowGroup`; Phase 1A is designed for one browser window. Independent multi-window tab sets are out of scope.
- The shell has no download progress, completed-download list, permission dashboard, or private mode. These are later-phase work.
- A normal Debug build signs successfully with App Sandbox, network-client, and user-selected read/write entitlements. A release distribution build and notarization are not yet verified.

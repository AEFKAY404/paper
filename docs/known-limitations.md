# Known limitations — Phase 1A

- URL restoration reopens tabs and preserves their order and active index. It does not restore form state, per-tab back/forward history, scroll position, or in-memory JavaScript state after app relaunch.
- Isolated-bundle XCTest UI scenarios now verify several native keyboard paths and new-tab focus. Webpage keyboard/mouse interaction and trackpad scrolling still need hands-on verification.
- WebKit history swipes are enabled for new sessions by default. Changing the preference affects newly created sessions; existing sessions retain their setting until recreated. Option-swipe tab switching needs physical trackpad verification.
- Save Panel downloads are implemented but an end-to-end saved-file check remains. File-overwrite behavior and server-provided filenames need manual confirmation.
- Popup requests with a URL open in a new tab. A script-created blank popup with no URL is not represented yet.
- Browser state is shared within the SwiftUI `WindowGroup`; Phase 1A is designed for one browser window. Independent multi-window tab sets are out of scope.
- The shell has no download progress, completed-download list, permission dashboard, or private mode. These are later-phase work.
- The native new-tab view, introduction, and handbook have state/routing tests and isolated-bundle UI tests for focus, menu access, shortcuts, onboarding Skip, the full three-step flow, and handbook Replay. VoiceOver behavior still needs hands-on checking. Light and Debug-forced dark captures were inspected.
- A normal Debug build signs successfully with App Sandbox, network-client, and user-selected read/write entitlements. A release distribution build and notarization are not yet verified.

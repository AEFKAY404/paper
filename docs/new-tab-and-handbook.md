# Native new tab, introduction, and handbook

The active tab has an explicit engine-neutral kind: `newTab` or `webpage`. A new tab still owns a WebKit session, but its web view is not loaded or displayed until navigation begins. The new-tab surface is SwiftUI, so opening it makes no request to Google and adds no web history entry. Its centered field uses `NavigationInput` through `BrowserController`, with Google as the default search provider. The search provider can be changed in Settings. URL-only snapshots now also save explicit tab kinds; older snapshots derive them from their URLs when decoded.

First launch presents a small optional three-step introduction. Step 1 recognizes ⌘L and lets the user continue after seeing the command palette. Step 2 accepts a practice search or URL locally without loading a site. Step 3 demonstrates ⌘T, Control-Tab, and ⌘W through buttons or shortcuts. Skip and completion share a local UserDefaults flag. The handbook's Replay button opens the introduction again.

The handbook is a native SwiftUI sheet with sections for getting started, search and navigation, tabs, gestures, downloads, settings, privacy, and Paper's philosophy. It opens through the command palette (`Help` or `Paper Handbook`), the Help menu, or ⌘?. Phase 1B adds overview, palette and interaction-setting guidance. The text distinguishes implemented behavior from unverified gestures and missing privacy features. No onboarding or handbook content makes a network request.

Verification records for Phase 1B are in [performance-benchmarks.md](performance-benchmarks.md). Isolated-bundle macOS UI tests cover new-tab focus and URL submission, ⌘T/⌘W, ⌘L, ⌘?, the overview shortcut, overview search and dismissal, Help-menu access, onboarding Skip, guided practice, and handbook Replay. Physical trackpad, VoiceOver, and end-to-end download checks remain. See [known-limitations.md](known-limitations.md).

Screenshots: [new tab, light](screenshots/new-tab-light.png), [new tab, dark](screenshots/new-tab-dark.png), and [handbook](screenshots/handbook-light.png).

# Development roadmap

## Phase 1A — WebKit browser foundation

Implemented: SwiftUI shell; WebKit session per tab; command palette; keyboard tab and navigation commands; URL/search parsing; back/forward/reload/stop; popup links in new tabs; save-panel download flow; history swipe support; optional Option-swipe tab switching; URL and active-tab restoration; engine-neutral core and WebKit tests.

Verification still needed on a physical trackpad and through reliable macOS UI automation: webpage mouse/keyboard interaction, all shortcuts, gesture behavior, download save completion, and quit/relaunch in the visible app. Performance coverage is partial. These are listed in [known-limitations.md](known-limitations.md); Phase 1A is not declared fully complete while they remain.

## Later phases

Phase 1B: visual refinement and advanced tab overview. Phase 2: privacy controls. Phase 3: controlled AI automation. No Phase 1B, 2, or 3 feature is part of this migration.

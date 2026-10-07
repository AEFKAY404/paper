# Development roadmap

## Phase 1A — WebKit browser foundation

Implemented: SwiftUI shell; WebKit session per tab; command palette; keyboard tab and navigation commands; URL/search parsing; back/forward/reload/stop; popup links in new tabs; save-panel download flow; history swipe support; optional Option-swipe tab switching; URL and active-tab restoration; engine-neutral core and WebKit tests.

The native new-tab search view, optional introduction, and built-in handbook are implemented. Google is the default search provider. See [new-tab-and-handbook.md](new-tab-and-handbook.md).

Isolated-bundle macOS UI automation now covers the new-tab search focus, selected tab/help shortcuts, the full introduction, handbook Replay, and Help-menu access. Verification still needed: physical trackpad behavior, webpage mouse/keyboard interaction, untested shortcuts, download save completion, and quit/relaunch in the visible app. Performance coverage is partial. These are listed in [known-limitations.md](known-limitations.md); Phase 1A is not declared fully complete while they remain.

## Phase 1B — Premium interaction system

Implemented in this phase: optional, configurable app-local tab swipe; temporary spatial tab overview with bounded, on-demand static snapshots; structured command palette actions; shared command routing; subtle motion that respects system and Paper Reduce Motion; interaction preferences; updated handbook and accessibility labels. See [phase1b-interaction-spec.md](phase1b-interaction-spec.md).

Physical trackpad, VoiceOver, end-to-end download, and reproducible full-app performance checks remain pending. Phase 1A is not declared fully signed off.

## Later phases

Phase 2: privacy controls. Phase 3: controlled AI automation. Neither has started.

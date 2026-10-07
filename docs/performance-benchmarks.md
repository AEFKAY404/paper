# Phase 1A performance and verification log

Host: Apple Silicon Mac, macOS 27.2, Xcode 27 beta, Debug build, 7 October 2026. Figures are not release-build benchmarks and should not be compared with CEF.

| Check | Result | Conditions |
| --- | --- | --- |
| Unit and WebKit integration tests | 10 passed | `xcodebuild test -only-testing:PaperTests`, Debug, signing disabled; includes local HTML/JavaScript, `https://example.com`, history navigation, tab view identity/state, and WebKit-backed URL restoration. |
| Actual app launch and HTTPS title | Passed | Launch Services opened a temporary bundle-ID override of Paper; diagnostic log showed WindowGroup content, active tab, and `Example Domain` title. Probe app exited after AppleScript quit. |
| Cold/warm launch, first usable window/render timings | Not measured reproducibly | No reliable window-present timestamp or controlled cold cache. |
| Navigation and tab-switch latency | Not measured reproducibly | Integration tests assert behavior, not timing. |
| Idle CPU and memory | Not measured reproducibly | A single brief process snapshot would be misleading. |
| 1, 5, 10, 20 tab performance | Not measured | No repeatable interaction harness or stable workload yet. |
| Physical keyboard, mouse, trackpad | Pending | macOS assistive access was denied to System Events in this environment. |
| UI XCTest | Passed for new-tab/handbook work | An isolated bundle identifier avoids existing `ark.Paper` processes. UI cases verify native search focus, ⌘T/⌘W, ⌘L, ⌘?, the full introduction, handbook Replay, Help menu, and light/dark appearance. The original-bundle run attached to a windowless second process. |
| Signed Debug build | Passed | Normal `xcodebuild build`; `codesign` showed App Sandbox, network-client, and user-selected read/write entitlements. |
| End-to-end saved download | Pending | Save Panel requires controlled interaction and file verification. |

The adapter retains one web view per tab; the tab-switch integration test confirms the same view and JavaScript state are present after switching. This supports the ownership design but is not a latency measurement.

The native new-tab, onboarding, and handbook change added four focused tests (14 passing total) and isolated-bundle UI tests. They do not provide new performance measurements or replace physical trackpad and download verification.

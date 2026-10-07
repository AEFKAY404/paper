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

## Phase 1B measurements — 7 October 2026

Debug build on the same Apple Silicon host. The isolated `snapshotQueueBenchmarkWorkloads()` test uses existing mock sessions that return a 320 × 180 `NSImage` after a programmed 15 ms wait. It opens one native new tab plus the stated number of webpage tabs. The table records one isolated sample from [phase1b-benchmark-sample.json](phase1b-benchmark-sample.json). `overviewStateMs` measures only the synchronous preview-store presentation call, **not** the first visible frame. `queueCompletionMs` includes asynchronous task scheduling, the programmed delay, and 10 ms polling. These are synthetic queue measurements, not WebKit rendering timings.

| Webpage tabs | Overview state call | Queue completion | Cache bytes | Peak captures |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 0.064 ms | 22.3 ms | 0.92 MB | 1 |
| 5 | 0.016 ms | 54.6 ms | 4.61 MB | 2 |
| 10 | 0.017 ms | 88.1 ms | 9.22 MB | 2 |
| 20 | 0.020 ms | 164.7 ms | 11.06 MB | 2 |

The cache retained at most 12 images and remained below its 24 MiB limit. The overview state change completed before the queued captures; the UI displays native placeholders while they finish. One isolated `visibleWebViewProducesStaticSnapshot()` run captured a visible local `data:` page at 320 × 240 in **20.1 ms** using the real `WKWebView.takeSnapshot` API. This single capture is a measured sample, not a distribution or a 20-WebKit-tab workload.

The signed Debug build and 21 core/WebKit tests passed. The final full isolated UI suite passed 11/11 in 92.88 seconds; that is test-suite wall time, not launch or interaction latency. Earlier full-suite reruns intermittently launched a windowless process after macOS restored closed-window state. The final UI harness sets `-ApplePersistenceIgnoreState YES` and activates each launch; this does not change normal app launch behavior. The Phase 1A baseline run was 8/9 in 78.33 seconds, with an intermittent dark-mode new-tab focus failure. The suites differ in case count and conditions, so they are not a before/after speed comparison. The delayed, cancellable new-tab focus request passed the final UI suite.

Cold/warm launch, first usable window, first webpage paint, palette and overview first-frame latency, live tab-switch latency before/after, idle CPU, process memory, and real WebKit snapshot overhead at 5/10/20 tabs remain unmeasured reproducibly. Physical trackpad, VoiceOver and end-to-end download verification remain pending. No fixed frame-rate claim is made.

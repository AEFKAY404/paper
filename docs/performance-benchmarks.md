# Paper performance and verification log

## Phase 2D blocker comparison — 9 October 2026

On the same Apple Silicon MacBook Air (macOS 27.2 beta, Xcode 27 beta, Debug), the checkpoint `phase2d-baseline-365004d` was built in a detached temporary checkout and compared with Blocker V2 Stage 1 using the same bundled EasyList/EasyPrivacy snapshots. Each setup row is one isolated `ContentBlockerTests` suite run with a new compiled-rule store, followed by a cache reopen. They are **samples, not medians**. Both suites passed. Stage 1 has no network access during the bundled compile portion; browsing is not gated on compilation, though first-run requests before completion may be unblocked.

| Measure | Phase 2A checkpoint | V2 Stage 1 | Observed change |
| --- | ---: | ---: | ---: |
| Accepted network rules compiled | 16,000 | 20,000 | +4,000 (+25%) |
| Attached content rule lists | 16 | 20 | +4 |
| Unsupported syntax lines | 17,635 | 10,833 | −6,802; classification changed, so this is not all newly blocked traffic |
| Cold bundled setup | 2.044 s | 2.994 s | +0.950 s |
| Cached setup | 0.0059 s | 0.0137 s | +0.0078 s |
| WebKit compile time, both sources | 0.308 s | 0.616 s | +0.308 s |

V2 parsing took 1.325 s for EasyList and 1.036 s for EasyPrivacy in that run; the checkpoint did not record parse time separately. V2 retained 4,000 EasyList hide rules plus 286 parsed cosmetic exceptions and 2 EasyPrivacy cosmetics. Parsing accepted more URL forms, but the operational cap still omits tens of thousands of supported candidates: 59,741 EasyList and 41,732 EasyPrivacy entries in this snapshot. The limits are Paper budgets, not WebKit maxima.

An offscreen local HTML fixture then created and loaded fresh `WebKitSession` groups with the blocker explicitly enabled. Values are medians of **three runs** for each tab count; each group measures all its tabs, not one tab. Both versions used their own temporary compiled cache and the same HTML. “Create” includes configuring the WebKit sessions and attaching rules; “load” ends when every page title appears. These tests do not measure first paint, live network loading, idle CPU, or separate WebContent process memory.

| Tabs | Create checkpoint → V2 | Change | Local load checkpoint → V2 | Change |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 17.9 → 7.6 ms | −10.3 ms | 81.3 → 84.8 ms | +3.5 ms |
| 5 | 46.0 → 19.0 ms | −27.0 ms | 140.1 → 146.2 ms | +6.1 ms |
| 10 | 78.5 → 33.1 ms | −45.4 ms | 287.7 → 289.5 ms | +1.8 ms |
| 20 | 134.0 → 44.8 ms | −89.2 ms | 590.8 → 555.6 ms | −35.2 ms |

The V2 creation times were lower in this harness despite more lists. Off-mode controls and process reuse varied, so these samples do **not** establish that V2 makes real tab creation faster. App-process RSS deltas also fluctuated and omit WebContent processes; no memory conclusion is drawn. One V2 host-specific cosmetic generation sample selected 500 selectors, produced an 8,746-byte script, and took 3.14 ms. Actual style recalculation cost was not isolated; the local load figures include any cosmetic work.

The signed, automated live smoke loaded ten public sites with title, no navigation error, and snapshot in one run; [raw records and captures](screenshots/phase2d/live-sites.json) accompany the [Stage 1 report](blocker-v2-stage1.md). A signed-out [YouTube public video](screenshots/phase2d/youtube-playback.json) reached normal playback in three seconds and accepted a seek in the recorded run. This is a non-regression sample, not proof of reliable video-ad blocking. Interactive sign-in, purchases, fullscreen, long playback, manual app use, and repeatable live on/off page-load comparison remain unmeasured.

## Phase 1A baseline — 7 October 2026

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

## Phase 2B local session sample — 8 October 2026

The [Phase 2B validation record](phase2b-validation.md) contains a one-run, signed Debug sample of standard and private WebKit session creation and local HTML load at 1, 5, 10 and 20 tabs. These timings do not include a live page's first paint or WebContent process memory and do not establish a repeatable private-mode performance difference.

# Phase 2B validation record

## Automated checks

Focused signed Debug runs passed: 17 core tests, 10 privacy tests, the private-blocker configuration test, two WebKit page-state tests, and the new private-tab/privacy-panel UI test. These include PSL cases, private versus standard store identity, shared and reset private store lifecycle, cookie and local-storage isolation, standard-only session restoration, scoped cookie removal, selected-category global clearing, permission persistence/revocation, command routing, blocker behavior in private tabs, and a local 1/5/10/20-tab creation/load timing sample. They use local fixtures or WebKit data-store APIs. They do not prove real-site authentication or physical user input.

Combined full-suite and grouped WebKit runs stalled in the macOS beta test host and were interrupted; they did not complete. The individual WebKit page-state tests passed when run separately. The complete suite still needs a reliable uninterrupted run.

## Hands-on checks still required

| Scenario | Status |
| --- | --- |
| Normal and private browsing in the Paper window; closing every private tab | Pending physical app check |
| Google sign-in, YouTube, and a representative OAuth popup | Pending; do not use real credentials in automation |
| Camera, microphone, geolocation and notification test pages | Pending physical device and macOS authorization check; notifications are WebKit-managed |
| Per-site blocker bypass and reload on live pages | Pending interactive app check |
| Clear site data in an authenticated page and confirm sign-out | Pending interactive app check |
| VoiceOver reading and keyboard traversal of Privacy, Settings and prompts | Pending physical accessibility check |
| Private download Save Panel notice and saved-file persistence | Pending end-to-end check |

The new macOS UI scenario passed on 8 October 2026: it used `⌘⇧N`, opened the command palette, selected Privacy, and confirmed the sheet identifies the tab as Private. Its [privacy panel screenshot](screenshots/phase2b/private-privacy-panel.png) is a native new-tab state; it does not show current-site rows. Earlier runs on this beta host timed out enabling automation, so broader UI reliability still needs confirmation. Physical trackpad checks from Phase 1A/1B remain pending.

## Local performance sample

A signed Debug XCTest run on the MacBook Air (macOS 27.2 beta, 8 October 2026) created 1, 5, 10, and 20 `WKWebView` sessions, then loaded short local HTML strings. Standard sessions used WebKit's default store; private sessions shared a new nonpersistent store per group. Times are elapsed milliseconds for the whole group, not per-tab medians. The JSON sample is [phase2b-benchmark-sample.json](phase2b-benchmark-sample.json).

| Tabs | Create standard / private | Local load standard / private | Test host RSS delta standard / private |
| ---: | ---: | ---: | ---: |
| 1 | 2.4 / 2.8 ms | 122 / 72 ms | 6.3 / 1.0 MiB |
| 5 | 8.6 / 8.1 ms | 208 / 145 ms | 3.4 / 1.7 MiB |
| 10 | 21.2 / 19.3 ms | 283 / 265 ms | 5.2 / 4.2 MiB |
| 20 | 36.8 / 35.0 ms | 533 / 531 ms | 0.7 / 3.6 MiB |

This is one sequential test-process sample. Order, WebKit process reuse, cache warm-up, and background activity affect it. RSS excludes separate WebContent processes. It does not establish a material private-mode performance difference or represent first paint of a live webpage. Repeat runs and full process-tree memory samples are still needed.

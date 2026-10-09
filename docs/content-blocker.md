# Phase 2A content blocker

This page records the historical Phase 2A baseline. The production [Blocker V2 Stage 1 upgrade](blocker-v2-stage1.md) expands declarative coverage and changes the operational network cap to 10,000 per source; the Phase 2A counts and timings below remain baseline measurements, not current totals.

Paper uses WebKit's `WKContentRuleListStore` and `WKContentRuleList` for request blocking. The privacy subsystem lives in `Paper/Privacy`; `WebKitEngine` only attaches its compiled lists and cosmetic script to sessions. Paper does not proxy traffic or send visited URLs to a filtering service.

## Sources and updates

| Source | Purpose | Subscription | License | Schedule |
| --- | --- | --- | --- | --- |
| EasyList | Ads | [easylist.txt](https://easylist.to/easylist/easylist.txt) | [GPL-3.0-or-later or CC BY-SA 3.0](https://easylist.to/pages/licence.html) | Bundled snapshot; check every four days, or use Settings → Privacy → Update filter lists |
| EasyPrivacy | Trackers and analytics | [easyprivacy.txt](https://easylist.to/easylist/easyprivacy.txt) | [GPL-3.0-or-later or CC BY-SA 3.0](https://easylist.to/pages/licence.html) | Same |

The bundled snapshots have upstream version `202610081602` and were fetched on 8 October 2026. SHA-256: EasyList `8943a8d791832c2062f41d029071c0895fa13997be6dec60da0ac0d8de79c4c9`; EasyPrivacy `cdbbf48955914e913ecf5d7f87a16537df097ce72ad75c7d37b87d30e679337d`. The engine stores each downloaded source's hash, upstream version, last-modified header, compile time, and last successful check locally. Peter Lowe's list is not enabled.

The parser deduplicates and classifies rules. It intentionally caps supported rules at 8,000 network entries and 4,000 cosmetic entries per source. At most 800 cosmetic rules per source are generic; the rest must be scoped to a domain. This avoids injecting thousands of generic selectors into every page. **These are partial EasyList/EasyPrivacy conversions, not full list compatibility.** The exact rejected and omitted counts appear below and in developer diagnostics.

WebKit compilation runs asynchronously in 1,000-rule chunks. Each chunk has a versioned, content-hashed identifier. The persistent manifest points only to a source whose entire chunk set compiled successfully. A failed download, parse, or compile leaves that source's last known-good lists attached; other sources continue working. On startup, Paper loads compiled lists by identifier. If a cache is missing, it compiles the bundled snapshots. Browsing continues while this happens, so a request started before first-run compilation finishes may not be blocked. Existing live web views receive newly compiled lists without being recreated or reloaded; a reload is needed to re-request already loaded resources and to apply a refreshed cosmetic script to current DOM content.

Settings → Privacy can disable the blocker globally, toggle cosmetic filtering, and request an update. The temporary Privacy sheet controls a standard tab's effective registrable site; a site exception is stored locally and the page reloads to apply it. Private tabs retain global blocking and ignore saved site exceptions. See [privacy-controls.md](privacy-controls.md).

## Statistics and diagnostics

`BrowserTab` stores ephemeral per-tab `BlockerStatistics`. WebKit does not expose a supported WKWebView callback for individual content-rule matches, so blocked-request and blocked-tracker totals are `nil` rather than invented counts. The cosmetic script reports the number of distinct elements matching its selectors once at document end; CSS applies to future matching elements without a JavaScript rescan. That count is an initial match count, not a lifetime hidden-element total. No visited URL or match data is uploaded. With `PAPER_DIAGNOSTICS=1`, Debug logging reports source hashes, counts, cache hits, compilation duration, and errors without logging page URLs.

## Verification and performance

Focused tests verify parsing, duplicate removal, unsupported classification, WebKit JSON compilation/cache lookup, persistent source cache reuse, failure fallback, domain bypass, a first-party/third-party local resource fixture, and cosmetic selector behavior. See `ContentBlockerTests.swift`.

On the 8 October 2026 signed Debug test run (MacBook Air, macOS 27.2 beta, Xcode beta), one cold engine start with both bundled sources took **1.689 s**; reopening the same compiled cache took **0.006 s**. WebKit chunk compilation accounted for **0.151 s** for EasyList and **0.130 s** for EasyPrivacy. These are single-run wall-clock observations inside the test process, not repeatable medians or page-load benchmarks. Parsing and source loading account for most of the cold-start time. Work is off the UI actor during parsing; browsing is not gated on completion.

| Source | Network rules compiled | Cosmetic rules retained | Unsupported syntax | Supported rules omitted by cap |
| --- | ---: | ---: | ---: | ---: |
| EasyList | 8,000 | 4,000 | 8,522 | 59,812 |
| EasyPrivacy | 8,000 | 2 | 9,113 | 39,163 |

Source version, list order, and parser changes alter these counts. The cap and chunk size are conservative operational limits; they are **not claimed as WebKit's maximum**.

An offscreen local HTML fixture loaded in fresh groups of 1, 5, 10, and 20 `WebKitSession` instances with the compiled lists off and on. This is one run in a test process, not a live-site or display-frame benchmark. Times cover all tabs in a group; lower is better.

| Tabs | Create off / on | Local load off / on |
| ---: | ---: | ---: |
| 1 | 2.8 / 16.2 ms | 69.7 / 79.6 ms |
| 5 | 26.2 / 44.5 ms | 212.9 / 252.0 ms |
| 10 | 35.0 / 82.1 ms | 292.6 / 295.1 ms |
| 20 | 48.4 / 125.6 ms | 504.3 / 613.9 ms |

The blocker added measurable configuration cost in this sample; the load difference varied by tab count. App-process resident-memory deltas fluctuated between positive and negative values as WebKit processes were reused, so this run does **not** establish blocker memory overhead. It also excludes separate WebContent process memory. Repeat runs, live page-load timing, and idle CPU still need measurement.

## Signed-out live-site smoke, 8 October 2026

An opt-in signed WebKit test opened each site with the blocker active, waited for a page title, and captured a static viewport. All six showed a title and no navigation error in this run. This is a visual smoke check, not a request-count comparison, interactive browser session, or proof that ads were removed.

| Site | Captured observation |
| --- | --- |
| [Google Search](screenshots/phase2a/google.png) | Search results and AI Overview rendered; no ad appeared in the captured viewport, which says nothing about other queries or positions. |
| [YouTube](screenshots/phase2a/youtube.png) | Signed-out home rendered; no video was played, so video-ad blocking and playback are unverified. |
| Reddit | Feed rendered. One capture showed a sponsored Kickbacks.ai post still visible; the feed changed on the repeat run. |
| [The Guardian](screenshots/phase2a/guardian.png) | Cookie-choice overlay obscured the page; ad blocking behind it was not assessed. |
| [Wikipedia](screenshots/phase2a/wikipedia.png) | WebKit article rendered normally in the captured viewport. |
| [The Verge](screenshots/phase2a/verge.png) | Page header and top story rendered; a privacy notice obscured lower content. |

Sign-in, form submission, media playback, page scrolling, full-layout breakage, and blocker-off comparisons still need hands-on checks. The macOS XCTest UI runner timed out while enabling automation mode on both this smoke attempt and an existing short UI test, so these captures came from the signed WebKit harness. See [known limitations](known-limitations.md).

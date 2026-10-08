# Web compatibility and browser identity — Phase 1B.1

## Baseline findings, before the production change (8 October 2026)

Before this change, Paper 1.0 created one `WKWebView` per tab with the default persistent website data store. It did not set `customUserAgent`, `applicationNameForUserAgent`, or `preferredContentMode`. The window started at 1100 × 750 points. The default macOS WebKit content mode was recommended, which Apple describes as desktop-appropriate on Mac.

The local-only fixture in `tools/identity_probe_server.py` recorded HTTP request identity at the initial URL, a 302 target, a JavaScript subresource, and an image. `tools/identity_probe.swift` read JavaScript capability values from a fresh, nonpersistent `WKWebView`. No account credentials or cookies were captured.

| Browser / experiment | Effective UA on main request | Client hints |
| --- | --- | --- |
| Default macOS `WKWebView` (Paper's prior configuration) | `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)` | None |
| WebKit with `applicationNameForUserAgent = Paper/1.0` only | Same base, followed by `Paper/1.0` | None |
| Installed Safari 27.2, measured HTTP request | Same platform and WebKit tokens, followed by `Version/27.2 Safari/605.1.15` | None |
| Installed Chrome 154, fresh headless profile | `AppleWebKit/537.36 ... HeadlessChrome/154.0.0.0 Safari/537.36` | `Sec-CH-UA` and `Sec-CH-UA-Platform` present |

The main request, redirect destination, script and image used the same UA within each probe. Safari also made icon requests with a shorter UA; this does not describe its main document identity. Safari WebDriver and AppleScript did not yield a JavaScript identity report in this environment; Safari's JavaScript-visible fields and signed-out Google layout remain unverified. The Chrome observation is headless with a temporary signed-out profile, not the user's normal Chrome session.

The default WebKit probe reported `platform=MacIntel`, `vendor=Apple Computer, Inc.`, `navigator.userAgentData=null`, `webdriver=false`, DPR 2, and true support for CSS grid/container queries, service workers, credentials, share and media capabilities. Chrome reported `vendor=Google Inc.`, non-null `userAgentData`, and Chromium client hints. These differences are expected and are not candidates for polyfills.

### Signed-out Google Search, query `yt`

Fresh, nonpersistent WebKit sessions were used for each variant so account state did not change. Results can vary by time, region and Google's experiments.

| WebKit UA | Observed result structure |
| --- | --- |
| Default | Compact `Google ×` header; `All / Videos / Images / News / Maps / Books / Search tools`; no AI Mode label in inspected page text. |
| Default + `Paper/1.0` app token | Same compact category structure; no AI Mode label in inspected page text. |
| Installed Safari-compatible desktop UA + `Paper/1.0` | Desktop result structure with accessibility links, `AI Mode`, `All`, `Videos`, `Short videos`, `Images`, `News`, `Forums`, and richer video modules. |

This controlled UA change within the same WebKit engine strongly indicates that Google's simplified layout was caused by browser classification from the bare embedded-WebKit UA, rather than a missing CSS or JavaScript capability. It does not establish that the UA is the only factor in every account or region. The application-token-only option did not fix the observed case. No Chromium identity was used in the WebKit experiments.

## Production identity

`BrowserIdentity` configures each new session before its first URL request. It asks that session's WebKit view for its real `navigator.userAgent`, reads the installed Safari version, and adds Safari's desktop `Version/… Safari/…` tokens plus Paper's own versioned token. On the measured machine the resulting identity is:

```text
Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.2 Safari/605.1.15 Paper/1.0
```

The WebKit engine and macOS platform tokens come from WebKit; the Safari version comes from the installed Safari app. When either lookup fails, Paper retains WebKit's default identity with its Paper application token. `preferredContentMode` is explicitly `.desktop`. The standard identity is shared by newly created tabs and is selected before navigation, including restored URLs. Existing live tabs are neither destroyed nor reloaded. The version change takes effect as new sessions are created, ordinarily at the next launch. The site policy has no active rules. Paper does not claim Chromium, provide `navigator.userAgentData`, or synthesize client hints.

The URL and capability diagnostic is developer-facing only: `tools/identity_probe_server.py` plus `tools/identity_probe.swift` can be run locally to inspect a fresh nonpersistent WebKit view. The local server records request UA at initial navigation, redirect, script and image. `tools/run_compatibility_smoke.py` runs the same isolated WebKit probe against public sites. These tools do not upload diagnostics, store credentials or access the normal Paper website data store.

From the repository root, start `python3 tools/identity_probe_server.py` in one terminal and run `DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer xcrun swift tools/identity_probe.swift` in another. The smoke check is `DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer python3 tools/run_compatibility_smoke.py /private/tmp/paper-web-compatibility.json`. It writes a local JSON report with query strings removed from final redirect URLs. These commands are diagnostics, not an in-app browser surface.

## Google after the change

The controlled signed-out `yt` search with the new UA displayed the desktop Google Search structure: accessibility links, `AI Mode`, `All`, `Videos`, `Short videos`, `Images`, `News`, `Forums`, and richer video modules. This is a page-text/layout observation from a fresh WKWebView using the identity Paper now applies; the production session test separately confirms its JavaScript-visible UA matches. It is not a claim that every Google experiment or signed-in account will show AI Mode. The baseline rows above used the same WebKit engine and query. A separate homepage probe timed out during UI regression testing, so homepage appearance remains unverified. A normal signed-in Paper, Safari, or Chrome account comparison was not performed because that would require interacting with the user's account. Headless signed-out Chrome received an unusual-traffic challenge for this query, so its Google layout cannot be compared fairly. Safari's main-request UA was measured, but its signed-out Google layout was not captured. No knowledge-panel comparison was possible for this query.

## Cross-site smoke, same identity

An isolated nonpersistent WKWebView loaded each site on 8 October 2026. The smoke utility checked the final page, DOM readiness and whether page JavaScript evaluation worked. It did not use the user's saved cookies. `42` denotes successful evaluation of the 21 diagnostic expressions twice; it does not prove all application JavaScript paths.

| Site | Observed result | Scope limit |
| --- | --- | --- |
| Google Search | Search results loaded with desktop categories and AI Mode text; JavaScript evaluation succeeded. | No account or feature eligibility check. |
| YouTube | Homepage loaded and contained a video element; JavaScript evaluation succeeded. | Video playback and signed-in state not tested. |
| GitHub | Homepage content and controls loaded; JavaScript evaluation succeeded. | Repository editing and login not tested. |
| Reddit | JavaScript challenge page loaded. | Normal Reddit browsing remains unverified. |
| Gmail | Redirected to Google sign-in, which loaded. | Mail and authentication not tested. |
| Google Docs | Redirected to Google sign-in, which loaded. | Docs editor not tested. |
| Microsoft | Redirected to regional `/en-in` page, which loaded. | Microsoft account flow not tested. |
| Wikipedia | Homepage loaded; JavaScript evaluation succeeded. | Deeper navigation not exercised. |

The suite covers a media-heavy site, account-heavy sites, a JavaScript-heavy SPA, redirects, and several page layouts at smoke-test depth. Cookie persistence, popup behavior, downloads, file uploads, media playback and complete authenticated flows were not reverified in this pass. Existing tests cover basic WebKit navigation, tab state, downloads wiring, and native UI behavior separately; those are not substitutes for site-level manual use.

## Measurement limits

UA resolution happens once per app identity and is cached. Each tab waits for it before its initial URL request; subsequent navigations use the cached value. The implementation neither recreates existing views nor adds a second view for identity probing. No repeatable pre-change latency or memory baseline was obtained, so a quantified before/after performance claim is unavailable. The isolated probe is suitable for repeating browser identity and public-site smoke checks, but network response times and Google experiments make it unsuitable as a stable latency benchmark.

## Verification record

The signed macOS Debug build passed on 8 October 2026. The serial core/WebKit test run passed 23/23, including identity formatting, domain policy matching, two-tab identity consistency, JavaScript-visible UA and desktop content mode. The UI regression run passed 11/11; Xcode reported four internal quality-of-service priority inversion warnings and no test failures. A first parallel core test invocation was interrupted after its runner stalled; the complete serial rerun passed. The cross-site table is a separate network smoke check, not an XCTest result. No authenticated account testing or manual visual confirmation inside a normal Paper window was completed in this pass.

# uBlock ecosystem feasibility audit

9 October 2026. Research and architecture only; Paper's production blocker is unchanged. Source review used the official [uBlock Origin repository](https://github.com/gorhill/uBlock) at `e5e96f6` (8 October 2026), its [MV3 build documentation](https://github.com/gorhill/uBlock/blob/master/platform/mv3/README.md), [uAssets](https://github.com/uBlockOrigin/uAssets), Apple's WebKit documentation, and Paper's current Swift source. Upstream rules and browser behavior can change after this date.

## Architecture map

```text
Filter sources / asset updates
    ↓
Static syntax parser and domain/exception normalization
    ├── Network rules → indexed matcher (uBO) or DNR compiler (uBOL)
    ├── CSS cosmetics → domain-specific selector sets
    ├── Procedural cosmetics → DOM evaluator
    ├── Scriptlet directives → bundled JavaScript resources
    ├── Redirect directives → bundled substitute resources
    └── Exceptions / dynamic rules → precedence and user policy

Paper V2 candidate:
    normalized subset → WKContentRuleList + static CSS
                      → optional, narrowly scoped Paper-owned runtime
```

Full uBO's [static parser](https://github.com/gorhill/uBlock/blob/master/src/js/static-filtering-parser.js), [network compiler and matcher](https://github.com/gorhill/uBlock/blob/master/src/js/static-net-filtering.js), [cosmetic engine](https://github.com/gorhill/uBlock/blob/master/src/js/cosmetic-filtering.js), [scriptlet engine](https://github.com/gorhill/uBlock/blob/master/src/js/scriptlet-filtering.js), [redirect engine](https://github.com/gorhill/uBlock/blob/master/src/js/redirect-engine.js), [dynamic network rules](https://github.com/gorhill/uBlock/blob/master/src/js/dynamic-net-filtering.js), and [asset manager](https://github.com/gorhill/uBlock/blob/master/src/js/assets.js) are separate subsystems. Resource aliases and implementations live under [`src/js/resources`](https://github.com/gorhill/uBlock/tree/master/src/js/resources). This separation is useful as a design model; its extension matcher and browser hooks do not transplant into WKWebView.

uBO Lite is built from the same repository's [`platform/mv3`](https://github.com/gorhill/uBlock/tree/master/platform/mv3). Its [build-time compiler](https://github.com/gorhill/uBlock/blob/master/platform/mv3/make-rulesets.js) packages selected lists into declarative rulesets; runtime [ruleset management](https://github.com/gorhill/uBlock/blob/master/platform/mv3/extension/js/ruleset-manager.js) and [content-script registration](https://github.com/gorhill/uBlock/blob/master/platform/mv3/extension/js/scripting-manager.js) depend on WebExtension APIs. The Safari build includes a [Safari-specific DNR patch](https://github.com/gorhill/uBlock/blob/master/platform/mv3/safari/patch-ruleset.js), including removal of unsupported rules. The maintainer describes [network-only basic mode](https://github.com/uBlockOrigin/uBOL-home/discussions/606) and permissions for CSS/JavaScript filtering. Safari translates extension DNR through its own content-blocking path; that does **not** grant WKWebView apps WebExtension DNR, content-script registration, or Safari extension hosting. uBOL is the closer *compiler architecture*, but not an embeddable component.

## Practical compatibility matrix

“Possible” describes a supported mechanism or a bounded design, not tested parity with uBO syntax.

| Capability | Paper today | WebKit-native route | Paper-owned runtime | Boundary / next proof |
| --- | --- | --- | --- | --- |
| Host-anchored third-party URL block | Limited subset, capped | `WKContentRuleList` block | Unneeded | Existing signed fixture tests; rule coverage is deliberately partial. |
| First-party URL block and resource types | Parser restricts to third-party, non-document | Rule trigger can target first-party/types | Unneeded | Add only with playback and login regressions. |
| Domain-scoped network rules | Basic supported modifiers | `if-domain` / `unless-domain` | Unneeded | Preserve Public Suffix List site semantics; test subdomains. |
| Network exceptions | `@@` rejected; site bypass is separate | `ignore-previous-rules` may express some ordered exceptions | Unneeded | Chunk/list ordering and precedence must be proven with compiled rules. |
| CSS cosmetics | Simple selectors, fixed local script | CSS display rules for suitable selectors | Existing local CSS script | Domain and exception handling can improve. |
| Procedural cosmetics | None | Native CSS `:has()` for compatible cases | Bounded DOM observer for a tiny subset | No general uBO procedural engine proposed. |
| Scriptlets / property interception | None | No content-rule action | Possible local page-world `WKUserScript` | Injection ordering, CSP, SPA, breakage need proof; no list-supplied code. |
| JSON pruning / fetch/XHR interception | Test-only YouTube experiment | No response-body rewrite | Page-world JavaScript can intercept page calls, incompletely | Cannot assume coverage of service workers, native loads, or all frames. |
| Response rewrite and headers | None | No general arbitrary body/header rewrite in WKContentRuleList | Limited page JavaScript only | Safari extension DNR is a different API; no proxy proposed. |
| Redirect to local resource | None | No general uBO-style HTTPS resource replacement shown | Possible only by site-specific page script changes | `WKURLSchemeHandler` handles app schemes, not normal HTTPS interception. |
| Dynamic filtering / per-request logger | Global and site bypass, no rule counts | No uBO-style matcher callback | Partial policy at navigation/session level | Exact blocked-request counts remain unavailable. |

Apple's [content rule list](https://developer.apple.com/documentation/webkit/wkcontentrulelist) and [content blocker specification](https://developer.apple.com/documentation/safariservices/creating-a-content-blocker) support declarative matching and actions, not full extension request APIs. [`WKNavigationDelegate`](https://developer.apple.com/documentation/webkit/wknavigationdelegate) covers navigation decisions rather than arbitrary subresources, and [`WKURLSchemeHandler`](https://developer.apple.com/documentation/webkit/wkurlschemehandler) handles custom schemes. Safari WebExtension [declarative request rules](https://developer.apple.com/documentation/safariservices/blocking-content-with-your-safari-web-extension) are a distinct host capability.

## Parser choices

| Choice | Gain | Cost and risk | Verdict |
| --- | --- | --- | --- |
| A. Embed uBO JavaScript parser | Closest syntax fidelity and upstream behavior | GPL code integration, JS runtime/build bridge, mapping many outputs WKWebView cannot execute, upstream churn | Do not copy into Paper for this phase. |
| B. Port selected behavior to Swift | Control over semantics | A port can still be derivative if code/structure is copied; large test burden | Only with file-specific licensing review and demonstrated value. |
| C. Expand Paper's parser with independent implementations | Matches available WebKit actions and current architecture | Incomplete uBO syntax; maintain conformance fixtures | Recommended. Treat unsupported syntax explicitly, never silently approximate. |

Paper currently accepts only a conservative `||host^` network subset, forces third-party matching, caps network rules at 8,000 per list, and emits simple CSS. It rejects `@@`, `#@#`, scriptlets, procedural selectors, redirects, and many modifiers; see [filter-list-compatibility.md](filter-list-compatibility.md). Rule ranking and transparent unsupported counts would improve real coverage more safely than blindly lifting caps.

**Direct reuse:** Paper may continue consuming appropriately licensed filter-list *data* and Apple's native content-rule APIs. No uBO/uBOL source component is recommended for direct embedding. **Adapt conceptually:** typed normalized rules, per-capability compilation, domain scoping, unsupported-rule accounting, and atomic ruleset updates. **Paper-specific runtime:** only a future reviewed module for behavior that cannot be expressed as native rules or static CSS. The [licensing inventory](ublock-licensing.md) explains why even a source port needs review.

## Page-world feasibility and scriptlet classes

[`WKUserScript` at document start](https://developer.apple.com/documentation/webkit/wkuserscriptinjectiontime/atdocumentstart) runs before most page content after the document element exists, but does not guarantee precedence over every source of state or cover service-worker/network internals. [`WKContentWorld.page`](https://developer.apple.com/documentation/webkit/wkcontentworld/page) shares page JavaScript globals and can intercept page-defined properties or `fetch`/XHR; an isolated world shares the DOM but not those globals. The page world carries higher page-tampering and compatibility risk. CSP interaction and script ordering need fixture and live-site validation; no blanket CSP-bypass claim is made.

| Class | Feasibility | Risk / policy |
| --- | --- | --- |
| Static domain CSS; native CSS `:has()` where supported | Safe to consider | Validate selector, scope to registrable site, cap count. |
| Bounded domain-specific DOM check for simple visibility/text cases | Possible, lower priority | Restrict selector root and scan budget; avoid full-document mutation loops. |
| Narrow property interception or JSON pruning | High risk, technically possible in page world | Can change page logic and authentication-adjacent objects; only source-controlled, domain-scoped, opt-in after strong evidence. |
| `fetch`/XHR wrapper, event suppression, timers, abort-current-script | High risk | Can interfere with playback, app behavior, CSP, SPA transitions; no generic list-driven execution. |
| Native arbitrary HTTPS response rewrite, service-worker interception, uBO extension API scriptlet host | Not available through the audited WKWebView APIs | Would require another browser architecture; do not simulate with a MITM proxy. |
| Broad media blocking or unrelated uBO scriptlets | Not relevant to Paper's near-term V2 | Exclude. |

The [uBO procedural cosmetic documentation](https://github.com/gorhill/uBlock/wiki/Procedural-cosmetic-filters) itself favors plain CSS where possible and warns about performance. A Paper prototype would need per-site selector budgets, an observer only while a matching page is open, deferred batch work, teardown on navigation, and no scanning of credential fields.

## Recommendation

Build **Blocker V2 incrementally**, beginning with better declarative rules and CSS; defer any general runtime layer. Copy no uBO/uBOL source. Preserve explicit unsupported counts and a last-known-good compiled list. Do not promise YouTube video-ad removal. See [Blocker V2 architecture](blocker-v2-architecture.md), [licensing](ublock-licensing.md), and the [YouTube comparison](youtube-blocking.md). This audit did not change behavior or establish new performance measurements.

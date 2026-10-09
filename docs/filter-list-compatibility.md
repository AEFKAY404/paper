# Filter-list compatibility — Blocker V2

Paper independently converts a safe EasyList/EasyPrivacy subset into WebKit rules. This is partial compatibility, not uBO parity. See [Stage 1 network behavior](blocker-v2-stage1.md) and [Stage 2 cosmetics](blocker-v2-stage2.md).

| Input class | Current handling |
| --- | --- |
| `||ads.example.com^` | Host-anchored HTTP(S) rule; broad hosts remain third-party by default |
| `||ads.example.com/banner*.js$script` | Bounded path and at most two wildcards, compiled to WebKit's supported URL-regex subset |
| `|https://cdn.example.com/ad.js|` | Exact scheme/host/path anchors, with start/end regex anchors |
| `^` separator | A validated non-alphanumeric separator; end-of-host uses WebKit-compatible path/query delimiter syntax |
| `$first-party`, `$third-party`, `~first-party`, `~third-party` | Explicit load type; contradictory combinations rejected |
| `$script,image,stylesheet,font,media,popup` | Native WebKit resource types |
| `$xmlhttprequest`, `$other` | XHR/fetch maps to `raw` and `fetch`; `other` stays distinct from `raw` |
| `$domain=site.example` or `$domain=~site.example` | WebKit `if-domain` or `unless-domain`, including subdomains; mixed positive/negative sets rejected because WebKit forbids using both fields |
| `@@` | Only an exact-pattern, same-source block/exception pair with matching resource types and an equal or broader exception party scope can be resolved before chunking; unmatched cases counted |
| `##.ad`, `site.example##.ad`, `site.example,~other.example##.ad` | Validated local CSS with host scope and exclusion; generated declaration is `display:none!important` |
| `site.example#@#.ad`, `#@#.ad` | Exact-selector domain or global cosmetic exception, applied across the approved sources |
| `div:has(.ad)`, attributes, combinators, supported pseudo-classes | Narrow validated native-CSS subset, bounded by selector length/complexity and per-page budgets; host-scoped ad custom elements also supported |
| Scriptlets, JSON pruning, response rewrite, redirect, unsupported regex/modifiers/procedures | Rejected and counted; never executed as remote code |

Accepted network rules are deduplicated and ranked deterministically under an operational 10,000-per-source cap. Priority partitions contain at most 1,000 rules; source-level compilation and activation remain atomic. Cosmetic admission considers up to 24,000 candidates per source and retains at most 4,000, including a reserved quota for advanced domain rules. Output is selected for the current host and limited to 500 selectors/32 KiB. Full list-wide CSS is not injected into every page.

The filter source snapshots remain EasyList and EasyPrivacy. [Licensing notes](ublock-licensing.md) apply. WKWebView does not expose individual content-rule match counts, and Paper does not promise YouTube video-ad removal. See [known limitations](known-limitations.md).

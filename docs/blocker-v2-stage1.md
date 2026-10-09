# Blocker V2 Stage 1: declarative coverage

9 October 2026. This is a production change to Paper's WebKit-native blocker. It uses independently written Swift parsing, `WKContentRuleList`, and locally generated static CSS. It adds no uBO source, remote scriptlets, YouTube runtime mitigation, proxy, or permanent UI.

## Behavior and rule boundaries

| Capability | Phase 2A | Stage 1 |
| --- | --- | --- |
| Network rules compiled per bundled source | First 8,000 supported rules | Up to 10,000, selected by deterministic specificity tiers rather than first-come order |
| URL syntax | `||host^` only | Host anchors, bounded host paths and wildcards, separator `^`, exact `|https://...|` / `|http://...|` anchors |
| Party | Third-party forced | Third-party remains the default for broad hosts; explicit first/third party modifiers work; domain-scoped paths without a party modifier may match either party |
| Resource types | Script, image, style sheet, font, media, raw, popup | Separates WebKit `raw`, `fetch`, and `other`; maps `xmlhttprequest` to raw/fetch; no document-level blocking |
| Domain filters | Positive **or** negative domains | Same safe WebKit boundary, with typed normalization and rejection of mixed positive/negative sets |
| Network exception | Unsupported | Narrow exact-pattern, same-source exception preprocessing before partitioning; domain exceptions can exclude a site from an otherwise unscoped block |
| Cosmetic rules | Simple class/ID selectors | Bounded simple `:has(.class)` / `:has(#id)`, domain exclusions, cross-source exact-selector exceptions |
| CSS payload | List-wide selector data injected for every page | Host-specific selection before navigation, at most 500 selectors and 32 KiB of generated CSS per page |

The [fixed local corpus](../PaperTests/BlockerV2CorpusTests.swift) records synthetic reserved-domain cases and short, exact examples from the existing bundled EasyList/EasyPrivacy snapshot (`202610081602`), each with source, category, text, and expected outcome. Approved list sources and their [dual license](https://easylist.to/pages/licence.html) remain unchanged. The Public Suffix List continues to govern *site settings*; WebKit domain triggers govern filter rules. WebKit's `first-party` load type uses the main page's scheme, domain, and port, so it should not be confused with Paper's registrable-site key for privacy controls. Apple's [content blocker format](https://developer.apple.com/documentation/SafariServices/creating-a-content-blocker) forbids combining `if-domain` and `unless-domain` in one trigger; mixed domain syntax is rejected rather than approximated.

Network rules are deduplicated within each source, assigned a fixed priority based on domain scope, path specificity, and resource specificity, and then partitioned by priority into groups of at most 1,000. This is a transparent ranking heuristic, **not** a claim about which hosts are most valuable or a machine-learned score. Rules that exceed the 10,000-per-source operational cap are counted. Partition labels, raw/accepted/duplicate/unsupported/omitted counts, parse/compile times, hashes, cache hits, and last errors remain local developer diagnostics. Exact request-match totals are still unavailable from WKWebView.

## Exception semantics and rollback

[WebKit documents](https://webkit.org/blog/3476/content-blockers-first-look/) `ignore-previous-rules` as order-sensitive and list-local. Paper's fixture reproduced: block then ignore in one list allowed a request; ignore then block did not; an ignore in a second list did not cancel the first list's block. Stage 1 therefore does **not** emit list-spanning `ignore-previous-rules`. It only removes or narrows a block when the exception's URL regex and resource-type set match exactly *within the same source before partitioning*, and its party scope is the same as or broader than the block's. Broader URL exceptions and unmatched cases remain unsupported and counted. Cross-source network exception precedence, partial resource exceptions, and mixed domain scopes are not claimed.

Cosmetic exceptions are evaluated across both source lists before CSS generation. A matching domain exception suppresses the same selector on that host and subdomains; unrelated selectors remain. The page's host is selected in Swift before navigation and checked again in the fixed script. No arbitrary filter-list CSS declarations or JavaScript run.

The cache format is version 4. On upgrade, Paper loads valid version-3 compiled lists first, compiles all V2 partitions for one source, then swaps that source only after every partition succeeds. A compile or download failure retains that source's last-known-good lists; other sources remain active. Manifest writes are atomic. The update is atomic **per source**, so two-source updates can briefly contain one new and one previous source. No partially compiled source is activated. Existing global bypass, registrable-site bypass, private-tab isolation, and permission behavior are unchanged.

## Verification and limits

Focused Swift/WebKit tests cover corpus classification, URL and type translation, exact exception normalization, WebKit list ordering, bounded partitions, cosmetic exceptions and budgets, cache/migration, global/site bypass, and private-mode regression. The local 1/5/10/20-tab fixture checks rule attachment and page load without a live network. Measurements and before/after counts are in [performance-benchmarks.md](performance-benchmarks.md); single runs are not latency distributions.

The signed WebKit live smoke opened [ten public sites](screenshots/phase2d/live-sites.json): Google Search, YouTube home, Reddit, The Guardian, Wikipedia, The Verge, GitHub, Microsoft, Amazon, and Twitch. All had a page title, no navigation error, and a captured viewport. [Google](screenshots/phase2d/google.png), [GitHub](screenshots/phase2d/github.png), [Wikipedia](screenshots/phase2d/wikipedia.png), [Microsoft](screenshots/phase2d/microsoft.png), and [Amazon](screenshots/phase2d/amazon.png) showed visible page content. [Guardian](screenshots/phase2d/guardian.png) and [The Verge](screenshots/phase2d/verge.png) showed consent overlays; [YouTube home](screenshots/phase2d/youtube.png) and [Twitch](screenshots/phase2d/twitch.png) had loading placeholders in the short capture. [Reddit](screenshots/phase2d/reddit.png) rendered a feed. These are automated, signed-out snapshots, not interactive manual validation or proof of ad removal. A separate public [YouTube video](screenshots/phase2d/youtube-playback.json) began normal playback within three seconds and accepted a seek in one signed-out run; no ad appeared in that sample. This is not evidence that video ads are suppressed. Fullscreen, login, purchases, long viewing, and physical app use remain pending.

The isolated-bundle UI XCTest rerun completed 13 cases with 4 passes and 9 failures (16 assertions). Failures involved keyboard focus, overlay discovery, or window screenshots; the automation log repeatedly reported display lookup problems. Core/WebKit tests and the signed live smoke are separate checks. This UI suite remains unresolved and is not claimed as a pass.

## Explicitly unsupported

Full uBO syntax and parity; list-provided scriptlets or JSON pruning; response rewrite, redirect resources, removeparam, procedural cosmetics beyond the narrow CSS subset; regex-like network filters outside the validated forms; document-level rules; cross-source network exception precedence; mixed positive/negative domain triggers; and reliable YouTube video-ad removal. If a new class materially breaks a site, disable that class and revalidate rather than broadening its interpretation. The existing per-site bypass remains the immediate user recovery control.

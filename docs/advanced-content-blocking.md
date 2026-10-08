# Advanced content blocking investigation

Phase 2C investigation, 9 October 2026. No runtime mitigation is enabled in Paper.

The subsequent [uBlock feasibility audit](ublock-feasibility.md) recommends a staged [Blocker V2 proposal](blocker-v2-architecture.md): improve WebKit-native declarative rules and safe CSS first, and keep page-world runtime mitigations out of production until a separate evidence gate is met. This is a proposal, not a Phase 2C implementation or approval to alter Paper's current blocker. [Licensing implications](ublock-licensing.md) are tracked separately.

Paper continues to use its existing `WKContentRuleList` rules, conservative EasyList/EasyPrivacy conversion, cosmetic CSS, global switch, and per-site bypass. [WebKit content rules](https://webkit.org/blog/3476/content-blockers-first-look/) act on resource requests and CSS selectors. They do not offer a supported way for Paper to rewrite the JSON body of YouTube's first-party player response or to observe exact per-rule matches. Paper's converter also limits network rules to third-party, non-document resources. This preserves ordinary playback but leaves first-party ad metadata outside its current network coverage.

## Rule compatibility reviewed

| Example from bundled lists | Current handling | Decision |
| --- | --- | --- |
| Third-party host anchors such as `||fcmatch.youtube.com^` | May compile when supported and within the rule cap | Keep standard blocker behavior; no claim of an observed match. |
| `||youtube.com/youtubei/v1/player/ad_break` | First-party request is outside Paper's conservative network policy | Do not broaden first-party blocking without playback evidence. |
| `youtube.com###masthead-ad`-style selectors | Simple selectors can become local CSS; complex `:has()` selectors are rejected | Keep conservative cosmetic filtering. |
| Scriptlets, JSON pruning, response rewriting, and procedural selectors | Unsupported by the EasyList converter | Do not import or execute filter-list scriptlet syntax. |
| Broad `googlevideo.com` or player resource blocking | Could affect the same media path used for normal video | Not adopted. |

The [YouTube investigation](youtube-blocking.md) found an ad in Paper's signed-out WebKit engine and tested two narrow, test-only transformations. Fetch-response pruning did not stop it. Changing the initial player response suppressed that ad in one run but delayed ordinary video playback by roughly 26 seconds. That regression and the limited live sample do not support shipping a runtime layer, global toggle, or per-site kill switch yet. The existing per-site blocker bypass remains available for the standard blocker.

No site-specific observer, remote script, media block, or background polling was added. There is therefore no new production CPU or page-load overhead to report. Any future runtime design needs repeatable ad and legitimate-playback results across multiple videos, route changes, seeking, playlists, Shorts, fullscreen, signed-in use, and an immediate independent kill switch before default enablement.

# Filter-list compatibility

Paper supports a deliberately narrow, reviewed subset of EasyList-style syntax. See [content-blocker.md](content-blocker.md) for source versions and measured coverage.

| Input | Handling |
| --- | --- |
| `||ads.example.com^` | Convert a validated host anchor to a WebKit URL regular expression; apply to third-party, non-document resources |
| `$script,image,stylesheet,font,media,xmlhttprequest,other,popup` | Map supported resource options to WebKit resource types; unsupported modifiers reject the whole rule |
| `$domain=example.com` or `$domain=~example.com` | Map to `if-domain` or `unless-domain`; mixed positive and negative sets are rejected |
| `##.ad`, `news.example##.sponsored` | Accept simple selector syntax, inject local CSS through a controlled `WKUserScript` |
| Duplicate supported rules | Remove duplicates while preserving source order |
| `@@` and `#@#` exceptions | Unsupported; Paper does not misrepresent their cross-list ordering semantics |
| Scriptlets, procedural selectors, redirect, removeparam, HTML filtering, complex regex and unknown modifiers | Unsupported and counted |

Network filters always exclude the main `document` resource and are third-party only. This is conservative compared with the original subscriptions and may miss first-party advertising or trackers. `WKContentRuleList` applies rules inside WebKit; Paper does not observe individual rule matches. The supported URL expression was checked by compiling it with the installed WebKit version. WebKit's regex format is a [strict subset of JavaScript regular expressions](https://webkit.org/blog/3476/content-blockers-first-look/), so the parser rejects rather than guesses at unsupported forms.

Cosmetic scripts contain locally generated selector data and fixed Paper code only. They inject CSS at document end, and CSS naturally applies to later matching elements. No remote JavaScript or full-DOM mutation loop is used. Pages with restrictive styling or complex selectors may remain visibly unfiltered. Basic selectors are not a substitute for uBlock Origin's procedural rules.

EasyList and EasyPrivacy include exceptions and advanced features that this converter does not implement. The rule cap further reduces coverage. The Settings per-site bypass is the recovery path for breakage; changing it may require reloading the current page. YouTube video ads are not expected to be removed reliably by these rules, and Paper contains no YouTube-specific script workaround.

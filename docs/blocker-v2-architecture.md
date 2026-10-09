# Blocker V2 architecture proposal

9 October 2026 architectural proposal. **Stage 1 is now implemented** as documented in [blocker-v2-stage1.md](blocker-v2-stage1.md). Later procedural or runtime stages remain proposals; no scriptlet or YouTube mitigation shipped. The historical [Phase 2A blocker](content-blocker.md) is the comparison baseline.

```text
FilterSourceManager (signed/bundled sources, hashes, license manifest)
    ↓
FilterParser → RuleNormalizer → typed rules + unsupported diagnostics
    ├── NativeNetworkBackend → ordered WKContentRuleList chunks
    ├── CosmeticBackend → domain CSS / narrowly validated CSS selectors
    └── RuntimeMitigationBackend [future, disabled by default]
           → bundled, versioned, domain-scoped Paper-owned modules

Policy layer: global setting → private-mode policy → per-site bypass
Rollback: compile all → fixture and smoke gates → atomic activation
          → last-known-good rules on failure
```

This mirrors uBOL's separation of build-time rule compilation from runtime declarative execution without using its GPL source or WebExtension APIs. Paper's current `ContentBlockerEngine`, `FilterParser`, `RuleCompiler`, and `CosmeticFilterEngine` already supply the basic boundaries. V2 should evolve them in small steps, keeping the `BrowserEngine` interface free of filter-list syntax.

## Staged implementation if approved

1. **Measurement and corpus.** Save representative official-list fixtures with provenance; report accepted/rejected rules by syntax and source, coverage after caps, compile time, compiled-list size, launch cost, page-load and breakage results. Keep this diagnostic local; no browsing URL telemetry. Establish repeatable 1/5/10/20-tab fixtures and live-site manual cases.
2. **Declarative network semantics.** Independently implement selected URL patterns, first-party/resource restrictions, domain scoping, and a small exception subset only where they map unambiguously to `WKContentRuleList`. Verify `ignore-previous-rules` precedence inside and across chunks/lists before enabling exceptions. Use ordered partitions or explicit fallback if cross-list semantics cannot be proved. Rank useful rules rather than simply increasing the 8,000-rule cap. Preserve current compile-all, source-hash, and last-known-good behavior.
3. **Static cosmetics.** Improve domain and cosmetic-exception handling. Admit standards-based CSS selectors such as `:has()` only after WebKit support and selector validation; bound selector counts and avoid untrusted CSS declarations. Prefer declarative CSS to a DOM procedure.
4. **Optional procedure experiment.** A tiny, domain-scoped, budgeted DOM evaluator only if a measured gap remains. Test SPA route changes, nested documents, MutationObserver cost, and teardown. It is not a general uBO procedural engine.
5. **Runtime mitigation research gate.** No production scriptlets by default. Any candidate needs a single-site problem statement, alternative analysis, controlled fixtures, many real playback/login cases, before/after latency, memory and CPU samples, security review, user-visible disable path, and instant kill switch. YouTube does not currently pass this gate.

Each stage is separately reversible. Do not replace the current pipeline wholesale or activate a partially compiled set. Private tabs retain global protection while ignoring persistent site exceptions, as today.

## Runtime policy and trust boundary

If ever approved, runtime modules are source-controlled, bundled with Paper, fixed-version, allowlisted to exact domains/paths, individually switchable, and independently tested. Filter lists may select only a known identifier with validated parameters after explicit review; they may never supply executable JavaScript, `eval`, remote code, credential selectors, token modifications, or broad global monkey-patching. Page-world modules must avoid credentials and authentication state and remove hooks/listeners on navigation or disable. A filter-source compromise must not become remote code execution. Log module IDs and aggregate failure signals locally without sensitive URLs or request bodies.

Page-world injection can alter site behavior even when Paper's own script is trusted; if it reaches a sensitive object, it may expose credentials or create XSS-like effects. A page can also inspect or interfere with hooks in its own world. Isolated-world code reduces shared-global exposure but cannot perform page-property interception. Treat CSP behavior as an item to test, not a security guarantee or an excuse to bypass site policy. Keep list parsing separate from executable code and use only bundled static resources.

[`WKContentWorld`](https://developer.apple.com/documentation/webkit/wkcontentworld) isolation should be the default for DOM work. Page-world access is reserved for a reviewed module that truly needs page JavaScript globals. `WKUserScript` document-start timing is helpful but does not guarantee every frame, service worker, or network response is intercepted. Test CSP, top/subframe scope, script ordering, navigation reuse, and SPA route changes on supported OS releases. A site-specific module must fail open for page functionality when its assumptions fail.

## Performance and release gates

Larger source lists increase parse and rule-compile time and can add process memory; the slope depends on actual rules and WebKit compiler behavior. Static CSS adds style work. Mutation observers and page-world wrappers add ongoing cost and are higher risk. These are **estimates of direction, not measured V2 results**. Existing measured Phase 2A numbers remain in [content-blocker.md](content-blocker.md); this audit ran no V2 benchmark.

Before each activation: compare against current blocker on local fixtures and representative pages; verify normal video startup, navigation, login, downloads, private tabs, global/site bypass, cold and warm launch, memory, CPU, rule compilation, and rollback. Set numeric budgets from measured baseline before implementation rather than promising a fixed frame rate. Track false positives and provide a narrow compatibility rollback. No exact per-request blocked count can be promised through current WKWebView content-rule APIs.

## Decision matrix

| Option | Blocking gain | Cost / risk | Decision |
| --- | --- | --- | --- |
| 1. Keep current blocker | Stability, low maintenance | Known syntax cap and YouTube video ads | Acceptable fallback; does not answer broader coverage gap. |
| 2. Stage Paper V2 as above | Better list coverage, exceptions and CSS where native API supports them | Moderate parser/testing upkeep; optional runtime becomes high ongoing site-specific upkeep | **Recommended**, with runtime and YouTube deferred. |
| 3. Return to Chromium/CEF | Potential extension-level request APIs if CEF's extension support and integration actually prove adequate | Engine migration, packaging, signing, lifecycle, performance, browser-compatibility and extension-maintenance costs; previous principal-class approach failed | Do not pursue just for ad blocking. Revisit only for broader product need and a working extension-capability prototype. |

The prior [CEF feasibility](cef-feasibility.md) and [lifecycle blocker](cef-lifecycle-blocker.md) are evidence of migration cost, not proof that full uBO could simply run in CEF.

## Maintenance estimate

These are planning estimates, not observed staffing data. Network parser and list fixtures are a **moderate, continuing** commitment: source syntax and WebKit compile behavior change. CSS support is moderate if kept standards-based; procedural DOM support increases per-site regression work. Scriptlet compatibility and YouTube-specific mitigation are **high, ongoing** commitments, with potentially frequent site changes and browser-version regressions. A broad uBO parity goal would require permanent filter-maintenance, security, and compatibility ownership and is outside Paper's current scope.

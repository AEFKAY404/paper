# Blocker V2 performance — Phase 2D.2

Measured on the Apple Silicon MacBook Air, macOS 27.2 beta, Debug XCTest process, 9 October 2026. Raw records are in [benchmarks/phase2d2](benchmarks/phase2d2). These are test-process samples, not app launch or first-paint measurements. The baseline is commit `07d9b9b` (tag `phase2d2-baseline-07d9b9b`).

## Finding and cache design

The baseline fresh setup took **5.909 s** in one focused suite run. Parsing EasyList and EasyPrivacy accounted for **4.647 s (79%)**; WebKit compilation took **1.222 s (21%)**. The suite was not serialized, so this is an observed sample rather than a controlled before/after distribution. The prior Stage 1 report recorded a separate **2.994 s** cold sample. Cached setup was **0.122 s** in this baseline run.

Paper now ships versioned, validated **portable prepared rule artifacts** for the bundled EasyList and EasyPrivacy snapshots (about 5.4 MB together). They hold Paper's normalized/ranked rule representation, not compiled WebKit objects. Source SHA-256, parser version, and OS compatibility metadata determine reuse. A fresh install still asks WebKit to compile the generated JSON asynchronously; it does not block the initial window. A normal start loads the last known good compiled identifiers first and skips parse, normalize, JSON generation, and compilation when source hashes and versions match. If a compiled object is missing, Paper can reuse a prepared artifact and a versioned JSON partition cache to rebuild it. Downloaded filter sources have their own prepared artifacts and raw-source fallback. The cache is bounded on disk, and a source's active compiled set changes only after all its partitions compile successfully.

The one-sample 500-rule-partition setup recorded in [post-setup.json](benchmarks/phase2d2/post-setup.json) took **2.408 s cold** and **0.039 s cached**, with parsing eliminated. Its cold critical stages were WebKit compilation **1.467 s (61%)**, portable-artifact decode **0.178 s (7%)**, fingerprinting **0.118 s (5%)**, JSON serialization **0.215 s (9%)**, and remaining source/cache/bookkeeping time. The two sources yielded 20,000 network rules, 40 compiled lists, and 4.40 MB of WebKit JSON. A separate 1,000-rule-partition sample took **1.908 s cold**, **0.078 s cached**, and **1.084 s** of WebKit compilation; run conditions and ordering differ, so these samples are not a controlled comparison.

An integrated, rotated three-round comparison tested 500 and 1,000 rules per partition with fresh stores. Median cold setup was **1.503 s at 500** and **1.447 s at 1,000**. Median WebKit compile time was **0.995 s** and **0.948 s** respectively. Median 20-tab rule attachment was **59.6 ms** and **55.0 ms**. Cached reopen medians were **31.2 ms** and **29.6 ms**. We retained **1,000** as the production default. The [raw comparison](benchmarks/phase2d2/engine-partitions.json) includes all six rows. A separate synthetic partition-only comparison of 500/1,000/2,000 was less consistent and is also retained in the raw benchmark directory.

## Tab workload and memory limits

The [three-run rotated local fixture](benchmarks/phase2d2/post-tabs.json) reports medians for whole tab groups. “On” includes network rules and static cosmetics; “network” omits cosmetics.

| Tabs | Create off / network / on | Local load off / network / on |
| ---: | ---: | ---: |
| 1 | 5.66 / 5.84 / 6.08 ms | 88.97 / 89.04 / 87.67 ms |
| 5 | 20.46 / 18.84 / 21.05 ms | 275.37 / 274.39 / 277.74 ms |
| 10 | 30.05 / 30.21 / 29.13 ms | 451.04 / 478.74 / 479.78 ms |
| 20 | 59.75 / 59.19 / 60.76 ms | 1080.05 / 1150.00 / 1116.55 ms |

An initially observed ~733 ms 20-tab network-only creation spike came from attempting CSS-removal JavaScript evaluation on blank WebKit views. Guarding that call until a page URL exists reduced the measured median to **59 ms** in the same fixture. The prior [single-run baseline](benchmarks/phase2d2/pre-change-tabs.json) is not directly comparable to three-run medians. WebContent processes, first paint, scrolling smoothness, CPU, and temporary parsing/compile peak memory were not measured reliably; app RSS deltas in this fixture were noisy and do not establish memory overhead. A 500-selector site payload took **7.2 ms** to generate in one sample; injected CSS style cost was not isolated.

## Operational boundary

First-run navigation can begin before asynchronous compilation completes and can therefore load some unblocked resources. Cached starts attach compiled last-known-good protection without a fresh compile. Filter changes compile per source in the background and activate atomically; a failed update keeps the previous source lists. The bundled portable artifacts are regenerated from the bundled text snapshots when parser semantics change and are validated against their hashes in tests. WebKit compiled lists are never bundled across machines or OS versions.

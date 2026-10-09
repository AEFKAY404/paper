import Darwin
import Foundation
import Testing
import WebKit
@testable import Paper

/// Local fixture benchmark for blocker-on/off tab creation and load costs.
@MainActor
@Suite(.serialized)
struct ContentBlockerBenchmarkTests {
    @Test func enginePartitionSizeComparison() async throws {
        guard FileManager.default.fileExists(atPath: "/private/tmp/paper-run-engine-partitions") else { return }
        let previousAttempt = UserDefaults.standard.object(forKey: "paper.blocker.lastUpdateAttempt")
        UserDefaults.standard.set(Date(), forKey: "paper.blocker.lastUpdateAttempt")
        defer {
            if let previousAttempt { UserDefaults.standard.set(previousAttempt, forKey: "paper.blocker.lastUpdateAttempt") }
            else { UserDefaults.standard.removeObject(forKey: "paper.blocker.lastUpdateAttempt") }
        }
        var rows: [[String: Any]] = []
        for round in 0..<3 {
            for size in round.isMultiple(of: 2) ? [500, 1_000] : [1_000, 500] {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("paper-engine-size-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let engine = ContentBlockerEngine(directory: directory, partitionSize: size)
                let coldBegan = Date()
                await engine.start()
                let coldMs = Date().timeIntervalSince(coldBegan) * 1_000
                #expect(engine.rules.count == 20_000 / size)
                let restored = ContentBlockerEngine(directory: directory, partitionSize: size)
                let cacheBegan = Date()
                await restored.start()
                let cacheMs = Date().timeIntervalSince(cacheBegan) * 1_000
                #expect(restored.cacheHits == 2)
                let attachBegan = Date()
                let sessions = (0..<20).map { _ in
                    WebKitSession(websiteDataStore: .nonPersistent(), blocker: restored)
                }
                let attachMs = Date().timeIntervalSince(attachBegan) * 1_000
                sessions.forEach { $0.close() }
                rows.append(["round": round, "size": size, "coldMs": coldMs,
                             "cacheMs": cacheMs, "attach20Ms": attachMs,
                             "compileMs": engine.stageProfiles.values.reduce(0) { $0 + $1.webKitCompile * 1_000 },
                             "lists": engine.rules.count])
            }
        }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/private/tmp/paper-phase2d2-engine-partitions.json"), options: .atomic)
    }

    @Test func partitionSizing() async throws {
        guard FileManager.default.fileExists(atPath: "/private/tmp/paper-run-partition-benchmark") else { return }
        let parsed = try FilterSource.defaults.map { source in
            let url = try #require(Bundle.main.url(forResource: source.id, withExtension: "txt"))
            return FilterParser.parse(try String(contentsOf: url, encoding: .utf8))
        }
        var reports: [[String: Any]] = []
        for size in [500, 1_000, 2_000] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("paper-partitions-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try #require(WKContentRuleListStore(url: directory))
            var lists: [WKContentRuleList] = []
            var jsonBytes = 0
            let compileBegan = Date()
            for (sourceIndex, source) in parsed.enumerated() {
                for (index, partition) in RulePartitioner.partitions(for: source.network, size: size).enumerated() {
                    let json = try RuleCompiler.json(for: partition.rules)
                    jsonBytes += json.utf8.count
                    let list = try #require(try await store.compileContentRuleList(
                        forIdentifier: "size-\(size)-\(sourceIndex)-\(index)", encodedContentRuleList: json))
                    lists.append(list)
                }
            }
            let compileMs = Date().timeIntervalSince(compileBegan) * 1_000
            let reloadBegan = Date()
            for list in lists { _ = try await store.contentRuleList(forIdentifier: list.identifier) }
            let reloadMs = Date().timeIntervalSince(reloadBegan) * 1_000
            let attachBegan = Date()
            let views = (0..<20).map { _ -> WKWebView in
                let configuration = WKWebViewConfiguration()
                lists.forEach { configuration.userContentController.add($0) }
                return WKWebView(frame: .zero, configuration: configuration)
            }
            let attachMs = Date().timeIntervalSince(attachBegan) * 1_000
            views.forEach { $0.stopLoading() }
            reports.append(["size": size, "lists": lists.count, "compileMs": compileMs,
                            "reloadMs": reloadMs, "attach20Ms": attachMs, "jsonBytes": jsonBytes])
        }
        let data = try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/private/tmp/paper-phase2d2-partitions.json"), options: .atomic)
    }

    @Test func tabWorkloads() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("paper-benchmark-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = ContentBlockerEngine(directory: directory)
        let wasEnabled = blocker.policy.enabled
        let wasCosmetic = blocker.cosmeticEnabled
        blocker.setEnabled(true)
        defer { blocker.setEnabled(wasEnabled); blocker.cosmeticEnabled = wasCosmetic }
        await blocker.start()
        #expect(blocker.rules.count >= 2)
        let cosmeticBegan = Date()
        let selected = CosmeticFilterEngine.selectors(for: blocker.cosmeticRules,
                                                       host: "bench.example", disabledDomains: [])
        let cosmeticScript = CosmeticFilterEngine.script(for: blocker.cosmeticRules,
                                                          disabledDomains: [], host: "bench.example")
        let cosmeticGenerationMs = Date().timeIntervalSince(cosmeticBegan) * 1_000
        let warm = WebKitSession(websiteDataStore: .nonPersistent(), blocker: blocker)
        warm.close()
        let repeated = FileManager.default.fileExists(atPath: "/private/tmp/paper-run-blocker-benchmark")
        let repetitions = repeated ? 3 : 1
        var measurements: [[String: Any]] = []
        for count in [1, 5, 10, 20] {
            var samples: [String: [Result]] = ["off": [], "network": [], "static": []]
            let modes = ["off", "network", "static"]
            for round in 0..<repetitions {
                for offset in 0..<modes.count {
                    let mode = modes[(round + offset) % modes.count]
                    blocker.cosmeticEnabled = mode == "static"
                    let result = try await measure(count: count, blocker: mode == "off" ? nil : blocker)
                    samples[mode, default: []].append(result)
                }
            }
            let off = medianResult(samples["off"]!)
            let networkOnly = medianResult(samples["network"]!)
            let on = medianResult(samples["static"]!)
            measurements.append(["tabs": count, "offCreateMs": off.creationMs,
                                 "networkOnlyCreateMs": networkOnly.creationMs,
                                 "onCreateMs": on.creationMs, "offLoadMs": off.loadMs,
                                 "networkOnlyLoadMs": networkOnly.loadMs,
                                 "onLoadMs": on.loadMs, "offRSSBytes": off.rssDeltaBytes,
                                 "networkOnlyRSSBytes": networkOnly.rssDeltaBytes,
                                 "onRSSBytes": on.rssDeltaBytes, "repetitions": repetitions])
            print(String(format: "PAPER_BLOCKER_TABS count=%d off_create=%.1fms on_create=%.1fms off_load=%.1fms on_load=%.1fms off_rss=%lld on_rss=%lld",
                         count, off.creationMs, on.creationMs, off.loadMs, on.loadMs,
                         off.rssDeltaBytes, on.rssDeltaBytes))
        }
        if FileManager.default.fileExists(atPath: "/private/tmp/paper-run-blocker-benchmark") {
            let data = try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: "/private/tmp/paper-phase2d-v2-tabs.json"), options: .atomic)
            let cosmetic: [String: Any] = ["generationMs": cosmeticGenerationMs,
                                           "selectedSelectors": selected.count,
                                           "scriptBytes": cosmeticScript?.source.utf8.count ?? 0]
            let cosmeticData = try JSONSerialization.data(withJSONObject: cosmetic, options: [.prettyPrinted, .sortedKeys])
            try cosmeticData.write(to: URL(fileURLWithPath: "/private/tmp/paper-phase2d-v2-cosmetic.json"), options: .atomic)
        }
    }

    private func measure(count: Int, blocker: ContentBlockerEngine?) async throws -> Result {
        let before = residentBytes()
        let creationStart = Date()
        let sessions = (0..<count).map { _ in
            WebKitSession(websiteDataStore: .nonPersistent(), blocker: blocker)
        }
        let creationMs = Date().timeIntervalSince(creationStart) * 1_000
        let loadStart = Date()
        for session in sessions {
            session.webView.loadHTMLString("<html><head><title>Paper bench</title></head><body><div class='ad'>Ad</div><p>Content</p></body></html>",
                                            baseURL: URL(string: "https://bench.example"))
        }
        for _ in 0..<100 where sessions.contains(where: { $0.webView.title != "Paper bench" }) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(sessions.allSatisfy { $0.webView.title == "Paper bench" })
        let loadMs = Date().timeIntervalSince(loadStart) * 1_000
        let rssDelta = Int64(residentBytes()) - Int64(before)
        sessions.forEach { $0.close() }
        try await Task.sleep(for: .milliseconds(150))
        return Result(creationMs: creationMs, loadMs: loadMs, rssDeltaBytes: rssDelta)
    }

    private func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    private func medianResult(_ values: [Result]) -> Result {
        let middle = values.count / 2
        return Result(creationMs: values.map(\.creationMs).sorted()[middle],
                      loadMs: values.map(\.loadMs).sorted()[middle],
                      rssDeltaBytes: values.map(\.rssDeltaBytes).sorted()[middle])
    }

    private struct Result {
        let creationMs: Double
        let loadMs: Double
        let rssDeltaBytes: Int64
    }
}

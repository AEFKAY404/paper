import Darwin
import Foundation
import Testing
import WebKit
@testable import Paper

/// Local fixture benchmark for blocker-on/off tab creation and load costs.
@MainActor
struct ContentBlockerBenchmarkTests {
    @Test func tabWorkloads() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("paper-benchmark-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = ContentBlockerEngine(directory: directory)
        let wasEnabled = blocker.policy.enabled
        blocker.setEnabled(true)
        defer { blocker.setEnabled(wasEnabled) }
        await blocker.start()
        #expect(blocker.rules.count >= 2)
        let cosmeticBegan = Date()
        let selected = CosmeticFilterEngine.selectors(for: blocker.cosmeticRules,
                                                       host: "bench.example", disabledDomains: [])
        let cosmeticScript = CosmeticFilterEngine.script(for: blocker.cosmeticRules,
                                                          disabledDomains: [], host: "bench.example")
        let cosmeticGenerationMs = Date().timeIntervalSince(cosmeticBegan) * 1_000
        var measurements: [[String: Any]] = []
        for count in [1, 5, 10, 20] {
            let off = try await measure(count: count, blocker: nil)
            let on = try await measure(count: count, blocker: blocker)
            measurements.append(["tabs": count, "offCreateMs": off.creationMs,
                                 "onCreateMs": on.creationMs, "offLoadMs": off.loadMs,
                                 "onLoadMs": on.loadMs, "offRSSBytes": off.rssDeltaBytes,
                                 "onRSSBytes": on.rssDeltaBytes])
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

    private struct Result {
        let creationMs: Double
        let loadMs: Double
        let rssDeltaBytes: Int64
    }
}

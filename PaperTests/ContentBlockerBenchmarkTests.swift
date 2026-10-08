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
        await blocker.start()
        for count in [1, 5, 10, 20] {
            let off = try await measure(count: count, blocker: nil)
            let on = try await measure(count: count, blocker: blocker)
            print(String(format: "PAPER_BLOCKER_TABS count=%d off_create=%.1fms on_create=%.1fms off_load=%.1fms on_load=%.1fms off_rss=%lld on_rss=%lld",
                         count, off.creationMs, on.creationMs, off.loadMs, on.loadMs,
                         off.rssDeltaBytes, on.rssDeltaBytes))
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

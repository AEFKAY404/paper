import AppKit
import Foundation
import Testing
import WebKit
@testable import Paper

/// Opt-in network smoke. Create /private/tmp/paper-run-live-webkit before running.
@MainActor
struct ContentBlockerLiveSiteTests {
    @Test func signedOutPageLoadsAndSnapshots() async throws {
        guard FileManager.default.fileExists(atPath: "/private/tmp/paper-run-live-webkit") else { return }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("paper-phase2a-sites", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        print("PAPER_LIVE_OUTPUT \(output.path)")
        let blocker = ContentBlockerEngine()
        let wasEnabled = blocker.policy.enabled
        blocker.setEnabled(true)
        defer { blocker.setEnabled(wasEnabled) }
        await blocker.start()
        #expect(blocker.rules.count >= 2)
        #expect(blocker.isActive)
        let sites: [(String, String)] = [
            ("google", "https://www.google.com/search?q=paper+browser"),
            ("youtube", "https://www.youtube.com/"),
            ("reddit", "https://www.reddit.com/"),
            ("guardian", "https://www.theguardian.com/international"),
            ("wikipedia", "https://en.wikipedia.org/wiki/WebKit"),
            ("verge", "https://www.theverge.com/")
        ]
        var records: [[String: Any]] = []
        for (name, address) in sites {
            let session = WebKitSession(websiteDataStore: .nonPersistent(), blocker: blocker)
            let window = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 1000, height: 700),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = session.webView
            window.orderFront(nil)
            var error: String?
            session.onEvent = { event in
                if case .navigationFailed(let message) = event { error = message }
            }
            let began = Date()
            session.load(URL(string: address)!)
            for _ in 0..<150 where session.webView.title?.isEmpty != false && error == nil {
                try await Task.sleep(for: .milliseconds(100))
            }
            try await Task.sleep(for: .seconds(2))
            let seconds = Date().timeIntervalSince(began)
            let configuration = WKSnapshotConfiguration()
            configuration.snapshotWidth = NSNumber(value: 800)
            configuration.afterScreenUpdates = false
            var image = await session.snapshot(maxWidth: 800)
            if image == nil { image = try? await session.webView.takeSnapshot(configuration: configuration) }
            if let image, let tiff = image.tiffRepresentation,
               let representation = NSBitmapImageRep(data: tiff),
               let png = representation.representation(using: .png, properties: [:]) {
                try png.write(to: output.appendingPathComponent(name + ".png"))
            }
            let title = session.webView.title ?? ""
            records.append(["site": name, "url": address, "title": title,
                            "error": error ?? "", "seconds": seconds,
                            "snapshot": image != nil])
            print("PAPER_LIVE_SITE \(name) title=\(title) error=\(error ?? "none") seconds=\(String(format: "%.2f", seconds)) snapshot=\(image != nil)")
            session.close()
            window.close()
        }
        let data = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("results.json"), options: .atomic)
    }
}

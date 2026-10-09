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
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("paper-phase2d-sites", isDirectory: true)
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
            ("verge", "https://www.theverge.com/"),
            ("github", "https://github.com/"),
            ("microsoft", "https://www.microsoft.com/en-us/"),
            ("amazon", "https://www.amazon.com/"),
            ("twitch", "https://www.twitch.tv/")
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

    @Test func signedOutYouTubePlaybackIsNotBlocked() async throws {
        guard FileManager.default.fileExists(atPath: "/private/tmp/paper-run-live-webkit") else { return }
        let blocker = ContentBlockerEngine()
        blocker.setEnabled(true)
        await blocker.start()
        let session = WebKitSession(websiteDataStore: .nonPersistent(), blocker: blocker)
        let window = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 1100, height: 750),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = session.webView
        window.orderFront(nil)
        defer { session.close(); window.close() }
        session.load(URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")!)
        var playing = false
        var adObserved = false
        var startupSeconds: Int?
        for second in 0..<45 {
            try await Task.sleep(for: .seconds(1))
            let state = try? await session.webView.evaluateJavaScript("""
            (() => { const v = document.querySelector('video'); return {
              time: v?.currentTime ?? 0, ready: v?.readyState ?? 0,
              ad: !!document.querySelector('.ad-showing') }; })()
            """) as? [String: Any]
            adObserved = adObserved || (state?["ad"] as? Bool == true)
            if (state?["ready"] as? Int ?? 0) >= 2,
               (state?["time"] as? Double ?? 0) > 0.5,
               state?["ad"] as? Bool != true {
                playing = true
                startupSeconds = second + 1
                break
            }
        }
        print("PAPER_PHASE2D_YOUTUBE normalVideoPlaying=\(playing) adObserved=\(adObserved) title=\(session.webView.title ?? "")")
        #expect(playing)
        var seeked: Bool? = nil
        if playing {
            seeked = try? await session.webView.evaluateJavaScript("""
            (() => { const v = document.querySelector('video');
              if (!v || !Number.isFinite(v.duration)) return false;
              v.currentTime = Math.max(0, Math.min(v.duration - 2, v.duration / 2)); return true; })()
            """) as? Bool
            #expect(seeked == true)
        }
        let report: [String: Any] = ["normalVideoPlaying": playing, "adObserved": adObserved,
                                     "startupSeconds": startupSeconds ?? -1,
                                     "seeked": seeked ?? false,
                                     "title": session.webView.title ?? ""]
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("paper-phase2d-sites", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("youtube-playback.json"), options: .atomic)
    }
}

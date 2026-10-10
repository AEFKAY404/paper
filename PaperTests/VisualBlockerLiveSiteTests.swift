import AppKit
import Foundation
import Testing
import WebKit
@testable import Paper

/// Opt in by creating /private/tmp/paper-run-phase2e-live. Signed-out smoke only.
@MainActor
struct VisualBlockerLiveSiteTests {
    @Test func signedOutVisualSmoke() async throws {
        guard FileManager.default.fileExists(atPath: "/private/tmp/paper-run-phase2e-live") else { return }
        let output = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PaperPhase2E", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        NSLog("PAPER_PHASE2E_LIVE_OUTPUT %@", output.path)
        let blocker = ContentBlockerEngine()
        blocker.setEnabled(true)
        await blocker.start()
        let sites: [(String, String)] = [
            ("reddit", "https://www.reddit.com/"),
            ("guardian", "https://www.theguardian.com/international"),
            ("verge", "https://www.theverge.com/"),
            ("amazon", "https://www.amazon.com/"),
            ("github-login", "https://github.com/login"),
            ("youtube", "https://www.youtube.com/")
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
            session.load(URL(string: address)!)
            for _ in 0..<100 where session.webView.title?.isEmpty != false && error == nil {
                try await Task.sleep(for: .milliseconds(100))
            }
            try await Task.sleep(for: .seconds(2))
            let state = (try? await session.webView.evaluateJavaScript("""
            (() => ({title:document.title, installed:!!window.__paperVisualBlocker,
              replaced:document.querySelectorAll('[data-paper-blocked]').length,
              placeholders:document.querySelectorAll('.paper-blocked-slot').length,
              dialogs:document.querySelectorAll('dialog[open],[role="dialog"],[aria-modal="true"]').length}))()
            """) as? [String: Any]) ?? [:]
            var record = state
            record["site"] = name
            record["error"] = error ?? ""
            let image = await session.snapshot(maxWidth: 800)
            if let image, let tiff = image.tiffRepresentation,
               let representation = NSBitmapImageRep(data: tiff),
               let png = representation.representation(using: .png, properties: [:]) {
                try png.write(to: output.appendingPathComponent(name + ".png"))
                record["snapshot"] = true
            } else { record["snapshot"] = false }
            records.append(record)
            NSLog("PAPER_PHASE2E_LIVE %@ title=%@ replaced=%@ error=%@", name,
                  state["title"] as? String ?? "", String(describing: state["replaced"] ?? 0), error ?? "")
            session.close()
            window.close()
        }
        let data = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("results.json"), options: .atomic)
    }
}

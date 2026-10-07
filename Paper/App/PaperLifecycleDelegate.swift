import AppKit

@MainActor
final class PaperLifecycleDelegate: NSObject, NSApplicationDelegate {
    weak var browser: BrowserController?

    func applicationWillTerminate(_ notification: Notification) {
        browser?.shutdown()
    }
}

import AppKit

@objc(PaperApplication)
final class PaperApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
    }
}

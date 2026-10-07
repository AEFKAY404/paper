import AppKit
import Combine

/// Handles browser commands before the focused webpage receives their key events.
@MainActor
final class BrowserInputMonitor: ObservableObject {
    private var monitor: Any?
    private let gestures = GestureEngine()

    func start(browser: BrowserController, ui: BrowserUIState) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .swipe]) { [weak self, weak browser, weak ui] event in
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let code = event.keyCode
            let modifiers = event.modifierFlags.rawValue
            let isSwipe = event.type == .swipe
            let deltaX = event.deltaX
            let handled = MainActor.assumeIsolated {
                guard let self, let browser, let ui, NSApp.keyWindow != nil else { return false }
                return self.handle(key: key, code: code, modifiers: modifiers, isSwipe: isSwipe,
                                   deltaX: deltaX, browser: browser, ui: ui)
            }
            return handled ? nil : event
        }
    }

    private func handle(key: String, code: UInt16, modifiers: UInt, isSwipe: Bool, deltaX: CGFloat,
                        browser: BrowserController, ui: BrowserUIState) -> Bool {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers).intersection([.command, .control, .shift, .option])
        if isSwipe {
            guard UserDefaults.standard.bool(forKey: "paper.tabSwipe"),
                  let action = gestures.actionForOptionSwipe(deltaX: deltaX, optionHeld: flags.contains(.option)) else {
                return false
            }
            browser.selectAdjacentTab(offset: action == .nextTab ? 1 : -1)
            return true
        }
        if flags == .command {
            switch key {
            case "l": ui.openPalette(prefill: browser.activeTab?.url?.absoluteString ?? "")
            case "t": browser.newTab(); ui.openPalette()
            case "w": browser.closeActiveTab()
            case "r": browser.reload()
            case "[": browser.goBack()
            case "]": browser.goForward()
            default: return false
            }
            return true
        }
        if (flags == .control || flags == [.control, .shift]) && code == 48 {
            browser.selectAdjacentTab(offset: flags.contains(.shift) ? -1 : 1)
            return true
        }
        if ui.isPaletteVisible && code == 53 {
            ui.dismissPalette()
            browser.activeSession?.focus()
            return true
        }
        return false
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

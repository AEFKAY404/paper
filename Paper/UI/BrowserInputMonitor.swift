import AppKit
import Combine
import SwiftUI

/// Handles browser commands before the focused webpage receives their key events.
@MainActor
final class BrowserInputMonitor: ObservableObject {
    private var monitor: Any?
    private let gestures = GestureEngine()
    weak var browserWindow: NSWindow?

    func start(browser: BrowserController, ui: BrowserUIState, onboarding: OnboardingState) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .swipe]) { [weak self, weak browser, weak ui, weak onboarding] event in
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let code = event.keyCode
            let modifiers = event.modifierFlags.rawValue
            let isSwipe = event.type == .swipe
            let deltaX = event.deltaX
            let handled = MainActor.assumeIsolated {
                guard let self, let browser, let ui, let onboarding,
                      let browserWindow = self.browserWindow,
                      NSApp.keyWindow === browserWindow, !ui.isHandbookVisible else { return false }
                return self.handle(key: key, code: code, modifiers: modifiers, isSwipe: isSwipe,
                                   deltaX: deltaX, browser: browser, ui: ui, onboarding: onboarding)
            }
            return handled ? nil : event
        }
    }

    private func handle(key: String, code: UInt16, modifiers: UInt, isSwipe: Bool, deltaX: CGFloat,
                        browser: BrowserController, ui: BrowserUIState, onboarding: OnboardingState) -> Bool {
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
            case "l": ui.openPalette(prefill: browser.activeTab?.url?.absoluteString ?? ""); onboarding.locationOpened()
            case "t": browser.newTab(); onboarding.record(.newTab)
            case "w": browser.closeActiveTab(); onboarding.record(.closeTab)
            case "r": browser.reload()
            case "[": browser.goBack()
            case "]": browser.goForward()
            default: return false
            }
            return true
        }
        if (flags == .control || flags == [.control, .shift]) && code == 48 {
            browser.selectAdjacentTab(offset: flags.contains(.shift) ? -1 : 1)
            if !flags.contains(.shift) { onboarding.record(.nextTab) }
            return true
        }
        if flags == [.command, .shift] && code == 44 {
            ui.openHandbook()
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

struct BrowserWindowAnchor: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowAnchorView {
        let view = WindowAnchorView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: WindowAnchorView, context: Context) {
        nsView.onWindowChange = onWindowChange
        onWindowChange(nsView.window)
    }
}

final class WindowAnchorView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

import AppKit
import Combine
import SwiftUI

/// Handles browser commands before the focused webpage receives their key events.
@MainActor
final class BrowserInputMonitor: ObservableObject {
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var gestures = GestureEngine()
    private var voiceShortcutDown = false
    weak var browserWindow: NSWindow?

    func start(browser: BrowserController, ui: BrowserUIState, onboarding: OnboardingState,
               voice: VoiceCommandController) {
        guard monitor == nil else { return }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                 object: NSApp, queue: .main) { [voice] _ in
            MainActor.assumeIsolated { voice.cancel() }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .swipe]) { [weak self, weak browser, weak ui, weak onboarding, weak voice] event in
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let code = event.keyCode
            let modifiers = event.modifierFlags.rawValue
            let isSwipe = event.type == .swipe
            let deltaX = event.deltaX
            let deltaY = event.deltaY
            let timestamp = event.timestamp
            let handled = MainActor.assumeIsolated {
                if let voice, let self, self.voiceShortcutDown {
                    if event.type == .keyUp && code == 49 {
                        self.voiceShortcutDown = false
                        voice.end()
                        return true
                    }
                    if event.type == .flagsChanged {
                        let flags = event.modifierFlags.intersection([.command, .control, .shift, .option])
                        if flags != [.control, .shift] { voice.end() }
                    }
                }
                guard let self, let browser, let ui, let onboarding,
                      let browserWindow = self.browserWindow,
                      NSApp.keyWindow === browserWindow, !ui.isHandbookVisible else { return false }
                if event.type == .keyDown, let voice {
                    if voice.handleChooserKey(code) { return true }
                    let flags = event.modifierFlags.intersection([.command, .control, .shift, .option])
                    if code == 49 && flags == [.control, .shift] {
                        if !event.isARepeat {
                            self.voiceShortcutDown = true
                            voice.begin()
                        }
                        return true
                    }
                }
                guard event.type == .keyDown || event.type == .swipe else { return false }
                return self.handle(key: key, code: code, modifiers: modifiers, isSwipe: isSwipe,
                                   deltaX: deltaX, deltaY: deltaY, timestamp: timestamp,
                                   browser: browser, ui: ui, onboarding: onboarding)
            }
            return handled ? nil : event
        }
    }

    private func handle(key: String, code: UInt16, modifiers: UInt, isSwipe: Bool, deltaX: CGFloat,
                        deltaY: CGFloat, timestamp: TimeInterval,
                        browser: BrowserController, ui: BrowserUIState, onboarding: OnboardingState) -> Bool {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers).intersection([.command, .control, .shift, .option])
        if isSwipe {
            var configuration = InteractionPreferences().configuration
            configuration.overlayVisible = ui.isPaletteVisible || ui.isOverviewVisible || onboarding.step != nil
            guard let action = gestures.actionForSwipe(deltaX: deltaX, deltaY: deltaY,
                                                       optionOnly: flags == .option, timestamp: timestamp,
                                                       configuration: configuration) else {
                return false
            }
            switchTab(offset: action == .nextTab ? 1 : -1, browser: browser, ui: ui)
            return true
        }
        if ui.isOverviewVisible {
            if code == 53 {
                ui.dismissOverview(); ui.showFeedback("Closed tab overview")
                DispatchQueue.main.async { browser.activeSession?.focus() }
                return true
            }
            if code == 125 || code == 124 { ui.moveOverviewSelection(offset: 1, tabs: browser.tabs); return true }
            if code == 126 || code == 123 { ui.moveOverviewSelection(offset: -1, tabs: browser.tabs); return true }
            if code == 36, let id = ui.overviewSelectionID {
                BrowserActionRouter.perform(.switchTab(id), browser: browser, ui: ui, onboarding: onboarding)
                return true
            }
        }
        if flags == [.command, .shift] && code == 42 {
            BrowserActionRouter.perform(.overview, browser: browser, ui: ui, onboarding: onboarding)
            return true
        }
        if flags == .command {
            switch key {
            case "l": ui.openPalette(prefill: browser.activeTab?.url?.absoluteString ?? ""); onboarding.locationOpened()
            case "t": BrowserActionRouter.perform(.newTab, browser: browser, ui: ui, onboarding: onboarding)
            case "w": BrowserActionRouter.perform(.closeTab, browser: browser, ui: ui, onboarding: onboarding)
            case "r": BrowserActionRouter.perform(.reload, browser: browser, ui: ui, onboarding: onboarding)
            case "[": BrowserActionRouter.perform(.back, browser: browser, ui: ui, onboarding: onboarding)
            case "]": BrowserActionRouter.perform(.forward, browser: browser, ui: ui, onboarding: onboarding)
            default: return false
            }
            return true
        }
        if (flags == .control || flags == [.control, .shift]) && code == 48 {
            switchTab(offset: flags.contains(.shift) ? -1 : 1, browser: browser, ui: ui)
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

    private func switchTab(offset: Int, browser: BrowserController, ui: BrowserUIState) {
        let index = browser.tabs.firstIndex { $0.id == browser.activeTabID } ?? 0
        let count = browser.tabs.count
        browser.selectAdjacentTab(offset: offset)
        if count <= 1 { ui.showFeedback("Only one tab") }
        else if offset > 0 && index == count - 1 { ui.showFeedback("First tab") }
        else if offset < 0 && index == 0 { ui.showFeedback("Last tab") }
        else { ui.showFeedback(browser.activeTab?.title ?? "Tab") }
    }

    func stop() {
        voiceShortcutDown = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
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

import AppKit
import Combine
import SwiftUI

enum PaperSurfaceBackground {
    static var nativeColor: NSColor { .windowBackgroundColor }
    static var color: Color { Color(nsColor: nativeColor) }

    static func resolvedNativeColor(for scheme: ColorScheme) -> NSColor {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
        var resolved = nativeColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = nativeColor.usingColorSpace(.deviceRGB) ?? nativeColor
        }
        return resolved
    }

    static func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
    }
}

@MainActor
final class PaperTitleBarStyler: ObservableObject {
    private weak var window: NSWindow?
    private var color = PaperSurfaceBackground.nativeColor

    func attach(_ window: NSWindow?) {
        guard self.window !== window else { return }
        self.window = window
        PaperSurfaceBackground.configure(window)
        window?.backgroundColor = color
    }

    func update(_ color: NSColor) {
        self.color = color
        guard let window, window.backgroundColor != color else { return }
        window.backgroundColor = color
    }
}

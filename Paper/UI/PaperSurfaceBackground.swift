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

/// A quiet desktop-backed surface for native new tabs. The opaque base prevents
/// an old webpage from showing through while the active tab changes.
struct PaperNewTabSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            PaperSurfaceBackground.color
            if !reduceTransparency {
                PaperWindowMaterial()
                PaperSurfaceBackground.color.opacity(colorScheme == .dark ? 0.90 : 0.88)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PaperWindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
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

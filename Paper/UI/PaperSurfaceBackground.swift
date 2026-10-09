import AppKit
import Combine
import SwiftUI

enum PaperSurfaceBackground {
    nonisolated static let transparencyKey = "paper.newTabTransparency"
    nonisolated static let defaultTransparency = 30.0
    static var nativeColor: NSColor { .windowBackgroundColor }
    static var color: Color { Color(nsColor: nativeColor) }

    nonisolated static func materialFraction(for percentage: Double) -> Double {
        min(100, max(0, percentage)) / 100
    }

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

/// A desktop-backed surface for native new tabs. The opaque base prevents an
/// old webpage from showing through while the active tab changes.
struct PaperNewTabSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(PaperSurfaceBackground.transparencyKey)
    private var transparency = PaperSurfaceBackground.defaultTransparency

    var body: some View {
        ZStack {
            PaperSurfaceBackground.color
            if !reduceTransparency && PaperSurfaceBackground.materialFraction(for: transparency) > 0 {
                PaperWindowMaterial()
                PaperSurfaceBackground.color.opacity(1 - PaperSurfaceBackground.materialFraction(for: transparency))
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
    private var translucent = false

    func attach(_ window: NSWindow?) {
        guard self.window !== window else { return }
        self.window = window
        PaperSurfaceBackground.configure(window)
        window?.isOpaque = !translucent
        window?.backgroundColor = translucent ? .clear : color
    }

    func update(_ color: NSColor, translucent: Bool = false) {
        self.color = color
        self.translucent = translucent
        guard let window else { return }
        let background = translucent ? NSColor.clear : color
        if window.isOpaque == translucent { window.isOpaque = !translucent }
        if window.backgroundColor != background { window.backgroundColor = background }
    }
}

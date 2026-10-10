import AppKit
import Combine
import SwiftUI

enum PaperSurfaceBackground {
    nonisolated static let transparencyKey = "paper.newTabTransparency"
    nonisolated static let defaultTransparency = 30.0
    nonisolated static let tintKey = "paper.newTabTint"
    nonisolated static let blurKey = "paper.newTabBlur"
    nonisolated static let maximumTintOpacity = 0.68
    static var nativeColor: NSColor { .windowBackgroundColor }
    static var color: Color { Color(nsColor: nativeColor) }

    nonisolated static var initialEffectPercentage: Double {
        let stored = UserDefaults.standard.object(forKey: transparencyKey) as? Double
        return stored ?? defaultTransparency
    }

    nonisolated static func fraction(for percentage: Double) -> Double {
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

/// The blur slider controls material visibility. At zero, the surface itself
/// is clear; Reduce Transparency always restores an opaque Paper background.
struct PaperNewTabSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(PaperSurfaceBackground.tintKey)
    private var tint = PaperSurfaceBackground.initialEffectPercentage
    @AppStorage(PaperSurfaceBackground.blurKey)
    private var blur = PaperSurfaceBackground.initialEffectPercentage

    var body: some View {
        ZStack {
            if reduceTransparency {
                PaperSurfaceBackground.color
            } else {
                Color.clear
                if PaperSurfaceBackground.fraction(for: blur) > 0 {
                    PaperWindowMaterial()
                        .opacity(PaperSurfaceBackground.fraction(for: blur))
                    PaperSurfaceBackground.color.opacity(
                        PaperSurfaceBackground.maximumTintOpacity *
                        PaperSurfaceBackground.fraction(for: tint) *
                        PaperSurfaceBackground.fraction(for: blur))
                }
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

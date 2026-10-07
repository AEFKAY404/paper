import CoreGraphics
import Foundation

enum BrowserGestureAction: Equatable {
    case nextTab
    case previousTab
}

enum TabSwitchGesture: String, CaseIterable, Identifiable {
    case disabled
    case optionSwipe

    var id: String { rawValue }
    var title: String {
        switch self {
        case .disabled: "Off"
        case .optionSwipe: "Option + horizontal swipe (experimental)"
        }
    }
}

struct GestureConfiguration {
    var customGesturesEnabled: Bool
    var tabSwitchGesture: TabSwitchGesture
    var overlayVisible: Bool
}

/// Resolves deliberate discrete AppKit swipe events; ordinary scroll events never enter this API.
struct GestureEngine {
    private(set) var lastActionTime: TimeInterval = -.infinity

    mutating func actionForSwipe(deltaX: CGFloat, deltaY: CGFloat, optionOnly: Bool,
                                 timestamp: TimeInterval, configuration: GestureConfiguration) -> BrowserGestureAction? {
        guard configuration.customGesturesEnabled,
              configuration.tabSwitchGesture == .optionSwipe,
              !configuration.overlayVisible,
              optionOnly,
              abs(deltaX) >= 0.65,
              abs(deltaX) > abs(deltaY) * 1.5,
              timestamp - lastActionTime >= 0.28 else { return nil }
        lastActionTime = timestamp
        return deltaX < 0 ? .nextTab : .previousTab
    }
}

import CoreGraphics

enum BrowserGestureAction: Equatable {
    case nextTab
    case previousTab
}

/// Translates deliberate discrete swipes into browser actions without seeing a web view.
struct GestureEngine {
    func actionForOptionSwipe(deltaX: CGFloat, optionHeld: Bool) -> BrowserGestureAction? {
        guard optionHeld, abs(deltaX) >= 0.5 else { return nil }
        return deltaX < 0 ? .nextTab : .previousTab
    }
}

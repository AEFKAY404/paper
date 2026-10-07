import Foundation

struct InteractionPreferences {
    static let customGesturesKey = "paper.interaction.customGestures"
    static let tabGestureKey = "paper.interaction.tabGesture"
    static let feedbackKey = "paper.interaction.feedback"
    static let reduceMotionKey = "paper.interaction.reduceMotion"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var configuration: GestureConfiguration {
        GestureConfiguration(
            customGesturesEnabled: defaults.bool(forKey: Self.customGesturesKey),
            tabSwitchGesture: TabSwitchGesture(rawValue: defaults.string(forKey: Self.tabGestureKey) ?? "") ?? .optionSwipe,
            overlayVisible: false
        )
    }

    var feedbackEnabled: Bool { defaults.object(forKey: Self.feedbackKey) as? Bool ?? true }
    var reducedMotion: Bool { defaults.bool(forKey: Self.reduceMotionKey) }

    func migrateLegacyGestureSetting() {
        guard defaults.object(forKey: Self.customGesturesKey) == nil,
              defaults.bool(forKey: "paper.tabSwipe") else { return }
        defaults.set(true, forKey: Self.customGesturesKey)
        defaults.set(TabSwitchGesture.optionSwipe.rawValue, forKey: Self.tabGestureKey)
    }
}

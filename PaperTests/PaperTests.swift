import AppKit
import Testing
@testable import Paper

@MainActor
private final class MockSession: BrowserSession {
    let view = NSView()
    var onEvent: ((BrowserEvent) -> Void)?
    var loadedURLs: [URL] = []
    var backCount = 0
    var forwardCount = 0
    var reloadCount = 0
    var closed = false
    var snapshotCalls = 0
    var snapshotDelayMs = 0
    var snapshotImage: NSImage?

    func load(_ url: URL) {
        loadedURLs.append(url)
        onEvent?(.urlChanged(url))
    }
    func goBack() { backCount += 1 }
    func goForward() { forwardCount += 1 }
    func reload() { reloadCount += 1 }
    func stop() {}
    func focus() {}
    func setHistorySwipe(enabled: Bool) {}
    func snapshot(maxWidth: CGFloat) async -> NSImage? {
        snapshotCalls += 1
        if snapshotDelayMs > 0 { try? await Task.sleep(for: .milliseconds(snapshotDelayMs)) }
        return snapshotImage
    }
    func close() { closed = true }
}

@MainActor
private final class MockEngine: BrowserEngine {
    var sessions: [MockSession] = []
    func makeSession() -> any BrowserSession {
        let session = MockSession()
        sessions.append(session)
        return session
    }
}

@MainActor
struct PaperTests {
    private func makeController() -> (BrowserController, MockEngine, SessionStore) {
        let engine = MockEngine()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = SessionStore(defaults: defaults)
        return (BrowserController(engine: engine, store: store), engine, store)
    }

    @Test func navigationAndTabLifecycle() {
        let (controller, engine, _) = makeController()
        controller.start()
        #expect(controller.tabs.count == 1)
        controller.navigate("example.com")
        #expect(engine.sessions[0].loadedURLs.last?.absoluteString == "https://example.com")
        controller.goBack()
        controller.goForward()
        controller.reload()
        #expect(engine.sessions[0].backCount == 1)
        #expect(engine.sessions[0].forwardCount == 1)
        #expect(engine.sessions[0].reloadCount == 1)

        let firstID = controller.activeTabID
        let secondID = controller.newTab(url: URL(string: "https://swift.org"))
        #expect(controller.activeTabID == secondID)
        controller.selectAdjacentTab(offset: 1)
        #expect(controller.activeTabID == firstID)
        controller.closeTab(secondID)
        #expect(engine.sessions[1].closed)
        #expect(controller.tabs.count == 1)
    }

    @Test func restorationPreservesOrderAndActiveTab() {
        let (controller, _, store) = makeController()
        controller.start()
        let first = controller.activeTabID!
        controller.navigate("example.com")
        controller.newTab(url: URL(string: "https://swift.org"))
        controller.activate(first)

        let newEngine = MockEngine()
        let restored = BrowserController(engine: newEngine, store: store)
        restored.start()
        #expect(restored.tabs.map(\.url?.absoluteString) == ["https://example.com", "https://swift.org"])
        #expect(restored.activeTabID == restored.tabs[0].id)
    }

    @Test func shutdownClosesSessionsButPreservesSnapshot() {
        let (controller, engine, store) = makeController()
        controller.start()
        controller.navigate("example.com")
        controller.newTab(url: URL(string: "https://swift.org"))
        controller.shutdown()
        let allClosed = engine.sessions.allSatisfy { $0.closed }
        #expect(allClosed)
        #expect(controller.tabs.isEmpty)
        #expect(store.load()?.urls.compactMap { $0?.host } == ["example.com", "swift.org"])
    }

    @Test func navigationInput() {
        #expect(NavigationInput.url(for: "https://example.com/a", searchEngine: .google)?.absoluteString == "https://example.com/a")
        #expect(NavigationInput.url(for: "example.com", searchEngine: .google)?.absoluteString == "https://example.com")
        #expect(NavigationInput.url(for: "paper browser", searchEngine: .google)?.absoluteString == "https://www.google.com/search?q=paper%20browser")
        #expect(NavigationInput.url(for: "paper & browser", searchEngine: .google)?.query == "q=paper%20%26%20browser")
        #expect(NavigationInput.url(for: "  ", searchEngine: .google) == nil)
    }

    @Test func deliberateTabSwipeMapping() {
        var gestures = GestureEngine()
        let enabled = GestureConfiguration(customGesturesEnabled: true, tabSwitchGesture: .optionSwipe, overlayVisible: false)
        #expect(gestures.actionForSwipe(deltaX: -1, deltaY: 0, optionOnly: false, timestamp: 1, configuration: enabled) == nil)
        #expect(gestures.actionForSwipe(deltaX: -0.2, deltaY: 0, optionOnly: true, timestamp: 1, configuration: enabled) == nil)
        #expect(gestures.actionForSwipe(deltaX: -1, deltaY: 0, optionOnly: true, timestamp: 1, configuration: enabled) == .nextTab)
        #expect(gestures.actionForSwipe(deltaX: 1, deltaY: 0, optionOnly: true, timestamp: 1.1, configuration: enabled) == nil)
        #expect(gestures.actionForSwipe(deltaX: 1, deltaY: 0, optionOnly: true, timestamp: 1.4, configuration: enabled) == .previousTab)
        #expect(gestures.actionForSwipe(deltaX: 1, deltaY: 1, optionOnly: true, timestamp: 2, configuration: enabled) == nil)
        #expect(gestures.actionForSwipe(deltaX: 1, deltaY: 0, optionOnly: true, timestamp: 2,
                                        configuration: GestureConfiguration(customGesturesEnabled: true, tabSwitchGesture: .optionSwipe, overlayVisible: true)) == nil)
        #expect(gestures.actionForSwipe(deltaX: 1, deltaY: 0, optionOnly: true, timestamp: 2,
                                        configuration: GestureConfiguration(customGesturesEnabled: false, tabSwitchGesture: .optionSwipe, overlayVisible: false)) == nil)
    }

    @Test func legacyGesturePreferenceMigration() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "paper.tabSwipe")
        let preferences = InteractionPreferences(defaults: defaults)
        preferences.migrateLegacyGestureSetting()
        #expect(preferences.configuration.customGesturesEnabled)
        #expect(preferences.configuration.tabSwitchGesture == .optionSwipe)
        defaults.set(false, forKey: InteractionPreferences.customGesturesKey)
        preferences.migrateLegacyGestureSetting()
        #expect(!preferences.configuration.customGesturesEnabled)
    }

    @Test func newTabIsNativeStateAndGoogleIsDefault() {
        let (controller, engine, store) = makeController()
        controller.start(restorePreviousSession: false)
        #expect(controller.activeTab?.kind == .newTab)
        #expect(controller.activeTab?.url == nil)
        #expect(engine.sessions[0].loadedURLs.isEmpty)
        #expect(store.load()?.kinds == [.newTab])
        controller.navigate("paper & browser")
        #expect(controller.activeTab?.kind == .webpage)
        #expect(engine.sessions[0].loadedURLs.last?.host == "www.google.com")
        #expect(engine.sessions[0].loadedURLs.last?.query == "q=paper%20%26%20browser")
    }

    @Test func legacySessionMigratesExplicitTabKinds() throws {
        let oldJSON = Data(#"{"urls":[null,"https://example.com"],"activeIndex":1}"#.utf8)
        let session = try JSONDecoder().decode(SavedSession.self, from: oldJSON)
        #expect(session.kinds == [.newTab, .webpage])
        let encoded = try JSONEncoder().encode(session)
        #expect(String(decoding: encoded, as: UTF8.self).contains("kinds"))
    }

    @Test func onboardingPersistenceAndPractice() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let state = OnboardingState(defaults: defaults)
        state.showIfNeeded()
        #expect(state.step == .navigate)
        state.locationOpened()
        state.continueFromLocation()
        #expect(state.step == .search)
        state.submitPractice("example.com")
        #expect(state.step == .tabs)
        state.record(.newTab)
        state.record(.nextTab)
        state.record(.closeTab)
        #expect(state.tabActions.count == 3)
        state.complete()
        #expect(state.step == nil)
        let nextLaunch = OnboardingState(defaults: defaults)
        nextLaunch.showIfNeeded()
        #expect(nextLaunch.step == nil)
        nextLaunch.reopen()
        #expect(nextLaunch.step == .navigate)
        nextLaunch.skip()
        #expect(nextLaunch.step == nil)
    }

    @Test func handbookPaletteRouting() {
        #expect(PaletteAction.resolve("Help") == .handbook)
        #expect(PaletteAction.resolve("paper handbook") == .handbook)
        #expect(PaletteAction.resolve("example.com") == .navigate("example.com"))
        #expect(PaletteAction.resolve(" ") == .none)
        let ui = BrowserUIState()
        ui.openPalette()
        ui.openHandbook()
        #expect(ui.isHandbookVisible)
        #expect(!ui.isPaletteVisible)
    }

    @Test func overviewFilteringActivationAndClosure() {
        let (browser, _, _) = makeController()
        browser.start(restorePreviousSession: false)
        let first = browser.activeTabID!
        let second = browser.newTab(url: URL(string: "https://example.com"))
        let ui = BrowserUIState()
        ui.openOverview(browser: browser)
        #expect(ui.isOverviewVisible)
        ui.overviewQuery = "example"
        #expect(ui.filteredTabs(browser.tabs).map(\.id) == [second])
        ui.moveOverviewSelection(offset: 1, tabs: browser.tabs)
        #expect(ui.overviewSelectionID == second)
        let onboarding = OnboardingState(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        BrowserActionRouter.perform(.switchTab(first), browser: browser, ui: ui, onboarding: onboarding)
        #expect(browser.activeTabID == first)
        #expect(!ui.isOverviewVisible)
        browser.closeTab(second)
        #expect(browser.tabs.count == 1)
    }

    @Test func paletteSuggestionsAndRouting() {
        let (browser, _, _) = makeController()
        browser.start(restorePreviousSession: false)
        let ui = BrowserUIState()
        let onboarding = OnboardingState(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(PaletteSuggestion.matching("overview", tabs: browser.tabs).first?.action == .overview)
        #expect(PaletteSuggestion.matching("settings", tabs: browser.tabs).first?.action == .settings)
        BrowserActionRouter.perform(.newTab, browser: browser, ui: ui, onboarding: onboarding)
        #expect(browser.tabs.count == 2)
        BrowserActionRouter.perform(.overview, browser: browser, ui: ui, onboarding: onboarding)
        #expect(ui.isOverviewVisible)
        BrowserActionRouter.perform(.closeTab, browser: browser, ui: ui, onboarding: onboarding)
        #expect(browser.tabs.count == 1)
        var settingsOpened = false
        BrowserActionRouter.perform(.settings, browser: browser, ui: ui, onboarding: onboarding,
                                    openSettings: { settingsOpened = true })
        #expect(settingsOpened)
    }

    @Test func snapshotQueueIsBoundedAndCacheReused() async {
        let (browser, engine, _) = makeController()
        browser.start(restorePreviousSession: false)
        for index in 0..<20 {
            browser.newTab(url: URL(string: "https://example.com/\(index)"), activate: false)
            engine.sessions[index + 1].snapshotDelayMs = 10
            engine.sessions[index + 1].snapshotImage = NSImage(size: NSSize(width: 100, height: 60))
        }
        let previews = TabPreviewStore()
        previews.present(browser: browser)
        #expect(previews.inFlightCount == 0)
        for tab in browser.tabs where tab.kind == .webpage { previews.cardAppeared(tab.id, browser: browser) }
        #expect(previews.inFlightCount <= 2)
        try? await Task.sleep(for: .milliseconds(350))
        #expect(previews.maxInFlightObserved <= 2)
        #expect(previews.cacheCount <= TabPreviewStore.maxEntries)
        #expect(previews.cacheBytes <= TabPreviewStore.maxCacheBytes)
        let cached = browser.tabs[2].id
        let calls = engine.sessions[2].snapshotCalls
        previews.request(cached, browser: browser)
        #expect(engine.sessions[2].snapshotCalls == calls)
        engine.sessions[2].onEvent?(.navigationSucceeded)
        previews.reconcile(browser: browser)
        #expect(previews.previews[cached] == nil)
        previews.removeTab(cached)
        browser.closeTab(cached)
        #expect(previews.previews[cached] == nil)
        previews.dismiss()
        #expect(previews.inFlightCount <= 2)
    }

    @Test func interactionPreferencesPersistAndMotionCanBeDisabled() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: InteractionPreferences.customGesturesKey)
        defaults.set(TabSwitchGesture.disabled.rawValue, forKey: InteractionPreferences.tabGestureKey)
        defaults.set(false, forKey: InteractionPreferences.feedbackKey)
        defaults.set(true, forKey: InteractionPreferences.reduceMotionKey)
        let prefs = InteractionPreferences(defaults: defaults)
        #expect(prefs.configuration.customGesturesEnabled)
        #expect(prefs.configuration.tabSwitchGesture == .disabled)
        #expect(!prefs.feedbackEnabled)
        #expect(prefs.reducedMotion)
        #expect(PaperMotion.overlay(reduceMotion: prefs.reducedMotion) == nil)
    }

    @Test func snapshotQueueBenchmarkWorkloads() async throws {
        var rows: [[String: Any]] = []
        for count in [1, 5, 10, 20] {
            let (browser, engine, _) = makeController()
            browser.start(restorePreviousSession: false)
            for index in 0..<count {
                browser.newTab(url: URL(string: "https://example.com/\(index)"), activate: false)
                engine.sessions[index + 1].snapshotDelayMs = 15
                engine.sessions[index + 1].snapshotImage = NSImage(size: NSSize(width: 320, height: 180))
            }
            let previews = TabPreviewStore()
            let openStart = CFAbsoluteTimeGetCurrent()
            previews.present(browser: browser)
            let openMs = (CFAbsoluteTimeGetCurrent() - openStart) * 1_000
            let captureStart = CFAbsoluteTimeGetCurrent()
            for tab in browser.tabs where tab.kind == .webpage { previews.cardAppeared(tab.id, browser: browser) }
            for _ in 0..<200 {
                let completed = engine.sessions.dropFirst().reduce(0) { $0 + $1.snapshotCalls }
                if completed == count && previews.inFlightCount == 0 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let captureMs = (CFAbsoluteTimeGetCurrent() - captureStart) * 1_000
            rows.append(["tabs": count, "overviewStateMs": openMs, "queueCompletionMs": captureMs,
                         "cacheBytes": previews.cacheBytes, "cacheEntries": previews.cacheCount,
                         "maxConcurrent": previews.maxInFlightObserved])
            #expect(previews.maxInFlightObserved <= 2)
            #expect(previews.cacheBytes <= TabPreviewStore.maxCacheBytes)
            previews.dismiss()
            browser.shutdown()
        }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("paper-phase1b-bench.json")
        try data.write(to: output)
        print("PAPER_BENCH_OUTPUT=\(output.path)")
    }
}

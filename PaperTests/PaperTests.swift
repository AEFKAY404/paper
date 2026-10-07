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

    func load(_ url: URL) {
        loadedURLs.append(url)
        onEvent?(.urlChanged(url))
    }
    func goBack() { backCount += 1 }
    func goForward() { forwardCount += 1 }
    func reload() { reloadCount += 1 }
    func stop() {}
    func focus() {}
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
        let gestures = GestureEngine()
        #expect(gestures.actionForOptionSwipe(deltaX: -1, optionHeld: false) == nil)
        #expect(gestures.actionForOptionSwipe(deltaX: -0.2, optionHeld: true) == nil)
        #expect(gestures.actionForOptionSwipe(deltaX: -1, optionHeld: true) == .nextTab)
        #expect(gestures.actionForOptionSwipe(deltaX: 1, optionHeld: true) == .previousTab)
    }
}

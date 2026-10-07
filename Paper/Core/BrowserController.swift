import Combine
import Foundation

struct BrowserTab: Identifiable {
    let id: UUID
    var url: URL?
    var title: String
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var error: String?
}

@MainActor
final class BrowserController: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published private(set) var activeTabID: UUID?

    private let engine: any BrowserEngine
    private let store: SessionStore
    private var sessions: [UUID: any BrowserSession] = [:]

    init(engine: any BrowserEngine, store: SessionStore) {
        self.engine = engine
        self.store = store
    }

    var activeTab: BrowserTab? { tabs.first { $0.id == activeTabID } }
    var activeSession: (any BrowserSession)? { activeTabID.flatMap { sessions[$0] } }

    func start(restorePreviousSession: Bool = true, initialURL: URL? = nil) {
        guard tabs.isEmpty else { return }
        if restorePreviousSession, let saved = store.load(), !saved.urls.isEmpty {
            for url in saved.urls { newTab(url: url, activate: false) }
            let index = min(max(saved.activeIndex, 0), tabs.count - 1)
            activate(tabs[index].id)
        } else {
            newTab(url: initialURL)
        }
    }

    @discardableResult
    func newTab(url: URL? = nil, activate shouldActivate: Bool = true) -> UUID {
        let id = UUID()
        let session = engine.makeSession()
        let tab = BrowserTab(id: id, url: url, title: "New Tab")
        session.onEvent = { [weak self] event in self?.apply(event, to: id) }
        sessions[id] = session
        tabs.append(tab)
        if shouldActivate { activate(id) }
        if let url { session.load(url) }
        save()
        return id
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTabID == id
        sessions.removeValue(forKey: id)?.close()
        tabs.remove(at: index)
        if wasActive {
            activeTabID = nil
            if !tabs.isEmpty { activate(tabs[min(index, tabs.count - 1)].id) }
        }
        if tabs.isEmpty { newTab() } else { save() }
    }

    func closeActiveTab() {
        if let activeTabID { closeTab(activeTabID) }
    }

    func activate(_ id: UUID) {
        guard sessions[id] != nil else { return }
        activeTabID = id
        sessions[id]?.focus()
        save()
    }

    func selectAdjacentTab(offset: Int) {
        guard let id = activeTabID,
              let index = tabs.firstIndex(where: { $0.id == id }),
              !tabs.isEmpty else { return }
        activate(tabs[(index + offset + tabs.count) % tabs.count].id)
    }

    func navigate(_ input: String, searchEngine: SearchEngine = .duckDuckGo) {
        guard let url = NavigationInput.url(for: input, searchEngine: searchEngine) else { return }
        if let index = tabs.firstIndex(where: { $0.id == activeTabID }) {
            tabs[index].error = nil
            tabs[index].url = url
            save()
        }
        if activeSession == nil { newTab(url: url) }
        else { activeSession?.load(url) }
    }

    func goBack() { clearActiveError(); activeSession?.goBack() }
    func goForward() { clearActiveError(); activeSession?.goForward() }
    func reload() { clearActiveError(); activeSession?.reload() }
    func stop() { activeSession?.stop() }

    func shutdown() {
        save()
        sessions.values.forEach { $0.close() }
        sessions.removeAll()
        tabs.removeAll()
        activeTabID = nil
    }

    func save() {
        let urls = tabs.map { $0.url }
        let index = tabs.firstIndex { $0.id == activeTabID } ?? 0
        store.save(SavedSession(urls: urls, activeIndex: index))
    }

    private func clearActiveError() {
        if let index = tabs.firstIndex(where: { $0.id == activeTabID }) { tabs[index].error = nil }
    }

    private func apply(_ event: BrowserEvent, to id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        switch event {
        case .urlChanged(let url):
            if let url {
                tabs[index].url = url
                save()
            }
        case .titleChanged(let title): tabs[index].title = title
        case .loadingChanged(let loading): tabs[index].isLoading = loading
        case .navigationChanged(let back, let forward):
            tabs[index].canGoBack = back
            tabs[index].canGoForward = forward
        case .navigationFailed(let message): tabs[index].error = message
        case .navigationSucceeded: tabs[index].error = nil
        case .openNewTab(let url): newTab(url: url)
        }
    }
}

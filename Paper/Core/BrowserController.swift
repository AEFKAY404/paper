import AppKit
import Combine
import Foundation

struct BrowserTab: Identifiable {
    let id: UUID
    var kind: BrowserTabKind
    var privacyMode: TabPrivacyMode = .standard
    var url: URL?
    var title: String
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var error: String?
    var previewRevision = 0
    var surfaceColor: NSColor?
    var surfaceRevision = 0
    var blockerStatistics = BlockerStatistics()
}

enum TabPrivacyMode: String, Codable, Equatable {
    case standard, `private`

    var savedDownloadNotice: String? {
        self == .private ? "Files saved from private tabs remain on disk after the tab closes." : nil
    }
}

enum BrowserTabKind: String, Codable, Equatable {
    case newTab
    case webpage
}

@MainActor
final class BrowserController: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published private(set) var activeTabID: UUID?

    private let engine: any BrowserEngine
    private let store: SessionStore
    private var sessions: [UUID: any BrowserSession] = [:]
    private var lastStandardActiveTabID: UUID?

    init(engine: any BrowserEngine, store: SessionStore) {
        self.engine = engine
        self.store = store
    }

    var activeTab: BrowserTab? { tabs.first { $0.id == activeTabID } }
    var activeSession: (any BrowserSession)? { activeTabID.flatMap { sessions[$0] } }

    func start(restorePreviousSession: Bool = true, initialURL: URL? = nil) {
        guard tabs.isEmpty else { return }
        if restorePreviousSession, let saved = store.load(), !saved.urls.isEmpty {
            for (offset, url) in saved.urls.enumerated() {
                let id = newTab(url: url, activate: false)
                if tabs[offset].id == id { tabs[offset].kind = saved.kinds[offset] }
            }
            let index = min(max(saved.activeIndex, 0), tabs.count - 1)
            activate(tabs[index].id)
        } else {
            newTab(url: initialURL)
        }
    }

    @discardableResult
    func newTab(url: URL? = nil, activate shouldActivate: Bool = true,
                privacyMode: TabPrivacyMode = .standard) -> UUID {
        let id = UUID()
        let session = engine.makeSession(privacyMode: privacyMode)
        let tab = BrowserTab(id: id, kind: url == nil ? .newTab : .webpage,
                             privacyMode: privacyMode, url: url, title: "New Tab")
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
        if tabs.first(where: { $0.id == id })?.privacyMode == .standard {
            lastStandardActiveTabID = id
        }
        sessions[id]?.focus()
        sessions[id]?.refreshSurfaceColor()
        save()
    }

    func selectAdjacentTab(offset: Int) {
        guard let id = activeTabID,
              let index = tabs.firstIndex(where: { $0.id == id }),
              !tabs.isEmpty else { return }
        activate(tabs[(index + offset + tabs.count) % tabs.count].id)
    }

    func navigate(_ input: String, searchEngine: SearchEngine = .google) {
        guard let url = NavigationInput.url(for: input, searchEngine: searchEngine) else { return }
        if let index = tabs.firstIndex(where: { $0.id == activeTabID }) {
            tabs[index].error = nil
            tabs[index].kind = .webpage
            tabs[index].url = url
            tabs[index].previewRevision += 1
            save()
        }
        if activeSession == nil { newTab(url: url) }
        else { activeSession?.load(url) }
    }

    func goBack() { clearActiveError(); activeSession?.goBack() }
    func goForward() { clearActiveError(); activeSession?.goForward() }
    func reload() { clearActiveError(); activeSession?.reload() }
    func stop() { activeSession?.stop() }

    func setHistorySwipe(enabled: Bool) {
        sessions.values.forEach { $0.setHistorySwipe(enabled: enabled) }
    }

    func snapshot(for id: UUID, maxWidth: CGFloat) async -> NSImage? {
        guard let tab = tabs.first(where: { $0.id == id }),
              tab.kind == .webpage, !tab.isLoading, tab.error == nil,
              let session = sessions[id] else { return nil }
        return await session.snapshot(maxWidth: maxWidth)
    }

    func shutdown() {
        save()
        sessions.values.forEach { $0.close() }
        sessions.removeAll()
        tabs.removeAll()
        activeTabID = nil
        lastStandardActiveTabID = nil
    }

    func save() {
        let standardTabs = tabs.filter { $0.privacyMode == .standard }
        let index = standardTabs.firstIndex { $0.id == (activeTab?.privacyMode == .standard ? activeTabID : lastStandardActiveTabID) } ?? 0
        store.save(SavedSession(urls: standardTabs.map(\.url), activeIndex: index,
                                kinds: standardTabs.map(\.kind)))
    }

    private func clearActiveError() {
        if let index = tabs.firstIndex(where: { $0.id == activeTabID }) { tabs[index].error = nil }
    }

    private func apply(_ event: BrowserEvent, to id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        switch event {
        case .urlChanged(let url):
            if let url {
                if tabs[index].url != url { tabs[index].previewRevision += 1 }
                tabs[index].kind = .webpage
                tabs[index].url = url
                save()
            }
        case .titleChanged(let title): tabs[index].title = title
        case .loadingChanged(let loading): tabs[index].isLoading = loading
        case .navigationChanged(let back, let forward):
            tabs[index].canGoBack = back
            tabs[index].canGoForward = forward
        case .navigationFailed(let message):
            tabs[index].error = message
            tabs[index].previewRevision += 1
        case .navigationSucceeded:
            tabs[index].error = nil
            tabs[index].previewRevision += 1
        case .surfaceColorChanged(let color):
            if tabs[index].surfaceColor != color {
                tabs[index].surfaceColor = color
                tabs[index].surfaceRevision += 1
            }
        case .blockerStatistics(let statistics):
            tabs[index].blockerStatistics = statistics
        case .openNewTab(let url): newTab(url: url, privacyMode: tabs[index].privacyMode)
        }
    }
}

import AppKit
import Combine
import Foundation

/// An on-demand, bounded cache of static page images. No web view is owned by this type.
@MainActor
final class TabPreviewStore: ObservableObject {
    @Published private(set) var previews: [UUID: NSImage] = [:]
    @Published private(set) var inFlightCount = 0
    private struct Entry {
        let image: NSImage
        let revision: Int
        let bytes: Int
        let createdAt: Date
        var lastAccess: Int
    }

    static let maxConcurrent = 2
    static let maxEntries = 12
    static let maxCacheBytes = 24 * 1024 * 1024

    private var cache: [UUID: Entry] = [:]
    private var pending: [UUID] = []
    private var visibleIDs: Set<UUID> = []
    private var inFlight: [UUID: Task<Void, Never>] = [:]
    private var inFlightGeneration: [UUID: Int] = [:]
    private var generation = 0
    private var access = 0
    private var isPresented = false
    private var evictionTask: Task<Void, Never>?
    private(set) var maxInFlightObserved = 0
    private(set) var captureDurationsMs: [Double] = []

    var cacheBytes: Int { cache.values.reduce(0) { $0 + $1.bytes } }
    var cacheCount: Int { cache.count }

    func present(browser: BrowserController) {
        evictionTask?.cancel()
        generation += 1
        isPresented = true
        visibleIDs.removeAll()
        reconcile(browser: browser)
    }

    func dismiss() {
        generation += 1
        isPresented = false
        pending.removeAll()
        visibleIDs.removeAll()
        inFlight.values.forEach { $0.cancel() }
        evictionTask?.cancel()
        evictionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled, let self, !self.isPresented else { return }
            self.cache.removeAll()
            self.previews.removeAll()
        }
    }

    func cardAppeared(_ id: UUID, browser: BrowserController) {
        visibleIDs.insert(id)
        request(id, browser: browser)
    }

    func cardDisappeared(_ id: UUID) { visibleIDs.remove(id) }

    func request(_ id: UUID, browser: BrowserController) {
        guard isPresented,
              let tab = browser.tabs.first(where: { $0.id == id }),
              tab.kind == .webpage, !tab.isLoading, tab.error == nil else { return }
        if var entry = cache[id] {
            if entry.revision == tab.previewRevision && Date().timeIntervalSince(entry.createdAt) < 300 {
                access += 1
                entry.lastAccess = access
                cache[id] = entry
                previews[id] = entry.image
                return
            }
            removeCached(id)
        }
        if inFlight[id] != nil {
            if inFlightGeneration[id] != generation, !pending.contains(id) { pending.insert(id, at: 0) }
            return
        }
        guard !pending.contains(id) else { return }
        pending.insert(id, at: 0)
        pump(browser: browser)
    }

    func removeTab(_ id: UUID) {
        pending.removeAll { $0 == id }
        visibleIDs.remove(id)
        inFlight[id]?.cancel()
        removeCached(id)
    }

    func reconcile(browser: BrowserController) {
        let revisions = Dictionary(uniqueKeysWithValues: browser.tabs.map { ($0.id, $0.previewRevision) })
        let stale = cache.compactMap { id, entry in
            revisions[id] == entry.revision && Date().timeIntervalSince(entry.createdAt) < 300 ? nil : id
        }
        stale.forEach(removeCached)
        pending.removeAll { revisions[$0] == nil }
        for id in visibleIDs { request(id, browser: browser) }
    }

    private func pump(browser: BrowserController) {
        guard isPresented else { return }
        while inFlight.count < Self.maxConcurrent, !pending.isEmpty {
            let id = pending.removeFirst()
            guard let tab = browser.tabs.first(where: { $0.id == id }),
                  tab.kind == .webpage, !tab.isLoading, tab.error == nil else { continue }
            let revision = tab.previewRevision
            let requestGeneration = generation
            let task = Task { [weak self, weak browser] in
                guard let self, let browser else { return }
                let start = CFAbsoluteTimeGetCurrent()
                let image = await browser.snapshot(for: id, maxWidth: 320)
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1_000
                self.inFlight.removeValue(forKey: id)
                self.inFlightGeneration.removeValue(forKey: id)
                self.inFlightCount = self.inFlight.count
                if !Task.isCancelled, self.isPresented, self.generation == requestGeneration,
                   let current = browser.tabs.first(where: { $0.id == id }),
                   current.previewRevision == revision, let image {
                    self.captureDurationsMs.append(elapsed)
                    if self.captureDurationsMs.count > 40 { self.captureDurationsMs.removeFirst() }
                    self.insert(image, id: id, revision: revision)
                }
                self.pump(browser: browser)
            }
            inFlight[id] = task
            inFlightGeneration[id] = requestGeneration
            inFlightCount = inFlight.count
            maxInFlightObserved = max(maxInFlightObserved, inFlight.count)
        }
    }

    private func insert(_ image: NSImage, id: UUID, revision: Int) {
        let bytes = estimatedBytes(image)
        guard bytes <= Self.maxCacheBytes else { return }
        access += 1
        cache[id] = Entry(image: image, revision: revision, bytes: bytes,
                          createdAt: Date(), lastAccess: access)
        previews[id] = image
        while cache.count > Self.maxEntries || cacheBytes > Self.maxCacheBytes {
            guard let oldest = cache.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else { break }
            removeCached(oldest)
        }
    }

    private func removeCached(_ id: UUID) {
        cache.removeValue(forKey: id)
        previews.removeValue(forKey: id)
    }

    private func estimatedBytes(_ image: NSImage) -> Int {
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return max(1, rep.pixelsWide * rep.pixelsHigh * 4)
        }
        return max(1, Int(image.size.width * image.size.height * 16))
    }
}

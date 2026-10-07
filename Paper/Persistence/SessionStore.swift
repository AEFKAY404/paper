import Foundation

struct SavedSession: Codable, Equatable {
    var urls: [URL?]
    var activeIndex: Int
    var kinds: [BrowserTabKind]

    init(urls: [URL?], activeIndex: Int, kinds: [BrowserTabKind]? = nil) {
        self.urls = urls
        self.activeIndex = activeIndex
        if let kinds, kinds.count == urls.count {
            self.kinds = kinds
        } else {
            self.kinds = urls.map { $0 == nil ? .newTab : .webpage }
        }
    }

    private enum CodingKeys: String, CodingKey { case urls, activeIndex, kinds }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let urls = try container.decode([URL?].self, forKey: .urls)
        let index = try container.decode(Int.self, forKey: .activeIndex)
        let kinds = try container.decodeIfPresent([BrowserTabKind].self, forKey: .kinds)
        self.init(urls: urls, activeIndex: index, kinds: kinds)
    }
}

struct SessionStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "paper.session.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> SavedSession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SavedSession.self, from: data)
    }

    func save(_ session: SavedSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: key)
    }
}

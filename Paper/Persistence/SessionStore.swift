import Foundation

struct SavedSession: Codable, Equatable {
    var urls: [URL?]
    var activeIndex: Int
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

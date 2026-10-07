import Foundation

enum SearchEngine: String, CaseIterable, Identifiable {
    case duckDuckGo
    case google
    case brave

    var id: String { rawValue }
    var title: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        case .brave: "Brave Search"
        }
    }
    var searchBase: String {
        switch self {
        case .duckDuckGo: "https://duckduckgo.com/?q="
        case .google: "https://www.google.com/search?q="
        case .brave: "https://search.brave.com/search?q="
        }
    }
}

enum NavigationInput {
    static func url(for input: String, searchEngine: SearchEngine) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let url = URL(string: value), let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme), url.host != nil { return url }
        if !value.contains(where: \.isWhitespace),
           (value.contains(".") || value.lowercased() == "localhost"),
           let url = URL(string: "https://" + value), url.host != nil { return url }
        let query = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        return URL(string: searchEngine.searchBase + query)
    }
}

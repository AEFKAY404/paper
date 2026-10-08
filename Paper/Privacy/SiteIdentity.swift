import Foundation

/// Effective registrable domains from the bundled Public Suffix List.
/// The private section is included so hosted sites such as foo.github.io stay distinct.
struct SiteIdentity {
    private let exact: Set<String>
    private let wildcard: Set<String>
    private let exception: Set<String>

    static let shared: SiteIdentity = {
        guard let url = Bundle.main.url(forResource: "public_suffix_list", withExtension: "dat"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            // No guessed registrable domains if the resource is missing.
            return SiteIdentity(rules: "")
        }
        return SiteIdentity(rules: text)
    }()

    init(rules: String) {
        var exact = Set<String>(), wildcard = Set<String>(), exception = Set<String>()
        for line in rules.split(whereSeparator: \.isNewline) {
            let rule = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !rule.isEmpty, !rule.hasPrefix("//") else { continue }
            if rule.hasPrefix("!") { exception.insert(String(rule.dropFirst())) }
            else if rule.hasPrefix("*.") { wildcard.insert(String(rule.dropFirst(2))) }
            else { exact.insert(rule) }
        }
        self.exact = exact
        self.wildcard = wildcard
        self.exception = exception
    }

    func domain(for url: URL?) -> String? { url?.host.flatMap(domain(forHost:)) }

    static func origin(for url: URL?) -> String? {
        guard let url, let scheme = url.scheme, let host = url.host else { return nil }
        return origin(scheme: scheme, host: host, port: url.port)
    }

    static func origin(scheme: String, host: String, port: Int?) -> String? {
        let scheme = scheme.lowercased(), host = host.lowercased()
        guard ["http", "https"].contains(scheme), !host.isEmpty else { return nil }
        let normalizedHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        let defaultPort = scheme == "https" ? 443 : 80
        let portPart = port.flatMap { $0 > 0 && $0 != defaultPort ? ":\($0)" : nil } ?? ""
        return "\(scheme)://\(normalizedHost)\(portPart)"
    }

    func domain(forHost host: String) -> String? {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty else { return nil }
        if host == "localhost" || host.contains(":") || host.split(separator: ".").allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) {
            return host
        }
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 1 else { return host }
        var suffixLength = 1 // PSL implicit wildcard rule.
        for index in labels.indices {
            let candidate = labels[index...].joined(separator: ".")
            if exception.contains(candidate) {
                suffixLength = labels.count - index - 1
                break
            }
            if exact.contains(candidate) { suffixLength = max(suffixLength, labels.count - index) }
            if index > 0, wildcard.contains(candidate) { suffixLength = max(suffixLength, labels.count - index + 1) }
        }
        guard labels.count > suffixLength else { return host }
        return labels.suffix(suffixLength + 1).joined(separator: ".")
    }
}

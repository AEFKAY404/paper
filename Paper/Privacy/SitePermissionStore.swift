import AppKit
import Combine
import Foundation
import WebKit

enum SitePermission: String, Codable, CaseIterable, Identifiable {
    case camera, microphone, geolocation, popups
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum SitePermissionChoice: String, Codable, CaseIterable, Identifiable {
    case ask, allow, block
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

@MainActor
final class SitePermissionStore: ObservableObject {
    static let shared = SitePermissionStore()
    @Published private(set) var decisions: [String: [String: SitePermissionChoice]]
    private let defaults: UserDefaults
    private let key = "paper.permissions.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let value = try? JSONDecoder().decode([String: [String: SitePermissionChoice]].self, from: data) {
            decisions = value
        } else { decisions = [:] }
    }

    func choice(_ permission: SitePermission, for site: String) -> SitePermissionChoice {
        decisions[site]?[permission.rawValue] ?? .ask
    }

    func set(_ choice: SitePermissionChoice, for permission: SitePermission, site: String) {
        guard let domain = SiteIdentity.origin(for: URL(string: site)) else { return }
        if choice == .ask {
            decisions[domain]?.removeValue(forKey: permission.rawValue)
            if decisions[domain]?.isEmpty == true { decisions.removeValue(forKey: domain) }
        } else { decisions[domain, default: [:]][permission.rawValue] = choice }
        persist()
    }

    func revoke(site: String) {
        decisions.removeValue(forKey: site)
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(decisions), forKey: key)
    }

    func decide(_ permissions: [SitePermission], site: String, privateTab: Bool,
                window: NSWindow?, completion: @escaping (Bool) -> Void) {
        let choices = permissions.map { privateTab ? .ask : choice($0, for: site) }
        if choices.contains(.block) { completion(false); return }
        if choices.allSatisfy({ $0 == .allow }) { completion(true); return }
        guard let window else { completion(false); return }
        let alert = NSAlert()
        alert.messageText = "Allow \(site) to use \(permissions.map(\.title).joined(separator: " and "))?"
        alert.informativeText = "Paper will also ask macOS for access when required."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Block")
        alert.showsSuppressionButton = !privateTab
        alert.suppressionButton?.title = "Remember for this site"
        alert.beginSheetModal(for: window) { [weak self] response in
            let allow = response == .alertFirstButtonReturn
            if alert.suppressionButton?.state == .on, !privateTab {
                permissions.forEach { self?.set(allow ? .allow : .block, for: $0, site: site) }
            }
            completion(allow)
        }
    }
}

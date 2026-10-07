import Foundation

enum PaletteAction: Equatable {
    case handbook
    case navigate(String)
    case none

    static func resolve(_ input: String) -> PaletteAction {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .none }
        if value.caseInsensitiveCompare("help") == .orderedSame ||
            value.caseInsensitiveCompare("paper handbook") == .orderedSame {
            return .handbook
        }
        return .navigate(value)
    }
}

import Foundation

/// An intentionally small CSS selector subset. Paper supplies the declaration;
/// filter lists can only supply a validated selector.
enum StaticCosmeticSelector {
    nonisolated static func isSafe(_ selector: String, domainScoped: Bool = false) -> Bool {
        guard (1...220).contains(selector.utf8.count), selector.allSatisfy(\.isASCII),
              !selector.contains(","),
              !selector.contains(";") && !selector.contains("{") && !selector.contains("}") else { return false }
        if domainScoped && selector.contains("-"), selector.split(separator: "-").contains("ad"),
           selector.range(of: "^[a-z][a-z0-9-]{2,79}$", options: .regularExpression) != nil {
            return true
        }
        guard selector.contains(".") || selector.contains("#") || selector.contains("[") else { return false }
        let input = Array(selector)
        var simplified = ""
        var index = 0
        var attributes = 0
        while index < input.count {
            if input[index] == "[" {
                let start = index + 1
                guard let end = input[(index + 1)...].firstIndex(of: "]"),
                      attributes < 3,
                      validAttribute(String(input[start..<end])) else { return false }
                simplified += "PAPERATTR"
                attributes += 1
                index = end + 1
                continue
            }
            guard input[index] != "]", input[index] != "\"", input[index] != "'" else { return false }
            simplified.append(input[index])
            index += 1
        }
        let characters = Array(simplified)
        var pseudoCount = 0
        var hasCount = 0
        var stripped = ""
        index = 0
        while index < characters.count {
            guard characters[index] == ":" else {
                stripped.append(characters[index]); index += 1; continue
            }
            guard index + 1 < characters.count, characters[index + 1] != ":" else { return false }
            var end = index + 1
            while end < characters.count && (characters[end].isLetter || characters[end] == "-") { end += 1 }
            let name = String(characters[(index + 1)..<end])
            pseudoCount += 1
            guard pseudoCount <= 3 else { return false }
            if end < characters.count && characters[end] == "(" {
                let start = end + 1
                guard let close = characters[start...].firstIndex(of: ")"),
                      !characters[start..<close].contains("(") else { return false }
                let argument = String(characters[start..<close]).trimmingCharacters(in: .whitespaces)
                switch name {
                case "has":
                    hasCount += 1
                    guard hasCount <= 1, simpleRelative(argument) else { return false }
                case "not", "is", "where":
                    guard simpleRelative(argument) else { return false }
                case "nth-child", "nth-of-type":
                    guard argument.range(of: "^(odd|even|[0-9]{1,3}|[0-9]{0,2}n([+-][0-9]{1,3})?)$",
                                         options: .regularExpression) != nil else { return false }
                default: return false
                }
                index = close + 1
            } else {
                guard ["first-child", "last-child", "only-child", "first-of-type",
                       "last-of-type", "empty", "checked", "disabled"].contains(name) else { return false }
                index = end
            }
            stripped += "a"
        }
        let trimmed = stripped.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("*") && !trimmed.hasPrefix(">") && !trimmed.hasPrefix("+") && !trimmed.hasPrefix("~"),
              !trimmed.hasSuffix(">") && !trimmed.hasSuffix("+") && !trimmed.hasSuffix("~"),
              trimmed.allSatisfy({ $0.isLetter || $0.isNumber || "_ .#>+~-".contains($0) }),
              !trimmed.contains(".."), !trimmed.contains("##"),
              !selector.lowercased().hasPrefix("body:has("),
              !selector.lowercased().hasPrefix("html:has(") else { return false }
        let combinators = trimmed.filter { ">+~".contains($0) }.count +
            trimmed.split(whereSeparator: \.isWhitespace).count - 1
        let complexity = selector.utf8.count / 20 + attributes * 2 + pseudoCount * 2 + hasCount * 4 + combinators * 2
        return combinators <= 5 && complexity <= 28
    }

    nonisolated private static func validAttribute(_ attribute: String) -> Bool {
        let pieces = attribute.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let nameAndOperator = String(pieces[0])
        let name = String(nameAndOperator.dropLast(
            nameAndOperator.last.map { "~|^$*".contains($0) } == true ? 1 : 0))
        guard name.range(of: "^[A-Za-z_][A-Za-z0-9_-]{0,40}$", options: .regularExpression) != nil else { return false }
        guard pieces.count == 2 else { return name == nameAndOperator }
        let value = String(pieces[1])
        guard (1...82).contains(value.utf8.count) else { return false }
        if let quote = value.first, quote == "\"" || quote == "'" {
            guard value.last == quote, value.count >= 3 else { return false }
            let content = Array(value.dropFirst().dropLast())
            var index = 0
            while index < content.count {
                if content[index] == "\\" {
                    guard index + 1 < content.count, content[index + 1] == quote else { return false }
                    index += 2
                } else {
                    guard content[index].isLetter || content[index].isNumber || "_ .:-".contains(content[index]) else { return false }
                    index += 1
                }
            }
            return !content.isEmpty
        }
        return value.range(of: "^[A-Za-z0-9_-]{1,60}$", options: .regularExpression) != nil
    }

    nonisolated private static func simpleRelative(_ argument: String) -> Bool {
        guard !argument.isEmpty, argument.utf8.count <= 90,
              !argument.contains(":"), !argument.contains(","), !argument.contains("*"),
              argument.allSatisfy({ $0.isLetter || $0.isNumber || "_ .#>+~-".contains($0) }),
              argument.contains(".") || argument.contains("#") || argument.contains("PAPERATTR") else { return false }
        return argument.filter { ">+~".contains($0) }.count <= 2
    }
}

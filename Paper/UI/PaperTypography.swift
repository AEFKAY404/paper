import SwiftUI

/// A small native type scale. Functional and long-form text keeps a readable
/// regular or medium weight; native placeholder styling supplies the quieter hint.
enum PaperTypography {
    static let placeholderColor: Color = .primary.opacity(0.68)
    static let readingColor: Color = .primary.opacity(0.8)
    static let shortcutColor: Color = .primary.opacity(0.72)

    static let smallBrand: Font = .system(size: 14, weight: .light)
    static let hero: Font = .system(size: 44, weight: .thin)
    static let overviewHeading: Font = .system(size: 30, weight: .thin)
    static let sectionHeading: Font = .system(size: 26, weight: .light)
    static let onboardingHeading: Font = .system(size: 24, weight: .thin)

    static let newTabInput: Font = .system(size: 22, weight: .light)
    static let commandInput: Font = .system(size: 16, weight: .light)
    static let searchInput: Font = .body.weight(.light)
    static let commandTitle: Font = .callout.weight(.light)
    static let tabTitle: Font = .callout.weight(.light)

    static let body: Font = .body.weight(.regular)
    static let supporting: Font = .callout.weight(.regular)
    static let annotation: Font = .callout.weight(.light)
    static let metadata: Font = .caption.weight(.regular)
    static let eyebrow: Font = .caption.weight(.medium)
    static let status: Font = .caption2.weight(.medium)
    static let shortcut: Font = .system(.callout, design: .monospaced, weight: .regular)
}

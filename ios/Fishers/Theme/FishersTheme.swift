import SwiftUI
import UIKit

/// Fishers visual language — Apple HIG tokens with a *visible* SF type hierarchy.
/// - Brand → SF Rounded (wordmark)
/// - Fixture titles → SF New York (serif content)
/// - Chrome / forms → SF Text (Dynamic Type styles)
enum FishersTheme {
    static let accent = Color("AccentColor")
    static let pitch = Color(light: Color(red: 0.10, green: 0.52, blue: 0.34),
                             dark: Color(red: 0.28, green: 0.72, blue: 0.50))
    static let available = Color(light: Color(red: 0.16, green: 0.58, blue: 0.36),
                                 dark: Color(red: 0.36, green: 0.78, blue: 0.52))
    static let maybe = Color(light: Color(red: 0.88, green: 0.58, blue: 0.12),
                             dark: Color(red: 0.96, green: 0.72, blue: 0.28))
    static let unavailable = Color(light: Color(red: 0.70, green: 0.26, blue: 0.26),
                                   dark: Color(red: 0.92, green: 0.42, blue: 0.40))
    static let seam = Color(red: 0.78, green: 0.18, blue: 0.18)

    static let ink = Color.primary
    static let muted = Color.secondary
    static let mist = Color(.systemGroupedBackground)
    static let cream = Color(.secondarySystemGroupedBackground)

    // MARK: Type — semantic Dynamic Type + deliberate SF designs

    /// Wordmark — SF Rounded, heavy (Apple brand moments).
    static let brand = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    static let brandInline = Font.system(.title2, design: .rounded).weight(.heavy)

    /// Screen / section titles — SF Text.
    static let display = Font.system(.largeTitle, design: .default).weight(.bold)
    static let title = Font.system(.title2, design: .default).weight(.bold)

    /// Fixture / content titles — New York (readable, distinct from chrome).
    static let contentTitle = Font.system(.title3, design: .serif).weight(.semibold)

    static let headline = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let subhead = Font.subheadline
    static let caption = Font.caption.weight(.semibold)
    static let footnote = Font.footnote
    /// Short labels only (HIG: avoid long all-caps runs).
    static let overline = Font.system(.caption2, design: .default).weight(.bold)

    static let space1: CGFloat = 8
    static let space2: CGFloat = 16
    static let space3: CGFloat = 24
    static let space4: CGFloat = 32
    static let minTap: CGFloat = 44

    /// Apply once at launch so large titles and bar buttons match the type system.
    static func applyNavigationChrome() {
        let large = UIFont.systemFont(ofSize: 34, weight: .bold)
        let inline = UIFont.systemFont(ofSize: 17, weight: .semibold)

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.largeTitleTextAttributes = [
            .font: large,
            .foregroundColor: UIColor.label,
        ]
        appearance.titleTextAttributes = [
            .font: inline,
            .foregroundColor: UIColor.label,
        ]

        let nav = UINavigationBar.appearance()
        nav.standardAppearance = appearance
        nav.compactAppearance = appearance
        nav.scrollEdgeAppearance = appearance
        nav.prefersLargeTitles = true
    }
}

private extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}

extension View {
    func fishersBody() -> some View {
        font(FishersTheme.body)
            .foregroundStyle(.primary)
            .lineSpacing(3)
    }

    func fishersTitle() -> some View {
        font(FishersTheme.title)
            .foregroundStyle(.primary)
            .tracking(-0.4)
    }

    func fishersContentTitle() -> some View {
        font(FishersTheme.contentTitle)
            .foregroundStyle(.primary)
            .lineSpacing(2)
    }

    func fishersCaption() -> some View {
        font(FishersTheme.caption)
            .foregroundStyle(.secondary)
    }

    func fishersOverline() -> some View {
        font(FishersTheme.overline)
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

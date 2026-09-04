import SwiftUI
import UIKit

/// Fishers visual language — Apple HIG semantic tokens + pitch-green brand tint.
/// Prefer system text styles (Dynamic Type) and semantic colors over fixed sizes.
enum FishersTheme {
    /// Brand tint — also set as the app `AccentColor` asset.
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

    // Semantic surfaces (HIG) — track light/dark automatically.
    static let ink = Color.primary
    static let muted = Color.secondary
    static let mist = Color(.systemGroupedBackground)
    static let cream = Color(.secondarySystemGroupedBackground)

    // Dynamic Type text styles (do not hard-code point sizes for body UI).
    static let brand = Font.largeTitle.weight(.bold)
    static let display = Font.largeTitle.weight(.bold)
    static let title = Font.title2.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let subhead = Font.subheadline
    static let caption = Font.caption.weight(.medium)
    static let footnote = Font.footnote
    static let overline = Font.caption2.weight(.semibold)

    /// 8-pt grid.
    static let space1: CGFloat = 8
    static let space2: CGFloat = 16
    static let space3: CGFloat = 24
    static let space4: CGFloat = 32
    static let minTap: CGFloat = 44
}

// MARK: - Adaptive colour helper

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
        font(FishersTheme.body).foregroundStyle(.primary)
    }

    func fishersTitle() -> some View {
        font(FishersTheme.title).foregroundStyle(.primary)
    }

    func fishersCaption() -> some View {
        font(FishersTheme.caption).foregroundStyle(.secondary)
    }
}

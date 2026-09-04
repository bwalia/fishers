import SwiftUI

/// Pavilion pitch greens, chalk surfaces, and a readable type ladder.
enum FishersTheme {
    // MARK: Colour — deep turf, not neon; cool chalk, not warm cream default

    static let accent = Color(red: 0.06, green: 0.38, blue: 0.30)
    static let pitch = Color(red: 0.10, green: 0.52, blue: 0.34)
    static let available = Color(red: 0.16, green: 0.58, blue: 0.36)
    static let maybe = Color(red: 0.88, green: 0.58, blue: 0.12)
    static let unavailable = Color(red: 0.70, green: 0.26, blue: 0.26)
    /// Near-black with a green cast for body copy.
    static let ink = Color(red: 0.07, green: 0.11, blue: 0.12)
    /// Cool pavilion chalk.
    static let mist = Color(red: 0.93, green: 0.95, blue: 0.94)
    /// Soft card surface.
    static let cream = Color(red: 0.97, green: 0.98, blue: 0.97)
    static let seam = Color(red: 0.78, green: 0.18, blue: 0.18)
    static let muted = Color(red: 0.35, green: 0.42, blue: 0.40)

    // MARK: Type — SF for legibility; rounded only for the brand wordmark

    /// Hero brand wordmark (auth / splash).
    static let brand = Font.system(size: 40, weight: .heavy, design: .rounded)
    /// Screen titles — slightly larger than default for glanceability.
    static let display = Font.system(size: 28, weight: .bold, design: .default)
    static let title = Font.system(size: 22, weight: .semibold, design: .default)
    static let headline = Font.system(size: 17, weight: .semibold, design: .default)
    /// Primary reading size — comfortable for fixture lists.
    static let body = Font.system(size: 17, weight: .regular, design: .default)
    static let callout = Font.system(size: 16, weight: .regular, design: .default)
    static let subhead = Font.system(size: 15, weight: .medium, design: .default)
    static let caption = Font.system(size: 13, weight: .medium, design: .default)
    static let footnote = Font.system(size: 13, weight: .regular, design: .default)
    static let overline = Font.system(size: 12, weight: .bold, design: .default)

    static var readableLineSpacing: CGFloat { 4 }
}

extension View {
    /// Comfortable body copy for lists and forms.
    func fishersBody() -> some View {
        font(FishersTheme.body)
            .foregroundStyle(FishersTheme.ink)
            .lineSpacing(FishersTheme.readableLineSpacing)
    }

    func fishersTitle() -> some View {
        font(FishersTheme.title)
            .foregroundStyle(FishersTheme.ink)
            .tracking(-0.3)
    }

    func fishersCaption() -> some View {
        font(FishersTheme.caption)
            .foregroundStyle(FishersTheme.muted)
    }
}

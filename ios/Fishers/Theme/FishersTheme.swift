import SwiftUI
import UIKit

/// The app's visual language, on Apple's type system.
///
/// Every colour comes from `Brand.generated.swift`, written from
/// `brands/<id>.yaml` — the same numbers the web's CSS gets, so a club's phone
/// and its laptop are the same product. Nothing here is a hex literal for a
/// brand colour, on purpose: a hardcoded palette still compiles and still
/// renders, which is exactly how this file stayed Fishers' sage inside a
/// GullyCricket build for as long as it did.
///
/// The four source colours are all light by design, so none of them carries
/// white text — the ramp darkens each until it does, and `brand:check` fails
/// the build rather than shipping a button nobody can read. Dark is not a grey
/// inversion: those surfaces are mixed from the brand's own hue, so the two
/// appearances are the same room at different times of day.
///
/// Type stays Apple's: SF Rounded for the wordmark, New York for fixture
/// titles, SF Text for everything else, all at Dynamic Type sizes.
enum FishersTheme {

    // MARK: The ramp

    /// The four the brand chose, as given.
    static let primary400 = Brand.Source.primary
    static let primaryPale = Brand.Source.primaryPale
    static let paper = Brand.Source.surface
    static let accent400 = Brand.Source.accent

    /// Darkened until they carry text.
    static let primary500 = Brand.Ramp.primary500
    static let primary600 = Brand.Ramp.primary600
    static let primary700 = Brand.Ramp.primary700
    static let primary800 = Brand.Ramp.primary800
    static let primary900 = Brand.Ramp.primary900

    static let accent600 = Brand.Ramp.accent600
    static let accent700 = Brand.Ramp.accent700

    /// Not the brand's. A cricket ball is red whoever ships the app, and so is
    /// an error, so these stay put where the palette above moves.
    static let red600 = Color(hex: 0xB3402F)
    static let red500 = Color(hex: 0xC8533F)

    // MARK: Semantic

    /// Tints every control. Dark needs a *lighter* primary, not a darker one —
    /// the same swap the dashboard makes.
    static let accent = Color("AccentColor")

    static let pitch = Color(light: primary600, dark: primary400)

    /// Availability has to stay legible as three states, so these are pulled
    /// towards the palette rather than replaced by it: primary for yes, accent for
    /// maybe, the ball's red for no. Never the only signal — every use pairs
    /// with a label or an SF Symbol.
    static let available = Color(light: primary600, dark: primaryPale)
    static let maybe = Color(light: accent700, dark: accent400)
    static let unavailable = Color(light: red600, dark: red500)

    /// The seam on a cricket ball.
    static let seam = red600

    /// Boundary colours, the same two the web uses, so blue and orange mean
    /// the same thing on a phone as on the dashboard — and so a four and a six
    /// are told apart at a glance instead of both reading as pitch green.
    /// Far enough apart for the common kinds of colour blindness.
    static let four = Color(red: 0.184, green: 0.502, blue: 0.929)
    static let six = Color(red: 0.949, green: 0.443, blue: 0.110)

    static let ink = Color.primary
    static let muted = Color.secondary

    /// The page, and the cards on it. Grouped-background semantics, but in the
    /// club's cream rather than iOS grey.
    static let mist = Color(light: paper, dark: Brand.Dark.bg)
    static let cream = Color(light: .white, dark: Brand.Dark.surface)
    /// One step raised from a card — chips, wells, table stripes.
    ///
    /// These two light greys are the only colours here the brand file cannot
    /// answer for: it carries a `dark:` block but no light surfaces beyond the
    /// paper itself. They are a shade off against a warm-cream brand and
    /// nowhere near wrong. Give `brands/<id>.yaml` a `light:` block when one
    /// of them starts to show.
    static let raised = Color(light: Color(hex: 0xF1EFE6), dark: Brand.Dark.surface2)
    static let hairline = Color(light: Color(hex: 0xE0DED1), dark: Brand.Dark.border)

    // MARK: Type — semantic Dynamic Type + deliberate SF designs

    /// Wordmark — SF Rounded, heavy (Apple brand moments).
    static let brand = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    static let brandInline = Font.system(.title2, design: .rounded).weight(.heavy)

    /// Screen / section titles — SF Text.
    static let display = Font.system(.largeTitle, design: .default).weight(.bold)
    static let title = Font.system(.title2, design: .default).weight(.bold)

    /// Fixture / content titles — New York (readable, distinct from chrome).
    static let contentTitle = Font.system(.title3, design: .serif).weight(.semibold)

    /// A score, an average, a shirt number. Monospaced digits so a column does
    /// not jitter as the number changes.
    static func figure(_ style: Font.TextStyle = .title) -> Font {
        .system(style, design: .rounded).weight(.bold).monospacedDigit()
    }

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
    static let corner: CGFloat = 14

    /// Apply once at launch so bars sit in the club's cream rather than the
    /// system grey, in both appearances.
    static func applyNavigationChrome() {
        let large = UIFont.systemFont(ofSize: 34, weight: .bold)
        let inline = UIFont.systemFont(ofSize: 17, weight: .semibold)
        let paper = UIColor(mist)

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = paper
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

        // The tab bar too, or the app is cream everywhere but its own floor.
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundColor = paper
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

extension Color {
    /// `Color(hex: 0x8FA28A)` — the palette is written in hex everywhere else,
    /// so it is written in hex here too.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

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

    /// A grouped list on the club's cream rather than the system grey.
    ///
    /// A `List` paints its own `systemGroupedBackground`, so repainting the
    /// palette everywhere else still leaves every screen sitting on iOS grey.
    func fishersList() -> some View {
        scrollContentBackground(.hidden)
            .background(FishersTheme.mist.ignoresSafeArea())
    }

    /// A card in the club's palette: cream paper, a hairline, a soft lift.
    func fishersCard(padding: CGFloat = FishersTheme.space2) -> some View {
        self
            .padding(padding)
            .background(FishersTheme.cream, in: RoundedRectangle(cornerRadius: FishersTheme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FishersTheme.corner, style: .continuous)
                    .strokeBorder(FishersTheme.hairline, lineWidth: 1)
            )
    }
}

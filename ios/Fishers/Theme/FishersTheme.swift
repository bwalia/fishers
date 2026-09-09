import SwiftUI
import UIKit

/// Fishers visual language — sage, cream and gold, on Apple's type system.
///
/// The four colours the club chose are the source: sage #8FA28A, pale sage
/// #C7D3C0, cream #F7F4ED, gold #C8A96B. They are all light, so none of them
/// carries white text — sage on white is 2.7:1. The ramp below darkens each
/// towards a deep bottle green until it does. These are the same hex values
/// the dashboard uses, so a club's phone and its laptop are the same product.
///
/// Dark is not a grey inversion: the surfaces are mixed from the same sage
/// hue, so the two appearances are the same room at different times of day.
///
/// Type stays Apple's: SF Rounded for the wordmark, New York for fixture
/// titles, SF Text for everything else, all at Dynamic Type sizes.
enum FishersTheme {

    // MARK: The ramp

    /// The four, as given.
    static let sage = Color(hex: 0x8FA28A)
    static let sagePale = Color(hex: 0xC7D3C0)
    static let creamPaper = Color(hex: 0xF7F4ED)
    static let gold = Color(hex: 0xC8A96B)

    /// Darkened until they carry text.
    static let sage500 = Color(hex: 0x798C76)
    static let sage600 = Color(hex: 0x667964)   // + white 4.68:1
    static let sage700 = Color(hex: 0x556754)
    static let sage800 = Color(hex: 0x445645)
    static let sage900 = Color(hex: 0x2C3A2D)

    static let gold600 = Color(hex: 0x927947)
    static let gold700 = Color(hex: 0x7E673A)   // + white 5.40:1

    static let red600 = Color(hex: 0xB3402F)
    static let red500 = Color(hex: 0xC8533F)

    // MARK: Semantic

    /// Tints every control. Dark needs a *lighter* sage, not a darker one —
    /// the same swap the dashboard makes.
    static let accent = Color("AccentColor")

    static let pitch = Color(light: sage600, dark: sage)

    /// Availability has to stay legible as three states, so these are pulled
    /// towards the palette rather than replaced by it: sage for yes, gold for
    /// maybe, the ball's red for no. Never the only signal — every use pairs
    /// with a label or an SF Symbol.
    static let available = Color(light: sage600, dark: sagePale)
    static let maybe = Color(light: gold700, dark: gold)
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
    static let mist = Color(light: creamPaper, dark: Color(hex: 0x111712))
    static let cream = Color(light: .white, dark: Color(hex: 0x171D17))
    /// One step raised from a card — chips, wells, table stripes.
    static let raised = Color(light: Color(hex: 0xF1EFE6), dark: Color(hex: 0x1C231C))
    static let hairline = Color(light: Color(hex: 0xE0DED1), dark: Color(hex: 0x2A332A))

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

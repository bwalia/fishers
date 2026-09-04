import SwiftUI

/// Brand mark for content areas (auth hero, empty states) — not persistent chrome.
/// Uses the same full-bleed icon artwork as the app icon (Apple HIG: one recognizable glyph).
struct FishersBrandHeader: View {
    enum Style {
        case hero
        case inline
    }

    var style: Style = .inline
    var showsTagline: Bool = false
    var tagline: String = "Clubs, calendars, and match day — organised."

    /// Continuous corner radius ≈ iOS icon mask proportion.
    private var iconCorner: CGFloat { logoSize * 0.2237 }

    private var logoSize: CGFloat {
        switch style {
        case .hero: return 108
        case .inline: return 40
        }
    }

    var body: some View {
        Group {
            switch style {
            case .hero:
                VStack(spacing: FishersTheme.space2) {
                    appIcon
                        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
                    Text("Fishers")
                        .font(FishersTheme.brand)
                        .tracking(0.8)
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    if showsTagline {
                        Text(tagline)
                            .font(FishersTheme.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, FishersTheme.space2)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            case .inline:
                HStack(spacing: 12) {
                    appIcon
                    Text("Fishers")
                        .font(FishersTheme.brandInline)
                        .tracking(0.4)
                        .foregroundStyle(.primary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Fishers")
            }
        }
    }

    private var appIcon: some View {
        Image("FishersLogo")
            .resizable()
            .scaledToFit()
            .frame(width: logoSize, height: logoSize)
            .clipShape(RoundedRectangle(cornerRadius: iconCorner, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Glyph-only mark (ball + hook) when a full green tile is too heavy.
struct FishersMark: View {
    var size: CGFloat = 28

    var body: some View {
        Image("FishersMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

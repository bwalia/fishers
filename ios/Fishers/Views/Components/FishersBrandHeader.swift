import SwiftUI

/// App mark + wordmark — the brand signal at the top of the experience.
struct FishersBrandHeader: View {
    enum Style {
        /// Large hero on the auth / splash screen.
        case hero
        /// Compact bar for navigation / home.
        case bar
    }

    var style: Style = .bar
    var showsTagline: Bool = false
    var tagline: String = "Clubs, calendars, and match day — organised."
    var onDark: Bool = false

    private var logoSize: CGFloat {
        switch style {
        case .hero: return 96
        case .bar: return 36
        }
    }

    var body: some View {
        Group {
            switch style {
            case .hero:
                VStack(spacing: 14) {
                    logo
                        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                    wordmark(size: 40)
                    if showsTagline {
                        Text(tagline)
                            .font(FishersTheme.callout)
                            .foregroundStyle(onDark ? Color.white.opacity(0.88) : FishersTheme.muted)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 12)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Fishers")
            case .bar:
                HStack(spacing: 10) {
                    logo
                    wordmark(size: 22)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Fishers")
            }
        }
    }

    private var logo: some View {
        Image("FishersLogo")
            .resizable()
            .scaledToFit()
            .frame(width: logoSize, height: logoSize)
            .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.22, style: .continuous))
            .accessibilityHidden(true)
    }

    private func wordmark(size: CGFloat) -> some View {
        Text("Fishers")
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .tracking(size > 30 ? 0.6 : 0.2)
            .foregroundStyle(onDark ? Color.white : FishersTheme.ink)
    }
}

/// Thin top strip used above tab content so the brand stays visible.
struct FishersTopBar: View {
    var body: some View {
        HStack(spacing: 10) {
            FishersBrandHeader(style: .bar, showsTagline: false)
            Spacer(minLength: 0)
        }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FishersTheme.cream.opacity(0.94))
    }
}

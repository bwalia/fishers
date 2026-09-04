import SwiftUI

/// Brand mark for content areas (auth hero, empty states) — not persistent chrome.
struct FishersBrandHeader: View {
    enum Style {
        case hero
        case inline
    }

    var style: Style = .inline
    var showsTagline: Bool = false
    var tagline: String = "Clubs, calendars, and match day — organised."

    private var logoSize: CGFloat {
        switch style {
        case .hero: return 88
        case .inline: return 36
        }
    }

    var body: some View {
        Group {
            switch style {
            case .hero:
                VStack(spacing: FishersTheme.space2) {
                    logo
                    Text("Fishers")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    if showsTagline {
                        Text(tagline)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, FishersTheme.space2)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            case .inline:
                HStack(spacing: 10) {
                    logo
                    Text("Fishers")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
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
}

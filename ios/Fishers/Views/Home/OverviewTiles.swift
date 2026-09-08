import SwiftUI

/// The three counts the dashboard opens with: how many clubs, how much is
/// coming, how much is being played.
///
/// Counts rather than a list, because the useful question on opening the app is
/// "is there anything?" — and a number answers it before the list has finished
/// arriving. The live tile is tinted only when it is non-zero: a permanently
/// coloured tile reading 0 teaches people to stop looking at it.
struct OverviewTiles: View {
    let clubs: Int
    let upcoming: Int
    let live: Int

    var body: some View {
        HStack(spacing: FishersTheme.space1) {
            Tile(value: clubs, label: "Clubs", caption: "memberships", tint: FishersTheme.accent)
            Tile(value: upcoming, label: "Upcoming", caption: "fixtures ahead", tint: nil)
            Tile(
                value: live,
                label: "In progress",
                caption: live == 1 ? "match" : "matches",
                tint: live > 0 ? FishersTheme.pitch : nil
            )
        }
        .padding(.horizontal, FishersTheme.space2)
        .padding(.vertical, FishersTheme.space1)
    }

    private struct Tile: View {
        let value: Int
        let label: String
        let caption: String
        let tint: Color?

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(FishersTheme.overline)
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(tint ?? FishersTheme.muted)
                Text("\(value)")
                    // Monospaced digits so the row does not shuffle sideways
                    // each time a count ticks over during a refresh.
                    .font(FishersTheme.display.monospacedDigit())
                    .foregroundStyle(.primary)
                Text(caption)
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FishersTheme.space1)
            .background(FishersTheme.cream, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(tint?.opacity(0.4) ?? .clear, lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(value) \(label), \(caption)")
        }
    }
}

/// The dot that says this is now, not a cached number.
struct LivePip: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(FishersTheme.seam)
                .frame(width: 7, height: 7)
            Text("Live")
                .font(FishersTheme.overline)
                .tracking(0.8)
                .foregroundStyle(FishersTheme.seam)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    List {
        Section {
            OverviewTiles(clubs: 2, upcoming: 5, live: 1)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }
}

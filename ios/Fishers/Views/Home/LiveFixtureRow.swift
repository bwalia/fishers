import SwiftUI

/// A match being played, as it looks on the Home overview.
///
/// The score carries the row. Someone opening the app during a game wants the
/// number first and the fixture's name second, which is the opposite of how an
/// upcoming fixture reads.
struct LiveFixtureRow: View {
    let fixture: CricketFixtureRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: FishersTheme.space2) {
            VStack(alignment: .leading, spacing: 6) {
                Text(fixture.sides)
                    .font(FishersTheme.contentTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let score = fixture.score, !score.isEmpty {
                    Text(score)
                        .font(FishersTheme.headline.monospacedDigit())
                        .foregroundStyle(FishersTheme.pitch)
                } else {
                    // A match can be live before a ball is bowled — during the
                    // toss and team sheets — and "0/0" would be a lie about it.
                    Text("Not started")
                        .font(FishersTheme.subhead)
                        .foregroundStyle(.secondary)
                }

                // Whether *you* may score it is EventDetailView's answer to
                // give; this only says whether anyone is on it, which is what
                // decides if the book is being kept at all.
                Text(fixture.hasScorer ? "Being scored" : "No scorer yet")
                    .font(FishersTheme.footnote)
                    .foregroundStyle(fixture.hasScorer ? .secondary : FishersTheme.maybe)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(fixture.sides), \(fixture.score ?? "not started"), "
                + (fixture.hasScorer ? "being scored" : "no scorer yet")
        )
    }
}

#Preview {
    List {
        LiveFixtureRow(
            fixture: CricketFixtureRow(
                eventId: UUID(),
                clubId: UUID(),
                title: "Saturday League",
                startAt: .now,
                eventStatus: "scheduled",
                matchId: UUID(),
                matchStatus: "live",
                homeName: "London Lords",
                awayName: "Watford",
                hasScorer: true,
                score: "20/1 (2.0 ov)",
                result: nil
            )
        )
    }
}

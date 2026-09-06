import SwiftUI

/// Always-visible Profile entry for Play-Cricket season runs, wickets and awards.
/// Kept as its own view so a failed load still shows a clear "Season stats" row —
/// never silently omit the section when the API or decode fails.
struct SeasonStatsSection: View {
    @State private var meStats: MeStatsResponse?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        Section {
            if isLoading && meStats == nil {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading season stats…")
                        .foregroundStyle(.secondary)
                }
            } else if let season = meStats?.seasons.first {
                seasonSummary(season)
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Try again") {
                        Task { await load() }
                    }
                }
            } else {
                Text("No season stats yet. Sign in as demo@fishers.test / password123 for sample runs and wickets, or pull to refresh.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let meStats, !meStats.achievements.isEmpty {
                ForEach(meStats.achievements) { achievement in
                    HStack(alignment: .top, spacing: 12) {
                        Text(achievement.icon ?? "★")
                            .font(.title3.weight(.bold))
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(achievement.title)
                                .font(.body.weight(.semibold))
                            if let description = achievement.description {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let year = achievement.seasonYear {
                                Text("Season \(year)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if let meStats {
                ForEach(meStats.links.filter { $0.profileURL != nil }) { link in
                    if let url = link.profileURL {
                        Link(destination: url) {
                            Label(link.displayName ?? "Play-Cricket profile", systemImage: "sportscourt")
                        }
                    }
                }
            }
        } header: {
            Text("Season stats")
        } footer: {
            Text("ECB Play-Cricket season board. Sample data ships with the demo club; live sync uses a club API token when configured.")
        }
        .task { await load() }
    }

    @ViewBuilder
    private func seasonSummary(_ season: PlayerSeasonStats) -> some View {
        HStack(spacing: 16) {
            pill("Runs", "\(season.runs)")
            pill("Wickets", "\(season.wickets)")
            pill("Matches", "\(season.matches)")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Season \(season.seasonYear): \(season.runs) runs, \(season.wickets) wickets, \(season.matches) matches")

        if let avg = season.battingAverage {
            LabeledContent("Batting avg", value: String(format: "%.1f", avg))
        }
        if let bowl = season.bowlingAverage {
            LabeledContent("Bowling avg", value: String(format: "%.1f", bowl))
        }
        if let highScore = season.highScore {
            LabeledContent("High score", value: "\(highScore)")
        }
        if let clubName = season.clubName {
            LabeledContent("Club", value: clubName)
        }
        LabeledContent("Season", value: "\(season.seasonYear)")
        if let url = season.playCricketURL {
            Link(destination: url) {
                Label("View on Play-Cricket", systemImage: "arrow.up.right.square")
            }
        }
    }

    private func pill(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            meStats = try await FishersAPI.mySeasonStats(season: 2026)
            errorMessage = nil
        } catch {
            meStats = nil
            errorMessage = error.localizedDescription
        }
    }
}

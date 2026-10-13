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
                    Text(t(tr("rest.loading_season_stats")))
                        .foregroundStyle(.secondary)
                }
            } else if let season = meStats?.seasons.first {
                seasonSummary(season)
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(t(tr("rest.try_again"))) {
                        Task { await load() }
                    }
                }
            } else {
                Text(t(tr("rest.no_season_stats_yet")))
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
                            Label(link.displayName ?? tr("Play-Cricket profile"), systemImage: "sportscourt")
                        }
                    }
                }
            }
        } header: {
            Text(t(tr("cl.season_stats")))
        } footer: {
            Text(t(tr("rest.play_cricket_season_board")))
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
            LabeledContent(tr("Batting avg"), value: String(format: "%.1f", avg))
        }
        if let bowl = season.bowlingAverage {
            LabeledContent(tr("Bowling avg"), value: String(format: "%.1f", bowl))
        }
        if let highScore = season.highScore {
            LabeledContent("High score", value: "\(highScore)")
        }
        if let clubName = season.clubName {
            LabeledContent(tr("Club"), value: clubName)
        }
        LabeledContent("Season", value: "\(season.seasonYear)")
        if let url = season.playCricketURL {
            Link(destination: url) {
                Label(t(tr("rest.view_on_play_cricket")), systemImage: "arrow.up.right.square")
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

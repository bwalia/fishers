import SwiftUI

/// Club season board: W–L–D, runs, wickets, and Play-Cricket leaderboards.
struct ClubStatsView: View {
    let clubId: UUID
    let clubName: String

    @State private var board: ClubSeasonBoard?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        List {
            if loading && board == nil {
                ProgressView("Loading season…")
            }
            if let error {
                Text(error)
                    .foregroundStyle(.secondary)
            }
            if let board {
                Section("\(board.club.seasonYear) record") {
                    LabeledContent("Played", value: "\(board.club.matchesPlayed)")
                    LabeledContent("W–L–D", value: board.club.recordLabel)
                    if board.club.wins + board.club.losses > 0 {
                        let rate = Double(board.club.wins)
                            / Double(board.club.wins + board.club.losses) * 100
                        LabeledContent("Win rate", value: String(format: "%.0f%%", rate))
                    }
                    LabeledContent("Runs for", value: "\(board.club.runsFor)")
                    LabeledContent("Runs against", value: "\(board.club.runsAgainst)")
                    LabeledContent("Wickets taken", value: "\(board.club.wicketsTaken)")
                    if let site = board.playCricket, let url = site.publicURL {
                        Link(destination: url) {
                            Label(site.siteName ?? "Play-Cricket club page", systemImage: "arrow.up.right.square")
                        }
                    }
                }
                Section("Batting") {
                    ForEach(board.topBatters) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(p.playerName ?? "Player")
                                Spacer()
                                Text("\(p.runs)")
                                    .font(.headline.monospacedDigit())
                            }
                            Text(battingLine(p))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 2)
                    }
                }
                Section("Bowling") {
                    ForEach(board.topBowlers.filter { $0.oversBowled > 0 }) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(p.playerName ?? "Player")
                                Spacer()
                                Text("\(p.wickets) wkt\(p.wickets == 1 ? "" : "s")")
                                    .font(.headline.monospacedDigit())
                            }
                            Text(bowlingLine(p))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(clubName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }


    /// M · Inns · NO · HS · Avg · SR — the dashboard's batting columns, read as
    /// a line because a phone has no room for nine of them.
    private func battingLine(_ p: PlayerSeasonStats) -> String {
        var parts = ["\(p.matches) M", "\(p.battingInnings) inns"]
        if p.notOuts > 0 { parts.append("\(p.notOuts) no") }
        if let hs = p.highScore { parts.append("HS \(hs)") }
        if let avg = p.battingAverage { parts.append(String(format: "avg %.2f", avg)) }
        if let sr = p.strikeRate { parts.append(String(format: "SR %.1f", sr)) }
        if p.fours > 0 || p.sixes > 0 { parts.append("\(p.fours)x4 \(p.sixes)x6") }
        return parts.joined(separator: " · ")
    }

    private func bowlingLine(_ p: PlayerSeasonStats) -> String {
        var parts = [String(format: "%.1f ov", p.oversBowled), "\(p.bowlingRuns) runs"]
        if p.maidens > 0 { parts.append("\(p.maidens) mdn") }
        if let avg = p.bowlingAverage { parts.append(String(format: "avg %.2f", avg)) }
        if p.oversBowled > 0 {
            parts.append(String(format: "econ %.2f", Double(p.bowlingRuns) / p.oversBowled))
        }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            board = try await FishersAPI.clubSeasonBoard(clubId: clubId)
            error = nil
        } catch {
            self.error = error.localizedDescription
            board = nil
        }
    }
}

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
                    LabeledContent("Runs for", value: "\(board.club.runsFor)")
                    LabeledContent("Runs against", value: "\(board.club.runsAgainst)")
                    LabeledContent("Wickets taken", value: "\(board.club.wicketsTaken)")
                    if let site = board.playCricket, let url = site.publicURL {
                        Link(destination: url) {
                            Label(site.siteName ?? "Play-Cricket club page", systemImage: "arrow.up.right.square")
                        }
                    }
                }
                Section("Top batters") {
                    ForEach(board.topBatters) { p in
                        HStack {
                            Text(p.playerName ?? "Player")
                            Spacer()
                            Text("\(p.runs) runs")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                Section("Top bowlers") {
                    ForEach(board.topBowlers) { p in
                        HStack {
                            Text(p.playerName ?? "Player")
                            Spacer()
                            Text("\(p.wickets) wkts")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle(clubName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            board = try await FishersAPI.clubSeasonBoard(clubId: clubId)
            error = nil
        } catch {
            self.error = "Could not load club stats"
            board = nil
        }
    }
}

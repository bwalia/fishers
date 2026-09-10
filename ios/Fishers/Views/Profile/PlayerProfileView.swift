import SwiftUI

/// Somebody else's record.
///
/// The same figures as your own profile and worked out the same way — career
/// totals are the sum of the seasons, and the averages come from those sums
/// rather than from averaging the seasons' own averages.
///
/// What is not here is their contact details. The API does not send them.
struct PlayerProfileView: View {
    let userId: UUID
    /// Shown while the real profile loads, so tapping a name in a list does
    /// not open a blank screen with a spinner where the name should be.
    var knownName: String?

    @State private var player: TeammateProfile?
    @State private var seasons: [PlayerSeasonStats] = []
    @State private var honours: [UserAchievement] = []
    @State private var message: String?
    @State private var loading = true

    private var totals: Totals { Totals(seasons) }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if let message {
                Section {
                    Text(message)
                        .font(FishersTheme.footnote)
                        .foregroundStyle(FishersTheme.unavailable)
                }
            }

            if loading {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if seasons.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Nothing scored yet",
                        systemImage: "figure.cricket",
                        description: Text(
                            "\(firstName)'s figures appear here once they play a match somebody scored on Fishers."
                        )
                    )
                }
            } else {
                careerSection
                seasonSection
            }

            if !honours.isEmpty {
                Section("Honours") {
                    ForEach(honours) { award in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(award.title).font(FishersTheme.headline)
                            if let detail = award.description {
                                Text(detail)
                                    .font(FishersTheme.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let clubs = player?.sharedClubs, !clubs.isEmpty {
                Section("You both play for") {
                    ForEach(clubs, id: \.self) { Text($0) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .fishersList()
        .navigationTitle(player?.name ?? knownName ?? "Player")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: Pieces

    private var firstName: String {
        (player?.name ?? knownName ?? "They").split(separator: " ").first.map(String.init) ?? "They"
    }

    private var header: some View {
        let name = player?.name ?? knownName ?? ""
        let parts = name.split(separator: " ").map(String.init)
        let last = parts.last ?? name
        let first = parts.count > 1 ? parts.dropLast().joined(separator: " ") : ""

        return HStack(spacing: FishersTheme.space2) {
            AvatarView(name: name, urlString: player?.avatarUrl, size: 76)
                .overlay(Circle().strokeBorder(FishersTheme.gold, lineWidth: 2))
            VStack(alignment: .leading, spacing: 0) {
                if !first.isEmpty {
                    Text(first)
                        .font(.system(.title3, design: .rounded).weight(.light))
                        .foregroundStyle(.white.opacity(0.86))
                }
                Text(last.uppercased())
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if let position = player?.mainSport?.position ?? player?.positionRole {
                    Text(position)
                        .font(FishersTheme.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(FishersTheme.gold.opacity(0.25), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(FishersTheme.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [FishersTheme.sage900, FishersTheme.sage700],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private var careerSection: some View {
        Section("Career") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2),
                      spacing: FishersTheme.space2) {
                figure("Matches", String(totals.matches))
                figure("Runs", String(totals.runs))
                figure("Average", fmt(totals.battingAverage))
                figure("Wickets", String(totals.wickets))
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private var seasonSection: some View {
        Section("Season by season") {
            ForEach(seasons) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(row.seasonYear)).font(FishersTheme.headline)
                        if let club = row.clubName {
                            Text(club).font(FishersTheme.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(row.matches) match\(row.matches == 1 ? "" : "es")")
                            .font(FishersTheme.footnote)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: FishersTheme.space2) {
                        stat("Runs", String(row.runs))
                        stat("HS", row.highScore.map(String.init) ?? "—")
                        stat("Avg", fmt(row.battingAverage))
                        stat("Wkts", String(row.wickets))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(FishersTheme.figure(.title)).foregroundStyle(FishersTheme.pitch)
            Text(label).font(FishersTheme.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FishersTheme.space1)
        .background(FishersTheme.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(FishersTheme.figure(.body))
            Text(label).font(FishersTheme.overline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fmt(_ value: Double?, places: Int = 2) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.\(places)f", value)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            player = try await FishersAPI.teammate(userId)
        } catch let failure {
            message = (failure as? APIError)?.friendlyMessage
                ?? "Could not load this player."
            return
        }
        // Neither of these is an error when empty — a new player has no
        // figures and no honours, and the screen says so.
        seasons = (try? await FishersAPI.playerSeasons(userId)) ?? []
        honours = (try? await FishersAPI.playerAchievements(userId)) ?? []
    }
}

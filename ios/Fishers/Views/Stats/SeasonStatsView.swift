import SwiftUI

/// Stats, for players first. The phone's half of the website's `/stats`.
///
/// "My game" opens on the good news in the season — a best, a milestone, a
/// number that went up — then the handful of figures that describe it, the
/// last ten matches, and the bests and milestones of a whole career. A lower
/// number than last season is plain context, never red: the screen is for
/// knowing your game, not for being marked down by it.
///
/// "Club" is the season's record and its leaderboards, and for a secretary
/// the box that closes the season and sends every member theirs.
///
/// Opened from the profile, from the club screen (on the Club tab), from a
/// club-mate's profile (their game only), and from the `season_closed` push.
struct SeasonStatsView: View {
    enum Tab: Hashable { case mine, club }

    /// Somebody else's game, from their profile. No Club tab then: the
    /// leaderboards are already one tap away on the club screen, and the
    /// highlights are written to the person reading them.
    var player: (id: UUID, name: String)?

    @State private var tab: Tab
    @State private var season: Int?
    @State private var clubId: UUID?

    @EnvironmentObject private var clubContext: ClubContextStore
    @EnvironmentObject private var session: SessionStore

    @State private var game: PlayerGame?
    @State private var clubSeason: ClubSeason?
    @State private var error: String?
    @State private var loading = false
    /// What is on screen, so the season the API chose being written back into
    /// the picker does not fetch the same thing twice.
    @State private var loadedKey: String?

    init(tab: Tab = .mine, season: Int? = nil, clubId: UUID? = nil) {
        _tab = State(initialValue: tab)
        _season = State(initialValue: season)
        _clubId = State(initialValue: clubId)
    }

    init(player id: UUID, name: String, season: Int? = nil) {
        self.player = (id, name)
        _tab = State(initialValue: .mine)
        _season = State(initialValue: season)
    }

    private var thisYear: Int { Calendar.current.component(.year, from: Date()) }

    /// Cricket clubs only: the figures are a cricket scorebook's.
    private var clubs: [Club] {
        clubContext.clubs.filter { $0.sportTypes.isEmpty || $0.sportTypes.contains("cricket") }
    }

    private var seasons: [Int] {
        var all = Set([thisYear])
        all.formUnion(game?.seasons ?? [])
        all.formUnion(clubSeason?.seasons ?? [])
        if let season { all.insert(season) }
        return all.sorted(by: >)
    }

    private var key: String {
        "\(player?.id.uuidString ?? "me")|\(tab)|\(season.map(String.init) ?? "-")|\(clubId?.uuidString ?? "-")"
    }

    var body: some View {
        List {
            controls

            if let error {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error)
                            .font(FishersTheme.footnote)
                            .foregroundStyle(.secondary)
                        Button(t("rest.try_again")) { Task { await load(force: true) } }
                    }
                }
            } else if loading && current == nil {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if tab == .mine, let game {
                MyGameSections(game: game, isMe: player == nil) { rank in
                    clubId = rank.clubId
                    tab = .club
                }
            } else if tab == .club {
                if clubId == nil {
                    Section {
                        ContentUnavailableView(
                            t("ss.no_club"),
                            systemImage: "person.3"
                        )
                    }
                } else if let clubSeason {
                    ClubSeasonSections(
                        season: clubSeason,
                        meId: session.user?.id ?? game?.userId,
                        onClosed: { Task { await load(force: true) } }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .fishersList()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: key) { await load() }
        .refreshable { await load(force: true) }
        .onAppear {
            if clubId == nil { clubId = clubContext.activeClubId ?? clubs.first?.id }
        }
    }

    private var current: Any? { tab == .mine ? game as Any? : clubSeason as Any? }

    private var title: String {
        if let player { return player.name }
        return tab == .mine ? t("ss.my_game") : t("ss.club_season")
    }

    @ViewBuilder
    private var controls: some View {
        Section {
            if player == nil {
                Picker(t("ss.view"), selection: $tab) {
                    Text(t("ss.tab_mine")).tag(Tab.mine)
                    Text(t("ss.tab_club")).tag(Tab.club)
                }
                .pickerStyle(.segmented)
            }
            Picker(t("sh.season"), selection: $season) {
                // Before the first answer the API chooses the season; the
                // picker shows nothing selected rather than a guessed year.
                if season == nil { Text("–").tag(Int?.none) }
                ForEach(seasons, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
            }
            if tab == .club, clubs.count > 1 {
                Picker(t("sh.club"), selection: $clubId) {
                    ForEach(clubs) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }
        } footer: {
            if player == nil {
                Text(tab == .mine ? t("ss.my_game_intro") : t("ss.club_intro", vars: ["brand": Brand.name]))
            }
        }
    }

    private func load(force: Bool = false) async {
        if !force, key == loadedKey { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            switch tab {
            case .mine:
                let g: PlayerGame
                if let player {
                    g = try await FishersAPI.playerGame(userId: player.id, season: season)
                } else {
                    g = try await FishersAPI.myGame(season: season)
                }
                game = g
                if season == nil { season = g.season }
            case .club:
                guard let clubId else {
                    clubSeason = nil
                    break
                }
                let c = try await FishersAPI.clubSeason(clubId: clubId, season: season)
                clubSeason = c
                if season == nil { season = c.season }
            }
            loadedKey = key
        } catch {
            // The picker moved on before this answered; the next load owns
            // the screen, and a cancelled request is not an error to show.
            if Task.isCancelled || error is CancellationError { return }
            if tab == .club { clubSeason = nil }
            self.error = (error as? APIError)?.errorDescription ?? t("ss.could_not_load")
        }
    }
}

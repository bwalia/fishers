import SwiftUI
import SwiftData

/// Every cricket fixture you can see, with the match on it: start one, pick up
/// one already under way, read the card of one that is finished.
///
/// Filtering, searching and paging all happen in the database — a club with a
/// season behind it is not something to download and sift through on a phone.
///
/// At a ground with no signal the last downloaded page stays on disk, and any
/// match scored on this phone appears under "On this phone" until it syncs.
struct ScoreHubPane: View {
    enum StateFilter: String, CaseIterable, Identifiable {
        case all = "All", live = "In progress", upcoming = "Not started", finished = "Finished"
        var id: String { rawValue }
        var query: String? {
            switch self {
            case .all: return nil
            case .live: return "live"
            case .upcoming: return "upcoming"
            case .finished: return "finished"
            }
        }
    }

    private struct Query: Equatable {
        var state: StateFilter = .all
        var search = ""
        var newestFirst = false
    }

    @Query(sort: \LocalCricketMatch.updatedAt, order: .reverse)
    private var localMatches: [LocalCricketMatch]

    @State private var query = Query()
    @State private var typed = ""
    @State private var rows: [CricketFixtureRow] = []
    @State private var total = 0
    @State private var page = 1
    @State private var hasMore = false
    @State private var loading = false
    @State private var loaded = false
    @State private var generation = 0
    @State private var message: String?
    @State private var showingCached = false
    /// Clubs this person may put a fixture in — who gets "Start a match now".
    @State private var startable: [Club] = []
    @State private var starting = false
    @State private var started: StartedMatch?
    @State private var resumeMatchId: UUID?

    private let perPage = 20

    /// A quick-match start, online or offline — carries the pending create body
    /// when the fixture has not reached the API yet.
    private struct StartedMatch: Identifiable, Hashable {
        let event: Event
        var pendingCreate: CreateEventBody?
        var id: UUID { event.id }

        static func == (lhs: StartedMatch, rhs: StartedMatch) -> Bool {
            lhs.event.id == rhs.event.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(event.id)
        }
    }

    /// Matches on this phone that still need the cloud, or that are not yet on
    /// the fixture list (offline quick-start).
    private var phoneMatches: [LocalCricketMatch] {
        localMatches.filter { match in
            match.hasPendingWork || !rows.contains { $0.eventId == match.eventId }
        }
    }

    var body: some View {
        List {
            if !startable.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Two sides, right now")
                            .font(FishersTheme.headline)
                        Text("No fixture needed — name the teams and start scoring. Works with no signal; syncs when you are back online.")
                            .font(FishersTheme.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            starting = true
                        } label: {
                            Label("Start a match now", systemImage: "plus")
                                .font(FishersTheme.headline)
                                .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(FishersTheme.pitch)
                    }
                    .padding(.vertical, 4)
                }
            }

            if !phoneMatches.isEmpty {
                Section("On this phone") {
                    ForEach(phoneMatches, id: \.matchId) { match in
                        Button {
                            resumeMatchId = match.matchId
                        } label: {
                            LocalMatchRow(match: match)
                        }
                    }
                }
            }

            Section {
                Picker("Which fixtures", selection: $query.state) {
                    ForEach(StateFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(rows) { fixture in
                    NavigationLink(value: FixtureRoute(eventId: fixture.eventId)) {
                        ScoreFixtureRow(fixture: fixture)
                    }
                }
                if hasMore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .onAppear { Task { await loadMore() } }
                }
            } header: {
                HStack {
                    if total > 0 { Text("\(rows.count) of \(total)") }
                    Spacer()
                    Picker("Order", selection: $query.newestFirst) {
                        Text("Soonest first").tag(false)
                        Text("Newest first").tag(true)
                    }
                    .pickerStyle(.menu)
                    .textCase(nil)
                }
            } footer: {
                if loaded, rows.isEmpty, phoneMatches.isEmpty {
                    ContentUnavailableView(
                        query.search.isEmpty && query.state == .all ? "No cricket fixtures yet" : "Nothing matches that",
                        systemImage: "figure.cricket"
                    )
                }
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(showingCached ? .secondary : FishersTheme.unavailable)
                }
            }
        }
        .fishersList()
        .searchable(text: $typed, prompt: "Search fixtures or teams")
        .overlay { if !loaded { ProgressView() } }
        .task(id: typed) {
            // One request per pause in typing, not per keystroke.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            query.search = typed
        }
        .task(id: query) { await reload() }
        .task { await loadStartable() }
        // A ball bowled in a match on the list moves its score.
        .task {
            for await event in LiveStream.shared.events() {
                switch event {
                case .match(let id, _) where rows.contains(where: { $0.matchId == id }): await refresh()
                case .resync: await refresh()
                default: break
                }
            }
        }
        .refreshable { await reload() }
        .sheet(isPresented: $starting) {
            QuickMatchSheet(clubs: startable) { event, pending in
                started = StartedMatch(event: event, pendingCreate: pending)
            }
        }
        .navigationDestination(item: $started) { started in
            CricketScoringFlowView(
                event: started.event,
                attendees: [],
                canScore: true,
                pendingCreateEvent: started.pendingCreate
            )
        }
        .navigationDestination(item: $resumeMatchId) { matchId in
            if let match = localMatches.first(where: { $0.matchId == matchId }) {
                CricketScoringFlowView(
                    event: eventStub(for: match),
                    attendees: [],
                    canScore: true
                )
            }
        }
    }

    private func eventStub(for match: LocalCricketMatch) -> Event {
        if let cached = OfflineCache.loadEvent(id: match.eventId) { return cached }
        return Event(
            id: match.eventId,
            clubId: match.clubId,
            teamId: nil,
            sport: "cricket",
            eventSubtype: "friendly",
            title: "\(match.homeName) v \(match.awayName)",
            venueId: nil,
            startAt: match.updatedAt,
            endAt: match.updatedAt.addingTimeInterval(4 * 3600),
            capacity: 22,
            feeAmountCents: nil,
            feeCurrency: "GBP",
            status: "scheduled",
            metadata: [
                "opposition": .string(match.awayName),
                "home_name": .string(match.homeName),
            ],
            ticketPriceCents: nil,
            opponentClubId: match.opponentClubId
        )
    }

    private func fetch(page: Int) async throws -> APIPage<CricketFixtureRow> {
        try await FishersAPI.cricketFixtures(
            state: query.state.query, search: query.search, newestFirst: query.newestFirst,
            page: page, perPage: perPage
        )
    }

    private func reload() async {
        generation += 1
        let mine = generation
        loading = true
        defer { if mine == generation { loading = false } }
        do {
            let first = try await fetch(page: 1)
            guard mine == generation else { return }
            if query.search.isEmpty {
                OfflineCache.saveFixtures(first, state: query.state.query)
            }
            rows = first.items
            total = first.total
            page = 1
            hasMore = first.hasMore
            message = nil
            showingCached = false
        } catch {
            guard mine == generation else { return }
            if query.search.isEmpty,
               let snap = OfflineCache.loadFixtures(state: query.state.query), !snap.rows.isEmpty {
                rows = snap.rows
                total = snap.total
                page = 1
                hasMore = false
                showingCached = true
                message = "Showing fixtures saved on this phone — will refresh when you are back online."
            } else {
                message = (error as? APIError)?.friendlyMessage ?? error.localizedDescription
                showingCached = false
            }
        }
        loaded = true
    }

    private func loadMore() async {
        guard !loading, hasMore, !showingCached else { return }
        let mine = generation
        loading = true
        defer { loading = false }
        guard let next = try? await fetch(page: page + 1), mine == generation else { return }
        if query.search.isEmpty {
            OfflineCache.saveFixtures(next, state: query.state.query)
        }
        rows += next.items.filter { item in !rows.contains { $0.id == item.id } }
        page += 1
        hasMore = next.hasMore
        total = next.total
    }

    /// The pages already on screen, again — without dropping somebody who has
    /// scrolled to page three back to the top.
    private func refresh() async {
        guard !showingCached else { return }
        let mine = generation
        var fresh: [CricketFixtureRow] = []
        for number in 1...page {
            guard let next = try? await fetch(page: number), mine == generation else { return }
            if query.search.isEmpty {
                OfflineCache.saveFixtures(next, state: query.state.query)
            }
            fresh += next.items.filter { item in !fresh.contains { $0.id == item.id } }
            hasMore = next.hasMore
            total = next.total
        }
        rows = fresh
    }

    private func loadStartable() async {
        do {
            var can: [Club] = []
            for club in try await FishersAPI.clubs() {
                if let role = try? await FishersAPI.myClubRole(clubId: club.id) {
                    OfflineCache.saveRole(role, clubId: club.id)
                    if role.permissions.contains("manage_events") {
                        can.append(club)
                        // And the roster. This screen is the last place with
                        // signal before the drive out to a ground that has
                        // none, and a team sheet with no players to pick from
                        // is where an offline match actually stops.
                        if let members = try? await FishersAPI.clubMembers(clubId: club.id) {
                            OfflineCache.saveRoster(
                                clubId: club.id,
                                players: members.map {
                                    OfflineCache.CachedPlayer(
                                        id: $0.userId, name: $0.name, isCaptain: $0.isCaptain
                                    )
                                }
                            )
                        }
                    }
                }
            }
            startable = can
            OfflineCache.saveStartableClubs(can)
        } catch {
            startable = OfflineCache.loadStartableClubs()
        }
    }
}

/// A match scored (or started) on this device that is not yet fully on the list.
private struct LocalMatchRow: View {
    let match: LocalCricketMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(match.homeName) v \(match.awayName)")
                .font(FishersTheme.headline)
                .lineLimit(2)
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                Text(match.hasPendingWork ? "Waiting to sync" : "On this phone")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(match.hasPendingWork ? FishersTheme.unavailable : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (match.hasPendingWork ? FishersTheme.unavailable : Color.secondary)
                            .opacity(0.14),
                        in: Capsule()
                    )
                Text(match.updatedAt.formatted(.relative(presentation: .named)))
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A fixture, and how far its match has got.
struct ScoreFixtureRow: View {
    let fixture: CricketFixtureRow

    private var status: (label: String, tint: Color) {
        switch fixture.matchStatus {
        case "live": return ("Live", FishersTheme.seam)
        case "complete", "published": return ("Finished", FishersTheme.pitch)
        case nil: return ("Not started", .secondary)
        case let other?: return (other.replacingOccurrences(of: "_", with: " ").capitalized, FishersTheme.accent)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(fixture.sides)
                .font(FishersTheme.headline)
                .lineLimit(2)
            Text(fixture.startAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                .font(FishersTheme.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(status.tint.opacity(0.14), in: Capsule())
                if let score = fixture.score, !score.isEmpty {
                    Text(score)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(FishersTheme.raised, in: Capsule())
                }
                if fixture.hasScorer, fixture.matchStatus == "live" {
                    Text("Being scored")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let result = fixture.result, !result.isEmpty {
                Text(result)
                    .font(FishersTheme.footnote.weight(.semibold))
                    .foregroundStyle(FishersTheme.pitch)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Who is playing whom, and nothing else — a game arranged in the car park has
/// no fixture behind it, and making somebody create one first is the wrong
/// order. The fixture is written from this. With no signal the fixture is held
/// on the phone and posted when connectivity returns.
struct QuickMatchSheet: View {
    let clubs: [Club]
    let onStarted: (Event, CreateEventBody?) -> Void

    enum Kind: String, CaseIterable, Identifiable {
        case friendly, league_match, social
        var id: String { rawValue }
        var label: String {
            switch self {
            case .friendly: return "Friendly"
            case .league_match: return "League"
            case .social: return "Social"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var clubId: UUID?
    @State private var teams: [Team] = []
    @State private var teamId: UUID?
    @State private var opponent: ClubIdentity?
    @State private var awayName = ""
    @State private var kind: Kind = .friendly
    @State private var picking = false
    @State private var busy = false
    @State private var error: String?

    private var club: Club? { clubs.first { $0.id == clubId } }
    private var homeName: String {
        guard let club else { return "" }
        return teams.first { $0.id == teamId }.map { "\(club.name) \($0.name)" } ?? club.name
    }

    private var missing: String? {
        if club == nil { return "which of your clubs is playing" }
        if awayName.trimmingCharacters(in: .whitespaces).isEmpty { return "who you are playing" }
        if opponent?.clubId == clubId { return "an opposition that is not your own club" }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your side") {
                    Picker("Club", selection: $clubId) {
                        ForEach(clubs) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if !teams.isEmpty {
                        Picker("Team", selection: $teamId) {
                            Text("The club").tag(UUID?.none)
                            ForEach(teams) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }

                Section {
                    Button {
                        picking = true
                    } label: {
                        LabeledContent("Opposition", value: awayName.isEmpty ? "Choose…" : awayName)
                    }
                } header: {
                    Text("The opposition")
                } footer: {
                    Text(opponent.map { "\($0.clubName) are on Fishers — their captain can name their own eleven." }
                         ?? "Find them by their code or name, or just type who turned up. Works offline if you type the name.")
                }

                Section("Kind of match") {
                    Picker("Kind", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if let error {
                    Text(error).foregroundStyle(FishersTheme.unavailable)
                }

                Section {
                    Button {
                        Task { await start() }
                    } label: {
                        Group {
                            if busy { ProgressView() } else { Text("Start scoring").font(FishersTheme.headline) }
                        }
                        .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FishersTheme.pitch)
                    .disabled(busy || missing != nil)
                    .listRowBackground(Color.clear)
                } footer: {
                    if let missing { Text("Still needed: \(missing).") }
                }
            }
            .navigationTitle("Start a match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $picking) {
                OppositionPickerView { name, identity in
                    awayName = name
                    opponent = identity
                    picking = false
                }
            }
            .task(id: clubId) {
                teamId = nil
                guard let clubId else { return }
                if let remote = try? await FishersAPI.teams(clubId: clubId) {
                    teams = remote
                    OfflineCache.saveTeams(clubId: clubId, teams: remote)
                } else {
                    teams = OfflineCache.loadTeams(clubId: clubId)
                }
            }
            .onAppear { if clubId == nil { clubId = clubs.first?.id } }
        }
    }

    private func start() async {
        guard let club else { return }
        busy = true
        error = nil
        defer { busy = false }
        let away = awayName.trimmingCharacters(in: .whitespaces)
        let body = CreateEventBody(
            club_id: club.id,
            opponent_club_id: opponent?.clubId,
            team_id: teamId,
            sport: "cricket",
            event_subtype: kind.rawValue,
            title: "\(homeName) v \(away)",
            venue_id: nil,
            start_at: .now,
            end_at: .now.addingTimeInterval(4 * 3600),
            recurrence_rule: nil,
            capacity: 22,
            fee_amount_cents: nil,
            metadata: ["opposition": .string(away), "home_name": .string(homeName)]
        )

        // Prefer the API when we have a path; fall back to a phone-local fixture.
        if CricketSyncService.shared.isOnline {
            do {
                let event = try await FishersAPI.createEvent(body)
                OfflineCache.saveEvent(event)
                dismiss()
                onStarted(event, nil)
                return
            } catch let api as APIError {
                if case .unreachable = api {
                    startOffline(club: club, away: away, body: body)
                    return
                }
                self.error = api.friendlyMessage
                return
            } catch {
                self.error = "Could not start the match"
                return
            }
        }
        startOffline(club: club, away: away, body: body)
    }

    private func startOffline(club: Club, away: String, body: CreateEventBody) {
        let event = Event(
            id: UUID(),
            clubId: club.id,
            teamId: teamId,
            sport: "cricket",
            eventSubtype: kind.rawValue,
            title: "\(homeName) v \(away)",
            venueId: nil,
            startAt: body.start_at,
            endAt: body.end_at,
            capacity: 22,
            feeAmountCents: nil,
            feeCurrency: "GBP",
            status: "scheduled",
            metadata: body.metadata,
            ticketPriceCents: nil,
            opponentClubId: opponent?.clubId
        )
        OfflineCache.saveEvent(event)
        dismiss()
        onStarted(event, body)
    }
}

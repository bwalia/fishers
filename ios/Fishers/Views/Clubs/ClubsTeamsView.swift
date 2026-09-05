import SwiftUI

struct ClubsTeamsView: View {
    @State private var clubs: [Club] = []
    @State private var showCreate = false
    @State private var newName = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(clubs) { club in
                    NavigationLink(value: club) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(club.name)
                                .font(.headline)
                            Text(club.sportTypes.joined(separator: " · ").capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if club.isInformalGroup {
                                Text("Friend group")
                                    .font(.caption2)
                                    .foregroundStyle(FishersTheme.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Clubs & Teams")
            .navigationDestination(for: Club.self) { ClubDetailView(club: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                NavigationStack {
                    Form {
                        TextField("Club name", text: $newName)
                        Button("Create London Lords-style club") {
                            Task { await create(informal: false) }
                        }
                        Button("Create friend group") {
                            Task { await create(informal: true) }
                        }
                    }
                    .navigationTitle("New club")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showCreate = false }
                        }
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        do {
            clubs = try await FishersAPI.clubs()
        } catch {
            message = error.localizedDescription
        }
    }

    private func create(informal: Bool) async {
        do {
            _ = try await FishersAPI.createClub(
                name: newName.isEmpty ? (informal ? "Friday Pickup" : "London Lords CC") : newName,
                sports: ["cricket"],
                informal: informal
            )
            showCreate = false
            newName = ""
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}

struct ClubDetailView: View {
    let club: Club
    @State private var teams: [Team] = []
    @State private var events: [Event] = []
    @State private var blocks: [FixtureBlock] = []
    @State private var isCreatingTournament = false
    @State private var newTournamentName = ""

    var body: some View {
        List {
            Section("About") {
                Text(club.description ?? "No description yet.")
                Text(club.visibility.replacingOccurrences(of: "_", with: " ").capitalized)
            }
            if club.sportTypes.contains("cricket") {
                Section("Season stats") {
                    NavigationLink {
                        ClubStatsView(clubId: club.id, clubName: club.name)
                    } label: {
                        Label("Runs, wickets & Play-Cricket", systemImage: "chart.bar")
                    }
                }
            }
            Section("Teams") {
                if teams.isEmpty {
                    Text("No teams yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(teams) { team in
                        Text(team.name)
                    }
                }
            }
            Section {
                if blocks.isEmpty {
                    Text("No tournaments or tours yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(blocks) { block in
                        NavigationLink(value: block) {
                            HStack(spacing: 10) {
                                Image(systemName: block.systemImage)
                                    .foregroundStyle(FishersTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(block.name)
                                    Text(block.kind.capitalized)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Button("New tournament or tour") { isCreatingTournament = true }
                    .font(.subheadline)
            } header: {
                Text("Tournaments & tours")
            } footer: {
                Text("A tournament carries its own entrants, pitches and table; a tour carries the travel details.")
            }

            Section("Fixtures & nets") {
                ForEach(events) { event in
                    NavigationLink(value: event) {
                        EventRow(event: event)
                    }
                }
            }
        }
        .navigationTitle(club.name)
        .navigationDestination(for: Event.self) { EventDetailView(eventId: $0.id) }
        .navigationDestination(for: FixtureBlock.self) { TournamentView(block: $0) }
        .task { await load() }
        .alert("New tournament or tour", isPresented: $isCreatingTournament) {
            TextField("e.g. Lords T20 Festival", text: $newTournamentName)
            Button("Create") {
                let name = newTournamentName
                newTournamentName = ""
                Task {
                    _ = try? await FishersAPI.createTournament(name: name, clubId: club.id)
                    await load()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add sample fixtures") {
                    Task { await seedSampleFixtures() }
                }
            }
        }
    }

    private func load() async {
        async let t = FishersAPI.teams(clubId: club.id)
        async let e = FishersAPI.events(clubId: club.id)
        async let b = FishersAPI.fixtureBlocks(clubId: club.id)
        teams = (try? await t) ?? []
        events = (try? await e) ?? []
        blocks = (try? await b) ?? []
    }

    /// Weekly cricket series: Wednesday nets, Saturday league, Sunday social.
    private func seedSampleFixtures() async {
        let teamId = teams.first?.id
        let samples: [(
            subtype: String, title: String, weekday: Int, hour: Int, durationHours: Double,
            capacity: Int, fee: Int, metadata: [String: JSONValue]
        )] = [
            (
                "nets", "Wednesday Nets", 4, 18, 2,
                18, 600,
                [
                    "lane_count": .number(3),
                    "max_players_per_lane": .number(6),
                    "bowling_machine": .bool(true),
                    "facility_type": .string("indoor"),
                ]
            ),
            (
                "league_match", "Saturday League", 7, 13, 5,
                22, 1500,
                [
                    "competition": .string("Middlesex League"),
                    "format": .string("40 overs"),
                    "home": .bool(true),
                ]
            ),
            (
                "social", "Sunday Social Cricket", 1, 11, 3,
                24, 800,
                [
                    "format": .string("friendly T20"),
                    "bring_kit": .bool(true),
                    "tea_included": .bool(true),
                ]
            ),
        ]

        for sample in samples {
            let start = nextWeekday(sample.weekday, hour: sample.hour)
            let end = start.addingTimeInterval(sample.durationHours * 3600)
            let byday: [Int: String] = [1: "SU", 4: "WE", 7: "SA"]
            let body = CreateEventBody(
                club_id: club.id,
                team_id: teamId,
                sport: "cricket",
                event_subtype: sample.subtype,
                title: sample.title,
                venue_id: nil,
                start_at: start,
                end_at: end,
                recurrence_rule: "FREQ=WEEKLY;BYDAY=\(byday[sample.weekday] ?? "WE")",
                capacity: sample.capacity,
                fee_amount_cents: sample.fee,
                metadata: sample.metadata
            )
            _ = try? await FishersAPI.createEvent(body)
        }
        events = (try? await FishersAPI.events(clubId: club.id)) ?? events
    }

    /// Next occurrence of `weekday` (1 = Sunday … 7 = Saturday) at `hour` local time.
    private func nextWeekday(_ weekday: Int, hour: Int) -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = 0
        components.second = 0
        guard var candidate = calendar.date(from: components) else { return now }
        while calendar.component(.weekday, from: candidate) != weekday || candidate <= now {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }
}

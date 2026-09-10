import SwiftUI

struct ClubsTeamsView: View {
    @State private var clubs: [Club] = []
    @State private var showCreate = false
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
                            HStack(spacing: 6) {
                                if let role = club.role {
                                    Text(role.displayName)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(FishersTheme.accent)
                                }
                                if club.isInformalGroup {
                                    Text("Friend group")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .fishersList()
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
                NewClubSheet { showCreate = false; Task { await load() } }
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

}

/// Whoever creates the club is its first secretary, so this is also how a new
/// account gets somewhere to add people to.
private struct NewClubSheet: View {
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var sports: Set<String> = ["cricket"]
    @State private var blurb = ""
    @State private var isInformal = false
    @State private var isPublic = false
    @State private var isSaving = false
    @State private var message: String?

    /// Exactly what the API's SportType accepts — anything else is rejected.
    private static let allSports = [
        "cricket", "football", "badminton", "paddle", "pickleball", "tennis", "other",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Fishers CC", text: $name)
                }
                Section("Sports played") {
                    ForEach(Self.allSports, id: \.self) { sport in
                        Button {
                            if sports.contains(sport) { sports.remove(sport) } else { sports.insert(sport) }
                        } label: {
                            HStack {
                                Text(sport.capitalized).foregroundStyle(.primary)
                                Spacer()
                                if sports.contains(sport) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(FishersTheme.accent)
                                }
                            }
                        }
                        .frame(minHeight: FishersTheme.minTap)
                        .accessibilityAddTraits(sports.contains(sport) ? .isSelected : [])
                    }
                }
                Section {
                    Toggle("Anyone can find it", isOn: $isPublic)
                    Toggle("A friend group, not a club", isOn: $isInformal)
                    TextField("Sunday friendlies, Hemel Hempstead", text: $blurb)
                } footer: {
                    Text("You become its secretary, so you can add members straight away.")
                }
                if let message {
                    Text(message).foregroundStyle(.red)
                }
            }
            .navigationTitle("Start a club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .bold()
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).count < 2 || sports.isEmpty)
                }
            }
        }
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let trimmedBlurb = blurb.trimmingCharacters(in: .whitespaces)
            _ = try await FishersAPI.createClub(
                name: name.trimmingCharacters(in: .whitespaces),
                sports: Self.allSports.filter(sports.contains),
                informal: isInformal,
                visibility: isPublic ? "public" : "invite_only",
                description: trimmedBlurb.isEmpty ? nil : trimmedBlurb
            )
            onCreated()
            dismiss()
        } catch {
            message = readable(error)
        }
    }

    /// The API's own words are more use than "the operation could not be completed".
    private func readable(_ error: Error) -> String {
        guard case let APIError.http(_, body) = error,
              let data = body.data(using: .utf8),
              let payload = try? JSONDecoder().decode([String: String].self, from: data),
              let reason = payload["error"] else {
            return error.localizedDescription
        }
        return reason
    }
}

struct ClubDetailView: View {
    let club: Club
    @State private var teams: [Team] = []
    @State private var events: [Event] = []
    @State private var blocks: [FixtureBlock] = []
    @State private var isCreatingTournament = false
    @State private var newTournamentName = ""
    @State private var role: ClubRoleInfo?

    var body: some View {
        List {
            Section("About") {
                Text(club.description ?? "No description yet.")
                Text(club.visibility.replacingOccurrences(of: "_", with: " ").capitalized)
            }
            if club.sportTypes.contains(where: { $0.caseInsensitiveCompare("cricket") == .orderedSame }) {
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
                Menu {
                    NavigationLink {
                        ClubQRView(club: club)
                    } label: {
                        Label("QR code", systemImage: "qrcode")
                    }
                    NavigationLink {
                        ClubAdminView(club: club, role: role)
                    } label: {
                        Label("Manage club", systemImage: "person.2.badge.gearshape")
                    }
                    if role?.isSecretary == true {
                        Button("Add sample fixtures") {
                            Task { await seedSampleFixtures() }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func load() async {
        async let t = FishersAPI.teams(clubId: club.id)
        async let e = FishersAPI.events(clubId: club.id)
        async let b = FishersAPI.fixtureBlocks(clubId: club.id)
        async let r = FishersAPI.myClubRole(clubId: club.id)
        teams = (try? await t) ?? []
        events = (try? await e) ?? []
        blocks = (try? await b) ?? []
        role = try? await r
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

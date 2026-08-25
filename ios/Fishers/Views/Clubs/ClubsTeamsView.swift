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

    var body: some View {
        List {
            Section("About") {
                Text(club.description ?? "No description yet.")
                Text(club.visibility.replacingOccurrences(of: "_", with: " ").capitalized)
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
        .task {
            async let t = FishersAPI.teams(clubId: club.id)
            async let e = FishersAPI.events(clubId: club.id)
            teams = (try? await t) ?? []
            events = (try? await e) ?? []
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Wednesday nets") {
                    Task { await seedNets() }
                }
            }
        }
    }

    private func seedNets() async {
        let start = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now
        let end = start.addingTimeInterval(2 * 3600)
        let body = CreateEventBody(
            club_id: club.id,
            team_id: teams.first?.id,
            sport: "cricket",
            event_subtype: "nets",
            title: "Wednesday Nets",
            venue_id: nil,
            start_at: start,
            end_at: end,
            recurrence_rule: "FREQ=WEEKLY;BYDAY=WE",
            capacity: 18,
            fee_amount_cents: 600,
            metadata: [
                "lane_count": .number(3),
                "max_players_per_lane": .number(6),
                "bowling_machine": .bool(true),
                "facility_type": .string("indoor"),
            ]
        )
        _ = try? await FishersAPI.createEvent(body)
        events = (try? await FishersAPI.events(clubId: club.id)) ?? events
    }
}

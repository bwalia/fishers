import SwiftUI

struct HomeFeedView: View {
    @EnvironmentObject private var clubContext: ClubContextStore
    @State private var events: [Event] = []
    @State private var live: [CricketFixtureRow] = []
    @State private var error: String?
    @State private var unread = 0

    /// A fixture that has already been played is not something to turn up to.
    private var upcoming: [Event] {
        events.filter { $0.startAt > .now }
    }

    var body: some View {
        NavigationStack {
            Group {
                if events.isEmpty && live.isEmpty && error == nil {
                    ContentUnavailableView {
                        Label("No sessions yet", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("Join a club or add sample fixtures from the Clubs tab.")
                            .font(FishersTheme.body)
                    }
                } else {
                    List {
                        if let error {
                            Section {
                                Text(error)
                                    .font(FishersTheme.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                        if clubContext.clubs.count > 1 {
                            Section {
                                Picker("Club", selection: Binding(
                                    get: { clubContext.activeClubId },
                                    set: { if let id = $0 { clubContext.select(id) } }
                                )) {
                                    ForEach(clubContext.clubs) { club in
                                        Text(club.name).tag(Optional(club.id))
                                    }
                                }
                            }
                        }
                        Section {
                            OverviewTiles(
                                clubs: clubContext.clubs.count,
                                upcoming: upcoming.count,
                                live: live.count
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }

                        // Above the fixture list on purpose: a match being
                        // played now is the only thing here with something to
                        // do about it right this minute.
                        if !live.isEmpty {
                            Section {
                                ForEach(live) { fixture in
                                    NavigationLink(value: fixture) {
                                        LiveFixtureRow(fixture: fixture)
                                    }
                                }
                            } header: {
                                HStack {
                                    Text("In progress")
                                        .font(FishersTheme.overline)
                                        .tracking(0.8)
                                    Spacer()
                                    LivePip()
                                }
                            }
                        }

                        Section {
                            ForEach(upcoming) { event in
                                NavigationLink(value: event) {
                                    EventRow(event: event)
                                }
                            }
                        } header: {
                            Text("Upcoming")
                                .font(FishersTheme.overline)
                                .tracking(0.8)
                        } footer: {
                            if upcoming.isEmpty {
                                Text("Nothing in the diary yet.")
                                    .font(FishersTheme.footnote)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
            .fishersList()
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        NotificationsView()
                    } label: {
                        // The count, not just a dot — "3 waiting" is a
                        // different decision to "1".
                        Image(systemName: unread > 0 ? "bell.badge.fill" : "bell")
                            .symbolRenderingMode(unread > 0 ? .palette : .monochrome)
                            .foregroundStyle(FishersTheme.accent, .primary)
                    }
                    .accessibilityLabel(
                        unread > 0 ? "\(unread) unread notifications" : "Notifications"
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ShopView()
                    } label: {
                        Image(systemName: "bag")
                    }
                    .accessibilityLabel("Shop")
                }
            }
            .navigationDestination(for: Event.self) { EventDetailView(eventId: $0.id) }
            // Through the fixture, not straight into scoring: EventDetailView
            // is where the question of whether *this* person may score it is
            // already answered, and answering it twice is how the two answers
            // start to differ.
            .navigationDestination(for: CricketFixtureRow.self) {
                EventDetailView(eventId: $0.eventId)
            }
            .task { await load() }
            .task { await loadUnread() }
            .onChange(of: clubContext.activeClubId) { _, _ in
                Task { await load() }
            }
            .refreshable {
                await load()
                await loadUnread()
            }
        }
    }

    private func loadUnread() async {
        unread = (try? await FishersAPI.notifications().unread) ?? 0
    }

    private func load() async {
        do {
            // Both at once: the fixture list and what is being played are
            // independent questions, and waiting for one to ask the other adds
            // a round trip to a screen that is opened constantly.
            async let all = FishersAPI.events(clubId: clubContext.activeClubId)
            async let inPlay = FishersAPI.cricketFixtures(
                clubId: clubContext.activeClubId, state: "live", perPage: 10
            )
            events = try await all
            live = try await inPlay.items
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct EventRow: View {
    let event: Event

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: FishersTheme.space2) {
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(FishersTheme.contentTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(event.eventSubtype.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(FishersTheme.overline)
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(FishersTheme.accent)

                Text(event.startAt.formatted(date: .abbreviated, time: .shortened))
                    .font(FishersTheme.subhead)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let fee = event.feeAmountCents {
                Text(String(format: "£%.0f", Double(fee) / 100))
                    .font(FishersTheme.headline.monospacedDigit())
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Fee \(String(format: "£%.0f", Double(fee) / 100))")
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

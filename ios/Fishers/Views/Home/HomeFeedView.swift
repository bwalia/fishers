import SwiftUI

struct HomeFeedView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var clubContext: ClubContextStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var guide = GettingStartedStore()
    @State private var events: [Event] = []
    @State private var live: [CricketFixtureRow] = []
    @State private var invites: [PendingInvite] = []
    @State private var error: String?
    @State private var unread = 0
    /// Until the first load lands, "no clubs" and "not asked yet" look the
    /// same — and a new-here screen shown to somebody with four clubs, for half
    /// a second, is worse than showing nothing.
    @State private var loaded = false
    @State private var pickedRole: RoleIntent?
    @State private var showNewClub = false
    /// Just made from the guide: open it, as the Clubs tab does.
    @State private var createdClub: ClubRoute?
    @State private var showProfileEdit = false
    /// A player straight out of the quick start: their link, to send.
    @State private var showWelcomeShare = false

    /// A fixture that has already been played is not something to turn up to.
    private var upcoming: [Event] {
        events.filter { $0.startAt > .now }
    }

    /// The club this person started — the one the secretary guide is about.
    private var ownClub: Club? {
        guard let id = session.user?.id else { return nil }
        return clubContext.clubs.first { $0.ownerId == id }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section {
                        Text(error)
                            .font(FishersTheme.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if loaded, let user = session.user, user.intent == nil, clubContext.clubs.isEmpty {
                    Section {
                        RoleChooserView(selection: $pickedRole) { role in
                            try? await session.setRoleIntent(role)
                            await refreshAll()
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("How will you use \(Brand.name)?")
                    } footer: {
                        Text("We'll show you exactly what to do next. You can switch later.")
                    }
                }

                PendingInvitesSection(invites: invites) { await refreshAll() }

                if loaded, let user = session.user, let role = user.intent {
                    GettingStartedSection(
                        role: role,
                        steps: GettingStartedGuide.steps(.init(
                            role: role,
                            user: user,
                            canVerify: guide.verification?.canVerify ?? false,
                            ownClub: ownClub,
                            teamCount: guide.teams.count,
                            members: guide.members,
                            eventCount: events.count,
                            inviteCount: invites.count,
                            clubCount: clubContext.clubs.count,
                            sharedOnce: guide.sharedOnce
                        )),
                        verification: guide.verification,
                        ownClub: ownClub,
                        ownClubRole: guide.ownClubRole,
                        user: user,
                        onChanged: { await refreshAll() },
                        onShared: { guide.markShared() },
                        onStartClub: { showNewClub = true }
                    )
                }

                if loaded, let user = session.user {
                    ProfileStrengthSection(user: user) { showProfileEdit = true }
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

                if !clubContext.clubs.isEmpty {
                    Section {
                        OverviewTiles(
                            clubs: clubContext.clubs.count,
                            upcoming: upcoming.count,
                            live: live.count
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                // Above the fixture list on purpose: a match being played now
                // is the only thing here with something to do about it right
                // this minute.
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

                if !clubContext.clubs.isEmpty {
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
            }
            .listStyle(.insetGrouped)
            .fishersList()
            .sheet(isPresented: $showNewClub) {
                NewClubSheet { club in
                    Task {
                        await refreshAll()
                        createdClub = ClubRoute(club: club, welcome: true)
                    }
                }
            }
            .navigationDestination(item: $createdClub) { route in
                ClubDetailView(club: route.club, welcome: route.welcome)
            }
            .sheet(isPresented: $showProfileEdit, onDismiss: { Task { await refreshAll() } }) {
                ProfileEditView(user: session.user)
            }
            .sheet(isPresented: $showWelcomeShare, onDismiss: { guide.markShared() }) {
                if let user = session.user {
                    WelcomeShareSheet(userId: user.id) { showWelcomeShare = false }
                }
            }
            .navigationTitle(greeting)
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
            .task { await refreshAll(clubs: session.justStarted) }
            // At launch the club list arrives on the app's schedule, not
            // Home's: a guide loaded before it asked about no club at all, and
            // told a secretary with four teams to add their first one.
            .task(id: ownClub?.id) {
                guard let club = ownClub, let user = session.user else { return }
                await guide.load(user: user, ownClub: club)
            }
            .task { await loadUnread() }
            .task {
                for await event in LiveStream.shared.events() {
                    switch event {
                    case .notification:
                        await loadUnread()
                        await loadInvites()
                    // Every ball of a match the club can see: the scores in
                    // the list move with it, and one just started shows up.
                    case .match:
                        await loadLive()
                    case .resync:
                        await loadUnread()
                        await loadInvites()
                        await loadLive()
                    case .message, .conversations:
                        break
                    }
                }
            }
            .onChange(of: clubContext.activeClubId) { _, _ in
                Task { await load() }
            }
            // Back from WhatsApp, where the invite link was sent, or from the
            // email the code came in: whatever changed while away is here now.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, loaded { Task { await refreshAll() } }
            }
            .refreshable {
                await refreshAll()
                await loadUnread()
            }
        }
    }

    /// "Good morning, Sam" — by the phone's own clock.
    private var greeting: String {
        guard let first = session.user?.name.split(separator: " ").first else { return "Home" }
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return "\(part), \(first)"
    }

    /// Everything the top of Home depends on, after anything that changes it —
    /// a club started, an invite accepted, a code confirmed.
    private func refreshAll(clubs: Bool = true) async {
        if clubs { await clubContext.bootstrap() }
        async let profile: Void = session.refreshProfile()
        async let feed: Void = load()
        async let mine: Void = loadInvites()
        _ = await (profile, feed, mine)
        if let user = session.user {
            await guide.load(user: user, ownClub: ownClub)
            // Moved on from now, so somebody who keeps opening the app is
            // never nagged — only somebody who drifted away.
            await ProfileReminder.reschedule(for: user)
        }
        loaded = true
        handOff()
    }

    /// Out of the quick start and into the thing that gets them playing: a
    /// secretary starts their club (and from there adds players), a player
    /// sends their profile link. Once, and not to somebody already in a club.
    private func handOff() {
        guard session.justStarted else { return }
        session.justStarted = false
        guard clubContext.clubs.isEmpty else { return }
        switch session.user?.intent {
        case .secretary: showNewClub = true
        case .player: showWelcomeShare = true
        case nil: break
        }
    }

    private func loadInvites() async {
        invites = ((try? await FishersAPI.myInvites()) ?? []).filter(\.isPending)
    }

    private func loadLive() async {
        guard !clubContext.clubs.isEmpty,
              let page = try? await FishersAPI.cricketFixtures(
                  clubId: clubContext.activeClubId, state: "live", perPage: 10
              )
        else { return }
        live = page.items
    }

    private func loadUnread() async {
        unread = (try? await FishersAPI.notifications().unread) ?? 0
    }

    private func load() async {
        guard !clubContext.clubs.isEmpty else {
            events = []
            live = []
            return
        }
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

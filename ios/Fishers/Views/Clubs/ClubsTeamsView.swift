import SwiftUI

/// The Clubs tab: every club you are in, a page at a time.
///
/// Searched, filtered and sorted by the server, so somebody in a hundred clubs
/// downloads twenty rows and a count rather than everything to sift on the
/// phone. The next page loads as the list scrolls to its end.
struct ClubsTeamsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var clubContext: ClubContextStore
    @State private var filters = ClubListFilters()
    @State private var search = ""
    @State private var rows: [ClubMembershipRow] = []
    @State private var total = 0
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var loaded = false
    @State private var message: String?
    @State private var invites: [PendingInvite] = []
    @State private var showCreate = false
    @State private var path = NavigationPath()
    /// Only the latest request may land: a slow answer to an old filter must
    /// not overwrite the new one.
    @State private var generation = 0

    private static let sports = ["cricket", "football", "badminton", "paddle", "pickleball", "tennis", "other"]

    var body: some View {
        NavigationStack(path: $path) {
            List {
                PendingInvitesSection(invites: invites) {
                    await reloadInvites()
                    await reload()
                    await clubContext.bootstrap()
                }

                if loaded && rows.isEmpty && !filters.isFiltered {
                    emptyState
                } else {
                    Section {
                        ForEach(rows) { row in
                            NavigationLink(value: ClubRoute(club: row.club, welcome: false)) {
                                ClubRowView(row: row)
                            }
                            .contextMenu { rowMenu(row) }
                            .onAppear {
                                if row.id == rows.last?.id, hasMore { Task { await loadMore() } }
                            }
                        }
                        if loading && !rows.isEmpty {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        }
                        if loaded && rows.isEmpty && filters.isFiltered {
                            ContentUnavailableView {
                                Label("No clubs match", systemImage: "magnifyingglass")
                            } actions: {
                                Button("Clear filters") { clearFilters() }
                            }
                        }
                    } header: {
                        HStack {
                            Text(total == 1 ? "1 club" : "\(total) clubs")
                            Spacer()
                            if filters.isFiltered {
                                Button("Clear filters") { clearFilters() }
                                    .font(FishersTheme.footnote)
                                    .textCase(nil)
                            }
                        }
                    }

                    if let user = session.user {
                        Section {
                            NavigationLink {
                                ShareProfileScreen(userId: user.id)
                            } label: {
                                Label("Send my profile to another club", systemImage: "link")
                            }
                        } header: {
                            Text("Your player profile")
                        } footer: {
                            Text("A club's secretary can invite you straight from your profile link.")
                        }
                    }

                    Section("How clubs work") {
                        ForEach(Array(Self.howClubsWork.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(FishersTheme.caption)
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(FishersTheme.pitch, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.0).font(FishersTheme.headline)
                                    Text(item.1).font(FishersTheme.footnote).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if let message {
                    Section { Text(message).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .fishersList()
            .overlay { if !loaded { ProgressView() } }
            .navigationTitle("Clubs")
            .searchable(text: $search, prompt: "Search by name or description")
            .navigationDestination(for: ClubRoute.self) { route in
                ClubDetailView(club: route.club, welcome: route.welcome)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Start a club")
                }
            }
            .sheet(isPresented: $showCreate) {
                NewClubSheet { club in
                    Task {
                        await reload()
                        await clubContext.bootstrap()
                        // Straight into the new club: adding players happens there.
                        path.append(ClubRoute(club: club, welcome: true))
                    }
                }
            }
            .task(id: search) {
                // One request per pause in typing, not per keystroke.
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, filters.query != search else { return }
                filters.query = search
            }
            .task(id: filters) { await reload() }
            .task { await reloadInvites() }
            .refreshable {
                await reloadInvites()
                await reload()
            }
        }
    }

    private static let howClubsWork: [(String, String)] = [
        ("A secretary runs the club", "Members and their roles, teams, grounds, fixtures and fees."),
        ("Players join by invite", "Added by email or mobile, or from their profile link — then accepted here or on Home."),
        ("Captains pick the side", "Everyone says whether they can play; the captain picks from who is available."),
        ("Matches are scored live", "Ball by ball. Stats and the club's public page keep themselves up to date."),
    ]

    private var filterMenu: some View {
        Menu {
            Picker("Your role", selection: $filters.role) {
                Text("All roles").tag(ClubListFilters.Role?.none)
                ForEach(ClubListFilters.Role.allCases) { Text($0.label).tag(Optional($0)) }
            }
            Picker("Sport", selection: $filters.sport) {
                Text("All sports").tag(String?.none)
                ForEach(Self.sports, id: \.self) { Text($0.capitalized).tag(Optional($0)) }
            }
            Picker("Public page", selection: $filters.publicPage) {
                Text("Any public page").tag(Bool?.none)
                Text("Page published").tag(Optional(true))
                Text("No public page").tag(Optional(false))
            }
            Picker("Sort by", selection: $filters.sort) {
                ForEach(ClubListFilters.Sort.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            Image(systemName: filters.role != nil || filters.sport != nil || filters.publicPage != nil
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter and sort")
    }

    @ViewBuilder
    private func rowMenu(_ row: ClubMembershipRow) -> some View {
        if let url = row.publicPageURL {
            Link(destination: url) { Label("View public page", systemImage: "safari") }
            ShareLink(item: url) { Label("Share public page", systemImage: "square.and.arrow.up") }
        } else if row.role.isSecretary {
            NavigationLink {
                PublicPageEditorView(club: row.club)
            } label: {
                Label("Set up public page", systemImage: "globe")
            }
        }
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: FishersTheme.space2) {
                Text("You're not in a club yet").font(FishersTheme.title)
                Text("Start your own, or get invited into the one you play for.")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Label("I run a club", systemImage: "person.3.fill").font(FishersTheme.headline)
                    Text("Set it up in a minute. You become its secretary and can add players straight away.")
                        .font(FishersTheme.footnote).foregroundStyle(.secondary)
                    Button {
                        showCreate = true
                    } label: {
                        Label("Start a club", systemImage: "plus")
                            .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(12)
                .background(FishersTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                if let user = session.user {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("I play for a club", systemImage: "figure.cricket").font(FishersTheme.headline)
                        Text("Send your profile link to the secretary. Their invite appears here to accept.")
                            .font(FishersTheme.footnote).foregroundStyle(.secondary)
                        ShareProfileView(userId: user.id)
                    }
                    .padding(12)
                    .background(FishersTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func clearFilters() {
        search = ""
        filters = ClubListFilters(sort: filters.sort)
    }

    private func reloadInvites() async {
        invites = ((try? await FishersAPI.myInvites()) ?? []).filter(\.isPending)
    }

    private func reload() async {
        generation += 1
        let mine = generation
        loading = true
        defer { if mine == generation { loading = false } }
        do {
            let first = try await FishersAPI.myClubs(filters, page: 1)
            guard mine == generation else { return }
            rows = first.items
            total = first.total
            page = 1
            hasMore = first.hasMore
            message = nil
        } catch {
            guard mine == generation else { return }
            message = (error as? APIError)?.friendlyMessage ?? error.localizedDescription
        }
        loaded = true
    }

    private func loadMore() async {
        guard !loading, hasMore else { return }
        let mine = generation
        loading = true
        defer { loading = false }
        guard let next = try? await FishersAPI.myClubs(filters, page: page + 1), mine == generation else { return }
        rows += next.items.filter { item in !rows.contains { $0.id == item.id } }
        page += 1
        hasMore = next.hasMore
        total = next.total
    }
}

/// Where a club row leads — and whether it is the club just created.
struct ClubRoute: Hashable {
    let club: Club
    let welcome: Bool
}

/// One club in the list: its crest, what it is, and what you are in it.
struct ClubRowView: View {
    let row: ClubMembershipRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ClubCrest(name: row.name, id: row.id, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name).font(FishersTheme.headline).lineLimit(2)
                    Spacer(minLength: 6)
                    Text(row.roleLabel)
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(FishersTheme.gold.opacity(0.22), in: Capsule())
                        .foregroundStyle(FishersTheme.maybe)
                }
                Label(row.isPublic ? "Anyone can find it" : "Invite only",
                      systemImage: row.isPublic ? "person.2" : "lock")
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
                if let description = row.description, !description.isEmpty {
                    Text(description).font(FishersTheme.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 12) {
                    Label("\(row.memberCount)", systemImage: "person.2.fill")
                        .accessibilityLabel("\(row.memberCount) \(row.memberCount == 1 ? "member" : "members")")
                    Label("\(row.teamCount)", systemImage: "shield")
                        .accessibilityLabel("\(row.teamCount) \(row.teamCount == 1 ? "team" : "teams")")
                    Text(row.sportTypes.map(\.capitalized).joined(separator: " · "))
                        .lineLimit(1)
                    if row.publicSlug != nil {
                        Image(systemName: "globe").foregroundStyle(FishersTheme.pitch)
                            .accessibilityLabel("Public page published")
                    }
                }
                .font(FishersTheme.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A club's initials on one of three colours, fixed per club, so a long list
/// is not a wall of identical squares.
struct ClubCrest: View {
    let name: String
    let id: UUID
    var size: CGFloat = 44

    /// From words that start with a letter: "Captain 1974 CC" is CC, not C1.
    private var initials: String {
        name.split(separator: " ")
            .filter { $0.first?.isLetter == true }
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    private var colour: Color {
        let tone = Int(id.uuidString.suffix(2), radix: 16).map { $0 % 3 } ?? 0
        switch tone {
        case 1: return FishersTheme.gold600
        case 2: return FishersTheme.sage900
        default: return FishersTheme.pitch
        }
    }

    var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(colour, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Whoever creates the club is its first secretary, so this is also how a new
/// account gets somewhere to add people to.
struct NewClubSheet: View {
    let onCreated: (Club) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    /// Set when the API refuses because the account is not confirmed yet: the
    /// code goes in right here, then the same club is created without retyping.
    @State private var verification: VerificationStatus?

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

    private var missing: String? {
        if name.trimmingCharacters(in: .whitespaces).count < 2 { return "Give the club a name to continue." }
        if sports.isEmpty { return "Pick at least one sport." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ClubCrest(name: name.isEmpty ? "Your club" : name, id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, size: 48)
                        TextField("Fishers CC", text: $name)
                            .font(FishersTheme.headline)
                            .textInputAutocapitalization(.words)
                    }
                } header: {
                    Text("1 · Club name")
                } footer: {
                    Text("How your players and the clubs you play will see you.")
                }

                Section {
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
                } header: {
                    Text("2 · Sports played")
                } footer: {
                    Text("Pick every one you play — teams are set up per sport inside the club.")
                }

                Section {
                    visibilityOption(isPublic: false, title: "Invite only", icon: "lock",
                                     detail: "Kept out of search. Players join with an invite.")
                    visibilityOption(isPublic: true, title: "Anyone can find it", icon: "person.2",
                                     detail: "Other clubs can find you by name when they arrange a match.")
                } header: {
                    Text("3 · Who can find it")
                }

                Section {
                    TextField("Sunday friendlies, Hemel Hempstead", text: $blurb, axis: .vertical)
                        .lineLimit(2...5)
                    Toggle("A friend group, not a club", isOn: $isInformal)
                } header: {
                    Text("4 · Description (optional)")
                } footer: {
                    Text("Where and when you play. It shows on the club card.")
                }

                if let verification {
                    Section {
                        VerifyContactView(status: verification, compact: true) { user in
                            session.adopt(user)
                            self.verification = nil
                            message = nil
                            Task { await create() }
                        }
                    } header: {
                        Label("One thing first — confirm it's you", systemImage: "checkmark.shield")
                    }
                } else if let message {
                    Text(message).foregroundStyle(FishersTheme.unavailable)
                }

                Section {
                    Label(missing ?? "You become its secretary, so you can add members straight away.",
                          systemImage: missing == nil ? "checkmark.shield" : "info.circle")
                        .font(FishersTheme.footnote)
                        .foregroundStyle(.secondary)
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
                        .disabled(isSaving || missing != nil)
                }
            }
        }
    }

    private func visibilityOption(isPublic value: Bool, title: String, icon: String, detail: String) -> some View {
        Button {
            isPublic = value
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 28)
                    .foregroundStyle(isPublic == value ? FishersTheme.pitch : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary).font(FishersTheme.headline)
                    Text(detail).font(FishersTheme.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isPublic == value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isPublic == value ? FishersTheme.pitch : .secondary)
            }
        }
        .accessibilityAddTraits(isPublic == value ? .isSelected : [])
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let trimmedBlurb = blurb.trimmingCharacters(in: .whitespacesAndNewlines)
            let club = try await FishersAPI.createClub(
                name: name.trimmingCharacters(in: .whitespaces),
                sports: Self.allSports.filter(sports.contains),
                informal: isInformal,
                visibility: isPublic ? "public" : "invite_only",
                description: trimmedBlurb.isEmpty ? nil : trimmedBlurb
            )
            onCreated(club)
            dismiss()
        } catch let api as APIError where api.isUnverified {
            verification = try? await FishersAPI.verificationStatus()
            message = api.friendlyMessage
        } catch {
            message = (error as? APIError)?.friendlyMessage ?? error.localizedDescription
        }
    }
}

struct ClubDetailView: View {
    let club: Club
    /// Arrived straight from creating it: say what comes next.
    var welcome: Bool = false

    @State private var teams: [Team] = []
    @State private var events: [Event] = []
    @State private var blocks: [FixtureBlock] = []
    @State private var venues: [Venue] = []
    @State private var members: [ClubMemberDetail] = []
    @State private var isCreatingTournament = false
    @State private var newTournamentName = ""
    @State private var role: ClubRoleInfo?
    @State private var showWelcome = false
    @State private var addingTeam = false
    @State private var addingGround = false
    @State private var openAdmin = false
    @State private var setupHidden = true

    private var isSecretary: Bool { role?.isSecretary ?? false }
    private var setupKey: String { "fishers:club-setup:\(club.id.uuidString):hidden" }
    private var setup: [ClubSetupStep] {
        ClubSetupStep.steps(members: members, teams: teams.count, venues: venues.count)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ClubCrest(name: club.name, id: club.id, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(club.description ?? "No description yet.")
                            .font(FishersTheme.subhead)
                            .foregroundStyle(club.description == nil ? .secondary : .primary)
                        Label(club.visibility == "public" ? "Anyone can find it" : "Invite only",
                              systemImage: club.visibility == "public" ? "person.2" : "lock")
                            .font(FishersTheme.footnote)
                            .foregroundStyle(.secondary)
                        if let role {
                            Text(RoleChoice(role: role.role, isCaptain: members.first { $0.userId == myId }?.isCaptain ?? false).label)
                                .font(.caption2.weight(.bold))
                                .textCase(.uppercase)
                                .foregroundStyle(FishersTheme.maybe)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if isSecretary, !setupHidden, setup.contains(where: { !$0.done }) {
                setupSection
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

            Section {
                NavigationLink {
                    ClubAdminView(club: club, role: role)
                } label: {
                    Label("\(members.count) \(members.count == 1 ? "member" : "members")", systemImage: "person.2")
                }
            } header: {
                Text("Members")
            }

            Section {
                if teams.isEmpty {
                    Text("No teams yet. A club can run without them — teams are for a 1st XI and a 2nd XI keeping separate squads.")
                        .font(FishersTheme.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(teams) { team in
                        NavigationLink {
                            TeamRosterView(team: team)
                        } label: {
                            LabeledContent(team.name, value: team.sport.capitalized)
                        }
                    }
                }
                if isSecretary {
                    Button { addingTeam = true } label: { Label("Add a team", systemImage: "plus") }
                }
            } header: {
                Text("Teams")
            }

            GroundsSection(venues: venues, canEdit: isSecretary) { addingGround = true }

            Section {
                if isSecretary {
                    NavigationLink {
                        PublicPageEditorView(club: club)
                    } label: {
                        Label("Your public page", systemImage: "globe")
                    }
                } else {
                    Label("The secretary sets up the club's public page.", systemImage: "globe")
                        .font(FishersTheme.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Public page")
            } footer: {
                Text("A page anyone can open — no login: your record, top players and next fixtures.")
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
        .fishersList()
        .navigationTitle(club.name)
        .navigationDestination(for: Event.self) { EventDetailView(eventId: $0.id) }
        .navigationDestination(for: FixtureBlock.self) { TournamentView(block: $0) }
        .navigationDestination(isPresented: $openAdmin) {
            ClubAdminView(club: club, role: role, startAdding: true)
        }
        .task {
            setupHidden = UserDefaults.standard.bool(forKey: setupKey)
            await load()
            if welcome, !UserDefaults.standard.bool(forKey: setupKey + ":welcomed") {
                UserDefaults.standard.set(true, forKey: setupKey + ":welcomed")
                showWelcome = true
            }
        }
        .refreshable { await load() }
        .sheet(isPresented: $showWelcome) {
            ClubWelcomeSheet(clubName: club.name, steps: setup) {
                showWelcome = false
                openAdmin = true
            }
        }
        .sheet(isPresented: $addingTeam) {
            AddTeamSheet(club: club) { Task { await load() } }
        }
        .sheet(isPresented: $addingGround) {
            AddGroundSheet(clubId: club.id) { Task { await load() } }
        }
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
                    if isSecretary {
                        if setupHidden && setup.contains(where: { !$0.done }) {
                            Button {
                                setupHidden = false
                                UserDefaults.standard.set(false, forKey: setupKey)
                            } label: {
                                Label("Show club setup", systemImage: "sparkles")
                            }
                        }
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

    private var myId: UUID? { KeychainStore.get("user_id").flatMap(UUID.init(uuidString:)) }

    /// The checklist, until it is done or hidden. Ticked off from what exists
    /// — members, teams, a captain, a ground — never from what was tapped.
    private var setupSection: some View {
        Section {
            let done = setup.filter(\.done).count + 1
            let total = setup.count + 1
            VStack(alignment: .leading, spacing: 6) {
                Text("Get \(club.name) ready for its first match").font(FishersTheme.headline)
                Text("\(done) of \(total) done — \(total - done) to go.")
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(done), total: Double(total)).tint(FishersTheme.pitch)
            }
            .padding(.vertical, 4)
            ForEach(setup) { step in
                Button {
                    switch step.kind {
                    case .players, .captain: openAdmin = true
                    case .team: addingTeam = true
                    case .ground: addingGround = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: step.done ? "checkmark.circle.fill" : step.systemImage)
                            .foregroundStyle(step.done ? FishersTheme.pitch : FishersTheme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .foregroundStyle(step.done ? .secondary : .primary)
                                .strikethrough(step.done)
                            if !step.done {
                                Text(step.detail).font(FishersTheme.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .disabled(step.done)
                .accessibilityValue(step.done ? "Done" : "To do")
            }
        } header: {
            HStack {
                Label("Club setup", systemImage: "sparkles")
                Spacer()
                Button("Hide") {
                    setupHidden = true
                    UserDefaults.standard.set(true, forKey: setupKey)
                }
                .font(FishersTheme.footnote)
                .textCase(nil)
            }
        }
    }

    private func load() async {
        async let t = FishersAPI.teams(clubId: club.id)
        async let e = FishersAPI.events(clubId: club.id)
        async let b = FishersAPI.fixtureBlocks(clubId: club.id)
        async let r = FishersAPI.myClubRole(clubId: club.id)
        async let v = FishersAPI.venues(clubId: club.id)
        async let m = FishersAPI.clubMembers(clubId: club.id)
        teams = (try? await t) ?? []
        events = (try? await e) ?? []
        blocks = (try? await b) ?? []
        role = try? await r
        venues = (try? await v) ?? []
        members = ((try? await m) ?? []).filter(\.isActive)
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

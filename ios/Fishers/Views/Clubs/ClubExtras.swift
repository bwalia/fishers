import SwiftUI
import MapKit

// MARK: - Welcome

/// "Boom Blast is ready" — straight after the club is made, what comes next,
/// with the one button that starts it.
struct ClubWelcomeSheet: View {
    let clubName: String
    let steps: [ClubSetupStep]
    let onAddPlayers: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: FishersTheme.space2) {
            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(FishersTheme.pitch, in: Circle())
                .padding(.top, FishersTheme.space3)
                .accessibilityHidden(true)
            Text("CLUB CREATED").font(FishersTheme.overline).tracking(0.8).foregroundStyle(FishersTheme.pitch)
            Text("\(clubName) is ready").font(FishersTheme.display).multilineTextAlignment(.center)
            Text("You're its secretary. Bring your players in next — then a team, a captain and a ground, and you're set for your first fixture.")
                .font(FishersTheme.subhead)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                row(number: nil, title: "Create your club", detail: nil, current: false)
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    row(number: index + 2, title: step.title, detail: index == 0 ? step.detail : nil, current: index == 0)
                }
            }
            .padding(.vertical, FishersTheme.space1)

            Spacer(minLength: 0)

            Button {
                onAddPlayers()
            } label: {
                Label("Add players", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("I'll do it later") { dismiss() }
                .frame(minHeight: FishersTheme.minTap)
        }
        .padding(.horizontal, FishersTheme.space3)
        .padding(.bottom, FishersTheme.space2)
        .presentationDetents([.large])
    }

    private func row(number: Int?, title: String, detail: String?, current: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(number == nil || current ? FishersTheme.pitch : FishersTheme.raised)
                if let number {
                    Text("\(number)").font(FishersTheme.caption).foregroundStyle(current ? .white : .secondary)
                } else {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                }
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(current ? FishersTheme.headline : FishersTheme.body)
                    .foregroundStyle(current || number == nil ? .primary : .secondary)
                if let detail {
                    Text(detail).font(FishersTheme.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(current ? 10 : 0)
        .background(current ? FishersTheme.raised : .clear, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Teams

/// One team, and who is in it.
struct TeamRosterView: View {
    let team: Team
    @State private var members: [TeamMemberRow]?
    @State private var failed = false

    var body: some View {
        List {
            if let members {
                if members.isEmpty {
                    ContentUnavailableView(
                        "Nobody in this team yet",
                        systemImage: "person.3",
                        description: Text("A secretary or the team captain adds people.")
                    )
                } else {
                    Section("\(members.count) in the squad") {
                        ForEach(members) { member in
                            NavigationLink {
                                PlayerProfileView(userId: member.userId, knownName: member.name)
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarView(name: member.name, urlString: member.avatarUrl, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(member.name)
                                        if let position = member.positionRole {
                                            Text(position).font(FishersTheme.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if member.role != .member {
                                        Text(member.role.shortLabel)
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(FishersTheme.pitch)
                                    }
                                }
                            }
                        }
                    }
                }
            } else if failed {
                Text("Could not load this team.").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .fishersList()
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { members = try await FishersAPI.teamMembers(teamId: team.id) } catch { failed = true }
        }
    }
}

struct AddTeamSheet: View {
    let club: Club
    let onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var sport = "cricket"
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("1st XI", text: $name)
                    Picker("Sport", selection: $sport) {
                        ForEach(club.sportTypes.isEmpty ? ["cricket"] : club.sportTypes, id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }
                } footer: {
                    Text("Each team keeps its own squad and fixtures. You can add more any time.")
                }
                if let error {
                    Text(error).foregroundStyle(FishersTheme.unavailable)
                }
            }
            .navigationTitle("Add a team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .bold()
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { sport = club.sportTypes.first ?? "cricket" }
        }
    }

    private func create() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await FishersAPI.createTeam(clubId: club.id, name: name.trimmingCharacters(in: .whitespaces), sport: sport)
            onAdded()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.friendlyMessage ?? error.localizedDescription
        }
    }
}

// MARK: - Grounds

/// Where the club plays. A fixture carries a ground, and until somebody has
/// entered one there is nothing to carry — which is why "where are we
/// playing?" ends up in the group chat every Saturday morning.
struct GroundsSection: View {
    let venues: [Venue]
    let canEdit: Bool
    let onAdd: () -> Void

    var body: some View {
        Section {
            if venues.isEmpty {
                Text("No grounds yet. Add the ones you play at and they can be picked when a fixture is scheduled.")
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(venues) { venue in
                HStack(spacing: 12) {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(FishersTheme.pitch).font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(venue.name)
                        if let address = venue.address {
                            Text(address).font(FishersTheme.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    // Somebody standing in a car park wants the map, not the
                    // address as text.
                    if let url = mapsURL(venue) {
                        Link(destination: url) {
                            Image(systemName: "map")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Open \(venue.name) in Maps")
                    }
                }
            }
            if canEdit {
                Button(action: onAdd) { Label("Add a ground", systemImage: "plus") }
            }
        } header: {
            Text("Grounds")
        }
    }

    private func mapsURL(_ venue: Venue) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: [venue.name, venue.address].compactMap { $0 }.joined(separator: ", "))]
        return components?.url
    }
}

struct AddGroundSheet: View {
    let clubId: UUID
    let onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Highbury Fields", text: $name)
                    TextField("Highbury Fields, London N5 1AR", text: $address, axis: .vertical)
                        .textContentType(.fullStreetAddress)
                } footer: {
                    Text("It can be picked whenever a fixture is scheduled, and players get a map to it.")
                }
                if let error {
                    Text(error).foregroundStyle(FishersTheme.unavailable)
                }
            }
            .navigationTitle("Add a ground")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await add() } }
                        .bold()
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func add() async {
        busy = true
        defer { busy = false }
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await FishersAPI.createVenue(
                clubId: clubId,
                name: name.trimmingCharacters(in: .whitespaces),
                address: trimmedAddress.isEmpty ? nil : trimmedAddress
            )
            onAdded()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.friendlyMessage ?? error.localizedDescription
        }
    }
}

// MARK: - Public page

/// The club's own public site, without them having to build one.
struct PublicPageEditorView: View {
    let club: Club
    @State private var page: ClubPageSettings?
    @State private var members: [ClubMemberDetail] = []
    @State private var slug = ""
    @State private var founded = ""
    @State private var busy = false
    @State private var saved = false
    @State private var error: String?

    private var suggested: String { ClubPageSettings.suggestedSlug(for: club.name) }
    private var address: String {
        let trimmed = slug.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? suggested : trimmed
    }

    var body: some View {
        Form {
            if let binding = Binding($page) {
                Section {
                    HStack {
                        Label(binding.wrappedValue.publicPage ? "Live" : "Not published",
                              systemImage: binding.wrappedValue.publicPage ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(binding.wrappedValue.publicPage ? FishersTheme.pitch : .secondary)
                        Spacer()
                        if binding.wrappedValue.publicPage, let slug = binding.wrappedValue.slug {
                            let url = AppConfig.webBaseURL.appending(path: "c/\(slug)")
                            Link("View", destination: url).buttonStyle(.borderless)
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                                .buttonStyle(.borderless)
                        }
                    }
                } footer: {
                    Text("A page anyone can open — no login. Your record and top players are worked out from the matches you have played; the rest is yours to write.")
                }

                Section("Web address") {
                    TextField(suggested, text: $slug)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("\(AppConfig.webBaseURL.host() ?? "fishers.cloud")/c/\(address)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Section("About the club") {
                    TextField("Sunday cricket in north London since 1974.", text: optional(binding.tagline))
                    TextField("Who you are, where you play, who you are looking for.", text: optional(binding.about), axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Details") {
                    TextField("Ground — Highbury Fields, London N5", text: optional(binding.ground))
                    TextField("Founded — 1974", text: $founded).keyboardType(.numberPad)
                    TextField("Email for new players", text: optional(binding.contactEmail))
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Picker("Lead with", selection: binding.iconPlayerId) {
                        Text("Nobody for now").tag(UUID?.none)
                        ForEach(members.filter(\.isActive)) { Text($0.name).tag(Optional($0.userId)) }
                    }
                } footer: {
                    Text("The one player the club puts on its front page. Optional.")
                }

                if let error {
                    Text(error).foregroundStyle(FishersTheme.unavailable)
                }

                Section {
                    Button {
                        Task { await save(publish: nil) }
                    } label: {
                        Text(saved ? "Saved" : "Save").frame(maxWidth: .infinity)
                    }
                    .disabled(busy)
                    Button {
                        Task { await save(publish: !binding.wrappedValue.publicPage) }
                    } label: {
                        Text(binding.wrappedValue.publicPage ? "Take it offline" : "Publish it").frame(maxWidth: .infinity)
                    }
                    .disabled(busy)
                }
            } else if error != nil {
                Text(error ?? "").foregroundStyle(FishersTheme.unavailable)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Public page")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    /// A text field for an optional string: empty means "not set".
    private func optional(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func load() async {
        do {
            async let p = FishersAPI.clubPage(clubId: club.id)
            async let m = FishersAPI.clubMembers(clubId: club.id)
            let fetched = try await p
            page = fetched
            slug = fetched.slug ?? ""
            founded = fetched.foundedYear.map(String.init) ?? ""
            members = (try? await m) ?? []
        } catch {
            self.error = (error as? APIError)?.friendlyMessage ?? error.localizedDescription
        }
    }

    private func save(publish: Bool?) async {
        guard var current = page else { return }
        busy = true
        saved = false
        error = nil
        defer { busy = false }
        current.slug = address
        current.foundedYear = Int(founded.trimmingCharacters(in: .whitespaces))
        do {
            let updated = try await FishersAPI.updateClubPage(clubId: club.id, current, publish: publish)
            page = updated
            slug = updated.slug ?? ""
            saved = true
        } catch {
            self.error = (error as? APIError)?.friendlyMessage ?? "Could not save the page"
        }
    }
}

// MARK: - A player's shared profile

/// Where a player's shared profile link lands, for a secretary or captain.
///
/// The player's card and one choice: which club, and which team in it. The
/// invite goes to their account and they approve it — sharing a link never
/// puts anyone in a club they did not agree to join.
struct SharedPlayerCardView: View {
    let token: String
    var preferredClubId: UUID?

    private struct Place: Identifiable {
        let club: Club
        let role: ClubRoleInfo
        let teams: [Team]
        var id: UUID { club.id }
        var canInviteToClub: Bool { role.permissions.contains("invite_to_club") }
    }

    @State private var card: SharedPlayerCard?
    @State private var places: [Place] = []
    @State private var clubId: UUID?
    @State private var teamId: UUID?
    @State private var busy = false
    @State private var sent: String?
    @State private var error: String?

    private var place: Place? { places.first { $0.id == clubId } }

    var body: some View {
        List {
            if let card {
                Section {
                    HStack(spacing: 14) {
                        AvatarView(name: card.name, urlString: card.avatarUrl, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.name).font(FishersTheme.title)
                            let sport = card.sportProfiles?.first { $0.sport == card.primarySport } ?? card.sportProfiles?.first
                            Text([card.primarySport?.capitalized, sport?.position, sport?.skillLevel, card.area]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(FishersTheme.subhead)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("No contact details — those come with membership, which they still accept.")
                }

                if let sent {
                    Section {
                        Label("Invite sent to \(card.name) for \(sent). It appears for them to accept.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(FishersTheme.pitch)
                    }
                } else if places.isEmpty {
                    Section {
                        Text("You can't invite anyone yet — that takes a club where you're the secretary or a captain.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Invite them to") {
                        Picker("Club", selection: $clubId) {
                            ForEach(places) { Text($0.club.name).tag(Optional($0.id)) }
                        }
                        if let place {
                            Picker("Team", selection: $teamId) {
                                if place.canInviteToClub { Text("The club as a whole").tag(UUID?.none) }
                                ForEach(place.teams) { Text($0.name).tag(Optional($0.id)) }
                            }
                        }
                        Button {
                            Task { await invite() }
                        } label: {
                            Group {
                                if busy { ProgressView() } else { Label("Send the invite", systemImage: "paperplane") }
                            }
                            .frame(maxWidth: .infinity, minHeight: FishersTheme.minTap)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || place == nil || (teamId == nil && place?.canInviteToClub == false))
                    }
                }
            } else if let error {
                ContentUnavailableView {
                    Label("This link didn't work", systemImage: "link")
                } description: {
                    Text("\(error). Ask the player to send you their link again.")
                }
            } else {
                ProgressView()
            }
            if card != nil, let error {
                Section { Text(error).foregroundStyle(FishersTheme.unavailable) }
            }
        }
        .fishersList()
        .navigationTitle("Player profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: clubId) { _, id in
            guard let place = places.first(where: { $0.id == id }) else { return }
            teamId = place.canInviteToClub ? nil : place.teams.first?.id
        }
    }

    private func load() async {
        do {
            async let c = FishersAPI.sharedPlayerCard(token: token)
            async let mine = FishersAPI.clubs()
            let fetched = try await c
            var found: [Place] = []
            for club in (try? await mine) ?? [] {
                guard let role = try? await FishersAPI.myClubRole(clubId: club.id),
                      role.permissions.contains("invite_to_club") || role.permissions.contains("invite_to_team")
                else { continue }
                let teams = (try? await FishersAPI.teams(clubId: club.id)) ?? []
                found.append(Place(club: club, role: role, teams: teams))
            }
            card = fetched
            places = found
            let start = found.first { $0.id == preferredClubId } ?? found.first
            clubId = start?.id
            teamId = (start?.canInviteToClub ?? true) ? nil : start?.teams.first?.id
        } catch {
            self.error = (error as? APIError)?.friendlyMessage ?? "That profile link did not open"
        }
    }

    private func invite() async {
        guard let card, let place else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await FishersAPI.invite(userId: card.id, toClub: place.club.id, toTeam: teamId)
            let team = place.teams.first { $0.id == teamId }
            sent = team.map { "\($0.name) at \(place.club.name)" } ?? place.club.name
        } catch {
            self.error = (error as? APIError)?.friendlyMessage ?? "Could not send the invite"
        }
    }
}

import SwiftUI

/// The player card: who they are, what they play and at what level, how they
/// travel, and the reliability score captains weigh when picking squads.
struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var isEditing = false
    @State private var confirmSignOut = false
    @State private var meStats: MeStatsResponse?
    @State private var statsError: String?

    var body: some View {
        NavigationStack {
            List {
                if let user = session.user {
                    header(user)
                    if let reliability = user.reliability {
                        Section("Reliability") {
                            ReliabilityCard(reliability: reliability)
                                .padding(.vertical, 4)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    seasonStatsSections
                    ForEach(user.profiles) { profile in
                        sportSection(profile)
                    }
                    if let location = user.location, !location.isEmpty {
                        locationSection(location)
                    }
                    contactSection(user)
                }
                shopSection
                accountSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { isEditing = true }
                }
            }
            .sheet(isPresented: $isEditing) {
                ProfileEditView(user: session.user)
            }
            .confirmationDialog("Sign out of Fishers?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    session.signOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can sign back in anytime on this device.")
            }
            .task {
                await session.refreshProfile()
                await loadSeasonStats()
            }
            .refreshable {
                await session.refreshProfile()
                await loadSeasonStats()
            }
        }
    }

    @ViewBuilder
    private var seasonStatsSections: some View {
        if let err = statsError {
            Section("Season stats") {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        if let meStats {
            if let season = meStats.seasons.first {
                Section {
                    HStack(spacing: 16) {
                        seasonPill(title: "Runs", value: "\(season.runs)")
                        seasonPill(title: "Wickets", value: "\(season.wickets)")
                        seasonPill(title: "Matches", value: "\(season.matches)")
                    }
                    .padding(.vertical, 4)
                    if let avg = season.battingAverage {
                        LabeledContent("Batting avg", value: String(format: "%.1f", avg))
                    }
                    if let bowl = season.bowlingAverage {
                        LabeledContent("Bowling avg", value: String(format: "%.1f", bowl))
                    }
                    if let hs = season.highScore {
                        LabeledContent("High score", value: "\(hs)")
                    }
                    if let club = season.clubName {
                        LabeledContent("Club", value: club)
                    }
                    if let url = season.playCricketURL {
                        Link(destination: url) {
                            Label("View on Play-Cricket", systemImage: "arrow.up.right.square")
                        }
                    }
                } header: {
                    Text("\(season.seasonYear) season · Play-Cricket")
                } footer: {
                    Text("Sample ECB Play-Cricket import. Live sync uses your club API token when configured.")
                }
            }
            if !meStats.achievements.isEmpty {
                Section("Achievements") {
                    ForEach(meStats.achievements) { a in
                        HStack(alignment: .top, spacing: 12) {
                            Text(a.icon ?? "★")
                                .font(.title3.weight(.bold))
                                .frame(width: 36, height: 36)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.title)
                                    .font(.body.weight(.semibold))
                                if let desc = a.description {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let year = a.seasonYear {
                                    Text("Season \(year)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            if meStats.links.contains(where: { $0.profileURL != nil }) {
                Section("Play-Cricket profiles") {
                    ForEach(meStats.links) { link in
                        if let url = link.profileURL {
                            Link(destination: url) {
                                Label(link.displayName ?? "Player profile", systemImage: "sportscourt")
                            }
                        }
                    }
                }
            }
        }
    }

    private func seasonPill(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadSeasonStats() async {
        do {
            meStats = try await FishersAPI.mySeasonStats(season: 2026)
            statsError = nil
        } catch {
            statsError = "Could not load season stats"
            meStats = nil
        }
    }

    // MARK: Sections

    private func header(_ user: PublicUser) -> some View {
        Section {
            HStack(spacing: FishersTheme.space2) {
                ProfileAvatar(user: user, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(FishersTheme.contentTitle)
                    Text(user.email)
                        .font(FishersTheme.subhead)
                        .foregroundStyle(.secondary)
                    if let primary = user.primaryProfile, let sport = primary.sportKind {
                        Label(
                            [sport.label, primary.tier?.label].compactMap { $0 }.joined(separator: " · "),
                            systemImage: sport.systemImage
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                    }
                }
                Spacer(minLength: 0)
                if let reliability = user.reliability {
                    ReliabilityRing(reliability: reliability, size: 56)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    private func sportSection(_ profile: SportProfile) -> some View {
        Section {
            if let tier = profile.tier {
                LabeledContent("Level", value: tier.label)
                if let next = tier.next {
                    Label("Working towards \(next.label)", systemImage: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let position = profile.position {
                LabeledContent("Position", value: position)
            }
            if let team = profile.teamName {
                LabeledContent("Team", value: team)
            }
            if let division = profile.division {
                LabeledContent("Division") {
                    HStack(spacing: 6) {
                        Text(division.label)
                        if let target = profile.target, target.rank > division.rank {
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(target.shortLabel)
                                .foregroundStyle(.tint)
                        }
                    }
                }
                if profile.divisionsToTarget > 0 {
                    DivisionLadder(current: division, target: profile.target)
                        .padding(.vertical, 4)
                }
            }
            if let age = profile.ageBand {
                LabeledContent("Age group", value: age.label)
            }
            if let years = profile.yearsPlaying, years > 0 {
                LabeledContent("Years playing", value: "\(years)")
            }
            ForEach(SportStats.summary(for: profile), id: \.label) { stat in
                LabeledContent(stat.label, value: stat.value)
            }
        } header: {
            HStack {
                if let sport = profile.sportKind {
                    Label(sport.label, systemImage: sport.systemImage)
                }
                if session.user?.primarySport == profile.sport {
                    Text("MAIN")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    private func locationSection(_ location: PlayerLocation) -> some View {
        Section("Travel & logistics") {
            if let summary = location.summary {
                LabeledContent("Based", value: summary)
            }
            if let radius = location.travelRadiusMiles {
                LabeledContent("Will travel", value: "\(radius) miles")
            }
            if let transport = location.transport {
                LabeledContent("Transport") {
                    Label(transport.label, systemImage: transport.systemImage)
                }
                if transport.offersLifts, let seats = location.spareSeats, seats > 0 {
                    LabeledContent("Spare seats", value: "\(seats)")
                }
            }
            if !location.weekdays.isEmpty {
                LabeledContent("Usual days", value: location.weekdays.map(\.shortLabel).joined(separator: ", "))
            }
            if let notes = location.notes {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func contactSection(_ user: PublicUser) -> some View {
        Section("Contact") {
            if let phone = user.phone {
                LabeledContent("Mobile", value: phone)
            }
            if let emergency = user.emergencyContact {
                LabeledContent("Emergency", value: emergency)
            }
        }
    }

    private var shopSection: some View {
        Section("Club shop") {
            NavigationLink {
                ShopView()
            } label: {
                Label("Browse kit & food", systemImage: "bag")
            }
        }
    }

    private var accountSection: some View {
        Section {
            LabeledContent("API host", value: AppConfig.apiBaseURL.absoluteString)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                confirmSignOut = true
            } label: {
                Text("Sign out")
            }
        } header: {
            Text("Account")
        }
    }
}

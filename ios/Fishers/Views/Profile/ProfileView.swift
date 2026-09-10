import SwiftUI

/// A player's own page — the face, the numbers, the details.
///
/// Three tabs, the same three the dashboard has: who they are, what they have
/// scored, what they have taken. The batting and bowling figures come from the
/// ball-by-ball log, so they are computed; the overview is what the player has
/// told us about themselves.
struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var tab: Tab = .overview
    @State private var isEditing = false
    @State private var confirmSignOut = false
    @State private var statsRefresh = 0
    @State private var stats: MeStatsResponse?

    enum Tab: String, CaseIterable, Identifiable {
        case overview, batting, bowling
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    /// Whichever club they have played the most for — the one to name in the
    /// band. Falls back to whatever team they typed on their sport profile.
    private var club: String? {
        let played = (stats?.seasons ?? []).reduce(into: [String: Int]()) { tally, season in
            if let name = season.clubName { tally[name, default: 0] += season.matches }
        }
        return played.max { $0.value < $1.value }?.key
            ?? session.user?.primaryProfile?.teamName
    }

    var body: some View {
        NavigationStack {
            List {
                if let user = session.user {
                    Section {
                        ProfileHeroView(user: user, club: club) { updated in
                            session.user = updated
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    Section {
                        Picker("Section", selection: $tab) {
                            ForEach(Tab.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .listRowBackground(Color.clear)

                    switch tab {
                    case .overview: overview(user)
                    case .batting:
                        CareerStatsView(seasons: stats?.seasons ?? [], discipline: .batting)
                    case .bowling:
                        CareerStatsView(seasons: stats?.seasons ?? [], discipline: .bowling)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .fishersList()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { isEditing = true }
                }
            }
            .sheet(isPresented: $isEditing) {
                ProfileEditView(user: session.user)
            }
            .confirmationDialog("Sign out of Fishers?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { session.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can sign back in anytime on this device.")
            }
            .task {
                await session.refreshProfile()
                await loadStats()
            }
            .refreshable {
                await session.refreshProfile()
                await loadStats()
                statsRefresh += 1
            }
        }
    }

    /// A player with no season on record is not an error — the tabs say so.
    private func loadStats() async {
        stats = try? await FishersAPI.mySeasonStats()
    }

    // MARK: - Overview

    @ViewBuilder
    private func overview(_ user: PublicUser) -> some View {
        Section("About \(user.name.split(separator: " ").first.map(String.init) ?? user.name)") {
            LabeledContent("Email", value: user.email ?? "—")
            LabeledContent("Mobile", value: user.phone ?? "—")
            if let emergency = user.emergencyContact {
                LabeledContent("In an emergency", value: emergency)
            }
        }

        if let career = stats?.seasons, !career.isEmpty {
            careerSummary(Totals(career), seasons: career.count)
        }

        if let achievements = stats?.achievements, !achievements.isEmpty {
            Section("Honours") {
                ForEach(achievements) { award in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(award.title).font(FishersTheme.headline)
                        if let detail = award.description {
                            Text(detail).font(FishersTheme.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        if let reliability = user.reliability {
            Section("Reliability") {
                ReliabilityCard(reliability: reliability)
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }

        // Owns its own loading / error / empty states.
        SeasonStatsSection()
            .id(statsRefresh)

        ForEach(user.profiles) { profile in
            sportSection(profile)
        }

        if let location = user.location, !location.isEmpty {
            locationSection(location)
        }

        contactSection(user)

        Section("Club shop") {
            NavigationLink {
                ShopView()
            } label: {
                Label("Browse kit & food", systemImage: "bag")
            }
        }

        Section("Account") {
            LabeledContent("API host", value: AppConfig.apiBaseURL.absoluteString)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Sign out", role: .destructive) {
                confirmSignOut = true
            }
        }
    }

    private func careerSummary(_ t: Totals, seasons: Int) -> some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2),
                      spacing: FishersTheme.space2) {
                figure("Matches", t.matches)
                figure("Runs", t.runs)
                figure("Wickets", t.wickets)
                figure("Catches", t.catches)
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("Career")
        } footer: {
            Text("Across \(seasons) season\(seasons == 1 ? "" : "s"), worked out from the ball-by-ball log.")
        }
    }

    private func figure(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text(String(value))
                .font(FishersTheme.figure(.title))
                .foregroundStyle(FishersTheme.pitch)
            Text(label).font(FishersTheme.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FishersTheme.space1)
        .background(FishersTheme.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Sport

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

    // MARK: - Location / contact

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
}

import SwiftUI

/// A player's own page — the face, the numbers, the details.
///
/// Three tabs, the same three the dashboard has: who they are, what they have
/// scored, what they have taken. The batting and bowling figures come from the
/// ball-by-ball log, so they are computed; the overview is what the player has
/// told us about themselves.
struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var language: LanguageStore
    @State private var tab: Tab = .overview
    @State private var isEditing = false
    @State private var confirmSignOut = false
    @State private var statsRefresh = 0
    @State private var stats: MeStatsResponse?

    enum Tab: String, CaseIterable, Identifiable {
        case overview, batting, bowling, umpiring
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

                    ProfileStrengthSection(user: user, onComplete: { isEditing = true }, offersReminder: false)

                    Section {
                        Picker(tr("Section"), selection: $tab) {
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
                    case .umpiring:
                        PendingUmpireReviewsView()
                        UmpiringView()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .fishersList()
            .navigationTitle(t("nav.profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("cl.edit")) { isEditing = true }
                }
            }
            .sheet(isPresented: $isEditing) {
                ProfileEditView(user: session.user)
            }
            .confirmationDialog("Sign out of \(Brand.name)?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button(t("nav.sign_out"), role: .destructive) { session.signOut() }
                Button(t("sc.cancel"), role: .cancel) {}
            } message: {
                Text(t("rest.sign_back_in_anytime"))
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
            Section(tr("Honours")) {
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
            Section(tr("Reliability")) {
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

        Section(tr("Club shop")) {
            NavigationLink {
                ShopView()
            } label: {
                Label(t("rest.browse_kit_and_food"), systemImage: "bag")
            }
        }

        Section {
            NavigationLink {
                ShareProfileScreen(userId: user.id)
            } label: {
                Label(t("rest.send_my_profile_to_a_club"), systemImage: "link")
            }
        } header: {
            Text(t("rest.joining_a_club"))
        } footer: {
            Text(t("cl.secretary_can_invite_you"))
        }

        Section(tr("Account")) {
            if !user.isVerified {
                NavigationLink {
                    VerifyAccountScreen()
                } label: {
                    Label(t("rest.confirm_email_or_phone"), systemImage: "checkmark.shield")
                        .foregroundStyle(FishersTheme.maybe)
                }
            }
            Picker(selection: Binding(
                get: { user.intent },
                set: { role in
                    guard let role else { return }
                    Task { try? await session.setRoleIntent(role) }
                }
            )) {
                ForEach(RoleIntent.allCases) { Text($0.title).tag(Optional($0)) }
            } label: {
                Label(t("rest.getting_started_guide"), systemImage: "sparkles")
            }
            // In its own script and never translated — a picker offering
            // "Punjabi" in English is no use to the person who needs it. The
            // same reasoning, and the same list, as the web's.
            Picker(selection: Binding(
                get: { language.language },
                set: { language.set($0) }
            )) {
                ForEach(Language.allCases) { Text($0.native).tag($0) }
            } label: {
                Label(language.t("lang.label"), systemImage: "globe")
            }
            NavigationLink {
                APIServerSettingsView()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(t("rest.api_server"), systemImage: "network")
                    Text(AppConfig.displayHost)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button(t("nav.sign_out"), role: .destructive) {
                confirmSignOut = true
            }
        }

        Section {
            // App Store Connect wants a policy anybody can read without an
            // account, so it lives on the web host rather than in here.
            Link(destination: AppConfig.webBaseURL.appendingPathComponent("privacy")) {
                Label(t("rest.privacy"), systemImage: "hand.raised")
            }
            NavigationLink {
                DeleteAccountView()
            } label: {
                Label(t("cl.delete_account"), systemImage: "person.crop.circle.badge.xmark")
                    .foregroundStyle(FishersTheme.unavailable)
            }
        } footer: {
            Text(t("rest.deleting_removes_everything"))
        }
    }

    private func careerSummary(_ totals: Totals, seasons: Int) -> some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2),
                      spacing: FishersTheme.space2) {
                figure("Matches", totals.matches)
                figure("Runs", totals.runs)
                figure("Wickets", totals.wickets)
                figure("Catches", totals.catches)
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text(t("cl.career"))
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
                    Text(t("rest.main_sport_badge"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    // MARK: - Location / contact

    private func locationSection(_ location: PlayerLocation) -> some View {
        Section(tr("Travel & logistics")) {
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
        Section(tr("Contact")) {
            if let phone = user.phone {
                LabeledContent("Mobile", value: phone)
            }
            if let emergency = user.emergencyContact {
                LabeledContent("Emergency", value: emergency)
            }
        }
    }
}


/// Your profile link, with what it is for.
struct ShareProfileScreen: View {
    let userId: UUID

    var body: some View {
        List {
            Section {
                ShareProfileView(userId: userId)
                    .padding(.vertical, 4)
            } footer: {
                Text(t("rest.drop_it_in_whatsapp"))
            }
        }
        .fishersList()
        .navigationTitle(t("rest.your_profile_link"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Confirming an email or phone from Profile, outside the guide.
struct VerifyAccountScreen: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var status: VerificationStatus?
    @State private var failed = false

    var body: some View {
        List {
            Section {
                if let status, status.canVerify {
                    VerifyContactView(status: status) { user in
                        session.adopt(user)
                        dismiss()
                    }
                    .padding(.vertical, 4)
                } else if failed || (status != nil && status?.canVerify == false) {
                    Text(t("rest.codes_cannot_be_sent"))
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            } footer: {
                Text(t("rest.starting_club_needs_confirmed"))
            }
        }
        .fishersList()
        .navigationTitle(t("rest.confirm_its_you"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { status = try await FishersAPI.verificationStatus() } catch { failed = true }
        }
    }
}

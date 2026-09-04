import SwiftUI

/// The player card: who they are, what they play and at what level, how they
/// travel, and the reliability score captains weigh when picking squads.
struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var isEditing = false
    @State private var confirmSignOut = false

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
            .task { await session.refreshProfile() }
        }
    }

    // MARK: Sections

    private func header(_ user: PublicUser) -> some View {
        Section {
            HStack(spacing: FishersTheme.space2) {
                ProfileAvatar(user: user, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(.title3.weight(.semibold))
                    Text(user.email)
                        .font(.subheadline)
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

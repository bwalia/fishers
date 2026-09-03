import SwiftUI

/// The player card: who they are, what they play and at what level, how they
/// travel, and the reliability score captains weigh when picking squads.
struct ProfileView: View {
    @Environment(AppState.self) private var app
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            List {
                if let user = app.currentUser {
                    header(user)
                    if let reliability = user.reliability {
                        Section("Reliability") {
                            ReliabilityCard(reliability: reliability)
                                .padding(.vertical, 4)
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
                settingsSection
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { isEditing = true }
                }
            }
            .sheet(isPresented: $isEditing) {
                ProfileEditView(user: app.currentUser)
            }
            .task { await app.refreshProfile() }
        }
    }

    // MARK: Sections

    private func header(_ user: User) -> some View {
        Section {
            HStack(spacing: 16) {
                AvatarView(user: user, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(.title3.bold())
                    Text(user.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let primary = user.primaryProfile, let sport = primary.sportKind {
                        Label(
                            [sport.label, primary.tier?.label].compactMap { $0 }.joined(separator: " · "),
                            systemImage: sport.systemImage
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer()
                if let reliability = user.reliability {
                    ReliabilityRing(reliability: reliability, size: 56)
                }
            }
            .padding(.vertical, 6)
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
                                .foregroundStyle(Color.accentColor)
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
                if app.currentUser?.primarySport == profile.sport {
                    Text("MAIN")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
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

    private func contactSection(_ user: User) -> some View {
        Section("Contact") {
            if let phone = user.phone {
                LabeledContent("Mobile", value: phone)
            }
            if let emergency = user.emergencyContact {
                LabeledContent("Emergency", value: emergency)
            }
        }
    }

    private var settingsSection: some View {
        Section("Settings") {
            Toggle("Demo mode", isOn: Binding(
                get: { app.demoMode },
                set: { app.setDemoMode($0) }
            ))
            if app.demoMode {
                Button("Redo profile setup") {
                    app.restartProfileSetup()
                }
            }
            Button("Sign out", role: .destructive) {
                app.signOut()
            }
        }
    }
}

#Preview {
    ProfileView()
        .environment(AppState(demoMode: true))
}

import SwiftUI

struct ClubsView: View {
    @Environment(AppState.self) private var app
    @State private var clubs: [Club] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section { ErrorBanner(message: errorMessage).listRowInsets(EdgeInsets()) }
                }
                if clubs.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No clubs yet",
                        systemImage: "person.3",
                        description: Text("Join or create a club to get started.")
                    )
                }
                ForEach(clubs) { club in
                    NavigationLink(value: club) {
                        HStack(spacing: 12) {
                            Image(systemName: sportIcon(club.sportTypes.first ?? ""))
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 40, height: 40)
                                .background(Color.accentColor.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(club.name).font(.headline)
                                Text(club.sportTypes.joined(separator: " · "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(club.visibility.label)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.fill.tertiary, in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Clubs & Teams")
            .navigationDestination(for: Club.self) { club in
                ClubDetailView(club: club)
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            clubs = try await app.api.clubs()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ClubDetailView: View {
    @Environment(AppState.self) private var app
    let club: Club

    @State private var teams: [Team] = []
    @State private var members: [ClubMember] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section { ErrorBanner(message: errorMessage).listRowInsets(EdgeInsets()) }
            }

            Section {
                HStack(spacing: 14) {
                    Image(systemName: sportIcon(club.sportTypes.first ?? ""))
                        .font(.largeTitle)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(club.name).font(.title3.bold())
                        Text("\(club.sportTypes.joined(separator: " · ")) · \(club.visibility.label)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Teams") {
                if teams.isEmpty {
                    Text("No teams yet").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(teams) { team in
                    Label {
                        Text(team.name)
                    } icon: {
                        Image(systemName: sportIcon(team.sport))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            Section("Members · \(members.count)") {
                ForEach(members) { member in
                    HStack(spacing: 10) {
                        if let user = member.user {
                            AvatarView(user: user, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(user.name).font(.subheadline)
                                if let position = user.position {
                                    Text(position).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        if member.role != .member {
                            Text(member.role.label)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle(club.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            async let teamsTask = app.api.teams(clubId: club.id)
            async let membersTask = app.api.members(clubId: club.id)
            let (loadedTeams, loadedMembers) = try await (teamsTask, membersTask)
            teams = loadedTeams
            members = loadedMembers
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ClubsView()
        .environment(AppState(demoMode: true))
}

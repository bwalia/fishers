import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            List {
                if let user = session.user {
                    Section {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(FishersTheme.pitch.gradient)
                                .frame(width: 56, height: 56)
                                .overlay {
                                    Text(String(user.name.prefix(1)).uppercased())
                                        .font(.title2.bold())
                                        .foregroundStyle(.white)
                                }
                            VStack(alignment: .leading) {
                                Text(user.name).font(.headline)
                                Text(user.email).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Sport profile") {
                        LabeledContent("Sports", value: user.sportsPlayed.joined(separator: ", ").capitalized)
                        LabeledContent("Role", value: user.positionRole ?? "—")
                        LabeledContent("Skill", value: user.skillLevel ?? "—")
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        session.signOut()
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}

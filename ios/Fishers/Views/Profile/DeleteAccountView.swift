import SwiftUI

/// Leaving, for good.
///
/// App Store Review 5.1.1(v) requires this to be reachable in the app for
/// anything that lets you create an account. Two steps rather than one button:
/// it cannot be undone, and a mis-tap should not end somebody's season.
struct DeleteAccountView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirming = false
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("Deleting removes your name, email, phone number, password, picture, location and player profile, and signs you out on every device.")
                Text("Scorecards you appear on stay, under no name. They belong to the other players too, and a match that loses a batter stops adding up.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("What happens")
            }

            Section {
                SecureField("Your password", text: $password)
                    .textContentType(.password)
            } footer: {
                Text("Leave blank if you sign in with Google.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(FishersTheme.unavailable)
                }
            }

            Section {
                Button(role: .destructive) {
                    confirming = true
                } label: {
                    if busy {
                        ProgressView()
                    } else {
                        Text("Delete my account")
                    }
                }
                .disabled(busy)
            } footer: {
                Text("This cannot be undone.")
            }
        }
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete your Fishers account?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) { Task { await remove() } }
            Button("Keep my account", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func remove() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await FishersAPI.deleteAccount(password: password.isEmpty ? nil : password)
            // The account is gone; the session on this phone has to go with it.
            session.signOut()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.friendlyMessage ?? error.localizedDescription
        }
    }
}

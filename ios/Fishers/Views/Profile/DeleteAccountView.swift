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
                Text(t("rest.deleting_removes"))
                Text(t("rest.scorecards_stay_unnamed"))
                    .foregroundStyle(.secondary)
            } header: {
                Text(t("rest.what_happens"))
            }

            Section {
                SecureField(t("cl.your_password"), text: $password)
                    .textContentType(.password)
            } footer: {
                Text(t("rest.leave_blank_if_google"))
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
                        Text(t("ld.delete_my_account"))
                    }
                }
                .disabled(busy)
            } footer: {
                Text(t("rest.cannot_be_undone"))
            }
        }
        .navigationTitle(t("cl.delete_account"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete your \(Brand.name) account?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(t("cl.delete_account"), role: .destructive) { Task { await remove() } }
            Button(t("rest.keep_my_account"), role: .cancel) {}
        } message: {
            Text(t("rest.cannot_be_undone"))
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

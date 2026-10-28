import SwiftUI

/// Who you have blocked, and the way back.
///
/// A block you cannot undo is a setting you are stuck with, so the list is as
/// much a part of blocking as the button that does it.
///
/// It shows only your own blocks. The symmetric half — people who blocked you
/// — is deliberately absent: telling you would tell you they had.
struct BlockedListView: View {
    @State private var blocked: [BlockedUser] = []
    @State private var loading = true
    @State private var message: String?

    var body: some View {
        List {
            if blocked.isEmpty && !loading {
                Text(t("mod.nobody_blocked"))
                    .foregroundStyle(.secondary)
            }
            ForEach(blocked) { user in
                HStack {
                    Text(user.name)
                    Spacer()
                    Button(t("mod.unblock")) { lift(user) }
                        .buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle(t("mod.blocked_people"))
        .overlay { if loading { ProgressView() } }
        .task { await load() }
        .alert(message ?? "", isPresented: .constant(message != nil)) {
            Button(t("rest.ok")) { message = nil }
        }
    }

    private func load() async {
        defer { loading = false }
        blocked = (try? await FishersAPI.blockedUsers()) ?? []
    }

    private func lift(_ user: BlockedUser) {
        // Off the list first: the row goes either way, and leaving it sitting
        // there while the request flies looks like nothing happened.
        let previous = blocked
        blocked.removeAll { $0.id == user.id }
        Task {
            do {
                try await FishersAPI.unblock(userId: user.id)
            } catch {
                blocked = previous
                message = t("mod.block_would_not_save")
            }
        }
    }
}

import SwiftUI

/// What is waiting for you.
///
/// Push is still an APNs stub, so opening the app is the only delivery that
/// works — which makes this the difference between "the other captain was told"
/// being true and being a hope.
struct NotificationsView: View {
    @State private var feed = NotificationFeed(unread: 0, items: [])
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        List {
            if feed.items.isEmpty && !isLoading {
                ContentUnavailableView(
                    "Nothing waiting",
                    systemImage: "bell",
                    description: Text("You'll be told here when a captain proposes terms or somebody invites you.")
                )
            }
            ForEach(feed.items) { item in
                row(item)
            }
        }
        .fishersList()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if feed.unread > 0 {
                ToolbarItem(placement: .primaryAction) {
                    Button("Mark all read") {
                        Task {
                            try? await FishersAPI.markNotificationRead(id: nil)
                            await load()
                        }
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .alert("Something went wrong", isPresented: .constant(message != nil)) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    @ViewBuilder
    private func row(_ item: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Unread earns a marker rather than a different background.
            Circle()
                .fill(item.isUnread ? FishersTheme.accent : .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.line)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.sentAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: FishersTheme.minTap)
        .contentShape(Rectangle())
        .onTapGesture {
            guard item.isUnread else { return }
            Task {
                try? await FishersAPI.markNotificationRead(id: item.id)
                await load()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.isUnread ? "Unread. \(item.line)" : item.line)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            feed = try await FishersAPI.notifications()
        } catch {
            message = error.localizedDescription
        }
    }
}

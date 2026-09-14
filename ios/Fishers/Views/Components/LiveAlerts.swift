import SwiftUI

/// Something happened while you were elsewhere in the app: a chat message, an
/// invite to accept, a fixture to answer. A banner at the top that says what
/// and takes you there — rather than a number changing somewhere you might not
/// be looking.
///
/// Not for the thread you are reading (you can see it), and not for what you
/// did yourself.
struct LiveAlerts: View {
    /// The thread on screen, which needs no alert about itself.
    static var openThread: UUID?

    @EnvironmentObject private var session: SessionStore
    @State private var alerts: [Alert] = []
    @State private var seen: Set<String> = []
    @State private var opening: Alert?

    struct Alert: Identifiable, Equatable {
        let id: String
        let icon: String
        let title: String
        var body: String?
        let destination: Destination
    }

    enum Destination: Equatable {
        case thread(ConversationSummary)
        case event(UUID)
        case notifications
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(alerts) { alert in
                AlertCard(alert: alert) {
                    dismiss(alert)
                    opening = alert
                } onClose: {
                    dismiss(alert)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .animation(.spring(duration: 0.3), value: alerts)
        .task {
            for await event in LiveStream.shared.events() {
                if let alert = await build(event), !seen.contains(alert.id) {
                    seen.insert(alert.id)
                    alerts = Array(([alert] + alerts).prefix(3))
                }
            }
        }
        .sheet(item: $opening) { alert in
            NavigationStack {
                destination(alert.destination)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { opening = nil }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func destination(_ destination: Destination) -> some View {
        switch destination {
        case .thread(let conversation): AlertThread(conversation: conversation)
        case .event(let id): EventDetailView(eventId: id)
        case .notifications: NotificationsView()
        }
    }

    private func dismiss(_ alert: Alert) {
        alerts.removeAll { $0.id == alert.id }
    }

    /// An alert that could not be built is one nobody misses.
    private func build(_ event: LiveEvent) async -> Alert? {
        switch event {
        case .message(let conversationId, let id):
            guard conversationId != Self.openThread,
                  let message = try? await FishersAPI.messages(conversationId: conversationId, limit: 1).first,
                  message.id == id, message.senderId != session.user?.id, message.kind != "system",
                  let thread = try? await FishersAPI.conversations().first(where: { $0.id == conversationId })
            else { return nil }
            return Alert(
                id: "m:\(message.id)",
                icon: "bubble.left.fill",
                title: "\(message.authorLabel) · \(thread.title)",
                body: message.body,
                destination: .thread(thread)
            )
        case .notification:
            // The same event fires when something is marked read elsewhere.
            guard let latest = try? await FishersAPI.notifications(perPage: 1).items.first,
                  latest.isUnread
            else { return nil }
            return Alert(
                id: "n:\(latest.id)",
                icon: "bell.fill",
                title: latest.line,
                destination: latest.eventId.map(Destination.event) ?? .notifications
            )
        case .conversations, .match, .resync:
            return nil
        }
    }
}

/// A thread opened from an alert keeps its own store, so a second alert
/// arriving does not reset the messages under the reader.
private struct AlertThread: View {
    let conversation: ConversationSummary
    @StateObject private var store = ChatStore()

    var body: some View { ChatThreadView(conversation: conversation, store: store) }
}

private struct AlertCard: View {
    let alert: LiveAlerts.Alert
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: alert.icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(FishersTheme.pitch, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.title)
                            .font(FishersTheme.subhead.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if let body = alert.body {
                            Text(body)
                                .font(FishersTheme.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: FishersTheme.minTap, height: FishersTheme.minTap)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .padding(.top, -8)
            .padding(.trailing, -10)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("live-alert")
        // Long enough to read a line, short enough not to sit over the screen.
        .task {
            try? await Task.sleep(for: .seconds(6))
            onClose()
        }
    }
}

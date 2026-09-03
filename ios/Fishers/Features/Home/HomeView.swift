import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @State private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            List {
                if let error = viewModel.errorMessage {
                    Section { ErrorBanner(message: error).listRowInsets(EdgeInsets()) }
                }

                if !viewModel.pendingInvites.isEmpty {
                    Section("Invites") {
                        ForEach(viewModel.pendingInvites) { invite in
                            InviteCard(invite: invite) { status in
                                Task {
                                    await viewModel.respond(
                                        inviteId: invite.id, status: status,
                                        api: app.api, currentUserId: app.currentUser?.id
                                    )
                                }
                            }
                        }
                    }
                }

                if !viewModel.unpaidEvents.isEmpty {
                    Section("Fees due") {
                        ForEach(viewModel.unpaidEvents) { event in
                            NavigationLink(value: event) {
                                HStack {
                                    Image(systemName: "sterlingsign.circle.fill")
                                        .foregroundStyle(.orange)
                                    VStack(alignment: .leading) {
                                        Text(event.title).font(.subheadline.weight(.semibold))
                                        Text(event.startAt, format: .dateTime.weekday(.wide).day().month())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text((event.feeAmount ?? 0).money(event.currency ?? "GBP"))
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }

                Section("Upcoming") {
                    if viewModel.upcomingEvents.isEmpty && !viewModel.isLoading {
                        ContentUnavailableView(
                            "Nothing scheduled",
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text("Events from your clubs will appear here.")
                        )
                    } else {
                        ForEach(viewModel.upcomingEvents) { event in
                            NavigationLink(value: event) {
                                EventRow(event: event)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Fishers")
            .navigationDestination(for: Event.self) { event in
                EventDetailView(event: event)
            }
            .refreshable {
                await viewModel.load(api: app.api, currentUserId: app.currentUser?.id)
            }
            .task {
                await viewModel.load(api: app.api, currentUserId: app.currentUser?.id)
            }
        }
    }
}

private struct InviteCard: View {
    let invite: EventInvite
    let onRespond: (RSVPStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let inviter = invite.inviter {
                    AvatarView(user: inviter, size: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let event = invite.event {
                        Text(event.title).font(.subheadline.weight(.semibold))
                        Text(event.startAt, format: .dateTime.weekday(.wide).day().month().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let inviter = invite.inviter {
                        Text("Invited by \(inviter.name)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            HStack(spacing: 8) {
                Button("Going") { onRespond(.going) }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                Button("Maybe") { onRespond(.maybe) }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                Button("Can't") { onRespond(.notGoing) }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
            .font(.footnote.weight(.semibold))
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HomeView()
        .environment(AppState(demoMode: true))
}

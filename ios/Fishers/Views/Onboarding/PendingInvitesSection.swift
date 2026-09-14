import SwiftUI

/// Invitations waiting for this account, as a list section.
///
/// An invite usually arrives as a link, and a link lost in a group chat is the
/// most common reason somebody never joins their club. It is already addressed
/// to this account, so it can simply be listed and accepted here.
///
/// Draws nothing when there is nothing waiting. The parent owns the list, so
/// the getting-started guide can count the same invites.
struct PendingInvitesSection: View {
    let invites: [PendingInvite]
    let onAccepted: () async -> Void

    @State private var busy: UUID?
    @State private var error: String?

    var body: some View {
        if !invites.isEmpty {
            Section {
                ForEach(invites) { invite in
                    HStack(spacing: 12) {
                        Image(systemName: invite.systemImage)
                            .foregroundStyle(FishersTheme.pitch)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invite.title).font(FishersTheme.headline)
                            Text(subtitle(invite))
                                .font(FishersTheme.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button {
                            Task { await accept(invite) }
                        } label: {
                            if busy == invite.id { ProgressView() } else { Text("Accept") }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(busy != nil)
                    }
                    .frame(minHeight: FishersTheme.minTap)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                HStack {
                    Text("Waiting for you").font(FishersTheme.overline).tracking(0.8)
                    Spacer()
                    Text("\(invites.count)")
                        .font(FishersTheme.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(FishersTheme.gold.opacity(0.25), in: Capsule())
                }
            } footer: {
                if let error {
                    Text(error).foregroundStyle(FishersTheme.unavailable)
                } else {
                    Text(invites.count == 1
                         ? "Somebody has invited you. Accepting puts you straight in."
                         : "People have invited you. Accepting puts you straight in.")
                }
            }
        }
    }

    private func subtitle(_ invite: PendingInvite) -> String {
        let sent = invite.createdAt.formatted(.dateTime.day().month(.abbreviated))
        return [invite.invitedByName.map { "from \($0)" }, "sent \(sent)"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func accept(_ invite: PendingInvite) async {
        busy = invite.id
        error = nil
        defer { busy = nil }
        do {
            _ = try await FishersAPI.acceptInvite(token: invite.token)
            await onAccepted()
        } catch let api as APIError where api.isUnverified {
            // The code goes in on this same screen, in the guide below.
            error = "Confirm your email or phone number first — the code is in the getting-started steps."
        } catch {
            self.error = (error as? APIError)?.friendlyMessage ?? error.localizedDescription
        }
    }
}

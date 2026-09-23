import SwiftUI

/// Tournaments another club has asked this one into, and has not been answered.
///
/// The host cannot make the draw until every side has said, so this sits on the
/// club's own screen rather than inside the tournament — which belongs to
/// somebody else and which this club cannot open.
///
/// Draws nothing when there is nothing waiting.
struct EntryInvitationsSection: View {
    let invitations: [EntryInvitation]
    let onAnswered: () async -> Void

    @State private var busy: UUID?
    @State private var error: String?

    var body: some View {
        if !invitations.isEmpty {
            Section {
                ForEach(invitations) { invitation in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(FishersTheme.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invitation.blockName).font(FishersTheme.headline)
                                Text(subtitle(invitation))
                                    .font(FishersTheme.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                        }

                        HStack(spacing: 10) {
                            Button {
                                Task { await answer(invitation, .accepted) }
                            } label: {
                                if busy == invitation.id {
                                    ProgressView()
                                } else {
                                    Text("Accept")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button("Decline") {
                                Task { await answer(invitation, .declined) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .disabled(busy != nil)
                    }
                    .frame(minHeight: FishersTheme.minTap)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(
                        "\(invitation.hostClubName) invited you to \(invitation.blockName)"
                    )
                }

                if let error {
                    Text(error)
                        .font(FishersTheme.footnote)
                        .foregroundStyle(FishersTheme.unavailable)
                }
            } header: {
                HStack {
                    Text("You have been asked").font(FishersTheme.overline).tracking(0.8)
                    Spacer()
                    Text("\(invitations.count)").font(FishersTheme.caption)
                }
            } footer: {
                // Accepting is not entering when there is a fee, and saying
                // otherwise would leave a club thinking its place was safe.
                Text(
                    invitations.contains(where: { ($0.entryFeeCents ?? 0) > 0 })
                        ? "Accepting holds your place. Where there is an entry fee your side is in the draw once it is settled — pay it on the web, or the host will record it."
                        : "Accepting puts your side in the draw. Declining tells them now, while they can still find somebody else."
                )
            }
        }
    }

    private func subtitle(_ invitation: EntryInvitation) -> String {
        var parts = [invitation.hostClubName]
        if let by = invitation.invitedByName { parts.append(by) }
        if let dates = invitation.dates { parts.append(dates) }
        parts.append("as \(invitation.entrantName)")
        // What it costs, before the Accept button rather than after it.
        if let fee = invitation.entryFeeCents, fee > 0 {
            parts.append("£\(String(format: "%.2f", Double(fee) / 100)) to enter")
        }
        return parts.joined(separator: " · ")
    }

    private func answer(_ invitation: EntryInvitation, _ status: EntryStatus) async {
        busy = invitation.id
        error = nil
        defer { busy = nil }
        do {
            _ = try await FishersAPI.respondToEntry(entrantId: invitation.entrantId, status: status)
            await onAnswered()
        } catch {
            self.error = "Could not send that answer. Try again in a moment."
        }
    }
}

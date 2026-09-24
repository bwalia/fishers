import SwiftUI

/// After the match: say how the umpiring went.
///
/// Shown on a finished match. The API decides who may leave one — this only
/// stops asking when no umpire was named, because "no umpires to rate" on
/// every match a club scores without naming one is noise.
///
/// Opens with whatever the player said last time rather than blank: the common
/// reason to come back is to change a three to a four, not to find out you
/// have already voted.
struct RateUmpiresView: View {
    let matchId: UUID

    @State private var umpires: [MatchUmpire] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if loaded && !umpires.isEmpty {
                Section {
                    ForEach(umpires) { umpire in
                        RateOne(matchId: matchId, umpire: umpire) {
                            await load()
                        }
                    }
                } header: {
                    Text("How was the umpiring?")
                } footer: {
                    Text("It goes on their profile, with your name on it. One review each — you can change it later.")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        umpires = (try? await FishersAPI.matchUmpires(matchId: matchId)) ?? []
        loaded = true
    }
}

private struct RateOne: View {
    let matchId: UUID
    let umpire: MatchUmpire
    let onSaved: () async -> Void

    @State private var rating: Int
    @State private var comment: String
    @State private var busy = false
    @State private var error: String?
    @State private var saved = false

    init(matchId: UUID, umpire: MatchUmpire, onSaved: @escaping () async -> Void) {
        self.matchId = matchId
        self.umpire = umpire
        self.onSaved = onSaved
        _rating = State(initialValue: umpire.myRating ?? 0)
        _comment = State(initialValue: umpire.myComment ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FishersTheme.space2) {
            HStack {
                Text(umpire.name).font(FishersTheme.headline)
                Spacer()
                if saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(FishersTheme.caption)
                        .foregroundStyle(FishersTheme.available)
                } else if umpire.myRating != nil {
                    Text("Your review")
                        .font(FishersTheme.caption)
                        .foregroundStyle(.secondary)
                }
            }

            StarPicker(value: $rating) { saved = false }

            TextField("Gave everything, explained the wides…", text: $comment, axis: .vertical)
                .lineLimit(2...4)
                .onChange(of: comment) { _, _ in saved = false }

            HStack {
                Button(umpire.myRating == nil ? "Submit" : "Update") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || rating < 1)

                if umpire.myRating != nil {
                    Button("Remove", role: .destructive) { Task { await remove() } }
                        .disabled(busy)
                }
            }

            if let error {
                Text(error).font(FishersTheme.caption).foregroundStyle(FishersTheme.unavailable)
            }
        }
        .padding(.vertical, 4)
    }

    private func submit() async {
        busy = true
        defer { busy = false }
        do {
            let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await FishersAPI.reviewUmpire(
                matchId: matchId, umpireId: umpire.userId,
                rating: rating, comment: text.isEmpty ? nil : text
            )
            saved = true
            error = nil
            await onSaved()
        } catch {
            self.error = "Could not save that"
        }
    }

    private func remove() async {
        busy = true
        defer { busy = false }
        do {
            try await FishersAPI.withdrawUmpireReview(matchId: matchId, umpireId: umpire.userId)
            rating = 0
            comment = ""
            saved = false
            error = nil
            await onSaved()
        } catch {
            self.error = "Could not remove that"
        }
    }
}

/// Five taps, each its own 44pt target — this is used at the boundary, on a
/// phone, one-handed.
private struct StarPicker: View {
    @Binding var value: Int
    var onChange: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { n in
                Button {
                    value = n
                    onChange()
                } label: {
                    Image(systemName: n <= value ? "star.fill" : "star")
                        .font(.system(size: 22))
                        .foregroundStyle(n <= value ? FishersTheme.accent400 : Color.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(n) out of 5")
                .accessibilityAddTraits(n == value ? .isSelected : [])
            }
            Text(value > 0 ? "\(value) / 5" : "Not rated")
                .font(FishersTheme.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.leading, 6)
        }
        .accessibilityElement(children: .contain)
    }
}

/// The matches waiting on this player's say, wherever they happen to be.
///
/// Sits on the profile, so three Sundays in a row can be cleared in one go
/// rather than each needing its own scorecard to be found again.
struct PendingUmpireReviewsView: View {
    @State private var pending: [PendingUmpireReview] = []

    var body: some View {
        ForEach(pending) { match in
            Section {
                ForEach(match.umpires) { umpire in
                    RateOne(matchId: match.matchId, umpire: umpire) { await load() }
                }
            } header: {
                Text(match.matchTitle)
            } footer: {
                if match.id == pending.first?.id {
                    Text("You played in these. It goes on their profile, with your name on it.")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        // A profile that cannot load this is a profile, not an error screen.
        pending = (try? await FishersAPI.pendingUmpireReviews()) ?? []
    }
}

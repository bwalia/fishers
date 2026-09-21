import SwiftUI

/// The man-of-the-match vote, in the thread where it was announced.
///
/// Both team sheets are on the ballot — a man of the match is quite often the
/// opposition's opening bowler — and anybody in either club may vote, whether
/// they played or watched. The running total stays hidden until you have
/// voted, so nobody is nudged towards whoever is already ahead.
struct ManOfTheMatchCard: View {
    let pollId: UUID
    @StateObject private var store: MotmStore

    init(pollId: UUID) {
        self.pollId = pollId
        _store = StateObject(wrappedValue: MotmStore(pollId: pollId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let view = store.view {
                if view.poll.isOpen {
                    ballot(view)
                } else {
                    result(view)
                }
            } else if store.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            }

            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(FishersTheme.unavailable)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(FishersTheme.raised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(FishersTheme.gold.opacity(0.35), lineWidth: 1)
        )
        .task { await store.load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.circle.fill")
                .foregroundStyle(FishersTheme.gold)
            VStack(alignment: .leading, spacing: 1) {
                Text("Man of the match")
                    .font(.subheadline.weight(.semibold))
                if let view = store.view {
                    Text(view.poll.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let view = store.view {
                Text(view.poll.isOpen ? closingLabel(view.poll.closesAt) : "Closed")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        (view.poll.isOpen ? FishersTheme.available : Color.secondary).opacity(0.16),
                        in: Capsule()
                    )
                    .foregroundStyle(view.poll.isOpen ? FishersTheme.available : .secondary)
            }
        }
    }

    // MARK: Voting

    @ViewBuilder
    private func ballot(_ view: MotmPollView) -> some View {
        if view.canVote {
            Text(view.myVote == nil
                 ? "Who was your man of the match? Tap a name — you can change it until voting closes."
                 : "Your vote is in. Tap another name to change it, or the same one to take it back.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Only the two clubs who played can vote.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        let sheets = view.byHomeAndAway
        VStack(alignment: .leading, spacing: 8) {
            sheet(sheets.home, named: sideName(view, "home"), view: view)
            sheet(sheets.away, named: sideName(view, "away"), view: view)
        }

        HStack {
            Text(votesSoFar(view))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func sheet(_ players: [MotmCandidate], named name: String, view: MotmPollView) -> some View {
        if !players.isEmpty {
            Text(name)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            ForEach(players) { player in
                CandidateRow(
                    player: player,
                    isMine: view.myVote == player.userId,
                    showsTally: view.tallyVisible,
                    isScorersPick: view.scorerAwardUserId == player.userId,
                    enabled: view.canVote && !store.isVoting
                ) {
                    Task { await store.vote(for: player.userId) }
                }
            }
        }
    }

    // MARK: Result

    @ViewBuilder
    private func result(_ view: MotmPollView) -> some View {
        if let winner = view.winner {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(FishersTheme.gold)
                VStack(alignment: .leading, spacing: 1) {
                    Text(winner.displayName)
                        .font(.headline)
                    Text("\(winner.votes) of \(view.totalVotes) \(view.totalVotes == 1 ? "vote" : "votes")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 2)
        } else if !view.tiedAtTheTop.isEmpty {
            // Nobody is recorded as the winner when the vote ties: choosing
            // between two players who drew is a captain's call.
            VStack(alignment: .leading, spacing: 4) {
                Label("A tie", systemImage: "equal.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FishersTheme.maybe)
                Text(view.tiedAtTheTop.map(\.displayName).formatted(.list(type: .and))
                     + " finished level. A captain picks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("Voting closed with nobody voted for.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // The full card, so a closed vote still shows how it went.
        if view.totalVotes > 0 {
            DisclosureGroup("All \(view.totalVotes) \(view.totalVotes == 1 ? "vote" : "votes")") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(view.candidates.filter { $0.votes > 0 }) { player in
                        CandidateRow(
                            player: player,
                            isMine: view.myVote == player.userId,
                            showsTally: true,
                            isScorersPick: view.scorerAwardUserId == player.userId,
                            enabled: false,
                            onTap: {}
                        )
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)
            .tint(FishersTheme.accent)
        }
    }

    // MARK: Labels

    /// "Home"/"Away" unless the poll's title gives the two sides away, which
    /// it does for every fixture created the ordinary way ("X vs Y").
    private func sideName(_ view: MotmPollView, _ side: String) -> String {
        let separators = [" vs ", " v ", " V "]
        for separator in separators {
            let parts = view.poll.title.components(separatedBy: separator)
            if parts.count == 2 {
                return side == "home" ? parts[0] : parts[1]
            }
        }
        return side == "home" ? "Home" : "Away"
    }

    private func closingLabel(_ closesAt: Date) -> String {
        let remaining = closesAt.timeIntervalSinceNow
        guard remaining > 0 else { return "Closing" }
        if remaining < 3600 {
            return "\(max(1, Int(remaining / 60)))m left"
        }
        if remaining < 86_400 {
            return "\(Int(remaining / 3600))h left"
        }
        return "\(Int(remaining / 86_400))d left"
    }

    private func votesSoFar(_ view: MotmPollView) -> String {
        if !view.tallyVisible {
            return "Votes are hidden until you have voted."
        }
        return "\(view.totalVotes) \(view.totalVotes == 1 ? "vote" : "votes") so far."
    }
}

/// One name on the ballot. A row rather than a picker: the whole point is to
/// see everybody who played at once and tap one.
private struct CandidateRow: View {
    let player: MotmCandidate
    let isMine: Bool
    let showsTally: Bool
    let isScorersPick: Bool
    let enabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: isMine ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isMine ? FishersTheme.available : Color.secondary)
                Text(player.displayName)
                    .font(.subheadline)
                    .foregroundStyle(FishersTheme.ink)
                if isScorersPick {
                    // The scorer's own award. Shown so the two are never
                    // mistaken for each other.
                    Image(systemName: "pencil.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(FishersTheme.gold)
                        .accessibilityLabel("The scorer's pick")
                }
                Spacer()
                if showsTally {
                    Text("\(player.votes)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(
            isMine
                ? "\(player.displayName), your vote"
                : "Vote for \(player.displayName)"
        )
    }
}

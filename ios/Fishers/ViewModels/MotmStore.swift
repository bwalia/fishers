import Foundation
import SwiftUI

/// One man-of-the-match vote, as the card in a chat thread sees it.
///
/// Small and per-card rather than one store for the whole app: a thread can
/// carry several finished fixtures' votes at once, and they are independent.
@MainActor
final class MotmStore: ObservableObject {
    @Published private(set) var view: MotmPollView?
    @Published var isLoading = false
    @Published var isVoting = false
    @Published var errorMessage: String?

    private let pollId: UUID

    init(pollId: UUID) {
        self.pollId = pollId
    }

    var candidates: [MotmCandidate] { view?.candidates ?? [] }
    var myVote: UUID? { view?.myVote }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            view = try await FishersAPI.motmPoll(id: pollId)
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.friendlyMessage ?? error.localizedDescription
        }
    }

    /// Tapping the person you already voted for takes the vote back, so a
    /// mis-tap is undone by the same tap that made it.
    func vote(for candidate: UUID) async {
        guard !isVoting else { return }
        isVoting = true
        defer { isVoting = false }
        errorMessage = nil
        do {
            view = myVote == candidate
                ? try await FishersAPI.withdrawManOfTheMatchVote(pollId: pollId)
                : try await FishersAPI.voteForManOfTheMatch(pollId: pollId, candidate: candidate)
        } catch {
            errorMessage = (error as? APIError)?.friendlyMessage ?? error.localizedDescription
        }
    }

    /// Captain or secretary. A 403 here is ordinary — most people cannot
    /// close a vote — so the button is only offered once the server has
    /// said it would work, and a refusal is shown as the sentence it sent.
    func close() async {
        isVoting = true
        defer { isVoting = false }
        errorMessage = nil
        do {
            view = try await FishersAPI.closeManOfTheMatchVote(pollId: pollId)
        } catch {
            errorMessage = (error as? APIError)?.friendlyMessage ?? error.localizedDescription
        }
    }
}

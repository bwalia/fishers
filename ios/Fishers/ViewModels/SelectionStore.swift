import Foundation
import SwiftUI

/// Selection state for one fixture: the board, a proposed squad, and the
/// captain's edits before publishing.
@MainActor
final class SelectionStore: ObservableObject {
    @Published var board: SelectionBoard?
    @Published var proposal: SquadProposal?
    @Published var selected: [UUID] = []
    @Published var reserves: [UUID] = []
    @Published var isLoading = false
    @Published var isThinking = false
    @Published var isPublishing = false
    @Published var errorMessage: String?

    private let eventId: UUID

    init(eventId: UUID) {
        self.eventId = eventId
    }

    var squadSize: Int { board?.requirements.size ?? 11 }
    var isFull: Bool { selected.count >= squadSize }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let board = try await FishersAPI.selectionBoard(eventId: eventId)
            self.board = board
            // Start from whatever is already decided.
            selected = board.candidates.filter { $0.state.isInSquad }.map(\.userId)
            reserves = board.candidates(in: .reserve).map(\.userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deterministic ranking — always available.
    func suggest() async {
        await propose { try await FishersAPI.suggestSquad(eventId: self.eventId) }
    }

    /// Ask the assistant to decide. Falls back to the ranking server-side when
    /// no API key is configured.
    func askAssistant() async {
        isThinking = true
        defer { isThinking = false }
        await propose { try await FishersAPI.agentSquad(eventId: self.eventId) }
    }

    private func propose(_ work: () async throws -> SquadProposal) async {
        errorMessage = nil
        do {
            let proposal = try await work()
            self.proposal = proposal
            selected = proposal.selected.map(\.userId)
            reserves = proposal.reserves.map(\.userId)
            if proposal.published { await load() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ candidate: SelectionCandidate) {
        if let index = selected.firstIndex(of: candidate.userId) {
            selected.remove(at: index)
        } else if let index = reserves.firstIndex(of: candidate.userId) {
            // Reserve → out; tap again from the pool to select.
            reserves.remove(at: index)
        } else if isFull {
            reserves.append(candidate.userId)
        } else {
            selected.append(candidate.userId)
        }
    }

    func role(of candidate: SelectionCandidate) -> SelectionState? {
        if selected.contains(candidate.userId) { return .selected }
        if reserves.contains(candidate.userId) { return .reserve }
        return nil
    }

    func publish() async {
        isPublishing = true
        defer { isPublishing = false }
        do {
            board = try await FishersAPI.setSquad(
                eventId: eventId,
                selected: selected,
                reserves: reserves,
                announcement: proposal?.announcement,
                publish: true
            )
            proposal = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveWithoutPublishing() async {
        do {
            board = try await FishersAPI.setSquad(
                eventId: eventId,
                selected: selected,
                reserves: reserves,
                announcement: nil,
                publish: false
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Rain, unplayable ground, opposition pulled out.
    func updateStatus(_ status: String, note: String?) async {
        do {
            try await FishersAPI.updateFixtureStatus(eventId: eventId, status: status, note: note)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

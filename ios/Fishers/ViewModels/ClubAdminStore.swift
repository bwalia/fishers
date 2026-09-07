import Foundation
import SwiftUI

/// Roster, club policy and outstanding fees for one club.
///
/// Policy edits are debounced: a stepper fires on every tap, and each tap
/// should not be a round trip.
@MainActor
final class ClubAdminStore: ObservableObject {
    @Published var members: [ClubMemberDetail] = []
    @Published var settings: ClubSettings?
    @Published var fees: OutstandingFees?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var isChasing = false
    @Published var errorMessage: String?

    private let clubId: UUID
    private var saveTask: Task<Void, Never>?

    init(clubId: UUID) {
        self.clubId = clubId
    }

    var errorBinding: Binding<Bool> {
        Binding(
            get: { self.errorMessage != nil },
            set: { if !$0 { self.errorMessage = nil } }
        )
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let members = FishersAPI.clubMembers(clubId: clubId)
        async let settings = FishersAPI.clubSettings(clubId: clubId)
        async let fees = FishersAPI.outstandingFees(clubId: clubId)
        self.members = (try? await members) ?? self.members
        self.settings = (try? await settings) ?? self.settings
        // Fees are captain-and-above; a plain member gets a 403 and no section.
        self.fees = try? await fees
    }

    // MARK: Roster

    func add(email: String, role: ClubRole) async {
        do {
            try await FishersAPI.addClubMember(
                clubId: clubId,
                email: email.trimmingCharacters(in: .whitespaces),
                role: role
            )
            await load()
        } catch {
            errorMessage = message(from: error)
        }
    }

    func setRole(member: ClubMemberDetail, role: ClubRole) async {
        // Move it in the list straight away; put it back if the server refuses.
        let previous = members
        if let index = members.firstIndex(where: { $0.id == member.id }) {
            members[index].role = role
        }
        do {
            try await FishersAPI.setMemberRole(
                clubId: clubId, userId: member.userId, role: role
            )
            await load()
        } catch {
            members = previous
            errorMessage = message(from: error)
        }
    }

    func remove(member: ClubMemberDetail) async {
        do {
            try await FishersAPI.removeClubMember(clubId: clubId, userId: member.userId)
            await load()
        } catch {
            errorMessage = message(from: error)
        }
    }

    // MARK: Policy

    /// Apply the change locally, then save once the taps stop.
    func mutateSettings(_ change: (inout ClubSettings) -> Void) {
        guard var current = settings else { return }
        change(&current)
        settings = current

        saveTask?.cancel()
        saveTask = Task { [current] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await save(current)
        }
    }

    private func save(_ settings: ClubSettings) async {
        isSaving = true
        defer { isSaving = false }
        do {
            self.settings = try await FishersAPI.updateClubSettings(clubId: clubId, settings)
        } catch {
            errorMessage = message(from: error)
            self.settings = try? await FishersAPI.clubSettings(clubId: clubId)
        }
    }

    // MARK: Fees

    func chaseFees() async {
        isChasing = true
        defer { isChasing = false }
        do {
            try await FishersAPI.chaseFees(clubId: clubId)
            fees = try? await FishersAPI.outstandingFees(clubId: clubId)
        } catch {
            errorMessage = message(from: error)
        }
    }

    /// The API's own words are more use than "the operation could not be
    /// completed" — it says things like "this is the club's last secretary".
    private func message(from error: Error) -> String {
        guard case let APIError.http(_, body) = error else {
            return error.localizedDescription
        }
        if let data = body.data(using: .utf8),
           let payload = try? JSONDecoder().decode([String: String].self, from: data),
           let reason = payload["error"] {
            return reason
        }
        return error.localizedDescription
    }
}

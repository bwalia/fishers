import Foundation
import SwiftUI

/// Shared active club for the signed-in member — one place for Home, Chat, Shop,
/// and role checks so screens stop inventing their own club picker state.
@MainActor
final class ClubContextStore: ObservableObject {
    @Published private(set) var clubs: [Club] = []
    @Published var activeClubId: UUID? {
        didSet {
            if let id = activeClubId {
                UserDefaults.standard.set(id.uuidString, forKey: Self.defaultsKey)
            }
            Task { await refreshRole() }
        }
    }
    @Published private(set) var roleInfo: ClubRoleInfo?
    @Published private(set) var isLoading = false

    private static let defaultsKey = "fishers_active_club_id"

    var activeClub: Club? {
        clubs.first { $0.id == activeClubId }
    }

    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        clubs = (try? await FishersAPI.clubs()) ?? []
        if let saved = UserDefaults.standard.string(forKey: Self.defaultsKey)
            .flatMap(UUID.init(uuidString:)),
           clubs.contains(where: { $0.id == saved })
        {
            activeClubId = saved
        } else {
            activeClubId = clubs.first?.id
        }
        await refreshRole()
    }

    func select(_ clubId: UUID) {
        guard clubs.contains(where: { $0.id == clubId }) else { return }
        activeClubId = clubId
    }

    func refreshRole() async {
        guard let clubId = activeClubId else {
            roleInfo = nil
            return
        }
        roleInfo = try? await FishersAPI.myClubRole(clubId: clubId)
    }

    func clear() {
        clubs = []
        activeClubId = nil
        roleInfo = nil
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }
}

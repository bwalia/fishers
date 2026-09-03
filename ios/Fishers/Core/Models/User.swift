import Foundation

struct User: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var email: String
    var phone: String?
    var avatarUrl: String?
    var sports: [String]?
    var position: String?
    var skillLevel: String?
    var emergencyContact: String?
    /// Sport the player leads with — drives the profile header and default filters.
    var primarySport: String?
    /// One entry per sport they play, each with its own level, division and stats.
    var sportProfiles: [SportProfile]?
    var location: PlayerLocation?
    /// Computed by the backend from RSVP, attendance and payment history.
    var reliability: ReliabilityScore?

    var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? parts.last?.first.map(String.init) ?? "" : ""
        return first + last
    }

    var profiles: [SportProfile] { sportProfiles ?? [] }

    var primaryProfile: SportProfile? {
        profiles.first { $0.sport == primarySport } ?? profiles.first
    }

    func profile(for sport: Sport) -> SportProfile? {
        profiles.first { $0.sport == sport.rawValue }
    }

    var playedSports: [Sport] {
        profiles.compactMap(\.sportKind)
    }

    /// The gate the app uses to decide whether to run profile setup: a name, at
    /// least one sport, and a stated level for it.
    var isProfileComplete: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let primary = primaryProfile else { return false }
        return primary.isComplete
    }
}

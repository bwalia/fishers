import Foundation

/// Another player, as their club-mates may see them.
///
/// Deliberately narrower than `PublicUser`: no email, no phone number, no
/// emergency contact, no home location. Being in the same club as somebody is
/// not consent to hand over their mobile number, and the server does not send
/// those fields — this type simply has nowhere to put them.
struct TeammateProfile: Decodable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let avatarUrl: String?
    let positionRole: String?
    let skillLevel: String?
    let primarySport: String?
    let sportProfiles: [SportProfile]
    let reliability: ReliabilityScore?
    /// Clubs you and they are both in — the reason you can see this at all,
    /// and the useful thing to know about a name you do not recognise.
    let sharedClubs: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, reliability
        case avatarUrl = "avatar_url"
        case positionRole = "position_role"
        case skillLevel = "skill_level"
        case primarySport = "primary_sport"
        case sportProfiles = "sport_profiles"
        case sharedClubs = "shared_clubs"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        positionRole = try c.decodeIfPresent(String.self, forKey: .positionRole)
        skillLevel = try c.decodeIfPresent(String.self, forKey: .skillLevel)
        primarySport = try c.decodeIfPresent(String.self, forKey: .primarySport)
        sportProfiles = try c.decodeIfPresent([SportProfile].self, forKey: .sportProfiles) ?? []
        reliability = try c.decodeIfPresent(ReliabilityScore.self, forKey: .reliability)
        sharedClubs = try c.decodeIfPresent([String].self, forKey: .sharedClubs) ?? []
    }

    /// The sport they lead with, falling back to whatever they have filled in.
    var mainSport: SportProfile? {
        sportProfiles.first { $0.sport == primarySport } ?? sportProfiles.first
    }
}

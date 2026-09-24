import Foundation

/// Umpiring, as a record a player builds rather than a job on one afternoon.
///
/// Club cricket umpires itself — the batting side gives two, or it is whoever
/// is next in — and the person who does it every week has had nothing to show
/// for it. These are that record.

struct UmpireReview: Codable, Identifiable, Hashable {
    let id: UUID
    let matchId: UUID
    /// One to five.
    let rating: Int
    let comment: String?
    let createdAt: Date
    let reviewerName: String
    let reviewerAvatarUrl: String?
    let matchTitle: String
    let playedOn: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case matchId = "match_id"
        case rating, comment
        case createdAt = "created_at"
        case reviewerName = "reviewer_name"
        case reviewerAvatarUrl = "reviewer_avatar_url"
        case matchTitle = "match_title"
        case playedOn = "played_on"
    }
}

struct UmpireProfile: Codable, Hashable {
    let userId: UUID
    /// Whether they have said they will stand — not the same as having stood.
    let umpires: Bool
    let note: String?
    let matches: Int
    /// `nil` until somebody reviews. Not 0.0, which reads as "rated, badly".
    let ratingAverage: Double?
    let ratingCount: Int
    /// How the ratings fall, one to five.
    let ratingBreakdown: [Int]
    let reviews: [UmpireReview]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case umpires, note, matches, reviews
        case ratingAverage = "rating_average"
        case ratingCount = "rating_count"
        case ratingBreakdown = "rating_breakdown"
    }

    /// "4.3 from 12", or what to say instead before anybody has rated them.
    var ratingLine: String {
        guard let average = ratingAverage, ratingCount > 0 else { return "No ratings yet" }
        return String(format: "%.1f from %d %@", average, ratingCount,
                      ratingCount == 1 ? "review" : "reviews")
    }
}

struct MatchUmpire: Codable, Identifiable, Hashable {
    let userId: UUID
    let name: String
    let avatarUrl: String?
    let myRating: Int?
    let myComment: String?

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case avatarUrl = "avatar_url"
        case myRating = "my_rating"
        case myComment = "my_comment"
    }
}

struct AvailableUmpire: Codable, Identifiable, Hashable {
    let userId: UUID
    let name: String
    let avatarUrl: String?
    let note: String?
    let matches: Int
    let ratingAverage: Double?
    let ratingCount: Int

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name, note, matches
        case avatarUrl = "avatar_url"
        case ratingAverage = "rating_average"
        case ratingCount = "rating_count"
    }
}

/// A finished match whose umpiring this player has not had their say on.
///
/// The prompt at the end of a match only reaches whoever had that screen open.
/// This is the list that finds everybody else.
struct PendingUmpireReview: Codable, Identifiable, Hashable {
    let matchId: UUID
    let matchTitle: String
    let playedOn: Date?
    /// Only the umpires they have not already rated.
    let umpires: [MatchUmpire]

    var id: UUID { matchId }

    enum CodingKeys: String, CodingKey {
        case matchId = "match_id"
        case matchTitle = "match_title"
        case playedOn = "played_on"
        case umpires
    }
}

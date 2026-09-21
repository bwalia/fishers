import Foundation

/// The club's man-of-the-match vote.
///
/// Distinct from the scorer's award, which one person gives from the scoring
/// screen. This one opens on its own when the game ends and everybody in the
/// club votes in it — including the people who watched rather than played,
/// which on most Saturdays is most of the club.
struct MotmPoll: Codable, Identifiable, Equatable {
    let id: UUID
    let clubId: UUID
    let eventId: UUID
    let matchId: UUID?
    let conversationId: UUID?
    let messageId: UUID?
    var title: String
    /// `open` | `closed`
    var status: String
    var closesAt: Date
    var winnerUserId: UUID?
    let createdAt: Date
    var closedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, status
        case clubId = "club_id"
        case eventId = "event_id"
        case matchId = "match_id"
        case conversationId = "conversation_id"
        case messageId = "message_id"
        case closesAt = "closes_at"
        case winnerUserId = "winner_user_id"
        case createdAt = "created_at"
        case closedAt = "closed_at"
    }

    /// The server decides whether a vote counts; this is only for the label.
    /// A poll past its closing time is over whether or not anything has run
    /// the close yet.
    var isOpen: Bool { status == "open" && closesAt > Date() }
}

struct MotmCandidate: Codable, Identifiable, Equatable {
    let userId: UUID
    var displayName: String
    /// `home` | `away`
    var side: String
    var votes: Int

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case side, votes
        case userId = "user_id"
        case displayName = "display_name"
    }
}

/// A poll as this person sees it — the ballot, their vote, and whether they
/// are allowed to see the running total yet.
struct MotmPollView: Codable, Equatable {
    var poll: MotmPoll
    var candidates: [MotmCandidate]
    var myVote: UUID?
    var totalVotes: Int
    /// False until you have voted, so a running tally cannot nudge you
    /// towards whoever is already ahead.
    var tallyVisible: Bool
    var canVote: Bool
    /// What the scorer gave, when they gave one. Shown beside the vote so the
    /// two never look like the same award.
    var scorerAwardUserId: UUID?

    enum CodingKeys: String, CodingKey {
        case candidates
        case myVote = "my_vote"
        case totalVotes = "total_votes"
        case tallyVisible = "tally_visible"
        case canVote = "can_vote"
        case scorerAwardUserId = "scorer_award_user_id"
    }

    /// The poll's own fields are flattened into the same object by the API
    /// (`#[serde(flatten)]`), so they are decoded from the same container
    /// rather than from a nested key.
    init(from decoder: Decoder) throws {
        poll = try MotmPoll(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        candidates = try c.decodeIfPresent([MotmCandidate].self, forKey: .candidates) ?? []
        myVote = try c.decodeIfPresent(UUID.self, forKey: .myVote)
        totalVotes = try c.decodeIfPresent(Int.self, forKey: .totalVotes) ?? 0
        tallyVisible = try c.decodeIfPresent(Bool.self, forKey: .tallyVisible) ?? false
        canVote = try c.decodeIfPresent(Bool.self, forKey: .canVote) ?? false
        scorerAwardUserId = try c.decodeIfPresent(UUID.self, forKey: .scorerAwardUserId)
    }

    func encode(to encoder: Encoder) throws {
        try poll.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(candidates, forKey: .candidates)
        try c.encodeIfPresent(myVote, forKey: .myVote)
        try c.encode(totalVotes, forKey: .totalVotes)
        try c.encode(tallyVisible, forKey: .tallyVisible)
        try c.encode(canVote, forKey: .canVote)
        try c.encodeIfPresent(scorerAwardUserId, forKey: .scorerAwardUserId)
    }

    var winner: MotmCandidate? {
        guard let id = poll.winnerUserId else { return nil }
        return candidates.first { $0.userId == id }
    }

    /// Everybody level at the top once the vote is closed with no winner —
    /// which is how a tie is recorded, because a captain picks between them.
    var tiedAtTheTop: [MotmCandidate] {
        guard !poll.isOpen, poll.winnerUserId == nil, tallyVisible else { return [] }
        guard let best = candidates.map(\.votes).max(), best > 0 else { return [] }
        return candidates.filter { $0.votes == best }
    }

    /// The ballot split into the two team sheets, each in the order the API
    /// sent them — a leaderboard once the tally is out, alphabetical before.
    var byHomeAndAway: (home: [MotmCandidate], away: [MotmCandidate]) {
        (candidates.filter { $0.side == "home" }, candidates.filter { $0.side == "away" })
    }
}

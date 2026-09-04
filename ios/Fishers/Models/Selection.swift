import Foundation

/// Where a player sits in the selection for one fixture.
enum SelectionState: String, Codable, CaseIterable {
    case pool
    case selected
    case reserve
    case notSelected = "not_selected"
    case confirmed
    case declined
    case dropped

    var label: String {
        switch self {
        case .pool: return "Available pool"
        case .selected: return "Selected"
        case .reserve: return "Reserve"
        case .notSelected: return "Not selected"
        case .confirmed: return "Confirmed"
        case .declined: return "Declined"
        case .dropped: return "Dropped"
        }
    }

    var isInSquad: Bool { self == .selected || self == .confirmed }
}

struct SelectionCandidate: Codable, Identifiable, Equatable {
    let userId: UUID
    let name: String
    let position: String?
    let skillLevel: String?
    let availability: AvailabilityStatus?
    let reliabilityScore: Int
    let reliabilityBand: String
    /// Fixtures they were available for but left out of, last 60 days.
    let gamesMissedOut: Int
    let state: SelectionState
    let isConfirmed: Bool

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case name, position, availability, state
        case userId = "user_id"
        case skillLevel = "skill_level"
        case reliabilityScore = "reliability_score"
        case reliabilityBand = "reliability_band"
        case gamesMissedOut = "games_missed_out"
        case isConfirmed = "is_confirmed"
    }
}

struct RankedCandidate: Codable, Identifiable, Equatable {
    let userId: UUID
    let name: String
    let score: Int
    /// Plain-English reasons, in the order the ranking applied them.
    let reasons: [String]

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case name, score, reasons
        case userId = "user_id"
    }
}

struct PositionQuota: Codable, Equatable {
    let position: String
    let minimum: Int
}

struct SquadRequirements: Codable, Equatable {
    let size: Int
    let reserves: Int
    let positionQuotas: [PositionQuota]

    enum CodingKeys: String, CodingKey {
        case size, reserves
        case positionQuotas = "position_quotas"
    }
}

/// Everything the captain's selection screen needs in one call.
struct SelectionBoard: Codable, Equatable {
    let eventId: UUID
    let title: String
    let sport: String
    let startsAt: Date
    let status: String
    let statusNote: String?
    let requirements: SquadRequirements
    /// `off` | `suggest` | `auto_publish`
    let autonomy: String
    let confirmLeadHours: Int
    let dropLeadHours: Int
    let candidates: [SelectionCandidate]
    let ranked: [RankedCandidate]
    let selectedCount: Int
    let confirmedCount: Int

    enum CodingKeys: String, CodingKey {
        case title, sport, status, requirements, autonomy, candidates, ranked
        case eventId = "event_id"
        case startsAt = "starts_at"
        case statusNote = "status_note"
        case confirmLeadHours = "confirm_lead_hours"
        case dropLeadHours = "drop_lead_hours"
        case selectedCount = "selected_count"
        case confirmedCount = "confirmed_count"
    }

    func candidates(in state: SelectionState) -> [SelectionCandidate] {
        candidates.filter { $0.state == state }
    }

    var pool: [SelectionCandidate] {
        // Ranked order, restricted to players not yet decided.
        let undecided = Set(candidates.filter { $0.state == .pool }.map(\.userId))
        return ranked.compactMap { ranked in
            candidates.first { $0.userId == ranked.userId && undecided.contains(ranked.userId) }
        }
    }

    func reasons(for userId: UUID) -> [String] {
        ranked.first { $0.userId == userId }?.reasons ?? []
    }

    var isAssistantAvailable: Bool { autonomy != "off" }
}

/// A squad awaiting publish, from either the ranking or the assistant.
struct SquadProposal: Codable, Equatable {
    /// `ranking` or `assistant`
    let source: String
    let selected: [RankedCandidate]
    let reserves: [RankedCandidate]
    let unmetQuotas: [String]
    let announcement: String?
    let concerns: String?
    let confidence: String?
    let published: Bool

    enum CodingKeys: String, CodingKey {
        case source, selected, reserves, announcement, concerns, confidence, published
        case unmetQuotas = "unmet_quotas"
    }

    var isFromAssistant: Bool { source == "assistant" }
}

struct OutstandingFee: Codable, Identifiable, Equatable {
    let userId: UUID
    let name: String
    let eventId: UUID
    let fixture: String
    let startAt: Date
    let amountCents: Int?
    let currency: String
    let remindersSent: Int

    var id: String { "\(userId)-\(eventId)" }

    enum CodingKeys: String, CodingKey {
        case name, fixture, currency
        case userId = "user_id"
        case eventId = "event_id"
        case startAt = "start_at"
        case amountCents = "amount_cents"
        case remindersSent = "reminders_sent"
    }
}

struct OutstandingFees: Codable, Equatable {
    let totalCents: Int
    let count: Int
    let owed: [OutstandingFee]

    enum CodingKeys: String, CodingKey {
        case count, owed
        case totalCents = "total_cents"
    }
}

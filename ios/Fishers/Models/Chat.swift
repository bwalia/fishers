import Foundation

/// A chat thread. Threads hang off a club, a team or a single fixture.
struct ConversationSummary: Codable, Identifiable, Equatable {
    let id: UUID
    let clubId: UUID?
    let teamId: UUID?
    let eventId: UUID?
    let kind: String
    var title: String
    var updatedAt: Date
    var lastMessageBody: String?
    var lastMessageAt: Date?
    var unreadCount: Int
    /// Agent proposals waiting on a captain's decision.
    var pendingProposals: Int

    enum CodingKeys: String, CodingKey {
        case id, kind, title
        case clubId = "club_id"
        case teamId = "team_id"
        case eventId = "event_id"
        case updatedAt = "updated_at"
        case lastMessageBody = "last_message_body"
        case lastMessageAt = "last_message_at"
        case unreadCount = "unread_count"
        case pendingProposals = "pending_proposals"
    }

    var systemImage: String {
        switch kind {
        case "event": return "calendar"
        case "team": return "person.3.fill"
        case "direct": return "person.fill"
        default: return "bubble.left.and.bubble.right.fill"
        }
    }
}

struct Conversation: Codable, Identifiable, Equatable {
    let id: UUID
    let clubId: UUID?
    let teamId: UUID?
    let eventId: UUID?
    let kind: String
    var title: String

    enum CodingKeys: String, CodingKey {
        case id, kind, title
        case clubId = "club_id"
        case teamId = "team_id"
        case eventId = "event_id"
    }
}

struct ChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let conversationId: UUID
    /// Nil when the assistant wrote it.
    let senderId: UUID?
    let senderName: String?
    /// `text` | `system` | `agent`
    let kind: String
    var body: String
    var metadata: [String: JSONValue]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, body, metadata
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case createdAt = "created_at"
    }

    var isFromAgent: Bool { kind == "agent" }
    var authorLabel: String { senderName ?? "Assistant" }
}

enum ProposalKind: String, Codable {
    case availability
    case squad
    case announcement
    case paymentChase = "payment_chase"

    var label: String {
        switch self {
        case .availability: return "Availability"
        case .squad: return "Squad"
        case .announcement: return "Announcement"
        case .paymentChase: return "Match fees"
        }
    }

    var systemImage: String {
        switch self {
        case .availability: return "calendar.badge.clock"
        case .squad: return "person.3.sequence.fill"
        case .announcement: return "megaphone.fill"
        case .paymentChase: return "sterlingsign.circle.fill"
        }
    }
}

/// Something the assistant thinks needs doing. Applied only by a captain.
struct AgentProposal: Codable, Identifiable, Equatable {
    let id: UUID
    let conversationId: UUID
    let kind: String
    let subjectUserId: UUID?
    let eventId: UUID?
    var payload: ProposalPayload
    var rationale: String
    var confidence: String
    var status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, payload, rationale, confidence, status
        case conversationId = "conversation_id"
        case subjectUserId = "subject_user_id"
        case eventId = "event_id"
        case createdAt = "created_at"
    }

    var proposalKind: ProposalKind? { ProposalKind(rawValue: kind) }
    var isPending: Bool { status == "pending" }
}

struct ProposalPayload: Codable, Equatable {
    var date: String?
    var availabilityStatus: AvailabilityStatus?
    var note: String?
    var userIds: [UUID]?
    var message: String?

    enum CodingKeys: String, CodingKey {
        case date, note, message
        case availabilityStatus = "availability_status"
        case userIds = "user_ids"
    }

    /// One line describing what applying this would do.
    var summary: String {
        if let message { return message }
        if let date, let availabilityStatus {
            return "Set \(availabilityStatus.rawValue) for \(date)"
        }
        if let userIds, !userIds.isEmpty { return "Invite \(userIds.count) players" }
        return "No details"
    }
}

struct AgentRun: Codable, Identifiable, Equatable {
    let id: UUID
    let model: String
    var status: String
    var inputTokens: Int?
    var outputTokens: Int?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case id, model, status, error
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }

    var isDisabled: Bool { status == "disabled" }
}

struct AgentAnalysis: Codable, Equatable {
    var run: AgentRun
    var proposals: [AgentProposal]
    var summary: String?
}

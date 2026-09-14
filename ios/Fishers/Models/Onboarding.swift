import Foundation

/// The two ways into Fishers: one builds a club, the other joins one. Asked
/// once, so the first screens can walk the right path.
enum RoleIntent: String, Codable, CaseIterable, Identifiable {
    case secretary, player

    var id: String { rawValue }

    var title: String {
        switch self {
        case .secretary: return "I run a club"
        case .player: return "I play for a club"
        }
    }

    var detail: String {
        switch self {
        case .secretary:
            return "Secretary or organiser. You set up the club, its teams and fixtures, and bring the players in."
        case .player:
            return "Set up your player profile, send it to your club's secretary, and accept their invite."
        }
    }

    var systemImage: String {
        switch self {
        case .secretary: return "person.3.fill"
        case .player: return "figure.cricket"
        }
    }
}

/// `GET /me/verification`.
struct VerificationStatus: Codable, Equatable {
    struct Channel: Codable, Equatable {
        var address: String?
        var verified: Bool
        /// The server can send a code this way (it has the address, and a
        /// sender configured for it).
        var available: Bool
    }

    /// Whether the server asks for confirmation at all.
    var enabled: Bool
    var email: Channel
    var phone: Channel
    /// Starting a club or accepting an invite is refused until one is verified.
    var verificationRequired: Bool

    enum CodingKeys: String, CodingKey {
        case enabled, email, phone
        case verificationRequired = "verification_required"
    }

    /// The ways a code can actually be sent, email first.
    var channels: [VerificationChannel] {
        VerificationChannel.allCases.filter { self[$0].available }
    }

    subscript(channel: VerificationChannel) -> Channel {
        channel == .email ? email : phone
    }

    /// A step worth showing: the server asks, and can send a code.
    var canVerify: Bool { enabled && !channels.isEmpty }
}

enum VerificationChannel: String, CaseIterable, Identifiable {
    case email, phone

    var id: String { rawValue }
    var noun: String { self == .email ? "email" : "phone number" }
    /// How the code travels, for the sentence under the field.
    var sentVerb: String { self == .email ? "emailed" : "sent on WhatsApp" }
    var systemImage: String { self == .email ? "envelope" : "message" }
}

/// `POST /me/verification/{channel}`.
struct VerificationSent: Codable {
    let sentTo: String
    let resendAfter: Int

    enum CodingKeys: String, CodingKey {
        case sentTo = "sent_to"
        case resendAfter = "resend_after"
    }
}

/// An invitation addressed to this account, from `GET /invites/mine`.
struct PendingInvite: Codable, Identifiable, Equatable {
    let id: UUID
    let targetType: String
    let targetId: UUID
    let token: String
    var status: String
    let createdAt: Date
    /// The club, "team · club", or fixture — present on your own invites.
    var targetName: String?
    var invitedByName: String?

    enum CodingKeys: String, CodingKey {
        case id, token, status
        case targetType = "target_type"
        case targetId = "target_id"
        case createdAt = "created_at"
        case targetName = "target_name"
        case invitedByName = "invited_by_name"
    }

    var isPending: Bool { status == "pending" }

    var title: String {
        targetName ?? "A \(targetType == "event" ? "fixture" : targetType) invitation"
    }

    var systemImage: String { targetType == "event" ? "calendar" : "person.3" }
}

/// `POST /me/share-link`.
struct ShareLinkToken: Codable {
    let token: String
}

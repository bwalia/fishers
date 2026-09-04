import Foundation

enum FishersAPI {
    static func signup(name: String, email: String, password: String) async throws -> AuthTokens {
        struct Body: Encodable { let name, email, password: String }
        return try await NetworkService.shared.request(
            "POST", path: "/auth/signup",
            body: Body(name: name, email: email, password: password),
            authorized: false
        )
    }

    static func login(email: String, password: String) async throws -> AuthTokens {
        struct Body: Encodable { let email, password: String }
        return try await NetworkService.shared.request(
            "POST", path: "/auth/login",
            body: Body(email: email, password: password),
            authorized: false
        )
    }

    static func me() async throws -> PublicUser {
        try await NetworkService.shared.request("GET", path: "/me")
    }

    /// Profile setup and later edits both send the whole profile the app holds.
    static func updateProfile(_ update: ProfileUpdate) async throws -> PublicUser {
        try await NetworkService.shared.request("PATCH", path: "/me", body: update)
    }

    // MARK: Selection

    static func selectionBoard(eventId: UUID) async throws -> SelectionBoard {
        try await NetworkService.shared.request(
            "GET", path: "/events/\(eventId.uuidString)/selection"
        )
    }

    /// Deterministic pick — no model, works with no API key on the server.
    static func suggestSquad(eventId: UUID) async throws -> SquadProposal {
        try await NetworkService.shared.request(
            "POST", path: "/events/\(eventId.uuidString)/selection/suggest"
        )
    }

    /// Let the assistant decide the side.
    static func agentSquad(eventId: UUID) async throws -> SquadProposal {
        try await NetworkService.shared.request(
            "POST", path: "/events/\(eventId.uuidString)/selection/agent"
        )
    }

    static func setSquad(
        eventId: UUID,
        selected: [UUID],
        reserves: [UUID],
        announcement: String? = nil,
        publish: Bool
    ) async throws -> SelectionBoard {
        struct Body: Encodable {
            let selected: [UUID]
            let reserves: [UUID]
            let announcement: String?
            let publish: Bool
        }
        return try await NetworkService.shared.request(
            "POST", path: "/events/\(eventId.uuidString)/selection",
            body: Body(selected: selected, reserves: reserves, announcement: announcement, publish: publish)
        )
    }

    /// The player's reconfirmation, a couple of days out.
    static func respondToSelection(eventId: UUID, confirming: Bool) async throws {
        struct Body: Encodable { let confirming: Bool }
        try await NetworkService.shared.requestVoid(
            "POST", path: "/events/\(eventId.uuidString)/selection/respond",
            body: Body(confirming: confirming)
        )
    }

    /// Rain stops play: change the fixture and tell the squad.
    static func updateFixtureStatus(
        eventId: UUID,
        status: String,
        note: String?,
        rescheduledTo: Date? = nil
    ) async throws {
        struct Body: Encodable {
            let status: String
            let note: String?
            let rescheduled_to: Date?
        }
        try await NetworkService.shared.requestVoid(
            "POST", path: "/events/\(eventId.uuidString)/status",
            body: Body(status: status, note: note, rescheduled_to: rescheduledTo)
        )
    }

    static func outstandingFees(clubId: UUID) async throws -> OutstandingFees {
        try await NetworkService.shared.request(
            "GET", path: "/clubs/\(clubId.uuidString)/fees/outstanding"
        )
    }

    static func chaseFees(clubId: UUID) async throws {
        try await NetworkService.shared.requestVoid(
            "POST", path: "/clubs/\(clubId.uuidString)/fees/chase"
        )
    }

    // MARK: Chat

    static func conversations() async throws -> [ConversationSummary] {
        try await NetworkService.shared.request("GET", path: "/conversations")
    }

    static func createConversation(
        title: String,
        clubId: UUID?,
        teamId: UUID? = nil,
        eventId: UUID? = nil
    ) async throws -> Conversation {
        struct Body: Encodable {
            let title: String
            let club_id: UUID?
            let team_id: UUID?
            let event_id: UUID?
        }
        return try await NetworkService.shared.request(
            "POST", path: "/conversations",
            body: Body(title: title, club_id: clubId, team_id: teamId, event_id: eventId)
        )
    }

    static func messages(conversationId: UUID, limit: Int = 50) async throws -> [ChatMessage] {
        try await NetworkService.shared.request(
            "GET", path: "/conversations/\(conversationId.uuidString)/messages?limit=\(limit)"
        )
    }

    static func postMessage(conversationId: UUID, body: String) async throws -> ChatMessage {
        struct Body: Encodable { let body: String }
        return try await NetworkService.shared.request(
            "POST", path: "/conversations/\(conversationId.uuidString)/messages",
            body: Body(body: body)
        )
    }

    static func markRead(conversationId: UUID) async throws {
        struct Body: Encodable { let read_at: Date? }
        try await NetworkService.shared.requestVoid(
            "POST", path: "/conversations/\(conversationId.uuidString)/read",
            body: Body(read_at: Date())
        )
    }

    static func proposals(conversationId: UUID) async throws -> [AgentProposal] {
        try await NetworkService.shared.request(
            "GET", path: "/conversations/\(conversationId.uuidString)/proposals"
        )
    }

    /// Asks the assistant to read the thread and propose what needs doing.
    static func analyseConversation(_ conversationId: UUID) async throws -> AgentAnalysis {
        try await NetworkService.shared.request(
            "POST", path: "/conversations/\(conversationId.uuidString)/agent/analyse"
        )
    }

    static func applyProposal(_ id: UUID) async throws -> AgentProposal {
        try await NetworkService.shared.request(
            "POST", path: "/agent/proposals/\(id.uuidString)/apply"
        )
    }

    static func dismissProposal(_ id: UUID) async throws -> AgentProposal {
        try await NetworkService.shared.request(
            "POST", path: "/agent/proposals/\(id.uuidString)/dismiss"
        )
    }

    // MARK: Clubs

    static func clubs() async throws -> [Club] {
        try await NetworkService.shared.request("GET", path: "/clubs")
    }

    static func createClub(name: String, sports: [String], informal: Bool = false) async throws -> Club {
        struct Body: Encodable {
            let name: String
            let sport_types: [String]
            let is_informal_group: Bool
            let visibility: String
        }
        return try await NetworkService.shared.request(
            "POST", path: "/clubs",
            body: Body(name: name, sport_types: sports, is_informal_group: informal, visibility: "invite_only")
        )
    }

    static func teams(clubId: UUID) async throws -> [Team] {
        try await NetworkService.shared.request("GET", path: "/clubs/\(clubId.uuidString)/teams")
    }

    static func events(clubId: UUID? = nil, cricketSeason: Bool = false) async throws -> [Event] {
        var path = "/events?"
        if let clubId { path += "club_id=\(clubId.uuidString)&" }
        if cricketSeason { path += "cricket_season=true&" }
        return try await NetworkService.shared.request("GET", path: path)
    }

    static func createEvent(_ body: CreateEventBody) async throws -> Event {
        try await NetworkService.shared.request("POST", path: "/events", body: body)
    }

    static func event(id: UUID) async throws -> Event {
        try await NetworkService.shared.request("GET", path: "/events/\(id.uuidString)")
    }

    static func rsvp(eventId: UUID, status: RsvpStatus) async throws {
        struct Body: Encodable { let status: String }
        try await NetworkService.shared.requestVoid(
            "POST", path: "/events/\(eventId.uuidString)/rsvp",
            body: Body(status: status.rawValue)
        )
    }

    static func attendees(eventId: UUID) async throws -> [AttendeeSummary] {
        try await NetworkService.shared.request("GET", path: "/events/\(eventId.uuidString)/attendees")
    }

    static func availability(from: String, to: String) async throws -> [Availability] {
        try await NetworkService.shared.request(
            "GET", path: "/availability?from=\(from)&to=\(to)"
        )
    }

    static func setAvailability(date: String, status: AvailabilityStatus) async throws -> Availability {
        struct Body: Encodable { let date: String; let status: String }
        return try await NetworkService.shared.request(
            "POST", path: "/availability",
            body: Body(date: date, status: status.rawValue)
        )
    }

    static func products(clubId: UUID) async throws -> [Product] {
        try await NetworkService.shared.request("GET", path: "/clubs/\(clubId.uuidString)/products")
    }

    static func placeOrder(clubId: UUID, eventId: UUID?, items: [(UUID, Int)]) async throws -> Order {
        struct Item: Encodable { let product_id: UUID; let quantity: Int }
        struct Body: Encodable {
            let club_id: UUID
            let event_id: UUID?
            let items: [Item]
        }
        struct Resp: Decodable { let order: Order }
        let resp: Resp = try await NetworkService.shared.request(
            "POST", path: "/orders",
            body: Body(
                club_id: clubId,
                event_id: eventId,
                items: items.map { Item(product_id: $0.0, quantity: $0.1) }
            )
        )
        return resp.order
    }

    static func paymentIntent(eventId: UUID, amountCents: Int) async throws -> PaymentIntentDTO {
        struct Body: Encodable {
            let event_id: UUID
            let amount_cents: Int
            let currency: String
        }
        return try await NetworkService.shared.request(
            "POST", path: "/payments/intent",
            body: Body(event_id: eventId, amount_cents: amountCents, currency: "GBP")
        )
    }
}

struct CreateEventBody: Encodable {
    let club_id: UUID
    let team_id: UUID?
    let sport: String
    let event_subtype: String
    let title: String
    let venue_id: UUID?
    let start_at: Date
    let end_at: Date
    let recurrence_rule: String?
    let capacity: Int?
    let fee_amount_cents: Int?
    let metadata: [String: JSONValue]?
}

struct PaymentIntentDTO: Codable {
    let paymentId: UUID
    let clientSecret: String
    let amountCents: Int
    let currency: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case currency, status
        case paymentId = "payment_id"
        case clientSecret = "client_secret"
        case amountCents = "amount_cents"
    }
}

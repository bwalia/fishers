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

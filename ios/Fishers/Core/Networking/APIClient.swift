import Foundation

/// The full backend surface the app talks to. `APIClient` is the live implementation;
/// `MockAPIClient` backs demo mode and previews.
protocol FishersAPI: AnyObject {
    func me() async throws -> User
    func updateProfile(_ update: ProfileUpdate) async throws -> User

    func clubs() async throws -> [Club]
    func club(id: UUID) async throws -> Club
    func createClub(name: String, sportTypes: [String], visibility: ClubVisibility) async throws -> Club
    func teams(clubId: UUID) async throws -> [Team]
    func members(clubId: UUID) async throws -> [ClubMember]

    func events(clubId: UUID?, teamId: UUID?, from: Date?, to: Date?) async throws -> [Event]
    func event(id: UUID) async throws -> Event
    func rsvp(eventId: UUID, status: RSVPStatus) async throws
    func attendees(eventId: UUID) async throws -> [Attendee]

    func availability(from: String, to: String) async throws -> [Availability]
    func setAvailability(date: String, status: AvailabilityStatus, note: String?) async throws -> Availability

    func invitesMine() async throws -> [EventInvite]
    func respondInvite(id: UUID, status: RSVPStatus) async throws

    func createPaymentIntent(eventId: UUID) async throws -> PaymentIntent

    func products(clubId: UUID?) async throws -> [Product]
    func createOrder(_ request: CreateOrderRequest) async throws -> Order
    func ordersMine() async throws -> [Order]

    func registerDevice(token: String) async throws
}

private struct RSVPRequest: Codable { var status: RSVPStatus }
private struct AvailabilityRequest: Codable {
    var date: String
    var status: AvailabilityStatus
    var note: String?
}
private struct PaymentIntentRequest: Codable { var eventId: UUID }
private struct RegisterDeviceRequest: Codable { var deviceToken: String; var platform: String }
private struct CreateClubRequest: Codable {
    var name: String
    var sportTypes: [String]
    var visibility: ClubVisibility
}
private struct EmptyBody: Codable {}

/// Live URLSession-backed client for the Rust backend, with bearer injection
/// and one automatic refresh + retry on 401.
final class APIClient {
    private let auth: AuthService
    private let session: URLSession

    init(auth: AuthService, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await send(endpoint, allowRefresh: true)
        do {
            return try APICoding.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func requestVoid(_ endpoint: Endpoint) async throws {
        _ = try await send(endpoint, allowRefresh: true)
    }

    private func send(_ endpoint: Endpoint, allowRefresh: Bool) async throws -> Data {
        guard var components = URLComponents(
            url: APIConfig.baseURL.appending(path: APIConfig.apiPrefix + endpoint.path),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidURL }
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.httpBody = endpoint.body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if endpoint.authenticated, let token = auth.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(statusCode: 0, message: nil)
        }

        if http.statusCode == 401, endpoint.authenticated, allowRefresh {
            try await auth.refresh()
            return try await send(endpoint, allowRefresh: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw APIError.unauthorized }
            let message = (try? APICoding.decoder.decode(ServerErrorBody.self, from: data))
                .flatMap { $0.message ?? $0.error }
            throw APIError.server(statusCode: http.statusCode, message: message)
        }
        return data
    }

    private func encode<B: Encodable>(_ body: B) throws -> Data {
        try APICoding.encoder.encode(body)
    }
}

extension APIClient: FishersAPI {
    func me() async throws -> User { try await request(.get("/users/me")) }

    func updateProfile(_ update: ProfileUpdate) async throws -> User {
        try await request(.patch("/users/me", body: encode(update)))
    }

    func clubs() async throws -> [Club] {
        try await request(.get("/clubs"))
    }

    func club(id: UUID) async throws -> Club {
        try await request(.get("/clubs/\(id.uuidString)"))
    }

    func createClub(name: String, sportTypes: [String], visibility: ClubVisibility) async throws -> Club {
        try await request(.post("/clubs", body: encode(CreateClubRequest(name: name, sportTypes: sportTypes, visibility: visibility))))
    }

    func teams(clubId: UUID) async throws -> [Team] {
        try await request(.get("/clubs/\(clubId.uuidString)/teams"))
    }

    func members(clubId: UUID) async throws -> [ClubMember] {
        try await request(.get("/clubs/\(clubId.uuidString)/members"))
    }

    func events(clubId: UUID?, teamId: UUID?, from: Date?, to: Date?) async throws -> [Event] {
        var query: [URLQueryItem] = []
        if let clubId { query.append(URLQueryItem(name: "club_id", value: clubId.uuidString)) }
        if let teamId { query.append(URLQueryItem(name: "team_id", value: teamId.uuidString)) }
        let iso = ISO8601DateFormatter()
        if let from { query.append(URLQueryItem(name: "from", value: iso.string(from: from))) }
        if let to { query.append(URLQueryItem(name: "to", value: iso.string(from: to))) }
        return try await request(.get("/events", query: query))
    }

    func event(id: UUID) async throws -> Event {
        try await request(.get("/events/\(id.uuidString)"))
    }

    func rsvp(eventId: UUID, status: RSVPStatus) async throws {
        try await requestVoid(.post("/events/\(eventId.uuidString)/rsvp", body: encode(RSVPRequest(status: status))))
    }

    func attendees(eventId: UUID) async throws -> [Attendee] {
        try await request(.get("/events/\(eventId.uuidString)/attendees"))
    }

    func availability(from: String, to: String) async throws -> [Availability] {
        try await request(.get("/availability", query: [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
        ]))
    }

    func setAvailability(date: String, status: AvailabilityStatus, note: String?) async throws -> Availability {
        try await request(.post("/availability", body: encode(AvailabilityRequest(date: date, status: status, note: note))))
    }

    func invitesMine() async throws -> [EventInvite] {
        try await request(.get("/invites/mine"))
    }

    func respondInvite(id: UUID, status: RSVPStatus) async throws {
        try await requestVoid(.post("/invites/\(id.uuidString)/respond", body: encode(RSVPRequest(status: status))))
    }

    func createPaymentIntent(eventId: UUID) async throws -> PaymentIntent {
        try await request(.post("/payments/intent", body: encode(PaymentIntentRequest(eventId: eventId))))
    }

    func products(clubId: UUID?) async throws -> [Product] {
        var query: [URLQueryItem] = []
        if let clubId { query.append(URLQueryItem(name: "club_id", value: clubId.uuidString)) }
        return try await request(.get("/products", query: query))
    }

    func createOrder(_ request: CreateOrderRequest) async throws -> Order {
        try await self.request(.post("/orders", body: encode(request)))
    }

    func ordersMine() async throws -> [Order] {
        try await request(.get("/orders/mine"))
    }

    func registerDevice(token: String) async throws {
        try await requestVoid(.post("/notifications/register-device", body: encode(RegisterDeviceRequest(deviceToken: token, platform: "ios"))))
    }
}

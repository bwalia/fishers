import Foundation

enum FishersAPI {
    static func myClubRole(clubId: UUID) async throws -> ClubRoleInfo {
        try await NetworkService.shared.request("GET", path: "/clubs/\(clubId.uuidString)/my-role")
    }

    static func inviteToEvent(eventId: UUID, userId: UUID) async throws {
        struct Body: Encodable { let user_id: UUID }
        try await NetworkService.shared.requestVoid(
            "POST", path: "/events/\(eventId.uuidString)/invite",
            body: Body(user_id: userId)
        )
    }

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

    // MARK: Tournaments

    static func fixtureBlocks(clubId: UUID) async throws -> [FixtureBlock] {
        try await NetworkService.shared.request(
            "GET", path: "/clubs/\(clubId.uuidString)/fixture-blocks"
        )
    }

    static func createTournament(
        name: String,
        clubId: UUID,
        kind: String = "tournament"
    ) async throws -> FixtureBlock {
        struct Body: Encodable {
            let name: String
            let club_id: UUID
            let kind: String
        }
        return try await NetworkService.shared.request(
            "POST", path: "/fixture-blocks",
            body: Body(name: name, club_id: clubId, kind: kind)
        )
    }

    static func entrants(blockId: UUID) async throws -> [TournamentEntrant] {
        try await NetworkService.shared.request(
            "GET", path: "/fixture-blocks/\(blockId.uuidString)/entrants"
        )
    }

    static func addEntrants(blockId: UUID, names: [String]) async throws -> [TournamentEntrant] {
        struct NewEntrant: Encodable { let name: String; let seed: Int? }
        struct Body: Encodable { let entrants: [NewEntrant] }
        let entrants = names.enumerated().map { NewEntrant(name: $1, seed: $0 + 1) }
        return try await NetworkService.shared.request(
            "POST", path: "/fixture-blocks/\(blockId.uuidString)/entrants",
            body: Body(entrants: entrants)
        )
    }

    static func tournamentSchedule(blockId: UUID) async throws -> [ScheduleRow] {
        try await NetworkService.shared.request(
            "GET", path: "/fixture-blocks/\(blockId.uuidString)/schedule"
        )
    }

    static func standings(blockId: UUID) async throws -> [Standing] {
        try await NetworkService.shared.request(
            "GET", path: "/fixture-blocks/\(blockId.uuidString)/standings"
        )
    }

    /// Lay out the grid: one slot per court per round.
    static func generateSlots(
        blockId: UUID,
        courts: [String],
        firstStart: Date,
        matchMinutes: Int,
        gapMinutes: Int,
        rounds: Int
    ) async throws {
        struct Body: Encodable {
            let courts: [String]
            let first_start: Date
            let match_minutes: Int
            let gap_minutes: Int
            let rounds: Int
            let replace: Bool
        }
        try await NetworkService.shared.requestVoid(
            "POST", path: "/fixture-blocks/\(blockId.uuidString)/slots",
            body: Body(
                courts: courts, first_start: firstStart, match_minutes: matchMinutes,
                gap_minutes: gapMinutes, rounds: rounds, replace: true
            )
        )
    }

    /// `commit: false` previews the fixture list without writing it.
    static func generateSchedule(
        blockId: UUID,
        format: TournamentFormat,
        groupCount: Int?,
        commit: Bool
    ) async throws {
        struct Body: Encodable {
            let format: String
            let group_count: Int?
            let commit: Bool
        }
        try await NetworkService.shared.requestVoid(
            "POST", path: "/fixture-blocks/\(blockId.uuidString)/schedule",
            body: Body(format: format.rawValue, group_count: groupCount, commit: commit)
        )
    }

    static func generateKnockout(blockId: UUID, perGroup: Int, commit: Bool) async throws {
        struct Body: Encodable { let per_group: Int; let commit: Bool }
        try await NetworkService.shared.requestVoid(
            "POST", path: "/fixture-blocks/\(blockId.uuidString)/knockout",
            body: Body(per_group: perGroup, commit: commit)
        )
    }

    static func recordResult(
        eventId: UUID,
        entrants: [(entrantId: UUID, score: Int?, result: String)]
    ) async throws {
        struct Line: Encodable { let entrant_id: UUID; let score: Int?; let result: String }
        struct Body: Encodable { let entrants: [Line] }
        try await NetworkService.shared.requestVoid(
            "POST", path: "/events/\(eventId.uuidString)/result",
            body: Body(entrants: entrants.map { Line(entrant_id: $0.entrantId, score: $0.score, result: $0.result) })
        )
    }

    // MARK: Ticketed events

    static func tickets(eventId: UUID) async throws -> TicketBooking {
        try await NetworkService.shared.request(
            "GET", path: "/events/\(eventId.uuidString)/tickets"
        )
    }

    static func bookTicket(
        eventId: UUID,
        guests: Int,
        guestNames: String?,
        notes: String?
    ) async throws -> EventTicket {
        struct Body: Encodable {
            let guests: Int
            let guest_names: String?
            let notes: String?
        }
        return try await NetworkService.shared.request(
            "POST", path: "/events/\(eventId.uuidString)/tickets",
            body: Body(guests: guests, guest_names: guestNames, notes: notes)
        )
    }

    static func payTicket(_ ticketId: UUID) async throws -> EventTicket {
        try await NetworkService.shared.request(
            "POST", path: "/tickets/\(ticketId.uuidString)/pay"
        )
    }

    static func cancelTicket(_ ticketId: UUID) async throws -> EventTicket {
        try await NetworkService.shared.request(
            "POST", path: "/tickets/\(ticketId.uuidString)/cancel"
        )
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

    // MARK: Cricket scoring

    static func createCricketMatch(
        eventId: UUID,
        oversLimit: Int,
        homeName: String,
        awayName: String
    ) async throws -> CricketMatchDTO {
        struct Body: Encodable {
            let overs_limit: Int
            let home_name: String
            let away_name: String
        }
        return try await NetworkService.shared.request(
            "POST", path: "/events/\(eventId.uuidString)/cricket-match",
            body: Body(overs_limit: oversLimit, home_name: homeName, away_name: awayName)
        )
    }

    static func cricketMatchForEvent(eventId: UUID) async throws -> CricketMatchDTO {
        try await NetworkService.shared.request(
            "GET", path: "/events/\(eventId.uuidString)/cricket-match"
        )
    }

    static func cricketMatch(id: UUID) async throws -> CricketMatchDTO {
        try await NetworkService.shared.request("GET", path: "/cricket/matches/\(id.uuidString)")
    }

    static func claimScorer(matchId: UUID, deviceId: String) async throws -> CricketMatchDTO {
        struct Body: Encodable { let device_id: String }
        return try await NetworkService.shared.request(
            "POST", path: "/cricket/matches/\(matchId.uuidString)/claim-scorer",
            body: Body(device_id: deviceId)
        )
    }

    static func postCricketEvents(
        matchId: UUID,
        deviceId: String,
        events: [ScoringEvent]
    ) async throws -> CricketMatchDTO {
        struct Body: Encodable {
            let device_id: String
            let events: [ScoringEvent]
        }
        return try await NetworkService.shared.request(
            "POST", path: "/cricket/matches/\(matchId.uuidString)/events",
            body: Body(device_id: deviceId, events: events)
        )
    }

    static func cricketScorecard(matchId: UUID) async throws -> MatchState {
        try await NetworkService.shared.request(
            "GET", path: "/cricket/matches/\(matchId.uuidString)/scorecard"
        )
    }

    // MARK: Season stats (Play-Cricket)

    static func mySeasonStats(season: Int? = nil) async throws -> MeStatsResponse {
        var path = "/me/stats"
        if let season { path += "?season=\(season)" }
        return try await NetworkService.shared.request("GET", path: path)
    }

    static func clubSeasonBoard(clubId: UUID, season: Int = 2026) async throws -> ClubSeasonBoard {
        try await NetworkService.shared.request(
            "GET", path: "/clubs/\(clubId.uuidString)/stats?season=\(season)"
        )
    }

    static func syncClubStats(clubId: UUID) async throws {
        struct Resp: Decodable {
            let status: String
            let message: String
        }
        let _: Resp = try await NetworkService.shared.request(
            "POST", path: "/clubs/\(clubId.uuidString)/stats/sync"
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

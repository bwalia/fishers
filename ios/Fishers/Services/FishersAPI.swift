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

    /// An address or a mobile number — whichever they actually use. Sending
    /// both as nil is rejected by the API, not silently accepted.
    static func signup(
        name: String,
        email: String?,
        phone: String?,
        password: String
    ) async throws -> AuthTokens {
        struct Body: Encodable {
            let name: String
            let email: String?
            let phone: String?
            let password: String
        }
        return try await NetworkService.shared.request(
            "POST", path: "/auth/signup",
            body: Body(name: name, email: email, phone: phone, password: password),
            authorized: false
        )
    }

    static func login(identifier: String, password: String) async throws -> AuthTokens {
        struct Body: Encodable { let identifier, password: String }
        return try await NetworkService.shared.request(
            "POST", path: "/auth/login",
            body: Body(identifier: identifier, password: password),
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

    // MARK: QR codes and opponents

    static func clubQRCode(clubId: UUID) async throws -> ClubQRCode {
        try await NetworkService.shared.request("GET", path: "/clubs/\(clubId.uuidString)/qr")
    }

    static func teamQRCode(teamId: UUID) async throws -> ClubQRCode {
        try await NetworkService.shared.request("GET", path: "/teams/\(teamId.uuidString)/qr")
    }

    /// Retires the old code immediately.
    static func rotateClubQRCode(clubId: UUID) async throws -> ClubQRCode {
        try await NetworkService.shared.request("POST", path: "/clubs/\(clubId.uuidString)/qr")
    }

    /// Resolve a scanned code — or the whole URL the camera read — to a side.
    static func lookupOpponent(token: String) async throws -> ClubIdentity {
        struct Body: Encodable { let token: String }
        return try await NetworkService.shared.request(
            "POST", path: "/opponents/lookup", body: Body(token: token)
        )
    }

    static func searchOpponents(query: String) async throws -> [ClubIdentity] {
        let escaped = query.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? query
        return try await NetworkService.shared.request(
            "GET", path: "/opponents/search?q=\(escaped)"
        )
    }

    // MARK: Match officials and the scoring lock

    static func matchOfficials(matchId: UUID) async throws -> [MatchOfficialRow] {
        try await NetworkService.shared.request(
            "GET", path: "/cricket/matches/\(matchId.uuidString)/officials"
        )
    }

    /// Appoint an umpire or a scorer. Either may control the scoring.
    static func appointOfficial(
        matchId: UUID,
        userId: UUID,
        role: String
    ) async throws -> [MatchOfficialRow] {
        struct Body: Encodable { let user_id: UUID; let role: String }
        return try await NetworkService.shared.request(
            "POST", path: "/cricket/matches/\(matchId.uuidString)/officials",
            body: Body(user_id: userId, role: role)
        )
    }

    static func removeOfficial(matchId: UUID, userId: UUID) async throws -> [MatchOfficialRow] {
        try await NetworkService.shared.request(
            "DELETE",
            path: "/cricket/matches/\(matchId.uuidString)/officials/\(userId.uuidString)"
        )
    }

    /// Pass the book on. Only the scorer holding it can.
    static func handOverScoring(matchId: UUID, toUserId: UUID) async throws -> CricketMatchDTO {
        struct Body: Encodable { let to_user_id: UUID }
        return try await NetworkService.shared.request(
            "POST", path: "/cricket/matches/\(matchId.uuidString)/handover",
            body: Body(to_user_id: toUserId)
        )
    }

    static func scorerTrail(matchId: UUID) async throws -> [ScorerHandover] {
        try await NetworkService.shared.request(
            "GET", path: "/cricket/matches/\(matchId.uuidString)/scorer-trail"
        )
    }

    /// A line of colour for one ball, written by the model the API is pointed
    /// at. `line` is nil when none is configured or it said something that did
    /// not match the ball — the line the app writes from the log then stands.
    static func commentary(
        matchId: UUID,
        over: Int,
        ballInOver: Int
    ) async throws -> BallCommentary {
        try await NetworkService.shared.request(
            "POST",
            path: "/cricket/matches/\(matchId.uuidString)/commentary",
            body: CommentaryRequest(over: over, ballInOver: ballInOver)
        )
    }

    /// Who each captain has to pick from: the fixture's squad for the home
    /// side, the opposing club's members when they are a Fishers club.
    static func squads(matchId: UUID) async throws -> MatchSquads {
        try await NetworkService.shared.request(
            "GET", path: "/cricket/matches/\(matchId.uuidString)/squad"
        )
    }

    /// The match as the server sees it — including which side this caller
    /// plays for and what they are allowed to act for.
    static func match(matchId: UUID) async throws -> CricketMatchDTO {
        try await NetworkService.shared.request(
            "GET", path: "/cricket/matches/\(matchId.uuidString)"
        )
    }

    /// A captain puts terms on the table, for their *own* side.
    ///
    /// The server refuses a proposal made on behalf of the opposition: that
    /// signed for a club which had not seen the terms and left them nothing to
    /// accept. The opposition is asked, and agrees separately.
    static func proposeTerms(
        matchId: UUID,
        conditions: MatchConditions,
        side: MatchSide,
        captainName: String
    ) async throws -> CricketMatchDTO {
        struct Body: Encodable {
            let conditions: MatchConditions
            let by: String
            let by_name: String
        }
        return try await NetworkService.shared.request(
            "POST", path: "/cricket/matches/\(matchId.uuidString)/propose",
            body: Body(conditions: conditions, by: side.rawValue, by_name: captainName)
        )
    }

    /// Rain, bad light, ground unfit. The scorecard survives and the match
    /// goes down as no result — which is not the same as deleting it.
    static func abandonMatch(matchId: UUID, reason: String) async throws -> CricketMatchDTO {
        struct Body: Encodable { let reason: String }
        return try await NetworkService.shared.request(
            "POST", path: "/cricket/matches/\(matchId.uuidString)/abandon",
            body: Body(reason: reason)
        )
    }

    /// Only a match nobody has scored a ball in — that one was a mistake.
    static func deleteMatch(matchId: UUID) async throws {
        try await NetworkService.shared.requestVoid(
            "DELETE", path: "/cricket/matches/\(matchId.uuidString)"
        )
    }

    /// A captain accepts the terms. A separate door from the scoring lock, so
    /// the visiting captain can agree from their own phone — they will never
    /// have scoring rights in the home club.
    static func agreeTerms(
        matchId: UUID,
        side: MatchSide,
        captainName: String
    ) async throws {
        struct Body: Encodable {
            let side: String
            let captain_name: String
        }
        try await NetworkService.shared.requestVoid(
            "POST", path: "/cricket/matches/\(matchId.uuidString)/agree",
            body: Body(side: side.rawValue, captain_name: captainName)
        )
    }

    // MARK: Notifications

    /// What is waiting for you. Push is still an APNs stub, so reading these
    /// back on open is the only delivery that actually works.
    /// One page of notifications, filtered server-side.
    ///
    /// The filtering and paging happen in the database: a club generates
    /// thousands of these over a season, and pulling the lot down to a phone
    /// to slice twenty out of them is exactly what a mobile connection is
    /// worst at.
    static func notifications(
        page: Int = 1,
        perPage: Int = 20,
        kind: String? = nil,
        unreadOnly: Bool = false,
        search: String? = nil
    ) async throws -> NotificationFeed {
        var query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        if let kind, !kind.isEmpty { query.append(.init(name: "kind", value: kind)) }
        if unreadOnly { query.append(.init(name: "unread", value: "true")) }
        // The server refuses one character; asking is a wasted round trip.
        if let search, search.trimmingCharacters(in: .whitespaces).count >= 2 {
            query.append(.init(name: "q", value: search.trimmingCharacters(in: .whitespaces)))
        }
        var components = URLComponents()
        components.queryItems = query
        let suffix = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return try await NetworkService.shared.request("GET", path: "/notifications\(suffix)")
    }

    /// Another player, as their club-mates may see them. No contact details:
    /// the server does not send them, on purpose.
    static func teammate(_ userId: UUID) async throws -> TeammateProfile {
        try await NetworkService.shared.request("GET", path: "/users/\(userId.uuidString)")
    }

    static func playerSeasons(_ userId: UUID) async throws -> [PlayerSeasonStats] {
        try await NetworkService.shared.request(
            "GET", path: "/users/\(userId.uuidString)/stats"
        )
    }

    static func playerAchievements(_ userId: UUID) async throws -> [UserAchievement] {
        try await NetworkService.shared.request(
            "GET", path: "/users/\(userId.uuidString)/achievements"
        )
    }

    /// One notification, or every unread one when `id` is nil.
    static func markNotificationRead(id: UUID?) async throws {
        struct Body: Encodable { let id: UUID? }
        try await NetworkService.shared.requestVoid(
            "POST", path: "/notifications/read", body: Body(id: id)
        )
    }

    /// Name one side. A separate door from the scoring log: a captain does this
    /// from their own phone without taking the book off whoever is scoring.
    static func submitXi(
        matchId: UUID,
        side: MatchSide,
        players: [MatchPlayer],
        captainId: UUID?,
        keeperId: UUID?
    ) async throws -> CricketMatchDTO {
        try await NetworkService.shared.request(
            "POST",
            path: "/cricket/matches/\(matchId.uuidString)/xi",
            body: XiRequest(
                side: side, players: players,
                captainId: captainId, keeperId: keeperId
            )
        )
    }

    private struct XiRequest: Encodable {
        let side: MatchSide
        let players: [MatchPlayer]
        let captainId: UUID?
        let keeperId: UUID?

        enum CodingKeys: String, CodingKey {
            case side, players
            case captainId = "captain_id"
            case keeperId = "keeper_id"
        }
    }

    private struct CommentaryRequest: Encodable {
        let over: Int
        let ballInOver: Int

        enum CodingKeys: String, CodingKey {
            case over
            case ballInOver = "ball_in_over"
        }
    }

    // MARK: Club administration

    /// The roster, with names and roles. Any member may read it; only a
    /// secretary may change it.
    static func clubMembers(clubId: UUID) async throws -> [ClubMemberDetail] {
        try await NetworkService.shared.request(
            "GET", path: "/clubs/\(clubId.uuidString)/members"
        )
    }

    /// Add someone already on Fishers to the club, by whatever they signed up
    /// with — an email address or a mobile number.
    static func addClubMember(
        clubId: UUID,
        identifier: String,
        role: ClubRole
    ) async throws {
        struct Body: Encodable {
            let identifier: String
            let role: String
        }
        try await NetworkService.shared.requestVoid(
            "POST", path: "/clubs/\(clubId.uuidString)/members",
            body: Body(identifier: identifier, role: role.rawValue)
        )
    }

    /// A link for somebody with no account yet: they follow it, sign up, and
    /// land in the club. Sending it is the secretary's job — share sheet,
    /// WhatsApp, however they already talk to their players.
    static func createClubInvite(clubId: UUID, email: String?) async throws -> ClubInvite {
        struct Body: Encodable {
            let target_type = "club"
            let target_id: UUID
            let invited_email: String?
        }
        return try await NetworkService.shared.request(
            "POST", path: "/invites",
            body: Body(target_id: clubId, invited_email: email)
        )
    }

    static func acceptInvite(token: String) async throws -> ClubInvite {
        try await NetworkService.shared.request(
            "POST", path: "/invites/\(token)/accept"
        )
    }

    /// Appoint a captain or vice captain, or stand someone down.
    static func setMemberRole(clubId: UUID, userId: UUID, role: ClubRole) async throws {
        struct Body: Encodable { let role: String }
        try await NetworkService.shared.requestVoid(
            "PATCH",
            path: "/clubs/\(clubId.uuidString)/members/\(userId.uuidString)",
            body: Body(role: role.rawValue)
        )
    }

    static func removeClubMember(clubId: UUID, userId: UUID) async throws {
        try await NetworkService.shared.requestVoid(
            "DELETE", path: "/clubs/\(clubId.uuidString)/members/\(userId.uuidString)"
        )
    }

    static func clubSettings(clubId: UUID) async throws -> ClubSettings {
        try await NetworkService.shared.request(
            "GET", path: "/clubs/\(clubId.uuidString)/settings"
        )
    }

    static func updateClubSettings(
        clubId: UUID,
        _ settings: ClubSettings
    ) async throws -> ClubSettings {
        try await NetworkService.shared.request(
            "PATCH", path: "/clubs/\(clubId.uuidString)/settings", body: settings
        )
    }

    // MARK: Clubs

    static func clubs() async throws -> [Club] {
        try await NetworkService.shared.request("GET", path: "/clubs")
    }

    static func createClub(
        name: String,
        sports: [String],
        informal: Bool = false,
        visibility: String = "invite_only",
        description: String? = nil
    ) async throws -> Club {
        struct Body: Encodable {
            let name: String
            let sport_types: [String]
            let is_informal_group: Bool
            let visibility: String
            let description: String?
        }
        return try await NetworkService.shared.request(
            "POST", path: "/clubs",
            body: Body(
                name: name,
                sport_types: sports,
                is_informal_group: informal,
                visibility: visibility,
                description: description
            )
        )
    }

    static func createTeam(clubId: UUID, name: String, sport: String) async throws -> Team {
        struct Body: Encodable {
            let name: String
            let sport: String
        }
        return try await NetworkService.shared.request(
            "POST", path: "/clubs/\(clubId.uuidString)/teams",
            body: Body(name: name, sport: sport)
        )
    }

    static func teams(clubId: UUID) async throws -> [Team] {
        try await NetworkService.shared.request("GET", path: "/clubs/\(clubId.uuidString)/teams")
    }

    /// `GET /events` pages now, so the array has to be unwrapped. The app asks
    /// for a big first page rather than paging: a season's fixtures on one
    /// screen is what a phone shows, and 200 is the server's ceiling anyway.
    static func events(
        clubId: UUID? = nil,
        cricketSeason: Bool = false,
        page: Int = 1,
        perPage: Int = 200
    ) async throws -> [Event] {
        try await eventPage(
            clubId: clubId, cricketSeason: cricketSeason, page: page, perPage: perPage
        ).items
    }

    static func eventPage(
        clubId: UUID? = nil,
        cricketSeason: Bool = false,
        page: Int = 1,
        perPage: Int = 200
    ) async throws -> APIPage<Event> {
        var path = "/events?page=\(page)&per_page=\(perPage)&"
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

    /// `matchId` is chosen on the device, so a match started with no signal
    /// registers under the id its local event log already uses.
    static func createCricketMatch(
        eventId: UUID,
        matchId: UUID? = nil,
        oversLimit: Int,
        homeName: String,
        awayName: String
    ) async throws -> CricketMatchDTO {
        struct Body: Encodable {
            let match_id: UUID?
            let overs_limit: Int
            let home_name: String
            let away_name: String
        }
        return try await NetworkService.shared.request(
            "POST", path: "/events/\(eventId.uuidString)/cricket-match",
            body: Body(
                match_id: matchId, overs_limit: oversLimit,
                home_name: homeName, away_name: awayName
            )
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

    /// Fixtures with their match state already joined on — score, status and
    /// result in the row.
    ///
    /// One request answers "what is happening right now", which the alternative
    /// could not: asking `/events` and then `/events/{id}/cricket-match` for
    /// every cricket fixture is a request per fixture, on a phone, at a ground.
    /// `state` is `live`, `upcoming` or `finished`.
    static func cricketFixtures(
        clubId: UUID? = nil,
        state: String? = nil,
        page: Int = 1,
        perPage: Int = 20
    ) async throws -> APIPage<CricketFixtureRow> {
        var path = "/cricket/fixtures?page=\(page)&per_page=\(perPage)&"
        if let clubId { path += "club_id=\(clubId.uuidString)&" }
        if let state { path += "state=\(state)&" }
        return try await NetworkService.shared.request("GET", path: path)
    }

    /// `force` takes the match off a scorer whose phone has died mid-innings.
    static func claimScorer(
        matchId: UUID,
        deviceId: String,
        force: Bool = false
    ) async throws -> CricketMatchDTO {
        struct Body: Encodable { let device_id: String; let force: Bool }
        return try await NetworkService.shared.request(
            "POST", path: "/cricket/matches/\(matchId.uuidString)/claim-scorer",
            body: Body(device_id: deviceId, force: force)
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

    /// Mint a secure live scoreboard link. Pass `postToChat: true` to also drop
    /// it into club chat; external WhatsApp/Mail shares usually leave it false.
    static func shareScoreboard(matchId: UUID, postToChat: Bool = false) async throws -> ScoreboardShareResponse {
        struct Body: Encodable {
            let post_to_chat: Bool
            let ttl_hours: Int
        }
        return try await NetworkService.shared.request(
            "POST",
            path: "/cricket/matches/\(matchId.uuidString)/share",
            body: Body(post_to_chat: postToChat, ttl_hours: 48)
        )
    }

    // MARK: Profile picture

    /// The server sniffs the real bytes and rejects anything that is not a
    /// JPEG, PNG or WebP, so the mime type sent here is a hint, not a claim
    /// it will be believed on.
    static func uploadAvatar(_ data: Data, mimeType: String = "image/jpeg") async throws -> PublicUser {
        try await NetworkService.shared.upload(
            path: "/me/avatar",
            fileName: "avatar.\(mimeType.hasSuffix("png") ? "png" : "jpg")",
            mimeType: mimeType,
            data: data
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

import Foundation

/// In-memory implementation of `FishersAPI` backing demo mode and previews.
/// State mutates so RSVPs, availability taps, payments and orders feel real.
final class MockAPIClient: FishersAPI {
    /// Rolling counters the reliability score is derived from. The live backend
    /// keeps the equivalent history in Postgres.
    private struct History {
        var invites = 18
        var responded = 17
        var saidGoing = 14
        var turnedUp = 13
        var lateCancellations = 1
        var feesDue = 12
        var feesPaid = 11
    }

    private var profile: User
    private var history = History()
    private var availabilityByDay: [String: Availability] = [:]
    private var attendeesByEvent: [UUID: [Attendee]] = [:]
    private var paidEventIds: Set<UUID> = []
    private var invites: [EventInvite] = []
    private var orders: [Order] = []
    private var eventsCache: [Event] = MockData.events

    /// `profile` is whatever the demo session has saved so far — a bare account
    /// on first launch, so the app opens straight into profile setup.
    init(profile: User = MockData.currentUser) {
        self.profile = profile
        seed()
        refreshReliability()
    }

    private func seed() {
        let calendar = Calendar.current
        let me = profile

        // Mark the user available for the next few Wednesdays, maybe on one Sunday.
        for event in eventsCache.prefix(20) where event.startAt > Date() {
            let key = event.dayKey
            if availabilityByDay[key] == nil, event.eventSubtype == .nets {
                availabilityByDay[key] = Availability(
                    id: UUID(), userId: me.id, date: key, status: .available, note: nil, recurrenceRule: nil
                )
            }
        }

        // Seed attendees for upcoming events: most of the squad going to nets, mixed for matches.
        for event in eventsCache where event.startAt > Date() {
            var list: [Attendee] = []
            for (index, player) in MockData.squad.enumerated() {
                let status: RSVPStatus
                switch (event.eventSubtype, index % 5) {
                case (.nets, 0), (.nets, 1), (.nets, 2): status = .going
                case (.nets, 3): status = .maybe
                case (.nets, _): status = .notGoing
                case (_, 0), (_, 1): status = .going
                case (_, 2): status = .maybe
                default: status = .notGoing
                }
                if player.id == me.id { continue } // the user RSVPs themselves
                list.append(Attendee(user: player, status: status, hasPaid: status == .going && index % 3 == 0))
            }
            attendeesByEvent[event.id] = list
        }

        // A pending invite to the friendly from the club admin.
        if let friendly = eventsCache.first(where: { $0.eventSubtype == .friendly && $0.startAt > Date() }) {
            invites.append(EventInvite(
                id: UUID(uuidString: "60000000-0000-0000-0000-000000000001")!,
                eventId: friendly.id,
                userId: me.id,
                invitedBy: MockData.squad[1].id,
                status: .pending,
                respondedAt: nil,
                event: friendly,
                inviter: MockData.squad[1]
            ))
        }
        if let league = eventsCache.first(where: { $0.eventSubtype == .leagueMatch && $0.startAt > Date() }) {
            invites.append(EventInvite(
                id: UUID(uuidString: "60000000-0000-0000-0000-000000000002")!,
                eventId: league.id,
                userId: me.id,
                invitedBy: MockData.squad[3].id,
                status: .pending,
                respondedAt: nil,
                event: league,
                inviter: MockData.squad[3]
            ))
        }

        // RSVP the user to the next nets session so Home shows an unpaid fee.
        if let nets = eventsCache.first(where: { $0.eventSubtype == .nets && $0.startAt > Date() }) {
            var list = attendeesByEvent[nets.id] ?? []
            list.insert(Attendee(user: me, status: .going, hasPaid: false), at: 0)
            attendeesByEvent[nets.id] = list
        }

        _ = calendar // silence unused warning if seeding logic changes
    }

    private func pause() async {
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    private func refreshReliability() {
        profile.reliability = ReliabilityScore.compute(
            invitesReceived: history.invites,
            responded: history.responded,
            saidGoing: history.saidGoing,
            turnedUp: history.turnedUp,
            lateCancellations: history.lateCancellations,
            feesDue: history.feesDue,
            feesPaid: history.feesPaid
        )
    }

    // MARK: Profile

    func me() async throws -> User {
        await pause()
        return profile
    }

    func updateProfile(_ update: ProfileUpdate) async throws -> User {
        await pause()
        profile.name = update.name
        profile.phone = update.phone
        profile.avatarUrl = update.avatarUrl
        profile.emergencyContact = update.emergencyContact
        profile.primarySport = update.primarySport
        profile.sports = update.sports
        profile.position = update.position
        profile.skillLevel = update.skillLevel
        profile.sportProfiles = update.sportProfiles
        profile.location = update.location
        // Reliability is earned, never submitted — recompute rather than accept it.
        refreshReliability()
        return profile
    }

    // MARK: Clubs

    func clubs() async throws -> [Club] {
        await pause()
        return MockData.clubs
    }

    func club(id: UUID) async throws -> Club {
        await pause()
        guard let club = MockData.clubs.first(where: { $0.id == id }) else {
            throw APIError.server(statusCode: 404, message: "Club not found")
        }
        return club
    }

    func createClub(name: String, sportTypes: [String], visibility: ClubVisibility) async throws -> Club {
        await pause()
        return Club(id: UUID(), name: name, sportTypes: sportTypes, visibility: visibility, ownerId: MockData.currentUserId, createdAt: Date())
    }

    func teams(clubId: UUID) async throws -> [Team] {
        await pause()
        return MockData.teams.filter { $0.clubId == clubId }
    }

    func members(clubId: UUID) async throws -> [ClubMember] {
        await pause()
        return clubId == MockData.clubId ? MockData.members : Array(MockData.members.prefix(4))
    }

    // MARK: Events

    func events(clubId: UUID?, teamId: UUID?, from: Date?, to: Date?) async throws -> [Event] {
        await pause()
        return eventsCache.filter { event in
            if let clubId, event.clubId != clubId { return false }
            if let teamId, event.teamId != teamId { return false }
            if let from, event.endAt < from { return false }
            if let to, event.startAt > to { return false }
            return true
        }
    }

    func event(id: UUID) async throws -> Event {
        await pause()
        guard let event = eventsCache.first(where: { $0.id == id }) else {
            throw APIError.server(statusCode: 404, message: "Event not found")
        }
        return event
    }

    func rsvp(eventId: UUID, status: RSVPStatus) async throws {
        await pause()
        var list = attendeesByEvent[eventId] ?? []
        list.removeAll { $0.user.id == MockData.currentUserId }
        list.insert(Attendee(user: profile, status: status, hasPaid: paidEventIds.contains(eventId)), at: 0)
        attendeesByEvent[eventId] = list
        if status == .going {
            history.saidGoing += 1
            history.turnedUp += 1
        }
        refreshReliability()
    }

    func attendees(eventId: UUID) async throws -> [Attendee] {
        await pause()
        return attendeesByEvent[eventId] ?? []
    }

    // MARK: Availability

    func availability(from: String, to: String) async throws -> [Availability] {
        await pause()
        return availabilityByDay.values.filter { $0.date >= from && $0.date <= to }
    }

    func setAvailability(date: String, status: AvailabilityStatus, note: String?) async throws -> Availability {
        await pause()
        let entry = Availability(
            id: availabilityByDay[date]?.id ?? UUID(),
            userId: MockData.currentUserId,
            date: date,
            status: status,
            note: note,
            recurrenceRule: nil
        )
        availabilityByDay[date] = entry
        return entry
    }

    // MARK: Invites

    func invitesMine() async throws -> [EventInvite] {
        await pause()
        return invites
    }

    func respondInvite(id: UUID, status: RSVPStatus) async throws {
        await pause()
        guard let index = invites.firstIndex(where: { $0.id == id }) else { return }
        invites[index].status = InviteStatus(rawValue: status.rawValue) ?? .pending
        invites[index].respondedAt = Date()
        history.responded += 1
        try await rsvp(eventId: invites[index].eventId, status: status)
    }

    // MARK: Payments

    func createPaymentIntent(eventId: UUID) async throws -> PaymentIntent {
        await pause()
        let event = try await event(id: eventId)
        paidEventIds.insert(eventId)
        if var list = attendeesByEvent[eventId],
           let index = list.firstIndex(where: { $0.user.id == MockData.currentUserId }) {
            list[index].hasPaid = true
            attendeesByEvent[eventId] = list
        }
        history.feesDue += 1
        history.feesPaid += 1
        refreshReliability()
        return PaymentIntent(
            paymentId: UUID(),
            clientSecret: "pi_mock_secret",
            amount: event.feeAmount ?? 0,
            currency: event.currency ?? "GBP"
        )
    }

    // MARK: Shop

    func products(clubId: UUID?) async throws -> [Product] {
        await pause()
        if let clubId { return MockData.products.filter { $0.clubId == clubId } }
        return MockData.products
    }

    func createOrder(_ request: CreateOrderRequest) async throws -> Order {
        await pause()
        let items: [OrderItem] = request.items.compactMap { item in
            guard let product = MockData.products.first(where: { $0.id == item.productId }) else { return nil }
            return OrderItem(productId: product.id, quantity: item.quantity, unitPrice: product.price, product: product)
        }
        let total = items.reduce(0) { $0 + $1.unitPrice * $1.quantity }
        let order = Order(
            id: UUID(),
            userId: MockData.currentUserId,
            eventId: request.eventId,
            status: .confirmed,
            totalAmount: total,
            currency: "GBP",
            note: request.note,
            createdAt: Date(),
            items: items
        )
        orders.insert(order, at: 0)
        return order
    }

    func ordersMine() async throws -> [Order] {
        await pause()
        return orders
    }

    // MARK: Notifications

    func registerDevice(token: String) async throws {
        await pause()
    }
}

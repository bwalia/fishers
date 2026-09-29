import Foundation

struct PublicUser: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    /// Absent for somebody who registered with a mobile number instead.
    var email: String?
    var phone: String?
    var avatarUrl: String?
    var sportsPlayed: [String]
    /// Position and standard of the primary sport, flattened for list views.
    var positionRole: String?
    var skillLevel: String?
    var emergencyContact: String?
    /// Sport the player leads with — the rest of the profile hangs off it.
    var primarySport: String?
    /// One entry per sport played, each with its own level, league and stats.
    var sportProfiles: [SportProfile]?
    var location: PlayerLocation?
    /// Server's view of whether first-run profile setup is done.
    var profileComplete: Bool?
    /// Computed by the API from attendance and payment history.
    var reliability: ReliabilityScore?
    /// Whether the address or number has been confirmed with a code. Starting a
    /// club and accepting an invite wait on one of them.
    var emailVerified: Bool?
    var phoneVerified: Bool?
    /// "secretary" or "player" — what they said they came to do. Absent until
    /// they have been asked.
    var roleIntent: String?

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, location, reliability
        case avatarUrl = "avatar_url"
        case sportsPlayed = "sports_played"
        case positionRole = "position_role"
        case skillLevel = "skill_level"
        case emergencyContact = "emergency_contact"
        case primarySport = "primary_sport"
        case sportProfiles = "sport_profiles"
        case profileComplete = "profile_complete"
        case emailVerified = "email_verified"
        case phoneVerified = "phone_verified"
        case roleIntent = "role_intent"
    }

    var isVerified: Bool { emailVerified == true || phoneVerified == true }

    var intent: RoleIntent? { roleIntent.flatMap(RoleIntent.init(rawValue:)) }

    var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? parts.last?.first.map(String.init) ?? "" : ""
        return first + last
    }

    var profiles: [SportProfile] { sportProfiles ?? [] }

    var primaryProfile: SportProfile? {
        profiles.first { $0.sport == primarySport } ?? profiles.first
    }

    func profile(for sport: Sport) -> SportProfile? {
        profiles.first { $0.sport == sport.rawValue }
    }

    var playedSports: [Sport] { profiles.compactMap(\.sportKind) }
}

struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let user: PublicUser

    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

/// Google / Apple sign-in response — same tokens, plus whether the account is new.
struct SocialSignedIn: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let user: PublicUser
    let created: Bool

    var tokens: AuthTokens {
        AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresIn: expiresIn,
            user: user
        )
    }

    enum CodingKeys: String, CodingKey {
        case user, created
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

struct Club: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var sportTypes: [String]
    var visibility: String
    var ownerId: UUID
    var description: String?
    var isInformalGroup: Bool
    /// What you are in this club. Only `GET /clubs` fills it in — a club
    /// fetched on its own says nothing about the reader.
    var role: ClubRole?

    enum CodingKeys: String, CodingKey {
        case id, name, visibility, description, role
        case sportTypes = "sport_types"
        case ownerId = "owner_id"
        case isInformalGroup = "is_informal_group"
    }
}

struct Team: Codable, Identifiable, Hashable {
    let id: UUID
    let clubId: UUID
    let sport: String
    var name: String

    enum CodingKeys: String, CodingKey {
        case id, sport, name
        case clubId = "club_id"
    }
}

struct Venue: Codable, Identifiable {
    let id: UUID
    let clubId: UUID
    var name: String
    var address: String?
    var lat: Double?
    var lng: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, address, lat, lng
        case clubId = "club_id"
    }
}

enum EventSubtype: String, Codable, CaseIterable {
    case nets, friendly, leagueMatch = "league_match"
    case tournament, social, training, generic
}

struct Event: Codable, Identifiable, Hashable {
    let id: UUID
    let clubId: UUID
    var teamId: UUID?
    var sport: String
    var eventSubtype: String
    var title: String
    var venueId: UUID?
    var startAt: Date
    var endAt: Date
    var capacity: Int?
    var feeAmountCents: Int?
    var feeCurrency: String
    var status: String
    var metadata: [String: JSONValue]?
    /// Set on a ticketed event — a dinner, a quiz, presentation night.
    var ticketPriceCents: Int?
    var opponentClubId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, sport, title, capacity, status, metadata
        case clubId = "club_id"
        case teamId = "team_id"
        case eventSubtype = "event_subtype"
        case venueId = "venue_id"
        case startAt = "start_at"
        case endAt = "end_at"
        case feeAmountCents = "fee_amount_cents"
        case feeCurrency = "fee_currency"
        case ticketPriceCents = "ticket_price_cents"
        case opponentClubId = "opponent_club_id"
    }
}

enum AvailabilityStatus: String, Codable, CaseIterable {
    case available, unavailable, maybe

    var colorName: String {
        switch self {
        case .available: return "available"
        case .unavailable: return "unavailable"
        case .maybe: return "maybe"
        }
    }

    var label: String {
        switch self {
        case .available: return "Available"
        case .unavailable: return "Unavailable"
        case .maybe: return "Maybe"
        }
    }

    func next() -> AvailabilityStatus {
        switch self {
        case .available: return .maybe
        case .maybe: return .unavailable
        case .unavailable: return .available
        }
    }
}

struct Availability: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let date: String
    var status: AvailabilityStatus
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id, date, status, note
        case userId = "user_id"
    }
}

enum RsvpStatus: String, Codable {
    case going, notGoing = "not_going", maybe, invited
}

struct AttendeeSummary: Codable, Identifiable {
    var id: UUID { userId }
    let userId: UUID
    let name: String
    let status: RsvpStatus
    let availability: AvailabilityStatus?
    let paid: Bool

    enum CodingKeys: String, CodingKey {
        case name, status, availability, paid
        case userId = "user_id"
    }
}

struct Product: Codable, Identifiable, Hashable {
    let id: UUID
    let clubId: UUID
    var name: String
    var description: String?
    var priceCents: Int
    var currency: String
    var category: String
    /// `nil` is "on request" — made to order, or a tea urn that does not run
    /// out. A second-hand item is almost always 1.
    var stock: Int?
    /// "new" or "used". Absent for the things it does not apply to: a cup of
    /// tea is neither.
    var condition: String?
    /// "Light wear on the toe, no cracks." The sentence that decides whether
    /// somebody drives an hour to look at it.
    var conditionNote: String?
    /// Short Handle, Harrow, Youth Large — free text, because bat, pad and
    /// glove sizes share no vocabulary.
    var size: String?
    var brand: String?
    var photos: [String]?
    /// Whether it appears outside the club.
    var listedPublicly: Bool?
    var collectionNote: String?
    /// Whether the price is the price. Second-hand kit gets haggled over, and
    /// a buyer who cannot tell either overpays or does not ask.
    var negotiable: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, description, currency, category, stock, condition, size, brand, photos
        case clubId = "club_id"
        case priceCents = "price_cents"
        case conditionNote = "condition_note"
        case listedPublicly = "listed_publicly"
        case collectionNote = "collection_note"
        case negotiable
    }

    var priceLabel: String {
        let amount = Double(priceCents) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        return f.string(from: NSNumber(value: amount)) ?? String(format: "£%.2f", amount)
    }

    /// "£45.00", or "£45.00 or near offer" when the seller will haggle. The
    /// difference decides whether somebody asks at all.
    var priceLine: String {
        negotiable == true ? "\(priceLabel) or near offer" : priceLabel
    }

    var isSold: Bool { stock == 0 }

    var availability: String {
        guard let stock else { return "On request" }
        if stock == 0 { return "Sold" }
        if stock == 1 && condition == "used" { return "One only" }
        return "\(stock) available"
    }

    var conditionLabel: String? {
        switch condition {
        case "used": return "Second-hand"
        case "new": return "Brand new"
        default: return nil
        }
    }

    var categoryLabel: String {
        switch category {
        case "equipment": return "Equipment"
        case "merchandise": return "Merchandise"
        default: return category.capitalized
        }
    }
}

/// One listing as its own page shows it: the product, plus who is selling it
/// and whether that is you.
///
/// `mine` is answered by the server rather than by comparing ids here, because
/// "mine" is not only "I posted it" — a secretary who runs the club's shop is
/// looking at their own listing too, and that rule belongs where the
/// permissions already live.
struct MarketListing: Codable, Identifiable, Hashable {
    var product: Product
    var clubName: String
    var sellerName: String?
    /// Only when the seller asked for their details to be shown. `nil`
    /// otherwise, and the buyer is pointed at the message thread instead.
    var sellerEmail: String?
    var sellerPhone: String?
    var mine: Bool
    /// How many people have asked about it. Only sent to the seller.
    var enquiries: Int?

    var id: UUID { product.id }

    /// The listing's own fields are flattened into the same object server-side,
    /// so the product decodes from the very same container.
    enum CodingKeys: String, CodingKey {
        case mine, enquiries
        case clubName = "club_name"
        case sellerName = "seller_name"
        case sellerEmail = "seller_email"
        case sellerPhone = "seller_phone"
    }

    init(from decoder: Decoder) throws {
        product = try Product(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clubName = try c.decode(String.self, forKey: .clubName)
        sellerName = try c.decodeIfPresent(String.self, forKey: .sellerName)
        sellerEmail = try c.decodeIfPresent(String.self, forKey: .sellerEmail)
        sellerPhone = try c.decodeIfPresent(String.self, forKey: .sellerPhone)
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
        enquiries = try c.decodeIfPresent(Int.self, forKey: .enquiries)
    }

    func encode(to encoder: Encoder) throws {
        try product.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clubName, forKey: .clubName)
        try c.encodeIfPresent(sellerName, forKey: .sellerName)
        try c.encodeIfPresent(sellerEmail, forKey: .sellerEmail)
        try c.encodeIfPresent(sellerPhone, forKey: .sellerPhone)
        try c.encode(mine, forKey: .mine)
        try c.encodeIfPresent(enquiries, forKey: .enquiries)
    }
}

/// The answer to asking about a listing: which thread to open, and whether it
/// is a new one or the one they already had.
struct EnquiryStarted: Codable {
    let conversationId: UUID
    let started: Bool

    enum CodingKeys: String, CodingKey {
        case started
        case conversationId = "conversation_id"
    }
}

struct Order: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let clubId: UUID
    var eventId: UUID?
    var status: String
    var totalAmountCents: Int
    var currency: String

    enum CodingKeys: String, CodingKey {
        case id, status, currency
        case userId = "user_id"
        case clubId = "club_id"
        case eventId = "event_id"
        case totalAmountCents = "total_amount_cents"
    }
}

/// Lightweight JSON value for event metadata.
enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

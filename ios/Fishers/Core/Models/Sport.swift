import Foundation

/// Sports the app knows about. Wire format stays a plain string (`User.sports`,
/// `Club.sportTypes`, `Team.sport`) so clubs can carry sports outside this list.
enum Sport: String, CaseIterable, Identifiable, Codable, Hashable {
    case cricket
    case football
    case badminton
    case padel
    case tennis
    case hockey
    case netball
    case rugby
    case basketball

    var id: String { rawValue }

    /// Stored form — capitalised to match the club/team sport strings.
    var label: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .cricket: return "figure.cricket"
        case .football: return "soccerball"
        case .badminton: return "figure.badminton"
        case .padel, .tennis: return "tennis.racket"
        case .hockey: return "figure.hockey"
        case .netball: return "figure.netball"
        case .rugby: return "figure.rugby"
        case .basketball: return "basketball.fill"
        }
    }

    /// Positions offered during profile setup for this sport.
    var positions: [String] {
        switch self {
        case .cricket:
            return ["Batter", "Fast Bowler", "Spinner", "All-rounder", "Wicketkeeper"]
        case .football, .hockey:
            return ["Goalkeeper", "Defender", "Midfielder", "Forward"]
        case .badminton, .tennis:
            return ["Singles", "Doubles", "Mixed doubles"]
        case .padel:
            return ["Right side", "Left side", "Either side"]
        case .netball:
            return ["Goal Shooter", "Goal Attack", "Wing Attack", "Centre", "Wing Defence", "Goal Defence", "Goal Keeper"]
        case .rugby:
            return ["Front row", "Second row", "Back row", "Half back", "Centre", "Back three"]
        case .basketball:
            return ["Guard", "Forward", "Centre"]
        }
    }

    /// Leagues are graded per sport; cricket drives the reference scenario.
    var usesDivisions: Bool {
        switch self {
        case .cricket, .football, .hockey, .netball, .rugby: return true
        case .badminton, .padel, .tennis, .basketball: return false
        }
    }

    init?(label: String?) {
        guard let label, let sport = Sport(rawValue: label.lowercased()) else { return nil }
        self = sport
    }
}

/// Self-rated standard, ordered so a player can see the rung above them.
enum SkillTier: String, CaseIterable, Identifiable, Codable, Hashable {
    case beginner
    case improver
    case intermediate
    case club
    case advanced
    case elite

    var id: String { rawValue }
    var label: String { rawValue == "club" ? "Club standard" : rawValue.capitalized }

    var blurb: String {
        switch self {
        case .beginner: return "New to the sport — learning the basics."
        case .improver: return "Played a bit, still building consistency."
        case .intermediate: return "Comfortable in social and lower league sides."
        case .club: return "Regular league cricketer, holds a place in an XI."
        case .advanced: return "Strong league performer, top-order or front-line."
        case .elite: return "Premier, county or representative standard."
        }
    }

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// The next rung up, used by the progression tracker on the profile.
    var next: SkillTier? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    /// Tolerates the capitalised strings stored on `User.skillLevel`.
    init?(stored: String?) {
        guard let stored else { return nil }
        let key = stored.lowercased().replacingOccurrences(of: " standard", with: "")
        guard let tier = SkillTier(rawValue: key) else { return nil }
        self = tier
    }
}

/// League grade, lowest to highest. Used for both "my team" and the opposition
/// standard a player is happy to face.
enum Division: String, CaseIterable, Identifiable, Codable, Hashable {
    case social
    case development
    case division5
    case division4
    case division3
    case division2
    case division1
    case premier
    case county

    var id: String { rawValue }

    var label: String {
        switch self {
        case .social: return "Social & friendlies"
        case .development: return "Development XI"
        case .division5: return "Division 5"
        case .division4: return "Division 4"
        case .division3: return "Division 3"
        case .division2: return "Division 2"
        case .division1: return "Division 1"
        case .premier: return "Premier Division"
        case .county: return "County / Representative"
        }
    }

    /// Compact form for badges next to a team or fixture.
    var shortLabel: String {
        switch self {
        case .social: return "Social"
        case .development: return "Dev XI"
        case .division5: return "Div 5"
        case .division4: return "Div 4"
        case .division3: return "Div 3"
        case .division2: return "Div 2"
        case .division1: return "Div 1"
        case .premier: return "Prem"
        case .county: return "County"
        }
    }

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    var next: Division? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    init?(stored: String?) {
        guard let stored, let division = Division(rawValue: stored) else { return nil }
        self = division
    }
}

/// Age band the player is eligible for — colts sides pick from the junior bands.
enum AgeGroup: String, CaseIterable, Identifiable, Codable, Hashable {
    case u11
    case u13
    case u15
    case u17
    case senior
    case vets40
    case vets50

    var id: String { rawValue }

    var label: String {
        switch self {
        case .u11: return "Under 11s"
        case .u13: return "Under 13s"
        case .u15: return "Under 15s"
        case .u17: return "Under 17s"
        case .senior: return "Senior"
        case .vets40: return "Vets 40+"
        case .vets50: return "Vets 50+"
        }
    }

    var isJunior: Bool {
        switch self {
        case .u11, .u13, .u15, .u17: return true
        default: return false
        }
    }

    init?(stored: String?) {
        guard let stored, let group = AgeGroup(rawValue: stored) else { return nil }
        self = group
    }
}

/// How the player gets to fixtures — feeds lift-sharing on away games.
enum TransportMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case driverWithSeats
    case driver
    case publicTransport
    case needsLift

    var id: String { rawValue }

    var label: String {
        switch self {
        case .driverWithSeats: return "Drives, can offer lifts"
        case .driver: return "Drives, no spare seats"
        case .publicTransport: return "Public transport"
        case .needsLift: return "Needs a lift"
        }
    }

    var systemImage: String {
        switch self {
        case .driverWithSeats: return "car.2.fill"
        case .driver: return "car.fill"
        case .publicTransport: return "tram.fill"
        case .needsLift: return "hand.raised.fill"
        }
    }

    var offersLifts: Bool { self == .driverWithSeats }
}

/// Weekday, matching `Calendar` numbering (1 = Sunday).
enum Weekday: Int, CaseIterable, Identifiable, Codable, Hashable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    /// Monday-first ordering for the day picker.
    static var pickerOrder: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}

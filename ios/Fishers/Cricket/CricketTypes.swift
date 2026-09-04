import Foundation

// MARK: - Enums (wire format matches Rust serde snake_case)

enum CricketMatchStatus: String, Codable, Hashable {
    case scheduled, preparing, toss, selectingXi = "selecting_xi"
    case ready, live, inningsBreak = "innings_break", complete, published
}

enum TossDecision: String, Codable, Hashable { case bat, bowl }

enum MatchSide: String, Codable, Hashable, CaseIterable {
    case home, away

    var opposite: MatchSide { self == .home ? .away : .home }
}

enum DismissalKind: String, Codable, CaseIterable, Identifiable {
    case bowled, caught, lbw, runOut = "run_out", stumped
    case hitWicket = "hit_wicket", retired, other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .bowled: return "Bowled"
        case .caught: return "Caught"
        case .lbw: return "LBW"
        case .runOut: return "Run out"
        case .stumped: return "Stumped"
        case .hitWicket: return "Hit wicket"
        case .retired: return "Retired"
        case .other: return "Other"
        }
    }
}

enum ExtraKind: String, Codable, CaseIterable, Identifiable {
    case wide, noBall = "no_ball", bye, legBye = "leg_bye", penalty

    var id: String { rawValue }
    var label: String {
        switch self {
        case .wide: return "Wide"
        case .noBall: return "No ball"
        case .bye: return "Bye"
        case .legBye: return "Leg bye"
        case .penalty: return "Penalty"
        }
    }
}

enum SyncStatus: String, Codable {
    case saved, syncing, offline
}

// MARK: - Event kinds (internally tagged `type`, nested under ScoringEvent.kind)

enum ScoringEventKind: Codable, Equatable {
    case matchPrepared(oversLimit: UInt8, homeName: String, awayName: String)
    case tossRecorded(winner: MatchSide, decision: TossDecision)
    case xiSelected(side: MatchSide, playerIds: [UUID], captainId: UUID?, keeperId: UUID?)
    case inningsStarted(
        inningsIndex: UInt8, batting: MatchSide,
        strikerId: UUID, nonStrikerId: UUID, bowlerId: UUID
    )
    case deliveryRecorded(runs: UInt8, isLegal: Bool, isBoundaryFour: Bool, isBoundarySix: Bool)
    case extrasRecorded(kind: ExtraKind, runs: UInt8)
    case wicketRecorded(
        batterId: UUID, kind: DismissalKind, fielderId: UUID?, newBatterId: UUID?
    )
    case bowlerChanged(bowlerId: UUID)
    case inningsCompleted
    case matchCompleted(winner: MatchSide?, margin: String)
    case undoLast

    private enum CodingKeys: String, CodingKey {
        case type
        case oversLimit = "overs_limit"
        case homeName = "home_name"
        case awayName = "away_name"
        case winner, decision, side
        case playerIds = "player_ids"
        case captainId = "captain_id"
        case keeperId = "keeper_id"
        case inningsIndex = "innings_index"
        case batting
        case strikerId = "striker_id"
        case nonStrikerId = "non_striker_id"
        case bowlerId = "bowler_id"
        case runs
        case isLegal = "is_legal"
        case isBoundaryFour = "is_boundary_four"
        case isBoundarySix = "is_boundary_six"
        case kind
        case batterId = "batter_id"
        case fielderId = "fielder_id"
        case newBatterId = "new_batter_id"
        case margin
    }

    private var typeName: String {
        switch self {
        case .matchPrepared: return "match_prepared"
        case .tossRecorded: return "toss_recorded"
        case .xiSelected: return "xi_selected"
        case .inningsStarted: return "innings_started"
        case .deliveryRecorded: return "delivery_recorded"
        case .extrasRecorded: return "extras_recorded"
        case .wicketRecorded: return "wicket_recorded"
        case .bowlerChanged: return "bowler_changed"
        case .inningsCompleted: return "innings_completed"
        case .matchCompleted: return "match_completed"
        case .undoLast: return "undo_last"
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(typeName, forKey: .type)
        switch self {
        case let .matchPrepared(overs, home, away):
            try c.encode(overs, forKey: .oversLimit)
            try c.encode(home, forKey: .homeName)
            try c.encode(away, forKey: .awayName)
        case let .tossRecorded(winner, decision):
            try c.encode(winner, forKey: .winner)
            try c.encode(decision, forKey: .decision)
        case let .xiSelected(side, ids, captain, keeper):
            try c.encode(side, forKey: .side)
            try c.encode(ids, forKey: .playerIds)
            try c.encodeIfPresent(captain, forKey: .captainId)
            try c.encodeIfPresent(keeper, forKey: .keeperId)
        case let .inningsStarted(idx, batting, striker, non, bowler):
            try c.encode(idx, forKey: .inningsIndex)
            try c.encode(batting, forKey: .batting)
            try c.encode(striker, forKey: .strikerId)
            try c.encode(non, forKey: .nonStrikerId)
            try c.encode(bowler, forKey: .bowlerId)
        case let .deliveryRecorded(runs, legal, four, six):
            try c.encode(runs, forKey: .runs)
            try c.encode(legal, forKey: .isLegal)
            try c.encode(four, forKey: .isBoundaryFour)
            try c.encode(six, forKey: .isBoundarySix)
        case let .extrasRecorded(kind, runs):
            try c.encode(kind, forKey: .kind)
            try c.encode(runs, forKey: .runs)
        case let .wicketRecorded(batter, kind, fielder, newBatter):
            try c.encode(batter, forKey: .batterId)
            try c.encode(kind, forKey: .kind)
            try c.encodeIfPresent(fielder, forKey: .fielderId)
            try c.encodeIfPresent(newBatter, forKey: .newBatterId)
        case let .bowlerChanged(bowler):
            try c.encode(bowler, forKey: .bowlerId)
        case .inningsCompleted, .undoLast:
            break
        case let .matchCompleted(winner, margin):
            try c.encodeIfPresent(winner, forKey: .winner)
            try c.encode(margin, forKey: .margin)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "match_prepared":
            self = .matchPrepared(
                oversLimit: try c.decode(UInt8.self, forKey: .oversLimit),
                homeName: try c.decode(String.self, forKey: .homeName),
                awayName: try c.decode(String.self, forKey: .awayName)
            )
        case "toss_recorded":
            self = .tossRecorded(
                winner: try c.decode(MatchSide.self, forKey: .winner),
                decision: try c.decode(TossDecision.self, forKey: .decision)
            )
        case "xi_selected":
            self = .xiSelected(
                side: try c.decode(MatchSide.self, forKey: .side),
                playerIds: try c.decode([UUID].self, forKey: .playerIds),
                captainId: try c.decodeIfPresent(UUID.self, forKey: .captainId),
                keeperId: try c.decodeIfPresent(UUID.self, forKey: .keeperId)
            )
        case "innings_started":
            self = .inningsStarted(
                inningsIndex: try c.decode(UInt8.self, forKey: .inningsIndex),
                batting: try c.decode(MatchSide.self, forKey: .batting),
                strikerId: try c.decode(UUID.self, forKey: .strikerId),
                nonStrikerId: try c.decode(UUID.self, forKey: .nonStrikerId),
                bowlerId: try c.decode(UUID.self, forKey: .bowlerId)
            )
        case "delivery_recorded":
            self = .deliveryRecorded(
                runs: try c.decode(UInt8.self, forKey: .runs),
                isLegal: try c.decode(Bool.self, forKey: .isLegal),
                isBoundaryFour: try c.decode(Bool.self, forKey: .isBoundaryFour),
                isBoundarySix: try c.decode(Bool.self, forKey: .isBoundarySix)
            )
        case "extras_recorded":
            self = .extrasRecorded(
                kind: try c.decode(ExtraKind.self, forKey: .kind),
                runs: try c.decode(UInt8.self, forKey: .runs)
            )
        case "wicket_recorded":
            self = .wicketRecorded(
                batterId: try c.decode(UUID.self, forKey: .batterId),
                kind: try c.decode(DismissalKind.self, forKey: .kind),
                fielderId: try c.decodeIfPresent(UUID.self, forKey: .fielderId),
                newBatterId: try c.decodeIfPresent(UUID.self, forKey: .newBatterId)
            )
        case "bowler_changed":
            self = .bowlerChanged(bowlerId: try c.decode(UUID.self, forKey: .bowlerId))
        case "innings_completed":
            self = .inningsCompleted
        case "match_completed":
            self = .matchCompleted(
                winner: try c.decodeIfPresent(MatchSide.self, forKey: .winner),
                margin: try c.decode(String.self, forKey: .margin)
            )
        case "undo_last":
            self = .undoLast
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "Unknown event type \(type)"
            )
        }
    }
}

struct ScoringEvent: Codable, Identifiable, Equatable {
    var id: UUID { clientEventId }
    var clientEventId: UUID
    var seq: Int64
    var kind: ScoringEventKind

    enum CodingKeys: String, CodingKey {
        case clientEventId = "client_event_id"
        case seq, kind
    }

    static func make(seq: Int64, kind: ScoringEventKind) -> ScoringEvent {
        ScoringEvent(clientEventId: UUID(), seq: seq, kind: kind)
    }
}

// MARK: - Stats / state

struct BatterStats: Codable, Equatable, Identifiable {
    var playerId: UUID
    var runs: UInt16
    var balls: UInt16
    var fours: UInt16
    var sixes: UInt16
    var out: Bool
    var dismissal: DismissalKind?

    var id: UUID { playerId }

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case runs, balls, fours, sixes, out, dismissal
    }

    init(playerId: UUID) {
        self.playerId = playerId
        runs = 0; balls = 0; fours = 0; sixes = 0; out = false; dismissal = nil
    }
}

struct BowlerStats: Codable, Equatable, Identifiable {
    var playerId: UUID
    var balls: UInt16
    var runs: UInt16
    var wickets: UInt16
    var maidens: UInt16
    var currentOverRuns: UInt16

    var id: UUID { playerId }

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case balls, runs, wickets, maidens
        case currentOverRuns = "current_over_runs"
    }

    init(playerId: UUID) {
        self.playerId = playerId
        balls = 0; runs = 0; wickets = 0; maidens = 0; currentOverRuns = 0
    }

    var oversDisplay: String { "\(balls / 6).\(balls % 6)" }
}

struct FallOfWicket: Codable, Equatable {
    var score: UInt16
    var wickets: UInt8
    var batterId: UUID
    var overBall: String

    enum CodingKeys: String, CodingKey {
        case score, wickets
        case batterId = "batter_id"
        case overBall = "over_ball"
    }
}

struct DeliveryRecord: Codable, Equatable {
    var over: UInt16
    var ballInOver: UInt8
    var label: String
    var runs: UInt8
    var isLegal: Bool
    var isWicket: Bool

    enum CodingKeys: String, CodingKey {
        case over, label, runs
        case ballInOver = "ball_in_over"
        case isLegal = "is_legal"
        case isWicket = "is_wicket"
    }
}

struct InningsState: Codable, Equatable {
    var index: UInt8
    var batting: MatchSide
    var bowling: MatchSide
    var runs: UInt16
    var wickets: UInt8
    var legalBalls: UInt16
    var extras: UInt16
    var batters: [BatterStats]
    var bowlers: [BowlerStats]
    var fall: [FallOfWicket]
    var deliveries: [DeliveryRecord]
    var strikerId: UUID?
    var nonStrikerId: UUID?
    var bowlerId: UUID?
    var complete: Bool
    var ballsInCurrentOver: UInt8

    enum CodingKeys: String, CodingKey {
        case index, batting, bowling, runs, wickets, extras, batters, bowlers, fall, deliveries, complete
        case legalBalls = "legal_balls"
        case strikerId = "striker_id"
        case nonStrikerId = "non_striker_id"
        case bowlerId = "bowler_id"
        case ballsInCurrentOver = "balls_in_current_over"
    }

    init(
        index: UInt8 = 0,
        batting: MatchSide = .home,
        bowling: MatchSide = .away
    ) {
        self.index = index
        self.batting = batting
        self.bowling = bowling
        runs = 0; wickets = 0; legalBalls = 0; extras = 0
        batters = []; bowlers = []; fall = []; deliveries = []
        strikerId = nil; nonStrikerId = nil; bowlerId = nil
        complete = false; ballsInCurrentOver = 0
    }

    mutating func swapStrike() {
        swap(&strikerId, &nonStrikerId)
    }

    mutating func ensureBowler(_ id: UUID) {
        if !bowlers.contains(where: { $0.playerId == id }) {
            bowlers.append(BowlerStats(playerId: id))
        }
    }

    mutating func batterMut(_ id: UUID) throws -> Int {
        guard let i = batters.firstIndex(where: { $0.playerId == id }) else {
            throw CricketEngineError.validation("batter not in innings")
        }
        return i
    }

    mutating func bowlerMut(_ id: UUID) throws -> Int {
        ensureBowler(id)
        guard let i = bowlers.firstIndex(where: { $0.playerId == id }) else {
            throw CricketEngineError.validation("bowler missing")
        }
        return i
    }
}

struct MatchStateSnapshot: Equatable {
    var status: CricketMatchStatus
    var innings: [InningsState]
    var target: UInt16?
    var winner: MatchSide?
    var margin: String?
}

struct MatchState: Codable, Equatable {
    var status: CricketMatchStatus
    var oversLimit: UInt8
    var homeName: String
    var awayName: String
    var tossWinner: MatchSide?
    var tossDecision: TossDecision?
    var homeXi: [UUID]
    var awayXi: [UUID]
    var homeCaptain: UUID?
    var awayCaptain: UUID?
    var homeKeeper: UUID?
    var awayKeeper: UUID?
    var innings: [InningsState]
    var target: UInt16?
    var winner: MatchSide?
    var margin: String?
    var lastSeq: Int64
    /// Local undo stack — not serialized to API.
    var history: [MatchStateSnapshot] = []

    enum CodingKeys: String, CodingKey {
        case status
        case oversLimit = "overs_limit"
        case homeName = "home_name"
        case awayName = "away_name"
        case tossWinner = "toss_winner"
        case tossDecision = "toss_decision"
        case homeXi = "home_xi"
        case awayXi = "away_xi"
        case homeCaptain = "home_captain"
        case awayCaptain = "away_captain"
        case homeKeeper = "home_keeper"
        case awayKeeper = "away_keeper"
        case innings, target, winner, margin
        case lastSeq = "last_seq"
    }

    init(
        oversLimit: UInt8 = 20,
        homeName: String = "Home",
        awayName: String = "Away"
    ) {
        status = .scheduled
        self.oversLimit = oversLimit
        self.homeName = homeName
        self.awayName = awayName
        tossWinner = nil; tossDecision = nil
        homeXi = []; awayXi = []
        homeCaptain = nil; awayCaptain = nil
        homeKeeper = nil; awayKeeper = nil
        innings = []; target = nil; winner = nil; margin = nil
        lastSeq = 0; history = []
    }

    var currentInnings: InningsState? { innings.last }

    static func oversBallsDisplay(_ legalBalls: UInt16) -> String {
        "\(legalBalls / 6).\(legalBalls % 6)"
    }

    var currentRunRate: Double {
        guard let inn = currentInnings, inn.legalBalls > 0 else { return 0 }
        return Double(inn.runs) * 6.0 / Double(inn.legalBalls)
    }

    var requiredRunRate: Double? {
        guard let target, let inn = currentInnings, inn.index >= 1 else { return nil }
        let remainingRuns = target > inn.runs ? target - inn.runs : 0
        let totalBalls = UInt16(oversLimit) * 6
        let remainingBalls = totalBalls > inn.legalBalls ? totalBalls - inn.legalBalls : 0
        guard remainingBalls > 0 else { return 0 }
        return Double(remainingRuns) * 6.0 / Double(remainingBalls)
    }

    func name(for side: MatchSide) -> String {
        side == .home ? homeName : awayName
    }

    func scoreLine() -> String {
        guard let inn = currentInnings else {
            return "\(homeName) vs \(awayName)"
        }
        let side = name(for: inn.batting)
        return "\(side) \(inn.runs)/\(inn.wickets) (\(Self.oversBallsDisplay(inn.legalBalls)))"
    }
}

struct CricketMatchDTO: Codable {
    let id: UUID
    let eventId: UUID
    let clubId: UUID
    let status: String
    let oversLimit: Int
    let homeName: String
    let awayName: String
    let lastSeq: Int64
    let activeScorerUserId: UUID?
    let state: MatchState

    enum CodingKeys: String, CodingKey {
        case id, status, state
        case eventId = "event_id"
        case clubId = "club_id"
        case oversLimit = "overs_limit"
        case homeName = "home_name"
        case awayName = "away_name"
        case lastSeq = "last_seq"
        case activeScorerUserId = "active_scorer_user_id"
    }
}

enum CricketEngineError: LocalizedError {
    case validation(String)
    case conflict(String)

    var errorDescription: String? {
        switch self {
        case .validation(let m), .conflict(let m): return m
        }
    }
}

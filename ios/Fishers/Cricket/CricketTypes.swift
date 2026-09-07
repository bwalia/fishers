import Foundation

// MARK: - Enums (wire format matches Rust serde snake_case)

enum CricketMatchStatus: String, Codable, Hashable {
    case scheduled, preparing, toss, selectingXi = "selecting_xi"
    case ready, live, inningsBreak = "innings_break", complete, published

    var isFinished: Bool { self == .complete || self == .published }
}

enum TossDecision: String, Codable, Hashable, CaseIterable {
    case bat, bowl
    var label: String { self == .bat ? "Bat" : "Bowl" }
}

enum MatchSide: String, Codable, Hashable, CaseIterable {
    case home, away

    var opposite: MatchSide { self == .home ? .away : .home }
}

enum DismissalKind: String, Codable, CaseIterable, Identifiable {
    case bowled, caught, lbw, runOut = "run_out", stumped
    case hitWicket = "hit_wicket", retired
    case retiredHurt = "retired_hurt"
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bowled: return "Bowled"
        case .caught: return "Caught"
        case .lbw: return "LBW"
        case .runOut: return "Run out"
        case .stumped: return "Stumped"
        case .hitWicket: return "Hit wicket"
        case .retired: return "Retired out"
        case .retiredHurt: return "Retired hurt"
        case .other: return "Other"
        }
    }

    /// Dismissals the bowler gets credit for.
    var creditsBowler: Bool {
        switch self {
        case .bowled, .caught, .lbw, .stumped, .hitWicket: return true
        default: return false
        }
    }

    /// Retiring, either way, does not use up a delivery.
    var usesABall: Bool { self != .retired && self != .retiredHurt }

    /// Retired hurt costs a batter but not a wicket, and they may come back.
    var costsAWicket: Bool { self != .retiredHurt }

    /// The only ways out on a free hit.
    var allowedOnAFreeHit: Bool {
        switch self {
        case .runOut, .retired, .retiredHurt, .other: return true
        default: return false
        }
    }

    /// A dismissal that can land on a delivery already booked as an extra.
    var canFollowAnExtra: Bool {
        switch self {
        case .stumped, .runOut, .other: return true
        default: return false
        }
    }

    /// Who took the catch, effected the run out, made the stumping.
    var needsFielder: Bool {
        switch self {
        case .caught, .runOut, .stumped: return true
        default: return false
        }
    }

    /// Only a run out can take the batter at the non-striker's end.
    var canDismissNonStriker: Bool {
        self == .runOut || self == .retired || self == .retiredHurt
    }

    /// Runs can be completed before a run out.
    var allowsCompletedRuns: Bool { self == .runOut }
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

    var shortLabel: String {
        switch self {
        case .wide: return "wd"
        case .noBall: return "nb"
        case .bye: return "b"
        case .legBye: return "lb"
        case .penalty: return "p"
        }
    }

    /// The runs field means "total including the extra itself" for wides and
    /// no-balls, and "runs run" for byes and leg byes.
    var footnote: String {
        switch self {
        case .wide: return "1 for the wide, plus any run."
        case .noBall: return "1 for the no ball, plus runs off the bat."
        case .bye, .legBye: return "Counts as a legal ball."
        case .penalty: return "Five penalty runs, no ball bowled."
        }
    }
}

enum SyncStatus: String, Codable {
    case saved, syncing, offline
}

// MARK: - Team sheet

/// Who is standing and who is keeping the book.
struct MatchOfficials: Codable, Equatable {
    var umpires: [MatchPlayer]
    var scorers: [MatchPlayer]

    init(umpires: [MatchPlayer] = [], scorers: [MatchPlayer] = []) {
        self.umpires = umpires
        self.scorers = scorers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        umpires = try c.decodeIfPresent([MatchPlayer].self, forKey: .umpires) ?? []
        scorers = try c.decodeIfPresent([MatchPlayer].self, forKey: .scorers) ?? []
    }

    var isEmpty: Bool { umpires.isEmpty && scorers.isEmpty }

    var summary: String {
        var parts: [String] = []
        if !umpires.isEmpty {
            parts.append("Umpires: " + umpires.map(\.name).joined(separator: ", "))
        }
        if !scorers.isEmpty {
            parts.append("Scorers: " + scorers.map(\.name).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }
}

/// Where the game is being played.
enum GroundType: String, Codable, CaseIterable, Identifiable {
    case open, boxed, indoor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open: return "Open ground"
        case .boxed: return "Boxed / caged"
        case .indoor: return "Indoor"
        }
    }

    var systemImage: String {
        switch self {
        case .open: return "sun.max"
        case .boxed: return "square.grid.3x3"
        case .indoor: return "building.2"
        }
    }

    var blurb: String {
        switch self {
        case .open: return "Full boundary, normal outfield."
        case .boxed: return "Caged or netted — walls are in play."
        case .indoor: return "Indoor centre rules."
        }
    }
}

/// What they are bowling with.
enum BallType: String, Codable, CaseIterable, Identifiable {
    case red, white, pink, tennis, tape

    var id: String { rawValue }

    var label: String {
        switch self {
        case .red: return "Red leather"
        case .white: return "White leather"
        case .pink: return "Pink leather"
        case .tennis: return "Tennis"
        case .tape: return "Tape ball"
        }
    }

    var shortLabel: String {
        switch self {
        case .red: return "Red"
        case .white: return "White"
        case .pink: return "Pink"
        case .tennis: return "Tennis"
        case .tape: return "Tape"
        }
    }
}

/// The terms of the game, as the two captains settle them at the toss.
struct MatchConditions: Codable, Equatable, Hashable {
    var oversLimit: UInt8
    /// Most a single bowler may send down. 0 means no limit.
    var oversPerBowler: UInt8
    var ground: GroundType
    var ball: BallType
    /// Overs of fielding restrictions at the start of an innings. 0 for none.
    var powerplayOvers: UInt8
    /// Fielders allowed outside the circle during the powerplay.
    var fieldersOutsidePowerplay: UInt8
    /// Fielders allowed outside the circle for the rest of the innings.
    var fieldersOutsideNormal: UInt8
    /// Fielders allowed behind square on the leg side. Two, in every format.
    var fieldersBehindSquareLeg: UInt8
    /// Overs a side is expected to bowl in an hour. 0 means nobody is counting.
    var targetOversPerHour: UInt8

    enum CodingKeys: String, CodingKey {
        case ground, ball
        case oversLimit = "overs_limit"
        case oversPerBowler = "overs_per_bowler"
        case powerplayOvers = "powerplay_overs"
        case fieldersOutsidePowerplay = "fielders_outside_powerplay"
        case fieldersOutsideNormal = "fielders_outside_normal"
        case fieldersBehindSquareLeg = "fielders_behind_square_leg"
        case targetOversPerHour = "target_overs_per_hour"
    }

    init(
        oversLimit: UInt8, oversPerBowler: UInt8,
        ground: GroundType, ball: BallType, powerplayOvers: UInt8 = 0,
        fieldersOutsidePowerplay: UInt8 = 2,
        fieldersOutsideNormal: UInt8 = 5,
        fieldersBehindSquareLeg: UInt8 = 2,
        targetOversPerHour: UInt8 = 0
    ) {
        self.oversLimit = oversLimit
        self.oversPerBowler = oversPerBowler
        self.ground = ground
        self.ball = ball
        self.powerplayOvers = powerplayOvers
        self.fieldersOutsidePowerplay = fieldersOutsidePowerplay
        self.fieldersOutsideNormal = fieldersOutsideNormal
        self.fieldersBehindSquareLeg = fieldersBehindSquareLeg
        self.targetOversPerHour = targetOversPerHour
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        oversLimit = try c.decode(UInt8.self, forKey: .oversLimit)
        oversPerBowler = try c.decode(UInt8.self, forKey: .oversPerBowler)
        ground = try c.decode(GroundType.self, forKey: .ground)
        ball = try c.decode(BallType.self, forKey: .ball)
        powerplayOvers = try c.decodeIfPresent(UInt8.self, forKey: .powerplayOvers) ?? 0
        fieldersOutsidePowerplay =
            try c.decodeIfPresent(UInt8.self, forKey: .fieldersOutsidePowerplay) ?? 2
        fieldersOutsideNormal =
            try c.decodeIfPresent(UInt8.self, forKey: .fieldersOutsideNormal) ?? 5
        fieldersBehindSquareLeg =
            try c.decodeIfPresent(UInt8.self, forKey: .fieldersBehindSquareLeg) ?? 2
        targetOversPerHour =
            try c.decodeIfPresent(UInt8.self, forKey: .targetOversPerHour) ?? 0
    }

    /// How many fielders may be outside the circle right now.
    func fieldersAllowedOutside(inPowerplay: Bool) -> UInt8 {
        inPowerplay ? fieldersOutsidePowerplay : fieldersOutsideNormal
    }

    /// A fifth of the innings each, rounded up: 20 overs gives 4, 50 gives 10.
    static func standardOversPerBowler(_ overs: UInt8) -> UInt8 {
        max(1, UInt8((Int(overs) + 4) / 5))
    }

    /// The powerplay most competitions use at each length.
    static func standardPowerplay(_ overs: UInt8) -> UInt8 {
        switch overs {
        case 0...5: return 0
        case 6...10: return 2
        case 11...20: return 6
        case 21...40: return 8
        default: return 10
        }
    }

    static func standard(overs: UInt8) -> MatchConditions {
        let overs = max(overs, 1)
        return MatchConditions(
            oversLimit: overs,
            oversPerBowler: standardOversPerBowler(overs),
            ground: .open,
            ball: .white,
            powerplayOvers: standardPowerplay(overs)
        )
    }

    /// "20 overs · 4 per bowler · white leather · open ground"
    var summary: String {
        let perBowler = oversPerBowler == 0 ? "no bowler limit" : "\(oversPerBowler) per bowler"
        var summary = "\(oversLimit) overs · \(perBowler) · \(ball.label.lowercased()) · \(ground.label.lowercased())"
        if powerplayOvers > 0 {
            summary += " · \(powerplayOvers) over powerplay"
        }
        return summary
    }
}

/// A player on a team sheet — a Fishers member, or a guest with a name only.
struct MatchPlayer: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    /// Left-handers mirror the field, so the wagon wheel has to know.
    var batsLeft: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case batsLeft = "bats_left"
    }

    init(id: UUID = UUID(), name: String, batsLeft: Bool = false) {
        self.id = id
        self.name = name
        self.batsLeft = batsLeft
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        batsLeft = try c.decodeIfPresent(Bool.self, forKey: .batsLeft) ?? false
    }
}

/// How the shot was played. Enough to write a line of commentary from.
enum ShotKind: String, Codable, CaseIterable, Identifiable {
    case drive, cut, pull, hook, sweep
    case reverseSweep = "reverse_sweep"
    case glance, flick, loft, defence, edge, leave, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .drive: return "Drive"
        case .cut: return "Cut"
        case .pull: return "Pull"
        case .hook: return "Hook"
        case .sweep: return "Sweep"
        case .reverseSweep: return "Reverse sweep"
        case .glance: return "Glance"
        case .flick: return "Flick"
        case .loft: return "Loft"
        case .defence: return "Defence"
        case .edge: return "Edge"
        case .leave: return "Leave"
        case .other: return "Other"
        }
    }

    /// The verb a commentator would use.
    var verb: String {
        switch self {
        case .drive: return "driven"
        case .cut: return "cut"
        case .pull: return "pulled"
        case .hook: return "hooked"
        case .sweep: return "swept"
        case .reverseSweep: return "reverse-swept"
        case .glance: return "glanced"
        case .flick: return "flicked"
        case .loft: return "lofted"
        case .defence: return "defended"
        case .edge: return "edged"
        case .leave: return "left alone"
        case .other: return "worked away"
        }
    }

    /// The shots most likely for a given number of runs, offered first.
    static func likely(forRuns runs: Int) -> [ShotKind] {
        switch runs {
        case 0: return [.defence, .leave, .edge, .drive, .cut, .pull, .other]
        case 4: return [.drive, .cut, .pull, .sweep, .glance, .flick, .edge, .loft]
        case 6: return [.loft, .pull, .hook, .drive, .sweep]
        default: return [.drive, .flick, .glance, .cut, .pull, .sweep, .other]
        }
    }
}

/// Where the ball went. `angle` is degrees clockwise from straight down the
/// ground past the bowler, as struck.
struct ShotRecord: Codable, Equatable, Hashable {
    var angle: UInt16
    var kind: ShotKind
    /// 0 at the stumps, 1 at the rope.
    var reach: Double

    enum CodingKeys: String, CodingKey {
        case angle, kind, reach
    }

    init(angle: UInt16, kind: ShotKind, reach: Double = 0.6) {
        self.angle = angle
        self.kind = kind
        self.reach = reach
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        angle = try c.decode(UInt16.self, forKey: .angle)
        kind = try c.decode(ShotKind.self, forKey: .kind)
        reach = try c.decodeIfPresent(Double.self, forKey: .reach) ?? 0.6
    }
}

/// The eight sectors of a wagon wheel, named as the batter's own field.
func cricketRegion(angle: UInt16, batsLeft: Bool) -> String {
    let raw = Int(angle) % 360
    let a = batsLeft ? (360 - raw) % 360 : raw
    switch a {
    case 0...44: return "long on"
    case 45...89: return "mid-wicket"
    case 90...134: return "square leg"
    case 135...179: return "fine leg"
    case 180...224: return "third man"
    case 225...269: return "point"
    case 270...314: return "cover"
    default: return "long off"
    }
}

// MARK: - Event kinds (internally tagged `type`, nested under ScoringEvent.kind)

enum ScoringEventKind: Codable, Equatable {
    case matchPrepared(oversLimit: UInt8, homeName: String, awayName: String)
    case tossRecorded(winner: MatchSide, decision: TossDecision)
    case xiSelected(side: MatchSide, players: [MatchPlayer], captainId: UUID?, keeperId: UUID?)
    case inningsStarted(
        inningsIndex: UInt8, batting: MatchSide,
        strikerId: UUID, nonStrikerId: UUID, bowlerId: UUID,
        superOver: Bool = false
    )
    case deliveryRecorded(
        runs: UInt8, isLegal: Bool, isBoundaryFour: Bool, isBoundarySix: Bool,
        shot: ShotRecord?
    )
    /// An extra plus whatever came of the ball. `runs` is what the batters ran
    /// (or the boundary), on top of the one-run penalty a wide or no ball
    /// carries by itself.
    case extrasRecorded(
        kind: ExtraKind, runs: UInt8, boundary: Bool, offTheBat: Bool, shot: ShotRecord?
    )
    case oversRevised(inningsIndex: UInt8, overs: UInt8)
    /// One captain sets out the terms. A later proposal clears both agreements.
    case conditionsProposed(conditions: MatchConditions, by: MatchSide, byName: String)
    /// A captain accepts the terms. The toss waits for both.
    case conditionsAgreed(side: MatchSide, captainName: String)
    case officialsAppointed(officials: MatchOfficials)
    /// A batter who retired hurt comes back in.
    case batterResumed(batterId: UUID, replacingId: UUID?)
    case playerOfTheMatch(playerId: UUID)
    /// Runs the umpire awards that nobody bowled or ran.
    case penaltyRuns(runs: UInt8, reason: String, toSide: MatchSide?)
    /// Where the field is set — the two counts the Laws restrict.
    case fieldSet(outsideCircle: UInt8, behindSquareLeg: UInt8)
    case wicketRecorded(
        batterId: UUID, kind: DismissalKind, fielderId: UUID?, newBatterId: UUID?,
        runs: UInt8, onExtra: Bool
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
        case winner, decision, side, players, overs, conditions, by
        case byName = "by_name"
        case captainName = "captain_name"
        case officials
        case onExtra = "on_extra"
        case playerId = "player_id"
        case replacingId = "replacing_id"
        case reason
        case superOver = "super_over"
        case toSide = "to_side"
        case outsideCircle = "outside_circle"
        case behindSquareLeg = "behind_square_leg"
        case captainId = "captain_id"
        case keeperId = "keeper_id"
        case inningsIndex = "innings_index"
        case batting
        case strikerId = "striker_id"
        case nonStrikerId = "non_striker_id"
        case bowlerId = "bowler_id"
        case runs, shot, boundary
        case offTheBat = "off_the_bat"
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
        case .oversRevised: return "overs_revised"
        case .conditionsProposed: return "conditions_proposed"
        case .conditionsAgreed: return "conditions_agreed"
        case .officialsAppointed: return "officials_appointed"
        case .batterResumed: return "batter_resumed"
        case .playerOfTheMatch: return "player_of_the_match"
        case .penaltyRuns: return "penalty_runs"
        case .fieldSet: return "field_set"
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
        case let .xiSelected(side, players, captain, keeper):
            try c.encode(side, forKey: .side)
            try c.encode(players, forKey: .players)
            try c.encodeIfPresent(captain, forKey: .captainId)
            try c.encodeIfPresent(keeper, forKey: .keeperId)
        case let .inningsStarted(idx, batting, striker, non, bowler, superOver):
            try c.encode(idx, forKey: .inningsIndex)
            try c.encode(batting, forKey: .batting)
            try c.encode(striker, forKey: .strikerId)
            try c.encode(non, forKey: .nonStrikerId)
            try c.encode(bowler, forKey: .bowlerId)
            try c.encode(superOver, forKey: .superOver)
        case let .deliveryRecorded(runs, legal, four, six, shot):
            try c.encode(runs, forKey: .runs)
            try c.encode(legal, forKey: .isLegal)
            try c.encode(four, forKey: .isBoundaryFour)
            try c.encode(six, forKey: .isBoundarySix)
            try c.encodeIfPresent(shot, forKey: .shot)
        case let .extrasRecorded(kind, runs, boundary, offTheBat, shot):
            try c.encode(kind, forKey: .kind)
            try c.encode(runs, forKey: .runs)
            try c.encode(boundary, forKey: .boundary)
            try c.encode(offTheBat, forKey: .offTheBat)
            try c.encodeIfPresent(shot, forKey: .shot)
        case let .oversRevised(index, overs):
            try c.encode(index, forKey: .inningsIndex)
            try c.encode(overs, forKey: .overs)
        case let .conditionsProposed(conditions, by, byName):
            try c.encode(conditions, forKey: .conditions)
            try c.encode(by, forKey: .by)
            try c.encode(byName, forKey: .byName)
        case let .conditionsAgreed(side, captainName):
            try c.encode(side, forKey: .side)
            try c.encode(captainName, forKey: .captainName)
        case let .officialsAppointed(officials):
            try c.encode(officials, forKey: .officials)
        case let .batterResumed(batterId, replacingId):
            try c.encode(batterId, forKey: .batterId)
            try c.encodeIfPresent(replacingId, forKey: .replacingId)
        case let .playerOfTheMatch(playerId):
            try c.encode(playerId, forKey: .playerId)
        case let .penaltyRuns(runs, reason, toSide):
            try c.encode(runs, forKey: .runs)
            try c.encode(reason, forKey: .reason)
            try c.encodeIfPresent(toSide, forKey: .toSide)
        case let .fieldSet(outsideCircle, behindSquareLeg):
            try c.encode(outsideCircle, forKey: .outsideCircle)
            try c.encode(behindSquareLeg, forKey: .behindSquareLeg)
        case let .wicketRecorded(batter, kind, fielder, newBatter, runs, onExtra):
            try c.encode(batter, forKey: .batterId)
            try c.encode(kind, forKey: .kind)
            try c.encodeIfPresent(fielder, forKey: .fielderId)
            try c.encodeIfPresent(newBatter, forKey: .newBatterId)
            try c.encode(runs, forKey: .runs)
            try c.encode(onExtra, forKey: .onExtra)
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
                players: try c.decode([MatchPlayer].self, forKey: .players),
                captainId: try c.decodeIfPresent(UUID.self, forKey: .captainId),
                keeperId: try c.decodeIfPresent(UUID.self, forKey: .keeperId)
            )
        case "innings_started":
            self = .inningsStarted(
                inningsIndex: try c.decode(UInt8.self, forKey: .inningsIndex),
                batting: try c.decode(MatchSide.self, forKey: .batting),
                strikerId: try c.decode(UUID.self, forKey: .strikerId),
                nonStrikerId: try c.decode(UUID.self, forKey: .nonStrikerId),
                bowlerId: try c.decode(UUID.self, forKey: .bowlerId),
                superOver: try c.decodeIfPresent(Bool.self, forKey: .superOver) ?? false
            )
        case "delivery_recorded":
            self = .deliveryRecorded(
                runs: try c.decode(UInt8.self, forKey: .runs),
                isLegal: try c.decode(Bool.self, forKey: .isLegal),
                isBoundaryFour: try c.decode(Bool.self, forKey: .isBoundaryFour),
                isBoundarySix: try c.decode(Bool.self, forKey: .isBoundarySix),
                shot: try c.decodeIfPresent(ShotRecord.self, forKey: .shot)
            )
        case "extras_recorded":
            self = .extrasRecorded(
                kind: try c.decode(ExtraKind.self, forKey: .kind),
                runs: try c.decodeIfPresent(UInt8.self, forKey: .runs) ?? 0,
                boundary: try c.decodeIfPresent(Bool.self, forKey: .boundary) ?? false,
                offTheBat: try c.decodeIfPresent(Bool.self, forKey: .offTheBat) ?? false,
                shot: try c.decodeIfPresent(ShotRecord.self, forKey: .shot)
            )
        case "overs_revised":
            self = .oversRevised(
                inningsIndex: try c.decode(UInt8.self, forKey: .inningsIndex),
                overs: try c.decode(UInt8.self, forKey: .overs)
            )
        case "conditions_proposed":
            self = .conditionsProposed(
                conditions: try c.decode(MatchConditions.self, forKey: .conditions),
                by: try c.decode(MatchSide.self, forKey: .by),
                byName: try c.decode(String.self, forKey: .byName)
            )
        case "conditions_agreed":
            self = .conditionsAgreed(
                side: try c.decode(MatchSide.self, forKey: .side),
                captainName: try c.decode(String.self, forKey: .captainName)
            )
        case "officials_appointed":
            self = .officialsAppointed(
                officials: try c.decode(MatchOfficials.self, forKey: .officials)
            )
        case "batter_resumed":
            self = .batterResumed(
                batterId: try c.decode(UUID.self, forKey: .batterId),
                replacingId: try c.decodeIfPresent(UUID.self, forKey: .replacingId)
            )
        case "player_of_the_match":
            self = .playerOfTheMatch(playerId: try c.decode(UUID.self, forKey: .playerId))
        case "penalty_runs":
            self = .penaltyRuns(
                runs: try c.decode(UInt8.self, forKey: .runs),
                reason: try c.decode(String.self, forKey: .reason),
                toSide: try c.decodeIfPresent(MatchSide.self, forKey: .toSide)
            )
        case "field_set":
            self = .fieldSet(
                outsideCircle: try c.decode(UInt8.self, forKey: .outsideCircle),
                behindSquareLeg: try c.decode(UInt8.self, forKey: .behindSquareLeg)
            )
        case "wicket_recorded":
            self = .wicketRecorded(
                batterId: try c.decode(UUID.self, forKey: .batterId),
                kind: try c.decode(DismissalKind.self, forKey: .kind),
                fielderId: try c.decodeIfPresent(UUID.self, forKey: .fielderId),
                newBatterId: try c.decodeIfPresent(UUID.self, forKey: .newBatterId),
                runs: try c.decodeIfPresent(UInt8.self, forKey: .runs) ?? 0,
                onExtra: try c.decodeIfPresent(Bool.self, forKey: .onExtra) ?? false
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
    /// When the scorer tapped it. The over rate is only tracked for events that
    /// carry one, so an older log still replays without it.
    var at: Date?

    enum CodingKeys: String, CodingKey {
        case clientEventId = "client_event_id"
        case seq, kind, at
    }

    init(clientEventId: UUID, seq: Int64, kind: ScoringEventKind, at: Date? = nil) {
        self.clientEventId = clientEventId
        self.seq = seq
        self.kind = kind
        self.at = at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientEventId = try c.decode(UUID.self, forKey: .clientEventId)
        seq = try c.decode(Int64.self, forKey: .seq)
        kind = try c.decode(ScoringEventKind.self, forKey: .kind)
        at = try c.decodeIfPresent(Date.self, forKey: .at)
    }

    /// Stamped with the clock, which is what makes the over rate measurable.
    static func make(seq: Int64, kind: ScoringEventKind, at: Date? = Date()) -> ScoringEvent {
        ScoringEvent(clientEventId: UUID(), seq: seq, kind: kind, at: at)
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
    /// Off the field hurt, not out, and eligible to resume.
    var retiredHurt: Bool
    var bowlerId: UUID?
    var fielderId: UUID?

    var id: UUID { playerId }

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case runs, balls, fours, sixes, out, dismissal
        case retiredHurt = "retired_hurt"
        case bowlerId = "bowler_id"
        case fielderId = "fielder_id"
    }

    init(playerId: UUID) {
        self.playerId = playerId
        runs = 0; balls = 0; fours = 0; sixes = 0; out = false
        dismissal = nil; retiredHurt = false; bowlerId = nil; fielderId = nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(UUID.self, forKey: .playerId)
        runs = try c.decode(UInt16.self, forKey: .runs)
        balls = try c.decode(UInt16.self, forKey: .balls)
        fours = try c.decode(UInt16.self, forKey: .fours)
        sixes = try c.decode(UInt16.self, forKey: .sixes)
        out = try c.decode(Bool.self, forKey: .out)
        dismissal = try c.decodeIfPresent(DismissalKind.self, forKey: .dismissal)
        retiredHurt = try c.decodeIfPresent(Bool.self, forKey: .retiredHurt) ?? false
        bowlerId = try c.decodeIfPresent(UUID.self, forKey: .bowlerId)
        fielderId = try c.decodeIfPresent(UUID.self, forKey: .fielderId)
    }

    var strikeRate: Double {
        balls == 0 ? 0 : Double(runs) * 100.0 / Double(balls)
    }

    /// Leaves the rest of the order off the card as "did not bat".
    var hasBatted: Bool { balls > 0 || runs > 0 || out || retiredHurt }

    /// Can still come back to the crease.
    var canResume: Bool { retiredHurt && !out }
}

struct BowlerStats: Codable, Equatable, Identifiable {
    var playerId: UUID
    var balls: UInt16
    var runs: UInt16
    var wickets: UInt16
    var maidens: UInt16
    var currentOverRuns: UInt16
    var wides: UInt16
    var noBalls: UInt16

    var id: UUID { playerId }

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case balls, runs, wickets, maidens, wides
        case currentOverRuns = "current_over_runs"
        case noBalls = "no_balls"
    }

    init(playerId: UUID) {
        self.playerId = playerId
        balls = 0; runs = 0; wickets = 0; maidens = 0
        currentOverRuns = 0; wides = 0; noBalls = 0
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(UUID.self, forKey: .playerId)
        balls = try c.decode(UInt16.self, forKey: .balls)
        runs = try c.decode(UInt16.self, forKey: .runs)
        wickets = try c.decode(UInt16.self, forKey: .wickets)
        maidens = try c.decode(UInt16.self, forKey: .maidens)
        currentOverRuns = try c.decodeIfPresent(UInt16.self, forKey: .currentOverRuns) ?? 0
        wides = try c.decodeIfPresent(UInt16.self, forKey: .wides) ?? 0
        noBalls = try c.decodeIfPresent(UInt16.self, forKey: .noBalls) ?? 0
    }

    var oversDisplay: String { "\(balls / 6).\(balls % 6)" }

    var economy: Double {
        balls == 0 ? 0 : Double(runs) * 6.0 / Double(balls)
    }

    /// "4.0-1-22-2", the way a bowling card always reads.
    var figures: String { "\(oversDisplay)-\(maidens)-\(runs)-\(wickets)" }
}

struct FallOfWicket: Codable, Equatable {
    var score: UInt16
    var wickets: UInt8
    var batterId: UUID
    var overBall: String
    var partnershipRuns: UInt16
    var partnershipBalls: UInt16

    enum CodingKeys: String, CodingKey {
        case score, wickets
        case batterId = "batter_id"
        case overBall = "over_ball"
        case partnershipRuns = "partnership_runs"
        case partnershipBalls = "partnership_balls"
    }

    init(
        score: UInt16, wickets: UInt8, batterId: UUID, overBall: String,
        partnershipRuns: UInt16, partnershipBalls: UInt16
    ) {
        self.score = score
        self.wickets = wickets
        self.batterId = batterId
        self.overBall = overBall
        self.partnershipRuns = partnershipRuns
        self.partnershipBalls = partnershipBalls
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        score = try c.decode(UInt16.self, forKey: .score)
        wickets = try c.decode(UInt8.self, forKey: .wickets)
        batterId = try c.decode(UUID.self, forKey: .batterId)
        overBall = try c.decode(String.self, forKey: .overBall)
        partnershipRuns = try c.decodeIfPresent(UInt16.self, forKey: .partnershipRuns) ?? 0
        partnershipBalls = try c.decodeIfPresent(UInt16.self, forKey: .partnershipBalls) ?? 0
    }
}

struct DeliveryRecord: Codable, Equatable, Identifiable {
    var over: UInt16
    var ballInOver: UInt8
    var label: String
    var runs: UInt8
    var isLegal: Bool
    var isWicket: Bool
    /// Who was on strike — the wagon wheel is drawn per batter.
    var batterId: UUID?
    var bowlerId: UUID?
    var shot: ShotRecord?

    var id: String { "\(over).\(ballInOver)-\(label)-\(runs)" }

    enum CodingKeys: String, CodingKey {
        case over, label, runs, shot
        case ballInOver = "ball_in_over"
        case isLegal = "is_legal"
        case isWicket = "is_wicket"
        case batterId = "batter_id"
        case bowlerId = "bowler_id"
    }

    init(
        over: UInt16, ballInOver: UInt8, label: String, runs: UInt8,
        isLegal: Bool, isWicket: Bool,
        batterId: UUID? = nil, bowlerId: UUID? = nil, shot: ShotRecord? = nil
    ) {
        self.over = over
        self.ballInOver = ballInOver
        self.label = label
        self.runs = runs
        self.isLegal = isLegal
        self.isWicket = isWicket
        self.batterId = batterId
        self.bowlerId = bowlerId
        self.shot = shot
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        over = try c.decode(UInt16.self, forKey: .over)
        ballInOver = try c.decode(UInt8.self, forKey: .ballInOver)
        label = try c.decode(String.self, forKey: .label)
        runs = try c.decode(UInt8.self, forKey: .runs)
        isLegal = try c.decode(Bool.self, forKey: .isLegal)
        isWicket = try c.decode(Bool.self, forKey: .isWicket)
        batterId = try c.decodeIfPresent(UUID.self, forKey: .batterId)
        bowlerId = try c.decodeIfPresent(UUID.self, forKey: .bowlerId)
        shot = try c.decodeIfPresent(ShotRecord.self, forKey: .shot)
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
    var wides: UInt16
    var noBalls: UInt16
    var byes: UInt16
    var legByes: UInt16
    var penalties: UInt16
    var partnershipRuns: UInt16
    var partnershipBalls: UInt16
    /// All out at this many wickets — one fewer than the team sheet.
    var wicketsAllowed: UInt8
    /// Overs this innings actually gets, after any weather reduction.
    var oversAvailable: UInt8
    /// Who bowled the over that just finished — nobody bowls two in a row.
    var lastOverBowler: UUID?
    /// The next legal delivery is a free hit: only a run out can get them.
    var freeHit: Bool
    /// One over a side, two wickets, to break a tie.
    var superOver: Bool
    /// Overs of fielding restrictions this innings gets.
    var powerplayOvers: UInt8
    /// Fielders the scorer last recorded outside the circle.
    var fieldersOutside: UInt8?
    var fieldersBehindSquareLeg: UInt8?
    /// Runs added to this innings that nobody scored.
    var penaltyRunsAwarded: UInt16
    /// When the innings started and when the last ball was bowled.
    var startedAt: Date?
    var lastBallAt: Date?

    enum CodingKeys: String, CodingKey {
        case index, batting, bowling, runs, wickets, extras, batters, bowlers
        case fall, deliveries, complete, wides, byes, penalties
        case legalBalls = "legal_balls"
        case strikerId = "striker_id"
        case nonStrikerId = "non_striker_id"
        case bowlerId = "bowler_id"
        case ballsInCurrentOver = "balls_in_current_over"
        case noBalls = "no_balls"
        case legByes = "leg_byes"
        case partnershipRuns = "partnership_runs"
        case partnershipBalls = "partnership_balls"
        case wicketsAllowed = "wickets_allowed"
        case oversAvailable = "overs_available"
        case lastOverBowler = "last_over_bowler"
        case freeHit = "free_hit"
        case superOver = "super_over"
        case powerplayOvers = "powerplay_overs"
        case fieldersOutside = "fielders_outside"
        case fieldersBehindSquareLeg = "fielders_behind_square_leg"
        case penaltyRunsAwarded = "penalty_runs_awarded"
        case startedAt = "started_at"
        case lastBallAt = "last_ball_at"
    }

    init(index: UInt8 = 0, batting: MatchSide = .home, bowling: MatchSide = .away) {
        self.index = index
        self.batting = batting
        self.bowling = bowling
        runs = 0; wickets = 0; legalBalls = 0; extras = 0
        batters = []; bowlers = []; fall = []; deliveries = []
        strikerId = nil; nonStrikerId = nil; bowlerId = nil
        complete = false; ballsInCurrentOver = 0
        wides = 0; noBalls = 0; byes = 0; legByes = 0; penalties = 0
        partnershipRuns = 0; partnershipBalls = 0
        wicketsAllowed = 10
        oversAvailable = 0
        lastOverBowler = nil
        freeHit = false
        superOver = false
        powerplayOvers = 0
        fieldersOutside = nil
        fieldersBehindSquareLeg = nil
        penaltyRunsAwarded = 0
        startedAt = nil
        lastBallAt = nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decode(UInt8.self, forKey: .index)
        batting = try c.decode(MatchSide.self, forKey: .batting)
        bowling = try c.decode(MatchSide.self, forKey: .bowling)
        runs = try c.decode(UInt16.self, forKey: .runs)
        wickets = try c.decode(UInt8.self, forKey: .wickets)
        legalBalls = try c.decode(UInt16.self, forKey: .legalBalls)
        extras = try c.decode(UInt16.self, forKey: .extras)
        batters = try c.decode([BatterStats].self, forKey: .batters)
        bowlers = try c.decode([BowlerStats].self, forKey: .bowlers)
        fall = try c.decode([FallOfWicket].self, forKey: .fall)
        deliveries = try c.decode([DeliveryRecord].self, forKey: .deliveries)
        strikerId = try c.decodeIfPresent(UUID.self, forKey: .strikerId)
        nonStrikerId = try c.decodeIfPresent(UUID.self, forKey: .nonStrikerId)
        bowlerId = try c.decodeIfPresent(UUID.self, forKey: .bowlerId)
        complete = try c.decode(Bool.self, forKey: .complete)
        ballsInCurrentOver = try c.decode(UInt8.self, forKey: .ballsInCurrentOver)
        wides = try c.decodeIfPresent(UInt16.self, forKey: .wides) ?? 0
        noBalls = try c.decodeIfPresent(UInt16.self, forKey: .noBalls) ?? 0
        byes = try c.decodeIfPresent(UInt16.self, forKey: .byes) ?? 0
        legByes = try c.decodeIfPresent(UInt16.self, forKey: .legByes) ?? 0
        penalties = try c.decodeIfPresent(UInt16.self, forKey: .penalties) ?? 0
        partnershipRuns = try c.decodeIfPresent(UInt16.self, forKey: .partnershipRuns) ?? 0
        partnershipBalls = try c.decodeIfPresent(UInt16.self, forKey: .partnershipBalls) ?? 0
        wicketsAllowed = try c.decodeIfPresent(UInt8.self, forKey: .wicketsAllowed) ?? 10
        oversAvailable = try c.decodeIfPresent(UInt8.self, forKey: .oversAvailable) ?? 0
        lastOverBowler = try c.decodeIfPresent(UUID.self, forKey: .lastOverBowler)
        freeHit = try c.decodeIfPresent(Bool.self, forKey: .freeHit) ?? false
        superOver = try c.decodeIfPresent(Bool.self, forKey: .superOver) ?? false
        powerplayOvers = try c.decodeIfPresent(UInt8.self, forKey: .powerplayOvers) ?? 0
        fieldersOutside = try c.decodeIfPresent(UInt8.self, forKey: .fieldersOutside)
        fieldersBehindSquareLeg =
            try c.decodeIfPresent(UInt8.self, forKey: .fieldersBehindSquareLeg)
        penaltyRunsAwarded =
            try c.decodeIfPresent(UInt16.self, forKey: .penaltyRunsAwarded) ?? 0
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        lastBallAt = try c.decodeIfPresent(Date.self, forKey: .lastBallAt)
    }

    /// How long the innings has been going, from the first ball to the last.
    var elapsedMinutes: Int? {
        guard let startedAt, let lastBallAt else { return nil }
        let minutes = Int(lastBallAt.timeIntervalSince(startedAt) / 60)
        return minutes > 0 ? minutes : nil
    }

    /// Overs actually bowled per hour so far.
    var oversPerHour: Double? {
        guard let minutes = elapsedMinutes else { return nil }
        return (Double(legalBalls) / 6.0) * 60.0 / Double(minutes)
    }

    /// Overs behind the clock — negative when they are ahead of it.
    func oversBehind(target: UInt8) -> Double? {
        guard target > 0, let minutes = elapsedMinutes else { return nil }
        let due = Double(minutes) / 60.0 * Double(target)
        return due - Double(legalBalls) / 6.0
    }

    /// What the field breaks, if anything. Empty when it is legal, or when the
    /// scorer has not said where the fielders are.
    func fieldingBreaches(_ conditions: MatchConditions) -> [String] {
        var breaches: [String] = []
        if let outside = fieldersOutside {
            let allowed = conditions.fieldersAllowedOutside(inPowerplay: inPowerplay)
            if outside > allowed {
                breaches.append(
                    "\(outside) outside the circle — \(allowed) allowed"
                        + (inPowerplay ? " in the powerplay" : "")
                )
            }
        }
        if let behind = fieldersBehindSquareLeg,
           behind > conditions.fieldersBehindSquareLeg {
            breaches.append(
                "\(behind) behind square on the leg side — \(conditions.fieldersBehindSquareLeg) allowed"
            )
        }
        return breaches
    }

    /// Inside the fielding restrictions.
    var inPowerplay: Bool {
        powerplayOvers > 0 && legalBalls < UInt16(powerplayOvers) * 6
    }

    /// Overs of powerplay still to come, for the banner.
    var powerplayOversLeft: UInt16 {
        let total = UInt16(powerplayOvers) * 6
        guard total > legalBalls else { return 0 }
        return (total - legalBalls + 5) / 6
    }

    /// Total balls this innings gets, or nil when no limit is recorded. Zero
    /// means "not set", never "no overs left".
    var ballsAllowed: UInt16? {
        oversAvailable == 0 ? nil : UInt16(oversAvailable) * 6
    }

    /// Balls left, given whatever overs this innings ended up with.
    var ballsRemaining: UInt16 {
        guard let total = ballsAllowed else { return 0 }
        return total > legalBalls ? total - legalBalls : 0
    }

    /// Every recorded shot, optionally for one batter — the wagon wheel.
    func shots(for batter: UUID? = nil) -> [DeliveryRecord] {
        deliveries.filter { $0.shot != nil }
            .filter { batter == nil || $0.batterId == batter }
    }

    var oversDisplay: String { "\(legalBalls / 6).\(legalBalls % 6)" }

    var runRate: Double {
        legalBalls == 0 ? 0 : Double(runs) * 6.0 / Double(legalBalls)
    }

    var isAllOut: Bool { wickets >= wicketsAllowed }

    /// The current over's balls, for the strip above the run buttons.
    var currentOverBalls: [DeliveryRecord] {
        let over = legalBalls / 6
        let fromThisOver = deliveries.filter { $0.over == over }
        // A maiden's worth is six entries; extras push it past that.
        return Array(fromThisOver.suffix(10))
    }

    mutating func swapStrike() {
        swap(&strikerId, &nonStrikerId)
    }

    mutating func ensureBowler(_ id: UUID) {
        if !bowlers.contains(where: { $0.playerId == id }) {
            bowlers.append(BowlerStats(playerId: id))
        }
    }

    func batterIndex(_ id: UUID) throws -> Int {
        guard let i = batters.firstIndex(where: { $0.playerId == id }) else {
            throw CricketEngineError.validation("batter not in innings")
        }
        return i
    }

    mutating func bowlerIndex(_ id: UUID) throws -> Int {
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
    var playerOfTheMatch: UUID?
    /// How many super overs it has taken so far.
    var superOvers: UInt8
    /// Penalties awarded to a side that has not batted yet, keyed `home`/`away`.
    var pendingPenalties: [String: UInt16]
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
    /// Keyed by lowercase UUID string: Swift encodes `[UUID: String]` as a flat
    /// array, and Rust writes lowercase keys, so the string form is the one
    /// shape both ends agree on.
    var playerNames: [String: String]
    /// Lower-case UUID strings of the left-handers, so the wheel mirrors.
    var leftHanders: Set<String>
    /// The terms of the game. `oversLimit` mirrors `conditions.oversLimit`.
    var conditions: MatchConditions
    var conditionsProposedBy: MatchSide?
    /// The captain who agreed, by name — the away captain rarely has an account.
    var agreedHome: String?
    var agreedAway: String?
    var officials: MatchOfficials
    var playerOfTheMatch: UUID?
    /// How many super overs it has taken so far.
    var superOvers: UInt8
    /// Penalties awarded to a side that has not batted yet, keyed `home`/`away`.
    var pendingPenalties: [String: UInt16]
    /// Local undo stack — never serialized.
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
        case playerNames = "player_names"
        case leftHanders = "left_handers"
        case conditions
        case conditionsProposedBy = "conditions_proposed_by"
        case agreedHome = "agreed_home"
        case agreedAway = "agreed_away"
        case officials
        case playerOfTheMatch = "player_of_the_match"
        case superOvers = "super_overs"
        case pendingPenalties = "pending_penalties"
    }

    init(oversLimit: UInt8 = 20, homeName: String = "Home", awayName: String = "Away") {
        status = .scheduled
        self.oversLimit = oversLimit
        self.homeName = homeName
        self.awayName = awayName
        tossWinner = nil; tossDecision = nil
        homeXi = []; awayXi = []
        homeCaptain = nil; awayCaptain = nil
        homeKeeper = nil; awayKeeper = nil
        innings = []; target = nil; winner = nil; margin = nil
        lastSeq = 0; playerNames = [:]; leftHanders = []; history = []
        conditions = MatchConditions.standard(overs: oversLimit)
        conditionsProposedBy = nil
        agreedHome = nil
        agreedAway = nil
        officials = MatchOfficials()
        playerOfTheMatch = nil
        superOvers = 0
        pendingPenalties = [:]
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(CricketMatchStatus.self, forKey: .status)
        oversLimit = try c.decode(UInt8.self, forKey: .oversLimit)
        homeName = try c.decode(String.self, forKey: .homeName)
        awayName = try c.decode(String.self, forKey: .awayName)
        tossWinner = try c.decodeIfPresent(MatchSide.self, forKey: .tossWinner)
        tossDecision = try c.decodeIfPresent(TossDecision.self, forKey: .tossDecision)
        homeXi = try c.decodeIfPresent([UUID].self, forKey: .homeXi) ?? []
        awayXi = try c.decodeIfPresent([UUID].self, forKey: .awayXi) ?? []
        homeCaptain = try c.decodeIfPresent(UUID.self, forKey: .homeCaptain)
        awayCaptain = try c.decodeIfPresent(UUID.self, forKey: .awayCaptain)
        homeKeeper = try c.decodeIfPresent(UUID.self, forKey: .homeKeeper)
        awayKeeper = try c.decodeIfPresent(UUID.self, forKey: .awayKeeper)
        innings = try c.decodeIfPresent([InningsState].self, forKey: .innings) ?? []
        target = try c.decodeIfPresent(UInt16.self, forKey: .target)
        winner = try c.decodeIfPresent(MatchSide.self, forKey: .winner)
        margin = try c.decodeIfPresent(String.self, forKey: .margin)
        lastSeq = try c.decodeIfPresent(Int64.self, forKey: .lastSeq) ?? 0
        playerNames = try c.decodeIfPresent([String: String].self, forKey: .playerNames) ?? [:]
        let lefties = try c.decodeIfPresent([String].self, forKey: .leftHanders) ?? []
        leftHanders = Set(lefties.map { $0.lowercased() })
        conditions = try c.decodeIfPresent(MatchConditions.self, forKey: .conditions)
            ?? MatchConditions.standard(overs: oversLimit)
        conditionsProposedBy = try c.decodeIfPresent(MatchSide.self, forKey: .conditionsProposedBy)
        agreedHome = try c.decodeIfPresent(String.self, forKey: .agreedHome)
        agreedAway = try c.decodeIfPresent(String.self, forKey: .agreedAway)
        officials = try c.decodeIfPresent(MatchOfficials.self, forKey: .officials)
            ?? MatchOfficials()
        playerOfTheMatch = try c.decodeIfPresent(UUID.self, forKey: .playerOfTheMatch)
        superOvers = try c.decodeIfPresent(UInt8.self, forKey: .superOvers) ?? 0
        pendingPenalties =
            try c.decodeIfPresent([String: UInt16].self, forKey: .pendingPenalties) ?? [:]
        history = []
    }

    // MARK: Names

    static func nameKey(_ id: UUID) -> String { id.uuidString.lowercased() }

    func name(for id: UUID) -> String {
        playerNames[Self.nameKey(id)] ?? String(id.uuidString.prefix(8))
    }

    mutating func setName(_ name: String, for id: UUID) {
        playerNames[Self.nameKey(id)] = name
    }

    func players(for side: MatchSide) -> [MatchPlayer] {
        xi(side).map {
            MatchPlayer(id: $0, name: name(for: $0), batsLeft: batsLeft($0))
        }
    }

    /// Both captains have signed off the terms, so the game can start.
    var conditionsAgreed: Bool { agreedHome != nil && agreedAway != nil }

    /// Penalties waiting for a side that has not batted yet.
    func pendingPenalty(_ side: MatchSide) -> UInt16 {
        pendingPenalties[side.rawValue] ?? 0
    }

    /// The scores are level and the match is over: it needs a super over.
    var needsASuperOver: Bool {
        status == .complete && winner == nil && innings.count >= 2 && innings.count % 2 == 0
    }

    /// Which side bats first in the super over: whoever batted second last.
    var superOverFirstBatting: MatchSide? { innings.last?.batting }

    /// Anyone appointed to stand or to score — they may score the match.
    func isOfficial(_ id: UUID) -> Bool {
        officials.umpires.contains { $0.id == id } || officials.scorers.contains { $0.id == id }
    }

    /// Which side still has to agree, for the screen that chases them.
    var awaitingAgreement: [MatchSide] {
        var waiting: [MatchSide] = []
        if agreedHome == nil { waiting.append(.home) }
        if agreedAway == nil { waiting.append(.away) }
        return waiting
    }

    func agreedName(_ side: MatchSide) -> String? {
        side == .home ? agreedHome : agreedAway
    }

    /// Overs this bowler may still send down, or nil when there is no limit.
    func oversLeftForBowler(_ bowler: UUID) -> UInt8? {
        guard conditions.oversPerBowler > 0 else { return nil }
        let bowled = currentInnings?.bowlers
            .first { $0.playerId == bowler }
            .map { UInt8($0.balls / 6) } ?? 0
        return conditions.oversPerBowler > bowled ? conditions.oversPerBowler - bowled : 0
    }

    /// Why this bowler cannot come on, if they cannot.
    func bowlerUnavailableReason(_ bowler: UUID) -> String? {
        guard let inn = currentInnings else { return nil }
        if inn.lastOverBowler == bowler && xi(inn.bowling).count > 1 {
            return "bowled the last over"
        }
        if let left = oversLeftForBowler(bowler), left == 0 {
            return "has bowled their \(conditions.oversPerBowler) overs"
        }
        return nil
    }

    func batsLeft(_ id: UUID) -> Bool {
        leftHanders.contains(Self.nameKey(id))
    }

    mutating func setBatsLeft(_ left: Bool, for id: UUID) {
        if left {
            leftHanders.insert(Self.nameKey(id))
        } else {
            leftHanders.remove(Self.nameKey(id))
        }
    }

    /// Where a shot went, named the way the batter's own field is laid out.
    func region(for delivery: DeliveryRecord) -> String? {
        guard let shot = delivery.shot else { return nil }
        let left = delivery.batterId.map { batsLeft($0) } ?? false
        return cricketRegion(angle: shot.angle, batsLeft: left)
    }

    func xi(_ side: MatchSide) -> [UUID] {
        side == .home ? homeXi : awayXi
    }

    func name(for side: MatchSide) -> String {
        side == .home ? homeName : awayName
    }

    // MARK: Derived

    var currentInnings: InningsState? { innings.last }

    static func oversBallsDisplay(_ legalBalls: UInt16) -> String {
        "\(legalBalls / 6).\(legalBalls % 6)"
    }

    var currentRunRate: Double { currentInnings?.runRate ?? 0 }

    var ballsRemaining: UInt16? {
        currentInnings?.ballsRemaining
    }

    var runsNeeded: UInt16? {
        guard let target, let inn = currentInnings, inn.index >= 1 else { return nil }
        return target > inn.runs ? target - inn.runs : 0
    }

    var requiredRunRate: Double? {
        guard let needed = runsNeeded, let remaining = ballsRemaining else { return nil }
        guard remaining > 0 else { return 0 }
        return Double(needed) * 6.0 / Double(remaining)
    }

    /// "Hemel need 42 from 30 balls" — the line every scoreboard carries.
    var chaseLine: String? {
        guard let inn = currentInnings, inn.index >= 1, !inn.complete,
              let needed = runsNeeded, let remaining = ballsRemaining
        else { return nil }
        return "\(name(for: inn.batting)) need \(needed) from \(remaining) ball\(remaining == 1 ? "" : "s")"
    }

    /// "c Smith b Jones", "run out (Patel)", "not out".
    func dismissalText(_ batter: BatterStats) -> String {
        if batter.retiredHurt && !batter.out { return "retired hurt" }
        guard batter.out else { return batter.hasBatted ? "not out" : "did not bat" }
        let bowler = batter.bowlerId.map { name(for: $0) }
        let fielder = batter.fielderId.map { name(for: $0) }
        switch batter.dismissal {
        case .bowled:
            return bowler.map { "b \($0)" } ?? "bowled"
        case .caught:
            if let f = fielder, let b = bowler { return "c \(f) b \(b)" }
            if let b = bowler { return "c & b \(b)" }
            return "caught"
        case .lbw:
            return bowler.map { "lbw b \($0)" } ?? "lbw"
        case .stumped:
            if let f = fielder, let b = bowler { return "st \(f) b \(b)" }
            if let b = bowler { return "st b \(b)" }
            return "stumped"
        case .hitWicket:
            return bowler.map { "hit wicket b \($0)" } ?? "hit wicket"
        case .runOut:
            return fielder.map { "run out (\($0))" } ?? "run out"
        case .retired:
            return "retired out"
        case .retiredHurt:
            return "retired hurt"
        case .other, nil:
            return "out"
        }
    }

    func scoreLine() -> String {
        guard let inn = currentInnings else {
            return "\(homeName) v \(awayName)"
        }
        return "\(name(for: inn.batting)) \(inn.runs)/\(inn.wickets) (\(inn.oversDisplay))"
    }
}

/// Where the chase stands on Duckworth–Lewis–Stern.
struct DlsPar: Codable, Equatable {
    let par: Int
    let aheadBy: Int
    let target: Int
    let resourcesFirst: Double
    let resourcesSecond: Double
    let resourcesUsed: Double
    /// `standard_approximation` | `supplied_table`
    let method: String
    let usedG50: Bool

    enum CodingKeys: String, CodingKey {
        case par, target, method
        case aheadBy = "ahead_by"
        case resourcesFirst = "resources_first"
        case resourcesSecond = "resources_second"
        case resourcesUsed = "resources_used"
        case usedG50 = "used_g50"
    }

    var methodLabel: String {
        method == "supplied_table"
            ? "DLS (supplied resource table)"
            : "DLS (Standard Edition approximation)"
    }

    /// "12 ahead of the DLS par of 84".
    var summary: String {
        if aheadBy == 0 { return "Level with the DLS par of \(par)" }
        return aheadBy > 0
            ? "\(aheadBy) ahead of the DLS par of \(par)"
            : "\(-aheadBy) behind the DLS par of \(par)"
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
    let activeScorerDeviceId: String?
    let canScore: Bool
    let dls: DlsPar?
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
        case activeScorerDeviceId = "active_scorer_device_id"
        case canScore = "can_score"
        case dls
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        eventId = try c.decode(UUID.self, forKey: .eventId)
        clubId = try c.decode(UUID.self, forKey: .clubId)
        status = try c.decode(String.self, forKey: .status)
        oversLimit = try c.decode(Int.self, forKey: .oversLimit)
        homeName = try c.decode(String.self, forKey: .homeName)
        awayName = try c.decode(String.self, forKey: .awayName)
        lastSeq = try c.decode(Int64.self, forKey: .lastSeq)
        activeScorerUserId = try c.decodeIfPresent(UUID.self, forKey: .activeScorerUserId)
        activeScorerDeviceId = try c.decodeIfPresent(String.self, forKey: .activeScorerDeviceId)
        canScore = try c.decodeIfPresent(Bool.self, forKey: .canScore) ?? false
        dls = try c.decodeIfPresent(DlsPar.self, forKey: .dls)
        state = try c.decode(MatchState.self, forKey: .state)
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

/// Response from `POST /cricket/matches/{id}/share`.
struct ScoreboardShareResponse: Codable, Equatable {
    let token: String
    let url: String
    let expiresAt: Date
    let conversationId: UUID?
    let messageId: UUID?

    enum CodingKeys: String, CodingKey {
        case token, url
        case expiresAt = "expires_at"
        case conversationId = "conversation_id"
        case messageId = "message_id"
    }
}

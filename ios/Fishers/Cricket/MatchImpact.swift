import Foundation

/// Who had the biggest game — the shortlist behind the player of the match.
///
/// Nobody in cricket *computes* this award. An adjudicator — a former player,
/// a commentator, one of the umpires at club level — watches the game and
/// picks. What they are weighing, though, is the scorecard, so the app does
/// the weighing and leaves the picking to whoever was there. The scorer still
/// taps the name; they just no longer have to hold twenty-two performances in
/// their head to do it.
///
/// Mirrors `backend/domain/src/cricket/impact.rs`. Where the two disagree the
/// Rust is right — but the numbers have to match, because the scorer sees this
/// list offline and the server's copy of it once they sync.

/// A wicket, in the runs club scoring has always valued it at.
private let wicketWorth = 20.0
private let maidenWorth = 8.0
private let catchWorth = 8.0
private let stumpingWorth = 10.0
private let runOutWorth = 8.0

/// The winning side's edge. An adjudicator nearly always picks from the
/// winners, so this is enough to break a near-tie that way — and deliberately
/// not enough to beat a real performance in a losing side, which is the one
/// case where the human overrules the list anyway.
private let winnerEdge = 1.1

/// Milestones an adjudicator notices. The highest one only — a hundred does
/// not also collect the fifty.
private func milestone(_ runs: UInt16) -> Double {
    switch runs {
    case 100...: return 40
    case 50..<100: return 20
    case 30..<50: return 8
    default: return 0
    }
}

private func haul(_ wickets: UInt16) -> Double {
    switch wickets {
    case 5...: return 25
    case 3..<5: return 10
    default: return 0
    }
}

/// One player's match, scored. Enough to rank the list and to say why.
struct PlayerImpact: Identifiable, Equatable {
    let playerId: UUID
    let name: String
    let side: MatchSide
    /// Higher is better. Runs-flavoured, but not runs — do not put it on a
    /// scorecard as if it were one.
    let score: Double
    /// "75* (45) · 2-18 (4.0) · 1 ct" — why they are on the list.
    let line: String

    var id: UUID { playerId }
}

/// Running totals for one player across every innings of the match.
private struct Tally {
    var runs: UInt16 = 0
    var balls: UInt16 = 0
    var fours: UInt16 = 0
    var sixes: UInt16 = 0
    var notOut = false
    var wickets: UInt16 = 0
    var conceded: UInt16 = 0
    var bowled: UInt16 = 0
    var maidens: UInt16 = 0
    var catches: UInt16 = 0
    var stumpings: UInt16 = 0
    var runOuts: UInt16 = 0

    var didSomething: Bool {
        balls > 0 || runs > 0 || bowled > 0 || catches + stumpings + runOuts > 0
    }

    func score(par: Double) -> Double {
        // Both halves fall to zero on their own for a player who did not bat
        // or did not bowl, so neither needs a guard.
        let batting = Double(runs)
            + Double(fours)
            + 2 * Double(sixes)
            + milestone(runs)
            + (Double(runs) - Double(balls) * par)
        let bowling = Double(wickets) * wicketWorth
            + Double(maidens) * maidenWorth
            + haul(wickets)
            + (Double(bowled) * par - Double(conceded))
        let fielding = Double(catches) * catchWorth
            + Double(stumpings) * stumpingWorth
            + Double(runOuts) * runOutWorth
        return batting + bowling + fielding
    }

    var line: String {
        var parts: [String] = []
        if balls > 0 || runs > 0 {
            parts.append("\(runs)\(notOut ? "*" : "") (\(balls))")
        }
        if bowled > 0 {
            parts.append("\(wickets)-\(conceded) (\(MatchState.oversBallsDisplay(bowled)))")
        }
        for (count, label) in [(catches, "ct"), (stumpings, "st"), (runOuts, "ro")] where count > 0 {
            parts.append("\(count) \(label)")
        }
        return parts.joined(separator: " · ")
    }
}

extension MatchState {
    /// Every player who did something, best game first.
    ///
    /// Empty before a ball is bowled. Safe to read at any point in a match —
    /// it is only *shown* at the end, but a leading-performers panel mid-game
    /// would read the same list.
    var impact: [PlayerImpact] {
        // The par rate comes from the match proper. A super over is one over
        // of hitting and would drag it somewhere no normal innings lives.
        let proper = innings.filter { !$0.superOver }
        let balls = proper.reduce(0) { $0 + Int($1.legalBalls) }
        guard balls > 0 else { return [] }
        let par = Double(proper.reduce(0) { $0 + Int($1.runs) }) / Double(balls)

        var tallies: [UUID: Tally] = [:]
        // Contributions count from every innings, super over included — the
        // player who wins it one-handed is exactly who this list is for.
        for inn in innings {
            for bat in inn.batters where bat.hasBatted {
                var t = tallies[bat.playerId] ?? Tally()
                t.runs += bat.runs
                t.balls += bat.balls
                t.fours += bat.fours
                t.sixes += bat.sixes
                t.notOut = t.notOut || !bat.out
                tallies[bat.playerId] = t

                // The fielder is on the other side, so this credits them in
                // their own tally, not the batter's.
                if let fielder = bat.fielderId, let kind = bat.dismissal {
                    var f = tallies[fielder] ?? Tally()
                    switch kind {
                    case .caught: f.catches += 1
                    case .stumped: f.stumpings += 1
                    case .runOut: f.runOuts += 1
                    default: break
                    }
                    tallies[fielder] = f
                }
            }
            for bowl in inn.bowlers {
                var t = tallies[bowl.playerId] ?? Tally()
                t.wickets += bowl.wickets
                t.conceded += bowl.runs
                t.bowled += bowl.balls
                t.maidens += bowl.maidens
                tallies[bowl.playerId] = t
            }
        }

        return tallies
            .filter { $0.value.didSomething }
            .map { playerId, tally in
                let side = self.side(of: playerId)
                var score = tally.score(par: par)
                if score > 0, let side, winner == side { score *= winnerEdge }
                return PlayerImpact(
                    playerId: playerId,
                    name: name(for: playerId),
                    side: side ?? .home,
                    score: score,
                    line: tally.line
                )
            }
            // Name breaks a tie, so a dictionary's order never decides the award.
            .sorted { $0.score == $1.score ? $0.name < $1.name : $0.score > $1.score }
    }

    /// The best game on the losing side — the one who made a contest of it.
    ///
    /// Club cricket gives this award more than the professional game does, and
    /// it is usually the right call: somebody carried their bat through a
    /// collapse, or took four while the other ten watched. Three things have
    /// to hold, or there is no fighter and the app says nothing rather than
    /// inventing one:
    ///
    /// - somebody won, so there is a losing side to pick from;
    /// - they played above the match's own par, because a heavy defeat where
    ///   nobody did anything had no fight in it;
    /// - they are not already the player of the match, since a performance
    ///   that beat everyone on the day does not also need the consolation.
    var fighterOfTheMatch: PlayerImpact? {
        guard let losing = winner?.opposite else { return nil }
        let ranked = impact
        guard let best = ranked.first,
              let fighter = ranked.first(where: { $0.side == losing && $0.score > 0 }),
              fighter.playerId != best.playerId
        else { return nil }
        return fighter
    }

    /// Which team sheet a player is on, if either.
    func side(of playerId: UUID) -> MatchSide? {
        if homeXi.contains(playerId) { return .home }
        if awayXi.contains(playerId) { return .away }
        return nil
    }
}

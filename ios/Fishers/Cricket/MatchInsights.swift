import Foundation

/// What the two sides actually did, side by side.
///
/// The scorecard says who scored what. This says where the game was won: who
/// left more dot balls, who cashed in during the powerplay, whose middle order
/// held. Every figure is read back off the ball-by-ball log, so it all works
/// with no signal — the log is on the device either way.
///
/// Mirrors `backend/domain/src/cricket/insights.rs`. Where the two disagree
/// the Rust is right.

/// Runs and wickets in one stretch of an innings.
struct PhaseScore: Identifiable, Equatable {
    /// "Powerplay", "Middle", "Death".
    let name: String
    /// The overs it covers, as a scorer would say them: "1-6".
    let overs: String
    let runs: UInt16
    let wickets: UInt8
    let balls: UInt16

    var id: String { "\(name)-\(overs)" }

    var runRate: Double {
        balls == 0 ? 0 : Double(runs) * 6.0 / Double(balls)
    }
}

/// One side's innings, totalled every way a post-match chat asks about.
struct SideInsights: Identifiable, Equatable {
    let side: MatchSide
    let name: String
    let runs: UInt16
    let wickets: UInt8
    let balls: UInt16
    let overs: String
    let runRate: Double
    /// Legal deliveries that went for nothing. A wicket off a dot is still a
    /// dot — the batting side got no runs from it either way.
    let dots: UInt16
    let dotPercent: Double
    let fours: UInt16
    let sixes: UInt16
    let boundaryRuns: UInt16
    /// How much of the total came in fours and sixes rather than in ones.
    let boundaryPercent: Double
    let extras: UInt16
    let phases: [PhaseScore]
    /// Runs by where they came in: 1-3, 4-7, and 8 down.
    let topOrder: UInt16
    let middleOrder: UInt16
    let lowerOrder: UInt16
    /// The biggest stand of the innings, broken or not.
    let bestPartnership: UInt16

    var id: MatchSide { side }
}

struct MatchInsights: Equatable {
    let home: SideInsights
    let away: SideInsights

    var both: [SideInsights] { [home, away] }
}

/// Where one innings divides, as 0-indexed over ranges.
///
/// The powerplay is whatever was agreed. The death is the last fifth, which
/// gives four overs of a twenty and ten of a fifty — what everyone already
/// calls it. Anything shorter than ten overs is one passage of play.
private func phaseRanges(_ inn: InningsState) -> [(String, UInt16, UInt16)] {
    let total = inn.oversAvailable > 0
        ? UInt16(inn.oversAvailable)
        : UInt16((Int(inn.legalBalls) + 5) / 6)
    guard total >= 10 else { return [] }
    let powerplay = min(UInt16(inn.powerplayOvers), total)
    let deathLength = max(total / 5, 1)
    let deathStart = max(total - min(deathLength, total), powerplay)

    var out: [(String, UInt16, UInt16)] = []
    if powerplay > 0 { out.append(("Powerplay", 0, powerplay)) }
    if deathStart > powerplay { out.append(("Middle", powerplay, deathStart)) }
    if total > deathStart { out.append(("Death", deathStart, total)) }
    return out
}

extension MatchState {
    /// Both sides totalled up, or nil before the second innings has begun —
    /// there is nothing to compare a side with until someone has replied.
    var insights: MatchInsights? {
        guard let home = sideInsights(.home), let away = sideInsights(.away) else { return nil }
        return MatchInsights(home: home, away: away)
    }

    /// One side's batting, across every innings they batted that was not a
    /// super over — one over of a tie-break belongs in nobody's powerplay.
    func sideInsights(_ side: MatchSide) -> SideInsights? {
        let batted = innings.filter { $0.batting == side && !$0.superOver }
        guard !batted.isEmpty else { return nil }

        var runs: UInt16 = 0, wickets: UInt8 = 0, balls: UInt16 = 0, extras: UInt16 = 0
        var dots: UInt16 = 0, fours: UInt16 = 0, sixes: UInt16 = 0
        var top: UInt16 = 0, middle: UInt16 = 0, lower: UInt16 = 0
        var best: UInt16 = 0
        var phases: [PhaseScore] = []

        for inn in batted {
            runs += inn.runs
            wickets += inn.wickets
            balls += inn.legalBalls
            extras += inn.extras
            dots += UInt16(inn.deliveries.filter { $0.isLegal && $0.runs == 0 }.count)

            for (position, bat) in inn.batters.enumerated() {
                fours += bat.fours
                sixes += bat.sixes
                switch position {
                case 0...2: top += bat.runs
                case 3...6: middle += bat.runs
                default: lower += bat.runs
                }
            }

            // Every stand that ended, plus the one that never did.
            best = max(best, inn.fall.map(\.partnershipRuns).max() ?? 0)
            best = max(best, inn.partnershipRuns)

            for (name, from, to) in phaseRanges(inn) {
                let inPhase = inn.deliveries.filter { $0.over >= from && $0.over < to }
                let runs = inPhase.reduce(UInt16(0)) { $0 + UInt16($1.runs) }
                let balls = UInt16(inPhase.filter(\.isLegal).count)
                // A side bowled out in the eighth over of a twenty never
                // reached the death. Saying "Death 0/0" invites the reader to
                // work out why; leaving the row out says it already.
                guard balls > 0 || runs > 0 else { continue }
                phases.append(PhaseScore(
                    name: name,
                    overs: "\(from + 1)-\(to)",
                    runs: runs,
                    wickets: UInt8(inPhase.filter(\.isWicket).count),
                    balls: balls
                ))
            }
        }

        let boundaryRuns = fours * 4 + sixes * 6
        return SideInsights(
            side: side,
            name: name(for: side),
            runs: runs,
            wickets: wickets,
            balls: balls,
            overs: MatchState.oversBallsDisplay(balls),
            runRate: balls == 0 ? 0 : Double(runs) * 6.0 / Double(balls),
            dots: dots,
            dotPercent: balls == 0 ? 0 : Double(dots) * 100.0 / Double(balls),
            fours: fours,
            sixes: sixes,
            boundaryRuns: boundaryRuns,
            boundaryPercent: runs == 0 ? 0 : Double(boundaryRuns) * 100.0 / Double(runs),
            extras: extras,
            phases: phases,
            topOrder: top,
            middleOrder: middle,
            lowerOrder: lower,
            bestPartnership: best
        )
    }
}

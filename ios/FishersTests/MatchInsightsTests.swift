import XCTest
@testable import Fishers

/// Mirrors `backend/domain/src/cricket/insights.rs` tests. The device works
/// these out from its own ball log with no signal; the server works them out
/// from the same log once it syncs. They must agree.
final class MatchInsightsTests: XCTestCase {

    private func ball(_ over: UInt16, _ runs: UInt8) -> DeliveryRecord {
        DeliveryRecord(
            over: over, ballInOver: 1, label: "\(runs)", runs: runs,
            isLegal: true, isWicket: false
        )
    }

    private func wicket(_ over: UInt16) -> DeliveryRecord {
        DeliveryRecord(
            over: over, ballInOver: 1, label: "W", runs: 0,
            isLegal: true, isWicket: true
        )
    }

    private func bat(_ runs: UInt16, _ fours: UInt16, _ sixes: UInt16) -> BatterStats {
        var b = BatterStats(playerId: UUID())
        b.runs = runs
        b.fours = fours
        b.sixes = sixes
        b.balls = max(runs, 1)
        return b
    }

    /// An innings of `perOver` runs off every ball of every over.
    private func innings(overs: UInt8, powerplay: UInt8, perOver: UInt8) -> InningsState {
        var inn = InningsState(index: 0, batting: .home, bowling: .away)
        for over in 0..<UInt16(overs) {
            for _ in 0..<6 { inn.deliveries.append(ball(over, perOver)) }
        }
        inn.runs = UInt16(overs) * 6 * UInt16(perOver)
        inn.legalBalls = UInt16(overs) * 6
        inn.oversAvailable = overs
        inn.powerplayOvers = powerplay
        inn.complete = true
        return inn
    }

    private func state(_ home: InningsState) -> MatchState {
        var away = home
        away.batting = .away
        away.bowling = .home
        away.index = 1
        away.deliveries = []
        var s = MatchState()
        s.innings = [home, away]
        return s
    }

    func testDotsComeOffTheBallLog() throws {
        var inn = innings(overs: 10, powerplay: 2, perOver: 1)
        for i in 0..<6 { inn.deliveries[i].runs = 0 }
        inn.runs -= 6
        let side = try XCTUnwrap(state(inn).sideInsights(.home))
        XCTAssertEqual(side.dots, 6)
        XCTAssertEqual(side.balls, 60)
        XCTAssertEqual(side.dotPercent, 10.0)
    }

    func testAWicketOffADotIsStillADot() throws {
        var inn = innings(overs: 10, powerplay: 2, perOver: 1)
        inn.deliveries[0] = wicket(0)
        inn.runs -= 1
        let side = try XCTUnwrap(state(inn).sideInsights(.home))
        XCTAssertEqual(side.dots, 1, "the batting side got nothing from it either way")
    }

    func testPhasesSplitTheInningsWhereAScorerWould() throws {
        let side = try XCTUnwrap(state(innings(overs: 20, powerplay: 6, perOver: 1)).sideInsights(.home))
        XCTAssertEqual(
            side.phases.map { [$0.name, $0.overs] },
            [["Powerplay", "1-6"], ["Middle", "7-16"], ["Death", "17-20"]]
        )
        // Every ball lands in exactly one phase.
        XCTAssertEqual(side.phases.reduce(0) { $0 + $1.balls }, side.balls)
        XCTAssertEqual(side.phases.reduce(0) { $0 + $1.runs }, side.runs)
    }

    func testAFiftyOverInningsGetsATenOverDeath() throws {
        let side = try XCTUnwrap(state(innings(overs: 50, powerplay: 10, perOver: 1)).sideInsights(.home))
        XCTAssertEqual(side.phases.last?.name, "Death")
        XCTAssertEqual(side.phases.last?.overs, "41-50")
    }

    func testAShortGameIsAllOnePassageOfPlay() throws {
        let side = try XCTUnwrap(state(innings(overs: 8, powerplay: 2, perOver: 1)).sideInsights(.home))
        XCTAssertTrue(side.phases.isEmpty, "eight overs has no middle to speak of")
    }

    func testRunsAreGroupedByWhereTheBatterCameIn() throws {
        var inn = innings(overs: 20, powerplay: 6, perOver: 0)
        inn.batters = [
            bat(10, 1, 0), bat(20, 2, 0), bat(30, 3, 0),
            bat(40, 0, 1), bat(1, 0, 0), bat(2, 0, 0), bat(3, 0, 0),
            bat(5, 0, 1), bat(6, 0, 0),
        ]
        let side = try XCTUnwrap(state(inn).sideInsights(.home))
        XCTAssertEqual(side.topOrder, 60)
        XCTAssertEqual(side.middleOrder, 46)
        XCTAssertEqual(side.lowerOrder, 11)
        XCTAssertEqual(side.fours, 6)
        XCTAssertEqual(side.sixes, 2)
        XCTAssertEqual(side.boundaryRuns, 6 * 4 + 2 * 6)
    }

    func testTheBestStandCountsTheOneThatNeverEnded() throws {
        var inn = innings(overs: 20, powerplay: 6, perOver: 1)
        inn.fall = [FallOfWicket(
            score: 40, wickets: 1, batterId: UUID(), overBall: "5.2",
            partnershipRuns: 40, partnershipBalls: 32
        )]
        inn.partnershipRuns = 75
        let side = try XCTUnwrap(state(inn).sideInsights(.home))
        XCTAssertEqual(side.bestPartnership, 75)
    }

    func testAnInningsThatEndedEarlyHasNoDeathOvers() throws {
        // Twenty overs available, all out inside eight.
        var inn = innings(overs: 20, powerplay: 6, perOver: 1)
        inn.deliveries.removeAll { $0.over >= 8 }
        inn.legalBalls = 48
        inn.runs = 48
        inn.wickets = 10
        let side = try XCTUnwrap(state(inn).sideInsights(.home))
        XCTAssertEqual(side.phases.map(\.name), ["Powerplay", "Middle"], "they never got to the death")
        XCTAssertEqual(side.phases.reduce(0) { $0 + $1.balls }, side.balls)
    }

    /// Mirrors `the_reply_to_a_super_over_is_still_a_super_over`. Both clients
    /// sent `super_over: false` for the reply, so a one-over decider came back
    /// asking for the whole match allocation and the same side batted twice.
    func testTheReplyToASuperOverGoesToTheOtherSide() {
        var s = MatchState()
        var first = InningsState(index: 0, batting: .home, bowling: .away)
        first.complete = true
        var second = InningsState(index: 1, batting: .away, bowling: .home)
        second.complete = true
        s.innings = [first, second]
        s.status = .complete

        // Whoever batted second opens it — so the same side bats twice
        // running across the join.
        XCTAssertTrue(s.needsASuperOver)
        XCTAssertTrue(s.nextIsSuperOver)
        XCTAssertEqual(s.superOverNextBatting, .away)

        var superFirst = InningsState(index: 2, batting: .away, bowling: .home)
        superFirst.superOver = true
        superFirst.complete = true
        s.innings.append(superFirst)

        // …and then they alternate again.
        XCTAssertTrue(s.nextIsSuperOver, "the reply is part of the same super over")
        XCTAssertEqual(s.superOverNextBatting, .home, "the other side replies")
    }

    func testASideThatNeverBattedHasNothingToShow() {
        XCTAssertNil(MatchState().insights)
    }
}

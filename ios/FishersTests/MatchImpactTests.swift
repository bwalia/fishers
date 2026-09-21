import XCTest
@testable import Fishers

/// Mirrors `backend/domain/src/cricket/impact.rs` tests — the scorer sees this
/// list offline and the server's copy of it once they sync, so the two have to
/// rank the same match the same way.
final class MatchImpactTests: XCTestCase {

    private func bat(_ playerId: UUID, _ runs: UInt16, _ balls: UInt16, out: Bool) -> BatterStats {
        var b = BatterStats(playerId: playerId)
        b.runs = runs
        b.balls = balls
        b.out = out
        return b
    }

    private func bowl(_ playerId: UUID, balls: UInt16, runs: UInt16, wickets: UInt16) -> BowlerStats {
        var b = BowlerStats(playerId: playerId)
        b.balls = balls
        b.runs = runs
        b.wickets = wickets
        return b
    }

    /// A twenty-over game: 150 apiece off 120 balls, so par is 1.25 a ball.
    private func match(_ first: [BatterStats], _ bowlers: [BowlerStats]) -> MatchState {
        var state = MatchState()
        state.homeXi = first.map(\.playerId)
        state.awayXi = bowlers.map(\.playerId)

        var one = InningsState(index: 0, batting: .home, bowling: .away)
        one.runs = 150
        one.legalBalls = 120
        one.batters = first
        one.bowlers = bowlers
        one.complete = true

        var two = InningsState(index: 1, batting: .away, bowling: .home)
        two.runs = 150
        two.legalBalls = 120
        two.complete = true

        state.innings = [one, two]
        state.status = .complete
        return state
    }

    func testTheBiggestGameTopsTheList() {
        let opener = UUID(), plodder = UUID(), seamer = UUID()
        let state = match(
            [bat(opener, 75, 45, out: true), bat(plodder, 30, 50, out: true)],
            [bowl(seamer, balls: 24, runs: 20, wickets: 3)]
        )

        let list = state.impact
        XCTAssertEqual(list.first?.playerId, opener, "75 off 45 is the game")
        let seamerRank = list.firstIndex { $0.playerId == seamer }
        let plodderRank = list.firstIndex { $0.playerId == plodder }
        XCTAssertLessThan(seamerRank!, plodderRank!, "3-20 off four beats 30 off 50")
        XCTAssertEqual(list.first?.line, "75 (45)")
    }

    func testTempoSeparatesTwoInningsOfTheSameSize() {
        let quick = UUID(), slow = UUID()
        let state = match([bat(quick, 50, 30, out: true), bat(slow, 50, 60, out: true)], [])
        let list = state.impact
        XCTAssertEqual(list.first?.playerId, quick)
        XCTAssertGreaterThan(list[0].score, list[1].score, "same runs, fewer balls, higher score")
    }

    func testTheWinningSideGetsTheBenefitOfATie() {
        let home = UUID(), away = UUID()
        var state = match([bat(home, 50, 40, out: true)], [])
        // The same innings for the other side, so only the result separates them.
        state.awayXi = [away]
        state.innings[1].batters = [bat(away, 50, 40, out: true)]
        state.winner = .away

        XCTAssertEqual(state.impact.first?.playerId, away, "level performances, the winner")
    }

    func testACatchIsWorthSomethingAndReadsOnTheLine() {
        let keeper = UUID(), batter = UUID()
        var out = bat(batter, 10, 10, out: true)
        out.dismissal = .caught
        out.fielderId = keeper
        var state = match([out], [])
        state.awayXi = [keeper]

        let fielder = state.impact.first { $0.playerId == keeper }
        XCTAssertEqual(fielder?.line, "1 ct")
        XCTAssertGreaterThan(fielder?.score ?? 0, 0)
    }

    func testTheFighterIsTheBestGameInTheLosingSide() throws {
        let winner = UUID(), loser = UUID(), alsoran = UUID()
        var state = match([], [])
        state.homeXi = [loser, alsoran]
        state.innings[0].batters = [bat(loser, 80, 50, out: true), bat(alsoran, 2, 9, out: true)]
        state.awayXi = [winner]
        state.innings[1].batters = [bat(winner, 95, 55, out: false)]
        state.winner = .away

        let fighter = try XCTUnwrap(state.fighterOfTheMatch, "somebody made a game of it")
        XCTAssertEqual(fighter.playerId, loser)
        XCTAssertEqual(fighter.side, .home)
        XCTAssertNotEqual(
            fighter.playerId, state.impact.first?.playerId,
            "the fighter is never also the player of the match"
        )
    }

    func testNoFighterWhenTheLosingSideHadTheBestGameAnyway() {
        let hero = UUID(), winner = UUID()
        var state = match([], [])
        state.homeXi = [hero]
        state.awayXi = [winner]
        // A hundred in a losing cause still tops the whole list, so it is the
        // award itself, not the consolation.
        state.innings[0].batters = [bat(hero, 140, 60, out: false)]
        state.innings[1].batters = [bat(winner, 20, 18, out: true)]
        state.winner = .away

        XCTAssertEqual(state.impact.first?.playerId, hero)
        XCTAssertNil(state.fighterOfTheMatch)
    }

    func testNoFighterWithoutAResult() {
        let state = match([bat(UUID(), 50, 30, out: true)], [])
        XCTAssertNil(state.winner)
        XCTAssertNil(state.fighterOfTheMatch, "a tie has no losing side")
    }

    func testNothingBowledMeansNothingToRank() {
        XCTAssertTrue(MatchState().impact.isEmpty)
    }
}

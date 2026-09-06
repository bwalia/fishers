import XCTest
@testable import Fishers

/// Mirrors `backend/domain/src/cricket/engine.rs` tests — the two engines must
/// agree, because the device scores with one and the API replays with the other.
final class CricketEngineTests: XCTestCase {

    // MARK: Fixture

    private func team(_ prefix: String, _ size: Int = 11) -> [MatchPlayer] {
        (0..<size).map { MatchPlayer(name: "\(prefix) \($0)") }
    }

    private struct Fixture {
        var state = MatchState()
        var home: [MatchPlayer]
        var away: [MatchPlayer]
        var seq: Int64 = 0

        mutating func push(_ kind: ScoringEventKind) throws {
            seq += 1
            try state.apply(.make(seq: seq, kind: kind))
        }

        mutating func runs(_ runs: UInt8) throws {
            try push(.deliveryRecorded(
                runs: runs, isLegal: true,
                isBoundaryFour: runs == 4, isBoundarySix: runs == 6,
                shot: nil
            ))
        }

        var innings: InningsState { state.currentInnings! }
    }

    private func fixture(overs: UInt8 = 20, size: Int = 11) throws -> Fixture {
        var f = Fixture(home: team("Home", size), away: team("Away", size))
        try f.push(.matchPrepared(oversLimit: overs, homeName: "Lords", awayName: "Hemel"))
        try f.push(.conditionsProposed(
            conditions: MatchConditions.standard(overs: overs),
            by: .home,
            byName: "Home captain"
        ))
        try f.push(.conditionsAgreed(side: .away, captainName: "Away captain"))
        try f.push(.tossRecorded(winner: .home, decision: .bat))
        try f.push(.xiSelected(
            side: .home, players: f.home, captainId: f.home[0].id, keeperId: f.home[1].id
        ))
        try f.push(.xiSelected(
            side: .away, players: f.away, captainId: f.away[0].id, keeperId: f.away[1].id
        ))
        try f.push(.inningsStarted(
            inningsIndex: 0, batting: .home,
            strikerId: f.home[0].id, nonStrikerId: f.home[1].id, bowlerId: f.away[0].id
        ))
        return f
    }

    // MARK: Scoring

    func testFourUpdatesScoreAndBatter() throws {
        var f = try fixture()
        try f.runs(4)
        XCTAssertEqual(f.innings.runs, 4)
        XCTAssertEqual(f.innings.legalBalls, 1)
        let batter = f.innings.batters.first { $0.playerId == f.home[0].id }
        XCTAssertEqual(batter?.runs, 4)
        XCTAssertEqual(batter?.fours, 1)
    }

    func testOddRunRotatesStrike() throws {
        var f = try fixture()
        try f.runs(1)
        XCTAssertEqual(f.innings.strikerId, f.home[1].id)
    }

    func testOverCompletionSwapsStrikeAndBanksAMaiden() throws {
        var f = try fixture()
        let striker = f.innings.strikerId
        for _ in 0..<6 { try f.runs(0) }
        XCTAssertEqual(f.innings.ballsInCurrentOver, 0)
        XCTAssertEqual(f.innings.legalBalls, 6)
        XCTAssertNotEqual(f.innings.strikerId, striker)
        XCTAssertEqual(f.innings.bowlers[0].maidens, 1)
    }

    // MARK: Extras

    func testWideCostsARunButNotABall() throws {
        var f = try fixture()
        try f.push(.extrasRecorded(kind: .wide, runs: 0, boundary: false, offTheBat: false, shot: nil))
        XCTAssertEqual(f.innings.runs, 1)
        XCTAssertEqual(f.innings.legalBalls, 0)
        XCTAssertEqual(f.innings.wides, 1)
        XCTAssertEqual(f.innings.extras, 1)
        XCTAssertEqual(f.innings.bowlers[0].wides, 1)
    }

    func testNoBallWithRunsOffTheBatSplitsTheCredit() throws {
        var f = try fixture()
        let striker = f.innings.strikerId!
        try f.push(.extrasRecorded(kind: .noBall, runs: 4, boundary: true, offTheBat: true, shot: nil))
        XCTAssertEqual(f.innings.runs, 5)
        XCTAssertEqual(f.innings.extras, 1, "only the no ball itself is an extra")
        XCTAssertEqual(f.innings.noBalls, 1)
        XCTAssertEqual(f.innings.batters.first { $0.playerId == striker }?.runs, 4)
    }

    func testByesDoNotGoAgainstTheBowler() throws {
        var f = try fixture()
        try f.push(.extrasRecorded(kind: .bye, runs: 2, boundary: false, offTheBat: false, shot: nil))
        XCTAssertEqual(f.innings.runs, 2)
        XCTAssertEqual(f.innings.byes, 2)
        XCTAssertEqual(f.innings.legalBalls, 1)
        XCTAssertEqual(f.innings.bowlers[0].runs, 0)
    }

    // MARK: Wickets

    func testCaughtCreditsTheBowlerAndReadsAsAScorecardLine() throws {
        var f = try fixture()
        let striker = f.innings.strikerId!
        try f.push(.wicketRecorded(
            batterId: striker, kind: .caught,
            fielderId: f.away[3].id, newBatterId: f.home[2].id, runs: 0
        ))
        XCTAssertEqual(f.innings.wickets, 1)
        XCTAssertEqual(f.innings.bowlers[0].wickets, 1)
        let out = f.innings.batters.first { $0.playerId == striker }!
        XCTAssertEqual(f.state.dismissalText(out), "c Away 3 b Away 0")
        XCTAssertEqual(f.innings.strikerId, f.home[2].id)
    }

    func testRunOutTakesTheNonStrikerAndSparesTheBowler() throws {
        var f = try fixture()
        let nonStriker = f.innings.nonStrikerId!
        try f.push(.wicketRecorded(
            batterId: nonStriker, kind: .runOut,
            fielderId: f.away[4].id, newBatterId: f.home[2].id, runs: 1
        ))
        XCTAssertEqual(f.innings.wickets, 1)
        XCTAssertEqual(f.innings.bowlers[0].wickets, 0, "run outs are not the bowler's")
        XCTAssertEqual(f.innings.runs, 1, "the completed run still counts")
        let out = f.innings.batters.first { $0.playerId == nonStriker }!
        XCTAssertEqual(f.state.dismissalText(out), "run out (Away 4)")
        XCTAssertTrue(
            f.innings.strikerId == f.home[2].id || f.innings.nonStrikerId == f.home[2].id,
            "the replacement is at the crease"
        )
    }

    func testFallOfWicketRecordsThePartnership() throws {
        var f = try fixture()
        try f.runs(2)
        try f.runs(4)
        let striker = f.innings.strikerId!
        try f.push(.wicketRecorded(
            batterId: striker, kind: .bowled,
            fielderId: nil, newBatterId: f.home[2].id, runs: 0
        ))
        let fall = f.innings.fall[0]
        XCTAssertEqual(fall.score, 6)
        XCTAssertEqual(fall.wickets, 1)
        XCTAssertEqual(fall.partnershipRuns, 6)
        XCTAssertEqual(fall.partnershipBalls, 3)
        XCTAssertEqual(f.innings.partnershipRuns, 0, "a new stand starts at zero")
    }

    func testAShortSideIsAllOutEarly() throws {
        var f = try fixture(size: 3)
        XCTAssertEqual(f.innings.wicketsAllowed, 2)
        try f.push(.wicketRecorded(
            batterId: f.home[0].id, kind: .bowled,
            fielderId: nil, newBatterId: f.home[2].id, runs: 0
        ))
        try f.push(.wicketRecorded(
            batterId: f.home[1].id, kind: .bowled,
            fielderId: nil, newBatterId: nil, runs: 0
        ))
        XCTAssertTrue(f.innings.complete, "three players, two wickets")
    }

    // MARK: Undo

    func testUndoRevertsTheLastBall() throws {
        var f = try fixture(overs: 5)
        try f.runs(6)
        XCTAssertEqual(f.innings.runs, 6)
        try f.push(.undoLast)
        XCTAssertEqual(f.innings.runs, 0)
    }

    func testUndoSurvivesAReplayOfTheLog() throws {
        // The bug this guards: state restored from a stored snapshot has an
        // empty undo stack, so a synced undo failed and jammed the queue.
        let home = team("Home")
        let away = team("Away")
        let log: [ScoringEvent] = [
            .make(seq: 1, kind: .matchPrepared(oversLimit: 5, homeName: "Lords", awayName: "Hemel")),
            .make(seq: 2, kind: .xiSelected(side: .home, players: home, captainId: nil, keeperId: nil)),
            .make(seq: 3, kind: .xiSelected(side: .away, players: away, captainId: nil, keeperId: nil)),
            .make(seq: 4, kind: .inningsStarted(
                inningsIndex: 0, batting: .home,
                strikerId: home[0].id, nonStrikerId: home[1].id, bowlerId: away[0].id
            )),
            .make(seq: 5, kind: .deliveryRecorded(
                runs: 4, isLegal: true, isBoundaryFour: true, isBoundarySix: false, shot: nil
            )),
            .make(seq: 6, kind: .deliveryRecorded(
                runs: 2, isLegal: true, isBoundaryFour: false, isBoundarySix: false, shot: nil
            )),
        ]

        let before = try MatchState.replay(log)
        XCTAssertEqual(before.currentInnings?.runs, 6)

        let after = try MatchState.replay(log + [.make(seq: 7, kind: .undoLast)])
        XCTAssertEqual(after.currentInnings?.runs, 4, "an undo after a reload must still undo")
        XCTAssertEqual(after.lastSeq, 7)
    }

    // MARK: Results

    func testChasingSideWinsByWickets() throws {
        var f = try fixture(overs: 2)
        try f.runs(4)
        try f.push(.inningsCompleted)
        XCTAssertEqual(f.state.target, 5)
        try f.push(.inningsStarted(
            inningsIndex: 1, batting: .away,
            strikerId: f.away[0].id, nonStrikerId: f.away[1].id, bowlerId: f.home[0].id
        ))
        try f.runs(6)
        XCTAssertEqual(f.state.status, .complete)
        XCTAssertEqual(f.state.winner, .away)
        let margin = try XCTUnwrap(f.state.margin)
        XCTAssertTrue(margin.hasPrefix("Hemel won by 10 wickets"), margin)
        XCTAssertTrue(margin.contains("balls remaining"), margin)
    }

    func testDefendingSideWinsByRuns() throws {
        var f = try fixture(overs: 1)
        for _ in 0..<6 { try f.runs(2) }
        try f.push(.inningsStarted(
            inningsIndex: 1, batting: .away,
            strikerId: f.away[0].id, nonStrikerId: f.away[1].id, bowlerId: f.home[0].id
        ))
        for _ in 0..<6 { try f.runs(1) }
        XCTAssertEqual(f.state.status, .complete)
        XCTAssertEqual(f.state.winner, .home)
        XCTAssertEqual(f.state.margin, "Lords won by 6 runs")
    }

    func testScoresLevelIsATie() throws {
        var f = try fixture(overs: 1)
        for _ in 0..<6 { try f.runs(1) }
        try f.push(.inningsStarted(
            inningsIndex: 1, batting: .away,
            strikerId: f.away[0].id, nonStrikerId: f.away[1].id, bowlerId: f.home[0].id
        ))
        for _ in 0..<6 { try f.runs(1) }
        XCTAssertEqual(f.state.margin, "Match tied")
        XCTAssertNil(f.state.winner)
    }

    func testChaseLineReadsLikeAScoreboard() throws {
        var f = try fixture(overs: 2)
        try f.runs(4)
        try f.push(.inningsCompleted)
        try f.push(.inningsStarted(
            inningsIndex: 1, batting: .away,
            strikerId: f.away[0].id, nonStrikerId: f.away[1].id, bowlerId: f.home[0].id
        ))
        try f.runs(2)
        XCTAssertEqual(f.state.chaseLine, "Hemel need 3 from 11 balls")
    }

    // MARK: Conditions the captains agree

    func testTossNeedsBothCaptainsToAgreeFirst() throws {
        var state = MatchState()
        var seq: Int64 = 0
        func push(_ kind: ScoringEventKind) throws {
            seq += 1
            try state.apply(.make(seq: seq, kind: kind))
        }

        try push(.matchPrepared(oversLimit: 20, homeName: "Lords", awayName: "Hemel"))
        XCTAssertThrowsError(try push(.tossRecorded(winner: .home, decision: .bat)))

        seq -= 1
        try push(.conditionsProposed(
            conditions: MatchConditions(
                oversLimit: 30, oversPerBowler: 6, ground: .boxed, ball: .tennis
            ),
            by: .home,
            byName: "Ravi"
        ))
        XCTAssertEqual(state.agreedHome, "Ravi", "proposing is agreeing")
        XCTAssertNil(state.agreedAway)
        XCTAssertFalse(state.conditionsAgreed)
        XCTAssertEqual(state.awaitingAgreement, [.away])
        XCTAssertThrowsError(try push(.tossRecorded(winner: .home, decision: .bat)))

        seq -= 1
        try push(.conditionsAgreed(side: .away, captainName: "Sam"))
        XCTAssertTrue(state.conditionsAgreed)
        XCTAssertEqual(state.status, .toss)
        XCTAssertEqual(state.conditions.ground, .boxed)
        XCTAssertEqual(state.conditions.ball, .tennis)
        XCTAssertEqual(state.conditions.oversLimit, 30)

        try push(.tossRecorded(winner: .home, decision: .bat))
        XCTAssertEqual(state.status, .selectingXi)
    }

    func testChangingTheTermsNeedsAgreeingAgain() throws {
        var f = try fixture()
        XCTAssertTrue(f.state.conditionsAgreed)
        try f.push(.conditionsProposed(
            conditions: MatchConditions.standard(overs: 10), by: .away, byName: "Sam"
        ))
        XCTAssertFalse(f.state.conditionsAgreed)
        XCTAssertEqual(f.state.awaitingAgreement, [.home])
    }

    func testStandardAllocationIsAFifthOfTheInnings() {
        XCTAssertEqual(MatchConditions.standardOversPerBowler(20), 4)
        XCTAssertEqual(MatchConditions.standardOversPerBowler(50), 10)
        XCTAssertEqual(MatchConditions.standardOversPerBowler(12), 3)
        XCTAssertEqual(MatchConditions.standardOversPerBowler(1), 1)
    }

    func testConditionsSummaryReadsLikeAScorecardHeader() {
        let conditions = MatchConditions(
            oversLimit: 20, oversPerBowler: 4, ground: .boxed, ball: .tape
        )
        XCTAssertEqual(
            conditions.summary,
            "20 overs · 4 per bowler · tape ball · boxed / caged"
        )
    }

    // MARK: The bowling Laws

    func testNobodyBowlsTwoOversInARow() throws {
        var f = try fixture()
        let opener = try XCTUnwrap(f.innings.bowlerId)
        for _ in 0..<6 { try f.runs(0) }
        XCTAssertEqual(f.innings.lastOverBowler, opener)
        XCTAssertEqual(f.state.bowlerUnavailableReason(opener), "bowled the last over")
        XCTAssertThrowsError(try f.push(.bowlerChanged(bowlerId: opener)))

        f.seq -= 1
        try f.push(.bowlerChanged(bowlerId: f.away[1].id))
        for _ in 0..<6 { try f.runs(0) }
        try f.push(.bowlerChanged(bowlerId: opener))
        XCTAssertEqual(f.innings.bowlerId, opener)
    }

    func testABowlerCannotExceedTheAgreedAllocation() throws {
        var f = try fixture(overs: 5)
        try f.push(.conditionsProposed(
            conditions: MatchConditions(
                oversLimit: 5, oversPerBowler: 1, ground: .open, ball: .white
            ),
            by: .home, byName: "Ravi"
        ))
        try f.push(.conditionsAgreed(side: .away, captainName: "Sam"))

        let opener = try XCTUnwrap(f.innings.bowlerId)
        for _ in 0..<6 { try f.runs(0) }
        XCTAssertEqual(f.state.oversLeftForBowler(opener), 0)
        try f.push(.bowlerChanged(bowlerId: f.away[1].id))
        for _ in 0..<6 { try f.runs(0) }
        XCTAssertThrowsError(try f.push(.bowlerChanged(bowlerId: opener)))
        XCTAssertEqual(
            f.state.bowlerUnavailableReason(opener),
            "has bowled their 1 overs"
        )
    }

    func testNoAllocationMeansNoLimit() throws {
        var f = try fixture(overs: 6)
        try f.push(.conditionsProposed(
            conditions: MatchConditions(
                oversLimit: 6, oversPerBowler: 0, ground: .boxed, ball: .tennis
            ),
            by: .home, byName: "Ravi"
        ))
        try f.push(.conditionsAgreed(side: .away, captainName: "Sam"))
        let a = try XCTUnwrap(f.innings.bowlerId)
        let b = f.away[1].id
        XCTAssertNil(f.state.oversLeftForBowler(a), "no limit to report")
        for _ in 0..<2 {
            for _ in 0..<6 { try f.runs(0) }
            try f.push(.bowlerChanged(bowlerId: b))
            for _ in 0..<6 { try f.runs(0) }
            try f.push(.bowlerChanged(bowlerId: a))
        }
        XCTAssertNil(f.state.bowlerUnavailableReason(a))
    }

    func testAnInningsWithNoRecordedOversDoesNotCloseItself() throws {
        var f = try fixture()
        f.state.innings[0].oversAvailable = 0
        try f.runs(1)
        XCTAssertFalse(f.innings.complete, "zero means unknown, not finished")
        XCTAssertNil(f.innings.ballsAllowed)
    }

    // MARK: Extras that carry runs

    private func extras(
        _ kind: ExtraKind, _ runs: UInt8,
        boundary: Bool = false, offTheBat: Bool = false
    ) -> ScoringEventKind {
        .extrasRecorded(
            kind: kind, runs: runs, boundary: boundary, offTheBat: offTheBat, shot: nil
        )
    }

    func testWideTheyRanASingleOffIsTwo() throws {
        var f = try fixture()
        let striker = try XCTUnwrap(f.innings.strikerId)
        try f.push(extras(.wide, 1))
        XCTAssertEqual(f.innings.runs, 2, "one for the wide, one run")
        XCTAssertEqual(f.innings.wides, 2)
        XCTAssertEqual(f.innings.legalBalls, 0)
        XCTAssertEqual(f.innings.bowlers[0].runs, 2)
        XCTAssertEqual(f.innings.batters.first { $0.playerId == striker }?.balls, 0)
        XCTAssertNotEqual(f.innings.strikerId, striker, "an odd run rotates strike")
    }

    func testWideToTheBoundaryIsFive() throws {
        var f = try fixture()
        let striker = try XCTUnwrap(f.innings.strikerId)
        try f.push(extras(.wide, 4, boundary: true))
        XCTAssertEqual(f.innings.runs, 5)
        XCTAssertEqual(f.innings.wides, 5)
        XCTAssertEqual(f.innings.strikerId, striker, "a boundary does not rotate")
    }

    func testNoBallHitForSixGivesTheBatterTheSix() throws {
        var f = try fixture()
        let striker = try XCTUnwrap(f.innings.strikerId)
        try f.push(extras(.noBall, 6, boundary: true, offTheBat: true))
        XCTAssertEqual(f.innings.runs, 7)
        XCTAssertEqual(f.innings.extras, 1, "only the no ball is an extra")
        let batter = f.innings.batters.first { $0.playerId == striker }
        XCTAssertEqual(batter?.runs, 6)
        XCTAssertEqual(batter?.sixes, 1)
        XCTAssertEqual(batter?.balls, 1)
        XCTAssertEqual(f.innings.bowlers[0].runs, 7)
    }

    func testByesOffANoBallAreNotTheBowlersFault() throws {
        var f = try fixture()
        try f.push(extras(.noBall, 2))
        XCTAssertEqual(f.innings.runs, 3)
        XCTAssertEqual(f.innings.noBalls, 1)
        XCTAssertEqual(f.innings.byes, 2)
        XCTAssertEqual(f.innings.bowlers[0].runs, 1, "only the no ball is charged")
    }

    func testWidesDoNotEndTheOver() throws {
        var f = try fixture(overs: 1)
        for _ in 0..<5 { try f.push(extras(.wide, 0)) }
        XCTAssertEqual(f.innings.legalBalls, 0)
        XCTAssertFalse(f.innings.complete)
        XCTAssertEqual(f.innings.runs, 5)
    }

    // MARK: Wagon wheel

    func testAShotIsKeptAgainstTheBatterWhoPlayedIt() throws {
        var f = try fixture()
        let striker = try XCTUnwrap(f.innings.strikerId)
        try f.push(.deliveryRecorded(
            runs: 4, isLegal: true, isBoundaryFour: true, isBoundarySix: false,
            shot: ShotRecord(angle: 280, kind: .drive, reach: 1.0)
        ))
        let shots = f.innings.shots(for: striker)
        XCTAssertEqual(shots.count, 1)
        XCTAssertEqual(shots[0].shot?.kind, .drive)
        XCTAssertEqual(f.state.region(for: shots[0]), "cover")
    }

    func testTheFieldMirrorsForALeftHander() {
        XCTAssertEqual(cricketRegion(angle: 280, batsLeft: false), "cover")
        XCTAssertEqual(cricketRegion(angle: 280, batsLeft: true), "mid-wicket")
        XCTAssertEqual(cricketRegion(angle: 50, batsLeft: false), "mid-wicket")
        XCTAssertEqual(cricketRegion(angle: 50, batsLeft: true), "cover")
        for angle in stride(from: UInt16(0), to: UInt16(360), by: 7) {
            XCTAssertFalse(cricketRegion(angle: angle, batsLeft: false).isEmpty)
        }
    }

    func testCommentaryReadsLikeCommentary() throws {
        var f = try fixture()
        try f.push(.deliveryRecorded(
            runs: 4, isLegal: true, isBoundaryFour: true, isBoundarySix: false,
            shot: ShotRecord(angle: 280, kind: .drive, reach: 1.0)
        ))
        let delivery = try XCTUnwrap(f.innings.deliveries.last)
        let line = CricketCommentary.line(for: delivery, in: f.state, innings: f.innings)
        XCTAssertTrue(line.contains("FOUR"), line)
        XCTAssertTrue(line.contains("driven"), line)
        XCTAssertTrue(line.contains("cover"), line)
        XCTAssertTrue(line.contains("Away 0 to Home 0"), line)
    }

    func testCommentaryNamesAWideWithRuns() throws {
        var f = try fixture()
        try f.push(extras(.wide, 2))
        let delivery = try XCTUnwrap(f.innings.deliveries.last)
        let line = CricketCommentary.line(for: delivery, in: f.state, innings: f.innings)
        XCTAssertTrue(line.contains("wide"), line)
    }

    // MARK: Rain and DLS

    func testRevisedOversShortenTheInnings() throws {
        var f = try fixture(overs: 20)
        try f.runs(1)
        try f.push(.oversRevised(inningsIndex: 0, overs: 10))
        XCTAssertEqual(f.innings.oversAvailable, 10)
        XCTAssertEqual(f.innings.ballsRemaining, 59)
    }

    func testOversCannotBeCutBelowWhatHasBeenBowled() throws {
        var f = try fixture(overs: 20)
        for _ in 0..<12 { try f.runs(0) }
        XCTAssertThrowsError(try f.push(.oversRevised(inningsIndex: 0, overs: 1)))
    }

    func testDlsParStartsAtZeroAndClimbs() throws {
        var f = try fixture(overs: 20)
        for _ in 0..<6 { try f.runs(4) }
        try f.push(.inningsCompleted)
        try f.push(.inningsStarted(
            inningsIndex: 1, batting: .away,
            strikerId: f.away[0].id, nonStrikerId: f.away[1].id, bowlerId: f.home[0].id
        ))
        let start = try XCTUnwrap(f.state.dlsPar)
        XCTAssertEqual(start.par, 0, "no resources used yet")

        for _ in 0..<6 { try f.runs(1) }
        let later = try XCTUnwrap(f.state.dlsPar)
        XCTAssertGreaterThan(later.par, start.par, "par climbs as overs go")
        XCTAssertEqual(later.aheadBy, 6 - later.par)
        XCTAssertTrue(later.summary.contains("DLS par"), later.summary)
    }

    func testDlsMatchesTheServerFormula() {
        // The published Standard Edition zero-wicket column, to a tenth.
        for (overs, published) in [(5.0, 17.2), (20.0, 56.6), (30.0, 75.1), (50.0, 100.0)] {
            let got = CricketDLS.resource(overs: overs, wickets: 0)
            XCTAssertEqual(got, published, accuracy: 0.15, "\(overs) overs")
        }
        XCTAssertEqual(CricketDLS.resource(overs: 0, wickets: 0), 0)
        XCTAssertEqual(CricketDLS.resource(overs: 20, wickets: 10), 0)
        for w in 0..<9 {
            XCTAssertGreaterThan(
                CricketDLS.resource(overs: 30, wickets: w),
                CricketDLS.resource(overs: 30, wickets: w + 1)
            )
        }
    }

    func testAShortenedChaseNeedsLess() throws {
        var f = try fixture(overs: 20)
        for _ in 0..<12 { try f.runs(3) }
        try f.push(.inningsCompleted)
        try f.push(.inningsStarted(
            inningsIndex: 1, batting: .away,
            strikerId: f.away[0].id, nonStrikerId: f.away[1].id, bowlerId: f.home[0].id
        ))
        let full = try XCTUnwrap(f.state.dlsPar)
        try f.push(.oversRevised(inningsIndex: 1, overs: 10))
        let shortened = try XCTUnwrap(f.state.dlsPar)
        XCTAssertLessThan(shortened.target, full.target)
    }

    // MARK: Names and wire format

    func testNamesTravelWithTheTeamSheet() throws {
        let f = try fixture()
        XCTAssertEqual(f.state.name(for: f.home[0].id), "Home 0")
        XCTAssertEqual(f.state.name(for: f.away[5].id), "Away 5")
    }

    /// Rust writes lowercase UUID keys; Swift's `uuidString` is uppercase. The
    /// lookup has to survive the round trip either way.
    func testPlayerNamesSurviveTheWireRoundTrip() throws {
        let f = try fixture()
        let data = try JSONEncoder().encode(f.state)
        let decoded = try JSONDecoder().decode(MatchState.self, from: data)
        XCTAssertEqual(decoded.name(for: f.home[3].id), "Home 3")

        // And a lowercase-keyed payload, as the API sends it.
        let id = UUID()
        let json = """
        {"status":"live","overs_limit":20,"home_name":"A","away_name":"B",
         "home_xi":[],"away_xi":[],"innings":[],"last_seq":0,
         "player_names":{"\(id.uuidString.lowercased())":"Alice"}}
        """.data(using: .utf8)!
        let fromServer = try JSONDecoder().decode(MatchState.self, from: json)
        XCTAssertEqual(fromServer.name(for: id), "Alice")
    }

    func testEventEncodesTheTaggedWireShape() throws {
        let event = ScoringEvent.make(
            seq: 1,
            kind: .wicketRecorded(
                batterId: UUID(), kind: .runOut,
                fielderId: UUID(), newBatterId: UUID(), runs: 1
            )
        )
        let data = try JSONEncoder().encode(event)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let kind = try XCTUnwrap(object["kind"] as? [String: Any])
        XCTAssertEqual(kind["type"] as? String, "wicket_recorded")
        XCTAssertEqual(kind["runs"] as? Int, 1)
        XCTAssertNotNil(kind["new_batter_id"])

        let round = try JSONDecoder().decode(ScoringEvent.self, from: data)
        XCTAssertEqual(round, event)
    }
}

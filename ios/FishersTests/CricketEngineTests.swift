import XCTest
@testable import Fishers

final class CricketEngineTests: XCTestCase {
    private func xi() -> [UUID] { (0..<11).map { _ in UUID() } }

    private func prepared() throws -> MatchState {
        var s = MatchState()
        let home = xi()
        let away = xi()
        try s.apply(.make(seq: 1, kind: .matchPrepared(oversLimit: 2, homeName: "Lords", awayName: "Away")))
        try s.apply(.make(seq: 2, kind: .tossRecorded(winner: .home, decision: .bat)))
        try s.apply(.make(seq: 3, kind: .xiSelected(side: .home, playerIds: home, captainId: home[0], keeperId: home[1])))
        try s.apply(.make(seq: 4, kind: .xiSelected(side: .away, playerIds: away, captainId: away[0], keeperId: away[1])))
        try s.apply(.make(seq: 5, kind: .inningsStarted(
            inningsIndex: 0, batting: .home,
            strikerId: home[0], nonStrikerId: home[1], bowlerId: away[0]
        )))
        s.homeXi = home
        s.awayXi = away
        return s
    }

    func testDeliveryAndBoundary() throws {
        var s = try prepared()
        try s.apply(.make(seq: 6, kind: .deliveryRecorded(runs: 4, isLegal: true, isBoundaryFour: true, isBoundarySix: false)))
        XCTAssertEqual(s.currentInnings?.runs, 4)
        XCTAssertEqual(s.currentInnings?.batters.first?.fours, 1)
        XCTAssertEqual(s.currentInnings?.legalBalls, 1)
    }

    func testWideDoesNotCountLegalBall() throws {
        var s = try prepared()
        try s.apply(.make(seq: 6, kind: .extrasRecorded(kind: .wide, runs: 1)))
        XCTAssertEqual(s.currentInnings?.runs, 1)
        XCTAssertEqual(s.currentInnings?.legalBalls, 0)
        XCTAssertEqual(s.currentInnings?.extras, 1)
    }

    func testUndoRestores() throws {
        var s = try prepared()
        try s.apply(.make(seq: 6, kind: .deliveryRecorded(runs: 6, isLegal: true, isBoundaryFour: false, isBoundarySix: true)))
        try s.apply(.make(seq: 7, kind: .undoLast))
        XCTAssertEqual(s.currentInnings?.runs, 0)
        XCTAssertEqual(s.lastSeq, 7)
    }

    func testOverCompletionSwapsStrike() throws {
        var s = try prepared()
        let striker = s.currentInnings!.strikerId!
        for i in 0..<6 {
            try s.apply(.make(
                seq: Int64(6 + i),
                kind: .deliveryRecorded(runs: 0, isLegal: true, isBoundaryFour: false, isBoundarySix: false)
            ))
        }
        XCTAssertEqual(s.currentInnings?.ballsInCurrentOver, 0)
        XCTAssertEqual(s.currentInnings?.legalBalls, 6)
        // After maiden over, strike swaps at over end.
        XCTAssertNotEqual(s.currentInnings?.strikerId, striker)
    }
}

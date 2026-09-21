import XCTest
@testable import Fishers

/// The vote card decodes a shape the API flattens — the poll's own fields sit
/// beside the ballot rather than under a key of their own — so a plain
/// `Codable` synthesis would have quietly produced an empty card.
final class ManOfTheMatchTests: XCTestCase {
    private func decode(_ json: String) throws -> MotmPollView {
        try FishersJSONDecoder.make().decode(MotmPollView.self, from: Data(json.utf8))
    }

    private let openPoll = """
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "club_id": "22222222-2222-2222-2222-222222222222",
      "event_id": "33333333-3333-3333-3333-333333333333",
      "match_id": "44444444-4444-4444-4444-444444444444",
      "conversation_id": "55555555-5555-5555-5555-555555555555",
      "message_id": null,
      "title": "Hemel Hempstead vs Chesham",
      "status": "open",
      "closes_at": "2999-01-01T12:00:00Z",
      "winner_user_id": null,
      "created_at": "2026-09-21T17:00:00Z",
      "closed_at": null,
      "candidates": [
        {"user_id": "aaaaaaaa-0000-0000-0000-000000000001", "display_name": "Stokes", "side": "home", "votes": 0},
        {"user_id": "aaaaaaaa-0000-0000-0000-000000000002", "display_name": "Cummins", "side": "away", "votes": 0}
      ],
      "my_vote": null,
      "total_votes": 3,
      "tally_visible": false,
      "can_vote": true,
      "scorer_award_user_id": "aaaaaaaa-0000-0000-0000-000000000002"
    }
    """

    func testTheFlattenedPollIsDecodedAlongsideTheBallot() throws {
        let view = try decode(openPoll)
        XCTAssertEqual(view.poll.title, "Hemel Hempstead vs Chesham")
        XCTAssertEqual(view.poll.status, "open")
        XCTAssertTrue(view.poll.isOpen)
        XCTAssertEqual(view.candidates.count, 2)
        XCTAssertEqual(view.totalVotes, 3)
        XCTAssertTrue(view.canVote)
        XCTAssertNil(view.myVote)
    }

    /// Both team sheets go on the ballot: a man of the match is quite often
    /// the opposition's opening bowler.
    func testTheBallotSplitsIntoTwoTeamSheets() throws {
        let sheets = try decode(openPoll).byHomeAndAway
        XCTAssertEqual(sheets.home.map(\.displayName), ["Stokes"])
        XCTAssertEqual(sheets.away.map(\.displayName), ["Cummins"])
    }

    /// The scorer's own award travels with the poll so the card can show the
    /// two side by side rather than letting a club vote look like it overruled
    /// the person scoring.
    func testTheScorersPickIsCarriedSeparately() throws {
        let view = try decode(openPoll)
        XCTAssertEqual(view.scorerAwardUserId?.uuidString.lowercased(),
                       "aaaaaaaa-0000-0000-0000-000000000002")
        XCTAssertNil(view.poll.winnerUserId)
    }

    /// A poll whose closing time has passed is over, whatever its status
    /// column still says — the sweeper runs every quarter of an hour, so
    /// there is always a window where the two disagree.
    func testAPollPastItsTimeReadsAsClosed() throws {
        let stale = openPoll.replacingOccurrences(
            of: "\"closes_at\": \"2999-01-01T12:00:00Z\"",
            with: "\"closes_at\": \"2020-01-01T12:00:00Z\""
        )
        XCTAssertFalse(try decode(stale).poll.isOpen)
    }

    func testAClosedPollNamesItsWinner() throws {
        let closed = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "club_id": "22222222-2222-2222-2222-222222222222",
          "event_id": "33333333-3333-3333-3333-333333333333",
          "match_id": null,
          "conversation_id": null,
          "message_id": null,
          "title": "Hemel vs Chesham",
          "status": "closed",
          "closes_at": "2026-09-23T17:00:00Z",
          "winner_user_id": "aaaaaaaa-0000-0000-0000-000000000001",
          "created_at": "2026-09-21T17:00:00Z",
          "closed_at": "2026-09-23T17:00:00Z",
          "candidates": [
            {"user_id": "aaaaaaaa-0000-0000-0000-000000000001", "display_name": "Stokes", "side": "home", "votes": 7},
            {"user_id": "aaaaaaaa-0000-0000-0000-000000000002", "display_name": "Cummins", "side": "away", "votes": 2}
          ],
          "my_vote": "aaaaaaaa-0000-0000-0000-000000000001",
          "total_votes": 9,
          "tally_visible": true,
          "can_vote": false,
          "scorer_award_user_id": null
        }
        """
        let view = try decode(closed)
        XCTAssertFalse(view.poll.isOpen)
        XCTAssertEqual(view.winner?.displayName, "Stokes")
        XCTAssertEqual(view.winner?.votes, 7)
        XCTAssertTrue(view.tiedAtTheTop.isEmpty)
        XCTAssertFalse(view.canVote)
    }

    /// A tie closes with no winner recorded — a captain picks between them —
    /// and the card has to name everybody who was level.
    func testATieNamesEverybodyLevelAtTheTop() throws {
        let tied = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "club_id": "22222222-2222-2222-2222-222222222222",
          "event_id": "33333333-3333-3333-3333-333333333333",
          "match_id": null,
          "conversation_id": null,
          "message_id": null,
          "title": "Hemel vs Chesham",
          "status": "closed",
          "closes_at": "2026-09-23T17:00:00Z",
          "winner_user_id": null,
          "created_at": "2026-09-21T17:00:00Z",
          "closed_at": "2026-09-23T17:00:00Z",
          "candidates": [
            {"user_id": "aaaaaaaa-0000-0000-0000-000000000001", "display_name": "Stokes", "side": "home", "votes": 4},
            {"user_id": "aaaaaaaa-0000-0000-0000-000000000002", "display_name": "Cummins", "side": "away", "votes": 4},
            {"user_id": "aaaaaaaa-0000-0000-0000-000000000003", "display_name": "Root", "side": "home", "votes": 1}
          ],
          "my_vote": null,
          "total_votes": 9,
          "tally_visible": true,
          "can_vote": false,
          "scorer_award_user_id": null
        }
        """
        let view = try decode(tied)
        XCTAssertNil(view.winner)
        XCTAssertEqual(view.tiedAtTheTop.map(\.displayName).sorted(), ["Cummins", "Stokes"])
    }

    /// Only the message that *opened* the vote draws a card. The result
    /// message carries the same id, and honouring both would put two
    /// identical cards in the thread.
    func testOnlyTheOpeningMessageCarriesACard() throws {
        func message(kind: String) throws -> ChatMessage {
            let json = """
            {
              "id": "66666666-6666-6666-6666-666666666666",
              "conversation_id": "55555555-5555-5555-5555-555555555555",
              "sender_id": null,
              "sender_name": null,
              "kind": "system",
              "body": "…",
              "metadata": {"kind": "\(kind)", "motm_poll_id": "11111111-1111-1111-1111-111111111111"},
              "created_at": "2026-09-21T17:00:00Z"
            }
            """
            return try FishersJSONDecoder.make().decode(ChatMessage.self, from: Data(json.utf8))
        }

        XCTAssertEqual(try message(kind: "motm_poll").motmPollId?.uuidString.lowercased(),
                       "11111111-1111-1111-1111-111111111111")
        XCTAssertNil(try message(kind: "motm_result").motmPollId)
        XCTAssertNil(try message(kind: "scoreboard_share").motmPollId)
    }
}

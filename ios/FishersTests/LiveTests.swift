import XCTest
@testable import Fishers

/// The live stream's reader, the alerts it feeds, and the celebrations a new
/// ball can set off.
final class LiveTests: XCTestCase {

    // MARK: The wire format

    private func parse(_ text: String) -> [LiveEvent] {
        var parser = LiveEventParser()
        return text.components(separatedBy: "\n").compactMap { parser.feed($0) }
    }

    func testReadsEachEventTheServerSends() {
        let conversation = UUID()
        let message = UUID()
        let match = UUID()
        let events = parse("""
        event: ready
        data: {}

        :

        event: message
        data: {"conversation_id":"\(conversation.uuidString.lowercased())","id":"\(message.uuidString.lowercased())"}

        event: notification
        data: {}

        event: conversations
        data: {}

        event: match
        data: {"id":"\(match.uuidString.lowercased())","seq":42}

        event: resync
        data: {}

        """)
        XCTAssertEqual(events, [
            .resync,
            .message(conversationId: conversation, id: message),
            .notification,
            .conversations,
            .match(id: match, seq: 42),
            .resync,
        ])
    }

    func testSkipsWhatItDoesNotUnderstand() {
        XCTAssertEqual(parse("event: something_new\ndata: {}\n\n"), [], "a newer server's event is ignored")
        XCTAssertEqual(parse("event: notification\n\n"), [], "no data, no event")
        XCTAssertEqual(parse("event: match\ndata: {\"seq\":1}\n\n"), [], "a match with no id says nothing")
        XCTAssertEqual(parse(": keep-alive\n\n"), [])
        // Nothing carries over from an event that did not finish into the next.
        XCTAssertEqual(parse("event: message\ndata: not json\n\nevent: notification\ndata:{}\n\n"), [.notification])
    }

    // MARK: Notifications

    private let decoder = FishersJSONDecoder.make()

    private func notification(_ type: String, _ payload: String) throws -> AppNotification {
        try decoder.decode(AppNotification.self, from: Data("""
        {"id":"\(UUID().uuidString)","type":"\(type)","payload":\(payload),
         "sent_at":"2026-09-14T08:00:00.123Z","read_at":null}
        """.utf8))
    }

    func testNullsInThePayloadDoNotSinkTheRow() throws {
        let invite = try notification("invite", """
        {"invite_id":"x","club_name":"Boom Blast","team_name":null,"event_title":null,
         "inviter":"Sam","url":"/","tag":"invite:x","n":3}
        """)
        XCTAssertEqual(invite.line, "Boom Blast wants you in the club. Sam invited you.")
        XCTAssertEqual(invite.payload["n"], "3")
        XCTAssertNil(invite.payload["team_name"])

        let team = try notification("invite", #"{"club_name":"Boom Blast","team_name":"2nd XI"}"#)
        XCTAssertEqual(team.line, "Boom Blast wants you in their 2nd XI.")
    }

    func testEveryKindReadsAsASentence() throws {
        let event = UUID()
        let fixture = try notification("fixture_scheduled", """
        {"event_id":"\(event.uuidString)","title":"Boom v Bust","start_at":"2026-09-20T13:00:00Z"}
        """)
        XCTAssertEqual(fixture.line, "Boom v Bust — can you play?")
        XCTAssertEqual(fixture.eventId, event, "a tap opens the fixture")
        XCTAssertNotNil(fixture.when)

        XCTAssertEqual(
            try notification("player_responded", #"{"player":"Ali","title":"Boom v Bust"}"#).line,
            "Ali answered for Boom v Bust."
        )
        XCTAssertEqual(
            try notification("match_book_handed_over", #"{"home_name":"Boom","away_name":"Bust"}"#).line,
            "Boom v Bust — you have the book. You're scoring from the next ball."
        )
        XCTAssertEqual(
            try notification("invite_accepted", #"{"player":"Ali","club_name":"Boom Blast","team_name":null}"#).line,
            "Ali accepted — they're in Boom Blast."
        )
        XCTAssertEqual(
            try notification("profile_nudge", #"{"percent":35,"url":"/profile"}"#).line,
            "Finish your profile — you're 35% there. Captains pick players they can see."
        )
        XCTAssertEqual(try notification("brand_new_kind", "{}").line, "brand new kind")
    }

    // MARK: Moments

    private struct Match {
        var state = MatchState()
        let home = (0..<11).map { MatchPlayer(name: "Home \($0)") }
        let away = (0..<11).map { MatchPlayer(name: "Away \($0)") }
        var seq: Int64 = 0

        mutating func push(_ kind: ScoringEventKind) throws {
            seq += 1
            try state.apply(.make(seq: seq, kind: kind))
        }

        mutating func ball(_ runs: UInt8, four: Bool = false, six: Bool = false) throws {
            try push(.deliveryRecorded(runs: runs, isLegal: true, isBoundaryFour: four, isBoundarySix: six, shot: nil))
        }

        static func started() throws -> Match {
            var m = Match()
            try m.push(.matchPrepared(oversLimit: 20, homeName: "Boom", awayName: "Bust"))
            try m.push(.conditionsProposed(conditions: .standard(overs: 20), by: .home, byName: "H"))
            try m.push(.conditionsAgreed(side: .away, captainName: "A"))
            try m.push(.tossRecorded(winner: .home, decision: .bat))
            try m.push(.xiSelected(side: .home, players: m.home, captainId: nil, keeperId: nil))
            try m.push(.xiSelected(side: .away, players: m.away, captainId: nil, keeperId: nil))
            try m.push(.inningsStarted(
                inningsIndex: 0, batting: .home,
                strikerId: m.home[0].id, nonStrikerId: m.home[1].id, bowlerId: m.away[0].id
            ))
            return m
        }
    }

    func testBoundariesAndWicketsAreCelebrated() throws {
        var m = try Match.started()
        var before = m.state
        try m.ball(4, four: true)
        XCTAssertEqual(Moment.between(before, m.state), Moment(kind: .four, who: "Home 0"))

        before = m.state
        try m.ball(6, six: true)
        XCTAssertEqual(Moment.between(before, m.state)?.kind, .six)

        before = m.state
        try m.push(.wicketRecorded(
            batterId: m.home[0].id, kind: .bowled, fielderId: nil,
            newBatterId: m.home[2].id, runs: 0, onExtra: false
        ))
        let out = Moment.between(before, m.state)
        XCTAssertEqual(out?.kind, .wicket)
        XCTAssertEqual(out?.who, "Home 0")
        XCTAssertEqual(out?.detail, "b Away 0")
    }

    func testOnlyANewBoundaryBallCounts() throws {
        var m = try Match.started()
        var before = m.state
        try m.ball(4)
        XCTAssertNil(Moment.between(before, m.state), "four run, not a boundary")

        try m.ball(4, four: true)
        before = m.state
        try m.push(.undoLast)
        XCTAssertNil(Moment.between(before, m.state), "an undo is not a celebration")

        XCTAssertNil(Moment.between(MatchState(), m.state), "a first load is not either")
    }
}

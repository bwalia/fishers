import XCTest
@testable import Fishers

/// Reporting and blocking are the two things Apple requires of an app that
/// carries other people's words, so the parts that cross the wire are pinned
/// rather than trusted.
///
/// The raw values matter more than usual here: the API parses these exact
/// strings and answers 422 on anything else. A renamed case would compile, and
/// would fail only on a real phone against a real server.
final class ModerationTests: XCTestCase {
    func testEveryReasonSendsTheStringTheApiParses() {
        XCTAssertEqual(
            ReportReason.allCases.map(\.rawValue),
            ["abuse", "objectionable", "spam", "impersonation", "privacy", "other"]
        )
    }

    func testEverySubjectKindSendsTheStringTheApiParses() {
        XCTAssertEqual(ReportSubjectKind.message.rawValue, "message")
        XCTAssertEqual(ReportSubjectKind.listing.rawValue, "listing")
        XCTAssertEqual(ReportSubjectKind.user.rawValue, "user")
        XCTAssertEqual(ReportSubjectKind.club.rawValue, "club")
    }

    /// Each reason has a sentence rather than its own raw value showing
    /// through. `label` reading as the key, or as the bare enum case, is what
    /// a missing dictionary entry looks like on screen.
    func testEveryReasonReadsAsASentence() {
        for reason in ReportReason.allCases {
            let label = reason.label
            XCTAssertFalse(label.isEmpty, "\(reason) has no label")
            XCTAssertFalse(label.hasPrefix("mod."), "\(reason) shows its key: \(label)")
            XCTAssertNotEqual(label, reason.rawValue, "\(reason) shows its raw value")
        }
    }

    /// Each reason points at its own dictionary key.
    ///
    /// The switch in `label` is written out by hand; the key here is computed
    /// from `rawValue`. Two independent derivations of the same mapping, so
    /// `.abuse` quietly wired to `mod.reason_spam` fails here — which reading
    /// the switch back against itself would not catch.
    func testEveryReasonPointsAtItsOwnKey() {
        for reason in ReportReason.allCases {
            XCTAssertEqual(
                reason.label,
                Strings.t("mod.reason_\(reason.rawValue)", language: Strings.current),
                "\(reason) is pointed at the wrong key"
            )
        }
    }

    /// And in Punjabi. An entry identical in both languages is one nobody
    /// translated — invisible in English, which is how a whole class of this
    /// got shipped before.
    func testEveryReasonIsTranslated() {
        for reason in ReportReason.allCases {
            let key = "mod.reason_\(reason.rawValue)"
            let english = Strings.t(key, language: .en)
            let punjabi = Strings.t(key, language: .pa)

            XCTAssertNotEqual(punjabi, key, "\(key) has no Punjabi entry at all")
            XCTAssertNotEqual(english, punjabi, "\(key) is the same in both languages")
            XCTAssertTrue(
                punjabi.unicodeScalars.contains { (0x0A00...0x0A7F).contains($0.value) },
                "\(key) has no Gurmukhi in it: \(punjabi)"
            )
        }
    }

    /// `GET /me/blocks` — the snake_case keys are the server's, so the
    /// mapping is pinned to a real response shape.
    func testBlockedUserDecodesTheApiPayload() throws {
        let payload = """
        [
          {
            "id": "2f1c7a5e-1b64-4f0b-9f1e-5d4a3c2b1a09",
            "name": "Sukhi Dhaliwal",
            "avatar_url": null,
            "blocked_at": "2026-10-28T09:15:00Z"
          }
        ]
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let blocked = try decoder.decode([BlockedUser].self, from: payload)

        XCTAssertEqual(blocked.count, 1)
        XCTAssertEqual(blocked[0].name, "Sukhi Dhaliwal")
        XCTAssertNil(blocked[0].avatarUrl)
    }
}

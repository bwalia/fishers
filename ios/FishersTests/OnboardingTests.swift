import XCTest
@testable import Fishers

/// The getting-started guide and the pieces it is built from.
///
/// The guide decides what a new account is told to do next, from real state.
/// Getting a rule wrong does not crash anything — it quietly tells a secretary
/// their club is set up when it is not — so the rules are pinned here.
final class OnboardingTests: XCTestCase {
    private let decoder = FishersJSONDecoder.make()

    private func user(verified: Bool = false, intent: String? = nil, complete: Bool = true) throws -> PublicUser {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"Sam Secretary","email":"sam@x.test",
         "sports_played":["cricket"],"profile_complete":\(complete),
         "email_verified":\(verified),"phone_verified":false,
         "role_intent":\(intent.map { "\"\($0)\"" } ?? "null")}
        """
        return try decoder.decode(PublicUser.self, from: Data(json.utf8))
    }

    private func member(_ role: String, captain: Bool? = nil) throws -> ClubMemberDetail {
        let flag = captain.map { ",\"is_captain\":\($0)" } ?? ""
        let json = """
        {"user_id":"\(UUID().uuidString)","name":"M","role":"\(role)","status":"active",
         "joined_at":"2026-09-14T08:00:00.123Z"\(flag)}
        """
        return try decoder.decode(ClubMemberDetail.self, from: Data(json.utf8))
    }

    private let club = Club(
        id: UUID(), name: "Boom Blast", sportTypes: ["cricket"], visibility: "invite_only",
        ownerId: UUID(), description: nil, isInformalGroup: false, role: .clubAdmin
    )

    // MARK: Decoding

    func testUserDecodesVerificationAndIntent() throws {
        let u = try user(verified: true, intent: "secretary")
        XCTAssertTrue(u.isVerified)
        XCTAssertEqual(u.intent, .secretary)
        XCTAssertNil(try user(intent: nil).intent)
        // An API older than these fields still decodes.
        let old = try decoder.decode(PublicUser.self, from: Data("""
        {"id":"11111111-1111-1111-1111-111111111111","name":"Old","sports_played":[]}
        """.utf8))
        XCTAssertFalse(old.isVerified)
        XCTAssertNil(old.intent)
    }

    func testVerificationStatusChannels() throws {
        let status = try decoder.decode(VerificationStatus.self, from: Data("""
        {"enabled":true,"verification_required":true,
         "email":{"address":"s***@x.test","verified":false,"available":true},
         "phone":{"address":null,"verified":false,"available":false}}
        """.utf8))
        XCTAssertEqual(status.channels, [.email])
        XCTAssertTrue(status.canVerify)
        XCTAssertEqual(status[.email].address, "s***@x.test")

        let off = VerificationStatus(enabled: false, email: status.email, phone: status.phone, verificationRequired: false)
        XCTAssertFalse(off.canVerify, "a server that does not ask should not show the step")
    }

    func testPendingInviteDecodesAndNamesItself() throws {
        let invite = try decoder.decode(PendingInvite.self, from: Data("""
        {"id":"\(UUID().uuidString)","target_type":"club","target_id":"\(UUID().uuidString)",
         "invited_by":"\(UUID().uuidString)","token":"abc","status":"pending",
         "created_at":"2026-09-14T08:00:00Z","target_name":"Boom Blast","invited_by_name":"Sam"}
        """.utf8))
        XCTAssertTrue(invite.isPending)
        XCTAssertEqual(invite.title, "Boom Blast")

        let unnamed = try decoder.decode(PendingInvite.self, from: Data("""
        {"id":"\(UUID().uuidString)","target_type":"event","target_id":"\(UUID().uuidString)",
         "token":"t","status":"pending","created_at":"2026-09-14T08:00:00.5Z"}
        """.utf8))
        XCTAssertEqual(unnamed.title, "A fixture invitation")
    }

    func testAPIErrorReadsTheCode() {
        let unverified = APIError.http(403, #"{"error":"confirm your email or phone number first","code":"unverified"}"#)
        XCTAssertTrue(unverified.isUnverified)
        XCTAssertEqual(unverified.friendlyMessage, "confirm your email or phone number first")
        XCTAssertFalse(APIError.http(400, #"{"error":"nope"}"#).isUnverified)
        XCTAssertNil(APIError.unauthorized.code)
    }

    func testResendCountdownIsReadFromTheMessage() {
        XCTAssertEqual(VerifyContactView.secondsToWait(in: "you can ask for another in 42s"), 42)
        XCTAssertNil(VerifyContactView.secondsToWait(in: "that code did not work"))
    }

    // MARK: The guide

    private func facts(
        role: RoleIntent, user u: PublicUser, canVerify: Bool = true, ownClub: Club? = nil,
        teams: Int = 0, members: [ClubMemberDetail] = [], events: Int = 0,
        invites: Int = 0, clubs: Int = 0, shared: Bool = false
    ) -> GettingStartedGuide.Facts {
        .init(role: role, user: u, canVerify: canVerify, ownClub: ownClub, teamCount: teams,
              members: members, eventCount: events, inviteCount: invites, clubCount: clubs, sharedOnce: shared)
    }

    func testSecretaryStepsFollowRealState() throws {
        let u = try user(verified: false, intent: "secretary")
        var steps = GettingStartedGuide.steps(facts(role: .secretary, user: u))
        XCTAssertEqual(steps.map(\.id), ["verify", "club", "team", "players", "captain", "fixture"])
        XCTAssertEqual(steps.first { !$0.done }?.id, "verify")

        let verified = try user(verified: true, intent: "secretary")
        steps = GettingStartedGuide.steps(facts(
            role: .secretary, user: verified, ownClub: club, teams: 1,
            members: [try member("club_admin"), try member("member")], events: 0
        ))
        XCTAssertEqual(steps.first { !$0.done }?.id, "captain", "two members and a team: captain is next")

        // A secretary who captains the side counts as naming a captain.
        steps = GettingStartedGuide.steps(facts(
            role: .secretary, user: verified, ownClub: club, teams: 1,
            members: [try member("club_admin", captain: true), try member("member")]
        ))
        XCTAssertEqual(steps.first { !$0.done }?.id, "fixture")

        steps = GettingStartedGuide.steps(facts(
            role: .secretary, user: verified, ownClub: club, teams: 1,
            members: [try member("club_admin"), try member("team_captain")], events: 3
        ))
        XCTAssertNil(steps.first { !$0.done }, "everything done: the guide goes away")
    }

    func testVerifyStepOnlyWhenTheServerCanSendACode() throws {
        let u = try user(intent: "player")
        let steps = GettingStartedGuide.steps(facts(role: .player, user: u, canVerify: false))
        XCTAssertEqual(steps.map(\.id), ["profile", "share", "join"])
    }

    func testPlayerShareStepTicksWhenAnInviteArrives() throws {
        let u = try user(verified: true, intent: "player", complete: true)
        var steps = GettingStartedGuide.steps(facts(role: .player, user: u))
        XCTAssertEqual(steps.first { !$0.done }?.id, "share")

        steps = GettingStartedGuide.steps(facts(role: .player, user: u, invites: 1))
        XCTAssertEqual(steps.first { !$0.done }?.id, "join", "an invite back means the link reached them")
        XCTAssertTrue(steps.first { $0.id == "join" }!.detail.contains("waiting"))

        steps = GettingStartedGuide.steps(facts(role: .player, user: u, clubs: 1))
        XCTAssertNil(steps.first { !$0.done })
    }
}

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
        XCTAssertEqual(steps.map(\.id), ["share", "join"], "the profile is the strength card's job, not a step")
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

    // MARK: Quick start and profile strength

    private func profiled(_ json: String) throws -> PublicUser {
        try decoder.decode(PublicUser.self, from: Data("""
        {"id":"11111111-1111-1111-1111-111111111111","name":"Pat Player","sports_played":[]\(json)}
        """.utf8))
    }

    func testStrengthCountsWhatIsFilledIn() throws {
        let fresh = try profiled("")
        XCTAssertEqual(ProfileStrength(fresh).percent, 10, "a name is all a new account has")
        XCTAssertEqual(ProfileStrength(fresh).nextUp, "Add what you play, a photo and the standard you play at")

        let quick = try profiled(#","phone":"07700900123","primary_sport":"cricket","sport_profiles":[{"sport":"cricket"}]"#)
        XCTAssertEqual(ProfileStrength(quick).percent, 35, "name, sport and number: what the quick start asks")
        XCTAssertEqual(ProfileStrength(quick).nextUp, "Add a photo, the standard you play at and your position")

        let full = try profiled("""
        ,"phone":"07700900123","avatar_url":"https://x/p.jpg","emergency_contact":"Mum 07700",
        "email_verified":true,"primary_sport":"cricket",
        "sport_profiles":[{"sport":"cricket","skill_level":"Club","position":"Batter"}],
        "location":{"area":"Hemel","transport":"driver"}
        """)
        XCTAssertEqual(ProfileStrength(full).percent, 100)
        XCTAssertTrue(ProfileStrength(full).isComplete)
        XCTAssertEqual(ProfileStrength(full).nextUp, "")
    }

    func testQuickStartIsShownOnceAndSkippable() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "quick-start-\(UUID().uuidString)"))
        let fresh = try profiled("")
        XCTAssertTrue(SessionStore.needsQuickStart(fresh, defaults: defaults))

        defaults.set(true, forKey: SessionStore.quickStartKey(fresh.id))
        XCTAssertFalse(SessionStore.needsQuickStart(fresh, defaults: defaults), "skipped is past it")

        let other = try XCTUnwrap(UserDefaults(suiteName: "quick-start-\(UUID().uuidString)"))
        let played = try profiled(#","sport_profiles":[{"sport":"cricket"}]"#)
        XCTAssertFalse(SessionStore.needsQuickStart(played, defaults: other), "a sport on file is past it on any phone")
    }

    func testRemindersLandInTheEvening() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let signedUp = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 22, minute: 30)))
        let trigger = ProfileReminder.trigger(inDays: 1, from: signedUp, calendar: calendar)
        XCTAssertEqual(trigger.dateComponents.day, 15)
        XCTAssertEqual(trigger.dateComponents.hour, 18)
        XCTAssertFalse(trigger.repeats)
    }
}

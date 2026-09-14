import XCTest
@testable import Fishers

final class ClubsTests: XCTestCase {
    private let decoder = FishersJSONDecoder.make()

    func testMembershipRowDecodesTheListFields() throws {
        let page = try decoder.decode(APIPage<ClubMembershipRow>.self, from: Data("""
        {"items":[{"id":"\(UUID().uuidString)","name":"Boom Blast CC","sport_types":["cricket","football"],
          "visibility":"public","owner_id":"\(UUID().uuidString)","description":null,"is_informal_group":false,
          "created_at":"2026-09-14T08:00:00.123Z","updated_at":"2026-09-14T08:00:00Z",
          "role":"club_admin","is_captain":true,"member_count":12,"team_count":2,"public_slug":"boom-blast"}],
         "total":45,"page":1,"per_page":20,"has_more":true}
        """.utf8))
        let row = try XCTUnwrap(page.items.first)
        XCTAssertEqual(page.total, 45)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(row.roleLabel, "Secretary & captain")
        XCTAssertEqual(row.memberCount, 12)
        XCTAssertTrue(row.isPublic)
        XCTAssertEqual(row.publicPageURL?.lastPathComponent, "boom-blast")
        XCTAssertEqual(row.club.role, .clubAdmin)
    }

    func testMembershipRowToleratesAnOlderAPI() throws {
        let row = try decoder.decode(ClubMembershipRow.self, from: Data("""
        {"id":"\(UUID().uuidString)","name":"Old","owner_id":"\(UUID().uuidString)","role":"team_captain"}
        """.utf8))
        XCTAssertTrue(row.isCaptain, "a Captain is a captain even when the API does not say")
        XCTAssertEqual(row.memberCount, 0)
        XCTAssertNil(row.publicSlug)
    }

    func testFiltersBecomeTheServersQuery() {
        var filters = ClubListFilters()
        XCTAssertFalse(filters.isFiltered)
        XCTAssertEqual(Set(filters.queryItems(page: 1, perPage: 20).map(\.name)), ["sort", "page", "per_page"])

        filters.query = "  watford "
        filters.role = .viceCaptain
        filters.sport = "tennis"
        filters.publicPage = false
        filters.sort = .members
        let items = Dictionary(uniqueKeysWithValues: filters.queryItems(page: 3, perPage: 20).map { ($0.name, $0.value) })
        XCTAssertTrue(filters.isFiltered)
        XCTAssertEqual(items["q"], "watford")
        XCTAssertEqual(items["role"], "vice_captain")
        XCTAssertEqual(items["sport"], "tennis")
        XCTAssertEqual(items["public_page"], "false")
        XCTAssertEqual(items["sort"], "members")
        XCTAssertEqual(items["page"], "3")
    }

    func testOnlyASecretaryCanAlsoBeCaptain() {
        XCTAssertEqual(RoleChoice(role: .clubAdmin, isCaptain: true).label, "Secretary & captain")
        XCTAssertFalse(RoleChoice(role: .member, isCaptain: true).isCaptain, "the flag means nothing for a member")
        XCTAssertEqual(RoleChoice(role: .teamCaptain, isCaptain: false).label, "Team captain")
        XCTAssertEqual(RoleChoice.appointable.first?.label, "Secretary & captain")
        XCTAssertEqual(Set(RoleChoice.appointable.map(\.id)).count, RoleChoice.appointable.count, "no duplicate choices")
    }

    func testMemberRoleChoiceComesFromTheFlag() throws {
        let member = try decoder.decode(ClubMemberDetail.self, from: Data("""
        {"user_id":"\(UUID().uuidString)","name":"Sam","role":"club_admin","is_captain":true,
         "status":"active","joined_at":"2026-09-14T08:00:00Z"}
        """.utf8))
        XCTAssertEqual(member.roleChoice, RoleChoice(role: .clubAdmin, isCaptain: true))
    }

    func testSuggestedWebAddress() {
        XCTAssertEqual(ClubPageSettings.suggestedSlug(for: "Riverside Cricket & Social Club"), "riverside-cricket-social-club")
        XCTAssertEqual(ClubPageSettings.suggestedSlug(for: "  Boom Blast CC!  "), "boom-blast-cc")
        XCTAssertEqual(ClubPageSettings.suggestedSlug(for: "Café Zürich XI"), "caf-z-rich-xi")
    }

    func testProfileTokenIsFoundInWhateverWasPasted() {
        let message = "Hi — I'd like to play for the club. Here's my Fishers player profile: https://www.fishers.cloud/p/IaUOqo6b0QDuycSkQSM6OP4C thanks"
        XCTAssertEqual(SharedPlayerCard.token(in: message), "IaUOqo6b0QDuycSkQSM6OP4C")
        XCTAssertNil(SharedPlayerCard.token(in: "https://www.fishers.cloud/c/boom-blast"))
        XCTAssertNil(SharedPlayerCard.token(in: "/p/short"))
    }

    func testSetupChecklistTicksFromWhatExists() throws {
        func member(_ role: String, captain: Bool = false) throws -> ClubMemberDetail {
            try decoder.decode(ClubMemberDetail.self, from: Data("""
            {"user_id":"\(UUID().uuidString)","name":"M","role":"\(role)","is_captain":\(captain),
             "status":"active","joined_at":"2026-09-14T08:00:00Z"}
            """.utf8))
        }
        var steps = ClubSetupStep.steps(members: [try member("club_admin")], teams: 0, venues: 0)
        XCTAssertEqual(steps.filter(\.done).count, 0)
        XCTAssertEqual(steps.map(\.kind), [.players, .team, .captain, .ground])

        steps = ClubSetupStep.steps(members: [try member("club_admin", captain: true), try member("member")], teams: 1, venues: 1)
        XCTAssertTrue(steps.allSatisfy(\.done), "a secretary who captains names the captain")
    }
}

import XCTest
@testable import Fishers

/// Leaving the team sheets half way used to lose every pick.
final class SheetDraftTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "SheetDraftTests")
        defaults.removePersistentDomain(forName: "SheetDraftTests")
    }

    func testAPickedSheetComesBackForItsOwnMatchOnly() {
        let event = UUID()
        let ravi = MatchPlayer(id: UUID(), name: "Ravi", batsLeft: false)
        let tom = MatchPlayer(id: UUID(), name: "Tom", batsLeft: true)
        SheetDraft(home: [ravi, tom], homeCaptain: ravi.id).save(eventId: event, defaults: defaults)

        let back = SheetDraft.load(eventId: event, defaults: defaults)
        XCTAssertEqual(back?.home.map(\.name), ["Ravi", "Tom"])
        XCTAssertEqual(back?.homeCaptain, ravi.id)
        XCTAssertEqual(back?.home.last?.batsLeft, true)
        XCTAssertNil(SheetDraft.load(eventId: UUID(), defaults: defaults), "another match's sheets")
    }

    func testAnEmptyDraftOrAClearLeavesNothingBehind() {
        let event = UUID()
        SheetDraft(away: [MatchPlayer(id: UUID(), name: "Imran", batsLeft: false)]).save(eventId: event, defaults: defaults)
        SheetDraft.clear(eventId: event, defaults: defaults)
        XCTAssertNil(SheetDraft.load(eventId: event, defaults: defaults))

        SheetDraft(away: [MatchPlayer(id: UUID(), name: "Imran", batsLeft: false)]).save(eventId: event, defaults: defaults)
        SheetDraft().save(eventId: event, defaults: defaults)
        XCTAssertNil(SheetDraft.load(eventId: event, defaults: defaults), "an empty draft clears")
    }
}

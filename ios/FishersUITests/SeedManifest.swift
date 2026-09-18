import XCTest

/// What `scripts/seed-area.py` wrote about the season it seeded: who to sign in as, and who is
/// playing tonight. The Simulator shares the Mac's file system, so the tours read it directly
/// rather than being told the same thing twice.
struct SeedManifest: Decodable {
    struct Account: Decodable {
        let email: String
        let name: String
        let club: String?
    }

    /// A side as it takes the field: batting order, who leads it, who keeps, and who can bowl.
    struct Side: Decodable {
        let club: String
        let name: String
        let batting: [String]
        let captain: String
        let keeper: String
        let bowlers: [String]
    }

    struct Fixture: Decodable {
        let event_id: String
        let title: String
        let home: Side?
        let away: Side?
    }

    let password: String
    let hero: Account
    let watford_captain: Account
    let super5s: Fixture
    /// A whole twenty overs, for a tour that wants to play one. Older seeds have no such fixture.
    let t20_tonight: Fixture?
    let live_t20: Fixture
    let club_chat: String

    static func load() throws -> SeedManifest {
        let path = ProcessInfo.processInfo.environment["FISHERS_SEED_MANIFEST"]
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".dev/seed-area.json").path
        guard let data = FileManager.default.contents(atPath: path) else {
            throw XCTSkip("no seed manifest at \(path) — run scripts/seed-area.py first")
        }
        return try JSONDecoder().decode(SeedManifest.self, from: data)
    }
}

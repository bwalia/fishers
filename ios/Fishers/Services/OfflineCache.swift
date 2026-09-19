import Foundation

/// Disk cache of fixtures, clubs and events so Score Hub still opens at a
/// ground with no signal. Scoring itself already lives in SwiftData; this is
/// the catalogue that gets you into a match.
enum OfflineCache {
    private static let folderName = "OfflineCache"

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Fishers", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name).appendingPathExtension("json")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Fixtures

    struct FixtureSnapshot: Codable {
        var savedAt: Date
        var rows: [CricketFixtureRow]
        var total: Int
    }

    static func saveFixtures(_ page: APIPage<CricketFixtureRow>, state: String?) {
        let snap = FixtureSnapshot(savedAt: .now, rows: page.items, total: page.total)
        write(snap, to: "fixtures-\(state ?? "all")")
        // Always refresh the unfiltered snapshot when we fetch "all".
        if state == nil {
            write(snap, to: "fixtures-all")
        }
        for row in page.items {
            saveEventStub(from: row)
        }
    }

    static func loadFixtures(state: String?) -> FixtureSnapshot? {
        read("fixtures-\(state ?? "all")")
    }

    // MARK: Startable clubs + teams

    static func saveStartableClubs(_ clubs: [Club]) {
        write(clubs, to: "startable-clubs")
    }

    static func loadStartableClubs() -> [Club] {
        read("startable-clubs") ?? []
    }

    static func saveTeams(clubId: UUID, teams: [Team]) {
        write(teams, to: "teams-\(clubId.uuidString)")
    }

    static func loadTeams(clubId: UUID) -> [Team] {
        read("teams-\(clubId.uuidString)") ?? []
    }

    // MARK: Events

    static func saveEvent(_ event: Event) {
        write(event, to: "event-\(event.id.uuidString)")
    }

    static func loadEvent(id: UUID) -> Event? {
        read("event-\(id.uuidString)")
    }

    // MARK: Club role (scoring permission offline)

    static func saveRole(_ role: ClubRoleInfo, clubId: UUID) {
        write(role, to: "role-\(clubId.uuidString)")
    }

    static func loadRole(clubId: UUID) -> ClubRoleInfo? {
        read("role-\(clubId.uuidString)")
    }

    /// Enough of a fixture to open scoring when the API is unreachable.
    static func saveEventStub(from row: CricketFixtureRow) {
        let meta: [String: JSONValue] = [
            "opposition": .string(row.awayName ?? ""),
            "home_name": .string(row.homeName ?? row.title),
        ]
        let event = Event(
            id: row.eventId,
            clubId: row.clubId,
            teamId: nil,
            sport: "cricket",
            eventSubtype: "friendly",
            title: row.title,
            venueId: nil,
            startAt: row.startAt,
            endAt: row.startAt.addingTimeInterval(4 * 3600),
            capacity: 22,
            feeAmountCents: nil,
            feeCurrency: "GBP",
            status: row.eventStatus,
            metadata: meta,
            ticketPriceCents: nil,
            opponentClubId: nil
        )
        saveEvent(event)
    }

    // MARK: IO

    private static func write<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    private static func read<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}

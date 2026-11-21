import Foundation

/// A team sheet still being picked, kept on this phone until its side is named.
///
/// Leaving the sheets half way used to lose every pick: they lived on the
/// screen, and only a named side goes into the match's log. A named side is
/// the log's, and the log always wins over a draft.
struct SheetDraft: Codable, Equatable {
    var home: [MatchPlayer] = []
    var away: [MatchPlayer] = []
    var homeCaptain: UUID?
    var awayCaptain: UUID?
    var homeKeeper: UUID?
    var awayKeeper: UUID?

    var isEmpty: Bool { home.isEmpty && away.isEmpty }

    private static func key(_ eventId: UUID) -> String { "cricket.sheet-draft.\(eventId.uuidString)" }

    static func load(eventId: UUID, defaults: UserDefaults = .standard) -> SheetDraft? {
        guard let data = defaults.data(forKey: key(eventId)) else { return nil }
        return try? JSONDecoder().decode(SheetDraft.self, from: data)
    }

    func save(eventId: UUID, defaults: UserDefaults = .standard) {
        if isEmpty {
            Self.clear(eventId: eventId, defaults: defaults)
        } else if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key(eventId))
        }
    }

    static func clear(eventId: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(eventId))
    }
}

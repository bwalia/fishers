import Foundation
import SwiftData

@Model
final class LocalCricketMatch {
    @Attribute(.unique) var matchId: UUID
    var eventId: UUID
    var clubId: UUID
    var deviceId: String
    var homeName: String
    var awayName: String
    var oversLimit: Int
    /// JSON-encoded `[UUID: String]` display names.
    var playerNamesJSON: Data
    /// Latest MatchState JSON snapshot for fast resume.
    var stateJSON: Data
    var lastSeq: Int64
    var syncStatusRaw: String
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \LocalScoringEvent.match)
    var events: [LocalScoringEvent] = []

    init(
        matchId: UUID,
        eventId: UUID,
        clubId: UUID,
        deviceId: String,
        homeName: String,
        awayName: String,
        oversLimit: Int,
        state: MatchState,
        playerNames: [UUID: String] = [:]
    ) {
        self.matchId = matchId
        self.eventId = eventId
        self.clubId = clubId
        self.deviceId = deviceId
        self.homeName = homeName
        self.awayName = awayName
        self.oversLimit = oversLimit
        self.lastSeq = state.lastSeq
        self.syncStatusRaw = SyncStatus.saved.rawValue
        self.updatedAt = .now
        let enc = JSONEncoder()
        self.stateJSON = (try? enc.encode(state)) ?? Data()
        let namePairs = Dictionary(uniqueKeysWithValues: playerNames.map { ($0.key.uuidString, $0.value) })
        self.playerNamesJSON = (try? enc.encode(namePairs)) ?? Data()
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .saved }
        set { syncStatusRaw = newValue.rawValue }
    }

    func decodedState() -> MatchState {
        (try? JSONDecoder().decode(MatchState.self, from: stateJSON))
            ?? MatchState(oversLimit: UInt8(oversLimit), homeName: homeName, awayName: awayName)
    }

    func setState(_ state: MatchState) {
        stateJSON = (try? JSONEncoder().encode(state)) ?? stateJSON
        lastSeq = state.lastSeq
        updatedAt = .now
    }

    func playerNames() -> [UUID: String] {
        guard let dict = try? JSONDecoder().decode([String: String].self, from: playerNamesJSON)
        else { return [:] }
        var out: [UUID: String] = [:]
        for (k, v) in dict {
            if let id = UUID(uuidString: k) { out[id] = v }
        }
        return out
    }

    func setPlayerNames(_ names: [UUID: String]) {
        let pairs = Dictionary(uniqueKeysWithValues: names.map { ($0.key.uuidString, $0.value) })
        playerNamesJSON = (try? JSONEncoder().encode(pairs)) ?? playerNamesJSON
    }
}

@Model
final class LocalScoringEvent {
    @Attribute(.unique) var clientEventId: UUID
    var seq: Int64
    var kindJSON: Data
    var pendingSync: Bool
    var createdAt: Date
    var match: LocalCricketMatch?

    init(event: ScoringEvent, pendingSync: Bool = true) {
        clientEventId = event.clientEventId
        seq = event.seq
        kindJSON = (try? JSONEncoder().encode(event.kind)) ?? Data()
        self.pendingSync = pendingSync
        createdAt = .now
    }

    func asScoringEvent() -> ScoringEvent? {
        guard let kind = try? JSONDecoder().decode(ScoringEventKind.self, from: kindJSON) else {
            return nil
        }
        return ScoringEvent(clientEventId: clientEventId, seq: seq, kind: kind)
    }
}

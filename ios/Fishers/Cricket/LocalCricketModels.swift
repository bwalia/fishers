import Foundation
import SwiftData

@Model
final class LocalCricketMatch {
    /// Chosen on the device before the API is ever called, so a match started
    /// with no signal keeps the same id when it is registered later.
    @Attribute(.unique) var matchId: UUID
    var eventId: UUID
    var clubId: UUID
    var deviceId: String
    var homeName: String
    var awayName: String
    var oversLimit: Int
    /// Latest MatchState JSON snapshot, for a fast resume before replay.
    var stateJSON: Data
    var lastSeq: Int64
    var syncStatusRaw: String
    /// True until the API has been told this match exists.
    var needsRemoteCreate: Bool = false
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
        needsRemoteCreate: Bool
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
        self.needsRemoteCreate = needsRemoteCreate
        self.updatedAt = .now
        self.stateJSON = (try? JSONEncoder().encode(state)) ?? Data()
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .saved }
        set { syncStatusRaw = newValue.rawValue }
    }

    var pendingEvents: [ScoringEvent] {
        events
            .filter(\.pendingSync)
            .sorted { $0.seq < $1.seq }
            .compactMap { $0.asScoringEvent() }
    }

    var hasPendingWork: Bool { needsRemoteCreate || events.contains(where: \.pendingSync) }

    /// The whole log in order — the engine folds this back into a scorecard.
    var orderedEvents: [ScoringEvent] {
        events.sorted { $0.seq < $1.seq }.compactMap { $0.asScoringEvent() }
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

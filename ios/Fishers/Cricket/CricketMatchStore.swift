import Foundation
import SwiftData

/// All LIVE mutations: append event → engine.apply → autosave. Never waits on network.
@MainActor
final class CricketMatchStore: ObservableObject {
    @Published private(set) var state: MatchState
    @Published private(set) var syncStatus: SyncStatus = .saved
    @Published private(set) var matchId: UUID?
    @Published private(set) var eventId: UUID
    @Published private(set) var clubId: UUID
    @Published var playerNames: [UUID: String] = [:]
    @Published var lastError: String?

    let deviceId: String
    private var modelContext: ModelContext?
    private var localMatch: LocalCricketMatch?

    init(
        eventId: UUID,
        clubId: UUID,
        modelContext: ModelContext? = nil,
        deviceId: String? = nil
    ) {
        self.eventId = eventId
        self.clubId = clubId
        self.modelContext = modelContext
        self.deviceId = deviceId ?? Self.resolvedDeviceId()
        self.state = MatchState()
    }

    func replaceContext(_ context: ModelContext) {
        modelContext = context
    }

    nonisolated static func resolvedDeviceId() -> String {
        let key = "cricket_device_id"
        if let existing = KeychainStore.get(key) { return existing }
        let id = UUID().uuidString
        KeychainStore.set(id, forKey: key)
        return id
    }

    func loadLocalOrCreate(
        matchId: UUID,
        homeName: String,
        awayName: String,
        oversLimit: Int
    ) throws {
        self.matchId = matchId
        guard let modelContext else {
            throw CricketEngineError.validation("store not ready")
        }
        let descriptor = FetchDescriptor<LocalCricketMatch>(
            predicate: #Predicate { $0.matchId == matchId }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            localMatch = existing
            playerNames = existing.playerNames()
            // Replay events so undo history is rebuilt.
            var rebuilt = MatchState(
                oversLimit: UInt8(existing.oversLimit),
                homeName: existing.homeName,
                awayName: existing.awayName
            )
            let sorted = existing.events.sorted { $0.seq < $1.seq }
            for row in sorted {
                if let ev = row.asScoringEvent() {
                    try? rebuilt.apply(ev)
                }
            }
            state = rebuilt
            syncStatus = existing.syncStatus
            return
        }

        let seed = MatchState(
            oversLimit: UInt8(oversLimit),
            homeName: homeName,
            awayName: awayName
        )
        let row = LocalCricketMatch(
            matchId: matchId,
            eventId: eventId,
            clubId: clubId,
            deviceId: deviceId,
            homeName: homeName,
            awayName: awayName,
            oversLimit: oversLimit,
            state: seed,
            playerNames: playerNames
        )
        modelContext.insert(row)
        try modelContext.save()
        localMatch = row
        state = seed
    }

    /// Append + apply locally. UI must call this for every scoring action.
    @discardableResult
    func append(_ kind: ScoringEventKind) -> Bool {
        let nextSeq = state.lastSeq + 1
        let event = ScoringEvent.make(seq: nextSeq, kind: kind)
        do {
            var next = state
            try next.apply(event)
            state = next
            persist(event)
            syncStatus = .saved
            lastError = nil
            Task { await CricketSyncService.shared.flushIfNeeded() }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func name(for id: UUID) -> String {
        playerNames[id] ?? String(id.uuidString.prefix(8))
    }

    func registerName(_ name: String, for id: UUID) {
        playerNames[id] = name
        localMatch?.setPlayerNames(playerNames)
        try? modelContext?.save()
    }

    func pendingEvents() -> [ScoringEvent] {
        guard let localMatch else { return [] }
        return localMatch.events
            .filter(\.pendingSync)
            .sorted { $0.seq < $1.seq }
            .compactMap { $0.asScoringEvent() }
    }

    func markSynced(clientIds: Set<UUID>, remoteState: MatchState?) {
        guard let localMatch else { return }
        for ev in localMatch.events where clientIds.contains(ev.clientEventId) {
            ev.pendingSync = false
        }
        if let remoteState {
            // Keep local history; only adopt remote fields when no pending.
            if localMatch.events.allSatisfy({ !$0.pendingSync }) {
                var adopted = remoteState
                adopted.history = state.history
                state = adopted
                localMatch.setState(adopted)
            }
        }
        localMatch.syncStatus = .saved
        syncStatus = .saved
        try? modelContext?.save()
    }

    func setSyncing(_ syncing: Bool, offline: Bool = false) {
        if offline {
            syncStatus = .offline
            localMatch?.syncStatus = .offline
        } else if syncing {
            syncStatus = .syncing
            localMatch?.syncStatus = .syncing
        } else {
            syncStatus = .saved
            localMatch?.syncStatus = .saved
        }
        try? modelContext?.save()
    }

    private func persist(_ event: ScoringEvent) {
        guard let localMatch, let modelContext else { return }
        let row = LocalScoringEvent(event: event, pendingSync: true)
        row.match = localMatch
        localMatch.events.append(row)
        localMatch.setState(state)
        localMatch.setPlayerNames(playerNames)
        try? modelContext.save()
    }
}

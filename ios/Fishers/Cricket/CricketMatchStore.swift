import Foundation
import SwiftData

/// All LIVE mutations: append event → engine.apply → autosave. Never waits on
/// the network. The match id is minted here, before the API is involved, so
/// scoring can start on a ground with no signal.
@MainActor
final class CricketMatchStore: ObservableObject {
    @Published private(set) var state: MatchState
    @Published private(set) var syncStatus: SyncStatus = .saved
    @Published private(set) var matchId: UUID?
    @Published private(set) var eventId: UUID
    @Published private(set) var clubId: UUID
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

    // MARK: Lifecycle

    /// Adopt this fixture's match if the device already has one. Creates
    /// nothing — the scorer may still be looking at the setup screen.
    @discardableResult
    func resumeLocal() -> UUID? {
        guard let modelContext else { return nil }
        let fixtureId = eventId
        let descriptor = FetchDescriptor<LocalCricketMatch>(
            predicate: #Predicate { $0.eventId == fixtureId }
        )
        guard let existing = try? modelContext.fetch(descriptor).first else { return nil }
        adopt(existing)
        return existing.matchId
    }

    /// Resume this fixture's match, or start one. Works with no network: the id
    /// is minted here and the API is told about it later.
    @discardableResult
    func openLocal(
        homeName: String,
        awayName: String,
        oversLimit: Int
    ) throws -> UUID {
        guard let modelContext else {
            throw CricketEngineError.validation("store not ready")
        }
        if let existing = resumeLocal() { return existing }

        let id = UUID()
        let seed = MatchState(
            oversLimit: UInt8(oversLimit),
            homeName: homeName,
            awayName: awayName
        )
        let row = LocalCricketMatch(
            matchId: id,
            eventId: eventId,
            clubId: clubId,
            deviceId: deviceId,
            homeName: homeName,
            awayName: awayName,
            oversLimit: oversLimit,
            state: seed,
            needsRemoteCreate: true
        )
        modelContext.insert(row)
        try modelContext.save()
        adopt(row)
        return id
    }

    /// Adopt a stored match, rebuilding state (and the undo stack) from its log.
    private func adopt(_ row: LocalCricketMatch) {
        localMatch = row
        matchId = row.matchId
        state = (try? MatchState.replay(row.orderedEvents)) ?? row.decodedState()
        if state.lastSeq == 0 {
            // Nothing scored yet — keep the names the fixture was set up with.
            state.oversLimit = UInt8(row.oversLimit)
            state.homeName = row.homeName
            state.awayName = row.awayName
        }
        syncStatus = row.syncStatus
    }

    /// The API has confirmed the match; stop trying to create it.
    func markRegistered(remoteId: UUID) {
        guard let localMatch else { return }
        if localMatch.matchId != remoteId {
            // The fixture already had a match on the server: adopt its id.
            localMatch.matchId = remoteId
            matchId = remoteId
        }
        localMatch.needsRemoteCreate = false
        try? modelContext?.save()
    }

    // MARK: Scoring

    /// Append + apply locally. Every scoring action goes through here.
    @discardableResult
    func append(_ kind: ScoringEventKind) -> Bool {
        let event = ScoringEvent.make(seq: state.lastSeq + 1, kind: kind)
        do {
            var next = state
            try next.apply(event)
            state = next
            persist(event)
            lastError = nil
            if CricketSyncService.shared.isOnline {
                CricketSyncService.shared.requestFlush()
            } else {
                setSyncing(false, offline: true)
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func name(for id: UUID) -> String { state.name(for: id) }

    /// DLS par for the chase, computed on the device so it survives a blackspot.
    var dlsPar: DlsPar? { state.dlsPar }

    func players(for side: MatchSide) -> [MatchPlayer] { state.players(for: side) }

    // MARK: Sync plumbing

    var localRow: LocalCricketMatch? { localMatch }

    func pendingEvents() -> [ScoringEvent] { localMatch?.pendingEvents ?? [] }

    var needsRemoteCreate: Bool { localMatch?.needsRemoteCreate ?? false }

    func markSynced(clientIds: Set<UUID>, remoteState: MatchState?) {
        guard let localMatch else { return }
        for event in localMatch.events where clientIds.contains(event.clientEventId) {
            event.pendingSync = false
        }
        // Adopt the server's projection only once nothing local is outstanding,
        // and keep the local undo stack — the server never sends one.
        if let remoteState, !localMatch.events.contains(where: \.pendingSync) {
            var adopted = remoteState
            adopted.history = state.history
            state = adopted
        }
        localMatch.setState(state)
        localMatch.syncStatus = .saved
        syncStatus = .saved
        try? modelContext?.save()
    }

    func setSyncing(_ syncing: Bool, offline: Bool = false) {
        let status: SyncStatus = offline ? .offline : (syncing ? .syncing : .saved)
        syncStatus = status
        localMatch?.syncStatus = status
        try? modelContext?.save()
    }

    func note(error: String?) {
        lastError = error
    }

    private func persist(_ event: ScoringEvent) {
        guard let localMatch, let modelContext else { return }
        let row = LocalScoringEvent(event: event, pendingSync: true)
        row.match = localMatch
        localMatch.events.append(row)
        localMatch.setState(state)
        try? modelContext.save()
    }
}

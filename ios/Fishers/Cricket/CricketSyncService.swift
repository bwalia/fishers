import Foundation
import Network
import SwiftData

/// Pushes pending scoring events when there is a network, and registers matches
/// that were started offline. One writer at a time: the live store owns the
/// active match, and the background sweep only touches the rest.
@MainActor
final class CricketSyncService: ObservableObject {
    static let shared = CricketSyncService()

    private let monitor = NWPathMonitor()
    private var container: ModelContainer?
    private var started = false
    private var flushing = false
    private weak var activeStore: CricketMatchStore?

    @Published private(set) var isOnline = true

    func configure(container: ModelContainer) {
        self.container = container
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.pathChanged(online)
            }
        }
        monitor.start(queue: DispatchQueue(label: "fishers.cricket.sync"))
    }

    /// The scorer's screen registers itself so its match syncs first and its
    /// published state stays in step.
    func register(store: CricketMatchStore) {
        activeStore = store
        requestFlush()
    }

    func unregister(store: CricketMatchStore) {
        if activeStore === store { activeStore = nil }
    }

    private func pathChanged(_ online: Bool) {
        let wasOffline = !isOnline
        isOnline = online
        if online && wasOffline {
            activeStore?.setSyncing(false)
            requestFlush()
        } else if !online {
            activeStore?.setSyncing(false, offline: true)
        }
    }

    /// Fire-and-forget: scoring never waits on the network.
    func requestFlush() {
        Task { await flush() }
    }

    func flush() async {
        guard isOnline, !flushing else { return }
        flushing = true
        defer { flushing = false }

        if let store = activeStore {
            await flushActive(store)
        }
        await sweepOthers()
    }

    // MARK: Active match

    private func flushActive(_ store: CricketMatchStore) async {
        guard store.needsRemoteCreate || !store.pendingEvents().isEmpty else { return }
        guard let row = store.localRow else { return }

        store.setSyncing(true)
        if store.needsRemoteCreate {
            do {
                let dto = try await FishersAPI.createCricketMatch(
                    eventId: row.eventId,
                    matchId: row.matchId,
                    oversLimit: row.oversLimit,
                    homeName: row.homeName,
                    awayName: row.awayName
                )
                store.markRegistered(remoteId: dto.id)
                _ = try? await FishersAPI.claimScorer(
                    matchId: dto.id, deviceId: store.deviceId, force: false
                )
            } catch {
                store.setSyncing(false, offline: true)
                return
            }
        }

        let pending = store.pendingEvents()
        guard !pending.isEmpty else {
            store.setSyncing(false)
            return
        }
        guard let matchId = store.matchId else { return }
        do {
            let updated = try await FishersAPI.postCricketEvents(
                matchId: matchId,
                deviceId: store.deviceId,
                events: pending
            )
            store.markSynced(
                clientIds: Set(pending.map(\.clientEventId)),
                remoteState: updated.state
            )
            store.note(error: nil)
        } catch {
            // Stay pending; the chip shows Offline and we retry on the next ball.
            store.setSyncing(false, offline: true)
            store.note(error: Self.syncMessage(for: error))
        }
    }

    /// A rejected batch is worth explaining — it usually means someone else took
    /// over scoring, which no amount of retrying will fix.
    private static func syncMessage(for error: Error) -> String? {
        guard let api = error as? APIError else { return nil }
        switch api {
        case .http(let code, _) where code == 409:
            return "Another device is scoring this match — take over to sync from here."
        case .unreachable:
            return nil // ordinary offline, the chip already says so
        default:
            return api.errorDescription
        }
    }

    // MARK: Everything else

    /// Matches this device scored earlier that never made it up.
    private func sweepOthers() async {
        guard let container else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalCricketMatch>()
        guard let matches = try? context.fetch(descriptor) else { return }

        for match in matches where match.hasPendingWork {
            if match.matchId == activeStore?.matchId { continue }
            var matchId = match.matchId
            if match.needsRemoteCreate {
                guard let dto = try? await FishersAPI.createCricketMatch(
                    eventId: match.eventId,
                    matchId: match.matchId,
                    oversLimit: match.oversLimit,
                    homeName: match.homeName,
                    awayName: match.awayName
                ) else { continue }
                matchId = dto.id
                match.matchId = dto.id
                match.needsRemoteCreate = false
                _ = try? await FishersAPI.claimScorer(
                    matchId: dto.id, deviceId: match.deviceId, force: false
                )
            }

            let pending = match.pendingEvents
            guard !pending.isEmpty else {
                try? context.save()
                continue
            }
            guard let updated = try? await FishersAPI.postCricketEvents(
                matchId: matchId,
                deviceId: match.deviceId,
                events: pending
            ) else { continue }

            let ids = Set(pending.map(\.clientEventId))
            for event in match.events where ids.contains(event.clientEventId) {
                event.pendingSync = false
            }
            match.setState(updated.state)
            match.syncStatus = .saved
            try? context.save()
        }
    }
}

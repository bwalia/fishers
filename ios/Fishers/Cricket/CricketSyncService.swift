import Foundation
import Network
import SwiftData

/// Background sync: push pending events, pull scorecard when online.
actor CricketSyncService {
    static let shared = CricketSyncService()

    private let monitor = NWPathMonitor()
    private var online = true
    private var modelContainer: ModelContainer?
    private var started = false

    func configure(container: ModelContainer) {
        modelContainer = container
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.pathChanged(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "fishers.cricket.sync"))
    }

    private func pathChanged(_ isOnline: Bool) {
        online = isOnline
        if isOnline {
            Task { await flushIfNeeded() }
        }
    }

    var isOnline: Bool { online }

    func flushIfNeeded() async {
        guard online, let container = modelContainer else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalCricketMatch>()
        guard let matches = try? context.fetch(descriptor) else { return }

        for match in matches {
            let pending = match.events
                .filter(\.pendingSync)
                .sorted { $0.seq < $1.seq }
                .compactMap { $0.asScoringEvent() }
            guard !pending.isEmpty else { continue }
            do {
                let updated = try await FishersAPI.postCricketEvents(
                    matchId: match.matchId,
                    deviceId: match.deviceId,
                    events: pending
                )
                let ids = Set(pending.map(\.clientEventId))
                for ev in match.events where ids.contains(ev.clientEventId) {
                    ev.pendingSync = false
                }
                match.setState(updated.state)
                match.syncStatus = .saved
                try context.save()
            } catch {
                // Stay pending; UI shows Offline / Syncing via store.
                continue
            }
        }
    }
}

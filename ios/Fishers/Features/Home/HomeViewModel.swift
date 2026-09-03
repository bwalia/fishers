import Foundation
import Observation

@Observable
@MainActor
final class HomeViewModel {
    var upcomingEvents: [Event] = []
    var pendingInvites: [EventInvite] = []
    var unpaidEvents: [Event] = []
    var isLoading = false
    var errorMessage: String?

    func load(api: FishersAPI, currentUserId: UUID?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let now = Date()
            let horizon = Calendar.current.date(byAdding: .day, value: 30, to: now)!
            async let eventsTask = api.events(clubId: nil, teamId: nil, from: now, to: horizon)
            async let invitesTask = api.invitesMine()
            let (events, invites) = try await (eventsTask, invitesTask)
            upcomingEvents = events.sorted { $0.startAt < $1.startAt }
            pendingInvites = invites.filter { $0.status == .pending }

            // Fees still owed: events I'm going to, with a fee, where my attendee row is unpaid.
            var unpaid: [Event] = []
            for event in upcomingEvents.filter({ $0.hasFee }).prefix(8) {
                let attendees = try await api.attendees(eventId: event.id)
                if let me = attendees.first(where: { $0.user.id == currentUserId }),
                   me.status == .going, !me.hasPaid {
                    unpaid.append(event)
                }
            }
            unpaidEvents = unpaid
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func respond(inviteId: UUID, status: RSVPStatus, api: FishersAPI, currentUserId: UUID?) async {
        do {
            try await api.respondInvite(id: inviteId, status: status)
            await load(api: api, currentUserId: currentUserId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

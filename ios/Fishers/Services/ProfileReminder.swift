import Foundation
import UserNotifications

/// A nudge on the phone to finish the profile — tomorrow evening, and again a
/// few days later if it is still not done.
///
/// Local notifications: they need no push setup, and they are rescheduled
/// every time the app opens, so somebody who uses the app daily is never
/// nagged (Home already shows them the card) while somebody who drifted away
/// hears about it once or twice. Nothing is asked for until the person taps
/// "Remind me"; after that, reminders follow the profile on their own.
enum ProfileReminder {
    private static let ids = ["fishers.profile.1", "fishers.profile.2"]

    /// Ask (once, when they asked to be reminded), then schedule.
    @discardableResult
    static func requestAndSchedule(for user: PublicUser) async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { await reschedule(for: user) }
        return granted
    }

    /// Push the reminders forward from now, or clear them once there is
    /// nothing left to ask for. Silent when notifications are not allowed.
    static func reschedule(for user: PublicUser) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        let strength = ProfileStrength(user)
        guard !strength.isComplete,
              await center.notificationSettings().authorizationStatus == .authorized
        else { return }

        for (id, days) in zip(ids, [1, 4]) {
            let content = UNMutableNotificationContent()
            content.title = "Finish your \(Brand.name) profile"
            content.body = "You're \(strength.percent)% there. \(strength.nextUp) so captains and clubs can see who they're picking."
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger(inDays: days)))
        }
    }

    /// Six in the evening, `days` from today — when people look at their phone
    /// about the weekend's game, not at the moment they signed up.
    static func trigger(inDays days: Int, from now: Date = .now, calendar: Calendar = .current) -> UNCalendarNotificationTrigger {
        let day = calendar.date(byAdding: .day, value: days, to: now) ?? now
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = 18
        return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    }
}

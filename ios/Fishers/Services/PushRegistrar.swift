import Foundation
import UIKit
import UserNotifications

/// Remote push: asking for permission, handing Apple's device token to the
/// API, and routing a tap.
///
/// The app already used *local* notifications for profile nudges, which need
/// no server at all. This is the other kind — the one that reaches a phone in
/// somebody's pocket when a match they were watching has finished and the
/// club's man-of-the-match vote has opened.
///
/// Registration is deliberately late and quiet. iOS only ever shows the
/// permission prompt once, so asking on the very first launch — before
/// anybody has joined a club or has any reason to want to hear from us —
/// spends that one chance on a stranger. Instead it is asked for after
/// sign-in, when there is a club behind it.
@MainActor
final class PushRegistrar: NSObject, ObservableObject {
    static let shared = PushRegistrar()

    /// The token last sent to the API, so a relaunch does not re-POST the
    /// same one on every cold start.
    private var registeredToken: String?

    /// Where a tapped notification wants to go. `RootView` watches this and
    /// opens the thread; it is cleared once it has.
    @Published var pendingConversation: UUID?
    @Published var pendingMotmPoll: UUID?

    private override init() { super.init() }

    /// Called once the app has a signed-in account.
    ///
    /// Asks for permission if it has not been asked before, and registers
    /// with APNs when it is granted. A refusal is final and silent: iOS will
    /// not ask again, and pestering somebody through an in-app alert for a
    /// permission the system has already recorded is worse than doing without.
    func start() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let settings = await center.notificationSettings()
        let granted: Bool
        switch settings.authorizationStatus {
        case .notDetermined:
            granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            granted = false
        default:
            granted = true
        }
        guard granted else { return }

        // The token comes back through the app delegate, not from here.
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Apple's device token, as raw bytes. Sent up as hex, which is what the
    /// APNs URL wants — `/3/device/<hex>`.
    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard token != registeredToken else { return }
        registeredToken = token
        Task {
            do {
                try await FishersAPI.registerDevice(token: token, platform: "ios")
            } catch {
                // Worth a line in the log and nothing else: the notification
                // is stored server-side regardless, so the bell still fills
                // up and the only thing lost is the buzz in the pocket.
                registeredToken = nil
                print("push: could not register this device — \(error.localizedDescription)")
            }
        }
    }

    func didFailToRegister(error: Error) {
        // Routine on a Simulator without a paired push environment.
        print("push: APNs registration failed — \(error.localizedDescription)")
    }

    /// Stop pushing to this phone when somebody signs out of it. A shared
    /// family iPad would otherwise keep buzzing with the last person's club.
    func unregister() async {
        guard let token = registeredToken else { return }
        registeredToken = nil
        try? await FishersAPI.unregisterDevice(token: token)
    }

    /// Where a tapped notification should take somebody.
    func route(_ target: Target) {
        if let conversation = target.conversation { pendingConversation = conversation }
        if let poll = target.motmPoll { pendingMotmPoll = poll }
    }

    /// The two ids Fishers puts alongside `aps`, lifted out of a payload.
    ///
    /// A `[AnyHashable: Any]` cannot cross an actor boundary, so the reading
    /// happens where the notification arrives and only these two values are
    /// carried over to the main actor.
    struct Target: Sendable {
        var conversation: UUID?
        var motmPoll: UUID?

        init(_ userInfo: [AnyHashable: Any]) {
            conversation = (userInfo["conversation_id"] as? String).flatMap(UUID.init(uuidString:))
            motmPoll = (userInfo["motm_poll_id"] as? String).flatMap(UUID.init(uuidString:))
        }
    }
}

extension PushRegistrar: UNUserNotificationCenterDelegate {
    /// Show it even with the app open — but not while the person is already
    /// reading the thread it came from, which is the same rule the live
    /// stream's in-app banners use.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let target = Target(notification.request.content.userInfo)
        let alreadyReadingIt = await MainActor.run {
            target.conversation != nil && LiveAlerts.openThread == target.conversation
        }
        return alreadyReadingIt ? [] : [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let target = Target(response.notification.request.content.userInfo)
        await PushRegistrar.shared.route(target)
    }
}

/// The delegate exists only to receive the APNs token: SwiftUI's `App` has no
/// hook for it, so `UIApplicationDelegateAdaptor` supplies one.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in PushRegistrar.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in PushRegistrar.shared.didFailToRegister(error: error) }
    }
}

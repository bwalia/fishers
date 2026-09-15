import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published var user: PublicUser?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    func bootstrap() async {
        #if DEBUG
        // UI tests start from a known session: the Simulator keeps the last
        // run's in the keychain. Either signed out, or signed in as an account
        // the test made — which also spares every test the system "Save
        // Password?" prompt that the sign-in form brings up over the app.
        let launch = ProcessInfo.processInfo
        if launch.arguments.contains("-FishersSignOutOnLaunch") {
            // Awaited, not `signOut()`: that clears the tokens in a detached
            // task, which would land after the ones set below and wipe them.
            await NetworkService.shared.clearTokens()
            KeychainStore.delete("user_id")
            if let access = launch.environment["FISHERS_UITEST_ACCESS_TOKEN"],
               let refresh = launch.environment["FISHERS_UITEST_REFRESH_TOKEN"] {
                await NetworkService.shared.setTokens(access: access, refresh: refresh)
            } else {
                return
            }
        }
        #endif
        await NetworkService.shared.loadTokensFromKeychain()
        guard KeychainStore.get("access_token") != nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let me = try await FishersAPI.me()
            KeychainStore.set(me.id.uuidString, forKey: "user_id")
            user = me
            isAuthenticated = true
        } catch {
            await NetworkService.shared.clearTokens()
            isAuthenticated = false
        }
    }

    /// `role` is asked on the form, before there is an account to save it on,
    /// so it goes up straight after. Failing to save it is not worth failing
    /// the signup for: Home asks again when it is missing.
    func signUp(
        name: String, email: String?, phone: String?, password: String,
        role: RoleIntent? = nil
    ) async {
        await authenticate {
            try await FishersAPI.signup(
                name: name, email: email, phone: phone, password: password
            )
        }
        if isAuthenticated, let role {
            user = (try? await FishersAPI.setRoleIntent(role)) ?? user
        }
    }

    /// Picked on Home, or switched from the getting-started guide.
    func setRoleIntent(_ role: RoleIntent) async throws {
        user = try await FishersAPI.setRoleIntent(role)
    }

    /// A screen that got a fresher copy of the user (a verification, say).
    func adopt(_ fresh: PublicUser) {
        user = fresh
    }

    /// `identifier` is an email address or a mobile number; the API works out
    /// which, so the app does not have to guess.
    func login(identifier: String, password: String) async {
        await authenticate {
            try await FishersAPI.login(identifier: identifier, password: password)
        }
    }

    /// Just through the quick start: Home takes them on to the next thing —
    /// a club to start, or a profile link to send. Once.
    @Published var justStarted = false

    /// Signed in, and not yet past the quick start — the app opens there.
    var needsQuickStart: Bool {
        guard let user else { return false }
        return Self.needsQuickStart(user, defaults: .standard)
    }

    /// Anyone who has told us a sport is past it, on any device; somebody who
    /// skipped is past it on this one.
    nonisolated static func needsQuickStart(_ user: PublicUser, defaults: UserDefaults) -> Bool {
        user.profiles.isEmpty && !defaults.bool(forKey: quickStartKey(user.id))
    }

    nonisolated static func quickStartKey(_ id: UUID) -> String { "fishers:quick-start:\(id.uuidString)" }

    func finishQuickStart() {
        guard let user else { return }
        UserDefaults.standard.set(true, forKey: Self.quickStartKey(user.id))
        justStarted = true
        objectWillChange.send()
    }

    /// Saves the setup or edit form and adopts the user the API returns.
    func saveProfile(_ update: ProfileUpdate) async throws {
        user = try await FishersAPI.updateProfile(update)
    }

    /// Pulls the server's copy, including the reliability score it computes.
    func refreshProfile() async {
        guard isAuthenticated, let fresh = try? await FishersAPI.me() else { return }
        user = fresh
    }

    func signOut() {
        Task { await NetworkService.shared.clearTokens() }
        KeychainStore.delete("user_id")
        KeychainStore.delete("access_token")
        KeychainStore.delete("refresh_token")
        user = nil
        isAuthenticated = false
        errorMessage = nil
    }

    private func authenticate(_ work: () async throws -> AuthTokens) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let tokens = try await work()
            await NetworkService.shared.setTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
            // The selection card needs to know which row on the board is yours.
            KeychainStore.set(tokens.user.id.uuidString, forKey: "user_id")
            user = tokens.user
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

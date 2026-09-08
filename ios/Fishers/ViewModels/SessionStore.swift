import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published var user: PublicUser?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    func bootstrap() async {
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

    func signUp(name: String, email: String?, phone: String?, password: String) async {
        await authenticate {
            try await FishersAPI.signup(
                name: name, email: email, phone: phone, password: password
            )
        }
    }

    /// `identifier` is an email address or a mobile number; the API works out
    /// which, so the app does not have to guess.
    func login(identifier: String, password: String) async {
        await authenticate {
            try await FishersAPI.login(identifier: identifier, password: password)
        }
    }

    /// Signed in but hasn't told us how they play yet — the app opens here.
    var needsProfileSetup: Bool {
        guard let user else { return false }
        return !user.isProfileComplete
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

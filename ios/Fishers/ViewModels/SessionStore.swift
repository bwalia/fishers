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
            user = try await FishersAPI.me()
            isAuthenticated = true
        } catch {
            await NetworkService.shared.clearTokens()
            isAuthenticated = false
        }
    }

    func signUp(name: String, email: String, password: String) async {
        await authenticate {
            try await FishersAPI.signup(name: name, email: email, password: password)
        }
    }

    func login(email: String, password: String) async {
        await authenticate {
            try await FishersAPI.login(email: email, password: password)
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
        Task {
            await NetworkService.shared.clearTokens()
        }
        user = nil
        isAuthenticated = false
    }

    private func authenticate(_ work: () async throws -> AuthTokens) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let tokens = try await work()
            await NetworkService.shared.setTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
            user = tokens.user
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

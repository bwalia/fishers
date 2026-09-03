import Foundation
import Observation

/// Session + environment state for the whole app. Demo mode (default on) swaps
/// the live `APIClient` for `MockAPIClient` so the app runs without a backend.
@Observable
final class AppState {
    private(set) var currentUser: User?
    private(set) var demoMode: Bool
    private(set) var api: FishersAPI

    private let authService = AuthService()
    private static let demoModeKey = "demoMode"
    private static let demoProfileKey = "demoProfile"

    init(demoMode: Bool? = nil) {
        let demo = demoMode ?? (UserDefaults.standard.object(forKey: Self.demoModeKey) as? Bool ?? true)
        self.demoMode = demo
        if demo {
            let user = Self.savedDemoProfile() ?? MockData.newUser
            self.api = MockAPIClient(profile: user)
            self.currentUser = user
        } else {
            self.api = APIClient(auth: authService)
            self.currentUser = nil
        }
    }

    var isSignedIn: Bool { currentUser != nil }

    /// Signed in but hasn't told us how they play yet — the app opens here.
    var needsProfileSetup: Bool {
        guard let currentUser else { return false }
        return !currentUser.isProfileComplete
    }

    /// The demo user captains the Lords 1st XI, unlocking the squad picker.
    var isCaptainOrAdmin: Bool {
        guard let currentUser else { return false }
        if demoMode { return true }
        return MockData.members.contains {
            $0.userId == currentUser.id && ($0.role == .captain || $0.role == .admin)
        }
    }

    func setDemoMode(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.demoModeKey)
        demoMode = on
        if on {
            let user = Self.savedDemoProfile() ?? MockData.newUser
            api = MockAPIClient(profile: user)
            currentUser = user
        } else {
            api = APIClient(auth: authService)
            currentUser = nil
        }
    }

    func login(email: String, password: String) async throws {
        let response = try await authService.login(email: email, password: password)
        api = APIClient(auth: authService)
        currentUser = response.user
    }

    func signup(name: String, email: String, password: String) async throws {
        let response = try await authService.signup(name: name, email: email, password: password)
        api = APIClient(auth: authService)
        currentUser = response.user
    }

    /// Saves the profile-setup form and adopts the user the server returns.
    @discardableResult
    func saveProfile(_ update: ProfileUpdate) async throws -> User {
        let user = try await api.updateProfile(update)
        currentUser = user
        persistDemoProfile(user)
        return user
    }

    /// Pulls the server's copy (including the reliability score it computes).
    func refreshProfile() async {
        guard let user = try? await api.me() else { return }
        currentUser = user
        persistDemoProfile(user)
    }

    /// Demo only: wipes the saved profile so setup runs again from the top.
    func restartProfileSetup() {
        guard demoMode else { return }
        UserDefaults.standard.removeObject(forKey: Self.demoProfileKey)
        api = MockAPIClient(profile: MockData.newUser)
        currentUser = MockData.newUser
    }

    func signOut() {
        authService.logout()
        if demoMode {
            setDemoMode(false)
        }
        currentUser = nil
    }

    // MARK: Demo persistence

    /// Demo mode has no backend, so the profile lives in UserDefaults and
    /// survives relaunches the way a real account would.
    private func persistDemoProfile(_ user: User) {
        guard demoMode, let data = try? JSONEncoder().encode(user) else { return }
        UserDefaults.standard.set(data, forKey: Self.demoProfileKey)
    }

    private static func savedDemoProfile() -> User? {
        guard let data = UserDefaults.standard.data(forKey: demoProfileKey) else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }
}

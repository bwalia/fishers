import Foundation

/// Handles the unauthenticated /auth endpoints and token storage.
/// `APIClient` uses it for bearer injection and 401 auto-refresh.
final class AuthService {
    let keychain = KeychainStore()

    var accessToken: String? { keychain.get(.accessToken) }
    var refreshToken: String? { keychain.get(.refreshToken) }
    var isAuthenticated: Bool { accessToken != nil }

    func signup(name: String, email: String, password: String) async throws -> AuthResponse {
        try await authRequest(path: "/auth/signup", body: SignupRequest(name: name, email: email, password: password))
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await authRequest(path: "/auth/login", body: LoginRequest(email: email, password: password))
    }

    /// Exchanges the refresh token for a new token pair. Throws `.unauthorized` if that fails.
    @discardableResult
    func refresh() async throws -> String {
        guard let token = refreshToken else { throw APIError.unauthorized }
        do {
            let response: AuthResponse = try await authRequest(path: "/auth/refresh", body: RefreshRequest(refreshToken: token))
            return response.accessToken
        } catch {
            keychain.clear()
            throw APIError.unauthorized
        }
    }

    func logout() {
        keychain.clear()
    }

    private func authRequest<B: Encodable>(path: String, body: B) async throws -> AuthResponse {
        guard let url = URL(string: APIConfig.apiPrefix + path, relativeTo: APIConfig.baseURL) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try APICoding.encoder.encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(statusCode: 0, message: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? APICoding.decoder.decode(ServerErrorBody.self, from: data))
                .flatMap { $0.message ?? $0.error }
            throw APIError.server(statusCode: http.statusCode, message: message)
        }
        do {
            let auth = try APICoding.decoder.decode(AuthResponse.self, from: data)
            keychain.set(auth.accessToken, for: .accessToken)
            keychain.set(auth.refreshToken, for: .refreshToken)
            return auth
        } catch {
            throw APIError.decoding(error)
        }
    }
}

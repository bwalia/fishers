import Foundation

struct AuthResponse: Codable {
    var user: User
    var accessToken: String
    var refreshToken: String
}

struct SignupRequest: Codable {
    var name: String
    var email: String
    var password: String
}

struct LoginRequest: Codable {
    var email: String
    var password: String
}

struct RefreshRequest: Codable {
    var refreshToken: String
}

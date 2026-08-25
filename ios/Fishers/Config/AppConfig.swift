import Foundation

enum AppConfig {
    /// Simulator → host machine. Device builds should point at your LAN IP or staging host.
    static let apiBaseURL = URL(string: "http://localhost:8080")!
    static let apiVersionPrefix = "/api/v1"
}

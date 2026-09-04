import Foundation

enum AppConfig {
    /// Simulator talks to the Mac host. Prefer 127.0.0.1 over `localhost`
    /// to avoid IPv6 (::1) connection refused when the API listens on IPv4 only.
    /// Physical devices need your Mac's LAN IP instead (e.g. http://192.168.x.x:8080).
    static var apiBaseURL: URL {
        #if targetEnvironment(simulator)
        return URL(string: "http://127.0.0.1:8080")!
        #else
        if let override = ProcessInfo.processInfo.environment["FISHERS_API_URL"],
           let url = URL(string: override) {
            return url
        }
        return URL(string: "http://127.0.0.1:8080")!
        #endif
    }

    static let apiVersionPrefix = "/api/v1"
}

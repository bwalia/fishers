import Foundation

enum AppConfig {
    /// Where the API lives.
    ///
    /// Resolution order, most specific first:
    ///   1. `FISHERS_API_URL` in the environment — Xcode schemes and UI tests.
    ///   2. `FishersAPIBaseURL` in Info.plist — set per build configuration, and
    ///      the only one that reaches a TestFlight or App Store build.
    ///   3. The Simulator's host loopback, for a laptop running the API.
    ///
    /// A release build with no Info.plist value is a configuration mistake, so
    /// it says so loudly in the log rather than silently dialling localhost.
    static let apiBaseURL: URL = {
        if let override = ProcessInfo.processInfo.environment["FISHERS_API_URL"],
           let url = URL(string: override) {
            return url
        }
        if let configured = Bundle.main.object(forInfoDictionaryKey: "FishersAPIBaseURL") as? String,
           !configured.isEmpty,
           !configured.hasPrefix("$("),
           let url = URL(string: configured) {
            return url
        }
        #if DEBUG
        // LAN Mac running the API (physical iPhone). Prefer this over loopback:
        // a device cannot reach the Mac via 127.0.0.1.
        return URL(string: "http://192.168.1.99:8080")!
        #else
        assertionFailure("FishersAPIBaseURL is not set for this build configuration")
        NSLog("[Fishers] FishersAPIBaseURL is not set — falling back to LAN default.")
        return URL(string: "http://192.168.1.99:8080")!
        #endif
    }()

    static let apiVersionPrefix = "/api/v1"

    /// Public web host for live scoreboard links shared into chat.
    ///
    /// Resolved the same way as `apiBaseURL`, and for the same reason: a
    /// hardcoded loopback address is a link nobody outside the Simulator can
    /// open, which is the one thing a share link must not be.
    static let webBaseURL: URL = {
        if let override = ProcessInfo.processInfo.environment["FISHERS_WEB_URL"],
           let url = URL(string: override) {
            return url
        }
        if let configured = Bundle.main.object(forInfoDictionaryKey: "FishersWebBaseURL") as? String,
           !configured.isEmpty,
           !configured.hasPrefix("$("),
           let url = URL(string: configured) {
            return url
        }
        #if DEBUG
        return URL(string: "http://192.168.1.99:3000")!
        #else
        assertionFailure("FishersWebBaseURL is not set for this build configuration")
        NSLog("[Fishers] FishersWebBaseURL is not set — shared live links will point at LAN default.")
        return URL(string: "http://192.168.1.99:3000")!
        #endif
    }()

    /// Shown when a build cannot reach its API, so the person holding the phone
    /// can say which server it was trying.
    static var displayHost: String {
        apiBaseURL.host.map { host in
            apiBaseURL.port.map { "\(host):\($0)" } ?? host
        } ?? apiBaseURL.absoluteString
    }
}

import Foundation

enum AppConfig {
    /// LAN Mac that hosts the API/web during local device + Simulator testing.
    private static let lanAPIBase = "http://192.168.1.99:8080"
    private static let lanWebBase = "http://192.168.1.99:3000"

    /// Where the API lives.
    ///
    /// Resolution order, most specific first:
    ///   1. `FISHERS_API_URL` in the environment — Xcode schemes and UI tests.
    ///   2. Debug builds: always the LAN Mac (loopback is useless on a phone).
    ///   3. `FishersAPIBaseURL` in Info.plist — Release / TestFlight / App Store.
    ///
    /// Stale Xcode projects sometimes still expand Info.plist to 127.0.0.1;
    /// Debug ignores that so a physical iPhone can reach the API on the LAN.
    static let apiBaseURL: URL = {
        let resolved: URL = {
            if let override = ProcessInfo.processInfo.environment["FISHERS_API_URL"],
               let url = URL(string: override),
               !isLoopback(url) {
                return url
            }
            #if DEBUG
            return URL(string: lanAPIBase)!
            #else
            if let configured = Bundle.main.object(forInfoDictionaryKey: "FishersAPIBaseURL") as? String,
               let url = usableRemoteURL(configured) {
                return url
            }
            assertionFailure("FishersAPIBaseURL is not set for this build configuration")
            NSLog("[Fishers] FishersAPIBaseURL is not set — falling back to LAN default.")
            return URL(string: lanAPIBase)!
            #endif
        }()
        NSLog("[Fishers] API base URL → %@", resolved.absoluteString)
        return resolved
    }()

    static let apiVersionPrefix = "/api/v1"

    /// Public web host for live scoreboard links shared into chat.
    static let webBaseURL: URL = {
        let resolved: URL = {
            if let override = ProcessInfo.processInfo.environment["FISHERS_WEB_URL"],
               let url = URL(string: override),
               !isLoopback(url) {
                return url
            }
            #if DEBUG
            return URL(string: lanWebBase)!
            #else
            if let configured = Bundle.main.object(forInfoDictionaryKey: "FishersWebBaseURL") as? String,
               let url = usableRemoteURL(configured) {
                return url
            }
            assertionFailure("FishersWebBaseURL is not set for this build configuration")
            NSLog("[Fishers] FishersWebBaseURL is not set — shared live links will point at LAN default.")
            return URL(string: lanWebBase)!
            #endif
        }()
        NSLog("[Fishers] Web base URL → %@", resolved.absoluteString)
        return resolved
    }()

    /// Shown when a build cannot reach its API, so the person holding the phone
    /// can say which server it was trying.
    static var displayHost: String {
        apiBaseURL.host.map { host in
            apiBaseURL.port.map { "\(host):\($0)" } ?? host
        } ?? apiBaseURL.absoluteString
    }

    /// Loopback / empty / unsubstituted plist values are not reachable from a phone.
    private static func usableRemoteURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$("), let url = URL(string: trimmed) else {
            return nil
        }
        guard !isLoopback(url) else { return nil }
        return url
    }

    private static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}

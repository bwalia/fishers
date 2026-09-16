import Foundation

enum AppConfig {
    /// Simulator fallback: loopback on the Mac's stack (same as Debug Info.plist).
    private static let simulatorAPIBase = "http://127.0.0.1:7312"
    private static let simulatorWebBase = "http://127.0.0.1:7311"

    /// Physical-device Debug fallback when nothing else is set: the Mac Studio's
    /// Wi-Fi address where local Xcode testing runs the API. A phone on the same
    /// Wi-Fi cannot use 127.0.0.1 — that is the phone itself — and without this
    /// the app looks like the API is down.
    private static let deviceLANAPIBase = "http://192.168.1.177:8080"
    private static let deviceLANWebBase = "http://192.168.1.177:7311"

    /// Where the API lives.
    ///
    /// Resolution order, most specific first:
    ///   1. `FISHERS_API_URL` in the environment — `scripts/start.sh`, Xcode
    ///      schemes, UI tests.
    ///   2. `FishersAPIBaseURL` in UserDefaults — written into the Simulator's
    ///      defaults by `scripts/start.sh` so a relaunch from the home screen or
    ///      from Xcode keeps the same server, and settable for one launch with
    ///      the `-FishersAPIBaseURL <url>` argument Foundation reads into the
    ///      argument domain.
    ///   3. `FishersAPIBaseURL` in Info.plist — Release / TestFlight / App Store.
    ///   4. Fallback: Simulator → loopback; physical device (Debug) → the LAN
    ///      Mac at `192.168.1.177:8080` so a phone on Wi-Fi reaches the API
    ///      without a scheme override.
    static let apiBaseURL: URL = resolve(
        env: "FISHERS_API_URL",
        key: "FishersAPIBaseURL",
        fallback: deviceAwareFallback(api: true),
        label: "API"
    )

    static let apiVersionPrefix = "/api/v1"

    /// Public web host for live scoreboard links shared into chat.
    static let webBaseURL: URL = resolve(
        env: "FISHERS_WEB_URL",
        key: "FishersWebBaseURL",
        fallback: deviceAwareFallback(api: false),
        label: "Web"
    )

    /// Loopback on Simulator; LAN Mac on a real device. Release still fails
    /// closed via empty Info.plist values before this is reached in practice.
    private static func deviceAwareFallback(api: Bool) -> String {
        #if targetEnvironment(simulator)
        return api ? simulatorAPIBase : simulatorWebBase
        #else
        return api ? deviceLANAPIBase : deviceLANWebBase
        #endif
    }

    /// Shown when a build cannot reach its API, so the person holding the phone
    /// can say which server it was trying.
    static var displayHost: String {
        apiBaseURL.host.map { host in
            apiBaseURL.port.map { "\(host):\($0)" } ?? host
        } ?? apiBaseURL.absoluteString
    }

    private static func resolve(env: String, key: String, fallback: String, label: String) -> URL {
        let sources: [(String, String?)] = [
            ("environment", ProcessInfo.processInfo.environment[env]),
            ("defaults", UserDefaults.standard.string(forKey: key)),
            ("Info.plist", Bundle.main.object(forInfoDictionaryKey: key) as? String),
        ]

        for (origin, raw) in sources {
            guard let url = usableURL(raw) else { continue }
            NSLog("[Fishers] %@ base URL → %@ (from %@)", label, url.absoluteString, origin)
            return url
        }

        #if !DEBUG
        assertionFailure("\(key) is not set for this build configuration")
        NSLog("[Fishers] %@ is not set — falling back to %@.", key, fallback)
        #endif
        NSLog("[Fishers] %@ base URL → %@ (fallback)", label, fallback)
        return URL(string: fallback)!
    }

    /// Empty and unsubstituted (`$(FISHERS_API_BASE_URL)`) values are not hosts.
    /// On the Simulator, loopback is honoured — that is the right address there.
    /// On a physical phone, loopback is the phone itself, so Debug Info.plist's
    /// `127.0.0.1` must not win over the LAN fallback; reject it here so
    /// resolution falls through to `192.168.1.177:8080` (or an explicit
    /// FISHERS_API_URL / UserDefaults override that names a real host).
    private static func usableURL(_ raw: String?) -> URL? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !trimmed.hasPrefix("$("),
              let url = URL(string: trimmed),
              let host = url.host
        else { return nil }
        #if !targetEnvironment(simulator)
        if host == "127.0.0.1" || host == "localhost" || host == "::1" {
            return nil
        }
        #endif
        return url
    }
}

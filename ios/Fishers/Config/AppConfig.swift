import Foundation

enum AppConfig {
    /// The Simulator shares the Mac's network stack, so loopback is the one
    /// address that is right without knowing today's DHCP lease. Physical
    /// devices need the Mac's LAN address, which `scripts/start.sh` resolves at
    /// launch and passes in — no address is compiled into the app.
    private static let fallbackAPIBase = "http://127.0.0.1:7312"
    private static let fallbackWebBase = "http://127.0.0.1:7311"

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
    ///   4. Loopback, which is correct on the Simulator and useless anywhere else.
    ///
    /// A LAN address baked in at build time was the old behaviour and it broke
    /// every time the Mac's lease changed, in a way that looked like the API
    /// being down. Nothing here is fixed at compile time except the last resort.
    static let apiBaseURL: URL = resolve(
        env: "FISHERS_API_URL",
        key: "FishersAPIBaseURL",
        fallback: fallbackAPIBase,
        label: "API"
    )

    static let apiVersionPrefix = "/api/v1"

    /// Public web host for live scoreboard links shared into chat.
    static let webBaseURL: URL = resolve(
        env: "FISHERS_WEB_URL",
        key: "FishersWebBaseURL",
        fallback: fallbackWebBase,
        label: "Web"
    )

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
    /// Loopback *is* honoured when it is asked for explicitly — that is the
    /// right address on the Simulator, and rejecting it was why an override
    /// could not point the Simulator at a local API.
    private static func usableURL(_ raw: String?) -> URL? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !trimmed.hasPrefix("$("),
              let url = URL(string: trimmed),
              url.host != nil
        else { return nil }
        return url
    }
}

import Foundation

enum AppConfig {
    /// Simulator fallback: loopback on the Mac's stack (same as Debug Info.plist).
    private static let simulatorAPIBase = "http://127.0.0.1:7312"
    private static let simulatorWebBase = "http://127.0.0.1:7311"

    /// Physical-device fallback when nothing else is set: the Mac Studio's
    /// Wi-Fi address where local Xcode testing runs the API. A phone on the same
    /// Wi-Fi cannot use 127.0.0.1 — that is the phone itself — and without this
    /// the app looks like the API is down.
    private static let deviceLANAPIBase = "http://192.168.1.177:8080"
    private static let deviceLANWebBase = "http://192.168.1.177:7311"

    /// UserDefaults / launch-argument key written by Settings and `scripts/start.sh`.
    static let apiDefaultsKey = "FishersAPIBaseURL"
    static let webDefaultsKey = "FishersWebBaseURL"

    /// Where the API lives — re-read on every access so a Settings override
    /// applies to the next request without restarting the app.
    ///
    /// Resolution order, most specific first:
    ///   1. `FISHERS_API_URL` in the environment — `scripts/start.sh`, Xcode
    ///      schemes, UI tests. Wins over Settings.
    ///   2. `FishersAPIBaseURL` in UserDefaults — Settings panel, `start.sh`,
    ///      or `-FishersAPIBaseURL <url>` launch argument.
    ///   3. `FishersAPIBaseURL` in Info.plist — Release / TestFlight / App Store.
    ///   4. Fallback: Simulator → loopback; physical device → LAN Mac at
    ///      `192.168.1.177:8080`.
    static var apiBaseURL: URL {
        resolve(
            env: "FISHERS_API_URL",
            key: apiDefaultsKey,
            fallback: deviceAwareFallback(api: true)
        )
    }

    static let apiVersionPrefix = "/api/v1"

    /// Public web host for live scoreboard links shared into chat.
    static var webBaseURL: URL {
        resolve(
            env: "FISHERS_WEB_URL",
            key: webDefaultsKey,
            fallback: deviceAwareFallback(api: false)
        )
    }

    /// Loopback on Simulator; LAN Mac on a real device. Release still fails
    /// closed via empty Info.plist values before this is reached in practice.
    private static func deviceAwareFallback(api: Bool) -> String {
        #if targetEnvironment(simulator)
        return api ? simulatorAPIBase : simulatorWebBase
        #else
        return api ? deviceLANAPIBase : deviceLANWebBase
        #endif
    }

    /// Built-in default the Settings "Reset" control restores to (ignores env).
    static var defaultAPIBaseURL: URL {
        URL(string: deviceAwareFallback(api: true))!
    }

    /// True when an Xcode scheme / `start.sh` env var is pinning the API —
    /// UserDefaults Settings cannot override that for this process.
    static var environmentPinsAPI: Bool {
        usableURL(ProcessInfo.processInfo.environment["FISHERS_API_URL"]) != nil
    }

    /// Raw UserDefaults override, if any (may differ from `apiBaseURL` when env wins).
    static var storedAPIOverride: String? {
        UserDefaults.standard.string(forKey: apiDefaultsKey)
    }

    /// Persist an API base URL for subsequent requests. Rejects empty /
    /// unsubstituted / (on device) loopback values.
    @discardableResult
    static func setAPIBaseURLOverride(_ raw: String) throws -> URL {
        guard let url = usableURL(raw) else {
            throw APIConfigError.invalidURL
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw APIConfigError.invalidURL
        }
        UserDefaults.standard.set(url.absoluteString, forKey: apiDefaultsKey)
        NSLog("[Fishers] API base URL → %@ (from settings)", url.absoluteString)
        return url
    }

    /// Remove the Settings / UserDefaults override so Info.plist + fallback apply.
    static func clearAPIBaseURLOverride() {
        UserDefaults.standard.removeObject(forKey: apiDefaultsKey)
        NSLog("[Fishers] API base URL override cleared → %@", apiBaseURL.absoluteString)
    }

    /// Shown when a build cannot reach its API, so the person holding the phone
    /// can say which server it was trying.
    static var displayHost: String {
        apiBaseURL.host.map { host in
            apiBaseURL.port.map { "\(host):\($0)" } ?? host
        } ?? apiBaseURL.absoluteString
    }

    private static func resolve(env: String, key: String, fallback: String) -> URL {
        let sources: [String?] = [
            ProcessInfo.processInfo.environment[env],
            UserDefaults.standard.string(forKey: key),
            Bundle.main.object(forInfoDictionaryKey: key) as? String,
        ]

        for raw in sources {
            if let url = usableURL(raw) { return url }
        }

        #if !DEBUG
        assertionFailure("\(key) is not set for this build configuration")
        #endif
        return URL(string: fallback)!
    }

    /// Empty and unsubstituted (`$(FISHERS_API_BASE_URL)`) values are not hosts.
    /// On the Simulator, loopback is honoured — that is the right address there.
    /// On a physical phone, loopback is the phone itself, so Debug Info.plist's
    /// `127.0.0.1` must not win over the LAN fallback; reject it here so
    /// resolution falls through to `192.168.1.177:8080` (or an explicit
    /// Settings / `FISHERS_API_URL` override that names a real host).
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

enum APIConfigError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            #if targetEnvironment(simulator)
            return "Enter a full URL such as http://127.0.0.1:7312 or https://int.fishers.cloud"
            #else
            return "Enter a full URL such as http://192.168.1.177:8080 or https://int.fishers.cloud — not localhost on a phone"
            #endif
        }
    }
}

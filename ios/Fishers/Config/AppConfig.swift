import Foundation

enum AppConfig {
    /// Simulator fallback: loopback on the Mac's stack.
    ///
    /// The ports are `scripts/start.sh`'s own defaults. They are not the
    /// authority on where the stack is — `.env` moves them, and project.yml
    /// substitutes whatever start.sh exported into Info.plist, which is read
    /// first. This is only what a build lands on when that substitution never
    /// happened, which is why it names the documented default rather than
    /// guessing.
    private static let simulatorAPIBase = "http://127.0.0.1:\(defaultAPIPort)"
    private static let simulatorWebBase = "http://127.0.0.1:\(defaultWebPort)"

    /// The ports `.env.example` ships and `scripts/start.sh` falls back to,
    /// deliberately off the beaten track so the stack does not fight Postgres
    /// on 5432 or another dev server on 8080.
    static let defaultAPIPort = 7312
    static let defaultWebPort = 7311

    /// Physical-device fallback: production. A phone cannot use 127.0.0.1 —
    /// that is the phone itself — and a LAN address here shipped to TestFlight,
    /// where a tester's network has no such host (or worse, some unrelated box
    /// answering on that address). Prod is the only fallback that is right for
    /// a build in someone else's hands; point a device at a local API with the
    /// Settings panel or `FISHERS_API_URL`.
    private static let deviceAPIBase = "https://www.fishers.cloud"
    private static let deviceWebBase = "https://www.fishers.cloud"

    /// UserDefaults / launch-argument key written by Settings and `scripts/start.sh`.
    static let apiDefaultsKey = "FishersAPIBaseURL"
    static let webDefaultsKey = "FishersWebBaseURL"

    /// Info.plist keys carrying the Mac's LAN address, written by project.yml
    /// in the Debug config only. Never a UserDefaults key: nothing writes
    /// these at runtime, they are what the build was generated against.
    static let lanAPIInfoKey = "FishersLANAPIBaseURL"
    static let lanWebInfoKey = "FishersLANWebBaseURL"

    /// The Mac's API on the Wi-Fi, if this build has one to offer.
    ///
    /// `nil` in Release, and `nil` in a Debug build generated without
    /// `scripts/start.sh` — the plist key is then empty, or names a host that
    /// is not a usable address from a phone.
    static var lanAPIBase: URL? { lanBase(lanAPIInfoKey) }
    static var lanWebBase: URL? { lanBase(lanWebInfoKey) }

    private static func lanBase(_ key: String) -> URL? {
        #if DEBUG
        return usableURL(Bundle.main.object(forInfoDictionaryKey: key) as? String)
        #else
        // A LAN address has no meaning in a build that has left this machine.
        return nil
        #endif
    }

    /// What this build was compiled to talk to, before any override. Shown as
    /// a Settings preset so the panel offers the build's own port rather than
    /// a number typed into the source years ago.
    static var buildAPIBase: URL? {
        usableURL(Bundle.main.object(forInfoDictionaryKey: apiDefaultsKey) as? String)
    }

    /// Where the API lives — re-read on every access so a Settings override
    /// applies to the next request without restarting the app.
    ///
    /// Resolution order, most specific first:
    ///   1. `FISHERS_API_URL` in the environment — `scripts/start.sh`, Xcode
    ///      schemes, UI tests. Wins over Settings.
    ///   2. `FishersAPIBaseURL` in UserDefaults — Settings panel, `start.sh`,
    ///      or `-FishersAPIBaseURL <url>` launch argument.
    ///   3. `FishersAPIBaseURL` in Info.plist — Release / TestFlight / App Store.
    ///   4. Fallback: Simulator → loopback; physical device → production.
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

    /// Loopback on the Simulator, the Mac's Wi-Fi address on a tethered Debug
    /// build, production everywhere else. Release sets both hosts in
    /// Info.plist; this is what a build reaches for when that substitution has
    /// gone wrong, so it has to be somewhere safe to land.
    ///
    /// The device Debug case is the one that is not merely "safe": a phone
    /// plugged into this Mac is here to talk to this Mac, and falling through
    /// to production meant every such run began by typing a LAN address into
    /// Settings. It is `#if DEBUG` and the key is empty in Release, so a
    /// TestFlight build still lands on production — a tester's network has no
    /// such host, or worse, something unrelated answering on it.
    private static func deviceAwareFallback(api: Bool) -> String {
        #if targetEnvironment(simulator)
        return api ? simulatorAPIBase : simulatorWebBase
        #else
        if let lan = api ? lanAPIBase : lanWebBase {
            return lan.absoluteString
        }
        return api ? deviceAPIBase : deviceWebBase
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

    /// Empty and unsubstituted values are not hosts. Two spellings reach here:
    /// Xcode's own `$(FISHERS_API_BASE_URL)`, when a build setting is missing,
    /// and XcodeGen's `${API_PORT}`, when the spec was generated without the
    /// ports exported. Both mean "nobody filled this in", and both must lose to
    /// the fallback rather than be parsed into a URL nothing answers on.
    ///
    /// On the Simulator, loopback is honoured — that is the right address there.
    /// On a physical phone, loopback is the phone itself, so Debug Info.plist's
    /// `127.0.0.1` must not win over the fallback; reject it here so resolution
    /// falls through to production (or an explicit Settings / `FISHERS_API_URL`
    /// override that names a real host).
    private static func usableURL(_ raw: String?) -> URL? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !trimmed.hasPrefix("$("),
              !trimmed.contains("${"),
              let url = URL(string: trimmed),
              // Non-nil is not enough: "http://:7312" parses, and its host is
              // the empty string rather than nil. That is what project.yml's
              // LAN address collapses to when LAN_IP was never exported, and
              // it has to read as "no address" rather than be dialled.
              let host = url.host, !host.isEmpty
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
            return "Enter a full URL such as http://127.0.0.1:\(AppConfig.defaultAPIPort) or https://int.fishers.cloud"
            #else
            return "Enter a full URL such as https://int.fishers.cloud or http://192.168.1.10:\(AppConfig.defaultAPIPort) — not localhost on a phone"
            #endif
        }
    }
}

import Foundation
import SwiftUI

/// What the app says, in the language the person reads.
///
/// The same dictionary the website uses, generated into the bundle by
/// `tools/i18n`. The rules below are the web's rules, deliberately — a club
/// whose secretary reads Punjabi on a laptop and Punjabi on a phone is one
/// product, and two sets of plural rules would be two products that disagree
/// about what a wicket is called.
///
///   - a key is `area.thing`, and `t("nav.home")` returns it
///   - `{name}` in a string is replaced from `vars`
///   - a plural is two keys, `.one` and `.other`, picked by `count`
///   - **fallback is per key, not per language**: a half-translated language
///     shows what it has and English for the rest. Falling back to the key
///     would put `moment.hat_trick` on a live scoreboard.
enum Strings {
    /// Loaded once. ~2,650 keys per language is 150–270KB of JSON; decoding it
    /// is a few milliseconds and happens on the first string the app asks for.
    private static let tables: [Language: [String: String]] = {
        var out: [Language: [String: String]] = [:]
        for language in Language.allCases {
            guard let url = Bundle.main.url(forResource: language.rawValue, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let table = try? JSONDecoder().decode([String: String].self, from: data)
            else {
                // Not fatal on purpose: a missing table means that language
                // falls back to English, which is a worse app rather than no
                // app. StringsTests is what makes sure it does not happen.
                assertionFailure("no string table for \(language.rawValue) in the bundle")
                continue
            }
            out[language] = table
        }
        return out
    }()

    /// The key a lookup should actually use.
    ///
    /// With a count, the plural form if the dictionary has one. Without, the
    /// key itself — and for a plural stem asked without a count, the `.other`
    /// form, because the general wording beats printing the stem.
    static func resolve(_ key: String, count: Int?) -> String {
        let english = tables[.fallback] ?? [:]
        if let count {
            let form = "\(key).\(count == 1 ? "one" : "other")"
            if english[form] != nil { return form }
        }
        if english[key] != nil { return key }
        let other = "\(key).other"
        return english[other] != nil ? other : key
    }

    /// One string, in `language`.
    static func t(
        _ key: String,
        language: Language,
        count: Int? = nil,
        vars: [String: CustomStringConvertible] = [:]
    ) -> String {
        let form = resolve(key, count: count)
        var out = tables[language]?[form] ?? tables[.fallback]?[form] ?? form
        if count != nil, vars["count"] == nil {
            out = out.replacingOccurrences(of: "{count}", with: String(count ?? 0))
        }
        for (name, value) in vars {
            out = out.replacingOccurrences(of: "{\(name)}", with: value.description)
        }
        return out
    }

    /// The language to use when nobody says.
    ///
    /// `LanguageStore` is the observable SwiftUI watches, and it is
    /// `@MainActor`. Strings are needed off the main actor too — a model's
    /// computed label, a formatter — so the value lives here behind a lock
    /// rather than behind an actor, and `t()` works from anywhere. It is
    /// written only when somebody uses the picker.
    private static let languageLock = NSLock()
    nonisolated(unsafe) private static var chosen: Language = .fallback

    static var current: Language {
        languageLock.lock()
        defer { languageLock.unlock() }
        return chosen
    }

    static func setCurrent(_ language: Language) {
        languageLock.lock()
        chosen = language
        languageLock.unlock()
    }

    /// English text back to the key that holds it, for `tr`.
    private static let keyForEnglish: [String: String] = {
        var out: [String: String] = [:]
        for (key, text) in tables[.fallback] ?? [:] {
            let plain = Self.plain(text)
            // Shortest key wins, so the general one is found rather than a
            // screen-specific duplicate — the rule the converters use.
            if let existing = out[plain], existing.count <= key.count { continue }
            out[plain] = key
        }
        return out
    }()

    /// Typographic punctuation in the dictionary, straight in the source.
    static func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
    }

    static func key(forEnglish english: String) -> String? { keyForEnglish[plain(english)] }

    /// Every key the tables carry, for the test that checks what the app asks
    /// for against what exists.
    static func keys(for language: Language) -> Set<String> {
        Set(tables[language]?.keys ?? [:].keys)
    }
}

/// The reader's language, and the one thing that changes it.
///
/// `@AppStorage`-backed rather than a plain `@Published` so the choice survives
/// a relaunch, which is the whole point of asking. The web keeps this in a
/// cookie for the same reason.
@MainActor
final class LanguageStore: ObservableObject {
    /// The one the global `t()` reads.
    ///
    /// A singleton as well as an environment object, for the same reason the
    /// web has both `useT()` and `clientT()`: most of what needs a string is a
    /// view, but plenty is not — a view model building an error, a formatter,
    /// a static helper — and threading a store down to all of them would mean
    /// changing every call site in the app to fix the wording in one.
    static let shared = LanguageStore()

    private static let key = "FishersLanguage"

    @Published private(set) var language: Language {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.key)
            Strings.setCurrent(language)
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.key),
           let chosen = Language(rawValue: saved) {
            language = chosen
        } else {
            language = Self.fromSystem()
        }
        // `didSet` does not fire for a value assigned in `init`.
        Strings.setCurrent(language)
    }

    /// What the phone is already set to, for somebody who has never opened the
    /// picker. `Locale.preferredLanguages` gives tags like `pa-Guru-IN`, and
    /// the product cares only about the first subtag — the web's `localeFrom`
    /// does the same thing to a cookie or an Accept-Language header.
    static func fromSystem() -> Language {
        for tag in Foundation.Locale.preferredLanguages {
            let base = tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? tag
            if let match = Language(rawValue: base.lowercased()) { return match }
        }
        return .fallback
    }

    func set(_ next: Language) {
        guard next != language else { return }
        language = next
    }

    /// `t("nav.home")` — the same call the web makes.
    func t(
        _ key: String,
        count: Int? = nil,
        vars: [String: CustomStringConvertible] = [:]
    ) -> String {
        Strings.t(key, language: language, count: count, vars: vars)
    }
}



/// `t("nav.home")` from anywhere — a view, a view model, a formatter.
///
/// Not `@MainActor`: a model's computed label needs a string too, and making
/// every one of those main-actor bound to read a dictionary would be the tail
/// wagging the dog. `Strings.current` is lock-guarded for exactly this.
func t(
    _ key: String,
    count: Int? = nil,
    vars: [String: CustomStringConvertible] = [:]
) -> String {
    Strings.t(key, language: Strings.current, count: count, vars: vars)
}

/// Translate a string by its English text rather than by a key.
///
/// For the places where the literal is also a *value*: a position stored on a
/// profile, an enum's backing string, a filter that is compared by equality.
/// There, swapping the literal for a key would change what gets saved and
/// sent, so the English stays and only what is drawn goes through here.
///
///     SelectableChip(title: tr(option), isSelected: position == option)
///                           ^ drawn               ^ stored, still English
///
/// Text it does not know comes back unchanged, which makes this safe in three
/// useful ways: a string the dictionary has not got yet reads in English
/// rather than showing a key, wrapping a site is never a regression, and
/// passing already-translated text through does nothing.
func tr(_ english: String, vars: [String: CustomStringConvertible] = [:]) -> String {
    guard let key = Strings.key(forEnglish: english) else {
        var out = english
        for (name, value) in vars { out = out.replacingOccurrences(of: "{\(name)}", with: value.description) }
        return out
    }
    return t(key, vars: vars)
}

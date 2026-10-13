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
    private static let key = "FishersLanguage"

    @Published private(set) var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.key) }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.key),
           let chosen = Language(rawValue: saved) {
            language = chosen
        } else {
            language = Self.fromSystem()
        }
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

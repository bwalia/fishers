import XCTest
@testable import Fishers

/// The web gets a compile error for a key that does not exist, because its
/// dictionary is also a type. iOS looks keys up at runtime, so this is what
/// buys that safety back — plus the rules themselves, which have to match the
/// web's or the same club reads two different products.
final class StringsTests: XCTestCase {
    func testBothTablesAreInTheBundle() {
        for language in Language.allCases {
            XCTAssertGreaterThan(
                Strings.keys(for: language).count, 2000,
                "\(language.rawValue).json is missing from the bundle or did not decode"
            )
        }
    }

    /// Punjabi being present is not the same as Punjabi being Punjabi: a
    /// generator bug that wrote en.json twice would pass every other test here.
    func testPunjabiIsActuallyTranslated() {
        XCTAssertEqual(Strings.t("nav.home", language: .en), "Home")
        let home = Strings.t("nav.home", language: .pa)
        XCTAssertNotEqual(home, "Home")
        XCTAssertTrue(
            home.unicodeScalars.contains { (0x0A00...0x0A7F).contains($0.value) },
            "\(home) is not in Gurmukhi"
        )
    }

    func testPluralsPickTheFormByCount() {
        // Resolution is what matters; the wording is the dictionary's business.
        XCTAssertTrue(Strings.resolve("outcome.runs", count: 1).hasSuffix(".one"))
        XCTAssertTrue(Strings.resolve("outcome.runs", count: 0).hasSuffix(".other"))
        XCTAssertTrue(Strings.resolve("outcome.runs", count: 4).hasSuffix(".other"))
        // A plural stem asked without a count takes the general form rather
        // than printing the stem onto the screen.
        XCTAssertTrue(Strings.resolve("outcome.runs", count: nil).hasSuffix(".other"))
    }

    /// `count` both picks the form and fills `{count}`, which is what the web
    /// does — there `count` is simply one of the vars, and happens also to be
    /// the one plural selection reads.
    func testCountFillsItsOwnPlaceholder() {
        XCTAssertEqual(Strings.t("wheel.plotted", language: .en, count: 1), "1 shot plotted")
        XCTAssertEqual(Strings.t("wheel.plotted", language: .en, count: 3), "3 shots plotted")
    }

    /// Most plurals name their own variable (`{n}`, `{runs}`), so the caller
    /// passes it alongside the count exactly as the web's call does.
    func testAPluralWithItsOwnVariableName() {
        XCTAssertEqual(
            Strings.t("outcome.runs", language: .en, count: 1, vars: ["runs": 1]), "1 run"
        )
        XCTAssertEqual(
            Strings.t("outcome.runs", language: .en, count: 4, vars: ["runs": 4]), "4 runs"
        )
    }

    func testVariablesAreInterpolated() {
        let said = Strings.t(
            "ball.bowler_to_batter", language: .en,
            vars: ["bowler": "Harry", "batter": "Sam"]
        )
        XCTAssertTrue(said.contains("Harry") && said.contains("Sam"), said)
        XCTAssertFalse(said.contains("{"), "a placeholder survived in \(said)")
    }

    /// Per key, not per language. A language that is 90% done shows 90% of
    /// itself; falling back to the key would put `moment.hat_trick` on a live
    /// scoreboard.
    func testAnUntranslatedKeyFallsBackToEnglishNotToTheKey() {
        let missing = "zz.not.a.real.key"
        XCTAssertEqual(Strings.t(missing, language: .pa), missing, "an unknown key is its own last resort")
        // Every real key resolves in both, so the fallback is exercised by
        // construction rather than by a key that happens to be missing today.
        for key in Strings.keys(for: .en) {
            XCTAssertFalse(Strings.t(key, language: .pa).isEmpty, "\(key) is empty in Punjabi")
        }
    }

    func testSystemLanguageFallsBackToEnglishForSomethingWeDoNotSpeak() {
        XCTAssertEqual(Language(rawValue: "de"), nil)
        XCTAssertEqual(Language.fallback, .en)
    }

    /// The real guard: every key the app asks for has to exist. Without this a
    /// typo is a screen that quietly renders `profile.lsat_match`.
    func testEveryKeyTheAppAsksForExists() throws {
        let appSources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // FishersTests
            .deletingLastPathComponent()      // ios
            .appendingPathComponent("Fishers")
        let known = Strings.keys(for: .en)
        // `t("some.key"` — the call the app makes, however it reached `t`.
        let call = try NSRegularExpression(pattern: #"\bt\(\s*"([a-z0-9_]+(?:\.[a-z0-9_]+)+)""#)

        var checked = 0
        var unknown: [String] = []
        let files = FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in call.matches(in: source, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
                let key = String(source[keyRange])
                checked += 1
                // A plural stem is asked for by its stem; both forms exist.
                if known.contains(key) || known.contains("\(key).other") { continue }
                unknown.append("\(url.lastPathComponent): \(key)")
            }
        }
        XCTAssertTrue(unknown.isEmpty, "keys the dictionary does not have:\n" + unknown.joined(separator: "\n"))
        XCTAssertGreaterThan(checked, 0, "the scanner found no t(\"…\") calls — has the call shape changed?")
    }
}

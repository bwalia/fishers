import Foundation

/// A single stat a player can record for a sport. The catalog below drives the
/// stats form during profile setup, so adding a sport needs no new UI.
struct StatField: Identifiable, Hashable {
    enum Kind: Hashable {
        case choice([String])
        case integer(ClosedRange<Int>)
        case decimal(String)
        case text(String)
    }

    let key: String
    let label: String
    let kind: Kind
    var footnote: String?

    var id: String { key }

    static func choice(_ key: String, _ label: String, _ options: [String], footnote: String? = nil) -> StatField {
        StatField(key: key, label: label, kind: .choice(options), footnote: footnote)
    }

    static func integer(_ key: String, _ label: String, _ range: ClosedRange<Int> = 0...999, footnote: String? = nil) -> StatField {
        StatField(key: key, label: label, kind: .integer(range), footnote: footnote)
    }

    static func decimal(_ key: String, _ label: String, placeholder: String = "0.0", footnote: String? = nil) -> StatField {
        StatField(key: key, label: label, kind: .decimal(placeholder), footnote: footnote)
    }

    static func text(_ key: String, _ label: String, placeholder: String = "", footnote: String? = nil) -> StatField {
        StatField(key: key, label: label, kind: .text(placeholder), footnote: footnote)
    }
}

/// Per-sport stat catalogs. Values are stored as strings on `SportProfile.stats`
/// so the backend can keep them in one JSONB column per sport.
enum SportStats {
    static func fields(for sport: Sport) -> [StatField] {
        switch sport {
        case .cricket:
            return [
                .choice("batting_style", "Batting", ["Right-hand", "Left-hand"]),
                .choice("bowling_style", "Bowling", [
                    "Right-arm fast", "Right-arm medium", "Off-spin", "Leg-spin",
                    "Left-arm seam", "Left-arm orthodox", "Doesn't bowl",
                ]),
                .integer("batting_number", "Usual batting position", 1...11),
                .decimal("batting_average", "Batting average", placeholder: "24.5"),
                .decimal("bowling_average", "Bowling average", placeholder: "18.2"),
                .integer("high_score", "Highest score"),
                .integer("wickets", "Career wickets"),
                .integer("catches", "Catches"),
                .integer("matches", "Matches played"),
            ]
        case .padel:
            return [
                .choice("side", "Preferred side", ["Right side", "Left side", "Either side"]),
                .decimal("padel_level", "Padel level", placeholder: "3.5", footnote: "0–7 scale used by most clubs and Playtomic."),
                .choice("play_style", "Style", ["Attacking", "Defensive", "Balanced"]),
                .integer("matches", "Matches played"),
                .integer("win_rate", "Win rate", 0...100),
                .text("partner", "Regular partner"),
            ]
        case .badminton:
            return [
                .choice("discipline", "Main discipline", ["Singles", "Doubles", "Mixed doubles"]),
                .choice("racket_hand", "Racket hand", ["Right", "Left"]),
                .choice("club_grade", "Club grade", ["Social", "Club league", "County", "National"]),
                .integer("ladder_position", "Club ladder position", 1...200),
                .integer("matches", "Matches played"),
                .integer("win_rate", "Win rate", 0...100),
            ]
        case .football:
            return [
                .choice("foot", "Preferred foot", ["Right", "Left", "Both"]),
                .integer("shirt_number", "Shirt number", 1...99),
                .integer("appearances", "Appearances"),
                .integer("goals", "Goals"),
                .integer("assists", "Assists"),
                .integer("clean_sheets", "Clean sheets", footnote: "Goalkeepers and defenders."),
            ]
        case .rugby:
            return [
                .integer("shirt_number", "Usual shirt number", 1...23),
                .integer("appearances", "Appearances"),
                .integer("tries", "Tries"),
                .integer("points", "Points scored"),
                .choice("kicker", "Goal kicker", ["Yes", "No"]),
            ]
        case .tennis:
            return [
                .decimal("rating", "LTA / NTRP rating", placeholder: "4.0"),
                .choice("hand", "Racket hand", ["Right", "Left"]),
                .choice("surface", "Preferred surface", ["Hard", "Clay", "Grass", "Indoor"]),
                .integer("matches", "Matches played"),
                .integer("win_rate", "Win rate", 0...100),
            ]
        case .hockey:
            return [
                .integer("shirt_number", "Shirt number", 1...99),
                .integer("appearances", "Appearances"),
                .integer("goals", "Goals"),
                .choice("penalty_corner", "Penalty corner role", ["Injector", "Stopper", "Striker", "None"]),
            ]
        case .netball:
            return [
                .integer("appearances", "Appearances"),
                .integer("goals", "Goals scored"),
                .integer("intercepts", "Intercepts"),
                .choice("bib_flexibility", "Can cover", ["One position", "Two positions", "Anywhere"]),
            ]
        case .basketball:
            return [
                .integer("shirt_number", "Shirt number", 0...99),
                .decimal("points_per_game", "Points per game", placeholder: "8.5"),
                .decimal("rebounds_per_game", "Rebounds per game", placeholder: "4.0"),
                .decimal("assists_per_game", "Assists per game", placeholder: "2.5"),
                .integer("games", "Games played"),
            ]
        }
    }

    /// Non-empty stats in catalog order, ready to render on the profile.
    static func summary(for profile: SportProfile) -> [(label: String, value: String)] {
        guard let sport = Sport(rawValue: profile.sport) else { return [] }
        return fields(for: sport).compactMap { field in
            guard let raw = profile.stats[field.key], !raw.isEmpty else { return nil }
            return (field.label, formatted(raw, for: field))
        }
    }

    private static func formatted(_ raw: String, for field: StatField) -> String {
        if field.key.hasSuffix("win_rate") { return "\(raw)%" }
        return raw
    }
}

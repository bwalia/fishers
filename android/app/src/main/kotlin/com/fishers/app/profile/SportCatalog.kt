package com.fishers.app.profile

import com.fishers.app.i18n.t

// What a profile can say, per sport — `PlayerProfile.swift` and `SportStats.swift`.
//
// Stored values are English and never translated: they are what goes on the
// profile and to the API, and the web and iPhone app write the same words.
// Each carries the dictionary key it is drawn with.

/** A stored value and the key it is drawn with. */
data class Choice(val value: String, val key: String) {
    val label: String get() = t(key)
}

private fun c(value: String, key: String) = Choice(value, key)

/** The draw-time label of a stored value, or the value itself for one this app does not know. */
fun List<Choice>.labelOf(value: String?): String? =
    value?.let { v -> firstOrNull { it.value == v }?.label ?: v }

/**
 * Sports the app knows about. The first seven spellings are the API's
 * `SportType`, so a profile saved on the web resolves here.
 */
enum class Sport(
    val wire: String,
    private val labelKey: String,
    /** Leagues are graded in these; the rest are rated. */
    val usesDivisions: Boolean,
    val positions: List<Choice>,
) {
    Cricket(
        "cricket", "rest.cricket", true,
        listOf(
            c("Batter", "pos.batter"), c("Fast Bowler", "sp.fast_bowler"), c("Spinner", "sp.spinner"),
            c("All-rounder", "lb.all_rounder"), c("Wicketkeeper", "pos.wicketkeeper"),
        ),
    ),
    Football("football", "pf.sport.football", true, FIELD_POSITIONS),
    Badminton("badminton", "pf.sport.badminton", false, RACKET_POSITIONS),
    Paddle("paddle", "pf.sport.paddle", false, SIDE_POSITIONS),
    Pickleball("pickleball", "pf.sport.pickleball", false, SIDE_POSITIONS),
    Tennis("tennis", "pf.sport.tennis", false, RACKET_POSITIONS),
    Other("other", "pf.sport.other", false, emptyList()),
    Hockey("hockey", "pf.sport.hockey", true, FIELD_POSITIONS),
    Netball(
        "netball", "pf.sport.netball", true,
        listOf(
            c("Goal Shooter", "sp.goal_shooter"), c("Goal Attack", "sp.goal_attack"),
            c("Wing Attack", "sp.wing_attack"), c("Centre", "sp.centre"),
            c("Wing Defence", "sp.wing_defence"), c("Goal Defence", "sp.goal_defence"),
            c("Goal Keeper", "sp.goal_keeper_netball"),
        ),
    ),
    Rugby(
        "rugby", "pf.sport.rugby", true,
        listOf(
            c("Front row", "sp.front_row"), c("Second row", "sp.second_row"), c("Back row", "sp.back_row"),
            c("Half back", "sp.half_back"), c("Centre", "sp.centre"), c("Back three", "sp.back_three"),
        ),
    ),
    Basketball(
        "basketball", "pf.sport.basketball", false,
        listOf(c("Guard", "sp.guard"), c("Forward", "sp.forward"), c("Centre", "sp.centre")),
    ),
    ;

    val label: String get() = t(labelKey)

    val statFields: List<StatField> get() = SportStats.fields(this)

    companion object {
        /** A stored sport, allowing for how the apps used to spell it ("padel"). */
        fun named(raw: String?): Sport? {
            val key = raw?.trim()?.lowercase()?.takeIf { it.isNotEmpty() } ?: return null
            val wire = if (key == "padel") "paddle" else key
            return entries.firstOrNull { it.wire == wire }
        }
    }
}

private val FIELD_POSITIONS = listOf(
    c("Goalkeeper", "sp.goalkeeper"), c("Defender", "sp.defender"),
    c("Midfielder", "sp.midfielder"), c("Forward", "sp.forward"),
)
private val RACKET_POSITIONS = listOf(
    c("Singles", "sp.singles"), c("Doubles", "sp.doubles"), c("Mixed doubles", "sp.mixed_doubles"),
)
private val SIDE_POSITIONS = listOf(
    c("Right side", "sp.right_side"), c("Left side", "sp.left_side"), c("Either side", "sp.either_side"),
)

/** Self-rated standard, ordered so a player can see the rung above them. */
enum class SkillTier(private val labelKey: String, private val blurbKey: String) {
    Beginner("lb.beginner", "sp.new_to_the_sport"),
    Improver("lb.improver", "sp.played_a_bit"),
    Intermediate("pf.tier.intermediate", "sp.comfortable_social_lower"),
    Club("lb.club_standard", "sp.regular_league_player"),
    Advanced("pf.tier.advanced", "sp.strong_league_performer"),
    Elite("pf.tier.elite", "sp.premier_county_rep"),
    ;

    val label: String get() = t(labelKey)
    val blurb: String get() = t(blurbKey)

    /**
     * What goes on the profile. The iPhone app stores the English label —
     * "Club standard", "Advanced" — and reads either form back, so this writes
     * the same thing rather than a third spelling.
     */
    val wire: String get() = if (this == Club) "Club standard" else name

    val next: SkillTier? get() = entries.getOrNull(ordinal + 1)

    companion object {
        /** Tolerates the capitalised strings stored on `skill_level`. */
        fun stored(raw: String?): SkillTier? {
            val key = raw?.lowercase()?.replace(" standard", "")?.trim() ?: return null
            return entries.firstOrNull { it.name.lowercase() == key }
        }
    }
}

/** League grade, lowest to highest — a player's current and target division. */
enum class Division(val wire: String, private val labelKey: String, private val shortKey: String) {
    Social("social", "sp.social_and_friendlies", "ld.social"),
    Development("development", "sp.development_side", "sp.dev_short"),
    Division5("division5", "sp.division_5", "sp.div_5"),
    Division4("division4", "sp.division_4", "sp.div_4"),
    Division3("division3", "sp.division_3", "sp.div_3"),
    Division2("division2", "sp.division_2", "sp.div_2"),
    Division1("division1", "sp.division_1", "sp.div_1"),
    Premier("premier", "sp.premier_division", "sp.prem_short"),
    County("county", "sp.county_representative", "sp.county"),
    ;

    val label: String get() = t(labelKey)
    val shortLabel: String get() = t(shortKey)

    companion object {
        fun stored(raw: String?): Division? = entries.firstOrNull { it.wire == raw }
    }
}

/** Age band the player is eligible for. */
enum class AgeGroup(val wire: String, private val labelKey: String) {
    U11("u11", "sp.under_11s"),
    U13("u13", "sp.under_13s"),
    U15("u15", "sp.under_15s"),
    U17("u17", "sp.under_17s"),
    Senior("senior", "sp.senior"),
    Vets40("vets40", "sp.vets_40"),
    Vets50("vets50", "sp.vets_50"),
    ;

    val label: String get() = t(labelKey)

    companion object {
        fun stored(raw: String?): AgeGroup? = entries.firstOrNull { it.wire == raw }
    }
}

/** How the player gets to fixtures — feeds lift sharing on away games. */
enum class TransportMode(val wire: String, private val labelKey: String) {
    DriverWithSeats("driverWithSeats", "sp.drives_can_offer_lifts"),
    Driver("driver", "sp.drives_no_spare_seats"),
    PublicTransport("publicTransport", "sp.public_transport"),
    NeedsLift("needsLift", "sp.needs_a_lift"),
    ;

    val label: String get() = t(labelKey)
    val offersLifts: Boolean get() = this == DriverWithSeats
}

/** Weekday, numbered as `Calendar` numbers them (1 = Sunday), listed Monday first. */
enum class Weekday(val number: Int, private val key: String) {
    Monday(2, "day.mon"),
    Tuesday(3, "day.tue"),
    Wednesday(4, "day.wed"),
    Thursday(5, "day.thu"),
    Friday(6, "day.fri"),
    Saturday(7, "day.sat"),
    Sunday(1, "day.sun"),
    ;

    val shortLabel: String get() = t(key)

    companion object {
        fun of(number: Int): Weekday? = entries.firstOrNull { it.number == number }
    }
}

/** The distances the travel picker offers. */
val TRAVEL_RADII = listOf(5, 10, 15, 20, 30, 50)

/** One stat a player can record for a sport. The catalog drives the form, so a sport needs no new UI. */
data class StatField(
    /** The column inside `SportProfile.stats`; the server reads it, so never translated. */
    val key: String,
    private val labelKey: String,
    val kind: Kind,
    private val footnoteKey: String? = null,
) {
    sealed interface Kind {
        data class Pick(val options: List<Choice>) : Kind
        data class Whole(val range: IntRange) : Kind
        data class Decimal(val placeholder: String) : Kind
        data object Text : Kind
    }

    val label: String get() = t(labelKey)
    val footnote: String? get() = footnoteKey?.let { t(it) }

    /** What a stored value reads as on a profile. */
    fun display(raw: String): String = when (kind) {
        is Kind.Pick -> kind.options.labelOf(raw) ?: raw
        else -> if (key.endsWith("win_rate")) "$raw%" else raw
    }
}

/** Per-sport stat catalogs — `SportStats.fields(for:)`. */
object SportStats {
    private fun pick(key: String, label: String, vararg options: Choice, footnote: String? = null) =
        StatField(key, label, StatField.Kind.Pick(options.toList()), footnote)

    private fun whole(key: String, label: String, range: IntRange = 0..999, footnote: String? = null) =
        StatField(key, label, StatField.Kind.Whole(range), footnote)

    private fun decimal(key: String, label: String, placeholder: String, footnote: String? = null) =
        StatField(key, label, StatField.Kind.Decimal(placeholder), footnote)

    private fun text(key: String, label: String) = StatField(key, label, StatField.Kind.Text)

    private val right = c("Right", "sp.right")
    private val left = c("Left", "sp.left")
    private val matches = whole("matches", "sp.matches_played")
    private val winRate = whole("win_rate", "sh.win_rate", 0..100)

    fun fields(sport: Sport): List<StatField> = when (sport) {
        Sport.Cricket -> listOf(
            pick("batting_style", "ss.batting", c("Right-hand", "sp.right_hand"), c("Left-hand", "sp.left_hand")),
            pick(
                "bowling_style", "ss.bowling",
                c("Right-arm fast", "sp.right_arm_fast"), c("Right-arm medium", "sp.right_arm_medium"),
                c("Off-spin", "sp.off_spin"), c("Leg-spin", "sp.leg_spin"),
                c("Left-arm seam", "sp.left_arm_seam"), c("Left-arm orthodox", "sp.left_arm_orthodox"),
                c("Doesn't bowl", "sp.doesnt_bowl"),
            ),
            whole("batting_number", "sp.usual_batting_position", 1..11),
            decimal("batting_average", "sp.batting_average", "24.5"),
            decimal("bowling_average", "sp.bowling_average", "18.2"),
            whole("high_score", "rest.highest_score_stat"),
            whole("wickets", "sp.career_wickets"),
            whole("catches", "rest.catches"),
            matches,
        )
        Sport.Paddle -> listOf(
            pick("side", "sp.preferred_side", *SIDE_POSITIONS.toTypedArray()),
            decimal("padel_level", "sp.padel_level", "3.5", footnote = "sp.scale_0_7"),
            pick("play_style", "sp.style", c("Attacking", "sp.attacking"), c("Defensive", "sp.defensive"), c("Balanced", "sp.balanced")),
            matches,
            winRate,
            text("partner", "sp.regular_partner"),
        )
        Sport.Badminton -> listOf(
            pick("discipline", "sp.main_discipline", *RACKET_POSITIONS.toTypedArray()),
            pick("racket_hand", "sp.racket_hand", right, left),
            pick(
                "club_grade", "sp.club_grade",
                c("Social", "ld.social"), c("Club league", "sp.club_league"),
                c("County", "sp.county"), c("National", "sp.national"),
            ),
            whole("ladder_position", "sp.club_ladder_position", 1..200),
            matches,
            winRate,
        )
        Sport.Football -> listOf(
            pick("foot", "sp.preferred_foot", right, left, c("Both", "sp.both")),
            whole("shirt_number", "sp.shirt_number", 1..99),
            whole("appearances", "sp.appearances"),
            whole("goals", "sp.goals"),
            whole("assists", "sp.assists"),
            whole("clean_sheets", "sp.clean_sheets", footnote = "sp.goalkeepers_and_defenders"),
        )
        Sport.Rugby -> listOf(
            whole("shirt_number", "sp.usual_shirt_number", 1..23),
            whole("appearances", "sp.appearances"),
            whole("tries", "sp.tries"),
            whole("points", "sp.points_scored"),
            pick("kicker", "sp.goal_kicker", c("Yes", "sp.yes"), c("No", "sp.no")),
        )
        Sport.Tennis -> listOf(
            decimal("rating", "sp.lta_ntrp_rating", "4.0"),
            pick("hand", "sp.racket_hand", right, left),
            pick(
                "surface", "sp.preferred_surface",
                c("Hard", "sp.hard"), c("Clay", "sp.clay"), c("Grass", "sp.grass"), c("Indoor", "ground_type.indoor"),
            ),
            matches,
            winRate,
        )
        Sport.Hockey -> listOf(
            whole("shirt_number", "sp.shirt_number", 1..99),
            whole("appearances", "sp.appearances"),
            whole("goals", "sp.goals"),
            pick(
                "penalty_corner", "sp.penalty_corner_role",
                c("Injector", "sp.injector"), c("Stopper", "sp.stopper"),
                c("Striker", "sc.striker"), c("None", "la.none"),
            ),
        )
        Sport.Netball -> listOf(
            whole("appearances", "sp.appearances"),
            whole("goals", "sp.goals_scored"),
            whole("intercepts", "sp.intercepts"),
            pick(
                "bib_flexibility", "sp.can_cover",
                c("One position", "sp.one_position"), c("Two positions", "sp.two_positions"),
                c("Anywhere", "sp.anywhere"),
            ),
        )
        Sport.Basketball -> listOf(
            whole("shirt_number", "sp.shirt_number", 0..99),
            decimal("points_per_game", "sp.points_per_game", "8.5"),
            decimal("rebounds_per_game", "sp.rebounds_per_game", "4.0"),
            decimal("assists_per_game", "sp.assists_per_game", "2.5"),
            whole("games", "sp.games_played"),
        )
        Sport.Pickleball -> listOf(
            pick("discipline", "sp.main_discipline", *RACKET_POSITIONS.toTypedArray()),
            pick("side", "sp.preferred_side", *SIDE_POSITIONS.toTypedArray()),
            decimal("dupr_rating", "sp.dupr_rating", "3.5", footnote = "sp.scale_2_8"),
            matches,
            winRate,
            text("partner", "sp.regular_partner"),
        )
        Sport.Other -> listOf(
            text("discipline", "rest.what_you_play"),
            matches,
            winRate,
        )
    }

    /** Non-empty stats in catalog order, ready to draw on a profile. */
    fun summary(profile: SportProfile): List<Pair<String, String>> {
        val sport = profile.sportKind ?: return emptyList()
        return fields(sport).mapNotNull { field ->
            profile.stats[field.key]?.takeIf { it.isNotBlank() }?.let { field.label to field.display(it) }
        }
    }

    /**
     * What a typed number may be. Digits only, held inside the field's range,
     * so a shirt number cannot be typed into nonsense — `StatFieldRow.clamped`.
     */
    fun clampWhole(typed: String, range: IntRange): String {
        val digits = typed.filter(Char::isDigit).take(6)
        if (digits.isEmpty()) return ""
        return digits.toInt().coerceIn(range).toString()
    }
}

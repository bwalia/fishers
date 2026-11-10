package com.fishers.app.season

import com.fishers.app.i18n.Language
import com.fishers.app.i18n.Strings
import com.fishers.app.i18n.t
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/*
 * A player's season, match by match, as `/me/game` and `/users/{id}/game`
 * return it, and a club's season from `/clubs/{id}/season`.
 *
 * The shapes are `backend/domain/src/season.rs`, field for field; the words
 * are `web/src/lib/season.ts`, mapping for mapping. The arithmetic is the
 * API's and none of it is redone here — a phone that worked out its own
 * average would one day disagree with the email that went out at season's end.
 *
 * Everything optional on the wire has a default, so a field the server stops
 * sending, or one it adds, costs a blank rather than the screen.
 */

@Serializable
data class Figures(val wickets: Int = 0, val runs: Int = 0)

@Serializable
data class Totals(
    val matches: Int = 0,
    val won: Int = 0,
    @SerialName("batting_innings") val battingInnings: Int = 0,
    @SerialName("not_outs") val notOuts: Int = 0,
    val runs: Int = 0,
    @SerialName("balls_faced") val ballsFaced: Int = 0,
    val fours: Int = 0,
    val sixes: Int = 0,
    @SerialName("high_score") val highScore: Int? = null,
    @SerialName("high_score_not_out") val highScoreNotOut: Boolean = false,
    val fifties: Int = 0,
    val hundreds: Int = 0,
    val ducks: Int = 0,
    @SerialName("double_figures") val doubleFigures: Int = 0,
    @SerialName("batting_average") val battingAverage: Double? = null,
    @SerialName("strike_rate") val strikeRate: Double? = null,
    @SerialName("bowling_balls") val bowlingBalls: Int = 0,
    val overs: String = "0.0",
    @SerialName("bowling_runs") val bowlingRuns: Int = 0,
    val wickets: Int = 0,
    val maidens: Int = 0,
    val economy: Double? = null,
    @SerialName("bowling_average") val bowlingAverage: Double? = null,
    @SerialName("bowling_strike_rate") val bowlingStrikeRate: Double? = null,
    @SerialName("best_bowling") val bestBowling: Figures? = null,
    val catches: Int = 0,
    val stumpings: Int = 0,
    @SerialName("player_of_match") val playerOfMatch: Int = 0,
    /** Times they made the ball a match turned on. */
    @SerialName("magic_moments") val magicMoments: Int = 0,
)

@Serializable
data class FormEntry(
    @SerialName("match_id") val matchId: String,
    @SerialName("event_id") val eventId: String = "",
    @SerialName("played_at") val playedAt: String,
    val opposition: String = "",
    /** Null is a tie or no result — not a loss, and not shown as one. */
    val won: Boolean? = null,
    val batted: Boolean = false,
    val runs: Int = 0,
    val balls: Int = 0,
    @SerialName("not_out") val notOut: Boolean = false,
    val bowled: Boolean = false,
    val wickets: Int = 0,
    @SerialName("runs_conceded") val runsConceded: Int = 0,
    val overs: String = "0.0",
    val catches: Int = 0,
    @SerialName("player_of_match") val playerOfMatch: Boolean = false,
)

/**
 * Strings rather than an enum: a fourth trend added server-side should drop
 * the sentence, not fail the whole decode.
 */
@Serializable
data class Form(
    /** Newest first, as the API sends them. */
    val matches: List<FormEntry> = emptyList(),
    @SerialName("recent_batting_average") val recentBattingAverage: Double? = null,
    @SerialName("batting_trend") val battingTrend: String? = null,
    @SerialName("recent_wickets_per_match") val recentWicketsPerMatch: Double? = null,
    @SerialName("bowling_trend") val bowlingTrend: String? = null,
)

@Serializable
data class Best(
    val code: String,
    val value: String,
    val opposition: String? = null,
    @SerialName("played_at") val playedAt: String? = null,
    @SerialName("season_year") val seasonYear: Int? = null,
    @SerialName("this_season") val thisSeason: Boolean = false,
)

@Serializable
data class Milestone(
    val code: String,
    @SerialName("reached_at") val reachedAt: String,
    val opposition: String = "",
    @SerialName("this_season") val thisSeason: Boolean = false,
)

@Serializable
data class ClubRank(
    @SerialName("club_id") val clubId: String,
    @SerialName("club_name") val clubName: String,
    /** A place, 1-based; null when they did nothing on that board. */
    val runs: Int? = null,
    val wickets: Int? = null,
    val catches: Int? = null,
    val players: Int = 0,
)

@Serializable
data class Highlight(
    val code: String,
    /** The API's own English — what is shown for a code this build does not know. */
    val text: String = "",
    val value: String? = null,
    val detail: String? = null,
)

@Serializable
data class PlayerGame(
    @SerialName("user_id") val userId: String,
    val name: String = "",
    val season: Int,
    val seasons: List<Int> = emptyList(),
    val totals: Totals = Totals(),
    /** Last season, when there was one. */
    val previous: Totals? = null,
    val career: Totals = Totals(),
    val form: Form = Form(),
    val bests: List<Best> = emptyList(),
    val milestones: List<Milestone> = emptyList(),
    @SerialName("club_rank") val clubRank: ClubRank? = null,
    val highlights: List<Highlight> = emptyList(),
)

@Serializable
data class Leader(
    @SerialName("user_id") val userId: String,
    val name: String,
    val value: String,
    val detail: String? = null,
)

@Serializable
data class Leaderboard(val code: String, val leaders: List<Leader> = emptyList())

@Serializable
data class SeasonRecord(
    val played: Int = 0,
    val won: Int = 0,
    val lost: Int = 0,
    @SerialName("tied_or_no_result") val tiedOrNoResult: Int = 0,
) {
    /** Rounded, as the web rounds it; null before a ball is bowled. */
    val winPercent: Int? get() = if (played > 0) Math.round(won * 100.0 / played).toInt() else null
}

@Serializable
data class ClubSeason(
    @SerialName("club_id") val clubId: String,
    @SerialName("club_name") val clubName: String = "",
    val season: Int,
    @SerialName("closed_at") val closedAt: String? = null,
    val seasons: List<Int> = emptyList(),
    val record: SeasonRecord = SeasonRecord(),
    val players: Int = 0,
    val boards: List<Leaderboard> = emptyList(),
)

/** What closing the season will do, shown before the secretary commits to it. */
@Serializable
data class ClosePreview(
    val season: Int,
    @SerialName("closed_at") val closedAt: String? = null,
    val members: Int = 0,
    @SerialName("will_email") val willEmail: Int = 0,
    val played: Int = 0,
    /** False when the server cannot send mail yet; absent from older servers, which means on. */
    @SerialName("email_on") val emailOn: Boolean? = null,
)

@Serializable
data class SeasonClosed(val season: Int = 0, val queued: Int = 0)

/**
 * `GET /clubs/{id}/my-role`, cut to what this screen asks of it. The server
 * sends a good deal more; the permission list is the only part that decides
 * anything here.
 */
@Serializable
data class MyClubRole(
    val role: String? = null,
    val permissions: List<String> = emptyList(),
) {
    val canCloseSeason: Boolean get() = "manage_club_ops" in permissions
}

// MARK: Words

/** One decimal place, or a dash — "–" rather than "0.0" for a figure that does not exist yet. */
fun fmt(v: Double?, dp: Int = 1): String =
    if (v == null) "–" else String.format(Locale.ROOT, "%.${dp}f", v)

fun score(runs: Int?, notOut: Boolean): String =
    if (runs == null) "–" else "$runs${if (notOut) "*" else ""}"

/**
 * "Top", "Second", "Third", then "No. 7" — ordinals do not pluralise, so they
 * are words for the three that matter and a number after that.
 */
fun place(n: Int): String = when (n) {
    1 -> t("ss.place.1")
    2 -> t("ss.place.2")
    3 -> t("ss.place.3")
    else -> t("ss.place.n", vars = mapOf("n" to n))
}

private val MILESTONES = mapOf(
    "first_match" to "ss.ms.first_match",
    "first_six" to "ss.ms.first_six",
    "first_fifty" to "ss.ms.first_fifty",
    "first_hundred" to "ss.ms.first_hundred",
    "first_wicket" to "ss.ms.first_wicket",
    "first_three_wickets" to "ss.ms.first_three_wickets",
    "first_five_wickets" to "ss.ms.first_five_wickets",
    "first_catch" to "ss.ms.first_catch",
    "first_player_of_match" to "ss.ms.first_player_of_match",
    "first_win" to "ss.ms.first_win",
)

private val COUNTED = Regex("^(matches|runs|wickets)_(\\d+)$")

/** A milestone code as words: "first_fifty", "runs_250". */
fun milestoneLabel(code: String): String {
    COUNTED.matchEntire(code)?.let { m ->
        return t("ss.ms.${m.groupValues[1]}", vars = mapOf("n" to m.groupValues[2]))
    }
    return MILESTONES[code]?.let { t(it) } ?: code.replace('_', ' ')
}

/**
 * A highlight in the reader's language, from its code. The API's English is
 * the fallback for a code this build does not know yet — a new kind of good
 * news should arrive in English rather than not at all.
 */
fun highlightText(h: Highlight): String {
    val v = h.value.orEmpty()
    val d = h.detail.orEmpty()
    val n = v.toIntOrNull() ?: 0
    fun vs(key: String) = if (d.isNotEmpty()) {
        t(key, vars = mapOf("value" to v, "opposition" to d))
    } else {
        h.text
    }
    return when (h.code) {
        "new_best_score" -> vs("ss.hl.new_best_score")
        "season_best_score" -> vs("ss.hl.season_best_score")
        "new_best_bowling" -> vs("ss.hl.new_best_bowling")
        "season_best_bowling" -> vs("ss.hl.season_best_bowling")
        "milestone" -> t("ss.hl.milestone", vars = mapOf("label" to milestoneLabel(d)))
        "average_up" -> t("ss.hl.average_up", vars = mapOf("value" to v))
        "strike_rate_up" -> t("ss.hl.strike_rate_up", vars = mapOf("value" to v))
        "economy_down" -> t("ss.hl.economy_down", vars = mapOf("value" to v))
        "more_runs" -> t("ss.hl.more_runs", vars = mapOf("value" to v, "before" to d))
        "more_wickets" -> t("ss.hl.more_wickets", vars = mapOf("value" to v, "before" to d))
        "club_top_runs" -> t("ss.hl.club_top_runs", vars = mapOf("place" to place(n), "club" to d))
        "club_top_wickets" -> t("ss.hl.club_top_wickets", vars = mapOf("place" to place(n), "club" to d))
        "consistent" -> t("ss.hl.consistent", vars = mapOf("value" to v, "of" to d))
        "player_of_match" -> t("ss.hl.player_of_match", count = n, vars = mapOf("n" to n))
        "safe_hands" -> t("ss.hl.safe_hands", vars = mapOf("value" to v))
        "winning_side" -> t("ss.hl.winning_side", vars = mapOf("value" to v, "of" to d))
        "turned_up" -> t("ss.hl.turned_up", count = n, vars = mapOf("n" to n))
        else -> h.text
    }
}

/** A trophy for a best or a club place; a tick for everything else. */
val Highlight.isTrophy: Boolean get() = code.startsWith("club_top") || "best" in code

private val BEST_LABELS = setOf(
    "best_score", "best_bowling", "most_sixes", "most_catches",
    "best_season_runs", "best_season_wickets",
)

fun bestLabel(code: String): String = if (code in BEST_LABELS) t("ss.best.$code") else code

private val BOARD_LABELS = setOf(
    "runs", "wickets", "batting_average", "strike_rate", "economy",
    "best_innings", "best_bowling", "catches", "sixes", "player_of_match",
)

fun boardLabel(code: String): String = if (code in BOARD_LABELS) t("ss.board.$code") else code

/** The sentence under "Form". Null for a trend this build does not know. */
fun trendText(trend: String?, recent: Double?, batting: Boolean): String? {
    if (trend == null || recent == null) return null
    if (trend !in setOf("rising", "steady", "quieter")) return null
    val kind = if (batting) "bat" else "bowl"
    return t("ss.trend.${kind}_$trend", vars = mapOf("value" to fmt(recent)))
}

/** One tile in the season's headline numbers. */
data class HeadlineTile(
    val key: String,
    val label: String,
    val value: String,
    val sub: String? = null,
    /** True only when better than last season. False and null read the same: plain context. */
    val up: Boolean? = null,
    /** Last season's figure, when there is one to set beside it. */
    val was: String? = null,
)

/**
 * The numbers that describe the season, each with last season beside it —
 * `Headline` in `web/src/app/stats/page.tsx`, rule for rule.
 *
 * Only the tiles that apply: somebody who never bowled is not shown an
 * economy of "–". A lower number than last season is shown as plain context,
 * never as a loss; [HeadlineTile.up] is only ever a reason to say well done.
 */
fun headlineTiles(now: Totals, before: Totals?): List<HeadlineTile> {
    fun better(a: Double?, b: Double?, higherIsBetter: Boolean = true): Boolean? =
        if (a == null || b == null) null else if (higherIsBetter) a > b else a < b

    val tiles = mutableListOf(
        HeadlineTile(
            key = "matches",
            label = t("ss.matches"),
            value = now.matches.toString(),
            sub = t("ss.won_n", vars = mapOf("n" to now.won)),
        ),
    )
    if (now.battingInnings > 0) {
        val batted = before != null && before.battingInnings > 0
        tiles += HeadlineTile(
            key = "runs",
            label = t("ss.runs"),
            value = now.runs.toString(),
            sub = t("ss.innings_n", count = now.battingInnings, vars = mapOf("n" to now.battingInnings)),
            up = if (batted) now.runs > before.runs else null,
            was = if (batted) before.runs.toString() else null,
        )
        tiles += HeadlineTile(
            key = "avg",
            label = t("ss.average"),
            value = fmt(now.battingAverage),
            sub = t("ss.best_n", vars = mapOf("score" to score(now.highScore, now.highScoreNotOut))),
            up = before?.let { better(now.battingAverage, it.battingAverage) },
            was = before?.battingAverage?.let { fmt(it) },
        )
        tiles += HeadlineTile(
            key = "sr",
            label = t("ss.strike_rate"),
            value = fmt(now.strikeRate),
            sub = t("ss.fours_sixes", vars = mapOf("fours" to now.fours, "sixes" to now.sixes)),
            up = before?.let { better(now.strikeRate, it.strikeRate) },
            was = before?.strikeRate?.let { fmt(it) },
        )
    }
    if (now.bowlingBalls > 0) {
        val bowled = before != null && before.bowlingBalls > 0
        val best = now.bestBowling
        tiles += HeadlineTile(
            key = "wkts",
            label = t("ss.wickets"),
            value = now.wickets.toString(),
            sub = if (best != null && best.wickets > 0) {
                t("ss.best_n", vars = mapOf("score" to "${best.wickets}/${best.runs}"))
            } else {
                t("ss.overs_n", vars = mapOf("overs" to now.overs))
            },
            up = if (bowled) now.wickets > before.wickets else null,
            was = if (bowled) before.wickets.toString() else null,
        )
        tiles += HeadlineTile(
            key = "econ",
            label = t("ss.economy"),
            value = fmt(now.economy, 2),
            sub = t("ss.overs_n", vars = mapOf("overs" to now.overs)),
            up = before?.let { better(now.economy, it.economy, higherIsBetter = false) },
            was = before?.economy?.let { fmt(it, 2) },
        )
    }
    val held = now.catches + now.stumpings
    // Somebody who neither batted nor bowled still gets a tile beyond "Matches".
    if (held > 0 || now.battingInnings == 0) {
        tiles += HeadlineTile(
            key = "field",
            label = t("ss.catches"),
            value = held.toString(),
            up = before?.let { held > it.catches + it.stumpings },
            was = before?.let { (it.catches + it.stumpings).toString() },
        )
    }
    if (now.magicMoments > 0) {
        tiles += HeadlineTile(
            key = "magic",
            label = t("mm.title"),
            value = now.magicMoments.toString(),
            up = before?.let { now.magicMoments > it.magicMoments },
            was = before?.let { it.magicMoments.toString() },
        )
    }
    return tiles
}

/**
 * The seasons the picker offers: whatever the API knows about, plus this
 * year — a player with nothing yet still has a season to look at — newest
 * first.
 */
fun pickerSeasons(thisYear: Int, vararg known: Collection<Int>, current: Int? = null): List<Int> =
    (known.flatMap { it } + thisYear + listOfNotNull(current)).distinct().sortedDescending()

// MARK: Dates

private fun locale(): Locale =
    if (Strings.language == Language.EN) Locale.UK else Locale.forLanguageTag(Strings.language.code)

private fun instant(iso: String): Instant? = runCatching { Instant.parse(iso) }.getOrNull()

/** "3 Oct" — the web's `shortDate`, in the reader's language. */
fun shortDate(iso: String, zone: ZoneId = ZoneId.systemDefault()): String =
    instant(iso)?.let { DateTimeFormatter.ofPattern("d MMM", locale()).withZone(zone).format(it) } ?: ""

fun yearOf(iso: String, zone: ZoneId = ZoneId.systemDefault()): String =
    instant(iso)?.atZone(zone)?.year?.toString() ?: ""

fun longDate(iso: String, zone: ZoneId = ZoneId.systemDefault()): String =
    instant(iso)?.let {
        DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale()).withZone(zone).format(it)
    } ?: ""

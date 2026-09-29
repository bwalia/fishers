package com.fishers.app.scores

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * A match from the wider game — an international or a domestic competition —
 * as opposed to a club fixture scored in this app.
 *
 * The server's own shape, from `backend/domain/src/world_cricket.rs`. Nothing
 * here is decided on the phone: which matches count as being played, and in
 * what order, is settled by the API so that Android, iOS and the web cannot
 * disagree about it.
 */
@Serializable
data class WorldMatch(
    val id: String,
    @SerialName("league_name") val leagueName: String,
    @SerialName("league_season") val leagueSeason: Int? = null,

    @SerialName("home_team_name") val homeTeamName: String,
    @SerialName("home_team_short") val homeTeamShort: String? = null,
    @SerialName("home_team_logo") val homeTeamLogo: String? = null,
    @SerialName("away_team_name") val awayTeamName: String,
    @SerialName("away_team_short") val awayTeamShort: String? = null,
    @SerialName("away_team_logo") val awayTeamLogo: String? = null,

    @SerialName("country_code") val countryCode: String? = null,
    @SerialName("country_name") val countryName: String? = null,

    /** `T20`, `ODI` or `TEST`. */
    val format: String? = null,
    /** `SINGLE` or `MULTI` — whether it runs over more than one day. */
    @SerialName("day_type") val dayType: String? = null,

    @SerialName("start_time") val startTime: String? = null,
    /**
     * Left as the feed's own `YYYY-MM-DD` string rather than parsed: it is a
     * calendar day, not a moment, and turning it into one in the phone's
     * timezone is how a match ends up filed under the wrong day.
     */
    @SerialName("start_date") val startDate: String,
    @SerialName("end_date") val endDate: String? = null,

    /** The feed's own words: "In play", "Tea", "Stumps", "Finished". */
    val state: String,
    /** `live`, `pending` or `done`. */
    val phase: String,
    /** "Day 2 - Maiwand need 390 runs." */
    val report: String? = null,

    /** Strings rather than numbers: a Test innings reads "128 & 59/5". */
    @SerialName("home_score") val homeScore: String? = null,
    @SerialName("home_info") val homeInfo: String? = null,
    @SerialName("away_score") val awayScore: String? = null,
    @SerialName("away_info") val awayInfo: String? = null,
) {
    val isLive: Boolean get() = phase == "live"

    /** The feed shouts TEST; a scorecard should not. */
    val formatLabel: String?
        get() = format?.uppercase()?.let { if (it == "TEST") "Test" else it }

    /**
     * The side with an over count against it is the side at the crease. The
     * feed does not say so outright — it only ever fills that field in for
     * whoever is batting.
     */
    val homeBatting: Boolean get() = isLive && !homeInfo.isNullOrBlank()
    val awayBatting: Boolean get() = isLive && !awayInfo.isNullOrBlank()

    /** Two letters for a missing badge, so the row keeps its shape. */
    val homeInitials: String get() = (homeTeamShort ?: homeTeamName).take(2).uppercase()
    val awayInitials: String get() = (awayTeamShort ?: awayTeamName).take(2).uppercase()

    /**
     * When it starts, in the reader's own timezone. A fixture list in UTC is a
     * fixture list nobody can use.
     */
    val startLabel: String?
        get() = startTime?.let {
            runCatching {
                val at = Instant.parse(it).atZone(ZoneId.systemDefault())
                val today = Instant.now().atZone(ZoneId.systemDefault()).toLocalDate()
                val pattern = if (at.toLocalDate() == today) "HH:mm" else "EEE HH:mm"
                at.format(DateTimeFormatter.ofPattern(pattern))
            }.getOrNull()
        }
}

/** Everything the scores screen needs, in one response. */
@Serializable
data class WorldScores(
    /**
     * False where no feed is configured — int and test, for instance. The
     * screen says so rather than showing an empty list, which reads as
     * breakage.
     */
    val enabled: Boolean = false,
    /**
     * When the feed was last read. Always shown: on the free allowance these
     * scores are minutes rather than seconds old, and one that is quietly
     * stale is worse than one that admits its age.
     */
    @SerialName("as_of") val asOf: String? = null,
    val live: List<WorldMatch> = emptyList(),
    val upcoming: List<WorldMatch> = emptyList(),
    val recent: List<WorldMatch> = emptyList(),
) {
    /**
     * How old the scores are, said plainly. Under a minute is "just now"
     * rather than "0 minutes ago", which reads like a bug.
     */
    fun freshness(now: Instant = Instant.now()): String {
        val at = asOf?.let { runCatching { Instant.parse(it) }.getOrNull() }
            ?: return "not loaded yet"
        val mins = Duration.between(at, now).toMinutes()
        return when {
            mins < 1 -> "just now"
            mins == 1L -> "1 minute ago"
            mins < 60 -> "$mins minutes ago"
            else -> {
                val hours = Math.round(mins / 60.0)
                if (hours == 1L) "1 hour ago" else "$hours hours ago"
            }
        }
    }
}


/**
 * One batter's line on the card.
 *
 * `howOut` arrives already composed — "c Kotian b Mulani", "not out", "did not
 * bat". The conventions are fiddly enough (a catch by the bowler is "c & b", a
 * run out names no bowler at all) that three clients would get them three
 * different kinds of wrong, so the API writes the phrase.
 */
@Serializable
data class BattingRow(
    val name: String,
    val runs: Int? = null,
    val balls: Int? = null,
    val fours: Int? = null,
    val sixes: Int? = null,
    @SerialName("strike_rate") val strikeRate: Double? = null,
    @SerialName("how_out") val howOut: String,
    @SerialName("not_out") val notOut: Boolean = false,
)

@Serializable
data class BowlingRow(
    val name: String,
    val overs: Double? = null,
    val maidens: Int? = null,
    val runs: Int? = null,
    val wickets: Int? = null,
    val economy: Double? = null,
)

@Serializable
data class FallOfWicket(
    /** Already counted from one; the feed counts from zero. */
    val wicket: Int,
    val runs: Int? = null,
    val overs: Double? = null,
    val batter: String? = null,
)

@Serializable
data class Extras(
    val total: Int? = null,
    val byes: Int? = null,
    @SerialName("leg_byes") val legByes: Int? = null,
    val wides: Int? = null,
    @SerialName("no_balls") val noBalls: Int? = null,
) {
    /** "4b, 2lb, 21nb" — only the ones that happened. */
    val breakdown: String?
        get() = listOfNotNull(
            byes?.takeIf { it > 0 }?.let { "${it}b" },
            legByes?.takeIf { it > 0 }?.let { "${it}lb" },
            wides?.takeIf { it > 0 }?.let { "${it}w" },
            noBalls?.takeIf { it > 0 }?.let { "${it}nb" },
        ).ifEmpty { null }?.joinToString(", ")
}

@Serializable
data class Innings(
    @SerialName("team_name") val teamName: String,
    /** "AUS-A" — what a tab is labelled with. */
    @SerialName("team_short") val teamShort: String? = null,
    @SerialName("team_logo") val teamLogo: String? = null,
    /** Computed by the API: runs off the bat plus extras. */
    @SerialName("total_runs") val totalRuns: Int? = null,
    val wickets: Int? = null,
    val batting: List<BattingRow> = emptyList(),
    val bowling: List<BowlingRow> = emptyList(),
    @SerialName("fall_of_wickets") val fallOfWickets: List<FallOfWicket> = emptyList(),
    val extras: Extras = Extras(),
) {
    /** "105-7", or "105" where nobody is out. */
    val score: String?
        get() = totalRuns?.let { if ((wickets ?: 0) > 0) "$it-$wickets" else "$it" }
}

/**
 * Somebody at the crease or bowling right now. `line` is composed server-side —
 * "101 (153b, 7x4, 3x6)" for a batter, "1/19 (11.6 ov)" for a bowler.
 */
@Serializable
data class CurrentPlayer(
    val name: String,
    @SerialName("team_name") val teamName: String? = null,
    val line: String,
)

@Serializable
data class WorldMatchDetail(
    val venue: String? = null,
    @SerialName("batting_now") val battingNow: List<CurrentPlayer> = emptyList(),
    @SerialName("bowling_now") val bowlingNow: List<CurrentPlayer> = emptyList(),
    val innings: List<Innings> = emptyList(),
)

@Serializable
data class WorldMatchDetailView(
    val summary: WorldMatch,
    /** Null when no scorecard has been fetched for this match yet. */
    val detail: WorldMatchDetail? = null,
    @SerialName("detail_as_of") val detailAsOf: String? = null,
) {
    fun freshness(now: Instant = Instant.now()): String {
        val at = detailAsOf?.let { runCatching { Instant.parse(it) }.getOrNull() }
            ?: return "not loaded yet"
        val mins = Duration.between(at, now).toMinutes()
        return when {
            mins < 1 -> "just now"
            mins == 1L -> "1 minute ago"
            mins < 60 -> "$mins minutes ago"
            else -> Math.round(mins / 60.0).let { if (it == 1L) "1 hour ago" else "$it hours ago" }
        }
    }
}

/**
 * A Test has four innings and two of them belong to each side, so the team name
 * alone will not tell them apart.
 */
private fun List<Innings>.ordinalAt(index: Int): Pair<Int, Boolean> {
    val name = this[index].teamName
    val nth = take(index + 1).count { it.teamName == name }
    return nth to (count { it.teamName == name } > 1)
}

private fun ordinalWord(n: Int) = when (n) {
    1 -> "1st"; 2 -> "2nd"; 3 -> "3rd"; else -> "${n}th"
}

/** "MWC 2nd" — a tab's label, abbreviated because four must fit across a phone. */
fun List<Innings>.tabLabel(index: Int): String {
    val inn = this[index]
    val name = inn.teamShort ?: inn.teamName
    val (nth, repeated) = ordinalAt(index)
    return if (repeated) "$name ${ordinalWord(nth)}" else name
}

/** "Maiwand Champions · 2nd innings" — the heading, which has the room. */
fun List<Innings>.title(index: Int): String {
    val inn = this[index]
    val (nth, repeated) = ordinalAt(index)
    return if (repeated) "${inn.teamName} · ${ordinalWord(nth)} innings" else inn.teamName
}

/**
 * A side's score across the whole match: "103 & 105/7". An innings all out shows
 * just the runs; one still going shows the wickets too.
 *
 * Derived from the card rather than taken from the summary because the two are
 * fetched separately and the card is the fresher — two different numbers for the
 * same thing on one screen reads as a bug.
 */
fun List<Innings>.sideScore(team: String): String? {
    val mine = filter { it.teamName == team && it.totalRuns != null }
    if (mine.isEmpty()) return null
    return mine.joinToString(" & ") { inn ->
        if ((inn.wickets ?: 0) >= 10) "${inn.totalRuns}" else "${inn.totalRuns}/${inn.wickets ?: 0}"
    }
}

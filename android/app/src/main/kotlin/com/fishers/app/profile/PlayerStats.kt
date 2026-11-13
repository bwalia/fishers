package com.fishers.app.profile

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.Locale

/** One season on record — imported from Play-Cricket or worked out from matches scored here. */
@Serializable
data class PlayerSeasonStats(
    val id: String,
    @SerialName("season_year") val seasonYear: Int,
    val matches: Int = 0,
    val runs: Int = 0,
    val wickets: Int = 0,
    @SerialName("batting_innings") val battingInnings: Int = 0,
    @SerialName("not_outs") val notOuts: Int = 0,
    @SerialName("balls_faced") val ballsFaced: Int = 0,
    @SerialName("high_score") val highScore: Int? = null,
    @SerialName("overs_bowled") val oversBowled: Double = 0.0,
    @SerialName("bowling_runs") val bowlingRuns: Int = 0,
    val maidens: Int = 0,
    val catches: Int = 0,
    val stumpings: Int = 0,
    @SerialName("magic_moments") val magicMoments: Int = 0,
    @SerialName("club_name") val clubName: String? = null,
    @SerialName("batting_average") val battingAverage: Double? = null,
    @SerialName("bowling_average") val bowlingAverage: Double? = null,
    @SerialName("strike_rate") val strikeRate: Double? = null,
    @SerialName("play_cricket_profile_url") val playCricketProfileUrl: String? = null,
) {
    val economy: Double? get() = if (oversBowled > 0) bowlingRuns / oversBowled else null
}

/** An honour, with the catalogue's words for it. */
@Serializable
data class UserAchievement(
    val id: String,
    val title: String,
    val description: String? = null,
    val icon: String? = null,
    @SerialName("season_year") val seasonYear: Int? = null,
)

@Serializable
data class PlayCricketLink(
    val id: String,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("profile_url") val profileUrl: String? = null,
)

/** `GET /me/stats`. */
@Serializable
data class MeStats(
    val links: List<PlayCricketLink> = emptyList(),
    val seasons: List<PlayerSeasonStats> = emptyList(),
    val achievements: List<UserAchievement> = emptyList(),
)

/**
 * Another player, as their club-mates may see them — `TeammateProfile.swift`.
 * No email, phone, emergency contact or home location: being in the same club
 * is not consent to hand those over, and this type has nowhere to put them.
 */
@Serializable
data class TeammateProfile(
    val id: String,
    val name: String,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("position_role") val positionRole: String? = null,
    @SerialName("skill_level") val skillLevel: String? = null,
    @SerialName("primary_sport") val primarySport: String? = null,
    @SerialName("sport_profiles") val sportProfiles: List<SportProfile> = emptyList(),
    val reliability: ReliabilityScore? = null,
    /** Clubs you both play for — the reason you can see this at all. */
    @SerialName("shared_clubs") val sharedClubs: List<String> = emptyList(),
) {
    val mainSport: SportProfile?
        get() = sportProfiles.firstOrNull { it.sport == primarySport } ?: sportProfiles.firstOrNull()
}

/**
 * Career figures, summed — `Totals` in `CareerStatsView.swift`.
 *
 * The averages come from these sums, never from averaging the seasons' own
 * averages, which is a different and wrong number.
 */
class Totals(seasons: List<PlayerSeasonStats>) {
    val matches = seasons.sumOf { it.matches }
    val runs = seasons.sumOf { it.runs }
    val wickets = seasons.sumOf { it.wickets }
    val catches = seasons.sumOf { it.catches + it.stumpings }
    val magicMoments = seasons.sumOf { it.magicMoments }
    val battingInnings = seasons.sumOf { it.battingInnings }
    val notOuts = seasons.sumOf { it.notOuts }
    val ballsFaced = seasons.sumOf { it.ballsFaced }
    val overs = seasons.sumOf { it.oversBowled }
    val bowlingRuns = seasons.sumOf { it.bowlingRuns }

    /** Runs per dismissal. Never out is no average, which is not an average of zero. */
    val battingAverage: Double?
        get() = (battingInnings - notOuts).takeIf { it > 0 }?.let { runs.toDouble() / it }

    val strikeRate: Double? get() = if (ballsFaced > 0) runs.toDouble() / ballsFaced * 100 else null
    val bowlingAverage: Double? get() = if (wickets > 0) bowlingRuns.toDouble() / wickets else null
    val economy: Double? get() = if (overs > 0) bowlingRuns / overs else null
}

/** "24.50", or "—" for a figure that does not exist yet. */
fun figure(value: Double?, places: Int = 2): String =
    if (value == null || !value.isFinite()) "—" else String.format(Locale.US, "%.${places}f", value)

/**
 * The club somebody has played the most for — the one to name under their
 * name. Falls back to whatever team they typed on their sport profile.
 */
fun mainClub(seasons: List<PlayerSeasonStats>, fallback: String?): String? =
    seasons.filter { it.clubName != null }
        .groupBy { it.clubName!! }
        .maxByOrNull { (_, rows) -> rows.sumOf { it.matches } }
        ?.key ?: fallback

/** One "best of it" line: what, how much, and which season. */
data class Highlight(val labelKey: String, val value: String, val season: Int?)

/**
 * The bests across [rows], for one discipline — `CareerStatsView.highlights`.
 * Economy ranks lowest-first; magic moments only appear once there are some.
 */
fun careerHighlights(rows: List<PlayerSeasonStats>, batting: Boolean): List<Highlight> {
    fun best(pick: (PlayerSeasonStats) -> Double?): PlayerSeasonStats? =
        rows.mapNotNull { row -> pick(row)?.let { it to row } }.maxByOrNull { it.first }?.second

    val discipline = if (batting) {
        val hs = best { it.highScore?.toDouble() }
        val most = best { it.runs.toDouble() }
        val avg = best { it.battingAverage }
        listOf(
            Highlight("rest.highest_score_stat", hs?.highScore?.toString() ?: "—", hs?.seasonYear),
            Highlight("rest.most_runs_in_a_season", most?.runs?.toString() ?: "—", most?.seasonYear),
            Highlight("rest.best_average", figure(avg?.battingAverage), avg?.seasonYear),
        )
    } else {
        val wickets = best { it.wickets.toDouble() }
        val economy = best { row -> row.economy?.let { -it } }
        val maidens = best { it.maidens.toDouble() }
        listOf(
            Highlight("rest.most_wickets_in_a_season", wickets?.wickets?.toString() ?: "—", wickets?.seasonYear),
            Highlight("rest.best_economy", figure(economy?.economy), economy?.seasonYear),
            Highlight("rest.most_maidens", maidens?.maidens?.toString() ?: "—", maidens?.seasonYear),
        )
    }
    val magic = Totals(rows).magicMoments
    return if (magic > 0) discipline + Highlight("mm.title", "$magic", null) else discipline
}

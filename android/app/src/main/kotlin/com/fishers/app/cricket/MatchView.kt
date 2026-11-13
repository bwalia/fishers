package com.fishers.app.cricket

import com.fishers.app.i18n.t
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * What the screens read off a match: the engine's state JSON, decoded.
 *
 * Read-only, and only the fields something draws. Nothing here decides a
 * Law — whether a ball, a bowler or a batter is allowed is asked of the engine
 * (`Engine.accepts`, `Engine.refusal`), which is the server's own code. These
 * are the numbers it handed back, laid out for a person.
 *
 * The same shape comes from two places: the engine's fold on the scorer's
 * phone, and `GET /cricket/matches/{id}/scorecard` for everybody else — the
 * server serialises the very struct the engine does.
 */
@Serializable
data class MatchView(
    val status: String = "scheduled",
    @SerialName("overs_limit") val oversLimit: Int = 20,
    @SerialName("home_name") val homeName: String = "Home",
    @SerialName("away_name") val awayName: String = "Away",
    @SerialName("toss_winner") val tossWinner: String? = null,
    @SerialName("toss_decision") val tossDecision: String? = null,
    @SerialName("home_xi") val homeXi: List<String> = emptyList(),
    @SerialName("away_xi") val awayXi: List<String> = emptyList(),
    val innings: List<InningsView> = emptyList(),
    val target: Int? = null,
    val winner: String? = null,
    val margin: String? = null,
    val abandoned: Boolean = false,
    @SerialName("last_seq") val lastSeq: Long = 0,
    @SerialName("player_names") val playerNames: Map<String, String> = emptyMap(),
    @SerialName("left_handers") val leftHanders: List<String> = emptyList(),
    val substitutes: List<String> = emptyList(),
    val conditions: ConditionsView = ConditionsView(),
    @SerialName("player_of_the_match") val playerOfTheMatch: String? = null,
    @SerialName("super_overs") val superOvers: Int = 0,
) {
    val current: InningsView? get() = innings.lastOrNull()

    val isFinished: Boolean get() = status == "complete" || status == "published"
    val isInningsBreak: Boolean get() = status == "innings_break"

    /** A ball can be bowled. */
    val isLive: Boolean get() = status == "live" && current?.complete == false

    /** Both sheets are in and nobody has started an innings yet. */
    val isReadyToStart: Boolean get() = innings.isEmpty() && status == "ready"

    fun name(id: String?): String = id?.let { playerNames[it] ?: it.take(8) } ?: "—"

    fun sideName(side: String): String = if (side == "home") homeName else awayName

    fun xi(side: String): List<String> = if (side == "home") homeXi else awayXi

    fun players(side: String): List<Player> = xi(side).map { Player(it, name(it), it in leftHanders) }

    fun batsLeft(id: String?): Boolean = id != null && id in leftHanders

    /**
     * The over is done and the same bowler is still down for the next. The
     * engine refuses the next ball until somebody else is on, so the screen
     * asks the question rather than letting the scorer meet the refusal.
     */
    val needsNewBowler: Boolean
        get() {
            val inn = current ?: return false
            if (inn.complete || inn.ballsInCurrentOver != 0 || inn.legalBalls == 0) return false
            val bowler = inn.bowlerId ?: return false
            return inn.lastOverBowler == bowler && xi(inn.bowling).size > 1
        }

    /** What the side batting now still needs — only in a chase. */
    val runsNeeded: Int?
        get() {
            val target = target ?: return null
            val inn = current ?: return null
            if (inn.index == 0) return null
            return (target - inn.runs).coerceAtLeast(0)
        }

    val requiredRunRate: Double?
        get() {
            val needed = runsNeeded ?: return null
            val left = current?.ballsRemaining ?: return null
            return if (left == 0) 0.0 else needed * 6.0 / left
        }

    /** "Hemel need 34 off 21" — only while there is a chase on. */
    val chaseLine: String?
        get() {
            val inn = current ?: return null
            if (inn.index == 0 || inn.complete || isFinished) return null
            val needed = runsNeeded ?: return null
            val left = inn.ballsRemaining
            return if (left > 0) {
                t("sc.team_need_off", vars = mapOf("team" to sideName(inn.batting), "runs" to needed, "balls" to left))
            } else {
                t("sc.team_need_to_win", vars = mapOf("team" to sideName(inn.batting), "runs" to needed))
            }
        }

    /** The scores are level at the end: a super over decides it. */
    val needsASuperOver: Boolean
        get() = status == "complete" && winner == null && !abandoned && margin != "Match drawn" &&
            innings.size >= 2 && innings.size % 2 == 0 && !conditions.twoInnings

    /** The innings about to start belongs to a super over. */
    val nextIsSuperOver: Boolean get() = needsASuperOver || (isInningsBreak && current?.superOver == true)

    /** Who bats the next innings. A super over is opened by whoever batted second. */
    val nextBatting: String?
        get() {
            val last = current ?: return null
            if (needsASuperOver) return last.batting
            return opposite(last.batting)
        }

    /** The batting side for the first innings, from the toss. */
    val firstBatting: String
        get() {
            val winner = tossWinner ?: return "home"
            return if (tossDecision == "bowl") opposite(winner) else winner
        }

    /** "c Smith b Jones", "run out (Patel)", "not out" — the card's line. */
    fun dismissalText(batter: BatterView): String {
        if (batter.retiredHurt && !batter.out) return t("out.retired_hurt")
        if (!batter.out) return if (batter.hasBatted) t("out.not_out") else t("out.did_not_bat")
        val bowler = batter.bowlerId?.let { name(it) }
        // "c sub (Patel) b Jones" is not the same claim as "c Patel b Jones".
        val fielder = batter.fielderId?.let { if (it in substitutes) "sub (${name(it)})" else name(it) }
        return when (batter.dismissal) {
            "bowled" -> bowler?.let { "b $it" } ?: t("out.bowled")
            "caught" -> when {
                fielder != null && bowler != null -> "c $fielder b $bowler"
                bowler != null -> "c & b $bowler"
                else -> t("out.caught")
            }
            "lbw" -> bowler?.let { "lbw b $it" } ?: t("out.lbw")
            "stumped" -> when {
                fielder != null && bowler != null -> "st $fielder b $bowler"
                bowler != null -> "st b $bowler"
                else -> t("out.stumped")
            }
            "hit_wicket" -> bowler?.let { "${t("out.hit_wicket")} b $it" } ?: t("out.hit_wicket")
            "run_out" -> fielder?.let { "${t("out.run_out")} ($it)" } ?: t("out.run_out")
            "retired" -> t("out.retired")
            "retired_hurt" -> t("out.retired_hurt")
            "obstructing_the_field" -> t("out.obstructing_the_field")
            "hit_the_ball_twice" -> t("out.hit_the_ball_twice")
            "timed_out" -> t("out.timed_out")
            else -> t("out.other")
        }
    }

    /** "Hemel 142/4 (16.0)" — the line at the top of the scorer. */
    fun scoreLine(): String {
        val inn = current ?: return "$homeName v $awayName"
        return "${sideName(inn.batting)} ${inn.score} (${inn.overs})"
    }

    companion object {
        fun opposite(side: String): String = if (side == "home") "away" else "home"
    }
}

@Serializable
data class ConditionsView(
    @SerialName("overs_limit") val oversLimit: Int = 20,
    @SerialName("overs_per_bowler") val oversPerBowler: Int = 0,
    @SerialName("powerplay_overs") val powerplayOvers: Int = 0,
    @SerialName("innings_per_side") val inningsPerSide: Int = 1,
) {
    val twoInnings: Boolean get() = inningsPerSide >= 2
}

@Serializable
data class InningsView(
    val index: Int = 0,
    val batting: String = "home",
    val bowling: String = "away",
    val runs: Int = 0,
    val wickets: Int = 0,
    @SerialName("legal_balls") val legalBalls: Int = 0,
    val extras: Int = 0,
    val batters: List<BatterView> = emptyList(),
    val bowlers: List<BowlerView> = emptyList(),
    val fall: List<FallView> = emptyList(),
    val deliveries: List<DeliveryView> = emptyList(),
    @SerialName("striker_id") val strikerId: String? = null,
    @SerialName("non_striker_id") val nonStrikerId: String? = null,
    @SerialName("bowler_id") val bowlerId: String? = null,
    val complete: Boolean = false,
    @SerialName("balls_in_current_over") val ballsInCurrentOver: Int = 0,
    val wides: Int = 0,
    @SerialName("no_balls") val noBalls: Int = 0,
    val byes: Int = 0,
    @SerialName("leg_byes") val legByes: Int = 0,
    val penalties: Int = 0,
    @SerialName("partnership_runs") val partnershipRuns: Int = 0,
    @SerialName("partnership_balls") val partnershipBalls: Int = 0,
    val declared: Boolean = false,
    val forfeited: Boolean = false,
    @SerialName("wickets_allowed") val wicketsAllowed: Int = 10,
    @SerialName("overs_available") val oversAvailable: Int = 0,
    @SerialName("last_over_bowler") val lastOverBowler: String? = null,
    @SerialName("free_hit") val freeHit: Boolean = false,
    @SerialName("super_over") val superOver: Boolean = false,
    @SerialName("powerplay_overs") val powerplayOvers: Int = 0,
) {
    /** "12.4" — overs as a scorebook writes them, not as a decimal. */
    val overs: String get() = "${legalBalls / 6}.${legalBalls % 6}"

    val score: String get() = "$runs/$wickets${if (declared) " dec" else ""}"

    val runRate: Double get() = if (legalBalls == 0) 0.0 else runs * 6.0 / legalBalls

    /** Balls left, or 0 when no limit is recorded. */
    val ballsRemaining: Int get() = if (oversAvailable == 0) 0 else (oversAvailable * 6 - legalBalls).coerceAtLeast(0)

    val inPowerplay: Boolean get() = powerplayOvers > 0 && legalBalls < powerplayOvers * 6

    val powerplayOversLeft: Int get() = ((powerplayOvers * 6 - legalBalls).coerceAtLeast(0) + 5) / 6

    /** This over's balls, for the strip above the buttons. Extras can push it past six. */
    val thisOver: List<DeliveryView> get() = deliveries.filter { it.over == legalBalls / 6 }.takeLast(10)

    /** The over just finished — shown while the next bowler is being chosen. */
    val lastOver: List<DeliveryView>
        get() = if (legalBalls == 0) emptyList() else deliveries.filter { it.over == legalBalls / 6 - 1 }.takeLast(10)

    fun batter(id: String?): BatterView? = batters.firstOrNull { it.playerId == id }
    fun bowler(id: String?): BowlerView? = bowlers.firstOrNull { it.playerId == id }

    /** Everyone who has been in, or is in now — the card's batting rows. */
    val batted: List<BatterView>
        get() = batters.filter { it.hasBatted || it.playerId == strikerId || it.playerId == nonStrikerId }

    val didNotBat: List<BatterView>
        get() {
            val played = batted.map { it.playerId }.toSet()
            return batters.filterNot { it.playerId in played }
        }

    /** "(b 2, lb 1, w 4, nb 1)". */
    val extrasBreakdown: String
        get() {
            val parts = buildList {
                if (byes > 0) add("b $byes")
                if (legByes > 0) add("lb $legByes")
                if (wides > 0) add("w $wides")
                if (noBalls > 0) add("nb $noBalls")
                if (penalties > 0) add("p $penalties")
            }
            return if (parts.isEmpty()) "—" else parts.joinToString(", ", "(", ")")
        }
}

@Serializable
data class BatterView(
    @SerialName("player_id") val playerId: String,
    val runs: Int = 0,
    val balls: Int = 0,
    val fours: Int = 0,
    val sixes: Int = 0,
    val out: Boolean = false,
    val dismissal: String? = null,
    @SerialName("retired_hurt") val retiredHurt: Boolean = false,
    @SerialName("bowler_id") val bowlerId: String? = null,
    @SerialName("fielder_id") val fielderId: String? = null,
) {
    val hasBatted: Boolean get() = balls > 0 || runs > 0 || out || retiredHurt
    val canResume: Boolean get() = retiredHurt && !out
    val strikeRate: Double get() = if (balls == 0) 0.0 else runs * 100.0 / balls
}

@Serializable
data class BowlerView(
    @SerialName("player_id") val playerId: String,
    val balls: Int = 0,
    val runs: Int = 0,
    val wickets: Int = 0,
    val maidens: Int = 0,
    val wides: Int = 0,
    @SerialName("no_balls") val noBalls: Int = 0,
) {
    val overs: String get() = "${balls / 6}.${balls % 6}"

    /** "3.2-0-24-2": overs, maidens, runs, wickets. */
    val figures: String get() = "$overs-$maidens-$runs-$wickets"

    val economy: Double get() = if (balls == 0) 0.0 else runs * 6.0 / balls
}

@Serializable
data class FallView(
    val score: Int,
    val wickets: Int,
    @SerialName("batter_id") val batterId: String,
    @SerialName("over_ball") val overBall: String,
    @SerialName("partnership_runs") val partnershipRuns: Int = 0,
    @SerialName("partnership_balls") val partnershipBalls: Int = 0,
)

@Serializable
data class ShotView(
    val angle: Int,
    val kind: String = "other",
    val reach: Float = 0.6f,
)

@Serializable
data class DeliveryView(
    val over: Int,
    @SerialName("ball_in_over") val ballInOver: Int,
    val label: String,
    val runs: Int = 0,
    @SerialName("is_legal") val isLegal: Boolean = true,
    @SerialName("is_wicket") val isWicket: Boolean = false,
    @SerialName("batter_id") val batterId: String? = null,
    @SerialName("bowler_id") val bowlerId: String? = null,
    val shot: ShotView? = null,
) {
    /** "12.4" — the over and ball this was, as the commentary marks it. */
    val marker: String get() = "$over.$ballInOver"
}

/** Somebody on a team sheet. */
data class Player(val id: String, val name: String, val batsLeft: Boolean = false)

/** Two places, the way a scoreboard shows a rate. */
fun rate(value: Double): String = String.format(java.util.Locale.ROOT, "%.2f", value)

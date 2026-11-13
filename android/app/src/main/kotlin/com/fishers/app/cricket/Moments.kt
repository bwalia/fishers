package com.fishers.app.cricket

import com.fishers.app.i18n.t

/**
 * A four, a six or a wicket — the ball that just happened, if it was one.
 * `Moments.swift`.
 */
data class Moment(val kind: Kind, val who: String, val detail: String? = null) {
    enum class Kind { Four, Six, Wicket }

    val word: String
        get() = when (kind) {
            Kind.Four -> t("moment.four")
            Kind.Six -> t("moment.six")
            Kind.Wicket -> t("moment.wicket")
        }

    /** What a screen reader says, once. */
    val spoken: String
        get() = when (kind) {
            Kind.Four -> t("moment.said.four", vars = mapOf("who" to who))
            Kind.Six -> t("moment.said.six", vars = mapOf("who" to who))
            Kind.Wicket -> t("moment.said.wicket", vars = mapOf("who" to who))
        }

    val lastsMillis: Long
        get() = when (kind) {
            Kind.Four -> 1900
            Kind.Six -> 2100
            Kind.Wicket -> 2500
        }

    companion object {
        /**
         * Worked out by comparing the match before and after, never guessed
         * from a run total: a four is the striker's `fours` going up, which a
         * four *run* does not do. Only a new ball sets one off — a first load,
         * a new innings and an undo never do.
         */
        fun between(before: MatchView?, after: MatchView?): Moment? {
            val now = after?.current ?: return null
            val then = before?.innings?.firstOrNull { it.index == now.index } ?: return null
            if (now.deliveries.size <= then.deliveries.size) return null

            if (now.wickets > then.wickets) {
                val out = now.batters.firstOrNull { b -> b.out && then.batter(b.playerId)?.out != true }
                return Moment(
                    Kind.Wicket,
                    who = out?.let { after.name(it.playerId) } ?: t("sc.wicket"),
                    detail = out?.let { after.dismissalText(it) },
                )
            }
            for (batter in now.batters) {
                val earlier = then.batter(batter.playerId)
                if (batter.sixes > (earlier?.sixes ?: 0)) return Moment(Kind.Six, after.name(batter.playerId))
                if (batter.fours > (earlier?.fours ?: 0)) return Moment(Kind.Four, after.name(batter.playerId))
            }
            return null
        }
    }
}

/**
 * A line for each ball, written from the log — what the follower reads under
 * the card, and the last few under the scorer's score. `CricketCommentary.swift`,
 * cut to what the log says for certain.
 */
data class BallLine(val marker: String, val text: String, val isWicket: Boolean, val isBoundary: Boolean)

object Commentary {
    /** Newest first. */
    fun lines(view: MatchView, innings: InningsView, limit: Int = 120): List<BallLine> {
        var wickets = 0
        // Every wicket in the deliveries has its row in the fall of wickets,
        // in the same order — the engine writes the two together.
        val all = innings.deliveries.map { ball ->
            val fall = if (ball.isWicket) innings.fall.getOrNull(wickets++) else null
            line(view, innings, ball, fall)
        }
        return all.takeLast(limit).reversed()
    }

    fun line(view: MatchView, innings: InningsView, ball: DeliveryView, fall: FallView? = null): BallLine {
        val who = when {
            ball.bowlerId != null && ball.batterId != null ->
                t("ball.bowler_to_batter", vars = mapOf("bowler" to view.name(ball.bowlerId), "batter" to view.name(ball.batterId)))
            ball.batterId != null -> t("ball.batter_only", vars = mapOf("batter" to view.name(ball.batterId)))
            else -> ""
        }
        val label = ball.label
        val outcome = when {
            ball.isWicket -> {
                val out = fall?.let { innings.batter(it.batterId) }
                listOfNotNull(t("moment.wicket"), out?.let { "${view.name(it.playerId)} ${view.dismissalText(it)}" })
                    .joinToString(" ")
            }
            label == "6" -> t("moment.six")
            label == "4" -> t("moment.four")
            label.startsWith("wd") -> t("sc.wide_n_runs", vars = mapOf("n" to ball.runs))
            label.startsWith("nb") -> t("sc.no_ball_n_runs", vars = mapOf("n" to ball.runs))
            label.endsWith("lb") -> t("sc.n_leg_byes", count = ball.runs, vars = mapOf("n" to ball.runs))
            label.endsWith("b") -> t("sc.n_byes", count = ball.runs, vars = mapOf("n" to ball.runs))
            label.endsWith("p") -> t("sc.n_penalty_runs", vars = mapOf("n" to ball.runs))
            label == "RH" -> t("out.retired_hurt")
            ball.runs == 0 -> t("sc.no_run")
            else -> t("la.over_runs", count = ball.runs, vars = mapOf("n" to ball.runs))
        }
        return BallLine(
            marker = ball.marker,
            text = t("ball.without_shot", vars = mapOf("who" to who, "outcome" to outcome)).trim(),
            isWicket = ball.isWicket,
            isBoundary = label == "4" || label == "6",
        )
    }
}

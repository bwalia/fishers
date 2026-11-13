package com.fishers.app.cricket

import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * The event kinds the scorer sends, in the wire shape of `ScoringEventKind`
 * (`backend/cricket/src/types.rs`, `#[serde(tag = "type")]`).
 *
 * Built, never validated, here: whether one is allowed is the engine's to
 * say, and every one of these goes through it before it is kept or sent.
 */
object Events {
    fun delivery(runs: Int, shortRuns: Int = 0, shot: Shot? = null): JsonObject = buildJsonObject {
        put("type", "delivery_recorded")
        put("runs", runs)
        put("is_legal", true)
        put("is_boundary_four", runs == 4)
        put("is_boundary_six", runs == 6)
        put("short_runs", shortRuns)
        shot?.let { put("shot", it.json()) }
    }

    /**
     * `runs` is what they ran (or the boundary) *on top of* the one a wide or
     * a no ball carries by itself: a wide they ran one off is `wide, 1`, two
     * to the side. `offTheBat` is a no ball's runs going to the batter.
     */
    fun extra(
        kind: String,
        runs: Int = 0,
        boundary: Boolean = false,
        offTheBat: Boolean = false,
        shot: Shot? = null,
    ): JsonObject = buildJsonObject {
        put("type", "extras_recorded")
        put("kind", kind)
        put("runs", runs)
        put("boundary", boundary)
        put("off_the_bat", offTheBat)
        shot?.let { put("shot", it.json()) }
    }

    fun wicket(
        batterId: String,
        kind: String,
        fielderId: String? = null,
        newBatterId: String? = null,
        runs: Int = 0,
        onExtra: Boolean = false,
    ): JsonObject = buildJsonObject {
        put("type", "wicket_recorded")
        put("batter_id", batterId)
        put("kind", kind)
        put("fielder_id", fielderId?.let(::JsonPrimitive) ?: JsonNull)
        put("new_batter_id", newBatterId?.let(::JsonPrimitive) ?: JsonNull)
        put("runs", runs)
        put("on_extra", onExtra)
    }

    fun bowlerChanged(bowlerId: String): JsonObject = buildJsonObject {
        put("type", "bowler_changed")
        put("bowler_id", bowlerId)
    }

    /** The engine numbers innings itself; `index` is only what the log says. */
    fun inningsStarted(
        index: Int,
        batting: String,
        strikerId: String,
        nonStrikerId: String,
        bowlerId: String,
        superOver: Boolean = false,
    ): JsonObject = buildJsonObject {
        put("type", "innings_started")
        put("innings_index", index)
        put("batting", batting)
        put("striker_id", strikerId)
        put("non_striker_id", nonStrikerId)
        put("bowler_id", bowlerId)
        put("super_over", superOver)
    }

    fun inningsCompleted(declared: Boolean = false, forfeited: Boolean = false): JsonObject = buildJsonObject {
        put("type", "innings_completed")
        put("declared", declared)
        put("forfeited", forfeited)
    }

    fun matchCompleted(winner: String?, margin: String): JsonObject = buildJsonObject {
        put("type", "match_completed")
        put("winner", winner?.let(::JsonPrimitive) ?: JsonNull)
        put("margin", margin)
    }

    fun penaltyRuns(runs: Int, reason: String, toSide: String?): JsonObject = buildJsonObject {
        put("type", "penalty_runs")
        put("runs", runs)
        put("reason", reason)
        put("to_side", toSide?.let(::JsonPrimitive) ?: JsonNull)
    }

    fun playerOfTheMatch(playerId: String): JsonObject = buildJsonObject {
        put("type", "player_of_the_match")
        put("player_id", playerId)
    }

    fun undo(): JsonObject = buildJsonObject { put("type", "undo_last") }
}

/**
 * Where the ball went, for the wagon wheel. `angle` is degrees clockwise from
 * straight down the ground past the bowler, as struck; `reach` is 0 at the
 * stumps and 1 at the rope.
 */
data class Shot(val angle: Int, val kind: String = "other", val reach: Float = 0.6f) {
    fun json(): JsonObject = buildJsonObject {
        put("angle", angle)
        put("kind", kind)
        put("reach", reach)
    }
}

/** The ways out, in the order the wicket sheet offers them. Wire names. */
object Dismissals {
    val all = listOf(
        "bowled", "caught", "lbw", "run_out", "stumped", "hit_wicket",
        "retired", "retired_hurt", "obstructing_the_field", "hit_the_ball_twice", "timed_out", "other",
    )

    /** On a free hit the Laws allow very little — the same short list as off a no ball. */
    fun allowedOnAFreeHit(kind: String) = kind in setOf(
        "run_out", "retired", "retired_hurt", "obstructing_the_field", "hit_the_ball_twice", "timed_out", "other",
    )

    /** Can land on a delivery already booked as an extra — stumped off a wide. */
    fun canFollowAnExtra(kind: String) =
        kind in setOf("stumped", "run_out", "other", "obstructing_the_field", "hit_the_ball_twice")

    /** Who took the catch, ran them out, made the stumping. */
    fun needsFielder(kind: String) = kind in setOf("caught", "run_out", "stumped")

    /** Only these can take the batter at the other end. */
    fun canDismissNonStriker(kind: String) = kind in setOf("run_out", "retired", "retired_hurt")

    fun allowsCompletedRuns(kind: String) = kind == "run_out"

    /** Retired hurt costs a batter but not a wicket. */
    fun costsAWicket(kind: String) = kind != "retired_hurt"
}

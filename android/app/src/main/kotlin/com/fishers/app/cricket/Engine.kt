package com.fishers.app.cricket

import com.fishers.app.i18n.t
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import uniffi.fishers_ffi.EngineException
import uniffi.fishers_ffi.applyEvent
import uniffi.fishers_ffi.replayMatch
import uniffi.fishers_ffi.wouldAccept

/**
 * The cricket engine, as this app talks to it.
 *
 * Everything below goes through `backend/ffi`, which is the same Rust the
 * server scores with. That is the whole point: when the scorer taps and the
 * screen changes, it is the server's rules that decided it, so the phone and
 * the server cannot come to different views of who won.
 *
 * The state is kept as the JSON the engine handed back. The screens decode it
 * into [MatchView] to draw it, and only to draw it: every question of what is
 * allowed goes back to the engine ([accepts], [refusal]), never to a Kotlin
 * copy of the Laws.
 */
class Engine(private val json: Json = Json { ignoreUnknownKeys = true; coerceInputValues = true }) {

    /** Build a match from its whole log. */
    fun replay(events: List<ScoringEvent>): Result<String> = runCatching {
        replayMatch(json.encodeToString(ListSerializer(ScoringEvent.serializer()), events))
    }

    /** Apply one event, and hand back the new state. */
    fun apply(state: String, event: ScoringEvent): Result<String> = runCatching {
        applyEvent(state, json.encodeToString(ScoringEvent.serializer(), event))
    }

    /**
     * The state after [event], given the [log] that made [state].
     *
     * One event is applied to the state as it stands — except an undo. The
     * engine's undo stack is rebuilt by replaying and never travels in the
     * JSON, so an undo applied to a state handed back across the boundary
     * finds nothing to undo. An undo is folded from the whole log instead,
     * which is exactly what the server does with it.
     */
    fun next(log: List<ScoringEvent>, state: String, event: ScoringEvent): Result<String> =
        if (event.kind["type"]?.jsonPrimitive?.contentOrNull == "undo_last") {
            replay(log + event)
        } else {
            apply(state, event)
        }

    /** Whether the engine would take it — for grey-ing a button out rather
     *  than letting somebody tap it and be told no. */
    fun accepts(state: String, event: ScoringEvent): Boolean =
        runCatching {
            wouldAccept(state, json.encodeToString(ScoringEvent.serializer(), event))
        }.getOrDefault(false)

    /**
     * Why the engine would refuse this, or null when it would take it.
     *
     * For laying out a choice — the bowlers who may bowl the next over, and
     * the reason against each who may not — in the engine's words rather than
     * a second copy of the Law here.
     */
    fun refusal(state: String, event: ScoringEvent): String? =
        apply(state, event).exceptionOrNull()?.let(::reason)

    /** What the engine said when it refused, in its own words. */
    fun reason(cause: Throwable): String = when (cause) {
        is EngineException.Refused -> inTheScorersLanguage(cause.detail)
        is EngineException.Malformed ->
            t("rest.the_book_could_not_be_read", vars = mapOf("detail" to cause.detail))
        else -> cause.message ?: t("rest.the_book_would_not_take_that")
    }

    /** The whole state, decoded for drawing. Null only if it is not a state at all. */
    fun view(state: String): MatchView? = runCatching {
        json.decodeFromString(MatchView.serializer(), state)
    }.getOrNull()

    /**
     * The sequence number of the last event the engine has seen.
     *
     * Read from the state's own root rather than from the scoreline, because
     * a match that has not started an innings has no scoreline — and an event
     * numbered with a sequence the log already holds is treated as a duplicate
     * and quietly skipped, which is right for a log and silent for a scorer.
     */
    fun lastSeq(state: String): Long = runCatching {
        json.parseToJsonElement(state).jsonObject["last_seq"]?.jsonPrimitive?.longOrNull ?: 0
    }.getOrDefault(0)

    // --- the few fields the old scoring screen draws ---

    fun scoreline(state: String): Scoreline? = runCatching {
        val root = json.parseToJsonElement(state).jsonObject
        val innings = root["innings"]?.jsonArray?.lastOrNull()?.jsonObject
            ?: return@runCatching null
        Scoreline(
            battingIsHome = innings["batting"]?.jsonPrimitive?.contentOrNull == "home",
            runs = innings["runs"]?.jsonPrimitive?.intOrNull ?: 0,
            wickets = innings["wickets"]?.jsonPrimitive?.intOrNull ?: 0,
            legalBalls = innings["legal_balls"]?.jsonPrimitive?.intOrNull ?: 0,
            complete = innings["complete"]?.jsonPrimitive?.contentOrNull == "true",
            homeName = root["home_name"]?.jsonPrimitive?.contentOrNull ?: "Home",
            awayName = root["away_name"]?.jsonPrimitive?.contentOrNull ?: "Away",
            target = root["target"]?.jsonPrimitive?.intOrNull,
            margin = root["margin"]?.jsonPrimitive?.contentOrNull,
            status = root["status"]?.jsonPrimitive?.contentOrNull ?: "scheduled",
            lastSeq = root["last_seq"]?.jsonPrimitive?.longOrNull ?: 0,
        )
    }.getOrNull()
}

data class Scoreline(
    val battingIsHome: Boolean,
    val runs: Int,
    val wickets: Int,
    val legalBalls: Int,
    val complete: Boolean,
    val homeName: String,
    val awayName: String,
    val target: Int?,
    val margin: String?,
    val status: String,
    val lastSeq: Long,
) {
    val battingName: String get() = if (battingIsHome) homeName else awayName

    /** "12.4" — overs the way a scorebook writes them, not as a decimal. */
    val overs: String get() = "${legalBalls / 6}.${legalBalls % 6}"

    val isComplete: Boolean get() = status == "complete"

    /** "Needs 34 off 21" — only while there is actually a chase on. */
    fun chase(oversLimit: Int): String? {
        if (target == null || isComplete) return null
        val needed = target - runs
        if (needed <= 0) return null
        val ballsLeft = oversLimit * 6 - legalBalls
        return if (ballsLeft > 0) {
            t("sc.needs_off", vars = mapOf("runs" to needed, "balls" to ballsLeft))
        } else {
            t("sc.needs_runs", vars = mapOf("runs" to needed))
        }
    }
}

/*
 * The engine's refusals are English sentences, written for a scorer. Those the
 * app has words for are shown in the reader's language; anything else stays as
 * the engine said it, which is still the right answer in English.
 */
private val plainRefusals = mapOf(
    "no live innings" to "sc.no_live_innings",
    "innings complete" to "sc.innings_complete",
    "new batter required" to "sc.new_batter_required",
    "nothing to undo" to "sc.nothing_to_undo",
    "it is a free hit — only a run out can get them" to "sc.free_hit_only_run_out_lower",
    "the two openers must be different players" to "sc.two_openers_must_differ",
    "both sides need a team sheet before the first ball" to "sc.both_sides_need_team_sheet",
    "only a batter who retired hurt can come back" to "sc.only_retired_hurt_can_return",
    "this match already has a result" to "sc.match_already_has_result",
    "batter not in innings" to "sc.batter_not_in_innings",
    "no striker" to "sc.no_striker",
    "no bowler" to "sc.no_bowler",
    "no innings" to "sc.no_innings_lower",
    "a penalty is at least one run" to "sc.penalty_at_least_one_run",
)

private val twoInARow =
    Regex("^(.+) bowled the last over — (nobody bowls two in a row|change the bowler before the next one)$")
private val usedUp = Regex("^(.+) has bowled their (\\d+) overs$")
private val takenOff = Regex("^(.+) has been taken off and cannot bowl again this innings$")

internal fun inTheScorersLanguage(detail: String): String {
    plainRefusals[detail]?.let { return t(it) }
    twoInARow.matchEntire(detail)?.let {
        return t("sc.bowled_it_nobody_two_in_row", vars = mapOf("name" to it.groupValues[1]))
    }
    usedUp.matchEntire(detail)?.let {
        return t("sc.has_bowled_their_overs", vars = mapOf("name" to it.groupValues[1], "n" to it.groupValues[2]))
    }
    takenOff.matchEntire(detail)?.let {
        return t("sc.taken_off_cannot_bowl", vars = mapOf("name" to it.groupValues[1]))
    }
    return detail
}

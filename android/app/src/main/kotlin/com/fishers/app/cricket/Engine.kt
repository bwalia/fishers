package com.fishers.app.cricket

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonObject
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
 * The state is kept as the JSON the engine handed back. Parsing it into Kotlin
 * classes would be another copy of the model to keep in step — the thing the
 * shared engine exists to stop — so the screen reads the few fields it draws
 * and leaves the rest alone.
 */
class Engine(private val json: Json = Json { ignoreUnknownKeys = true }) {

    /** Build a match from its whole log. */
    fun replay(events: List<ScoringEvent>): Result<String> = runCatching {
        replayMatch(json.encodeToString(ListSerializer(ScoringEvent.serializer()), events))
    }

    /** Apply one event, and hand back the new state. */
    fun apply(state: String, event: ScoringEvent): Result<String> = runCatching {
        applyEvent(state, json.encodeToString(ScoringEvent.serializer(), event))
    }

    /** Whether the engine would take it — for grey-ing a button out rather
     *  than letting somebody tap it and be told no. */
    fun accepts(state: String, event: ScoringEvent): Boolean =
        runCatching {
            wouldAccept(state, json.encodeToString(ScoringEvent.serializer(), event))
        }.getOrDefault(false)

    /** What the engine said when it refused, in its own words. */
    fun reason(t: Throwable): String = when (t) {
        is EngineException.Refused -> t.detail
        is EngineException.Malformed -> "The book could not be read: ${t.detail}"
        else -> t.message ?: "The book would not take that."
    }

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

    // --- the few fields the scoring screen draws ---

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
        return if (ballsLeft > 0) "Needs $needed off $ballsLeft" else "Needs $needed"
    }
}

/** Build the event kinds the scoring screen can send. */
object Events {
    fun delivery(runs: Int, shortRuns: Int = 0): JsonObject = jsonObject(
        "type" to "delivery_recorded",
        "runs" to runs,
        "is_legal" to true,
        "is_boundary_four" to (runs == 4),
        "is_boundary_six" to (runs == 6),
        "short_runs" to shortRuns,
    )

    fun extra(kind: String, runs: Int = 0): JsonObject = jsonObject(
        "type" to "extras_recorded",
        "kind" to kind,
        "runs" to runs,
        "boundary" to false,
        "off_the_bat" to false,
    )

    fun undo(): JsonObject = jsonObject("type" to "undo_last")

    private fun jsonObject(vararg pairs: Pair<String, Any>): JsonObject = JsonObject(
        pairs.associate { (k, v) ->
            k to when (v) {
                is Int -> kotlinx.serialization.json.JsonPrimitive(v)
                is Boolean -> kotlinx.serialization.json.JsonPrimitive(v)
                else -> kotlinx.serialization.json.JsonPrimitive(v.toString())
            }
        },
    )
}

package com.fishers.app.cricket

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

/**
 * The scoring API, from `backend/api/src/routes/cricket.rs`.
 *
 * The event log is the lasting record and the state is only ever a fold over
 * it. That fold is `backend/ffi` — the same Rust the server scores with — so
 * the shapes here are only what carries the log to and from the wire.
 */
@Serializable
data class CricketMatch(
    val id: String,
    @SerialName("event_id") val eventId: String,
    val status: String,
    @SerialName("overs_limit") val oversLimit: Int = 0,
    @SerialName("home_name") val homeName: String = "Home",
    @SerialName("away_name") val awayName: String = "Away",
    @SerialName("last_seq") val lastSeq: Long = 0,
    /** True when the caller is allowed to score this match. */
    @SerialName("can_score") val canScore: Boolean = false,
    @SerialName("active_scorer_user_id") val activeScorerUserId: String? = null,
)

/**
 * One event out of the log.
 *
 * `kind` stays a raw JSON object rather than a sealed hierarchy: the engine
 * reads it, not this app, and re-declaring twenty-two event shapes in Kotlin
 * would be the fourth copy of the model that the shared engine exists to
 * avoid. Anything the screen needs to know, it asks the engine.
 */
@Serializable
data class ScoringEvent(
    @SerialName("client_event_id") val clientEventId: String,
    val seq: Long,
    val kind: JsonObject,
    val at: String? = null,
)

@Serializable
data class EventsBatch(
    @SerialName("device_id") val deviceId: String? = null,
    val events: List<ScoringEvent>,
)

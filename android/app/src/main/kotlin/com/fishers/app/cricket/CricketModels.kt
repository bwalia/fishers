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
 *
 * The server also sends its own fold as `state` on every answer. It is left
 * out here on purpose: the scorer folds the log itself, and the follower reads
 * `/scorecard`, so nothing would read it.
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
    /** Which phone holds the book — this one, when it matches [DeviceId]. */
    @SerialName("active_scorer_device_id") val activeScorerDeviceId: String? = null,
    @SerialName("club_id") val clubId: String? = null,
    /** The visitors, when they are a club here — somebody to hand the book to. */
    @SerialName("opponent_club_id") val opponentClubId: String? = null,
    /** The side this caller plays for, `home` or `away`. */
    @SerialName("my_club_side") val myClubSide: String? = null,
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
    /** When the scorer tapped it, ISO 8601. The over rate is read from these. */
    val at: String? = null,
)

@Serializable
data class EventsBatch(
    @SerialName("device_id") val deviceId: String? = null,
    val events: List<ScoringEvent>,
)

@Serializable
data class ClaimScorerBody(
    @SerialName("device_id") val deviceId: String,
    /**
     * Take it off a scorer whose phone has died. Captains and secretaries
     * only, and logged. No default: the network's JSON leaves defaults out.
     */
    val force: Boolean,
)

/**
 * No defaults, deliberately. The network's JSON leaves a default out of the
 * body, and the server's own default for `post_to_chat` is *true* — so a
 * "false" that was a default would post the link into club chat.
 */
@Serializable
data class ShareScoreboardBody(
    @SerialName("post_to_chat") val postToChat: Boolean,
    @SerialName("ttl_hours") val ttlHours: Int,
)

@Serializable
data class ScoreboardShare(
    val token: String = "",
    val url: String,
    @SerialName("conversation_id") val conversationId: String? = null,
)

@Serializable
data class HandoverBody(@SerialName("to_user_id") val toUserId: String)

@Serializable
data class AbandonBody(val reason: String)

@Serializable
data class MatchOfficialRow(
    @SerialName("user_id") val userId: String,
    val name: String,
    val role: String,
)

@Serializable
data class SquadPlayer(
    val id: String,
    val name: String,
    @SerialName("bats_left") val batsLeft: Boolean = false,
)

@Serializable
data class SideSquad(
    @SerialName("team_name") val teamName: String = "",
    val players: List<SquadPlayer> = emptyList(),
)

@Serializable
data class MatchSquads(val home: SideSquad = SideSquad(), val away: SideSquad = SideSquad())

@Serializable
data class CommentaryRequest(
    val over: Int,
    @SerialName("ball_in_over") val ballInOver: Int,
    val lang: String? = null,
)

/** `line` is null when no model is set up, or it said something the ball did not do. */
@Serializable
data class BallCommentary(val line: String? = null)

/** Where the chase stands on Duckworth–Lewis–Stern. */
@Serializable
data class DlsPar(
    val par: Int,
    @SerialName("ahead_by") val aheadBy: Int,
    val target: Int,
)

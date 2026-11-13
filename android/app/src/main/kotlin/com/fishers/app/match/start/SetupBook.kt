package com.fishers.app.match.start

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.put

/** Encodes every field, defaults included: the engine reads the event, not this app. */
internal val SetupJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
    explicitNulls = false
}

/**
 * What the wizard reads off the engine's state: how far the setup has got.
 *
 * The engine's JSON is the state (`MatchState` in `backend/cricket/src/types.rs`);
 * this is the handful of fields a setup screen draws, decoded with unknown keys
 * ignored so the rest of the scorecard is left alone.
 */
@Serializable
data class SetupBook(
    val status: String = "scheduled",
    @SerialName("overs_limit") val oversLimit: Int = 20,
    @SerialName("home_name") val homeName: String = "Home",
    @SerialName("away_name") val awayName: String = "Away",
    @SerialName("toss_winner") val tossWinner: Side? = null,
    @SerialName("toss_decision") val tossDecision: TossCall? = null,
    @SerialName("home_xi") val homeXi: List<String> = emptyList(),
    @SerialName("away_xi") val awayXi: List<String> = emptyList(),
    @SerialName("home_captain") val homeCaptain: String? = null,
    @SerialName("away_captain") val awayCaptain: String? = null,
    @SerialName("home_keeper") val homeKeeper: String? = null,
    @SerialName("away_keeper") val awayKeeper: String? = null,
    @SerialName("last_seq") val lastSeq: Long = 0,
    @SerialName("player_names") val playerNames: Map<String, String> = emptyMap(),
    @SerialName("left_handers") val leftHanders: List<String> = emptyList(),
    val conditions: MatchConditions? = null,
    @SerialName("conditions_proposed_by") val conditionsProposedBy: Side? = null,
    @SerialName("agreed_home") val agreedHome: String? = null,
    @SerialName("agreed_away") val agreedAway: String? = null,
    val officials: MatchOfficials = MatchOfficials(),
) {
    fun agreed(side: Side): String? = if (side == Side.Home) agreedHome else agreedAway
    val bothAgreed: Boolean get() = agreedHome != null && agreedAway != null
    fun name(side: Side): String = if (side == Side.Home) homeName else awayName
    fun xi(side: Side): List<String> = if (side == Side.Home) homeXi else awayXi

    /** One side's sheet as players, batting order kept. */
    fun players(side: Side): List<MatchPlayer> = xi(side).map {
        MatchPlayer(it, playerNames[it] ?: "?", batsLeft = it in leftHanders)
    }

    /** Who bats first, once the toss is in. */
    val battingFirst: Side?
        get() {
            val winner = tossWinner ?: return null
            val call = tossDecision ?: return null
            return if (call == TossCall.Bat) winner else winner.opposite
        }

    /** Where the wizard picks up — `resumeOrPrepare` in `CricketScoringFlowView.swift`. */
    val step: SetupStep
        get() = when (status) {
            "live", "innings_break", "complete", "published" -> SetupStep.Scoring
            "ready" -> SetupStep.Openers
            "selecting_xi" -> SetupStep.Sheets
            "toss" -> SetupStep.Toss
            "preparing" -> if (conditionsProposedBy == null) SetupStep.Terms else SetupStep.Agreement
            else -> SetupStep.Terms
        }

    companion object {
        fun read(engineState: String): SetupBook =
            runCatching { SetupJson.decodeFromString(serializer(), engineState) }.getOrDefault(SetupBook())
    }
}

/** The wizard's pages, in order. `Scoring` is the hand-over to the scorer. */
enum class SetupStep { Terms, Agreement, Toss, Sheets, Openers, Scoring }

/**
 * The setup events, shaped as `ScoringEventKind` in `backend/cricket/src/types.rs`
 * serialises them — the same `type` tags and keys `CricketTypes.swift` writes.
 */
object SetupEvents {
    fun matchPrepared(oversLimit: Int, homeName: String, awayName: String): JsonObject = buildJsonObject {
        put("type", "match_prepared")
        put("overs_limit", oversLimit)
        put("home_name", homeName)
        put("away_name", awayName)
    }

    fun conditionsProposed(conditions: MatchConditions, by: Side, byName: String): JsonObject = buildJsonObject {
        put("type", "conditions_proposed")
        put("conditions", SetupJson.encodeToJsonElement(conditions))
        put("by", SetupJson.encodeToJsonElement(by))
        put("by_name", byName)
    }

    fun conditionsAgreed(side: Side, captainName: String): JsonObject = buildJsonObject {
        put("type", "conditions_agreed")
        put("side", SetupJson.encodeToJsonElement(side))
        put("captain_name", captainName)
    }

    fun tossRecorded(winner: Side, decision: TossCall): JsonObject = buildJsonObject {
        put("type", "toss_recorded")
        put("winner", SetupJson.encodeToJsonElement(winner))
        put("decision", SetupJson.encodeToJsonElement(decision))
    }

    fun xiSelected(side: Side, players: List<MatchPlayer>, captainId: String?, keeperId: String?): JsonObject =
        buildJsonObject {
            put("type", "xi_selected")
            put("side", SetupJson.encodeToJsonElement(side))
            put("players", SetupJson.encodeToJsonElement(players))
            captainId?.let { put("captain_id", it) }
            keeperId?.let { put("keeper_id", it) }
        }

    fun officialsAppointed(officials: MatchOfficials): JsonObject = buildJsonObject {
        put("type", "officials_appointed")
        put("officials", SetupJson.encodeToJsonElement(officials))
    }

    fun inningsStarted(batting: Side, strikerId: String, nonStrikerId: String, bowlerId: String): JsonObject =
        buildJsonObject {
            put("type", "innings_started")
            // The engine counts its own innings and ignores this; iOS sends 0.
            put("innings_index", 0)
            put("batting", SetupJson.encodeToJsonElement(batting))
            put("striker_id", strikerId)
            put("non_striker_id", nonStrikerId)
            put("bowler_id", bowlerId)
            put("super_over", JsonPrimitive(false))
        }
}

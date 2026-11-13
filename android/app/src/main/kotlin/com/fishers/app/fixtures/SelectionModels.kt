package com.fishers.app.fixtures

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Picking the side, from `backend/domain/src/selection.rs` and
// `ios/Fishers/Models/Selection.swift`.

/** Where a player sits in the selection for one fixture. */
@Serializable
enum class SelectionState {
    @SerialName("pool") Pool,
    @SerialName("selected") Selected,
    @SerialName("reserve") Reserve,
    @SerialName("not_selected") NotSelected,
    @SerialName("confirmed") Confirmed,
    @SerialName("declined") Declined,
    @SerialName("dropped") Dropped;

    val isInSquad: Boolean get() = this == Selected || this == Confirmed
}

@Serializable
data class SelectionCandidate(
    @SerialName("user_id") val userId: String,
    val name: String,
    val position: String? = null,
    /** Their standing calendar for the day. */
    val availability: AvailabilityStatus? = null,
    /** Their answer to this fixture — the one a captain picks off. */
    val rsvp: RsvpStatus? = null,
    @SerialName("reliability_score") val reliabilityScore: Long = 0,
    @SerialName("reliability_band") val reliabilityBand: String = "",
    /** Fixtures they were available for and left out of, last 60 days. */
    @SerialName("games_missed_out") val gamesMissedOut: Long = 0,
    val state: SelectionState = SelectionState.Pool,
    @SerialName("is_confirmed") val isConfirmed: Boolean = false,
) {
    /**
     * Said no, one way or the other. The fixture's own answer wins over the
     * calendar: somebody whose calendar says busy but who answered "available"
     * has told the captain something newer.
     */
    val ruledOut: Boolean
        get() = when (rsvp) {
            RsvpStatus.NotGoing -> true
            RsvpStatus.Going, RsvpStatus.Maybe -> false
            else -> availability == AvailabilityStatus.Unavailable
        }
}

@Serializable
data class RankedCandidate(
    @SerialName("user_id") val userId: String,
    val name: String,
    val score: Long = 0,
    /** Plain-English reasons, in the order the ranking applied them. */
    val reasons: List<String> = emptyList(),
)

@Serializable
data class SquadRequirements(
    val size: Int = 11,
    val reserves: Int = 0,
)

/** Everything the captain's selection screen needs, in one call. */
@Serializable
data class SelectionBoard(
    @SerialName("event_id") val eventId: String,
    val title: String,
    val sport: String = "",
    @SerialName("starts_at") val startsAt: String,
    val status: String = "scheduled",
    @SerialName("status_note") val statusNote: String? = null,
    val requirements: SquadRequirements = SquadRequirements(),
    /** `off` | `suggest` | `auto_publish` */
    val autonomy: String = "off",
    @SerialName("confirm_lead_hours") val confirmLeadHours: Int = 48,
    @SerialName("drop_lead_hours") val dropLeadHours: Int = 24,
    val candidates: List<SelectionCandidate> = emptyList(),
    val ranked: List<RankedCandidate> = emptyList(),
    @SerialName("selected_count") val selectedCount: Int = 0,
    @SerialName("confirmed_count") val confirmedCount: Int = 0,
) {
    fun reasons(userId: String): List<String> = ranked.firstOrNull { it.userId == userId }?.reasons.orEmpty()

    fun candidate(userId: String): SelectionCandidate? = candidates.firstOrNull { it.userId == userId }

    /** Whether the club lets the assistant have a go. */
    val isAssistantAvailable: Boolean get() = autonomy != "off"
}

/** A squad waiting to be published — from the ranking, or from the assistant. */
@Serializable
data class SquadProposal(
    /** `ranking` or `assistant` */
    val source: String = "ranking",
    val selected: List<RankedCandidate> = emptyList(),
    val reserves: List<RankedCandidate> = emptyList(),
    @SerialName("unmet_quotas") val unmetQuotas: List<String> = emptyList(),
    val announcement: String? = null,
    val concerns: String? = null,
    val confidence: String? = null,
    val published: Boolean = false,
) {
    val isFromAssistant: Boolean get() = source == "assistant"
}

@Serializable
data class SetSquadBody(
    val selected: List<String>,
    val reserves: List<String>,
    val announcement: String? = null,
    val publish: Boolean,
)

@Serializable
data class RespondToSelectionBody(val confirming: Boolean)

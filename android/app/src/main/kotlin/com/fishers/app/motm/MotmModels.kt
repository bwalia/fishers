package com.fishers.app.motm

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant

/**
 * Man of the match — `backend/domain/src/motm.rs`.
 *
 * `MotmPollView` arrives flattened: the poll's own fields sit beside the
 * candidates rather than nested under a key.
 */
@Serializable
data class MotmPollView(
    val id: String,
    @SerialName("event_id") val eventId: String,
    val title: String,
    /** The result as it stood when the card was posted. */
    val result: String? = null,
    /** `open` | `closed` */
    val status: String,
    @SerialName("closes_at") val closesAt: String,
    @SerialName("winner_user_id") val winnerUserId: String? = null,
    val candidates: List<MotmCandidate> = emptyList(),
    @SerialName("my_vote") val myVote: String? = null,
    @SerialName("total_votes") val totalVotes: Long = 0,
    /**
     * Whether `candidates[].votes` carries the real count. A running tally
     * shown before you vote is a nudge towards whoever is already ahead, so
     * the server hides it until you have voted or the poll has closed.
     */
    @SerialName("tally_visible") val tallyVisible: Boolean = false,
    @SerialName("can_vote") val canVote: Boolean = false,
    /** The scorer's own award. Shown beside the vote, never as the same thing. */
    @SerialName("scorer_award_user_id") val scorerAwardUserId: String? = null,
) {
    /**
     * Whether a vote cast right now would count.
     *
     * Past its closing time the poll is over whether or not anybody has run
     * the close yet — otherwise the answer depends on who asked last. The
     * server says the same; this is so the button greys out at the right
     * moment rather than on the next refresh.
     */
    fun isOpen(now: Instant = Instant.now()): Boolean =
        status == "open" && runCatching { Instant.parse(closesAt) > now }.getOrDefault(false)

    /** Only when the poll is live and the server has not already refused them. */
    fun votingAllowed(now: Instant = Instant.now()): Boolean = canVote && isOpen(now)

    val home: List<MotmCandidate> get() = candidates.filter { it.side == "home" }
    val away: List<MotmCandidate> get() = candidates.filter { it.side == "away" }
}

@Serializable
data class MotmCandidate(
    @SerialName("user_id") val userId: String,
    @SerialName("display_name") val displayName: String,
    /** `home` | `away` */
    val side: String,
    val votes: Long = 0,
)

@Serializable
data class CastMotmVoteRequest(
    @SerialName("candidate_user_id") val candidateUserId: String,
)

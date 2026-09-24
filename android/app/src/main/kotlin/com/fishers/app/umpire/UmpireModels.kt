package com.fishers.app.umpire

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Umpiring — `backend/domain/src/umpire.rs`.
 *
 * Club cricket umpires itself: the batting side gives two, or it is whoever is
 * next in. The app already knew who stood; nothing carried it forward. This is
 * the record that does.
 */
@Serializable
data class UmpireReview(
    val id: String,
    @SerialName("match_id") val matchId: String,
    /** One to five. */
    val rating: Int,
    val comment: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("reviewer_name") val reviewerName: String,
    @SerialName("reviewer_avatar_url") val reviewerAvatarUrl: String? = null,
    @SerialName("match_title") val matchTitle: String,
    @SerialName("played_on") val playedOn: String? = null,
)

@Serializable
data class UmpireProfile(
    @SerialName("user_id") val userId: String,
    /** Whether they have said they will stand — not the same as having stood. */
    val umpires: Boolean,
    val note: String? = null,
    val matches: Int,
    /** Null until somebody reviews. Not 0.0, which reads as "rated, badly". */
    @SerialName("rating_average") val ratingAverage: Double? = null,
    @SerialName("rating_count") val ratingCount: Int,
    /** How the ratings fall, one to five. */
    @SerialName("rating_breakdown") val ratingBreakdown: List<Long> = emptyList(),
    val reviews: List<UmpireReview> = emptyList(),
) {
    /** "4.3 from 12", or what to say before anybody has rated them. */
    val ratingLine: String
        get() = if (ratingAverage == null || ratingCount == 0) {
            "No ratings yet"
        } else {
            "%.1f from %d %s".format(ratingAverage, ratingCount,
                if (ratingCount == 1) "review" else "reviews")
        }
}

@Serializable
data class MatchUmpire(
    @SerialName("user_id") val userId: String,
    val name: String,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("my_rating") val myRating: Int? = null,
    @SerialName("my_comment") val myComment: String? = null,
)

/**
 * A finished match whose umpiring this player has not had their say on.
 *
 * The prompt at the end of a match only reaches whoever had that screen open.
 * This is the list that finds everybody else.
 */
@Serializable
data class PendingUmpireReview(
    @SerialName("match_id") val matchId: String,
    @SerialName("match_title") val matchTitle: String,
    @SerialName("played_on") val playedOn: String? = null,
    /** Only the umpires they have not already rated. */
    val umpires: List<MatchUmpire> = emptyList(),
)

@Serializable
data class AvailableUmpire(
    @SerialName("user_id") val userId: String,
    val name: String,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    val note: String? = null,
    val matches: Int,
    @SerialName("rating_average") val ratingAverage: Double? = null,
    @SerialName("rating_count") val ratingCount: Int,
)

/**
 * A PATCH of one field leaves the rest alone. `note` needs its own flag
 * because kotlinx drops a null by default and the note would never clear.
 */
@Serializable
data class UmpiringPatch(
    val umpires: Boolean? = null,
    val note: String? = null,
)

@Serializable
data class UmpireReviewBody(
    val rating: Int,
    val comment: String? = null,
)

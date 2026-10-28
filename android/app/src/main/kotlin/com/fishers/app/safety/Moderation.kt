package com.fishers.app.safety

import com.fishers.app.i18n.t
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Reporting something, and blocking somebody.
 *
 * The raw values are the wire contract — the API parses these exact strings
 * and answers 422 on anything else — so they are separate from the labels on
 * screen, which are translated.
 */
enum class ReportSubjectKind(val wire: String) {
    MESSAGE("message"),
    LISTING("listing"),
    USER("user"),
    CLUB("club"),
}

enum class ReportReason(val wire: String, val key: String) {
    ABUSE("abuse", "mod.reason_abuse"),
    OBJECTIONABLE("objectionable", "mod.reason_objectionable"),
    SPAM("spam", "mod.reason_spam"),
    IMPERSONATION("impersonation", "mod.reason_impersonation"),
    PRIVACY("privacy", "mod.reason_privacy"),
    OTHER("other", "mod.reason_other");

    /** The sentence on screen, so it reads in Punjabi too. */
    val label: String get() = t(key)
}

@Serializable
data class ReportRequest(
    @SerialName("subject_kind") val subjectKind: String,
    @SerialName("subject_id") val subjectId: String,
    val reason: String,
    val note: String? = null,
)

@Serializable
data class BlockRequest(
    @SerialName("user_id") val userId: String,
)

@Serializable
data class BlockedUser(
    val id: String,
    val name: String,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("blocked_at") val blockedAt: String,
)

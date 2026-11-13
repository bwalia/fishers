package com.fishers.app.onboarding

import com.fishers.app.i18n.t
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** `GET /me/verification` — `VerificationStatus` in `Onboarding.swift`. */
@Serializable
data class VerificationStatus(
    /** Whether the server asks for confirmation at all. */
    val enabled: Boolean = false,
    val email: Channel = Channel(),
    val phone: Channel = Channel(),
    /** Starting a club or accepting an invite is refused until one is verified. */
    @SerialName("verification_required") val verificationRequired: Boolean = false,
) {
    @Serializable
    data class Channel(
        val address: String? = null,
        val verified: Boolean = false,
        /** The server has the address and a sender configured for it. */
        val available: Boolean = false,
    )

    operator fun get(channel: VerificationChannel): Channel =
        if (channel == VerificationChannel.Email) email else phone

    /** The ways a code can actually be sent, email first. */
    val channels: List<VerificationChannel> get() = VerificationChannel.entries.filter { this[it].available }

    /** A step worth showing: the server asks, and can send a code. */
    val canVerify: Boolean get() = enabled && channels.isNotEmpty()
}

enum class VerificationChannel(val wire: String) {
    Email("email"),
    Phone("phone"),
    ;

    /** "Confirm your {noun}". */
    val noun: String get() = if (this == Email) t("pf.email_word") else t("rest.phone_number_word")

    /** How the code travels, for the sentence under the field. */
    val sentVerb: String get() = if (this == Email) t("le.emailed") else t("le.sent_on_whatsapp")

    val tabLabel: String get() = if (this == Email) t("rest.email") else t("rest.phone")
}

/** `POST /me/verification/{channel}`. */
@Serializable
data class VerificationSent(
    /** Masked, so a screenshot does not leak the address. */
    @SerialName("sent_to") val sentTo: String,
    @SerialName("resend_after") val resendAfter: Int = 60,
)

@Serializable
data class VerificationCode(val code: String)

/** An invitation addressed to this account, from `GET /invites/mine`. */
@Serializable
data class PendingInvite(
    val id: String,
    @SerialName("target_type") val targetType: String,
    @SerialName("target_id") val targetId: String,
    val token: String,
    val status: String,
    @SerialName("created_at") val createdAt: String,
    /** The club, "team · club", or fixture — present on your own invites. */
    @SerialName("target_name") val targetName: String? = null,
    @SerialName("invited_by_name") val invitedByName: String? = null,
) {
    val isPending: Boolean get() = status == "pending"
    val isFixture: Boolean get() = targetType == "event"

    val title: String
        get() = targetName ?: when (targetType) {
            "event" -> t("pf.invite_fixture")
            "team" -> t("pf.invite_team")
            else -> t("pf.invite_club")
        }
}

/** `POST /me/share-link`. */
@Serializable
data class ShareLinkToken(val token: String)

/** `GET /sports` — what this deployment's pickers offer. */
@Serializable
data class SportsOnOffer(
    val offered: List<String> = emptyList(),
    val all: List<String> = emptyList(),
)

package com.fishers.app.payments

/**
 * Where a tapped payments notification opens — §11 "Notifications".
 *
 * Routed by the payload, as the doc says: an `event_id` opens that event, whose
 * page has the money section (and "who came?"); otherwise a `club_id` opens the
 * money overview, which sends anybody who is not a money admin on to the pay
 * screen. FCM's data carries the payload's keys but not the kind today, so the
 * kind is used only when it is there.
 *
 * Every field is read as an optional string: an unknown kind, or a payload
 * with nothing this understands, opens nothing rather than crashing.
 */
sealed interface MoneyLink {
    data class Event(val eventId: String) : MoneyLink
    data class Pay(val clubId: String) : MoneyLink
    /** The treasurer's page, or the pay screen for anybody it is not for. */
    data class ClubMoney(val clubId: String) : MoneyLink

    companion object {
        /** What the payer is told about: their own money, so their pay screen. */
        private val PAYER_KINDS = setOf(
            "fee_reminder", "payment_confirmed", "payment_rejected",
            // Passes and group fees: about the person's own pass or dues
            // (or those of somebody they pay for), so the pay screen.
            "pass_started", "pass_charge", "pass_behind", "pass_cancelled", "pass_price_changed",
            "pass_sessions_left", "pass_bank_changed", "collection_issued",
            // Your own pass paused; somebody said they paid for you.
            "pass_suspended", "paid_for_you",
        )

        private val ADMIN_KINDS = setOf(
            "payment_claimed", "payments_to_check", "payout_details_changed", "payout_details_frozen",
            // Somebody's pass paused: the money admins are told, to the overview.
            "pass_suspended_club",
        )

        fun fromPush(kind: String?, eventId: String?, clubId: String?): MoneyLink? {
            val event = eventId?.trim()?.takeIf { it.isNotEmpty() }
            val club = clubId?.trim()?.takeIf { it.isNotEmpty() }
            return when {
                // Any event's notification opens the event: for a bill that is
                // where the money is, and for anything else it is still right.
                event != null -> Event(event)
                club == null -> null
                kind in PAYER_KINDS -> Pay(club)
                kind == null || kind in ADMIN_KINDS -> ClubMoney(club)
                // Some other club notification this version does not know.
                else -> null
            }
        }
    }
}

package com.fishers.app.fixtures

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** `backend/domain/src/enums.rs` — snake_case on the wire. */
@Serializable
enum class EventStatus {
    @SerialName("draft") Draft,
    @SerialName("scheduled") Scheduled,
    @SerialName("postponed") Postponed,
    @SerialName("cancelled") Cancelled,
    @SerialName("completed") Completed,
}

@Serializable
enum class EventSubtype {
    @SerialName("nets") Nets,
    @SerialName("friendly") Friendly,
    @SerialName("league_match") LeagueMatch,
    @SerialName("tournament") Tournament,
    @SerialName("social") Social,
    @SerialName("training") Training,
    @SerialName("generic") Generic;

    val label: String
        get() = when (this) {
            Nets -> "Nets"
            Friendly -> "Friendly"
            LeagueMatch -> "League"
            Tournament -> "Tournament"
            Social -> "Social"
            Training -> "Training"
            Generic -> "Event"
        }
}

@Serializable
enum class RsvpStatus {
    @SerialName("going") Going,
    @SerialName("not_going") NotGoing,
    @SerialName("maybe") Maybe,
    @SerialName("invited") Invited;

    val label: String
        get() = when (this) {
            Going -> "Going"
            NotGoing -> "Can't"
            Maybe -> "Maybe"
            Invited -> "Asked"
        }
}

@Serializable
data class RsvpRequest(val status: RsvpStatus)

@Serializable
data class FishersEvent(
    val id: String,
    @SerialName("club_id") val clubId: String,
    val title: String,
    @SerialName("event_subtype") val subtype: EventSubtype = EventSubtype.Generic,
    val status: EventStatus = EventStatus.Scheduled,
    @SerialName("start_at") val startAt: String,
    @SerialName("end_at") val endAt: String? = null,
    @SerialName("venue_id") val venueId: String? = null,
    /** "Called off — ground unplayable after Friday's rain." */
    @SerialName("status_note") val statusNote: String? = null,
    @SerialName("rescheduled_to") val rescheduledTo: String? = null,
    @SerialName("fee_amount_cents") val feeAmountCents: Int? = null,
    @SerialName("ticket_price_cents") val ticketPriceCents: Int? = null,
    /** This viewer's answer, when the server sends one with the fixture. */
    @SerialName("my_rsvp") val myRsvp: RsvpStatus? = null,
) {
    val startsAt: Instant? get() = runCatching { Instant.parse(startAt) }.getOrNull()

    /**
     * Whether it is still ahead. A fixture with an unreadable date is treated
     * as upcoming rather than hidden: a captain would rather see a fixture with
     * a wrong-looking date than not see it at all.
     */
    fun isUpcoming(now: Instant = Instant.now()): Boolean =
        startsAt?.let { it >= now } ?: true

    /**
     * Called off, and the app must say so loudly. A cancelled fixture that
     * looks like any other is how a side turns up to an empty ground.
     */
    val isOff: Boolean
        get() = status == EventStatus.Cancelled || status == EventStatus.Postponed
}

/** "Sat 27 Sep, 13:30" — short, and in the reader's own time zone. */
fun formatWhen(iso: String, zone: ZoneId = ZoneId.systemDefault()): String =
    runCatching {
        DateTimeFormatter
            .ofPattern("EEE d MMM, HH:mm", Locale.getDefault())
            .withZone(zone)
            .format(Instant.parse(iso))
    }.getOrDefault(iso)

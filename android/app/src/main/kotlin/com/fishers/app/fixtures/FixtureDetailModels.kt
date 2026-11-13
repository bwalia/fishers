package com.fishers.app.fixtures

import com.fishers.app.i18n.t
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// The shapes behind making a fixture and reading one, from
// `backend/api/src/routes/events.rs`, `clubs.rs` and `cricket.rs`. Named as the
// wire names them.

/**
 * `GET /clubs/{id}/my-role` — what this person may do in one club.
 *
 * The server sends the role's permissions as plain names; asking for one by
 * name is what the website and the iPhone do, so all three agree on who may
 * schedule a match.
 */
@Serializable
data class ClubRole(
    val role: String? = null,
    val permissions: List<String> = emptyList(),
    @SerialName("is_secretary") val isSecretary: Boolean = false,
    @SerialName("is_captain") val isCaptain: Boolean = false,
    @SerialName("can_score_match") val canScoreFlag: Boolean? = null,
) {
    /** Put a fixture in the club's diary. */
    val canManageEvents: Boolean get() = "manage_events" in permissions

    /** Pick the side, and call a fixture off — the server checks the same permission for both. */
    val canSelect: Boolean get() = "manage_selection" in permissions

    /** Save a new ground. A captain may schedule a match without being allowed to do this. */
    val canAddGround: Boolean get() = "manage_club_ops" in permissions

    val canScore: Boolean get() = canScoreFlag ?: ("score_match" in permissions)
}

/** A club's ground. */
@Serializable
data class Venue(
    val id: String,
    @SerialName("club_id") val clubId: String,
    val name: String,
    val address: String? = null,
)

@Serializable
data class NewVenue(val name: String, val address: String? = null)

/**
 * The other side, found by name — `GET /opponents/search`. A club, or one of
 * its teams. Thin on purpose: who you are playing and nothing else.
 */
@Serializable
data class Opponent(
    val id: String,
    val name: String,
    /** `club` or `team`. */
    val kind: String = "club",
    @SerialName("club_id") val clubId: String,
    @SerialName("club_name") val clubName: String = "",
    val sport: String? = null,
) {
    /** "Hemel Hempstead CC — 2nd XI" for a team, just the club otherwise. */
    val displayName: String
        get() = if (kind == "team" && clubName.isNotEmpty() && clubName != name) "$clubName — $name" else name
}

/**
 * `POST /events`. Absent fields are left out of the JSON rather than sent as
 * null (`explicitNulls = false`), which the server reads the same way.
 */
@Serializable
data class CreateEventBody(
    @SerialName("club_id") val clubId: String,
    @SerialName("opponent_club_id") val opponentClubId: String? = null,
    @SerialName("team_id") val teamId: String? = null,
    val sport: String,
    @SerialName("event_subtype") val subtype: EventSubtype,
    val title: String,
    @SerialName("venue_id") val venueId: String? = null,
    @SerialName("start_at") val startAt: String,
    @SerialName("end_at") val endAt: String,
)

@Serializable
enum class AvailabilityStatus {
    @SerialName("available") Available,
    @SerialName("unavailable") Unavailable,
    @SerialName("maybe") Maybe;

    val label: String
        get() = when (this) {
            Available -> t("av.available")
            Unavailable -> t("ld.unavailable_label")
            Maybe -> t("ev.maybe")
        }
}

/** One person asked about a fixture, and what they said. `GET /events/{id}/attendees`. */
@Serializable
data class Attendee(
    @SerialName("user_id") val userId: String,
    val name: String,
    val status: RsvpStatus = RsvpStatus.Invited,
    /** Their standing calendar for the day, which is a weaker signal than [status]. */
    val availability: AvailabilityStatus? = null,
    val paid: Boolean = false,
    /** Which side they are on: a fixture asks both clubs. */
    @SerialName("club_id") val clubId: String? = null,
    @SerialName("club_name") val clubName: String? = null,
)

/** `POST /events/{id}/status` — rain stops play. */
@Serializable
data class FixtureStatusBody(
    /** `scheduled`, `postponed` or `cancelled`. */
    val status: String,
    val note: String? = null,
)

/**
 * The scorebook on a fixture, `GET /events/{id}/cricket-match`. Only what this
 * page decides with: whether there is one, how far it has got, and whether
 * this person may write in it.
 */
@Serializable
data class FixtureMatch(
    val id: String,
    @SerialName("event_id") val eventId: String,
    /** `scheduled` … `live`, `innings_break`, `complete`, `published`. */
    val status: String,
    @SerialName("home_name") val homeName: String = "",
    @SerialName("away_name") val awayName: String = "",
    @SerialName("can_score") val canScore: Boolean = false,
)

/** `GET /availability` — one day of your standing calendar. */
@Serializable
data class DayAvailability(
    /** `2026-09-27` — a calendar day, not an instant. */
    val date: String,
    val status: AvailabilityStatus,
)

@Serializable
data class SetDayAvailability(val date: String, val status: AvailabilityStatus)

@Serializable
data class SetDaysAvailability(val dates: List<String>, val status: AvailabilityStatus)

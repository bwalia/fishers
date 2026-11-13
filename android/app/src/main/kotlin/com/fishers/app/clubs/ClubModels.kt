package com.fishers.app.clubs

import com.fishers.app.i18n.Strings
import com.fishers.app.i18n.t
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** `backend/domain/src/enums.rs`. Unknown values are not a crash — see below. */
@Serializable
enum class UserRole {
    @SerialName("super_admin") SuperAdmin,
    @SerialName("club_admin") ClubAdmin,
    @SerialName("team_captain") TeamCaptain,
    @SerialName("team_vice_captain") TeamViceCaptain,
    @SerialName("member") Member,
    @SerialName("guest") Guest;

    /** What a club calls it, not what the database does. */
    val label: String
        get() = when (this) {
            SuperAdmin -> t("rest.admin")
            ClubAdmin -> t("cl.secretary")
            TeamCaptain -> t("sc.captain")
            TeamViceCaptain -> t("cl.vice_captain")
            Member -> t("lb.member")
            Guest -> t("rest.guest")
        }

    /** The role in full, as the role sheet and the roster headings say it. `RBAC.swift`'s `displayName`. */
    val displayName: String
        get() = when (this) {
            SuperAdmin -> t("rest.super_admin")
            ClubAdmin -> t("cl.club_secretary_role")
            TeamCaptain -> t("cl.team_captain")
            TeamViceCaptain -> t("cl.vice_captain")
            Member -> t("lb.member")
            Guest -> t("rest.guest")
        }

    /** What the role lets somebody do, in the words the app uses. */
    val responsibilities: String
        get() = when (this) {
            SuperAdmin -> t("rest.platform_administration")
            ClubAdmin -> t("cl.everything_the_roster_roles")
            TeamCaptain -> t("cl.create_fixtures_invite_pick")
            TeamViceCaptain -> t("cl.help_with_selection")
            Member -> t("cl.mark_availability_rsvp_chat")
            Guest -> t("cl.same_as_member_one_off")
        }

    /** Whether they can do secretary things — invite, edit, pick sides. */
    val runsTheClub: Boolean get() = this == ClubAdmin || this == SuperAdmin

    companion object {
        /** The order the roster groups people in, strongest first. */
        val rosterOrder = listOf(SuperAdmin, ClubAdmin, TeamCaptain, TeamViceCaptain, Member, Guest)
    }
}

/**
 * A role as the picker offers it: the roles, plus a secretary who captains —
 * usual in a small club, and the one choice the bare enum cannot say.
 */
class RoleChoice(val role: UserRole, isCaptain: Boolean = false) {
    /** Only a secretary carries the flag; a captain is a captain by role. */
    val captains: Boolean = role.runsTheClub && isCaptain

    val label: String
        get() = if (captains) t("cl.secretary_and_captain") else role.displayName

    /** For a badge. */
    val shortLabel: String
        get() = if (captains) t("cl.sec_and_captain_badge") else when (role) {
            UserRole.SuperAdmin -> t("cl.admin_badge")
            UserRole.ClubAdmin -> t("cl.sec_badge")
            UserRole.TeamCaptain -> t("cl.capt_badge")
            UserRole.TeamViceCaptain -> t("cl.vice_badge")
            UserRole.Member -> t("cl.member_badge")
            UserRole.Guest -> t("cl.guest_badge")
        }

    val responsibilities: String
        get() = if (captains) t("cl.secretary_who_also_captains") else role.responsibilities

    /** What `PATCH /clubs/{id}/members/{user}` is sent. */
    val body: RoleBody get() = RoleBody(role = role.wireName, captain = captains)

    override fun equals(other: Any?): Boolean =
        other is RoleChoice && other.role == role && other.captains == captains

    override fun hashCode(): Int = role.hashCode() * 31 + captains.hashCode()

    override fun toString(): String = "RoleChoice(${role.wireName}${if (captains) "+captain" else ""})"

    companion object {
        /** Every choice a secretary can make, strongest first. Never super admin: the server refuses it. */
        val appointable: List<RoleChoice> = listOf(
            RoleChoice(UserRole.ClubAdmin, isCaptain = true),
            RoleChoice(UserRole.ClubAdmin),
            RoleChoice(UserRole.TeamCaptain),
            RoleChoice(UserRole.TeamViceCaptain),
            RoleChoice(UserRole.Member),
            RoleChoice(UserRole.Guest),
        )
    }
}

/** The spelling the API takes. */
val UserRole.wireName: String
    get() = when (this) {
        UserRole.SuperAdmin -> "super_admin"
        UserRole.ClubAdmin -> "club_admin"
        UserRole.TeamCaptain -> "team_captain"
        UserRole.TeamViceCaptain -> "team_vice_captain"
        UserRole.Member -> "member"
        UserRole.Guest -> "guest"
    }

@Serializable
enum class MembershipStatus {
    @SerialName("active") Active,
    @SerialName("invited") Invited,
    @SerialName("suspended") Suspended,
    @SerialName("left") Left,
}

/**
 * A club. `GET /clubs` sends each one with what the asker is in it — role,
 * captaincy and the counts the list shows. `POST /clubs` and `GET /clubs/{id}`
 * send the club alone, so those fields are optional.
 */
@Serializable
data class Club(
    val id: String,
    val name: String,
    @SerialName("sport_types") val sportTypes: List<String> = emptyList(),
    val description: String? = null,
    @SerialName("is_informal_group") val isInformalGroup: Boolean = false,
    /** `public` or `invite_only`. */
    val visibility: String? = null,
    val role: UserRole? = null,
    @SerialName("is_captain") val isCaptain: Boolean = false,
    @SerialName("member_count") val memberCount: Int? = null,
    @SerialName("team_count") val teamCount: Int? = null,
    /** The public page's address, only once the club has switched it on. */
    @SerialName("public_slug") val publicSlug: String? = null,
) {
    val isPublic: Boolean get() = visibility == "public"
    val playsCricket: Boolean get() = sportTypes.any { it.equals("cricket", ignoreCase = true) }

    /** "Secretary & captain", "Team captain"… — what you are in it, for the row. */
    val roleLabel: String? get() = role?.let { RoleChoice(it, isCaptain).label }
}

@Serializable
data class ClubMemberDetail(
    @SerialName("user_id") val userId: String,
    val name: String,
    /** Absent for anyone who registered with a mobile number instead. */
    val email: String? = null,
    val phone: String? = null,
    val role: UserRole = UserRole.Member,
    /** Captains the side — by role, or as a secretary who captains too. */
    @SerialName("is_captain") val isCaptain: Boolean = false,
    val status: MembershipStatus = MembershipStatus.Active,
    @SerialName("position_role") val positionRole: String? = null,
    @SerialName("skill_level") val skillLevel: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
) {
    /**
     * Somebody who was asked and has not answered is not in the side yet, and
     * a roster that counts them is a roster that is wrong on a Saturday.
     */
    val isOnTheBooks: Boolean get() = status == MembershipStatus.Active

    val roleChoice: RoleChoice get() = RoleChoice(role, isCaptain)

    /** Whichever way this member can actually be reached. */
    val contact: String get() = email ?: phone ?: t("cl.no_contact_details_short")

    /** "Batter · Club standard" under the name. */
    val subtitle: String get() = listOfNotNull(positionRole, skillLevel).joinToString(" · ")
}

/**
 * The club's open link: addressed to nobody, never used up, good for everyone
 * who follows it until the secretary turns it off. `uses` counts who has
 * joined through it.
 */
@Serializable
data class ClubJoinLink(val token: String, val uses: Int = 0)

@Serializable
data class MakeJoinLink(val fresh: Boolean)

@Serializable
data class Team(
    val id: String,
    @SerialName("club_id") val clubId: String,
    val name: String,
    val sport: String? = null,
)

// ---- what `GET /clubs/{id}/my-role` says ----

/**
 * What this person may do in one club. The page decides its buttons from the
 * permissions rather than the role, because that is what the server checks.
 */
@Serializable
data class ClubRoleInfo(
    val role: UserRole = UserRole.Member,
    @SerialName("is_secretary") val isSecretary: Boolean = false,
    @SerialName("is_captain") val isCaptain: Boolean = false,
    @SerialName("can_score_match") val canScoreMatch: Boolean = false,
    val permissions: List<String> = emptyList(),
) {
    /** Teams, grounds, the policy — what `require_club_permission(ManageClubOps)` guards. */
    val runsClubOps: Boolean get() = "manage_club_ops" in permissions
    /** Fixtures: what `POST /events` is refused without. */
    val managesEvents: Boolean get() = "manage_events" in permissions
    val invitesToClub: Boolean get() = "invite_to_club" in permissions
    val scores: Boolean get() = canScoreMatch || "score_match" in permissions
}

// ---- starting one ----

/** `POST /clubs`. Sports are the API's `SportType` spellings. */
@Serializable
data class CreateClubBody(
    val name: String,
    @SerialName("sport_types") val sportTypes: List<String>,
    /** `invite_only` or `public`. */
    val visibility: String,
    val description: String? = null,
    @SerialName("is_informal_group") val isInformalGroup: Boolean = false,
)

/** `GET /sports`: what a new club may be started in here, and every name a sport can have. */
@Serializable
data class OfferedSports(
    val offered: List<String> = emptyList(),
    val all: List<String> = emptyList(),
)

/** Exactly what the API's `SportType` accepts — anything else is refused. */
val ALL_SPORTS = listOf("cricket", "football", "badminton", "paddle", "pickleball", "tennis", "other")

/** A sport as a person reads it. Cricket has a translation; the rest are names. */
fun sportLabel(sport: String): String =
    if (sport.equals("cricket", ignoreCase = true)) t("rest.cricket")
    else sport.replaceFirstChar { it.titlecase(Locale.ROOT) }

// ---- teams and grounds ----

@Serializable
data class CreateTeamBody(val name: String, val sport: String)

/** One person in a team, from `GET /teams/{id}/members`. */
@Serializable
data class TeamMemberRow(
    @SerialName("user_id") val userId: String,
    val name: String,
    val role: UserRole = UserRole.Member,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("position_role") val positionRole: String? = null,
)

/** Where a club plays. */
@Serializable
data class Venue(
    val id: String,
    val name: String,
    val address: String? = null,
)

@Serializable
data class CreateVenueBody(val name: String, val address: String? = null)

/**
 * One of the club's fixtures, as the club page lists it. Only what the row
 * shows: the fixtures area has the event in full.
 */
@Serializable
data class ClubFixture(
    val id: String,
    val title: String,
    @SerialName("start_at") val startAt: String,
    val status: String? = null,
    @SerialName("event_subtype") val subtype: String? = null,
) {
    /** "Sat 27 Sep, 13:30", in the reader's time zone and the app's language. */
    fun whenText(zone: ZoneId = ZoneId.systemDefault()): String =
        runCatching {
            DateTimeFormatter.ofPattern("EEE d MMM, HH:mm", Locale.forLanguageTag(Strings.language.code))
                .withZone(zone)
                .format(Instant.parse(startAt))
        }.getOrDefault(startAt)

    /** Called off or moved: the row must say so, not look like any other. */
    val isOff: Boolean get() = status == "cancelled" || status == "postponed"
}

/** `GET /events` pages; the page is all the club page reads. */
@Serializable
data class ClubFixturePage(
    val items: List<ClubFixture> = emptyList(),
    @SerialName("has_more") val hasMore: Boolean = false,
)

// ---- the roster ----

/** `POST /clubs/{id}/members`: an email address or a mobile number, and the role to start in. */
@Serializable
data class AddMemberBody(val identifier: String, val role: String)

/** `PATCH /clubs/{id}/members/{user}`. `captain` means something only for a secretary. */
@Serializable
data class RoleBody(val role: String, val captain: Boolean)

// ---- invites ----

/** `POST /invites` for a club. Left without an address, the link is anybody's who opens it first. */
@Serializable
data class CreateInviteBody(
    @SerialName("target_type") val targetType: String = "club",
    @SerialName("target_id") val targetId: String,
    @SerialName("invited_email") val invitedEmail: String? = null,
)

/** An invite as the API answers with it: what it is to, and the token that makes the link. */
@Serializable
data class ClubInvite(
    val id: String,
    @SerialName("target_type") val targetType: String,
    @SerialName("target_id") val targetId: String,
    val token: String,
    val status: String? = null,
    val open: Boolean = false,
    val uses: Int = 0,
)

/**
 * What a link is to, before anybody signs in — enough to say "Join Southall
 * Strikers" rather than "You have been invited", and to say a dead link is
 * dead before somebody bothers.
 */
@Serializable
data class InvitePreview(
    @SerialName("target_type") val targetType: String,
    @SerialName("target_id") val targetId: String,
    /** The club it leads into: the club itself, a team's club, or a fixture's. */
    @SerialName("club_id") val clubId: String? = null,
    @SerialName("club_name") val clubName: String? = null,
    @SerialName("team_name") val teamName: String? = null,
    @SerialName("event_title") val eventTitle: String? = null,
    @SerialName("invited_by_name") val invitedByName: String? = null,
    /** The club's open link rather than one made for a person. */
    val open: Boolean = false,
    /** False once a one-use invite is spent or the open link is turned off. */
    val usable: Boolean = true,
) {
    /** "1st XI · Southall Strikers", or the club alone. */
    val joining: String?
        get() = clubName?.let { club -> teamName?.let { "$it · $club" } ?: club }
}

/** `POST /me/share-link`. */
@Serializable
data class ProfileShareLink(val token: String)

// ---- policy and fees ----

/** The knobs a secretary can turn. */
@Serializable
data class ClubSettings(
    /** `off`, `suggest` or `auto_publish`. */
    @SerialName("selection_autonomy") val selectionAutonomy: String = "suggest",
    @SerialName("confirm_lead_hours") val confirmLeadHours: Int = 0,
    @SerialName("drop_lead_hours") val dropLeadHours: Int = 0,
    @SerialName("fee_chase_after_hours") val feeChaseAfterHours: Int = 0,
    @SerialName("fee_chase_max_reminders") val feeChaseMaxReminders: Int = 0,
)

@Serializable
data class OutstandingFee(
    @SerialName("user_id") val userId: String,
    val name: String,
    @SerialName("event_id") val eventId: String,
    val fixture: String,
    @SerialName("start_at") val startAt: String,
    @SerialName("amount_cents") val amountCents: Int? = null,
    val currency: String? = null,
    @SerialName("reminders_sent") val remindersSent: Int = 0,
)

@Serializable
data class OutstandingFees(
    @SerialName("total_cents") val totalCents: Long = 0,
    val count: Int = 0,
    val owed: List<OutstandingFee> = emptyList(),
)

/** "£12.50" or "₹600.00" — a fee in its own currency, not always pounds. */
fun money(cents: Long, currency: String?): String {
    val format = java.text.NumberFormat.getCurrencyInstance(Locale.UK)
    runCatching { format.currency = java.util.Currency.getInstance(currency ?: "GBP") }
    return format.format(cents / 100.0)
}

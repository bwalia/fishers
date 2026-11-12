package com.fishers.app.clubs

import com.fishers.app.i18n.t
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

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

    /** Whether they can do secretary things — invite, edit, pick sides. */
    val runsTheClub: Boolean get() = this == ClubAdmin || this == SuperAdmin
}

@Serializable
enum class MembershipStatus {
    @SerialName("active") Active,
    @SerialName("invited") Invited,
    @SerialName("suspended") Suspended,
    @SerialName("left") Left,
}

@Serializable
data class Club(
    val id: String,
    val name: String,
    @SerialName("sport_types") val sportTypes: List<String> = emptyList(),
    val description: String? = null,
    @SerialName("is_informal_group") val isInformalGroup: Boolean = false,
)

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
) {
    /**
     * Somebody who was asked and has not answered is not in the side yet, and
     * a roster that counts them is a roster that is wrong on a Saturday.
     */
    val isOnTheBooks: Boolean get() = status == MembershipStatus.Active
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

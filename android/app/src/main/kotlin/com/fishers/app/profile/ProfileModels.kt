package com.fishers.app.profile

import com.fishers.app.i18n.t
import com.fishers.app.net.PublicUser
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * The signed-in person, all of it — `PublicUser` in `Models.swift`.
 *
 * [com.fishers.app.net.PublicUser] carries the six fields signing in needs and
 * is what the rest of the app holds; this is what a profile page reads. A save
 * hands the short form back through [toPublicUser].
 */
@Serializable
data class Me(
    val id: String,
    val name: String,
    /** Absent for somebody who registered with a mobile number instead. */
    val email: String? = null,
    val phone: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("emergency_contact") val emergencyContact: String? = null,
    /** The sport they lead with — the rest of the profile hangs off it. */
    @SerialName("primary_sport") val primarySport: String? = null,
    @SerialName("sport_profiles") val sportProfiles: List<SportProfile> = emptyList(),
    val location: PlayerLocation? = null,
    @SerialName("email_verified") val emailVerified: Boolean = false,
    @SerialName("phone_verified") val phoneVerified: Boolean = false,
    /** "secretary" or "player"; absent until they have been asked. */
    @SerialName("role_intent") val roleIntent: String? = null,
    /** Worked out by the server from attendance and payments; never sent back. */
    val reliability: ReliabilityScore? = null,
) {
    /** Starting a club and accepting an invite wait on one of these. */
    val isVerified: Boolean get() = emailVerified || phoneVerified

    val primaryProfile: SportProfile?
        get() = sportProfiles.firstOrNull { it.sport == primarySport } ?: sportProfiles.firstOrNull()

    fun toPublicUser() = PublicUser(
        id = id, name = name, email = email, phone = phone,
        avatarUrl = avatarUrl, roleIntent = roleIntent,
    )
}

/** One sport a player takes part in, with the level, league and stats they keep for it. */
@Serializable
data class SportProfile(
    val sport: String,
    val position: String? = null,
    @SerialName("skill_level") val skillLevel: String? = null,
    @SerialName("current_division") val currentDivision: String? = null,
    @SerialName("target_division") val targetDivision: String? = null,
    @SerialName("age_group") val ageGroup: String? = null,
    @SerialName("team_name") val teamName: String? = null,
    @SerialName("years_playing") val yearsPlaying: Int? = null,
    /** Strings, keyed by the catalog's field key — one JSONB column per sport server-side. */
    val stats: Map<String, String> = emptyMap(),
) {
    val sportKind: Sport? get() = Sport.named(sport)
    val tier: SkillTier? get() = SkillTier.stored(skillLevel)
    val division: Division? get() = Division.stored(currentDivision)
    val target: Division? get() = Division.stored(targetDivision)
    val ageBand: AgeGroup? get() = AgeGroup.stored(ageGroup)
}

/** Where the player is based and how they travel — drives away-game lift sharing. */
@Serializable
data class PlayerLocation(
    val area: String? = null,
    val postcode: String? = null,
    @SerialName("travel_radius_miles") val travelRadiusMiles: Int? = null,
    /** `driverWithSeats` | `driver` | `publicTransport` | `needsLift`. */
    val transport: String? = null,
    @SerialName("spare_seats") val spareSeats: Int? = null,
    /** Calendar weekday numbers, 1 = Sunday. */
    @SerialName("preferred_days") val preferredDays: List<Int>? = null,
    val notes: String? = null,
) {
    val transportMode: TransportMode? get() = TransportMode.entries.firstOrNull { it.wire == transport }

    val summary: String?
        get() = listOfNotNull(area, postcode).filter { it.isNotBlank() }
            .takeIf { it.isNotEmpty() }?.joinToString(" · ")

    val isEmpty: Boolean
        get() = area.isNullOrBlank() && postcode.isNullOrBlank() && travelRadiusMiles == null &&
            transport == null && preferredDays.isNullOrEmpty() && notes.isNullOrBlank()
}

@Serializable
data class ReliabilityScore(
    val score: Int = 0,
    @SerialName("attendance_rate") val attendanceRate: Double = 0.0,
    @SerialName("response_rate") val responseRate: Double = 0.0,
    @SerialName("payment_rate") val paymentRate: Double = 0.0,
    @SerialName("late_cancellations") val lateCancellations: Int = 0,
    @SerialName("sample_size") val sampleSize: Int = 0,
    /** `unproven` | `patchy` | `dependable` | `rock_solid`. */
    val band: String = "unproven",
) {
    val isUnproven: Boolean get() = band == "unproven"

    val bandLabel: String
        get() = when (band) {
            "patchy" -> t("sp.patchy")
            "dependable" -> t("sp.dependable")
            "rock_solid" -> t("sp.rock_solid")
            else -> t("sp.unproven")
        }

    val bandBlurb: String
        get() = when (band) {
            "patchy" -> t("sp.drops_out_late")
            "dependable" -> t("sp.turns_up_when_they_say")
            "rock_solid" -> t("sp.answers_early_shows_up")
            else -> t("sp.not_enough_games_to_score")
        }

    companion object {
        /** Games before a score means anything — `ReliabilityScore.minimumSample`. */
        const val MINIMUM_SAMPLE = 3
    }
}

/**
 * Body of `PATCH /me` — `ProfileUpdate` in `PlayerProfile.swift`.
 *
 * The client submits the whole profile it holds; the flat `position_role` and
 * `skill_level` mirror the primary sport for list views. Nothing here has a
 * default value on purpose: the JSON is written with `encodeDefaults` off, and
 * a list that happened to equal its default — every sport deselected — would
 * not be sent at all, so the server would keep the old ones. A null is left
 * out instead (`explicitNulls = false`), which the server reads as "unchanged",
 * the same as the iPhone app's encoder.
 */
@Serializable
data class ProfileUpdate(
    val name: String,
    val phone: String?,
    @SerialName("emergency_contact") val emergencyContact: String?,
    @SerialName("primary_sport") val primarySport: String?,
    @SerialName("sports_played") val sportsPlayed: List<String>,
    @SerialName("position_role") val positionRole: String?,
    @SerialName("skill_level") val skillLevel: String?,
    @SerialName("sport_profiles") val sportProfiles: List<SportProfile>,
    val location: PlayerLocation?,
) {
    companion object {
        /** Mirrors the Swift initialiser: the flat fields follow the primary sport. */
        fun of(
            name: String,
            sportProfiles: List<SportProfile>,
            primarySport: String?,
            phone: String? = null,
            emergencyContact: String? = null,
            location: PlayerLocation? = null,
        ): ProfileUpdate {
            val primary = sportProfiles.firstOrNull { it.sport == primarySport } ?: sportProfiles.firstOrNull()
            return ProfileUpdate(
                name = name,
                phone = phone,
                emergencyContact = emergencyContact,
                primarySport = primarySport,
                sportsPlayed = sportProfiles.map { it.sport },
                positionRole = primary?.position,
                skillLevel = primary?.skillLevel,
                sportProfiles = sportProfiles,
                location = location,
            )
        }
    }
}

/** Trimmed, or null when nothing is left — keeps blank fields out of a payload. */
internal fun String?.nonEmpty(): String? = this?.trim()?.takeIf { it.isNotEmpty() }

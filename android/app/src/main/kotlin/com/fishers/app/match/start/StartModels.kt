package com.fishers.app.match.start

import com.fishers.app.cricket.ScoringEvent
import com.fishers.app.i18n.t
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

// The wire shapes behind starting a match, named as the server names them —
// `backend/api/src/routes/cricket.rs`, `events.rs`, `clubs.rs`. The app's JSON
// does not encode defaults, so a request body below declares none: a field
// with a default that happens to equal it is a field that never leaves.

// MARK: The hub

/** `CricketFixtureRow` in `Tournament.swift`: a fixture with its match joined on. */
@Serializable
data class FixtureRow(
    @SerialName("event_id") val eventId: String,
    @SerialName("club_id") val clubId: String,
    val title: String,
    @SerialName("start_at") val startAt: String,
    @SerialName("event_status") val eventStatus: String = "scheduled",
    /** Absent until a match is set up on the fixture. */
    @SerialName("match_id") val matchId: String? = null,
    @SerialName("match_status") val matchStatus: String? = null,
    @SerialName("home_name") val homeName: String? = null,
    @SerialName("away_name") val awayName: String? = null,
    /** Somebody is holding the book — not necessarily you. */
    @SerialName("has_scorer") val hasScorer: Boolean = false,
    /** "128/4 (14.2 ov)", formatted by the server. */
    val score: String? = null,
    val result: String? = null,
) {
    /** "London Lords v Watford", or the fixture's own title before a match names the sides. */
    val sides: String
        get() = if (homeName != null && awayName != null) "$homeName v $awayName" else title

    val stage: Stage get() = Stage.of(matchStatus)

    /** How far a match has got, as the hub sorts it. */
    enum class Stage {
        /** No match yet. */
        NotStarted,
        /** Terms, toss or team sheets — set up but no ball bowled. */
        SettingUp,
        Live,
        Finished;

        companion object {
            fun of(status: String?): Stage = when (status) {
                null, "scheduled" -> NotStarted
                "live", "innings_break" -> Live
                "complete", "published" -> Finished
                else -> SettingUp
            }
        }
    }
}

@Serializable
data class FixturePage(
    val items: List<FixtureRow> = emptyList(),
    val total: Int = 0,
    val page: Int = 1,
    @SerialName("per_page") val perPage: Int = 20,
    @SerialName("has_more") val hasMore: Boolean = false,
)

// MARK: The quick start

/** `POST /clubs`. Informal: a side that turned up is not a club with a committee. */
@Serializable
data class NewClub(
    val name: String,
    @SerialName("sport_types") val sportTypes: List<String>,
    @SerialName("is_informal_group") val isInformalGroup: Boolean,
    val visibility: String,
)

/** `CreateEventBody` in `FishersAPI.swift`. */
@Serializable
data class NewFixture(
    @SerialName("club_id") val clubId: String,
    @SerialName("opponent_club_id") val opponentClubId: String?,
    @SerialName("team_id") val teamId: String?,
    val sport: String,
    @SerialName("event_subtype") val eventSubtype: String,
    val title: String,
    @SerialName("start_at") val startAt: String,
    @SerialName("end_at") val endAt: String,
    val capacity: Int,
    val metadata: Map<String, String>,
)

/** The fixture `POST /events` made — its id is all the wizard needs. */
@Serializable
data class CreatedFixture(
    val id: String,
    @SerialName("club_id") val clubId: String,
    val title: String = "",
)

/** `GET /events/{id}`, for the names and the sides. */
@Serializable
data class FixtureInfo(
    val id: String,
    @SerialName("club_id") val clubId: String,
    val title: String = "",
    @SerialName("team_id") val teamId: String? = null,
    @SerialName("opponent_club_id") val opponentClubId: String? = null,
    val metadata: JsonElement? = null,
) {
    /** The phone's own id for a fixture it made — how it knows the fixture again. */
    val clientRef: String?
        get() = runCatching { (metadata?.jsonObject?.get(CLIENT_REF) as? JsonPrimitive)?.content }.getOrNull()

    companion object {
        /** The metadata key a quick start writes the phone's id for its fixture under. */
        const val CLIENT_REF = "client_ref"
    }
}

/** `GET /events`, a page of them. */
@Serializable
data class FixtureInfoPage(val items: List<FixtureInfo> = emptyList())

/** A club or team as its code identifies it — `ClubIdentity.swift`. A name, nothing more. */
@Serializable
data class ClubIdentity(
    val id: String,
    val name: String,
    /** `club` or `team`. */
    val kind: String = "club",
    @SerialName("club_id") val clubId: String,
    @SerialName("club_name") val clubName: String = "",
    val sport: String? = null,
) {
    val isTeam: Boolean get() = kind == "team"

    /** "Hemel Hempstead CC — 2nd XI" for a team, just the club otherwise. */
    val displayName: String
        get() = if (isTeam && clubName.isNotBlank() && clubName != name) "$clubName — $name" else name
}

@Serializable
data class LookupOpponent(val token: String)

/** The kind of match, as `QuickMatchSheet.Kind` offers it. */
enum class MatchKind(val wire: String) {
    Friendly("friendly"),
    League("league_match"),
    Social("social");

    val label: String
        get() = when (this) {
            Friendly -> t("ld.friendly")
            League -> t("ld.league")
            Social -> t("ld.social")
        }
}

@Serializable
data class ConfirmCode(val code: String)

// MARK: The match

/** `POST /events/{id}/cricket-match`. `match_id` is chosen on the device, as iOS does. */
@Serializable
data class NewMatch(
    @SerialName("match_id") val matchId: String,
    @SerialName("overs_limit") val oversLimit: Int,
    @SerialName("home_name") val homeName: String,
    @SerialName("away_name") val awayName: String,
    @SerialName("opponent_club_id") val opponentClubId: String?,
)

/** The match as the server answers it — `MatchResponse` in `cricket.rs`. */
@Serializable
data class SetupMatch(
    val id: String,
    @SerialName("event_id") val eventId: String,
    @SerialName("club_id") val clubId: String = "",
    @SerialName("opponent_club_id") val opponentClubId: String? = null,
    val status: String = "scheduled",
    @SerialName("overs_limit") val oversLimit: Int = 20,
    @SerialName("home_name") val homeName: String = "Home",
    @SerialName("away_name") val awayName: String = "Away",
    @SerialName("last_seq") val lastSeq: Long = 0,
    @SerialName("active_scorer_user_id") val activeScorerUserId: String? = null,
    @SerialName("can_score") val canScore: Boolean = false,
    /** The side this caller plays for — who they propose terms on behalf of. */
    @SerialName("my_club_side") val myClubSide: Side? = null,
    /** The server's projection. Read for the terms a tournament set, nothing else. */
    val state: JsonObject? = null,
)

@Serializable
data class ClaimScorer(
    @SerialName("device_id") val deviceId: String,
    val force: Boolean,
)

@Serializable
data class SetupBatch(
    @SerialName("device_id") val deviceId: String,
    val events: List<ScoringEvent>,
)

@Serializable
data class Official(
    @SerialName("user_id") val userId: String,
    /** `umpire` or `scorer`. */
    val role: String,
)

/** `GET /cricket/matches/{id}/squad`. */
@Serializable
data class MatchSquads(val home: SideSquad, val away: SideSquad)

@Serializable
data class SideSquad(
    val side: String = "home",
    @SerialName("team_name") val teamName: String = "",
    @SerialName("club_id") val clubId: String? = null,
    @SerialName("can_pick") val canPick: Boolean = false,
    val submitted: Boolean = false,
    val players: List<SquadPlayer> = emptyList(),
)

@Serializable
data class SquadPlayer(
    val id: String,
    val name: String,
    @SerialName("is_captain") val isCaptain: Boolean = false,
    /** `selected`, `reserve`, `available`, `unavailable` or `member`. */
    val standing: String = "member",
    @SerialName("bats_left") val batsLeft: Boolean = false,
)

// MARK: The book's own shapes, as the engine reads them

@Serializable
enum class Side {
    @SerialName("home") Home,
    @SerialName("away") Away;

    val opposite: Side get() = if (this == Home) Away else Home
}

@Serializable
enum class TossCall {
    @SerialName("bat") Bat,
    @SerialName("bowl") Bowl;

    val label: String get() = if (this == Bat) t("la.bat") else t("la.bowl")
}

@Serializable
enum class Ground {
    @SerialName("open") Open,
    @SerialName("boxed") Boxed,
    @SerialName("indoor") Indoor;

    val label: String
        get() = when (this) {
            Open -> t("la.open_ground")
            Boxed -> t("sc.boxed_caged")
            Indoor -> t("ground_type.indoor")
        }

    val blurb: String
        get() = when (this) {
            Open -> t("sc.full_boundary_normal_outfield")
            Boxed -> t("sc.caged_or_netted")
            Indoor -> t("sc.indoor_centre_rules")
        }
}

@Serializable
enum class Ball {
    @SerialName("red") Red,
    @SerialName("white") White,
    @SerialName("pink") Pink,
    @SerialName("tennis") Tennis,
    @SerialName("tape") Tape;

    val label: String
        get() = when (this) {
            Red -> t("la.red_leather")
            White -> t("la.white_leather")
            Pink -> t("la.pink_leather")
            Tennis -> t("ball_type.tennis")
            Tape -> t("sc.tape_ball")
        }
}

/**
 * The terms both captains settle at the toss — `MatchConditions` in
 * `backend/cricket/src/types.rs`, field for field.
 */
@Serializable
data class MatchConditions(
    @SerialName("overs_limit") val oversLimit: Int,
    @SerialName("overs_per_bowler") val oversPerBowler: Int,
    val ground: Ground,
    val ball: Ball,
    @SerialName("powerplay_overs") val powerplayOvers: Int = 0,
    @SerialName("fielders_outside_powerplay") val fieldersOutsidePowerplay: Int = 2,
    @SerialName("fielders_outside_normal") val fieldersOutsideNormal: Int = 5,
    @SerialName("fielders_behind_square_leg") val fieldersBehindSquareLeg: Int = 2,
    @SerialName("target_overs_per_hour") val targetOversPerHour: Int = 0,
    @SerialName("innings_per_side") val inningsPerSide: Int = 1,
) {
    /** "20 overs · 4 per bowler · white leather · open ground", as iOS writes it. */
    val summary: String
        get() {
            val perBowler = if (oversPerBowler == 0) t("sr.no_bowler_limit")
            else t("sr.n_per_bowler", vars = mapOf("n" to oversPerBowler))
            var line = "$oversLimit ${t("sc.overs").lowercase()} · $perBowler · " +
                "${ball.label.lowercase()} · ${ground.label.lowercase()}"
            if (powerplayOvers > 0) line += t("sc.n_over_powerplay", vars = mapOf("n" to powerplayOvers))
            return line
        }

    /** A new over limit brings the usual allocation and powerplay with it, as on iOS. */
    fun withOvers(overs: Int): MatchConditions = copy(
        oversLimit = overs,
        oversPerBowler = standardOversPerBowler(overs),
        powerplayOvers = standardPowerplay(overs),
    )

    companion object {
        /** A fifth of the innings each, rounded up: 20 gives 4, 50 gives 10. */
        fun standardOversPerBowler(overs: Int): Int = maxOf(1, (overs + 4) / 5)

        fun standardPowerplay(overs: Int): Int = when (overs) {
            in 0..5 -> 0
            in 6..10 -> 2
            in 11..20 -> 6
            in 21..40 -> 8
            else -> 10
        }

        fun standard(overs: Int): MatchConditions {
            val o = maxOf(overs, 1)
            return MatchConditions(
                oversLimit = o,
                oversPerBowler = standardOversPerBowler(o),
                ground = Ground.Open,
                ball = Ball.White,
                powerplayOvers = standardPowerplay(o),
            )
        }

        val overPresets = listOf(5, 6, 8, 10, 12, 15, 16, 20, 25, 30, 35, 40, 45, 50)
    }
}

/** A player on a team sheet: a member, by their user id, or a guest with a name and a fresh id. */
@Serializable
data class MatchPlayer(
    val id: String,
    val name: String,
    @SerialName("bats_left") val batsLeft: Boolean = false,
)

@Serializable
data class MatchOfficials(
    val umpires: List<MatchPlayer> = emptyList(),
    val scorers: List<MatchPlayer> = emptyList(),
)

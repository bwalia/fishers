package com.fishers.app.net

import com.fishers.app.clubs.Club
import com.fishers.app.clubs.ClubMemberDetail
import com.fishers.app.clubs.Team
import com.fishers.app.cricket.ScoringEvent
import com.fishers.app.match.start.ClaimScorer
import com.fishers.app.match.start.ClubIdentity
import com.fishers.app.match.start.ConfirmCode
import com.fishers.app.match.start.CreatedFixture
import com.fishers.app.match.start.FixtureInfo
import com.fishers.app.match.start.FixtureInfoPage
import com.fishers.app.match.start.FixturePage
import com.fishers.app.match.start.LookupOpponent
import com.fishers.app.match.start.MatchSquads
import com.fishers.app.match.start.NewClub
import com.fishers.app.match.start.NewFixture
import com.fishers.app.match.start.NewMatch
import com.fishers.app.match.start.Official
import com.fishers.app.match.start.SetupBatch
import com.fishers.app.match.start.SetupMatch
import com.fishers.app.season.MyClubRole
import kotlinx.serialization.json.JsonElement
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * Starting a match: the score hub, the quick start, the setup wizard.
 *
 * The calls `ScoreHubView.swift`, `CricketScoringFlowView.swift` and
 * `CricketSyncService.swift` make, as `FishersAPI.swift` spells them. Kept apart
 * from [FishersApi] so this area and the scorer can be built at once.
 */
interface MatchStartApi {

    // ---- the hub ----

    /** Fixtures with their match already joined on. `state` is `live`,
     *  `upcoming` or `finished`; `q` needs two letters or the server refuses. */
    @GET("cricket/fixtures")
    suspend fun cricketFixtures(
        @Query("state") state: String? = null,
        @Query("q") search: String? = null,
        @Query("order") order: String = "asc",
        @Query("page") page: Int = 1,
        @Query("per_page") perPage: Int = 20,
    ): FixturePage

    // ---- your clubs ----

    @GET("clubs")
    suspend fun myClubs(): List<Club>

    @GET("clubs/{id}/my-role")
    suspend fun myClubRole(@Path("id") clubId: String): MyClubRole

    @GET("clubs/{id}/teams")
    suspend fun clubTeams(@Path("id") clubId: String): List<Team>

    @GET("clubs/{id}/members")
    suspend fun clubMembers(@Path("id") clubId: String): List<ClubMemberDetail>

    /** Refused with `{"code": "unverified"}` until an email or phone is confirmed,
     *  on a server that asks for that. */
    @POST("clubs")
    suspend fun createClub(@Body body: NewClub): Club

    // ---- the fixture ----

    @POST("events")
    suspend fun createEvent(@Body body: NewFixture): CreatedFixture

    @GET("events/{id}")
    suspend fun event(@Path("id") eventId: String): FixtureInfo

    /** A club's fixtures starting in a window — for finding one this phone
     *  asked for when the answer never came back. */
    @GET("events")
    suspend fun clubFixtures(
        @Query("club_id") clubId: String,
        @Query("from") from: String,
        @Query("to") to: String,
        @Query("per_page") perPage: Int = 50,
    ): FixtureInfoPage

    // ---- the opposition ----

    /** A scanned or typed code — or the whole URL it came in — to a side. */
    @POST("opponents/lookup")
    suspend fun lookupOpponent(@Body body: LookupOpponent): ClubIdentity

    @GET("opponents/search")
    suspend fun searchOpponents(@Query("q") query: String): List<ClubIdentity>

    // ---- the match ----

    /** 404 until somebody has set the match up. */
    @GET("events/{id}/cricket-match")
    suspend fun matchForEvent(@Path("id") eventId: String): SetupMatch

    /** Create-or-get: a fixture that already has a match answers with that one. */
    @POST("events/{id}/cricket-match")
    suspend fun createMatch(@Path("id") eventId: String, @Body body: NewMatch): SetupMatch

    @POST("cricket/matches/{id}/claim-scorer")
    suspend fun claimScorer(@Path("id") matchId: String, @Body body: ClaimScorer): SetupMatch

    @GET("cricket/matches/{id}/events")
    suspend fun matchEvents(@Path("id") matchId: String): List<ScoringEvent>

    @POST("cricket/matches/{id}/events")
    suspend fun postEvents(@Path("id") matchId: String, @Body body: SetupBatch): SetupMatch

    /** Who each side picks from: the fixture's squad, and the visitors' members
     *  when they are a club here. */
    @GET("cricket/matches/{id}/squad")
    suspend fun squads(@Path("id") matchId: String): MatchSquads

    /** An umpire or scorer who is a member gets scoring rights on the match. */
    @POST("cricket/matches/{id}/officials")
    suspend fun appointOfficial(@Path("id") matchId: String, @Body body: Official): JsonElement

    // ---- confirming who you are, when starting a club needs it ----

    /** `channel` is `email` or `phone`. */
    @POST("me/verification/{channel}")
    suspend fun sendCode(@Path("channel") channel: String): JsonElement

    @POST("me/verification/{channel}/confirm")
    suspend fun confirmCode(@Path("channel") channel: String, @Body body: ConfirmCode): PublicUser
}

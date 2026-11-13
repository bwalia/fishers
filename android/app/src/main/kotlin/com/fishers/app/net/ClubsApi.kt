package com.fishers.app.net

import com.fishers.app.clubs.AddMemberBody
import com.fishers.app.clubs.Club
import com.fishers.app.clubs.ClubFixturePage
import com.fishers.app.clubs.ClubInvite
import com.fishers.app.clubs.ClubMemberDetail
import com.fishers.app.clubs.ClubRoleInfo
import com.fishers.app.clubs.ClubSettings
import com.fishers.app.clubs.CreateClubBody
import com.fishers.app.clubs.CreateInviteBody
import com.fishers.app.clubs.CreateTeamBody
import com.fishers.app.clubs.CreateVenueBody
import com.fishers.app.clubs.InvitePreview
import com.fishers.app.clubs.OfferedSports
import com.fishers.app.clubs.OutstandingFees
import com.fishers.app.clubs.ProfileShareLink
import com.fishers.app.clubs.RoleBody
import com.fishers.app.clubs.Team
import com.fishers.app.clubs.TeamMemberRow
import com.fishers.app.clubs.Venue
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * Clubs, teams, grounds, members and invites — `backend/api/src/routes/clubs.rs`
 * and `invites.rs`. The clubs area's own interface, so it never edits
 * [FishersApi]; the few club calls that were already there (the roster, the
 * club link) stay there for the screens that use them.
 *
 * Paths are relative: the base URL already ends in `/api/v1/`.
 */
interface ClubsApi {

    // ---- a club ----

    /** Whoever starts it becomes its secretary. 403 `unverified` until the account is confirmed. */
    @POST("clubs")
    suspend fun createClub(@Body body: CreateClubBody): Club

    /** Members only. No role in it — that is [myRole]. */
    @GET("clubs/{id}")
    suspend fun club(@Path("id") clubId: String): Club

    /** What this person may do here. The page shows its buttons from this. */
    @GET("clubs/{id}/my-role")
    suspend fun myRole(@Path("id") clubId: String): ClubRoleInfo

    /** What this deployment lets a club be started in. No auth needed. */
    @GET("sports")
    suspend fun sports(): OfferedSports

    // ---- teams and grounds ----

    @GET("clubs/{id}/teams")
    suspend fun teams(@Path("id") clubId: String): List<Team>

    /** Needs `manage_club_ops`. */
    @POST("clubs/{id}/teams")
    suspend fun createTeam(@Path("id") clubId: String, @Body body: CreateTeamBody): Team

    /** Any club member may read a side's roster. */
    @GET("teams/{id}/members")
    suspend fun teamMembers(@Path("id") teamId: String): List<TeamMemberRow>

    @GET("clubs/{id}/venues")
    suspend fun venues(@Path("id") clubId: String): List<Venue>

    /** Needs `manage_club_ops`. */
    @POST("clubs/{id}/venues")
    suspend fun createVenue(@Path("id") clubId: String, @Body body: CreateVenueBody): Venue

    /** The club's fixtures, a page at a time, earliest first. */
    @GET("events")
    suspend fun clubFixtures(
        @Query("club_id") clubId: String,
        @Query("from") from: String? = null,
        @Query("per_page") perPage: Int = 50,
    ): ClubFixturePage

    // ---- the roster ----

    /** Every membership, any status. Any member may read it. */
    @GET("clubs/{id}/members")
    suspend fun members(@Path("id") clubId: String): List<ClubMemberDetail>

    /** By email or mobile number — whatever they signed up with. Secretary only. */
    @POST("clubs/{id}/members")
    suspend fun addMember(@Path("id") clubId: String, @Body body: AddMemberBody)

    /** 409 when it would leave the club without a secretary. */
    @PATCH("clubs/{id}/members/{userId}")
    suspend fun setRole(
        @Path("id") clubId: String,
        @Path("userId") userId: String,
        @Body body: RoleBody,
    )

    /** Answers `{"removed": bool}`, which nothing here needs. */
    @DELETE("clubs/{id}/members/{userId}")
    suspend fun removeMember(@Path("id") clubId: String, @Path("userId") userId: String)

    // ---- invites ----

    /** A one-person link: spent by the first account through it. */
    @POST("invites")
    suspend fun createInvite(@Body body: CreateInviteBody): ClubInvite

    /** What a link is to. No auth: it is read before anybody signs in. */
    @GET("invites/{token}")
    suspend fun invitePreview(@Path("token") token: String): InvitePreview

    /**
     * 404 once used or turned off; 403 `removed_from_club` when the club took
     * this person out; 403 `unverified` until the account is confirmed.
     */
    @POST("invites/{token}/accept")
    suspend fun acceptInvite(@Path("token") token: String): ClubInvite

    // The club's open link is in FishersApi already, with ClubDetailViewModel.

    /** The link a player sends a secretary. The same token until it is rotated. */
    @POST("me/share-link")
    suspend fun profileShareLink(): ProfileShareLink

    // ---- policy and fees ----

    @GET("clubs/{id}/settings")
    suspend fun settings(@Path("id") clubId: String): ClubSettings

    /** Needs `manage_club_ops`. Hours 0–336, reminders 0–10. */
    @PATCH("clubs/{id}/settings")
    suspend fun updateSettings(@Path("id") clubId: String, @Body body: ClubSettings): ClubSettings

    /** Captains and above; 403 for everyone else. */
    @GET("clubs/{id}/fees/outstanding")
    suspend fun outstandingFees(@Path("id") clubId: String): OutstandingFees

    @POST("clubs/{id}/fees/chase")
    suspend fun chaseFees(@Path("id") clubId: String)
}

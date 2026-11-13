package com.fishers.app.net

import com.fishers.app.clubs.Club
import com.fishers.app.clubs.Team
import com.fishers.app.fixtures.Attendee
import com.fishers.app.fixtures.ClubRole
import com.fishers.app.fixtures.CreateEventBody
import com.fishers.app.fixtures.DayAvailability
import com.fishers.app.fixtures.FishersEvent
import com.fishers.app.fixtures.FixtureMatch
import com.fishers.app.fixtures.FixtureStatusBody
import com.fishers.app.fixtures.MyFixture
import com.fishers.app.fixtures.NewVenue
import com.fishers.app.fixtures.Opponent
import com.fishers.app.fixtures.RespondToSelectionBody
import com.fishers.app.fixtures.RsvpRequest
import com.fishers.app.fixtures.SelectionBoard
import com.fishers.app.fixtures.SetDayAvailability
import com.fishers.app.fixtures.SetDaysAvailability
import com.fishers.app.fixtures.SetSquadBody
import com.fishers.app.fixtures.SquadProposal
import com.fishers.app.fixtures.Venue
import com.fishers.app.motm.MotmPollView
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * Fixtures, availability and picking the side — the calls `FishersAPI.swift`
 * makes for `FixturesView`, `EventDetailView` and `SelectionBoardView`.
 *
 * Its own interface rather than more of [FishersApi], so this area and the
 * others built alongside it do not all edit one file.
 */
interface FixturesApi {

    // ---- the diary ----

    /** Your fixtures starting in `[from, to)`, each with your answer. ISO instants. */
    @GET("events/mine")
    suspend fun myFixtures(
        @Query("from") from: String? = null,
        @Query("to") to: String? = null,
    ): List<MyFixture>

    @GET("events/{id}")
    suspend fun event(@Path("id") id: String): FishersEvent

    /** 403 for somebody in neither club. */
    @POST("events")
    suspend fun createEvent(@Body body: CreateEventBody): FishersEvent

    @POST("events/{id}/rsvp")
    suspend fun rsvp(@Path("id") id: String, @Body body: RsvpRequest)

    @GET("events/{id}/attendees")
    suspend fun attendees(@Path("id") id: String): List<Attendee>

    /** Postponed, called off, or back on — and everybody asked is told. */
    @POST("events/{id}/status")
    suspend fun updateFixtureStatus(@Path("id") id: String, @Body body: FixtureStatusBody)

    // ---- the clubs a fixture can belong to ----

    @GET("clubs")
    suspend fun clubs(): List<Club>

    @GET("clubs/{id}/my-role")
    suspend fun myRole(@Path("id") clubId: String): ClubRole

    @GET("clubs/{id}/teams")
    suspend fun teams(@Path("id") clubId: String): List<Team>

    @GET("clubs/{id}/venues")
    suspend fun venues(@Path("id") clubId: String): List<Venue>

    /** Needs `manage_club_ops`, which a captain may not have. */
    @POST("clubs/{id}/venues")
    suspend fun createVenue(@Path("id") clubId: String, @Body body: NewVenue): Venue

    /** Clubs and teams by name. 400 under two letters. */
    @GET("opponents/search")
    suspend fun searchOpponents(@Query("q") query: String): List<Opponent>

    // ---- picking the side ----

    @GET("events/{id}/selection")
    suspend fun selectionBoard(@Path("id") id: String): SelectionBoard

    /** The deterministic pick: no model, works with no API key on the server. */
    @POST("events/{id}/selection/suggest")
    suspend fun suggestSquad(@Path("id") id: String): SquadProposal

    /** Let the assistant pick. Falls back to the ranking server-side. */
    @POST("events/{id}/selection/agent")
    suspend fun assistantSquad(@Path("id") id: String): SquadProposal

    @POST("events/{id}/selection")
    suspend fun setSquad(@Path("id") id: String, @Body body: SetSquadBody): SelectionBoard

    /** A picked player saying they are playing, or pulling out. */
    @POST("events/{id}/selection/respond")
    suspend fun respondToSelection(@Path("id") id: String, @Body body: RespondToSelectionBody)

    /** Fill empty places from the reserves, in the captain's order. */
    @POST("events/{id}/selection/promote")
    suspend fun promoteReserves(@Path("id") id: String)

    // ---- what happens on the day ----

    /** 404 until somebody sets the match up. */
    @GET("events/{id}/cricket-match")
    suspend fun cricketMatch(@Path("id") eventId: String): FixtureMatch

    /** 404 until there is a vote. */
    @GET("events/{id}/motm")
    suspend fun motm(@Path("id") eventId: String): MotmPollView

    // ---- your standing calendar ----

    /** Calendar days, `2026-09-01`, both ends included. */
    @GET("availability")
    suspend fun availability(@Query("from") from: String, @Query("to") to: String): List<DayAvailability>

    @POST("availability")
    suspend fun setAvailability(@Body body: SetDayAvailability): DayAvailability

    /** "Every Saturday this month" in one go. */
    @POST("availability/bulk")
    suspend fun setAvailability(@Body body: SetDaysAvailability): List<DayAvailability>
}

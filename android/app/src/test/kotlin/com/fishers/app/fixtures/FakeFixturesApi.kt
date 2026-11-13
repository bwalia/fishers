package com.fishers.app.fixtures

import com.fishers.app.clubs.Club
import com.fishers.app.clubs.Team
import com.fishers.app.motm.MotmPollView
import com.fishers.app.net.FixturesApi
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import retrofit2.HttpException
import retrofit2.Response

/**
 * [FixturesApi] that fails loudly for anything a test did not set up, so a
 * test that quietly starts depending on another call says so.
 */
open class FakeFixturesApi : FixturesApi {
    override suspend fun myFixtures(from: String?, to: String?): List<MyFixture> = error("myFixtures not expected")
    override suspend fun event(id: String): FishersEvent = error("event not expected")
    override suspend fun createEvent(body: CreateEventBody): FishersEvent = error("createEvent not expected")
    override suspend fun rsvp(id: String, body: RsvpRequest): Unit = error("rsvp not expected")
    override suspend fun attendees(id: String): List<Attendee> = error("attendees not expected")
    override suspend fun updateFixtureStatus(id: String, body: FixtureStatusBody): Unit = error("updateFixtureStatus not expected")
    override suspend fun clubs(): List<Club> = error("clubs not expected")
    override suspend fun myRole(clubId: String): ClubRole = error("myRole not expected")
    override suspend fun teams(clubId: String): List<Team> = error("teams not expected")
    override suspend fun venues(clubId: String): List<Venue> = error("venues not expected")
    override suspend fun createVenue(clubId: String, body: NewVenue): Venue = error("createVenue not expected")
    override suspend fun searchOpponents(query: String): List<Opponent> = error("searchOpponents not expected")
    override suspend fun selectionBoard(id: String): SelectionBoard = error("selectionBoard not expected")
    override suspend fun suggestSquad(id: String): SquadProposal = error("suggestSquad not expected")
    override suspend fun assistantSquad(id: String): SquadProposal = error("assistantSquad not expected")
    override suspend fun setSquad(id: String, body: SetSquadBody): SelectionBoard = error("setSquad not expected")
    override suspend fun respondToSelection(id: String, body: RespondToSelectionBody): Unit = error("respondToSelection not expected")
    override suspend fun promoteReserves(id: String): Unit = error("promoteReserves not expected")
    override suspend fun cricketMatch(eventId: String): FixtureMatch = error("cricketMatch not expected")
    override suspend fun motm(eventId: String): MotmPollView = error("motm not expected")
    override suspend fun availability(from: String, to: String): List<DayAvailability> = error("availability not expected")
    override suspend fun setAvailability(body: SetDayAvailability): DayAvailability = error("setAvailability not expected")
    override suspend fun setAvailability(body: SetDaysAvailability): List<DayAvailability> = error("setAvailability (bulk) not expected")
}

/** What Retrofit throws for a refusal, with the server's `{"error": …}` body. */
fun httpError(code: Int, message: String = "nope"): HttpException = HttpException(
    Response.error<Any>(code, """{"error":"$message"}""".toResponseBody("application/json".toMediaType())),
)

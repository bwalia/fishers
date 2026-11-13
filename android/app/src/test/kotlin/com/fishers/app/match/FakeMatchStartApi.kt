package com.fishers.app.match

import com.fishers.app.clubs.Club
import com.fishers.app.clubs.ClubMemberDetail
import com.fishers.app.clubs.Team
import com.fishers.app.cricket.ScoringEvent
import com.fishers.app.match.start.ClaimScorer
import com.fishers.app.match.start.ClubIdentity
import com.fishers.app.match.start.ConfirmCode
import com.fishers.app.match.start.CreatedFixture
import com.fishers.app.match.start.FixtureInfo
import com.fishers.app.match.start.FixturePage
import com.fishers.app.match.start.LookupOpponent
import com.fishers.app.match.start.MatchSquads
import com.fishers.app.match.start.NewClub
import com.fishers.app.match.start.NewFixture
import com.fishers.app.match.start.NewMatch
import com.fishers.app.match.start.Official
import com.fishers.app.match.start.SetupBatch
import com.fishers.app.match.start.SetupMatch
import com.fishers.app.net.MatchStartApi
import com.fishers.app.net.PublicUser
import com.fishers.app.season.MyClubRole
import kotlinx.serialization.json.JsonElement
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import retrofit2.HttpException
import retrofit2.Response

/**
 * Every call refuses unless a test says otherwise, as `FakeFishersApi` does: a
 * test that passes because a call it never expected answered with an empty list
 * is a test of nothing.
 */
open class FakeMatchStartApi : MatchStartApi {
    private fun no(): Nothing = throw AssertionError("not expected in this test")

    override suspend fun cricketFixtures(state: String?, search: String?, order: String, page: Int, perPage: Int): FixturePage = no()
    override suspend fun myClubs(): List<Club> = no()
    override suspend fun myClubRole(clubId: String): MyClubRole = no()
    override suspend fun clubTeams(clubId: String): List<Team> = no()
    override suspend fun clubMembers(clubId: String): List<ClubMemberDetail> = no()
    override suspend fun createClub(body: NewClub): Club = no()
    override suspend fun createEvent(body: NewFixture): CreatedFixture = no()
    override suspend fun event(eventId: String): FixtureInfo = no()
    override suspend fun lookupOpponent(body: LookupOpponent): ClubIdentity = no()
    override suspend fun searchOpponents(query: String): List<ClubIdentity> = no()
    override suspend fun matchForEvent(eventId: String): SetupMatch = no()
    override suspend fun createMatch(eventId: String, body: NewMatch): SetupMatch = no()
    override suspend fun claimScorer(matchId: String, body: ClaimScorer): SetupMatch = no()
    override suspend fun matchEvents(matchId: String): List<ScoringEvent> = no()
    override suspend fun postEvents(matchId: String, body: SetupBatch): SetupMatch = no()
    override suspend fun squads(matchId: String): MatchSquads = no()
    override suspend fun appointOfficial(matchId: String, body: Official): JsonElement = no()
    override suspend fun sendCode(channel: String): JsonElement = no()
    override suspend fun confirmCode(channel: String, body: ConfirmCode): PublicUser = no()
}

/** What the server sends back when it refuses: `{"error": …, "code": …}`. */
fun refused(status: Int, message: String, code: String? = null): HttpException {
    val body = if (code == null) """{"error":"$message"}""" else """{"error":"$message","code":"$code"}"""
    return HttpException(Response.error<Any>(status, body.toResponseBody("application/json".toMediaType())))
}

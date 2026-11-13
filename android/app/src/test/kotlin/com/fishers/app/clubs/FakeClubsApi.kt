package com.fishers.app.clubs

import com.fishers.app.net.ClubsApi
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import retrofit2.HttpException
import retrofit2.Response

/**
 * [ClubsApi] with every call refusing by default, as [com.fishers.app.FakeFishersApi]
 * does: a test overrides what it exercises, and anything else being reached
 * fails by name rather than quietly answering with nothing.
 */
open class FakeClubsApi : ClubsApi {
    override suspend fun createClub(body: CreateClubBody): Club = error("createClub not expected")
    override suspend fun club(clubId: String): Club = error("club not expected")
    override suspend fun myRole(clubId: String): ClubRoleInfo = error("myRole not expected")
    override suspend fun sports(): OfferedSports = error("sports not expected")
    override suspend fun teams(clubId: String): List<Team> = error("teams not expected")
    override suspend fun createTeam(clubId: String, body: CreateTeamBody): Team = error("createTeam not expected")
    override suspend fun teamMembers(teamId: String): List<TeamMemberRow> = error("teamMembers not expected")
    override suspend fun venues(clubId: String): List<Venue> = error("venues not expected")
    override suspend fun createVenue(clubId: String, body: CreateVenueBody): Venue = error("createVenue not expected")
    override suspend fun clubFixtures(clubId: String, from: String?, perPage: Int): ClubFixturePage =
        error("clubFixtures not expected")
    override suspend fun members(clubId: String): List<ClubMemberDetail> = error("members not expected")
    override suspend fun addMember(clubId: String, body: AddMemberBody): Unit = error("addMember not expected")
    override suspend fun setRole(clubId: String, userId: String, body: RoleBody): Unit = error("setRole not expected")
    override suspend fun removeMember(clubId: String, userId: String): Unit = error("removeMember not expected")
    override suspend fun createInvite(body: CreateInviteBody): ClubInvite = error("createInvite not expected")
    override suspend fun invitePreview(token: String): InvitePreview = error("invitePreview not expected")
    override suspend fun acceptInvite(token: String): ClubInvite = error("acceptInvite not expected")
    override suspend fun profileShareLink(): ProfileShareLink = error("profileShareLink not expected")
    override suspend fun settings(clubId: String): ClubSettings = error("settings not expected")
    override suspend fun updateSettings(clubId: String, body: ClubSettings): ClubSettings =
        error("updateSettings not expected")
    override suspend fun outstandingFees(clubId: String): OutstandingFees = error("outstandingFees not expected")
    override suspend fun chaseFees(clubId: String): Unit = error("chaseFees not expected")
}

/** What the server sends when it says no: a status, and `{"error": ..., "code": ...}`. */
fun refused(status: Int, error: String, code: String? = null): HttpException {
    val body = buildString {
        append("""{"error":"$error"""")
        code?.let { append(""","code":"$it"""") }
        append("}")
    }
    return HttpException(Response.error<Any>(status, body.toResponseBody("application/json".toMediaType())))
}

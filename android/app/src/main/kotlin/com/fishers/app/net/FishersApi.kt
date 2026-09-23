package com.fishers.app.net

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path

/**
 * The server's own shapes, from `backend/domain/src/user.rs`. Named as the wire
 * names them: these are a contract, not a place to improve on someone's
 * spelling, and a rename here is a bug the compiler cannot see.
 */
@Serializable
data class LoginRequest(
    /** An email or a mobile number — the server takes either. */
    val identifier: String,
    val password: String,
)

/**
 * One of `email` or `phone` is required — the server says which is missing
 * rather than insisting on an address somebody may not have.
 */
@Serializable
data class SignupRequest(
    val name: String,
    val email: String? = null,
    val phone: String? = null,
    val password: String,
)

/** `PATCH /me` leaves everything it is not sent alone, so this is the one field. */
@Serializable
data class RoleIntentPatch(
    @SerialName("role_intent") val roleIntent: String,
)

@Serializable
data class RefreshRequest(
    @SerialName("refresh_token") val refreshToken: String,
)

@Serializable
data class AuthTokens(
    @SerialName("access_token") val accessToken: String,
    @SerialName("refresh_token") val refreshToken: String,
    @SerialName("token_type") val tokenType: String = "Bearer",
    @SerialName("expires_in") val expiresIn: Long = 0,
    val user: PublicUser? = null,
) {
    fun asTokens() = Tokens(access = accessToken, refresh = refreshToken)
}

/**
 * Only what signing in needs for now. The server sends a good deal more, and
 * `ignoreUnknownKeys` means the rest arriving early breaks nothing — a field
 * added server-side should never take the app down.
 */
@Serializable
data class PublicUser(
    val id: String,
    val name: String,
    val email: String? = null,
    val phone: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("role_intent") val roleIntent: String? = null,
)

interface FishersApi {
    @POST("auth/login")
    suspend fun login(@Body body: LoginRequest): AuthTokens

    @POST("auth/signup")
    suspend fun signup(@Body body: SignupRequest): AuthTokens

    @POST("auth/refresh")
    suspend fun refresh(@Body body: RefreshRequest): AuthTokens

    @GET("me")
    suspend fun me(): PublicUser

    @PATCH("me")
    suspend fun setRoleIntent(@Body body: RoleIntentPatch): PublicUser

    // ---- chat ----

    @GET("conversations")
    suspend fun conversations(): List<com.fishers.app.chat.ConversationSummary>

    @GET("conversations/{id}/messages")
    suspend fun messages(@Path("id") id: String): List<com.fishers.app.chat.ChatMessage>

    @POST("conversations/{id}/messages")
    suspend fun postMessage(
        @Path("id") id: String,
        @Body body: com.fishers.app.chat.PostMessageRequest,
    ): com.fishers.app.chat.ChatMessage

    // ---- cricket ----

    @GET("events/{id}/cricket-match")
    suspend fun cricketMatch(@Path("id") eventId: String): com.fishers.app.cricket.CricketMatch

    @GET("cricket/matches/{id}/events")
    suspend fun scoringEvents(
        @Path("id") matchId: String,
    ): List<com.fishers.app.cricket.ScoringEvent>

    @POST("cricket/matches/{id}/events")
    suspend fun postScoringEvents(
        @Path("id") matchId: String,
        @Body body: com.fishers.app.cricket.EventsBatch,
    ): com.fishers.app.cricket.CricketMatch

    // ---- clubs ----

    @GET("me/clubs")
    suspend fun myClubs(): List<com.fishers.app.clubs.Club>

    @GET("clubs/{id}/members")
    suspend fun clubMembers(@Path("id") id: String): List<com.fishers.app.clubs.ClubMemberDetail>

    @GET("clubs/{id}/teams")
    suspend fun clubTeams(@Path("id") id: String): List<com.fishers.app.clubs.Team>

    // ---- fixtures ----

    /** Everything this person is involved in, across their clubs. */
    @GET("events/mine")
    suspend fun myFixtures(): List<com.fishers.app.fixtures.FishersEvent>

    @GET("events/{id}")
    suspend fun event(@Path("id") id: String): com.fishers.app.fixtures.FishersEvent

    @POST("events/{id}/rsvp")
    suspend fun rsvp(
        @Path("id") id: String,
        @Body body: com.fishers.app.fixtures.RsvpRequest,
    )

    // ---- man of the match ----

    @GET("motm/polls/{id}")
    suspend fun motmPoll(@Path("id") id: String): com.fishers.app.motm.MotmPollView

    @GET("events/{id}/motm")
    suspend fun motmForEvent(@Path("id") eventId: String): com.fishers.app.motm.MotmPollView

    @POST("motm/polls/{id}/vote")
    suspend fun castMotmVote(
        @Path("id") id: String,
        @Body body: com.fishers.app.motm.CastMotmVoteRequest,
    ): com.fishers.app.motm.MotmPollView

    @DELETE("motm/polls/{id}/vote")
    suspend fun withdrawMotmVote(@Path("id") id: String): com.fishers.app.motm.MotmPollView

    @POST("conversations/{id}/read")
    suspend fun markRead(
        @Path("id") id: String,
        @Body body: com.fishers.app.chat.MarkReadRequest = com.fishers.app.chat.MarkReadRequest(),
    )
}

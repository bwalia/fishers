package com.fishers.app.net

import com.fishers.app.onboarding.PendingInvite
import com.fishers.app.onboarding.ShareLinkToken
import com.fishers.app.onboarding.SportsOnOffer
import com.fishers.app.onboarding.VerificationCode
import com.fishers.app.onboarding.VerificationSent
import com.fishers.app.onboarding.VerificationStatus
import com.fishers.app.profile.Me
import com.fishers.app.profile.MeStats
import com.fishers.app.profile.PlayerSeasonStats
import com.fishers.app.profile.ProfileUpdate
import com.fishers.app.profile.TeammateProfile
import com.fishers.app.profile.UserAchievement
import kotlinx.serialization.json.JsonElement
import okhttp3.MultipartBody
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Multipart
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Part
import retrofit2.http.Path

/**
 * The profile and onboarding area's calls: your own record, somebody else's,
 * confirming a contact, and the invitations waiting for you.
 *
 * `GET /me` is here as well as in [FishersApi] because that one decodes into
 * the six fields signing in needs. A profile page needs all of it — the sports,
 * the location, whether a contact is confirmed — so it reads [Me].
 */
interface ProfileApi {
    @GET("me")
    suspend fun me(): Me

    /** Edits send the whole profile the app holds; an absent field is left alone. */
    @PATCH("me")
    suspend fun updateProfile(@Body body: ProfileUpdate): Me

    /** Only the one field: `PATCH /me` leaves everything it is not sent alone. */
    @PATCH("me")
    suspend fun setRoleIntent(@Body body: RoleIntentPatch): Me

    /** A JPEG, PNG or WebP under 2 MB, in a part called `file`. The server
     *  sniffs the bytes, so the content type sent is a hint. */
    @Multipart
    @POST("me/avatar")
    suspend fun uploadAvatar(@Part file: MultipartBody.Part): Me

    /** The same token every time until it is rotated, so asking twice is harmless. */
    @POST("me/share-link")
    suspend fun shareLink(): ShareLinkToken

    @GET("me/stats")
    suspend fun myStats(): MeStats

    // ---- Confirming an email or a number ----

    @GET("me/verification")
    suspend fun verificationStatus(): VerificationStatus

    /** `channel` is `email` or `phone`. */
    @POST("me/verification/{channel}")
    suspend fun sendVerificationCode(@Path("channel") channel: String): VerificationSent

    /** Answers with the user, now marked verified. */
    @POST("me/verification/{channel}/confirm")
    suspend fun confirmVerification(
        @Path("channel") channel: String,
        @Body body: VerificationCode,
    ): Me

    // ---- Invitations addressed to this account ----

    @GET("invites/mine")
    suspend fun myInvites(): List<PendingInvite>

    /** The invite, accepted. Nothing on it is needed afterwards. */
    @POST("invites/{token}/accept")
    suspend fun acceptInvite(@Path("token") token: String): JsonElement

    // ---- Somebody else ----

    /** A club-mate, without contact details: the server does not send them. */
    @GET("users/{id}")
    suspend fun teammate(@Path("id") userId: String): TeammateProfile

    @GET("users/{id}/stats")
    suspend fun playerSeasons(@Path("id") userId: String): List<PlayerSeasonStats>

    @GET("users/{id}/achievements")
    suspend fun playerAchievements(@Path("id") userId: String): List<UserAchievement>

    /** What this deployment's sport pickers should offer. */
    @GET("sports")
    suspend fun offeredSports(): SportsOnOffer
}

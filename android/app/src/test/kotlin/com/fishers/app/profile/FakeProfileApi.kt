package com.fishers.app.profile

import com.fishers.app.net.ProfileApi
import com.fishers.app.net.RoleIntentPatch
import com.fishers.app.onboarding.PendingInvite
import com.fishers.app.onboarding.ShareLinkToken
import com.fishers.app.onboarding.SportsOnOffer
import com.fishers.app.onboarding.VerificationCode
import com.fishers.app.onboarding.VerificationSent
import com.fishers.app.onboarding.VerificationStatus
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.ResponseBody.Companion.toResponseBody
import retrofit2.HttpException
import retrofit2.Response

/**
 * Every call refuses unless a test says what it should do — the same rule as
 * `FakeFishersApi`: a call nobody expected fails loudly and by name, instead
 * of quietly answering with nothing.
 */
open class FakeProfileApi : ProfileApi {
    override suspend fun me(): Me = error("me not expected")
    override suspend fun updateProfile(body: ProfileUpdate): Me = error("updateProfile not expected")
    override suspend fun setRoleIntent(body: RoleIntentPatch): Me = error("setRoleIntent not expected")
    override suspend fun uploadAvatar(file: MultipartBody.Part): Me = error("uploadAvatar not expected")
    override suspend fun shareLink(): ShareLinkToken = error("shareLink not expected")
    override suspend fun myStats(): MeStats = error("myStats not expected")
    override suspend fun verificationStatus(): VerificationStatus = error("verificationStatus not expected")
    override suspend fun sendVerificationCode(channel: String): VerificationSent = error("sendVerificationCode not expected")
    override suspend fun confirmVerification(channel: String, body: VerificationCode): Me =
        error("confirmVerification not expected")
    override suspend fun myInvites(): List<PendingInvite> = error("myInvites not expected")
    override suspend fun acceptInvite(token: String): JsonElement = error("acceptInvite not expected")
    override suspend fun teammate(userId: String): TeammateProfile = error("teammate not expected")
    override suspend fun playerSeasons(userId: String): List<PlayerSeasonStats> = error("playerSeasons not expected")
    override suspend fun playerAchievements(userId: String): List<UserAchievement> = error("playerAchievements not expected")
    override suspend fun offeredSports(): SportsOnOffer = error("offeredSports not expected")
}

/** What the API sends when it refuses: a status, and `{"error", "code"}`. */
fun refusal(status: Int, message: String, code: String? = null): HttpException {
    val body = if (code == null) """{"error":"$message"}""" else """{"error":"$message","code":"$code"}"""
    return HttpException(Response.error<Any>(status, body.toResponseBody("application/json".toMediaType())))
}

val emptyJson: JsonElement = JsonObject(emptyMap())

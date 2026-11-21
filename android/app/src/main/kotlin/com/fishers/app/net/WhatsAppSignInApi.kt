package com.fishers.app.net

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST

/** `GET /auth/whatsapp`: offer the option only when this is true. */
@Serializable
data class WhatsAppConfig(val enabled: Boolean = false)

/** The number as typed: the server works out the country code and the spaces. */
@Serializable
data class WhatsAppPhone(val phone: String) {
    override fun toString(): String = "WhatsAppPhone(…${phone.takeLast(3)})"
}

@Serializable
data class WhatsAppCode(val phone: String, val code: String) {
    /** Never the code, wherever this ends up printed. */
    override fun toString(): String = "WhatsAppCode(…${phone.takeLast(3)})"
}

/**
 * `POST /auth/whatsapp/start`. Always the same answer, whether or not the
 * number has an account, so it never says which numbers do.
 */
@Serializable
data class WhatsAppCodeSent(
    val sent: Boolean = true,
    /** Seconds the code works for. */
    @SerialName("expires_in") val expiresIn: Int = 600,
    /** Seconds before another may be asked for. */
    @SerialName("resend_after") val resendAfter: Int = 60,
)

/**
 * Signing in with a mobile number and a code sent by WhatsApp —
 * `backend/api/src/routes/auth.rs`, §5.4 and §10 of
 * docs/CLUB_PAYMENTS_V2_PLAN.md. Its own interface, like every area's.
 *
 * Refusals are `{error, code}`: `bad_phone` (400), `slow_down` (429),
 * `wrong_code` (400), `not_sent` (502) and `whatsapp_off` (503). Each comes
 * with a sentence to show as it is.
 */
interface WhatsAppSignInApi {
    @GET("auth/whatsapp")
    suspend fun config(): WhatsAppConfig

    @POST("auth/whatsapp/start")
    suspend fun start(@Body body: WhatsAppPhone): WhatsAppCodeSent

    /** The same tokens as `/auth/login`. */
    @POST("auth/whatsapp/verify")
    suspend fun verify(@Body body: WhatsAppCode): AuthTokens
}

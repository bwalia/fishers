package com.fishers.app.net

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import retrofit2.http.Body
import retrofit2.http.POST

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

    @POST("auth/refresh")
    suspend fun refresh(@Body body: RefreshRequest): AuthTokens
}

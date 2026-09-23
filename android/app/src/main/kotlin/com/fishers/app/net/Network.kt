package com.fishers.app.net

import com.fishers.app.config.AppConfig
import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import retrofit2.Retrofit

/**
 * Everything the app talks to the server through.
 *
 * The base URL is read from [AppConfig] at build time rather than captured
 * once, because the settings panel can move the server between launches and a
 * client built against a stale address talks to nothing.
 */
class Network(config: AppConfig, session: Session) {

    private val json = Json {
        // A field added server-side must never take the app down.
        ignoreUnknownKeys = true
        explicitNulls = false
    }

    /** Unsigned, and used only to renew: signing a refresh with the token that
     *  was just refused is how a refresh loop starts. */
    private val plain: FishersApi = Retrofit.Builder()
        .baseUrl(config.apiV1.trimEnd('/') + "/")
        .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
        .build()
        .create(FishersApi::class.java)

    private val client = fishersHttpClient(
        session = session,
        refreshWith = { token ->
            runCatching { plain.refresh(RefreshRequest(token)).asTokens() }.getOrNull()
        },
    )

    val api: FishersApi = Retrofit.Builder()
        .baseUrl(config.apiV1.trimEnd('/') + "/")
        .client(client)
        .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
        .build()
        .create(FishersApi::class.java)
}

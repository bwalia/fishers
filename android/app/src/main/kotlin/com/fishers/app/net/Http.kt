package com.fishers.app.net

import kotlinx.coroutines.runBlocking
import okhttp3.Authenticator
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.Route
import java.util.concurrent.TimeUnit

/** Paths that must never carry a token, because they are how you get one. */
private fun Request.isAuthEndpoint(): Boolean =
    url.encodedPath.contains("/auth/login") ||
        url.encodedPath.contains("/auth/register") ||
        url.encodedPath.contains("/auth/refresh")

/** Signs each request with the session, the way iOS sets the Bearer header. */
class AuthInterceptor(private val session: Session) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val token = session.access
        if (token == null || request.isAuthEndpoint()) return chain.proceed(request)
        return chain.proceed(
            request.newBuilder().header("Authorization", "Bearer $token").build()
        )
    }
}

/**
 * A 401 means renew and try once more.
 *
 * OkHttp calls this only after a request has been refused, and stops calling it
 * if the retry is refused too, so there is no loop to write. The guard below is
 * for the other shape: a token that is renewed successfully and still refused,
 * which is the server saying no rather than the session being stale.
 */
class RefreshAuthenticator(
    private val session: Session,
    private val refreshWith: suspend (String) -> Tokens?,
) : Authenticator {

    override fun authenticate(route: Route?, response: Response): Request? {
        if (response.request.isAuthEndpoint()) return null
        // Refused twice already: renewing again would not change the answer.
        if (response.priorResponse != null) return null

        val stale = response.request.header("Authorization")?.removePrefix("Bearer ")
        // Authenticator is called on OkHttp's thread and must answer there.
        // `renew` coalesces, so several of these arriving at once is one refresh.
        val fresh = runBlocking { session.renew(stale) { refreshWith(it) } } ?: return null

        return response.request.newBuilder()
            .header("Authorization", "Bearer $fresh")
            .build()
    }
}

fun fishersHttpClient(
    session: Session,
    refreshWith: suspend (String) -> Tokens?,
    extra: List<Interceptor> = emptyList(),
): OkHttpClient = OkHttpClient.Builder()
    .addInterceptor(AuthInterceptor(session))
    .apply { extra.forEach { addInterceptor(it) } }
    .authenticator(RefreshAuthenticator(session, refreshWith))
    // A scorer at a ground is on whatever signal the ground has. Long enough to
    // ride out a bad over, short enough that a tap does not hang for a minute.
    .connectTimeout(15, TimeUnit.SECONDS)
    .readTimeout(30, TimeUnit.SECONDS)
    .writeTimeout(30, TimeUnit.SECONDS)
    .retryOnConnectionFailure(true)
    .build()

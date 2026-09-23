package com.fishers.app.net

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** What the server hands back when a session starts or is renewed. */
data class Tokens(val access: String, val refresh: String)

/**
 * The signed-in session — `NetworkService.swift`'s token half.
 *
 * The one thing here that is not bookkeeping is [renew]. The server rotates the
 * refresh token: every successful refresh invalidates the one that was used. So
 * when several requests are answered 401 at once — which is the normal case,
 * because a screen fires its calls together — they must not each go and refresh.
 * The first would succeed and the rest would present a token the server has
 * already retired, and the app would sign the user out in the middle of an over.
 *
 * iOS holds the in-flight `Task` and awaits it. This holds a mutex and, once
 * inside, checks whether somebody else already renewed: the losers of the race
 * return the winner's tokens instead of asking again.
 */
class Session(private val store: TokenStore) {

    private val mutex = Mutex()

    @Volatile
    var access: String? = store.get(TokenStore.ACCESS)
        private set

    @Volatile
    var refresh: String? = store.get(TokenStore.REFRESH)
        private set

    val isSignedIn: Boolean get() = access != null || refresh != null

    fun set(tokens: Tokens?) {
        access = tokens?.access
        refresh = tokens?.refresh
        store.set(TokenStore.ACCESS, tokens?.access)
        store.set(TokenStore.REFRESH, tokens?.refresh)
    }

    fun clear() = set(null)

    /**
     * Renew the session once, however many callers ask at the same time.
     *
     * [stale] is the access token the caller was refused with. If it no longer
     * matches, somebody else has already renewed and the caller simply takes
     * the new one — that is the whole of the coalescing.
     *
     * Returns the usable access token, or null when there is no way back and
     * the session has been cleared.
     */
    suspend fun renew(stale: String?, refreshWith: suspend (String) -> Tokens?): String? =
        mutex.withLock {
            val current = access
            if (current != null && current != stale) return@withLock current

            val token = refresh ?: run {
                clear()
                return@withLock null
            }
            val fresh = refreshWith(token)
            if (fresh == null) {
                // The refresh token is spent or rejected. There is nothing left
                // to try, and pretending otherwise loops.
                clear()
                null
            } else {
                set(fresh)
                fresh.access
            }
        }
}

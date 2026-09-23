package com.fishers.app.net

import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

class SessionTest {

    private class FakeStore(private val values: MutableMap<String, String?> = mutableMapOf()) :
        TokenStore {
        override fun get(key: String) = values[key]
        override fun set(key: String, value: String?) {
            if (value == null) values.remove(key) else values[key] = value
        }
    }

    private fun signedIn() = FakeStore(
        mutableMapOf(TokenStore.ACCESS to "stale", TokenStore.REFRESH to "r1"),
    )

    /**
     * The one that matters. A screen fires its calls together, so they are
     * refused together. The server rotates the refresh token on every renewal,
     * so a second refresh would present one the server has already retired —
     * and the app would sign somebody out in the middle of an over.
     */
    @Test
    fun `parallel refusals cause exactly one refresh`() = runTest {
        val session = Session(signedIn())
        val refreshes = AtomicInteger(0)

        val results = (1..8).map {
            async {
                session.renew("stale") {
                    refreshes.incrementAndGet()
                    delay(20) // the network takes a moment; the others pile up behind it
                    Tokens(access = "fresh", refresh = "r2")
                }
            }
        }.awaitAll()

        assertEquals("one renewal, however many asked", 1, refreshes.get())
        assertTrue("and they all got the new token", results.all { it == "fresh" })
        assertEquals("fresh", session.access)
        assertEquals("the rotated refresh token was kept", "r2", session.refresh)
    }

    @Test
    fun `somebody who already has the new token does not refresh again`() = runTest {
        val session = Session(signedIn())
        session.set(Tokens(access = "fresh", refresh = "r2"))
        var called = false

        val token = session.renew("stale") { called = true; null }

        assertEquals("fresh", token)
        assertFalse("nothing to renew — it was already done", called)
    }

    /** A spent refresh token has no way back, and pretending otherwise loops. */
    @Test
    fun `a refused refresh clears the session rather than retrying`() = runTest {
        val session = Session(signedIn())

        val token = session.renew("stale") { null }

        assertNull(token)
        assertNull(session.access)
        assertNull(session.refresh)
        assertFalse(session.isSignedIn)
    }

    @Test
    fun `with no refresh token there is nothing to renew`() = runTest {
        val session = Session(FakeStore(mutableMapOf(TokenStore.ACCESS to "stale")))
        var called = false

        assertNull(session.renew("stale") { called = true; null })
        assertFalse(called)
        assertFalse(session.isSignedIn)
    }

    @Test
    fun `tokens survive a restart, because they are written as they are set`() {
        val store = FakeStore()
        Session(store).set(Tokens(access = "a", refresh = "r"))

        val next = Session(store)
        assertEquals("a", next.access)
        assertEquals("r", next.refresh)
        assertTrue(next.isSignedIn)
    }

    @Test
    fun `clearing takes them out of the store too`() {
        val store = FakeStore()
        val session = Session(store)
        session.set(Tokens(access = "a", refresh = "r"))

        session.clear()

        assertNull(store.get(TokenStore.ACCESS))
        assertNull(store.get(TokenStore.REFRESH))
        assertFalse(Session(store).isSignedIn)
    }
}

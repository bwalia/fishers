package com.fishers.app.session

import com.fishers.app.EnglishStrings
import com.fishers.app.FakeFishersApi
import com.fishers.app.clubs.refused
import com.fishers.app.net.AuthTokens
import com.fishers.app.net.PublicUser
import com.fishers.app.net.Session
import com.fishers.app.net.TokenStore
import com.fishers.app.net.WhatsAppCode
import com.fishers.app.net.WhatsAppCodeSent
import com.fishers.app.net.WhatsAppConfig
import com.fishers.app.net.WhatsAppPhone
import com.fishers.app.net.WhatsAppSignInApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.io.IOException

/** Sign in with a mobile number and a WhatsApp code: offered only when on, every refusal in the server's words. */
@OptIn(ExperimentalCoroutinesApi::class)
class WhatsAppSignInViewModelTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val tokens = AuthTokens(accessToken = "a", refreshToken = "r", user = PublicUser(id = "u1", name = "Ravi Sharma"))

    /** A server with WhatsApp sign-in on, unless told otherwise. Everything asked is kept. */
    private open class Server(var enabled: Boolean = true) : WhatsAppSignInApi {
        val started = mutableListOf<String>()
        val verified = mutableListOf<WhatsAppCode>()
        var startFails: Throwable? = null
        var verifyFails: Throwable? = null
        var tokens = AuthTokens(accessToken = "a", refreshToken = "r")
        override suspend fun config() = WhatsAppConfig(enabled)
        override suspend fun start(body: WhatsAppPhone): WhatsAppCodeSent {
            started += body.phone
            startFails?.let { startFails = null; throw it }
            return WhatsAppCodeSent(sent = true, expiresIn = 600, resendAfter = 60)
        }
        override suspend fun verify(body: WhatsAppCode): AuthTokens {
            verified += body
            verifyFails?.let { verifyFails = null; throw it }
            return tokens
        }
    }

    private var now = 1_000_000L
    private val signedIn = mutableListOf<AuthTokens>()

    private fun model(api: WhatsAppSignInApi) = WhatsAppSignInViewModel(api, onSignedIn = { signedIn += it }, clock = { now })

    @Test
    fun `offered only when the server says it is on`() = runTest(dispatcher.scheduler) {
        val on = model(Server(enabled = true)).apply { loadConfig() }
        val off = model(Server(enabled = false)).apply { loadConfig() }
        val unreachable = model(object : Server() {
            override suspend fun config(): WhatsAppConfig = throw IOException("no signal")
        }).apply { loadConfig() }
        advanceUntilIdle()
        assertTrue(on.state.value.enabled)
        assertFalse(off.state.value.enabled)
        assertFalse("a failure to ask leaves it off, quietly", unreachable.state.value.enabled)
        assertNull(unreachable.state.value.error)
    }

    @Test
    fun `number, then code, then signed in`() = runTest(dispatcher.scheduler) {
        val api = Server().apply { tokens = this@WhatsAppSignInViewModelTest.tokens }
        val model = model(api)
        model.loadConfig()
        advanceUntilIdle()
        model.open()
        assertTrue(model.state.value.open)

        model.sendCode(" +44 7700 900123 ")
        advanceUntilIdle()
        assertEquals(listOf("+44 7700 900123"), api.started)
        assertEquals("+44 7700 900123", model.state.value.sentTo)

        model.verify("123 456")
        advanceUntilIdle()
        assertEquals(WhatsAppCode("+44 7700 900123", "123456"), api.verified.single())
        assertEquals(listOf(tokens), signedIn)
        assertFalse("the form is done with", model.state.value.open)
        assertNull(model.state.value.sentTo)
    }

    @Test
    fun `a code that is not six digits is not sent`() = runTest(dispatcher.scheduler) {
        val api = Server()
        val model = model(api)
        model.sendCode("+447700900123")
        advanceUntilIdle()
        model.verify("1234")
        advanceUntilIdle()
        assertTrue(api.verified.isEmpty())
        assertEquals("The code is 6 digits.", model.state.value.error)
    }

    @Test
    fun `a bad number is the server's sentence, and the number stays to fix`() = runTest(dispatcher.scheduler) {
        val said = "That doesn't look like a mobile number. Put the country code first, like +44 7700 900123."
        val api = Server().apply { startFails = refused(400, said, "bad_phone") }
        val model = model(api)
        model.open()
        model.sendCode("07700")
        advanceUntilIdle()
        assertEquals(said, model.state.value.error)
        assertNull(model.state.value.sentTo)
        assertFalse(model.state.value.isBusy)
    }

    @Test
    fun `a message WhatsApp would not take is the server's sentence, not "the server is having trouble"`() = runTest(dispatcher.scheduler) {
        val said = "We couldn't send the WhatsApp message just now. Try again in a minute."
        val api = Server().apply { startFails = refused(502, said, "not_sent") }
        val model = model(api)
        model.sendCode("+447700900123")
        advanceUntilIdle()
        assertEquals(said, model.state.value.error)
    }

    @Test
    fun `asking too soon is the server's sentence`() = runTest(dispatcher.scheduler) {
        val said = "A code is already on its way. Wait a minute before asking for another."
        val api = Server().apply { startFails = refused(429, said, "slow_down") }
        val model = model(api)
        model.sendCode("+447700900123")
        advanceUntilIdle()
        assertEquals(said, model.state.value.error)
    }

    @Test
    fun `a wrong code is the server's sentence, and the code can be typed again`() = runTest(dispatcher.scheduler) {
        val said = "That code isn't right, or it has run out. Ask for a new one."
        val api = Server().apply { verifyFails = refused(400, said, "wrong_code") }
        val model = model(api)
        model.sendCode("+447700900123")
        advanceUntilIdle()
        model.verify("000000")
        advanceUntilIdle()
        assertEquals(said, model.state.value.error)
        assertEquals("+447700900123", model.state.value.sentTo)
        assertTrue(signedIn.isEmpty())

        model.verify("123456")
        advanceUntilIdle()
        assertEquals(1, signedIn.size)
    }

    @Test
    fun `switched off since the form opened goes back to email, saying why`() = runTest(dispatcher.scheduler) {
        val said = "Signing in with WhatsApp isn't switched on yet. Use your email and password."
        val api = Server().apply { startFails = refused(503, said, "whatsapp_off") }
        val model = model(api)
        model.loadConfig()
        advanceUntilIdle()
        model.open()
        model.sendCode("+447700900123")
        advanceUntilIdle()
        val state = model.state.value
        assertFalse(state.open)
        assertFalse(state.enabled)
        assertEquals(said, state.error)
    }

    @Test
    fun `another code only once the server's wait is over`() = runTest(dispatcher.scheduler) {
        val api = Server()
        val model = model(api)
        model.sendCode("+447700900123")
        advanceUntilIdle()
        assertEquals(60, model.secondsUntilResend())

        now += 30_000
        model.resend()
        advanceUntilIdle()
        assertEquals("too soon: not asked", 1, api.started.size)
        assertEquals(30, model.secondsUntilResend())

        now += 30_000
        assertEquals(0, model.secondsUntilResend())
        model.resend()
        advanceUntilIdle()
        assertEquals(2, api.started.size)
    }

    @Test
    fun `a different number goes back to the number, and email closes it`() = runTest(dispatcher.scheduler) {
        val model = model(Server())
        model.loadConfig()
        advanceUntilIdle()
        model.open()
        model.sendCode("+447700900123")
        advanceUntilIdle()
        model.changeNumber()
        assertNull(model.state.value.sentTo)
        assertTrue(model.state.value.open)
        model.close()
        assertFalse(model.state.value.open)
        assertTrue("still offered", model.state.value.enabled)
    }

    @Test
    fun `the session takes the tokens as signing in`() = runTest(dispatcher.scheduler) {
        val store = object : TokenStore {
            val values = mutableMapOf<String, String?>()
            override fun get(key: String) = values[key]
            override fun set(key: String, value: String?) {
                if (value == null) values.remove(key) else values[key] = value
            }
        }
        val session = Session(store)
        val model = SessionViewModel(FakeFishersApi(), session)
        model.signedIn(tokens)
        assertTrue(session.isSignedIn)
        assertTrue(model.state.value.isAuthenticated)
        assertEquals("Ravi Sharma", model.state.value.user?.name)
    }
}

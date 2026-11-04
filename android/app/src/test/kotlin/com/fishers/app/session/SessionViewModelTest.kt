package com.fishers.app.session

import com.fishers.app.EnglishStrings
import com.fishers.app.FakeFishersApi
import com.fishers.app.net.AuthTokens
import com.fishers.app.net.DeleteAccountRequest
import com.fishers.app.net.GoogleConfig
import com.fishers.app.net.GoogleSignInRequest
import com.fishers.app.net.FishersApi
import com.fishers.app.net.LoginRequest
import com.fishers.app.net.PublicUser
import com.fishers.app.net.RefreshRequest
import com.fishers.app.net.RoleIntentPatch
import com.fishers.app.net.Session
import com.fishers.app.net.SignupRequest
import com.fishers.app.net.TokenStore
import com.fishers.app.net.Tokens
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import retrofit2.HttpException
import retrofit2.Response

@OptIn(ExperimentalCoroutinesApi::class)
class SessionViewModelTest {
    @get:Rule val english = EnglishStrings()


    // `runTest` builds its own TestCoroutineScheduler unless it is handed
    // one, and a bare StandardTestDispatcher() builds a second. Work launched
    // on viewModelScope then sits on the dispatcher's scheduler while
    // advanceUntilIdle() drains runTest's, so the assertions run before the
    // view model has done anything — sometimes. It passed on every machine
    // here and failed in CI, which is the worst way to find out.
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private class FakeStore(private val values: MutableMap<String, String?> = mutableMapOf()) :
        TokenStore {
        override fun get(key: String) = values[key]
        override fun set(key: String, value: String?) {
            if (value == null) values.remove(key) else values[key] = value
        }
    }

    private val alice = PublicUser(id = "u1", name = "Alice Ahmed", email = "a@example.test")

    private fun tokens(user: PublicUser? = null) = AuthTokens(
        accessToken = "a", refreshToken = "r", user = user,
    )

    private fun unauthorized() = HttpException(
        Response.error<Any>(401, "".toResponseBody("application/json".toMediaType())),
    )

    // ---- bootstrap ----

    @Test
    fun `with no stored token the app goes straight to the form`() = runTest(dispatcher.scheduler) {
        val model = SessionViewModel(FakeFishersApi(), Session(FakeStore()))

        model.bootstrap()
        advanceUntilIdle()

        assertFalse(model.state.value.isAuthenticated)
        assertFalse("and stops showing the spinner", model.state.value.isStarting)
    }

    /**
     * The one that matters on launch. A stored token is not proof of a session:
     * it may have been revoked, or the account deleted. Believing it would put
     * somebody inside an app where every screen then fails one at a time, which
     * reads as the app being broken rather than as being signed out.
     */
    @Test
    fun `a token the server no longer honours signs them out cleanly`() = runTest(dispatcher.scheduler) {
        val store = FakeStore(
            mutableMapOf(TokenStore.ACCESS to "stale", TokenStore.REFRESH to "also-stale"),
        )
        val session = Session(store)
        val model = SessionViewModel(object : FakeFishersApi() {
            override suspend fun me(): PublicUser = throw unauthorized()
        }, session)

        model.bootstrap()
        advanceUntilIdle()

        assertFalse(model.state.value.isAuthenticated)
        assertFalse(model.state.value.isStarting)
        assertNull("the dead tokens are not left to fail every screen", session.access)
        assertNull(store.get(TokenStore.REFRESH))
    }

    @Test
    fun `a token the server honours restores the session without asking again`() = runTest(dispatcher.scheduler) {
        val session = Session(FakeStore(mutableMapOf(TokenStore.ACCESS to "good")))
        val model = SessionViewModel(object : FakeFishersApi() {
            override suspend fun me() = alice
        }, session)

        model.bootstrap()
        advanceUntilIdle()

        assertTrue(model.state.value.isAuthenticated)
        assertEquals(alice, model.state.value.user)
        assertFalse(model.state.value.isStarting)
    }

    // ---- signing in ----

    @Test
    fun `signing in keeps the tokens and the user`() = runTest(dispatcher.scheduler) {
        val store = FakeStore()
        val session = Session(store)
        val model = SessionViewModel(object : FakeFishersApi() {
            override suspend fun login(body: LoginRequest) = tokens(alice)
        }, session)

        model.signIn(" a@example.test ", "hunter2hunter2")
        advanceUntilIdle()

        assertTrue(model.state.value.isAuthenticated)
        assertEquals(alice, model.state.value.user)
        assertEquals("a", store.get(TokenStore.ACCESS))
        assertEquals("r", store.get(TokenStore.REFRESH))
    }

    @Test
    fun `the identifier is trimmed, because a keyboard adds a space`() = runTest(dispatcher.scheduler) {
        var seen: String? = null
        val model = SessionViewModel(object : FakeFishersApi() {
            override suspend fun login(body: LoginRequest): AuthTokens {
                seen = body.identifier
                return tokens(alice)
            }
        }, Session(FakeStore()))

        model.signIn("  a@example.test  ", "hunter2hunter2")
        advanceUntilIdle()

        assertEquals("a@example.test", seen)
    }

    @Test
    fun `a refused sign-in says so and stores nothing`() = runTest(dispatcher.scheduler) {
        val store = FakeStore()
        val model = SessionViewModel(object : FakeFishersApi() {
            override suspend fun login(body: LoginRequest): AuthTokens = throw unauthorized()
        }, Session(store))

        model.signIn("a@example.test", "wrong")
        advanceUntilIdle()

        assertFalse(model.state.value.isAuthenticated)
        assertEquals("That email or password was not right.", model.state.value.error)
        assertFalse("and it is not still spinning", model.state.value.isLoading)
        assertNull("nothing was written", store.get(TokenStore.ACCESS))
    }

    // ---- signing up ----

    @Test
    fun `an identifier with an at sign is an email, and one without is a phone`() = runTest(dispatcher.scheduler) {
        var asEmail: SignupRequest? = null
        var asPhone: SignupRequest? = null
        val api = object : FakeFishersApi() {
            override suspend fun signup(body: SignupRequest): AuthTokens {
                if (body.email != null) asEmail = body else asPhone = body
                return tokens(alice)
            }
            override suspend fun setRoleIntent(body: RoleIntentPatch) = alice
        }

        SessionViewModel(api, Session(FakeStore()))
            .signUp("Alice", "a@example.test", "hunter2hunter2", null)
        advanceUntilIdle()
        SessionViewModel(api, Session(FakeStore()))
            .signUp("Bilal", "07700900123", "hunter2hunter2", null)
        advanceUntilIdle()

        assertEquals("a@example.test", asEmail?.email)
        assertNull(asEmail?.phone)
        assertEquals("07700900123", asPhone?.phone)
        assertNull(asPhone?.email)
    }

    @Test
    fun `the role is saved after the account exists, because there was nowhere to put it before`() =
        runTest {
            var patched: String? = null
            val model = SessionViewModel(object : FakeFishersApi() {
                override suspend fun signup(body: SignupRequest) = tokens(alice)
                override suspend fun setRoleIntent(body: RoleIntentPatch): PublicUser {
                    patched = body.roleIntent
                    return alice.copy(roleIntent = body.roleIntent)
                }
            }, Session(FakeStore()))

            model.signUp("Alice", "a@example.test", "hunter2hunter2", RoleIntent.Secretary)
            advanceUntilIdle()

            assertEquals("secretary", patched)
            assertEquals("secretary", model.state.value.user?.roleIntent)
        }

    /**
     * Deliberate: the account exists and they are signed in. Failing the whole
     * sign-up because one optional field did not save would be throwing away a
     * working account over something the app can ask again.
     */
    @Test
    fun `a role that will not save does not undo the sign-up`() = runTest(dispatcher.scheduler) {
        val model = SessionViewModel(object : FakeFishersApi() {
            override suspend fun signup(body: SignupRequest) = tokens(alice)
            override suspend fun setRoleIntent(body: RoleIntentPatch): PublicUser =
                throw unauthorized()
        }, Session(FakeStore()))

        model.signUp("Alice", "a@example.test", "hunter2hunter2", RoleIntent.Player)
        advanceUntilIdle()

        assertTrue("still signed in", model.state.value.isAuthenticated)
        assertNotNull(model.state.value.user)
        assertNull("and not told off about it", model.state.value.error)
    }

    // ---- signing out ----

    @Test
    fun `signing out takes the tokens with it`() = runTest(dispatcher.scheduler) {
        val store = FakeStore()
        val session = Session(store)
        session.set(Tokens("a", "r"))
        val model = SessionViewModel(FakeFishersApi(), session)

        model.signOut()

        assertFalse(model.state.value.isAuthenticated)
        assertNull(store.get(TokenStore.ACCESS))
        assertNull(store.get(TokenStore.REFRESH))
        assertFalse("and does not sit on a spinner", model.state.value.isStarting)
    }

    // ---- deleting the account ----

    private fun signedIn(): Pair<FakeStore, Session> {
        val store = FakeStore()
        val session = Session(store)
        session.set(Tokens("a", "r"))
        return store to session
    }

    @Test
    fun `deleting the account signs them out and takes the tokens with it`() = runTest(dispatcher.scheduler) {
        val (store, session) = signedIn()
        var sent: DeleteAccountRequest? = null
        val model = SessionViewModel(object : FakeFishersApi() {
            override suspend fun deleteAccount(body: DeleteAccountRequest) { sent = body }
        }, session)
        var failure: String? = null

        model.deleteAccount("hunter22") { failure = it }
        advanceUntilIdle()

        assertEquals("the password is sent, so a stolen session is not enough", "hunter22", sent?.password)
        assertFalse(model.state.value.isAuthenticated)
        assertNull(store.get(TokenStore.ACCESS))
        assertNull(store.get(TokenStore.REFRESH))
        assertNull("and nothing is reported, because nothing went wrong", failure)
    }

    /**
     * An account that signs in with Google has no password to type, and the
     * server accepts the live session instead — but only if the field is
     * absent. An empty string would be checked against nothing and refused.
     */
    @Test
    fun `a blank password goes up as absent`() = runTest(dispatcher.scheduler) {
        val (_, session) = signedIn()
        var sent: DeleteAccountRequest? = null
        val model = SessionViewModel(object : FakeFishersApi() {
            override suspend fun deleteAccount(body: DeleteAccountRequest) { sent = body }
        }, session)

        model.deleteAccount("") { }
        advanceUntilIdle()

        assertNull(sent?.password)
    }

    @Test
    fun `a wrong password says so and leaves them signed in`() = runTest(dispatcher.scheduler) {
        val (store, session) = signedIn()
        val model = SessionViewModel(object : FakeFishersApi() {
            override suspend fun deleteAccount(body: DeleteAccountRequest) = throw unauthorized()
        }, session)
        var failure: String? = null

        model.deleteAccount("nope") { failure = it }
        advanceUntilIdle()

        assertEquals("That password does not match.", failure)
        assertEquals("still signed in — nothing was deleted", "a", store.get(TokenStore.ACCESS))
    }

    @Test
    fun `no signal says the account could not be deleted`() = runTest(dispatcher.scheduler) {
        val (store, session) = signedIn()
        val model = SessionViewModel(object : FakeFishersApi() {
            override suspend fun deleteAccount(body: DeleteAccountRequest) =
                throw java.io.IOException("down")
        }, session)
        var failure: String? = null

        model.deleteAccount("pw") { failure = it }
        advanceUntilIdle()

        assertEquals("could not delete the account — try again", failure)
        assertEquals("a", store.get(TokenStore.ACCESS))
    }

    // ---- continue with Google ----

    @Test
    fun `the button is offered only when the server has Google on and names a client`() = runTest(dispatcher.scheduler) {
        suspend fun offered(config: () -> GoogleConfig): String? {
            val model = SessionViewModel(object : FakeFishersApi() {
                override suspend fun googleConfig() = config()
            }, Session(FakeStore()))
            model.loadGoogle()
            advanceUntilIdle()
            return model.googleClientId.value
        }

        assertEquals("web-id", offered { GoogleConfig(enabled = true, clientId = "web-id") })
        assertNull("switched off", offered { GoogleConfig(enabled = false, clientId = "web-id") })
        assertNull("on, but nothing to ask Google with", offered { GoogleConfig(enabled = true) })
        assertNull("a blank id is no id", offered { GoogleConfig(enabled = true, clientId = " ") })
        assertNull("the iPhone's id is no use here", offered { GoogleConfig(enabled = true, iosClientId = "ios-id") })
    }

    /** Email still works, so the form must not say anything about a button nobody asked for. */
    @Test
    fun `an unreachable server just leaves the button off`() = runTest(dispatcher.scheduler) {
        val model = SessionViewModel(object : FakeFishersApi() {
            override suspend fun googleConfig(): GoogleConfig = throw java.io.IOException("down")
        }, Session(FakeStore()))

        model.loadGoogle()
        advanceUntilIdle()

        assertNull(model.googleClientId.value)
        assertNull("and says nothing", model.state.value.error)
    }

    @Test
    fun `a Google token signs them in, and the server is the one that checks it`() = runTest(dispatcher.scheduler) {
        val store = FakeStore()
        var sent: GoogleSignInRequest? = null
        val model = SessionViewModel(object : FakeFishersApi() {
            override suspend fun googleSignIn(body: GoogleSignInRequest): AuthTokens {
                sent = body
                return tokens(alice)
            }
        }, Session(store))

        model.signInWithGoogle("id-token-from-google")
        advanceUntilIdle()

        assertEquals("id-token-from-google", sent?.credential)
        assertTrue(model.state.value.isAuthenticated)
        assertEquals(alice, model.state.value.user)
        assertEquals("a", store.get(TokenStore.ACCESS))
    }

    /** A 401 here means Google did not vouch for it, not that a password was wrong. */
    @Test
    fun `Google not confirming the token does not blame a password nobody typed`() = runTest(dispatcher.scheduler) {
        val model = SessionViewModel(object : FakeFishersApi() {
            override suspend fun googleSignIn(body: GoogleSignInRequest): AuthTokens = throw unauthorized()
        }, Session(FakeStore()))

        model.signInWithGoogle("forged")
        advanceUntilIdle()

        assertEquals("Google sign-in did not work — try again", model.state.value.error)
        assertFalse(model.state.value.isAuthenticated)
    }

    @Test
    fun `a failure before there is a token is said where the form says everything else`() = runTest(dispatcher.scheduler) {
        val model = SessionViewModel(FakeFishersApi(), Session(FakeStore()))

        model.googleFailed("There is no Google account on this phone.")

        assertEquals("There is no Google account on this phone.", model.state.value.error)
        assertFalse(model.state.value.isLoading)
    }
}

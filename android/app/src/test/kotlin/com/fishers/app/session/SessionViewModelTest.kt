package com.fishers.app.session

import com.fishers.app.FakeFishersApi
import com.fishers.app.net.AuthTokens
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
import org.junit.Test
import retrofit2.HttpException
import retrofit2.Response

@OptIn(ExperimentalCoroutinesApi::class)
class SessionViewModelTest {

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
}

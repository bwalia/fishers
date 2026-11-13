package com.fishers.app.clubs

import com.fishers.app.EnglishStrings
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

@OptIn(ExperimentalCoroutinesApi::class)
class CreateClubTest {
    @get:Rule val english = EnglishStrings()

    // One scheduler for runTest and the view model's dispatcher — see ClubsTest.
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private class Recording : FakeClubsApi() {
        var sent: CreateClubBody? = null
        override suspend fun createClub(body: CreateClubBody): Club {
            sent = body
            return Club("new-club", body.name, body.sportTypes)
        }
    }

    @Test
    fun `the form says what is missing before it lets anybody save`() {
        val model = CreateClubViewModel(FakeClubsApi())
        assertEquals("Give the club a name to continue.", model.state.value.missing)
        assertFalse(model.state.value.canSave)

        model.setName(" L ")
        assertEquals("one letter and spaces is not a name", "Give the club a name to continue.", model.state.value.missing)

        model.setName("Lords CC")
        model.toggleSport("cricket")
        assertEquals("Pick at least one sport.", model.state.value.missing)

        model.toggleSport("cricket")
        assertNull(model.state.value.missing)
        assertTrue(model.state.value.canSave)
    }

    @Test
    fun `a save sends what the API takes, tidied`() = runTest(dispatcher.scheduler) {
        val api = Recording()
        val model = CreateClubViewModel(api)
        model.setName("  Lords CC ")
        model.toggleSport("tennis")
        model.setPublic(true)
        model.setDescription("   ")
        model.setInformal(true)

        model.create()
        advanceUntilIdle()

        val sent = api.sent!!
        assertEquals("Lords CC", sent.name)
        // The picker's order, not the order they were tapped in.
        assertEquals(listOf("cricket", "tennis"), sent.sportTypes)
        assertEquals("public", sent.visibility)
        assertNull("a blank description is no description", sent.description)
        assertTrue(sent.isInformalGroup)
        assertEquals("new-club", model.state.value.created?.id)
    }

    @Test
    fun `an invite-only club is what you get unless you say otherwise`() = runTest(dispatcher.scheduler) {
        val api = Recording()
        val model = CreateClubViewModel(api)
        model.setName("Southall Strikers")
        model.setDescription(" Sunday friendlies ")
        model.create()
        advanceUntilIdle()

        assertEquals("invite_only", api.sent!!.visibility)
        assertEquals("Sunday friendlies", api.sent!!.description)
        assertFalse(api.sent!!.isInformalGroup)
    }

    @Test
    fun `only the sports this deployment offers are offered`() = runTest(dispatcher.scheduler) {
        val model = CreateClubViewModel(object : FakeClubsApi() {
            override suspend fun sports() = OfferedSports(offered = listOf("cricket"), all = ALL_SPORTS)
        })
        model.toggleSport("football")

        model.loadSports()
        advanceUntilIdle()

        assertEquals(listOf("cricket"), model.state.value.offered)
        assertEquals("football is not on offer here, so it is not kept", setOf("cricket"), model.state.value.sports)
    }

    @Test
    fun `not hearing which sports are offered leaves them all`() = runTest(dispatcher.scheduler) {
        val model = CreateClubViewModel(object : FakeClubsApi() {
            override suspend fun sports(): OfferedSports = throw java.io.IOException("offline")
        })
        model.loadSports()
        advanceUntilIdle()
        assertEquals(ALL_SPORTS, model.state.value.offered)
    }

    /**
     * Whoever starts a club runs it, so the server wants a confirmed account.
     * That is a step to take, not a dead end, and the form says so in the
     * server's own words.
     */
    @Test
    fun `an unconfirmed account is told to confirm, not that something broke`() = runTest(dispatcher.scheduler) {
        val model = CreateClubViewModel(object : FakeClubsApi() {
            override suspend fun createClub(body: CreateClubBody): Club =
                throw refused(403, "confirm your email or phone number first — it takes a minute", "unverified")
        })
        model.setName("Lords CC")
        model.create()
        advanceUntilIdle()

        val state = model.state.value
        assertTrue(state.needsVerifying)
        assertEquals("confirm your email or phone number first — it takes a minute", state.error)
        assertFalse(state.isSaving)
        assertNull(state.created)
    }

    @Test
    fun `a sport the server will not take comes back in its words`() = runTest(dispatcher.scheduler) {
        val model = CreateClubViewModel(object : FakeClubsApi() {
            override suspend fun createClub(body: CreateClubBody): Club =
                throw refused(400, "football is not offered here")
        })
        model.setName("Lords CC")
        model.create()
        advanceUntilIdle()

        assertFalse(model.state.value.needsVerifying)
        assertEquals("football is not offered here", model.state.value.error)
    }
}

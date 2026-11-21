package com.fishers.app.fixtures

import com.fishers.app.EnglishStrings
import com.fishers.app.clubs.Club
import com.fishers.app.clubs.Team
import com.fishers.app.payments.CostMode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

/** The optional Cost section on the schedule form: sent with POST /events, asked about above £100 a head. */
@OptIn(ExperimentalCoroutinesApi::class)
class ScheduleCostTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val now = Instant.parse("2026-09-23T12:00:00Z")
    private val london = ZoneId.of("Europe/London")
    private val lords = Club("lords", "Lords CC", sportTypes = listOf("cricket"))

    /** What `Network` sends with: nulls left out, defaults kept. */
    private val wire = Json {
        explicitNulls = false
        encodeDefaults = true
    }

    private class Secretary(private val club: Club) : FakeFixturesApi() {
        val sent = mutableListOf<CreateEventBody>()
        override suspend fun clubs() = listOf(club)
        override suspend fun myRole(clubId: String) = ClubRole(permissions = listOf("manage_events"))
        override suspend fun teams(clubId: String) = listOf(Team("t1", clubId, "1st XI"))
        override suspend fun venues(clubId: String) = emptyList<Venue>()
        override suspend fun createEvent(body: CreateEventBody): FishersEvent {
            sent += body
            return FishersEvent(id = "e${sent.size}", clubId = body.clubId, title = body.title, startAt = body.startAt)
        }
    }

    private fun TestScope.form(api: Secretary, nets: Boolean): CreateFixtureViewModel {
        val model = CreateFixtureViewModel(api, "lords", london) { now }
        if (nets) model.setWhat(EventSubtype.Nets) else model.setOppositionName("Hemel")
        model.load()
        advanceUntilIdle()
        return model
    }

    @Test
    fun `no cost is what it always sent`() = runTest(dispatcher.scheduler) {
        val api = Secretary(lords)
        val model = form(api, nets = false)
        model.save()
        advanceUntilIdle()

        val json = wire.encodeToJsonElement(CreateEventBody.serializer(), api.sent.single()).jsonObject
        assertFalse("no cost fields at all", json.keys.any { it.startsWith("cost_") })
    }

    @Test
    fun `a match fee is sent in pence with its mode`() = runTest(dispatcher.scheduler) {
        val api = Secretary(lords)
        val model = form(api, nets = false)
        model.setCostMode(CostMode.PerPlayer)
        model.setCostAmount("5")
        model.save()
        advanceUntilIdle()

        val body = api.sent.single()
        assertEquals("per_player", body.costMode)
        assertEquals(500L, body.costAmountCents)
        val json = wire.encodeToJsonElement(CreateEventBody.serializer(), body).jsonObject
        assertEquals("\"per_player\"", json["cost_mode"].toString())
        assertEquals("500", json["cost_amount_cents"].toString())
    }

    @Test
    fun `every week of a nets series carries the same cost`() = runTest(dispatcher.scheduler) {
        val api = Secretary(lords)
        val model = form(api, nets = true)
        model.setRepeatWeekly(true)
        model.setWeeks(3)
        model.setCostMode(CostMode.SplitTotal)
        model.setCostAmount("60.00")
        model.save()
        advanceUntilIdle()

        assertEquals(3, api.sent.size)
        assertTrue(api.sent.all { it.costMode == "split_total" && it.costAmountCents == 6000L })
    }

    @Test
    fun `a cost chosen and not typed, or typed wrong, holds the form`() = runTest(dispatcher.scheduler) {
        val api = Secretary(lords)
        val model = form(api, nets = true)
        model.setCostMode(CostMode.SplitTotal)
        assertEquals(listOf("the cost"), model.missing())
        assertNull("nothing typed is not yet wrong", model.state.value.costProblem)

        model.setCostAmount("7.505")
        assertEquals("Type an amount, like 7.50.", model.state.value.costProblem)
        model.save()
        advanceUntilIdle()
        assertTrue(api.sent.isEmpty())

        model.setCostMode(null)
        assertTrue("no cost after all", model.missing().isEmpty())
    }

    @Test
    fun `above 100 a head it asks first, and sends only once told yes`() = runTest(dispatcher.scheduler) {
        val api = Secretary(lords)
        val model = form(api, nets = false)
        model.setCostMode(CostMode.PerPlayer)
        model.setCostAmount("150")
        model.save()
        advanceUntilIdle()

        assertEquals(15_000L, model.state.value.confirmingCost)
        assertTrue("nothing sent until somebody says yes", api.sent.isEmpty())

        model.dismissCostConfirm()
        assertNull(model.state.value.confirmingCost)
        assertTrue(api.sent.isEmpty())

        model.save()
        model.confirmCost()
        advanceUntilIdle()
        assertEquals(15_000L, api.sent.single().costAmountCents)

        // A new amount is a new question.
        model.setCostAmount("200")
        assertFalse(model.state.value.costConfirmed)
    }
}

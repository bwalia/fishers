package com.fishers.app.fixtures

import com.fishers.app.EnglishStrings
import com.fishers.app.clubs.Club
import com.fishers.app.clubs.Team
import com.fishers.app.payments.CostMode
import com.fishers.app.payments.MoneySettings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
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
import java.time.Instant
import java.time.ZoneId

/** The schedule form starts from the club's usual price: nets from the nets price, a match from the match fee. */
@OptIn(ExperimentalCoroutinesApi::class)
class UsualPriceScheduleTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val now = Instant.parse("2026-09-23T12:00:00Z")
    private val london = ZoneId.of("Europe/London")
    private val lords = Club("lords", "Lords CC", sportTypes = listOf("cricket"))
    private val usual = MoneySettings(defaultNetsMode = "split_total", defaultNetsCents = 6000, defaultMatchFeeCents = 500)

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

    private fun TestScope.form(
        api: Secretary,
        nets: Boolean,
        prices: suspend (String) -> MoneySettings? = { usual },
    ): CreateFixtureViewModel {
        val model = CreateFixtureViewModel(api, "lords", london, usualPrices = prices) { now }
        if (nets) model.setWhat(EventSubtype.Nets) else model.setOppositionName("Hemel")
        model.load()
        advanceUntilIdle()
        return model
    }

    @Test
    fun `nets start from the usual nets price, and it is sent as it is`() = runTest(dispatcher.scheduler) {
        val api = Secretary(lords)
        val model = form(api, nets = true)
        val s = model.state.value
        assertEquals(CostMode.SplitTotal, s.costMode)
        assertEquals("60", s.costAmount)
        assertTrue(s.costFromUsual)

        model.save()
        advanceUntilIdle()
        assertEquals("split_total", api.sent.single().costMode)
        assertEquals(6000L, api.sent.single().costAmountCents)
    }

    @Test
    fun `a match starts from the match fee, a head`() = runTest(dispatcher.scheduler) {
        val model = form(Secretary(lords), nets = false)
        assertEquals(CostMode.PerPlayer, model.state.value.costMode)
        assertEquals("5", model.state.value.costAmount)
    }

    @Test
    fun `switching between nets and a match follows the usual prices, and training has none`() = runTest(dispatcher.scheduler) {
        val model = form(Secretary(lords), nets = false)
        model.setWhat(EventSubtype.Nets)
        assertEquals(CostMode.SplitTotal, model.state.value.costMode)
        assertEquals("60", model.state.value.costAmount)

        model.setWhat(EventSubtype.Training)
        assertNull("the nets price taken back out", model.state.value.costMode)
        assertEquals("", model.state.value.costAmount)
        assertFalse(model.state.value.costFromUsual)
    }

    @Test
    fun `a cost somebody chose is theirs, whatever they schedule`() = runTest(dispatcher.scheduler) {
        val model = form(Secretary(lords), nets = true)
        model.setCostAmount("45")
        assertFalse(model.state.value.costFromUsual)
        model.setWhat(null)
        assertEquals("45", model.state.value.costAmount)
        assertEquals(CostMode.SplitTotal, model.state.value.costMode)

        model.setCostMode(null)
        model.setWhat(EventSubtype.Nets)
        assertNull("no cost was a choice too", model.state.value.costMode)
    }

    @Test
    fun `no usual prices, or none this person may read, is no cost to start with`() = runTest(dispatcher.scheduler) {
        val none = form(Secretary(lords), nets = true, prices = { null })
        assertNull(none.state.value.costMode)

        val refused = form(Secretary(lords), nets = true, prices = { error("403") })
        assertNull(refused.state.value.costMode)
        assertNull(refused.state.value.error)
    }

    @Test
    fun `a big usual price is still asked about before it is sent`() = runTest(dispatcher.scheduler) {
        val api = Secretary(lords)
        val model = form(api, nets = false, prices = { MoneySettings(defaultMatchFeeCents = 15_000) })
        model.save()
        advanceUntilIdle()
        assertEquals(15_000L, model.state.value.confirmingCost)
        assertTrue(api.sent.isEmpty())
    }
}

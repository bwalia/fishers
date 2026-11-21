package com.fishers.app.payments

import com.fishers.app.EnglishStrings
import com.fishers.app.clubs.refused
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
import java.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class EventMoneyViewModelTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    /** After both demo sessions ended. */
    private val afterwards = Instant.parse("2026-11-21T12:00:00Z")

    private val aman = "285e2195-e3a0-4a7c-b652-a2d239430a8d"
    private val josh = "cb6f1ac7-3e51-4b53-8826-05acfdd14b55"
    private val ravi = "1053c505-eac3-4b82-a124-e0124e0550b9"
    private val tom = "1dda4e43-935f-461e-b53d-ef09a8813238"

    /** Aman, the secretary, on an event: [money] is what `GET /bill` answers, and every preview and send is kept. */
    private open class Secretary(var money: EventMoney) : FakePaymentsApi() {
        val previews = mutableListOf<BillBody>()
        val sent = mutableListOf<BillBody>()
        var sendFails: Throwable? = null
        override suspend fun bill(eventId: String) = money
        override suspend fun previewBill(eventId: String, body: BillBody): BillPreview {
            previews += body
            val people = body.attendees.size + body.guests.size
            return BillPreview(shares = List(people) { PreviewShare(name = "p$it", amountCents = 500) }, totalCents = 500L * people)
        }
        override suspend fun sendBill(eventId: String, body: BillBody): EventMoney {
            sent += body
            sendFails?.let { sendFails = null; throw it }
            return Captured.read("bill_billed_admin")
        }
    }

    private fun model(api: FakePaymentsApi, now: Instant = afterwards) = EventMoneyViewModel(api, "e1", now = { now }, previewDelayMs = 300)

    @Test
    fun `an ended, costed, unbilled session opens on who came, ticked as the server suggests`() = runTest(dispatcher.scheduler) {
        val api = Secretary(Captured.read("bill_unbilled_admin"))
        val model = model(api)
        model.load()
        advanceUntilIdle()

        val state = model.state.value
        assertTrue(state.choosing)
        assertEquals(setOf(josh, ravi, tom), state.ticked)
        assertEquals("the total is asked for straight away", listOf(josh, ravi, tom).sorted(), api.previews.single().attendees)
        assertEquals("£15.00 between 3: £5.00 each", state.preview?.summary)
    }

    @Test
    fun `before the session is over, who came waits to be opened`() = runTest(dispatcher.scheduler) {
        val api = Secretary(Captured.read("bill_unbilled_admin"))
        val model = model(api, now = Instant.parse("2026-11-20T00:00:00Z"))
        model.load()
        advanceUntilIdle()
        assertFalse(model.state.value.choosing)
        assertTrue(api.previews.isEmpty())

        model.startChoosing()
        advanceUntilIdle()
        assertTrue(model.state.value.choosing)
        assertEquals(1, api.previews.size)
    }

    @Test
    fun `ticks and guests are previewed once the taps stop, then sent as a new bill`() = runTest(dispatcher.scheduler) {
        val api = Secretary(Captured.read("bill_unbilled_admin"))
        val model = model(api)
        model.load()
        advanceUntilIdle()

        model.toggle(aman)
        model.toggle(tom)
        model.addGuest("  Guest   Gary ")
        model.addGuest("guest gary")
        advanceUntilIdle()

        assertEquals("one preview for the burst of taps, after the first", 2, api.previews.size)
        assertEquals(listOf(aman, josh, ravi).sorted(), api.previews.last().attendees)
        assertEquals("the same guest twice is one guest", listOf("Guest Gary"), api.previews.last().guests)

        model.send()
        advanceUntilIdle()

        val body = api.sent.single()
        assertNull("a first bill has no version", body.version)
        assertEquals(listOf("Guest Gary"), body.guests)
        val state = model.state.value
        assertFalse(state.choosing)
        assertTrue(state.bill != null)
        assertEquals("Bill sent. Everyone on it has been told their share.", state.message)
    }

    @Test
    fun `nobody ticked is never sent`() = runTest(dispatcher.scheduler) {
        val api = Secretary(Captured.read("bill_unbilled_admin"))
        val model = model(api)
        model.load()
        advanceUntilIdle()
        listOf(josh, ravi, tom).forEach(model::toggle)
        advanceUntilIdle()

        assertFalse(model.state.value.canSend)
        assertEquals("Nobody's ticked as coming.", model.state.value.previewProblem)
        model.send()
        advanceUntilIdle()
        assertTrue(api.sent.isEmpty())
    }

    @Test
    fun `a re-split sends the version it was read at`() = runTest(dispatcher.scheduler) {
        val api = Secretary(Captured.read("bill_billed_admin"))
        val model = model(api)
        model.load()
        advanceUntilIdle()
        assertFalse("billed: nothing to tick until asked", model.state.value.choosing)

        model.startChoosing()
        model.toggle(tom)
        advanceUntilIdle()
        model.send()
        advanceUntilIdle()

        assertEquals(1, api.sent.single().version)
        assertEquals(listOf(aman, josh, ravi).sorted(), api.sent.single().attendees)
        assertEquals("Bill changed. Anyone whose share changed has been told.", model.state.value.message)
    }

    @Test
    fun `somebody else changed it first, reload, and say the server's sentence`() = runTest(dispatcher.scheduler) {
        val sentence = "Somebody changed this bill a moment ago (it's now version 2). Reload it and try again."
        var reads = 0
        val counting = object : Secretary(Captured.read("bill_billed_admin")) {
            override suspend fun bill(eventId: String): EventMoney {
                reads++
                return money
            }
        }.apply { sendFails = refused(409, sentence, "version_conflict") }
        val model = model(counting)
        model.load()
        advanceUntilIdle()
        model.startChoosing()
        advanceUntilIdle()

        model.send()
        advanceUntilIdle()

        val state = model.state.value
        assertEquals(sentence, state.error)
        assertEquals("read once, then again after the conflict", 2, reads)
        assertFalse(state.choosing)
        assertFalse(state.isBusy)
    }

    @Test
    fun `letting somebody off sends the reason and reads the bill again`() = runTest(dispatcher.scheduler) {
        val waived = mutableListOf<Pair<String, String?>>()
        val api = object : Secretary(Captured.read("bill_billed_admin")) {
            override suspend fun waiveShare(shareId: String, body: ReasonBody): Share {
                waived += shareId to body.reason
                return money.shares.first { it.id == shareId }.copy(stateName = "waived")
            }
        }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        val ravisShare = model.state.value.money!!.shares.first { it.name == "Ravi Sharma" }
        assertTrue(ravisShare.canLetOff)

        model.letOff(ravisShare, "  Junior  ")
        advanceUntilIdle()

        assertEquals(listOf(ravisShare.id to "Junior"), waived)
        assertEquals("Ravi Sharma has been let off.", model.state.value.message)
    }

    @Test
    fun `setting a cost on a weekly series says how many later weeks took it`() = runTest(dispatcher.scheduler) {
        val costs = mutableListOf<CostBody>()
        val api = object : Secretary(Captured.read("bill_unbilled_admin")) {
            override suspend fun setCost(eventId: String, body: CostBody): CostResponse {
                costs += body
                return CostResponse(EventCost("split_total", body.amountCents), seriesUpdated = 3)
            }
        }
        val model = model(api, now = Instant.parse("2026-11-20T00:00:00Z"))
        model.load()
        advanceUntilIdle()

        model.saveCost(CostMode.SplitTotal, 6000, " Lane hire ", applyToSeries = true)
        advanceUntilIdle()

        assertEquals(CostBody("split_total", 6000, "Lane hire", applyToSeries = true), costs.single())
        assertEquals("Cost saved, here and on 3 later weeks.", model.state.value.message)
    }

    @Test
    fun `already billed when the cost was changed, reload and say so`() = runTest(dispatcher.scheduler) {
        val api = object : Secretary(Captured.read("bill_unbilled_admin")) {
            override suspend fun setCost(eventId: String, body: CostBody): CostResponse {
                money = Captured.read("bill_billed_admin")
                throw refused(409, "This one's already been billed. Re-split the bill to change it.", "already_billed")
            }
        }
        val model = model(api)
        model.load()
        advanceUntilIdle()

        model.saveCost(CostMode.PerPlayer, 700, null, applyToSeries = false)
        advanceUntilIdle()

        val state = model.state.value
        assertEquals("This one's already been billed. Re-split the bill to change it.", state.error)
        assertTrue("the reload shows the bill somebody else sent", state.bill != null)
    }

    @Test
    fun `a visiting player's 403 leaves the section out, quietly`() = runTest(dispatcher.scheduler) {
        val api = object : FakePaymentsApi() {
            override suspend fun bill(eventId: String): EventMoney = throw refused(403, "You're not a member of this club", "not_member")
        }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        assertNull(model.state.value.money)
        assertNull(model.state.value.error)
    }

    @Test
    fun `members nobody asked are offered, unticked, after those who were`() = runTest(dispatcher.scheduler) {
        val base = Captured.read<EventMoney>("bill_unbilled_admin")
        val walkIn = Candidate(userId = "u-new", name = "Nick New", rsvp = "not_invited", suggested = false)
        val api = Secretary(base.copy(candidates = base.candidates + walkIn))
        val model = model(api)
        model.load()
        advanceUntilIdle()

        val (asked, others) = model.state.value.money!!.candidates.partition { it.wasAsked }
        assertEquals(5, asked.size)
        assertEquals(listOf("Nick New"), others.map { it.name })
        assertFalse("u-new" in model.state.value.ticked)
    }
}

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
import java.io.IOException
import java.time.Instant

/** A billed event, for whoever runs it: Share to WhatsApp, Copy link, switch it off, and Who paid cash? */
@OptIn(ExperimentalCoroutinesApi::class)
class EventMoneySharingTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val afterwards = Instant.parse("2026-11-21T12:00:00Z")

    // Share ids on the demo bill: Aman and Ravi owe, Tom is waiting, Josh paid.
    private val amanShare = "2e85b72d-c658-4245-a44f-4823907f9a8e"
    private val raviShare = "7c5f2847-06a4-46a8-9b86-0aab4c69f714"

    /** Aman, the secretary, on Friday nets once billed. */
    private open class Aman : FakePaymentsApi() {
        var money = Captured.read<EventMoney>("bill_billed_admin")
        var link = Captured.read<BillLink>("stepA_bill_link")
        var links = 0
        var loads = 0
        var linkFails: Throwable? = null
        val disabled = mutableListOf<String>()
        val cash = mutableListOf<Pair<String, CashBody>>()
        var cashFails: Throwable? = null
        var received = true
        override suspend fun bill(eventId: String): EventMoney {
            loads++
            return money
        }
        override suspend fun billLink(eventId: String): BillLink {
            links++
            linkFails?.let { linkFails = null; throw it }
            return link
        }
        override suspend fun disableBillLink(eventId: String): DisabledLinks {
            disabled += eventId
            return DisabledLinks(1)
        }
        override suspend fun cashAtGround(eventId: String, idempotencyKey: String, body: CashBody): CashRecorded {
            cash += idempotencyKey to body
            cashFails?.let { cashFails = null; throw it }
            return CashRecorded(recorded = body.shareIds.size, totalCents = 1500L * body.shareIds.size, received = received)
        }
    }

    private fun model(api: FakePaymentsApi): EventMoneyViewModel {
        var n = 0
        return EventMoneyViewModel(api, "e1", now = { afterwards }, keys = AttemptKeys { "key-${++n}" })
    }

    @Test
    fun `share the bill hands the server's bill message to the phone, once`() = runTest(dispatcher.scheduler) {
        val api = Aman()
        val model = model(api)
        model.load()
        advanceUntilIdle()

        model.share(LinkUse.Bill)
        advanceUntilIdle()

        val out = model.state.value.outgoing as Outgoing.Share
        assertEquals(api.link.billMessage, out.text)
        assertNull("no message: the share sheet is the answer", model.state.value.message)
        model.handled()
        assertNull(model.state.value.outgoing)
    }

    @Test
    fun `remind who hasn't paid asks again, so it names whoever still owes now`() = runTest(dispatcher.scheduler) {
        val api = Aman()
        val model = model(api)
        model.load()
        advanceUntilIdle()

        model.share(LinkUse.Bill)
        advanceUntilIdle()
        model.handled()
        api.link = api.link.copy(reminderMessage = "Still to pay for Friday nets, Fri 20 Nov: Tom.\nTap to pay: x")
        model.share(LinkUse.Reminder)
        advanceUntilIdle()

        assertEquals(2, api.links)
        assertEquals("Still to pay for Friday nets, Fri 20 Nov: Tom.\nTap to pay: x", (model.state.value.outgoing as Outgoing.Share).text)
    }

    @Test
    fun `copy link puts the url on the clipboard and says so`() = runTest(dispatcher.scheduler) {
        val api = Aman()
        val model = model(api)
        model.load()
        advanceUntilIdle()
        model.share(LinkUse.CopyLink)
        advanceUntilIdle()
        assertEquals(Outgoing.Copy(api.link.url), model.state.value.outgoing)
        assertEquals("Link copied.", model.state.value.message)
    }

    @Test
    fun `no bill yet is the server's sentence, and the page is read again`() = runTest(dispatcher.scheduler) {
        val api = Aman().apply { linkFails = refused(409, "Send the bill first, then share it.", "no_bill") }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        val loadsBefore = api.loads
        model.share(LinkUse.Bill)
        advanceUntilIdle()
        assertEquals("Send the bill first, then share it.", model.state.value.error)
        assertNull(model.state.value.outgoing)
        assertEquals(loadsBefore + 1, api.loads)
    }

    @Test
    fun `switching the link off says how to make a new one`() = runTest(dispatcher.scheduler) {
        val api = Aman()
        val model = model(api)
        model.load()
        advanceUntilIdle()
        model.switchLinkOff()
        advanceUntilIdle()
        assertEquals(listOf("e1"), api.disabled)
        assertEquals("The link is off. Share the bill again for a new one.", model.state.value.message)
    }

    @Test
    fun `who paid cash lists only those who still owe`() = runTest(dispatcher.scheduler) {
        val model = model(Aman())
        model.load()
        advanceUntilIdle()
        val state = model.state.value
        assertTrue(state.anyoneOwes)
        assertEquals(listOf("Aman Gill", "Ravi Sharma"), state.cashCandidates.map { it.name })
    }

    @Test
    fun `a money admin's ticks are saved as received, with one key for the attempt`() = runTest(dispatcher.scheduler) {
        val api = Aman()
        val model = model(api)
        model.load()
        advanceUntilIdle()

        model.startCash()
        model.toggleCash(raviShare)
        model.toggleCash(amanShare)
        assertEquals(setOf(raviShare, amanShare), model.state.value.cashTicked)
        model.saveCash()
        advanceUntilIdle()

        val (key, body) = api.cash.single()
        assertEquals("key-1", key)
        assertEquals("sent in a steady order", listOf(amanShare, raviShare), body.shareIds)
        val state = model.state.value
        assertFalse(state.cashOpen)
        assertTrue(state.cashTicked.isEmpty())
        assertEquals("Cash from 2 people saved: £30.00.", state.message)
    }

    @Test
    fun `a captain's ticks wait for the treasurer, and the sentence says so`() = runTest(dispatcher.scheduler) {
        val api = Aman().apply { received = false }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        model.startCash()
        model.toggleCash(raviShare)
        model.saveCash()
        advanceUntilIdle()
        assertEquals("Cash from 1 person noted: £15.00. The treasurer will tick it off once they have it.", model.state.value.message)
    }

    @Test
    fun `a retry after no signal sends the same key, and the list stays open`() = runTest(dispatcher.scheduler) {
        val api = Aman().apply { cashFails = IOException("no signal") }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        model.startCash()
        model.toggleCash(raviShare)
        model.saveCash()
        advanceUntilIdle()
        assertTrue("still open to try again", model.state.value.cashOpen)
        assertTrue(model.state.value.error != null)

        model.saveCash()
        advanceUntilIdle()
        assertEquals(listOf("key-1", "key-1"), api.cash.map { it.first })
        assertFalse(model.state.value.cashOpen)
    }

    @Test
    fun `nothing ticked sends nothing, and not now forgets the ticks`() = runTest(dispatcher.scheduler) {
        val api = Aman()
        val model = model(api)
        model.load()
        advanceUntilIdle()
        model.startCash()
        model.saveCash()
        advanceUntilIdle()
        assertTrue(api.cash.isEmpty())
        model.toggleCash(raviShare)
        model.stopCash()
        assertFalse(model.state.value.cashOpen)
        assertTrue(model.state.value.cashTicked.isEmpty())
    }

    @Test
    fun `cash already paid is said plainly, not as a failure`() = runTest(dispatcher.scheduler) {
        val api = object : Aman() {
            override suspend fun cashAtGround(eventId: String, idempotencyKey: String, body: CashBody) = CashRecorded(0, 0, true)
        }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        model.startCash()
        model.toggleCash(raviShare)
        model.saveCash()
        advanceUntilIdle()
        assertEquals("Nothing new to save. They'd already paid, or said they had.", model.state.value.message)
        assertNull(model.state.value.error)
    }
}

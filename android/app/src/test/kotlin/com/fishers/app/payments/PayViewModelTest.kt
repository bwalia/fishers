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
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.io.IOException

@OptIn(ExperimentalCoroutinesApi::class)
class PayViewModelTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val club = "814f6802-c8e0-44c2-a9f7-f2a86c06c1d7"

    /** Ravi, who owes £15. Each claim's key and body is kept; [fail] decides what the next claim meets. */
    private open class Ravi : FakePaymentsApi() {
        val keys = mutableListOf<String>()
        val bodies = mutableListOf<ClaimBody>()
        var fail: Throwable? = null
        var screen = Captured.read<PayScreen>("pay_screen")
        var loads = 0
        override suspend fun payScreen(clubId: String): PayScreen {
            loads++
            return screen
        }
        override suspend fun claimPayment(clubId: String, idempotencyKey: String, body: ClaimBody): Payment {
            keys += idempotencyKey
            bodies += body
            fail?.let { fail = null; throw it }
            screen = Captured.read("pay_screen_waiting")
            return screen.claims.single()
        }
    }

    private fun model(api: FakePaymentsApi): PayViewModel {
        var n = 0
        return PayViewModel(api, club, AttemptKeys { "key-${++n}" })
    }

    @Test
    fun `I've paid sends a transfer claim with a key, and the screen shows it waiting`() = runTest(dispatcher.scheduler) {
        val api = Ravi()
        val model = model(api)
        model.load()
        advanceUntilIdle()
        assertTrue(model.state.value.pay!!.canPay)

        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()

        assertEquals(listOf("key-1"), api.keys)
        assertEquals("the amount is left to the server: everything owed", ClaimBody(method = "transfer"), api.bodies.single())
        val state = model.state.value
        assertEquals(1500L, state.pay!!.waitingCents)
        assertEquals(1, state.pay.claims.size)
        assertEquals("Thanks. The club will confirm it once the money has arrived.", state.message)
        assertNull(state.error)
    }

    @Test
    fun `a retry after no signal reuses the key, so the server sees one claim`() = runTest(dispatcher.scheduler) {
        val api = Ravi().apply { fail = IOException("no signal") }
        val model = model(api)
        model.load()
        advanceUntilIdle()

        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()
        assertTrue(model.state.value.error != null)

        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()

        assertEquals(listOf("key-1", "key-1"), api.keys)
        assertNull(model.state.value.error)
    }

    @Test
    fun `a double tap is one claim`() = runTest(dispatcher.scheduler) {
        val api = Ravi()
        val model = model(api)
        model.claim(PaymentMethod.Transfer)
        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()
        assertEquals(1, api.keys.size)
    }

    @Test
    fun `once the server has answered, the next claim is a new attempt with a new key`() = runTest(dispatcher.scheduler) {
        val api = Ravi()
        val model = model(api)
        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()
        model.claim(PaymentMethod.Cash)
        advanceUntilIdle()
        assertEquals(2, api.keys.size)
        assertNotEquals(api.keys[0], api.keys[1])
        assertEquals("cash", api.bodies[1].method)
    }

    @Test
    fun `nothing owed is not a failure, it reloads and says the server's words`() = runTest(dispatcher.scheduler) {
        val api = Ravi().apply {
            fail = refused(409, "You've already said you paid. The club just needs to confirm it.", "nothing_owed")
        }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        val before = api.loads

        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()

        val state = model.state.value
        assertNull(state.error)
        assertEquals("You've already said you paid. The club just needs to confirm it.", state.message)
        assertTrue("it read the screen again", api.loads > before)
        assertFalse(state.isClaiming)
    }

    @Test
    fun `undo takes a claim back and reads the screen again`() = runTest(dispatcher.scheduler) {
        val cancelled = mutableListOf<String>()
        val api = object : Ravi() {
            override suspend fun cancelClaim(paymentId: String) {
                cancelled += paymentId
                screen = Captured.read("pay_screen")
            }
        }
        api.screen = Captured.read("pay_screen_waiting")
        val model = model(api)
        model.load()
        advanceUntilIdle()

        model.undo(model.state.value.pay!!.claims.single())
        advanceUntilIdle()

        assertEquals(listOf("cf07a56d-256a-4065-93c6-e25aae04b958"), cancelled)
        assertTrue(model.state.value.pay!!.claims.isEmpty())
        assertEquals(1500L, model.state.value.pay!!.owedCents)
    }

    @Test
    fun `the dues card reads every club, and keeps its last answer through a failure`() = runTest(dispatcher.scheduler) {
        var down = false
        val api = object : FakePaymentsApi() {
            override suspend fun myDues(): Dues = if (down) throw IOException("no signal") else Captured.read("me_dues")
        }
        val dues = DuesViewModel(api)
        dues.load()
        advanceUntilIdle()
        assertEquals(1500L, dues.state.value.dues!!.owing.single().owedCents)

        down = true
        dues.load()
        advanceUntilIdle()
        assertEquals("the card does not vanish on one bad bar", 1, dues.state.value.dues!!.owing.size)
    }
}

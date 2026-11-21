package com.fishers.app.payments

import com.fishers.app.EnglishStrings
import com.fishers.app.clubs.refused
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.io.IOException

@OptIn(ExperimentalCoroutinesApi::class)
class ClubMoneyViewModelTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val club = "814f6802-c8e0-44c2-a9f7-f2a86c06c1d7"

    /** Tara, the treasurer. Everything she is sent is kept. */
    private open class Treasurer : FakePaymentsApi() {
        var overview = Captured.read<MoneyOverview>("money_overview")
        val calls = mutableListOf<String>()
        val recorded = mutableListOf<Pair<String, RecordBody>>()
        var recordFails: Throwable? = null
        override suspend fun money(clubId: String) = overview
        override suspend fun confirmPayment(paymentId: String): Payment {
            calls += "confirm:$paymentId"
            return overview.toCheck.first { it.id == paymentId }.copy(status = "confirmed")
        }
        override suspend fun rejectPayment(paymentId: String, body: ReasonBody): Payment {
            calls += "reject:$paymentId:${body.reason}"
            return overview.toCheck.first { it.id == paymentId }.copy(status = "rejected")
        }
        override suspend fun recordPayment(clubId: String, idempotencyKey: String, body: RecordBody): Payment {
            recorded += idempotencyKey to body
            recordFails?.let { recordFails = null; throw it }
            return Payment(id = "p-new", amountCents = body.amountCents, methodName = body.method ?: "cash", status = "confirmed")
        }
    }

    private fun model(api: FakePaymentsApi): ClubMoneyViewModel {
        var n = 0
        return ClubMoneyViewModel(api, club, AttemptKeys { "key-${++n}" }, saveDelayMs = 600)
    }

    @Test
    fun `a 403 means the page is not for them, in the server's words`() = runTest(dispatcher.scheduler) {
        val api = object : FakePaymentsApi() {
            override suspend fun money(clubId: String): MoneyOverview = throw refused(
                403, "Only the club owner, a secretary or a treasurer can look after the club's money", "not_money_admin",
            )
        }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        val state = model.state.value
        assertNull(state.overview)
        assertEquals("Only the club owner, a secretary or a treasurer can look after the club's money", state.notAllowed)
        assertNull(state.loadError)
    }

    @Test
    fun `received and not received each decide one payment and read the page again`() = runTest(dispatcher.scheduler) {
        val api = Treasurer()
        val model = model(api)
        model.load()
        advanceUntilIdle()
        val toms = model.state.value.overview!!.toCheck.single()

        model.confirm(toms)
        advanceUntilIdle()
        assertEquals("Marked Tom Bennett's payment as received.", model.state.value.message)

        model.reject(toms, "  Nothing with that reference  ")
        advanceUntilIdle()
        assertEquals(listOf("confirm:${toms.id}", "reject:${toms.id}:Nothing with that reference"), api.calls)
        assertEquals("Tom Bennett has been told it hasn't arrived.", model.state.value.message)
        assertTrue(model.state.value.deciding.isEmpty())
    }

    @Test
    fun `somebody else decided it first, the server's sentence, and a fresh page`() = runTest(dispatcher.scheduler) {
        var reads = 0
        val api = object : Treasurer() {
            override suspend fun money(clubId: String): MoneyOverview {
                reads++
                return overview
            }
            override suspend fun confirmPayment(paymentId: String): Payment =
                throw refused(409, "That payment was already confirmed", "already_decided")
        }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        model.confirm(model.state.value.overview!!.toCheck.single())
        advanceUntilIdle()
        assertEquals("That payment was already confirmed", model.state.value.error)
        assertEquals(2, reads)
    }

    @Test
    fun `recording cash sends who and how much with a key, reused if the signal drops`() = runTest(dispatcher.scheduler) {
        val api = Treasurer().apply { recordFails = IOException("no signal") }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        val ravi = model.state.value.overview!!.members.first { it.name == "Ravi Sharma" }

        model.record(ravi, 1500, PaymentMethod.Cash, " at the ground ")
        advanceUntilIdle()
        model.record(ravi, 1500, PaymentMethod.Cash, " at the ground ")
        advanceUntilIdle()

        assertEquals(listOf("key-1", "key-1"), api.recorded.map { it.first })
        assertEquals(
            RecordBody(userId = ravi.userId, amountCents = 1500, method = "cash", note = "at the ground"),
            api.recorded.last().second,
        )
        assertEquals("Recorded Ravi Sharma's payment.", model.state.value.message)

        model.record(ravi, 500, PaymentMethod.Transfer, null)
        advanceUntilIdle()
        assertEquals("a new payment is a new attempt", "key-2", api.recorded.last().first)
    }

    @Test
    fun `a guest is recorded by name`() = runTest(dispatcher.scheduler) {
        val api = Treasurer()
        val model = model(api)
        model.record(MemberBalance(guestName = "Guest Gary", name = "Guest Gary", owedCents = 500), 500, PaymentMethod.Cash, null)
        advanceUntilIdle()
        val body = api.recorded.single().second
        assertNull(body.userId)
        assertEquals("Guest Gary", body.guestName)
    }

    @Test
    fun `settings save once the taps stop, sending what changed`() = runTest(dispatcher.scheduler) {
        val saved = mutableListOf<MoneySettingsBody>()
        val api = object : Treasurer() {
            override suspend fun updateMoneySettings(clubId: String, body: MoneySettingsBody): MoneySettings {
                saved += body
                return MoneySettings(body.autoBill!!, body.autoBillAfterHours!!, body.roundSharesUp!!)
            }
        }
        val model = model(api)
        model.load()
        advanceUntilIdle()

        model.changeSettings { it.copy(autoBillAfterHours = 48) }
        advanceTimeBy(100)
        model.changeSettings { it.copy(roundSharesUp = true) }
        advanceUntilIdle()

        assertEquals(1, saved.size)
        assertEquals(MoneySettingsBody(autoBill = true, autoBillAfterHours = 48, roundSharesUp = true), saved.single())
        assertEquals(48, model.state.value.overview!!.settings.autoBillAfterHours)
    }

    // ---- bank details ----

    /** What `POST /payout-account` answers, by password. */
    private open class Owner : Treasurer() {
        val bodies = mutableListOf<AddBankDetailsBody>()
        override suspend fun addPayoutAccount(clubId: String, body: AddBankDetailsBody): PayoutAccounts {
            bodies += body
            return when (body.password) {
                null -> throw refused(428, "Type your password to change the club's bank details", "reauth_required")
                "wrong" -> throw refused(403, "That password doesn't match", "wrong_password")
                else -> overview.account.copy(
                    pending = PayoutAccount("new", holderName = body.holderName, last4 = body.accountNumber.takeLast(4), stateName = "pending"),
                )
            }
        }
    }

    @Test
    fun `no password, then a wrong one, the form asks again and stays open`() = runTest(dispatcher.scheduler) {
        val api = Owner()
        val model = model(api)
        model.load()
        advanceUntilIdle()
        model.openForm()

        model.saveBankDetails("Riverside Strikers CC", "20-00-00", "1234 5678", "12345678", isPersonal = false, password = "")
        advanceUntilIdle()
        var form = model.state.value.form
        assertNotNull("428 is not a reason to close the form, or to sign anybody out", form)
        assertTrue(form!!.needsPassword)
        assertEquals("Type your password to change the club's bank details", form.error)
        assertEquals("the number is sent as digits", "12345678", api.bodies.single().accountNumber)
        assertEquals("200000", api.bodies.single().sortCode)
        assertNull(api.bodies.single().password)

        model.saveBankDetails("Riverside Strikers CC", "20-00-00", "12345678", "12345678", isPersonal = false, password = "wrong")
        advanceUntilIdle()
        form = model.state.value.form
        assertNotNull(form)
        assertEquals("That password doesn't match", form!!.error)
        assertFalse(form.isSaving)

        model.saveBankDetails("Riverside Strikers CC", "20-00-00", "12345678", "12345678", isPersonal = true, password = "password123")
        advanceUntilIdle()
        val state = model.state.value
        assertNull("saved: the form closes", state.form)
        assertEquals("5678", state.overview!!.account.pending?.last4)
        assertEquals("Saved. They go live in 24 hours, and everyone who looks after the money has been told.", state.message)
        assertTrue(api.bodies.last().isPersonal)
    }

    @Test
    fun `account numbers that differ are never sent`() = runTest(dispatcher.scheduler) {
        val api = Owner()
        val model = model(api)
        model.load()
        advanceUntilIdle()
        model.openForm()
        model.saveBankDetails("Riverside", "200000", "12345678", "12345679", isPersonal = false, password = "pw")
        advanceUntilIdle()
        assertTrue(api.bodies.isEmpty())
        assertEquals("The two account numbers don't match. Check them against the bank's paperwork.", model.state.value.form?.error)
    }

    @Test
    fun `freezing sends the reason and shows what the server now holds`() = runTest(dispatcher.scheduler) {
        val reasons = mutableListOf<String?>()
        val api = object : Treasurer() {
            override suspend fun freezePayoutAccount(clubId: String, accountId: String, body: ReasonBody): PayoutAccounts {
                reasons += body.reason
                val current = overview.account.current!!
                return overview.account.copy(current = null, frozen = current.copy(stateName = "frozen", freezeReason = body.reason))
            }
        }
        val model = model(api)
        model.load()
        advanceUntilIdle()

        model.freeze(model.state.value.account!!.current!!, "  ")
        advanceUntilIdle()

        assertEquals("a blank reason is no reason", listOf<String?>(null), reasons)
        val account = model.state.value.account!!
        assertNull(account.current)
        assertEquals(PayoutState.Frozen, account.frozen?.state)
    }
}

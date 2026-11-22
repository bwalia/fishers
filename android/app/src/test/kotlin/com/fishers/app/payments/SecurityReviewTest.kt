package com.fishers.app.payments

import com.fishers.app.EnglishStrings
import com.fishers.app.clubs.refusalOf
import com.fishers.app.clubs.refused
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import retrofit2.HttpException

/**
 * §13 of docs/CLUB_PAYMENTS_V2_PLAN.md on Android: `busy` retried with the
 * same key, covered lines worded from `cover`, friends, payments made for
 * somebody else, the standing order paying this month, the overview's bill
 * kinds, the group fee's link read before it is made, and "Prices and who
 * pays" from the server.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SecurityReviewTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val club = "814f6802-c8e0-44c2-a9f7-f2a86c06c1d7"
    private val ravi = "1053c505-eac3-4b82-a124-e0124e0550b9"
    private val jas = "2f8220c1-98ea-4078-a107-1ddb132421d5"

    private fun busy() = refused(409, "Someone else is saving a payment for you right now. Try again in a moment.", "busy")

    // ---- busy: once more, a second later, with the same key ----

    /** Ravi, who owes £15. Each claim's key is kept; [failures] are what the next claims meet. */
    private open class Ravi : FakePaymentsApi() {
        val keys = mutableListOf<String>()
        val failures = ArrayDeque<Throwable>()
        var screen = Captured.read<PayScreen>("pay_screen")
        override suspend fun payScreen(clubId: String): PayScreen = screen
        override suspend fun claimPayment(clubId: String, idempotencyKey: String, body: ClaimBody): Payment {
            keys += idempotencyKey
            failures.removeFirstOrNull()?.let { throw it }
            screen = Captured.read("pay_screen_waiting")
            return screen.claims.single()
        }
    }

    private fun payModel(api: FakePaymentsApi, me: String? = ravi, forEveryone: Boolean = false): PayViewModel {
        var n = 0
        return PayViewModel(api, club, AttemptKeys { "key-${++n}" }, me = me, forEveryone = forEveryone)
    }

    @Test
    fun `busy is tried once more, quietly, a second later, with the same key`() = runTest(dispatcher.scheduler) {
        val api = Ravi().apply { failures += busy() }
        val model = payModel(api)
        model.load()
        advanceUntilIdle()

        model.claim(PaymentMethod.Transfer)
        runCurrent()
        assertEquals("the first try met busy", 1, api.keys.size)
        assertTrue("the buttons wait meanwhile", model.state.value.isClaiming)
        assertNull("nothing said", model.state.value.error)

        advanceTimeBy(BUSY_RETRY_MS - 1)
        runCurrent()
        assertEquals("not before a second has passed", 1, api.keys.size)
        advanceTimeBy(2)
        runCurrent()
        advanceUntilIdle()

        assertEquals(listOf("key-1", "key-1"), api.keys)
        assertNull(model.state.value.error)
        assertEquals("Thanks. The club will confirm it once the money has arrived.", model.state.value.message)
    }

    @Test
    fun `busy twice is said, and the next tap still carries the same key`() = runTest(dispatcher.scheduler) {
        val api = Ravi().apply { failures += busy(); failures += busy() }
        val model = payModel(api)
        model.load()
        advanceUntilIdle()

        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()
        assertEquals("only one retry", 2, api.keys.size)
        assertEquals("Someone else is saving a payment for you right now. Try again in a moment.", model.state.value.error)

        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()
        assertEquals("the payment it was busy with may be this one", listOf("key-1", "key-1", "key-1"), api.keys)
    }

    @Test
    fun `a 409 that is not busy is not retried, and is still readable`() = runTest(dispatcher.scheduler) {
        var calls = 0
        val e = runCatching {
            retryIfBusy {
                calls++
                throw refused(409, "You don't owe anything right now", "nothing_owed")
            }
        }.exceptionOrNull()
        assertEquals(1, calls)
        val refusal = refusalOf(e as HttpException)
        assertEquals("nothing_owed", refusal?.code)
        assertEquals("You don't owe anything right now", refusal?.message)
    }

    @Test
    fun `paying for everyone and recording cash retry busy with the same key too`() = runTest(dispatcher.scheduler) {
        val forOthers = mutableListOf<String>()
        val recorded = mutableListOf<String>()
        val api = object : FakePaymentsApi() {
            var forOthersBusy = true
            var recordBusy = true
            override suspend fun payScreen(clubId: String): PayScreen = Captured.read("pay_screen")
            override suspend fun myDues(): Dues = Captured.read("stepBC_me_dues_with_people")
            override suspend fun payForOthers(clubId: String, idempotencyKey: String, body: ForOthersBody): ForOthers {
                forOthers += idempotencyKey
                if (forOthersBusy) { forOthersBusy = false; throw busy() }
                return Captured.read("stepBC_pay_for_others")
            }
            override suspend fun money(clubId: String): MoneyOverview = Captured.read("money_overview")
            override suspend fun recordPayment(clubId: String, idempotencyKey: String, body: RecordBody): Payment {
                recorded += idempotencyKey
                if (recordBusy) { recordBusy = false; throw busy() }
                return Payment(id = "p1", amountCents = body.amountCents, status = "confirmed")
            }
        }
        // Pay for everyone is for the club the captured juniors are in.
        val juniorsClub = Captured.read<Dues>("stepBC_me_dues_with_people").people.first().clubId
        val pay = PayViewModel(api, juniorsClub, AttemptKeys { "key-1" }, me = ravi, forEveryone = true)
        pay.load()
        advanceUntilIdle()
        pay.claim(PaymentMethod.Transfer)
        advanceUntilIdle()
        assertEquals(listOf("key-1", "key-1"), forOthers)
        assertNull(pay.state.value.error)

        var n = 0
        val money = ClubMoneyViewModel(api, club, AttemptKeys { "r-${++n}" })
        money.load()
        advanceUntilIdle()
        money.record(MemberBalance(userId = ravi, name = "Ravi Sharma", owedCents = 1500), 1500, PaymentMethod.Cash, null)
        advanceUntilIdle()
        assertEquals(listOf("r-1", "r-1"), recorded)
        assertEquals("Recorded Ravi Sharma's payment.", money.state.value.message)
    }

    // ---- covered lines, from `cover` ----

    @Test
    fun `a covered line is worded from cover, never from the English reason`() {
        val line = Share(id = "s1", stateName = "covered", reason = "Free: Coach", cover = "pass")
        assertFalse("the reason's words do not decide it", line.isFreePrice)
        assertTrue(line.copy(reason = null, cover = "free").isFreePrice)
        assertFalse("a line nobody covers is never free", line.copy(stateName = "owed", cover = "free").isFreePrice)
        // The captured bills carry it as the server sends it.
        assertEquals("pass", Captured.read<EventMoney>("stepBC_bill_with_pass_cover").shares[0].cover)
        assertEquals("free", Captured.read<EventMoney>("stepBC_bill_priced").shares.single { it.name == "Tom Bennett" }.cover)
    }

    // ---- friends ----

    @Test
    fun `friends come from the pay screen, each with what they owe, and switching it off unticks them`() = runTest(dispatcher.scheduler) {
        val api = Ravi().apply {
            screen = screen.copy(friends = listOf(Friend(jas, "Jas Gill", 563), Friend("t1", "Tom Bennett", 0)))
        }
        val model = payModel(api)
        model.load()
        advanceUntilIdle()
        val own = model.state.value.pay!!.owedCents
        assertEquals("nobody who owes nothing", listOf("Jas Gill" to 563L), model.state.value.friends.map { it.name to it.owedCents })

        model.toggleFriend(jas)
        assertEquals(own + 563, model.state.value.payingCents)
        assertTrue(model.state.value.payingForOthers)

        model.clearFriends()
        assertEquals(own, model.state.value.payingCents)
        assertFalse(model.state.value.payingForOthers)
    }

    // ---- payments made for somebody else ----

    @Test
    fun `a payment you made for somebody else says who it was for, and one made for you says so`() {
        val mine = Payment(id = "p1", userId = ravi, createdBy = ravi, name = "Ravi Sharma", amountCents = 500, methodName = "transfer", status = "claimed")
        assertEquals("£5.00 by bank transfer", mine.waitingWords(ravi))
        val forJas = mine.copy(userId = jas, name = "Jas Gill", amountCents = 563)
        assertEquals("For Jas Gill: £5.63 by bank transfer", forJas.waitingWords(ravi))
        val forMe = mine.copy(createdBy = "neha", methodName = "cash")
        assertEquals("Paid for you: £5.00 in cash", forMe.waitingWords(ravi))
        assertEquals("not knowing who is signed in, it reads as your own", "£5.63 by bank transfer", forJas.waitingWords(null))
    }

    @Test
    fun `undoing a payment made for somebody else says they owe it again`() = runTest(dispatcher.scheduler) {
        val undone = mutableListOf<String>()
        val forJas = Payment(id = "p9", clubId = club, userId = jas, createdBy = ravi, name = "Jas Gill", amountCents = 563, methodName = "transfer", status = "claimed")
        val api = object : Ravi() {
            override suspend fun cancelClaim(paymentId: String) {
                undone += paymentId
            }
        }.apply { screen = screen.copy(claims = listOf(forJas)) }
        val model = payModel(api)
        model.load()
        advanceUntilIdle()
        model.undo(forJas)
        advanceUntilIdle()
        assertEquals(listOf("p9"), undone)
        assertEquals("Undone. Jas Gill still owes it.", model.state.value.message)
    }

    @Test
    fun `the server's payment rows carry who made them`() {
        val row = Captured.json.decodeFromString<Payment>(
            """{"id": "p1", "user_id": "$jas", "name": "Jas Gill", "amount_cents": 563, "method": "transfer", "status": "claimed", "created_by": "$ravi"}""",
        )
        assertEquals(ravi, row.createdBy)
    }

    // ---- the standing order pays this month ----

    @Test
    fun `a month still owed on a pass paid by standing order is the standing order's to pay`() {
        val pass = Captured.read<List<PassHolder>>("stepBC_me_passes").single()
        val month = Share(id = "s1", kind = "pass", title = "Monthly nets — November 2026", userId = pass.userId, amountCents = 2000, stateName = "owed")
        val screen = PayScreen(shares = listOf(month))
        assertTrue(PayState(pay = screen).standingOrderPaysThisMonth(pass))
        assertFalse("said to be paid already", PayState(pay = screen.copy(shares = listOf(month.copy(stateName = "waiting", waitingCents = 2000)))).standingOrderPaysThisMonth(pass))
        assertFalse("a session is not the pass", PayState(pay = screen.copy(shares = listOf(month.copy(kind = "event")))).standingOrderPaysThisMonth(pass))
        assertFalse("no standing order, nothing to say", PayState(pay = screen).standingOrderPaysThisMonth(pass.copy(standingOrder = null)))
        // A junior's month, in the dues of somebody their parent pays for.
        val junior = PersonDues(userId = pass.userId, dues = ClubDues(clubId = club, shares = listOf(month)))
        assertTrue(PayState(pay = PayScreen(), people = listOf(junior)).standingOrderPaysThisMonth(pass))
    }

    // ---- the treasurer's overview ----

    @Test
    fun `a bill on the overview says what kind it is`() {
        val bill = Captured.json.decodeFromString<BillSummary>(
            """{"bill_id": "b1", "event_id": null, "kind": "collection", "title": "Match balls", "event_start_at": "2026-11-21T19:12:29Z"}""",
        )
        assertEquals("collection", bill.kind)
        assertNull("before §13 there was none: a session's event opens it", Captured.read<MoneyOverview>("money_overview").bills.first().kind)
    }

    // ---- a group fee's link: read first, made on Share ----

    private val feeId = Captured.read<GroupFee>("stepBC_collection_created").id

    private open class Fee(var current: JsonElement) : FakePaymentsApi() {
        val made = mutableListOf<String>()
        override suspend fun groupFee(billId: String): GroupFee = Captured.read("stepBC_collection_created")
        override suspend fun currentGroupFeeLink(billId: String): JsonElement = current
        override suspend fun groupFeeLink(billId: String): BillLink {
            made += billId
            return Captured.read("stepBC_collection_link")
        }
        override suspend fun disableGroupFeeLink(billId: String): DisabledLinks = DisabledLinks(1)
    }

    @Test
    fun `a group fee with no link yet says so, and Share makes one`() = runTest(dispatcher.scheduler) {
        val api = Fee(JsonNull)
        val model = GroupFeesViewModel(api, club)
        model.open(feeId)
        advanceUntilIdle()
        assertTrue(model.state.value.linkRead)
        assertNull(model.state.value.link)
        assertTrue("reading never makes one", api.made.isEmpty())

        model.share(model.state.value.open!!, LinkUse.Bill)
        advanceUntilIdle()
        assertEquals(Captured.read<BillLink>("stepBC_collection_link").url, model.state.value.link?.url)

        model.switchLinkOff(model.state.value.open!!)
        advanceUntilIdle()
        assertNull(model.state.value.link)
    }

    @Test
    fun `a group fee's open link is read when it is opened`() = runTest(dispatcher.scheduler) {
        val api = Fee(Captured.json.parseToJsonElement(Captured.text("stepBC_collection_link")))
        val model = GroupFeesViewModel(api, club)
        model.open(feeId)
        advanceUntilIdle()
        assertEquals(Captured.read<BillLink>("stepBC_collection_link").url, model.state.value.link?.url)
        assertTrue(api.made.isEmpty())
    }

    // ---- prices and who pays ----

    @Test
    fun `prices and who pays come from the payments members list`() = runTest(dispatcher.scheduler) {
        val types = Captured.read<List<PriceType>>("stepBC_price_types")
        val members = Captured.json.decodeFromString<List<MoneyMember>>(
            """[
              {"user_id": "j1", "name": "Jas Gill", "price_type_id": "${types[0].id}", "payer_id": "n1", "payer_name": "Neha Gill", "managed": true},
              {"user_id": "n1", "name": "Neha Gill", "price_type_id": null, "payer_id": null, "payer_name": null, "managed": false}
            ]""",
        )
        val api = object : FakePaymentsApi() {
            override suspend fun priceTypes(clubId: String): List<PriceType> = types
            override suspend fun moneyMembers(clubId: String): List<MoneyMember> = members
        }
        val model = PricesAdminViewModel(api, club)
        model.load()
        advanceUntilIdle()
        val s = model.state.value
        val jasRow = s.roster.first()
        assertEquals("Junior", s.groupOf(jasRow)?.name)
        assertEquals("Neha Gill", jasRow.payerName)
        assertNull(s.groupOf(s.roster.last()))
        assertEquals(listOf("Neha Gill"), s.payers.map { it.name })
    }
}

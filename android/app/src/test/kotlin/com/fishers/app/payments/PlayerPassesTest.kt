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

/**
 * The player's side of steps B and C on the pay screen: passes (get one,
 * how it stands, cancel with the bank reminder) and paying for others (a
 * parent's Pay for everyone, friends on the same session) with one key per
 * payment, the same on every retry.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class PlayerPassesTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    // The captured responses are made afresh by each seed run: their ids are read, not typed.
    private val people = Captured.read<Dues>("stepBC_me_dues_with_people").people
    private val club = people.first().clubId
    private val ravi = Captured.read<List<PassHolder>>("stepBC_me_passes").single().userId
    private val jas = people.single { it.name == "Jas Gill" }.userId
    private val arjun = people.single { it.name == "Arjun Gill" }.userId

    /** One club's pay screen and passes, as the captured responses have them. */
    private open class Club : FakePaymentsApi() {
        var screen = Captured.read<PayScreen>("pay_screen")
        var plans = Captured.read<List<PassPlan>>("stepBC_passes_member")
        var mine = Captured.read<List<PassHolder>>("stepBC_me_passes")
        var dues = Captured.read<Dues>("stepBC_me_dues_with_people")
        var loads = 0
        val joins = mutableListOf<Pair<String, JoinPassBody>>()
        var joinFails: Throwable? = null
        val cancels = mutableListOf<String>()
        var cancelFails: Throwable? = null
        val forOthers = mutableListOf<Pair<String, ForOthersBody>>()
        val failures = ArrayDeque<Throwable>()
        val claims = mutableListOf<ClaimBody>()

        override suspend fun payScreen(clubId: String): PayScreen {
            loads++
            return screen
        }
        override suspend fun passes(clubId: String, all: Boolean?): List<PassPlan> = plans
        override suspend fun myPasses(): List<PassHolder> = mine
        override suspend fun priceTypes(clubId: String): List<PriceType> = Captured.read("stepBC_price_types")
        override suspend fun myDues(): Dues = dues
        override suspend fun joinPass(passId: String, body: JoinPassBody): PassHolder {
            joins += passId to body
            joinFails?.let { joinFails = null; throw it }
            return Captured.read<List<PassHolder>>("stepBC_pass_holders").single().copy(name = if (body.forUserId != null) "Jas Gill" else "Ravi Sharma")
        }
        override suspend fun cancelPass(holderId: String): PassHolder {
            cancels += holderId
            cancelFails?.let { cancelFails = null; throw it }
            return mine.single().copy(cancelledAt = "2026-11-22T10:00:00Z", endsOn = "2026-12-20")
        }
        override suspend fun payForOthers(clubId: String, idempotencyKey: String, body: ForOthersBody): ForOthers {
            forOthers += idempotencyKey to body
            failures.removeFirstOrNull()?.let { throw it }
            return Captured.read("stepBC_pay_for_others")
        }
        override suspend fun claimPayment(clubId: String, idempotencyKey: String, body: ClaimBody): Payment {
            claims += body
            return Captured.read<PayScreen>("stepA_pay_screen").claims.first()
        }
    }

    private fun model(api: FakePaymentsApi, me: String? = ravi, forEveryone: Boolean = false): PayViewModel {
        var n = 0
        return PayViewModel(api, club, AttemptKeys { "key-${++n}" }, PayGuideMemory.InMemory(), me = me, forEveryone = forEveryone)
    }

    // ---- passes ----

    @Test
    fun `the pay screen shows your pass with its standing order, and the passes you could get`() = runTest(dispatcher.scheduler) {
        val model = model(Club())
        model.load()
        advanceUntilIdle()
        val s = model.state.value

        val own = s.ownPasses.single()
        assertEquals("Monthly nets", own.planName)
        assertEquals("SHARMA", own.standingOrder?.reference)
        assertEquals("Covers nets and training", own.coversLine())
        assertTrue(s.theirPasses.isEmpty())
        // Monthly nets is his; Season is for the secretary to add.
        assertEquals(listOf("5 nets", "Junior nets"), s.offered.map { it.name })
        assertEquals("Only for Junior members", s.offered[1].onlyForWords(s.priceTypes))
    }

    @Test
    fun `without knowing who is signed in, your own pass is the one the club's list calls yours`() = runTest(dispatcher.scheduler) {
        val model = model(Club(), me = null)
        model.load()
        advanceUntilIdle()
        assertEquals(listOf("Monthly nets"), model.state.value.ownPasses.map { it.planName })
    }

    @Test
    fun `passes that cannot be read leave the pay screen paying`() = runTest(dispatcher.scheduler) {
        val api = object : Club() {
            override suspend fun passes(clubId: String, all: Boolean?): List<PassPlan> = throw IOException("no signal")
            override suspend fun myPasses(): List<PassHolder> = throw IOException("no signal")
        }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        assertTrue(model.state.value.pay != null)
        assertNull(model.state.value.error)
        assertFalse(model.state.value.hasPasses)
    }

    @Test
    fun `Get this pass joins it, says what to do next, and reads the screen again`() = runTest(dispatcher.scheduler) {
        val api = Club()
        val model = model(api)
        model.load()
        advanceUntilIdle()
        val loadsBefore = api.loads
        val bundle = model.state.value.offered.first()

        model.getPass(bundle)
        assertEquals(bundle.id, model.state.value.joining)
        advanceUntilIdle()

        assertEquals(bundle.id to JoinPassBody(null), api.joins.single())
        assertNull(model.state.value.joining)
        assertEquals("You're on 5 nets. Pay £25.00 below and you're covered.", model.state.value.message)
        assertEquals(loadsBefore + 1, api.loads)
    }

    @Test
    fun `a monthly pass got for somebody you pay for says it is theirs`() = runTest(dispatcher.scheduler) {
        val api = Club()
        val model = model(api)
        model.load()
        advanceUntilIdle()
        val juniorNets = model.state.value.plans.single { it.name == "Junior nets" }

        model.getPass(juniorNets, forUserId = jas)
        advanceUntilIdle()

        assertEquals(JoinPassBody(jas), api.joins.single().second)
        assertEquals("For Jas Gill: You're on Junior nets. Now set up the standing order below: £10.00 a month.", model.state.value.message)
    }

    @Test
    fun `a pass you may not have is refused in the server's words`() = runTest(dispatcher.scheduler) {
        val api = Club().apply { joinFails = refused(403, "This pass is for Junior members", "not_eligible") }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        model.getPass(model.state.value.offered.last())
        advanceUntilIdle()
        assertEquals("This pass is for Junior members", model.state.value.error)
        assertNull(model.state.value.message)
    }

    @Test
    fun `cancelling a monthly pass says until when, and to cancel the standing order too`() = runTest(dispatcher.scheduler) {
        val api = Club()
        val model = model(api)
        model.load()
        advanceUntilIdle()
        val own = model.state.value.ownPasses.single()

        model.cancelPass(own)
        assertEquals(own.id, model.state.value.cancelling)
        advanceUntilIdle()

        assertEquals(listOf(own.id), api.cancels)
        val said = model.state.value.message!!
        assertTrue(said, said.startsWith("Monthly nets is cancelled. It covers you until ${dayMonth("2026-12-20")}."))
        assertTrue(said, said.endsWith("Now cancel the standing order in your banking app too."))
        assertNull(model.state.value.cancelling)
    }

    @Test
    fun `a pass already cancelled elsewhere reads the screen again`() = runTest(dispatcher.scheduler) {
        val api = Club().apply { cancelFails = refused(409, "That pass is already cancelled", "already_cancelled") }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        val loadsBefore = api.loads
        model.cancelPass(model.state.value.ownPasses.single())
        advanceUntilIdle()
        assertEquals("That pass is already cancelled", model.state.value.error)
        assertEquals(loadsBefore + 1, api.loads)
    }

    // ---- Pay for everyone ----

    @Test
    fun `Pay for everyone is you and everybody you pay for, in one total`() = runTest(dispatcher.scheduler) {
        val model = model(Club(), forEveryone = true)
        model.load()
        advanceUntilIdle()
        val s = model.state.value
        assertEquals(listOf("Arjun Gill", "Jas Gill"), s.othersOwing.map { it.name })
        assertTrue(s.payingForOthers)
        assertEquals(1500L + 600 + 900, s.payingCents)
        assertEquals(listOf(arjun, jas).sorted(), s.othersInPayment)
    }

    @Test
    fun `Pay for everyone is one payment, and a retry after no signal is the same payment`() = runTest(dispatcher.scheduler) {
        val api = Club().apply { failures += IOException("no signal") }
        val model = model(api, forEveryone = true)
        model.load()
        advanceUntilIdle()

        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()
        assertTrue("said, not silently dropped", model.state.value.error != null)

        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()

        val (first, second) = api.forOthers
        assertEquals("key-1", first.first)
        assertEquals("the retry carries the same key", "key-1", second.first)
        assertEquals(ForOthersBody(method = "transfer", people = listOf(arjun, jas).sorted(), includeMe = true), second.second)
        assertTrue("never the single claim", api.claims.isEmpty())
        assertEquals("Thanks. The club will confirm it once the money has arrived.", model.state.value.message)

        // A new payment is a new attempt.
        model.claim(PaymentMethod.Cash)
        advanceUntilIdle()
        assertEquals("key-2", api.forOthers.last().first)
        assertEquals("cash", api.forOthers.last().second.method)
    }

    @Test
    fun `a payment the server refused is over, so the next one has a new key`() = runTest(dispatcher.scheduler) {
        val api = Club().apply { failures += refused(403, "You can pay for the people you pay for, or friends on the same bill", "not_their_payer") }
        val model = model(api, forEveryone = true)
        model.load()
        advanceUntilIdle()
        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()
        assertEquals("You can pay for the people you pay for, or friends on the same bill", model.state.value.error)

        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()
        assertEquals(listOf("key-1", "key-2"), api.forOthers.map { it.first })
    }

    @Test
    fun `nobody owing anything after all is said quietly, and the screen is read again`() = runTest(dispatcher.scheduler) {
        val api = Club().apply { failures += refused(409, "Nobody you picked owes anything", "nothing_owed") }
        val model = model(api, forEveryone = true)
        model.load()
        advanceUntilIdle()
        val loadsBefore = api.loads
        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()
        assertNull(model.state.value.error)
        assertEquals("Nobody you picked owes anything", model.state.value.message)
        assertEquals(loadsBefore + 1, api.loads)
    }

    @Test
    fun `with nobody else owing, the pay screen pays for you alone`() = runTest(dispatcher.scheduler) {
        val api = Club().apply { dues = Dues() }
        val model = model(api, forEveryone = true)
        model.load()
        advanceUntilIdle()
        assertFalse(model.state.value.payingForOthers)
        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()
        assertTrue(api.forOthers.isEmpty())
        assertEquals("transfer", api.claims.single().method)
    }

    // ---- friends on the same session ----

    @Test
    fun `friends ticked are paid for with you, and untick themselves once they've paid`() = runTest(dispatcher.scheduler) {
        val friend = Friend(userId = "f1", name = "Imran Khan", owedCents = 500)
        val api = Club().apply { screen = screen.copy(friends = listOf(friend, Friend("f2", "Paid Already", 0))) }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        assertEquals(listOf("Imran Khan"), model.state.value.friends.map { it.name })

        model.toggleFriend("f1")
        assertEquals(api.screen.owedCents + 500, model.state.value.payingCents)
        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()

        assertEquals(ForOthersBody("transfer", listOf("f1"), includeMe = true), api.forOthers.single().second)
        assertTrue("cleared once paid", model.state.value.friendsTicked.isEmpty())

        model.toggleFriend("f1")
        api.screen = api.screen.copy(friends = emptyList())
        model.load()
        advanceUntilIdle()
        assertTrue("a friend no longer owing drops off the ticks", model.state.value.friendsTicked.isEmpty())
    }
}

package com.fishers.app.payments

import com.fishers.app.EnglishStrings
import com.fishers.app.clubs.ClubMemberDetail
import com.fishers.app.clubs.Team
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
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.io.IOException
import java.time.LocalDate

/**
 * The money admin's side of steps B and C: passes from templates, who is on
 * them, group fees (made once however many times the tap is retried, shared
 * in the server's words, cancelled with why), groups and who pays for whom,
 * and a session's price for juniors.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class MoneyAdminTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val club = "417a6102-8f61-4685-90c7-cdd3be22bbbc"
    private val neha = ClubMemberDetail("4d032087-744b-4fe5-ade1-273a69dbcfb3", "Neha Gill")
    private val sam = ClubMemberDetail("b5889fe5-3401-40b4-b4c1-7755e91d22ef", "Sam Student")

    private open class Admin : FakePaymentsApi() {
        var plans = Captured.read<List<PassPlan>>("stepBC_passes_member")
        val made = mutableListOf<NewPassBody>()
        val added = mutableListOf<Pair<String, AddHolderBody>>()
        val kept = mutableListOf<Pair<String, KeepCoveringBody>>()
        val changed = mutableListOf<Pair<String, PassChangeBody>>()
        var planLoads = 0
        override suspend fun passes(clubId: String, all: Boolean?): List<PassPlan> {
            planLoads++
            return plans
        }
        override suspend fun priceTypes(clubId: String): List<PriceType> = Captured.read("stepBC_price_types")
        override suspend fun clubMembers(clubId: String): List<ClubMemberDetail> = listOf(
            // On Monthly nets in the captured holders: the same person.
            ClubMemberDetail(Captured.read<List<PassHolder>>("stepBC_pass_holders").single().userId, "Ravi Sharma"),
            ClubMemberDetail("b5889fe5-3401-40b4-b4c1-7755e91d22ef", "Sam Student"),
            ClubMemberDetail("4d032087-744b-4fe5-ade1-273a69dbcfb3", "Neha Gill"),
        )
        override suspend fun clubTeams(clubId: String): List<Team> = listOf(Team("t1", clubId, "1st XI"))
        override suspend fun addPass(clubId: String, body: NewPassBody): PassPlan {
            made += body
            return Captured.read<PassPlan>("stepBC_pass_created_instalments").copy(name = body.name)
        }
        override suspend fun passHolders(passId: String): List<PassHolder> = Captured.read("stepBC_pass_holders")
        override suspend fun addToPass(passId: String, body: AddHolderBody): PassHolder {
            added += passId to body
            return Captured.read<List<PassHolder>>("stepBC_pass_holders").single()
        }
        override suspend fun keepCovering(holderId: String, body: KeepCoveringBody): PassHolder {
            kept += holderId to body
            return Captured.read<List<PassHolder>>("stepBC_pass_holders").single().copy(keepCovering = body.on, standingName = "suspended")
        }
        override suspend fun changePass(passId: String, body: PassChangeBody): PassPlan {
            changed += passId to body
            val was = plans.single { it.id == passId }
            return was.copy(openToJoin = body.openToJoin ?: was.openToJoin, archivedAt = if (body.archived == true) "2026-11-22T10:00:00Z" else was.archivedAt, mine = null)
        }
    }

    // ---- passes ----

    @Test
    fun `a pass made from the Monthly nets template is sent as the plan describes`() = runTest(dispatcher.scheduler) {
        val api = Admin()
        val model = PassesAdminViewModel(api, club, today = { LocalDate.of(2026, 11, 22) })
        model.load()
        advanceUntilIdle()
        val loadsBefore = api.planLoads

        model.startFrom(PassTemplate.MonthlyNets)
        assertEquals("Monthly nets", model.state.value.draft?.name)
        model.changeDraft { it.copy(price = "22.50", covers = it.covers + SessionKind.Training) }
        model.saveDraft()
        advanceUntilIdle()

        val body = api.made.single()
        assertEquals(NewPassBody(name = "Monthly nets", priceCents = 2250, billing = "monthly", covers = listOf("nets", "training")), body)
        assertNull("the form closes", model.state.value.draft)
        assertEquals("Monthly nets is ready. Add people, or let players get it from their pay screen.", model.state.value.message)
        assertEquals(loadsBefore + 1, api.planLoads)
    }

    @Test
    fun `a form with something wrong says so and sends nothing`() = runTest(dispatcher.scheduler) {
        val api = Admin()
        val model = PassesAdminViewModel(api, club)
        model.startFrom(PassTemplate.TenSessions)
        model.changeDraft { it.copy(sessions = "") }
        model.saveDraft()
        advanceUntilIdle()
        assertEquals("Say how many sessions: 1 to 500.", model.state.value.draftProblem)
        assertTrue(api.made.isEmpty())
    }

    @Test
    fun `the server's refusal of a new pass is said on the form`() = runTest(dispatcher.scheduler) {
        val api = object : Admin() {
            override suspend fun addPass(clubId: String, body: NewPassBody): PassPlan =
                throw refused(400, "A bundle is 1 to 500 sessions")
        }
        val model = PassesAdminViewModel(api, club)
        model.startFrom(PassTemplate.WinterNets)
        model.saveDraft()
        advanceUntilIdle()
        assertEquals("A bundle is 1 to 500 sessions", model.state.value.draftProblem)
        assertTrue("still open to fix", model.state.value.draft != null)
    }

    @Test
    fun `a pass opens to who is on it, and somebody added is told and charged by the server`() = runTest(dispatcher.scheduler) {
        val api = Admin()
        val model = PassesAdminViewModel(api, club)
        model.load()
        advanceUntilIdle()
        val monthly = model.state.value.plans.first()
        model.open(monthly.id)
        advanceUntilIdle()
        assertEquals(listOf("Ravi Sharma"), model.state.value.holders.map { it.name })
        assertEquals("only those not on it", listOf("Neha Gill", "Sam Student"), model.state.value.canAdd.map { it.name })

        model.add(sam)
        advanceUntilIdle()
        assertEquals(monthly.id to AddHolderBody(sam.userId), api.added.single())
        assertEquals("Sam Student is on Monthly nets.", model.state.value.message)
    }

    @Test
    fun `keep covering is sent, and the row shows what the server says`() = runTest(dispatcher.scheduler) {
        val api = Admin()
        val model = PassesAdminViewModel(api, club)
        model.load()
        advanceUntilIdle()
        model.open(model.state.value.plans.first().id)
        advanceUntilIdle()
        val holder = model.state.value.holders.single()

        model.keepCovering(holder, on = true)
        advanceUntilIdle()

        assertEquals(holder.id to KeepCoveringBody(true), api.kept.single())
        assertTrue(model.state.value.holders.single().keepCovering)
        assertTrue(model.state.value.holders.single().adminWords().startsWith("Payments late, kept covered"))
    }

    @Test
    fun `stopping a pass keeps it in the list, under no longer offered`() = runTest(dispatcher.scheduler) {
        val api = Admin()
        val model = PassesAdminViewModel(api, club)
        model.load()
        advanceUntilIdle()
        val bundle = model.state.value.plans[1]
        model.stopOffering(bundle)
        advanceUntilIdle()
        assertEquals(PassChangeBody(archived = true), api.changed.single().second)
        assertEquals(listOf("5 nets"), model.state.value.stopped.map { it.name })
        assertEquals("5 nets is no longer offered.", model.state.value.message)
    }

    @Test
    fun `a new price is checked before it is sent`() = runTest(dispatcher.scheduler) {
        val api = Admin()
        val model = PassesAdminViewModel(api, club)
        model.load()
        advanceUntilIdle()
        val monthly = model.state.value.plans.first()
        assertEquals("Type an amount, like 7.50.", model.changePrice(monthly, "twenty"))
        assertNull(model.changePrice(monthly, "25"))
        advanceUntilIdle()
        assertEquals(PassChangeBody(priceCents = 2500), api.changed.single().second)
    }

    // ---- group fees ----

    private open class Fees : FakePaymentsApi() {
        val made = mutableListOf<Pair<String, NewGroupFeeBody>>()
        val failures = ArrayDeque<Throwable>()
        val links = mutableListOf<String>()
        val voids = mutableListOf<Pair<String, ReasonBody>>()
        override suspend fun groupFees(clubId: String): List<GroupFee> = Captured.read("stepBC_collections_list")
        override suspend fun clubMembers(clubId: String): List<ClubMemberDetail> = emptyList()
        override suspend fun clubTeams(clubId: String): List<Team> = emptyList()
        override suspend fun priceTypes(clubId: String): List<PriceType> = Captured.read("stepBC_price_types")
        override suspend fun addGroupFee(clubId: String, idempotencyKey: String, body: NewGroupFeeBody): GroupFee {
            made += idempotencyKey to body
            failures.removeFirstOrNull()?.let { throw it }
            return Captured.read("stepBC_collection_created")
        }
        override suspend fun groupFee(billId: String): GroupFee = Captured.read("stepBC_collection_created")
        override suspend fun groupFeeLink(billId: String): BillLink {
            links += billId
            return Captured.read("stepBC_collection_link")
        }
        override suspend fun cancelGroupFee(billId: String, body: ReasonBody): GroupFee {
            voids += billId to body
            return Captured.read<GroupFee>("stepBC_collection_created").copy(voidedAt = "2026-11-22T10:00:00Z", voidReason = body.reason)
        }
    }

    private fun fees(api: FakePaymentsApi): GroupFeesViewModel {
        var n = 0
        return GroupFeesViewModel(api, club, AttemptKeys { "key-${++n}" })
    }

    @Test
    fun `a group fee retried after no signal is the same group fee`() = runTest(dispatcher.scheduler) {
        val api = Fees().apply { failures += IOException("no signal") }
        val model = fees(api)
        model.load()
        advanceUntilIdle()
        model.startNew()
        model.changeDraft { it.copy(title = "Match balls", mode = CostMode.SplitTotal, amount = "45") }

        model.saveDraft()
        advanceUntilIdle()
        assertTrue("the form stays, saying why", model.state.value.draft != null && model.state.value.draftProblem != null)
        model.saveDraft()
        advanceUntilIdle()

        assertEquals(listOf("key-1", "key-1"), api.made.map { it.first })
        assertTrue(api.made.last().second.everyone)
        assertNull(model.state.value.draft)
        assertEquals("Match balls", model.state.value.open?.title)
        assertEquals("Match balls sent to 3 people. Now share it to WhatsApp.", model.state.value.message)
        // A second group fee is a new one.
        model.startNew()
        model.changeDraft { it.copy(title = "Kit", amount = "15") }
        model.saveDraft()
        advanceUntilIdle()
        assertEquals("key-2", api.made.last().first)
    }

    @Test
    fun `sharing a group fee posts the server's words, asked for each time`() = runTest(dispatcher.scheduler) {
        val api = Fees()
        val model = fees(api)
        model.open("0990623b-1c04-4de9-a570-26ffea7a5159")
        advanceUntilIdle()
        val fee = model.state.value.open!!

        model.share(fee, LinkUse.Reminder)
        advanceUntilIdle()
        val out = model.state.value.outgoing as Outgoing.Share
        assertTrue(out.text.startsWith("Still to pay for Match balls, by Sun 6 Dec: Gary, Ravi and Sam."))
        model.handled()
        model.share(fee, LinkUse.CopyLink)
        advanceUntilIdle()
        assertEquals(Outgoing.Copy(Captured.read<BillLink>("stepBC_collection_link").url), model.state.value.outgoing)
        assertEquals(listOf(fee.id, fee.id), api.links)
    }

    @Test
    fun `cancelling a group fee needs a reason, and keeps it on record`() = runTest(dispatcher.scheduler) {
        val api = Fees()
        val model = fees(api)
        model.open("0990623b-1c04-4de9-a570-26ffea7a5159")
        advanceUntilIdle()
        val fee = model.state.value.open!!

        model.cancel(fee, "   ")
        advanceUntilIdle()
        assertTrue(api.voids.isEmpty())

        model.cancel(fee, " Bought by the league ")
        advanceUntilIdle()
        assertEquals(fee.id to ReasonBody("Bought by the league"), api.voids.single())
        assertTrue(model.state.value.open!!.isCancelled)
        assertEquals("Match balls is cancelled. Anything paid is kept as credit.", model.state.value.message)
    }

    // ---- groups, and who pays for whom ----

    private class People : FakePaymentsApi() {
        val groups = mutableListOf<Pair<String, MemberPriceTypeBody>>()
        val payers = mutableListOf<Pair<String, PayerBody>>()
        val juniors = mutableListOf<ManagedMemberBody>()
        val added = mutableListOf<PriceTypeBody>()
        override suspend fun priceTypes(clubId: String): List<PriceType> = Captured.read("stepBC_price_types")
        override suspend fun clubMembers(clubId: String): List<ClubMemberDetail> = listOf(
            ClubMemberDetail("85490ff5-c175-4232-9c04-6d95c6be3c84", "Jas Gill"),
            ClubMemberDetail("4d032087-744b-4fe5-ade1-273a69dbcfb3", "Neha Gill"),
        )
        override suspend fun setMemberPriceType(clubId: String, userId: String, body: MemberPriceTypeBody) {
            groups += userId to body
        }
        override suspend fun setPayer(clubId: String, memberId: String, body: PayerBody) {
            payers += memberId to body
        }
        override suspend fun addJunior(clubId: String, body: ManagedMemberBody): ManagedMember {
            juniors += body
            return ManagedMember("new-junior", body.name, body.payerId)
        }
        override suspend fun addPriceType(clubId: String, body: PriceTypeBody): PriceType {
            added += body
            return PriceType("new-type", clubId, body.name ?: "", body.free ?: false, body.forGuests ?: false, 9)
        }
    }

    @Test
    fun `a member's group and payer are sent together, and the page remembers them`() = runTest(dispatcher.scheduler) {
        val api = People()
        val model = PricesAdminViewModel(api, club)
        model.load()
        advanceUntilIdle()
        val jas = model.state.value.roster.first()
        val junior = model.state.value.inUse.first()

        model.saveMember(jas, Pick(junior), Pick(neha))
        advanceUntilIdle()

        assertEquals(jas.userId to MemberPriceTypeBody(junior.id), api.groups.single())
        assertEquals(jas.userId to PayerBody(neha.userId), api.payers.single())
        assertEquals(MemberMoney(groupSet = true, groupId = junior.id, payerSet = true, payerId = neha.userId), model.state.value.known[jas.userId])
        assertEquals("Jas Gill pays the Junior price. Neha Gill now pays for Jas Gill.", model.state.value.message)

        // Back to the standard price, payer untouched: only the group is sent.
        model.saveMember(jas, Pick(null), null)
        advanceUntilIdle()
        assertEquals(MemberPriceTypeBody(null), api.groups.last().second)
        assertEquals(1, api.payers.size)
        assertEquals("Jas Gill pays the standard price.", model.state.value.message)
    }

    @Test
    fun `a junior by name needs who pays for them`() = runTest(dispatcher.scheduler) {
        val api = People()
        val model = PricesAdminViewModel(api, club)
        model.load()
        advanceUntilIdle()
        assertEquals("Pick who pays for them.", model.addJunior("Arjun Gill", null))
        assertEquals("Type their name, up to 70 letters.", model.addJunior("  ", neha))
        assertTrue(api.juniors.isEmpty())

        assertNull(model.addJunior("  Arjun   Gill ", neha))
        advanceUntilIdle()
        assertEquals(ManagedMemberBody("Arjun Gill", neha.userId), api.juniors.single())
        assertEquals("Arjun Gill added. Neha Gill pays for them.", model.state.value.message)
    }

    @Test
    fun `a new group says what it is, free or the guests' price`() = runTest(dispatcher.scheduler) {
        val api = People()
        val model = PricesAdminViewModel(api, club)
        model.load()
        advanceUntilIdle()
        assertEquals("Give the group a name of up to 30 letters.", model.addGroup(" ", free = false, forGuests = false))
        assertNull(model.addGroup("Coach", free = true, forGuests = false))
        advanceUntilIdle()
        assertEquals(PriceTypeBody(name = "Coach", free = true, forGuests = false), api.added.single())
        assertEquals("Coach · free", model.state.value.types.last().label)
    }

    // ---- a session's price for juniors ----

    @Test
    fun `the session cost carries its prices for juniors, and the club's groups are read for the form`() = runTest(dispatcher.scheduler) {
        val costs = mutableListOf<CostBody>()
        val api = object : FakePaymentsApi() {
            override suspend fun bill(eventId: String): EventMoney = Captured.read("stepBC_bill_priced")
            override suspend fun priceTypes(clubId: String): List<PriceType> = Captured.read("stepBC_price_types")
            override suspend fun setCost(eventId: String, body: CostBody): CostResponse {
                costs += body
                return Captured.read("stepBC_cost_with_prices")
            }
        }
        val model = EventMoneyViewModel(api, "3529a322-89e3-4338-8e8b-4daefe8c05ab")
        model.load()
        advanceUntilIdle()
        assertEquals(4, model.state.value.priceTypes.size)

        model.saveCost(CostMode.PerPlayer, 600, null, false, prices = listOf(PriceIn("c44e0090-460a-4716-a97c-a186f401198e", 300)))
        advanceUntilIdle()
        assertEquals(listOf(PriceIn("c44e0090-460a-4716-a97c-a186f401198e", 300)), costs.single().prices)

        // A total split evenly has no prices by group: none are sent.
        model.saveCost(CostMode.SplitTotal, 6000, null, false, prices = listOf(PriceIn("x", 1)))
        advanceUntilIdle()
        assertNull(costs.last().prices)
    }
}

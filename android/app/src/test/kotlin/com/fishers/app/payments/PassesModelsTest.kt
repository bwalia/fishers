package com.fishers.app.payments

import com.fishers.app.EnglishStrings
import com.fishers.app.i18n.Language
import com.fishers.app.i18n.Strings
import kotlinx.serialization.encodeToString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.io.File
import java.time.LocalDate

/**
 * Steps B and C as the server sends them (`.dev/payments/examples/stepBC_*`):
 * every response decodes, unknown words never stop one loading, and the words
 * a player reads come out plain.
 */
class PassesModelsTest {
    @get:Rule val english = EnglishStrings()

    // ---- every captured response decodes ----

    @Test
    fun `every step B and C response decodes`() {
        val mine = Captured.read<List<PassHolder>>("stepBC_me_passes").single()
        val passes = Captured.read<List<PassPlan>>("stepBC_passes_member")
        assertEquals(4, passes.size)
        assertEquals(PassBilling.Monthly, passes[0].billing)
        assertEquals(mine.userId, passes[0].mine?.userId)
        assertEquals(listOf("nets", "training"), passes[0].covers)

        assertEquals(PassStanding.UpToDate, mine.standing)
        assertEquals(2000L, mine.standingOrder?.amountCents)
        assertEquals("SHARMA", mine.standingOrder?.reference)
        assertEquals("2026-11-21", mine.standingOrder?.firstPaymentOn)
        assertTrue(mine.clubName.startsWith("Step BC"))

        assertEquals(PassStanding.Suspended, Captured.read<List<PassHolder>>("stepBC_me_passes_suspended").single().standing)
        assertEquals(1, Captured.read<List<PassHolder>>("stepBC_pass_holders").size)

        val season = Captured.read<PassPlan>("stepBC_pass_created_instalments")
        assertEquals(PassBilling.Instalments, season.billing)
        assertEquals(3334L, season.chargeCents)

        val types = Captured.read<List<PriceType>>("stepBC_price_types")
        assertEquals(listOf("Junior", "Coach", "Guest", "junior"), types.map { it.name })
        assertTrue(types[1].free)
        assertTrue(types[2].forGuests)

        val fee = Captured.read<GroupFee>("stepBC_collection_created")
        assertEquals(CostMode.SplitTotal, fee.mode)
        assertEquals("2026-12-06", fee.dueOn)
        assertEquals(3, fee.people)
        assertEquals(3, fee.shares.size)
        assertEquals("collection", fee.shares[0].kind)
        assertNull(fee.shares[0].eventId)
        assertEquals(1, Captured.read<GroupFee>("stepBC_collection_member_view").shares.size)
        assertEquals(2, Captured.read<List<GroupFee>>("stepBC_collections_list").size)
        assertTrue(Captured.read<BillLink>("stepBC_collection_link").reminderMessage.startsWith("Still to pay for Match balls"))

        val forOthers = Captured.read<ForOthers>("stepBC_pay_for_others")
        assertEquals(1500L, forOthers.totalCents)
        assertEquals("GILL", forOthers.reference)
        assertEquals(listOf("Jas Gill", "Arjun Gill"), forOthers.payments.map { it.name })

        val dues = Captured.read<Dues>("stepBC_me_dues_with_people")
        assertTrue(dues.clubs.isEmpty())
        assertEquals(listOf("Arjun Gill", "Jas Gill"), dues.people.map { it.name })
        assertTrue(dues.people[0].managed)

        val priced = Captured.read<EventMoney>("stepBC_bill_priced")
        assertEquals(listOf("Junior" to 300L, "Guest" to 800L), priced.prices.map { it.name to it.amountCents })
        assertTrue(priced.shares.single { it.name == "Tom Bennett" }.isCovered)
        assertEquals(2, Captured.read<CostResponse>("stepBC_cost_with_prices").prices.size)
        assertEquals("Covered by Monthly nets", Captured.read<EventMoney>("stepBC_bill_with_pass_cover").shares[0].reason)
        assertEquals("Free: Coach", Captured.read<BillPreview>("stepBC_bill_preview_priced").shares[2].covered)
        assertNull(Captured.read<MoneySettings>("stepBC_usual_prices").usualNets)
    }

    @Test
    fun `words the server has not taught the app yet never stop a pass loading`() {
        val text = Captured.text("stepBC_me_passes")
            .replace("\"monthly\"", "\"weekly\"")
            .replace("\"standing\": \"up_to_date\"", "\"standing\": \"on_holiday\"")
        val pass = Captured.json.decodeFromString<List<PassHolder>>(text).single()
        assertEquals(PassBilling.Unknown, pass.billing)
        assertEquals(PassStanding.Unknown, pass.standing)
        assertEquals("Covered ✓", pass.standingWords())
        assertEquals("Next payment 21 Dec", pass.adminWords())

        val plan = Captured.json.decodeFromString<PassPlan>(
            Captured.text("stepBC_pass_created_instalments").replace("\"league_match\"", "\"darts_night\""),
        )
        assertEquals("Membership of the club", plan.coversLine())
    }

    // ---- passes in words ----

    @Test
    fun `a pass says its price and what it covers in one plain line`() {
        val (monthly, bundle, season, junior) = Captured.read<List<PassPlan>>("stepBC_passes_member")
        assertEquals("£20.00 a month", monthly.priceWords())
        assertEquals("Covers nets and training", monthly.coversLine())
        assertEquals("£25.00", bundle.priceWords())
        assertEquals("Covers 2 sessions: nets", bundle.coversLine())
        assertEquals("£100.00, or 3 payments of £33.34", season.priceWords())
        assertEquals("Covers league matches", season.coversLine())
        val types = Captured.read<List<PriceType>>("stepBC_price_types")
        assertEquals("Only for Junior members", junior.onlyForWords(types))
        assertNull(monthly.onlyForWords(types))
        assertEquals("nets, training and league matches", coversWords(listOf("nets", "training", "league_match")))
    }

    @Test
    fun `how a pass stands is said as the person would want it`() {
        val running = Captured.read<List<PassHolder>>("stepBC_me_passes").single()
        assertEquals("Covered ✓", running.standingWords())
        assertFalse(running.needsPaying)

        val paused = Captured.read<List<PassHolder>>("stepBC_me_passes_suspended").single()
        assertEquals("Paused: a payment is late. Pay what's owed and it covers you again.", paused.standingWords())
        assertTrue(paused.needsPaying)
        assertTrue(paused.adminWords().startsWith("Paused: payments late"))
        assertEquals("Payments late, kept covered", paused.copy(keepCovering = true).adminWords().substringBefore(" · "))

        val late = running.copy(standingName = "behind")
        assertEquals("A payment is late: pay it to stay covered.", late.standingWords())

        assertEquals("3 sessions left", running.copy(sessionsLeft = 3).standingWords())
        assertEquals("1 session left", running.copy(sessionsLeft = 1).standingWords())
        assertEquals("All used. Get another to stay covered.", running.copy(sessionsLeft = 0, running = false).standingWords())

        val until = LocalDate.now().plusMonths(2)
        assertEquals("Covered until ${dayMonth(until.toString())}", running.standingWords(validUntil = until.toString()))

        val ends = LocalDate.now().plusDays(20).toString()
        val cancelled = running.copy(cancelledAt = "2026-11-22T10:00:00Z", endsOn = ends)
        assertEquals("Cancelled. Covers until ${dayMonth(ends)}.", cancelled.standingWords())
        assertNull("no next payment once cancelled", cancelled.nextPaymentWords())
    }

    @Test
    fun `dates read as a day and a month, with the year only when it is not near`() {
        val today = LocalDate.of(2026, 11, 22)
        assertEquals("6 Dec", dayMonth("2026-12-06", today))
        assertEquals("31 Mar", dayMonth("2027-03-31", today))
        assertEquals("6 Dec 2027", dayMonth("2027-12-06", today))
        assertEquals("", dayMonth("not a date", today))
        assertEquals("", dayMonth(null, today))
    }

    // ---- lines in "You owe" ----

    @Test
    fun `a group fee says when it is due, a covered session says why it costs nothing`() {
        val due = LocalDate.now().plusDays(14).toString()
        val fee = Captured.read<GroupFee>("stepBC_collection_created").shares[1].copy(dueOn = due)
        assertEquals("by ${dayMonth(due)}", fee.whenWords())
        assertEquals("", fee.copy(dueOn = null).whenWords())

        val covered = Captured.read<EventMoney>("stepBC_bill_with_pass_cover").shares[0]
        assertTrue(covered.isCovered)
        assertFalse(covered.isFreePrice)
        assertEquals("Covered by your pass ✓", covered.state.label)
        val coach = Captured.read<EventMoney>("stepBC_bill_priced").shares.single { it.name == "Tom Bennett" }
        assertTrue(coach.isFreePrice)
    }

    @Test
    fun `the preview leaves out whoever a pass or a free price covers`() {
        val preview = Captured.read<BillPreview>("stepBC_bill_preview_priced")
        assertEquals(
            "£17.00 between 3: 1 pays £8.00, 1 pays £6.00, 1 pays £3.00 1 more pays nothing (a pass or a free price).",
            preview.summary,
        )
    }

    @Test
    fun `you owe counts the people you pay for, club by club`() {
        val dues = Captured.read<Dues>("stepBC_me_dues_with_people")
        val club = dues.people.first().clubId
        val owing = dues.owing.single()
        assertEquals(club, owing.clubId)
        assertEquals(1500L, owing.owedCents)
        assertEquals(dues.people.first().dues.clubName, owing.clubName)
        assertEquals(2, dues.peopleIn(club).size)
        assertTrue(dues.hasAnything)
        assertTrue(Dues().owing.isEmpty())
    }

    // ---- the forms ----

    @Test
    fun `each template makes the pass the plan describes`() {
        val today = LocalDate.of(2026, 11, 22)
        val types = Captured.read<List<PriceType>>("stepBC_price_types")
        fun body(t: PassTemplate) = (t.draft(today, types).check() as PassDraftCheck.Ok).body

        body(PassTemplate.WinterNets).let {
            assertEquals("once", it.billing)
            assertEquals(6000L, it.priceCents)
            assertEquals(listOf("nets"), it.covers)
            assertEquals("2027-03-31", it.validUntil)
        }
        body(PassTemplate.TenSessions).let {
            assertEquals(10, it.sessions)
            assertNull(it.validUntil)
        }
        body(PassTemplate.MonthlyNets).let {
            assertEquals("monthly", it.billing)
            assertNull(it.sessions)
            assertNull(it.validUntil)
        }
        body(PassTemplate.SeasonMembership).let {
            assertEquals("instalments", it.billing)
            assertEquals(3, it.instalments)
            assertEquals(12000L, it.priceCents)
            assertTrue(it.covers.isEmpty())
            assertFalse(it.openToJoin)
        }
        assertEquals(types.first { it.name == "Junior" }.id, body(PassTemplate.JuniorMembership).priceTypeId)
        assertEquals("£120.00, or 3 payments of £40.00", PassTemplate.SeasonMembership.draft(today, types).preview("GBP").priceWords())
    }

    @Test
    fun `a monthly pass never sends an end, and a bad form says what is wrong`() {
        val draft = PassDraft(name = "  Monthly   nets ", price = "20", billing = PassBilling.Monthly, length = PassLength.Sessions, sessions = "10")
        val ok = (draft.check() as PassDraftCheck.Ok).body
        assertEquals("Monthly nets", ok.name)
        assertNull(ok.sessions)

        assertEquals("Give the pass a name of up to 60 letters.", (draft.copy(name = " ").check() as PassDraftCheck.Invalid).problem)
        assertEquals("Type an amount, like 7.50.", (draft.copy(price = "free").check() as PassDraftCheck.Invalid).problem)
        assertEquals(
            "Split it into 2 to 12 parts.",
            (draft.copy(billing = PassBilling.Instalments, instalments = 1).check() as PassDraftCheck.Invalid).problem,
        )
        assertEquals(
            "Say how many sessions: 1 to 500.",
            (draft.copy(billing = PassBilling.Once, sessions = "0").check() as PassDraftCheck.Invalid).problem,
        )
        assertEquals(
            "Pick the date it ends.",
            (draft.copy(billing = PassBilling.Once, length = PassLength.UntilDate, until = null).check() as PassDraftCheck.Invalid).problem,
        )
    }

    @Test
    fun `a group fee says who in exactly one way`() {
        val draft = GroupFeeDraft(title = "Match balls", mode = CostMode.SplitTotal, amount = "45", dueOn = LocalDate.of(2026, 12, 6))
        val everyone = (draft.check() as GroupFeeCheck.Ok).body
        assertTrue(everyone.everyone)
        assertEquals(4500L, everyone.amountCents)
        assertEquals("2026-12-06", everyone.dueOn)

        val onlyGuests = (draft.copy(who = FeeWho.Names, guests = listOf("Gary")).check() as GroupFeeCheck.Ok).body
        assertFalse(onlyGuests.everyone)
        assertNull("no list at all: guests only", onlyGuests.userIds)
        assertEquals(listOf("Gary"), onlyGuests.guests)

        val names = (draft.copy(who = FeeWho.Names, names = setOf("b", "a")).check() as GroupFeeCheck.Ok).body
        assertEquals(listOf("a", "b"), names.userIds)

        assertEquals("Pick the team.", (draft.copy(who = FeeWho.Team).check() as GroupFeeCheck.Invalid).problem)
        assertEquals("Tick at least one name, or add a guest.", (draft.copy(who = FeeWho.Names).check() as GroupFeeCheck.Invalid).problem)
        assertEquals("Say what it's for, in up to 80 letters.", (draft.copy(title = "").check() as GroupFeeCheck.Invalid).problem)
        assertTrue(draft.copy(mode = CostMode.PerPlayer, amount = "1001").check() is GroupFeeCheck.Invalid)
    }

    @Test
    fun `bodies leave out what is not being changed, as the server reads them`() {
        val json = Captured.json
        assertEquals("{}", json.encodeToString(MemberPriceTypeBody(null)))
        assertEquals("{}", json.encodeToString(PayerBody(null)))
        assertEquals("""{"on":true}""", json.encodeToString(KeepCoveringBody(true)))
        assertFalse("prices left as they are", "prices" in json.encodeToString(CostBody("per_player", 600)))
        assertTrue("prices cleared", json.encodeToString(CostBody("per_player", 600, prices = emptyList())).contains(""""prices":[]"""))
        val fee = json.encodeToString(NewGroupFeeBody(title = "Kit", mode = "per_player", amountCents = 1500, everyone = true))
        assertFalse("no list unless names were ticked", "user_ids" in fee)
        assertTrue(""""everyone":true""" in fee)
        assertEquals("""{"method":"transfer","people":["a"],"include_me":true}""", json.encodeToString(ForOthersBody("transfer", listOf("a"), includeMe = true)))
    }

    @Test
    fun `a group's price for one session, empty is the usual price and nought is free`() {
        val ok = checkTypePrices(mapOf("junior" to "3", "coach" to "0", "guest" to "")) as TypePricesCheck.Ok
        assertEquals(listOf(PriceIn("junior", 300), PriceIn("coach", 0)), ok.prices)
        val bad = checkTypePrices(mapOf("junior" to "lots", "guest" to "1001")) as TypePricesCheck.Invalid
        assertEquals(setOf("junior", "guest"), bad.problems.keys)
        assertTrue(checkTypePrices(mapOf("junior" to "-0")) is TypePricesCheck.Invalid)
    }

    /** Every `pa3.*` key the app asks for is in the table, so nobody reads a bare key. */
    @Test
    fun `every passes and group fees string the app uses exists`() {
        val english = Strings.keys(Language.EN)
        val sources = File("src/main/kotlin").walkTopDown().filter { it.extension == "kt" }.map { it.readText() }.joinToString("\n")
        val used = Regex("\"(pa[23]\\.[a-z0-9_]+)\"").findAll(sources).map { it.groupValues[1] }.toSet()
        assertTrue("found no step B and C strings", used.count { it.startsWith("pa3.") } > 100)
        val missing = used.filter { it !in english && "$it.other" !in english }
        assertTrue("missing from en.json: $missing", missing.isEmpty())
    }
}

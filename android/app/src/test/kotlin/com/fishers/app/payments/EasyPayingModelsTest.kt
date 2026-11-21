package com.fishers.app.payments

import com.fishers.app.EnglishStrings
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * Step A's shapes, from the responses the running API gave
 * (`.dev/payments/examples/stepA_*.json`), and the pay screen's plain words.
 */
class EasyPayingModelsTest {
    @get:Rule val english = EnglishStrings()

    // ---- decoding ----

    @Test
    fun `the pay screen says who the money goes to, and what they are to the club`() {
        val pay = Captured.read<PayScreen>("stepA_pay_screen")
        val account = requireNotNull(pay.account)
        assertEquals("secretary", account.payeeRole)
        assertEquals("SHARMA", pay.reference)
        assertEquals("Pay Aman Gill, the club secretary.", account.payeeLine())
        assertEquals("This is Aman's own bank account. The club uses it to collect money.", account.whoseAccount())
        assertEquals("Aman", account.payeeShortName)
        assertEquals("Thanks. Waiting for Aman to check it arrived.", account.waitingLine())
        val claim = pay.claims.first()
        assertFalse(claim.hasScreenshot)
        assertNull(claim.viaLink)
        assertNull(claim.shareId)
    }

    @Test
    fun `a club's own account is named as the club's, with no role`() {
        val account = Captured.read<PayScreen>("pay_screen").account!!
        assertNull("phase 1 sent no role, and that still reads", account.payeeRole)
        assertEquals("Pay Riverside Strikers CC.", account.payeeLine())
        assertEquals("This is the club's own bank account.", account.whoseAccount())
        assertEquals("Riverside Strikers CC", account.payeeShortName)
        assertEquals("Thanks. Waiting for the club to check it arrived.", account.waitingLine())
    }

    @Test
    fun `each role is said in words, and one the app does not know is left unsaid`() {
        val aman = BankDetails(holderName = "Aman Gill", isPersonal = true)
        assertEquals("Pay Aman Gill, the club treasurer.", aman.copy(payeeRole = "treasurer").payeeLine())
        assertEquals("Pay Aman Gill, who runs the club.", aman.copy(payeeRole = "owner").payeeLine())
        assertEquals("Pay Aman Gill.", aman.copy(payeeRole = "chairman").payeeLine())
        assertEquals("Pay Aman Gill.", aman.payeeLine())
    }

    @Test
    fun `a payment carries its line, its link and whether a picture came with it`() {
        val text = """{"id":"p1","amount_cents":1500,"status":"claimed","share_id":"s1",
            "via_link":"l1","has_screenshot":true,"method":"transfer"}"""
        val p = Captured.json.decodeFromString<Payment>(text)
        assertEquals("s1", p.shareId)
        assertEquals("l1", p.viaLink)
        assertTrue(p.hasScreenshot)
    }

    @Test
    fun `a line from a pass, with no event and a state this version only half knows, still reads`() {
        val text = """{"id":"s9","bill_id":null,"event_id":null,"kind":"pass","due_on":"2026-12-01",
            "title":"December nets pass","amount_cents":0,"paid_cents":0,"waiting_cents":0,"currency":"GBP",
            "state":"covered","reason":null,"name":"Ravi Sharma"}"""
        val share = Captured.json.decodeFromString<Share>(text)
        assertNull(share.eventId)
        assertEquals("pass", share.kind)
        assertEquals("2026-12-01", share.dueOn)
        assertEquals(ShareState.Covered, share.state)
        assertEquals("Covered by your pass ✓", share.state.label)
        assertEquals(0L, share.leftCents)
        assertFalse("nothing to let off", share.canLetOff)

        val odd = Captured.json.decodeFromString<Share>(text.replace("\"covered\"", "\"on_hold\"").replace("\"pass\"", "\"tour\""))
        assertEquals(ShareState.Unknown, odd.state)
        assertEquals("tour", odd.kind)
    }

    @Test
    fun `dues with a pass charge in them load whole`() {
        val text = """{"clubs":[{"club_id":"c1","club_name":"Riverside","owed_cents":3000,"shares":[
            {"id":"a","event_id":"e1","title":"Friday nets","amount_cents":1500,"state":"owed"},
            {"id":"b","event_id":null,"kind":"collection","title":"League fee","amount_cents":1500,"state":"owed"}]}]}"""
        val dues = Captured.json.decodeFromString<Dues>(text)
        assertEquals(listOf("e1", null), dues.clubs.single().shares.map { it.eventId })
    }

    @Test
    fun `the usual prices are read back from the settings`() {
        val settings = Captured.read<MoneySettings>("stepA_settings")
        assertEquals("split_total", settings.defaultNetsMode)
        assertEquals(6000L, settings.defaultNetsCents)
        assertEquals(500L, settings.defaultMatchFeeCents)
        assertTrue(settings.hasUsualPrices)
        assertEquals(CostMode.SplitTotal, settings.usualNets?.mode)
        assertEquals("£60.00, split between whoever comes", usualNetsWords(settings, "GBP"))

        val none = Captured.read<MoneyOverview>("money_overview").settings
        assertFalse("phase 1's settings have none", none.hasUsualPrices)
        assertNull(none.usualNets)
    }

    @Test
    fun `a bill's link comes with the server's words for the group`() {
        val link = Captured.read<BillLink>("stepA_bill_link")
        assertTrue(link.url.contains("/p/"))
        assertTrue(link.billMessage.startsWith("🏏 Friday nets"))
        assertTrue(link.reminderMessage.startsWith("Still to pay for Friday nets"))
        assertEquals(listOf("Aman Gill", "Tom Bennett"), link.stillToPay)
    }

    // ---- the pay screen's words ----

    @Test
    fun `you owe, and what for`() {
        val pay = Captured.read<PayScreen>("pay_screen")
        assertEquals("You owe £15.00 for Friday nets", pay.oweHeadline())

        val two = pay.copy(
            owedCents = 3000,
            shares = pay.shares + pay.shares.first().copy(id = "x", title = "Sunday match"),
        )
        assertEquals("You owe £30.00 for Friday nets and 1 more", two.oweHeadline())
        val three = two.copy(owedCents = 4500, shares = two.shares + two.shares.first().copy(id = "y"))
        assertEquals("You owe £45.00 for Friday nets and 2 more", three.oweHeadline())

        val untitled = pay.copy(shares = emptyList())
        assertEquals("You owe £15.00.", untitled.oweHeadline())
    }

    @Test
    fun `the month a standing order pays is not named in what you owe`() {
        val pay = Captured.read<PayScreen>("pay_screen")
        val nets = pay.shares.first()
        val month = nets.copy(id = "m", title = "Monthly nets — November 2026", kind = "pass", dueOn = "2026-11-28", amountCents = 2000)
        // The server's amount is Friday nets only; the pass charge is the standing order's.
        val withOrder = pay.copy(shares = listOf(month, nets), standingOrderCents = 2000)
        val today = java.time.LocalDate.parse("2026-11-22")
        assertEquals("You owe £15.00 for Friday nets", withOrder.oweHeadline(today))
        // Past its due day the standing order has not paid it: it is to pay by hand.
        assertEquals(
            "You owe £15.00 for Monthly nets — November 2026 and 1 more",
            withOrder.oweHeadline(java.time.LocalDate.parse("2026-11-29")),
        )
        // Without a standing order it is just another line.
        assertEquals(2, withOrder.copy(standingOrderCents = 0).byHandShares(today).size)
    }

    @Test
    fun `waiting and paid lines are not counted as owed`() {
        val pay = Captured.read<PayScreen>("stepA_pay_screen")
        assertTrue("everything is waiting", pay.owedShares.isEmpty())
    }

    @Test
    fun `the details to send someone else are everything a banking app asks for`() {
        val pay = Captured.read<PayScreen>("pay_screen").copy(reference = "SHARMA")
        val text = pay.detailsToSend()
        assertEquals(
            listOf(
                "Please pay £15.00 to Riverside Strikers (demo), for Friday nets.",
                "",
                "Name: Riverside Strikers CC",
                "Sort code: 20-00-00",
                "Account number: 55779911",
                "In the reference box, write: SHARMA",
            ),
            text.lines(),
        )
        assertEquals("", pay.copy(account = null).detailsToSend())
    }

    @Test
    fun `the account number never reaches a log line`() {
        val account = Captured.read<PayScreen>("stepA_pay_screen").account!!
        assertFalse(account.toString().contains("12345678"))
        assertFalse(Captured.read<PayScreen>("stepA_pay_screen").toString().contains("12345678"))
    }

    // ---- the usual prices form ----

    /** What `Network` sends with: nulls left out, defaults kept. */
    private val wire = Json {
        explicitNulls = false
        encodeDefaults = true
    }

    @Test
    fun `usual prices are sent as the settings call takes them, and nothing else changes`() {
        val check = checkUsualPrices(CostMode.SplitTotal, "60", "5.00") as UsualPricesCheck.Ok
        val json = wire.encodeToJsonElement(MoneySettingsBody.serializer(), check.body).jsonObject
        assertEquals(setOf("default_nets", "default_match_fee_cents"), json.keys)
        assertEquals("""{"mode":"split_total","amount_cents":6000}""", json["default_nets"].toString())
        assertEquals("500", json["default_match_fee_cents"].toString())
    }

    @Test
    fun `either price may be left out, and a wrong one is said beside its box`() {
        val netsOnly = checkUsualPrices(CostMode.PerPlayer, "5", "") as UsualPricesCheck.Ok
        assertEquals(DefaultPrice("per_player", 500), netsOnly.body.defaultNets)
        assertNull(netsOnly.body.defaultMatchFeeCents)

        val neither = checkUsualPrices(CostMode.SplitTotal, " ", "") as UsualPricesCheck.Ok
        assertNull(neither.body.defaultNets)
        assertNull(neither.body.defaultMatchFeeCents)

        val bad = checkUsualPrices(CostMode.SplitTotal, "abc", "2000") as UsualPricesCheck.Invalid
        assertEquals("Type an amount, like 7.50.", bad.netsProblem)
        assertEquals("That's more than one cost can be. Check the amount.", bad.feeProblem)
    }

    @Test
    fun `a club with nothing set up needs the wizard, but only for somebody who can finish it`() {
        val overview = Captured.read<MoneyOverview>("money_overview")
        assertFalse("the demo club has details", overview.needsSetup)
        val empty = overview.copy(account = PayoutAccounts(canManage = true))
        assertTrue(empty.needsSetup)
        assertFalse(empty.copy(account = PayoutAccounts(canManage = false)).needsSetup)
        assertFalse(
            "usual prices count as set up",
            empty.copy(settings = empty.settings.copy(defaultMatchFeeCents = 500)).needsSetup,
        )
    }

    @Test
    fun `first names, as a player would say them`() {
        assertEquals("Aman", firstName("Aman Gill"))
        assertEquals("Aman", firstName("  Aman   Singh Gill "))
        assertEquals("Prince", firstName("Prince"))
    }
}

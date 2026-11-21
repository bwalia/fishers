package com.fishers.app.payments

import com.fishers.app.EnglishStrings
import com.fishers.app.i18n.Language
import com.fishers.app.i18n.Strings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.io.File
import java.time.Instant

/**
 * The payments shapes, read from real responses — the ones the running API
 * gave for the demo club — and the small rules the forms apply.
 */
class PaymentModelsTest {
    @get:Rule val english = EnglishStrings()

    // ---- decoding what the server sends ----

    @Test
    fun `a billed event, as its secretary reads it`() {
        val money = Captured.read<EventMoney>("bill_billed_admin")
        assertTrue(money.canBill)
        assertTrue(money.canManageMoney)
        assertEquals(CostMode.SplitTotal, money.cost?.mode)
        assertEquals(6000L, money.cost?.amountCents)
        val bill = requireNotNull(money.bill)
        assertEquals(1, bill.version)
        assertEquals(1500L, bill.paidCents)
        assertEquals(1500L, bill.waitingCents)
        assertEquals(3000L, bill.owedCents)
        assertEquals(4, money.shares.size)
        assertEquals(
            listOf(ShareState.Owed, ShareState.Paid, ShareState.Owed, ShareState.Waiting),
            money.shares.map { it.state },
        )
        assertEquals("Aman Gill", money.myShare?.name)
        assertEquals("who came is ticked from the server's suggestion", 4, money.candidates.count { it.suggested })
        assertTrue(money.isWorthShowing)
        assertTrue(money.hasEnded(Instant.parse("2026-11-21T00:00:00Z")))
    }

    @Test
    fun `a player sees their own share only, and nothing to tick`() {
        val money = Captured.read<EventMoney>("bill_billed_player")
        assertFalse(money.canBill)
        assertFalse(money.canManageMoney)
        assertEquals(listOf("Ravi Sharma"), money.shares.map { it.name })
        assertEquals(1500L, money.myShare?.leftCents)
        assertTrue(money.candidates.isEmpty())
        assertTrue("their share is worth showing", money.isWorthShowing)
    }

    @Test
    fun `an unbilled match with a fee a head`() {
        val money = Captured.read<EventMoney>("bill_unbilled_admin")
        assertNull(money.bill)
        assertEquals(CostMode.PerPlayer, money.cost?.mode)
        assertEquals("£5.00 each", money.cost?.summary)
        assertEquals(listOf("Josh Turner", "Ravi Sharma", "Tom Bennett"), money.candidates.filter { it.suggested }.map { it.name })
    }

    @Test
    fun `the preview says what each pays, odd pennies and all`() {
        val preview = Captured.read<BillPreview>("bill_preview")
        assertEquals("Guest Gary", preview.shares.last().name)
        assertNull(preview.shares.last().userId)
        assertEquals("£20.00 between 4: £5.00 each", preview.summary)

        val uneven = BillPreview(
            shares = List(6) { PreviewShare(name = "p$it", amountCents = 667) } + List(3) { PreviewShare(name = "q$it", amountCents = 666) },
            totalCents = 6000,
        )
        assertEquals("£60.00 between 9: 6 pay £6.67, 3 pay £6.66", uneven.summary)
        val one = BillPreview(shares = listOf(PreviewShare(name = "solo", amountCents = 500)), totalCents = 500)
        assertEquals("£5.00 for 1 person", one.summary)
    }

    @Test
    fun `what you owe, across clubs`() {
        val dues = Captured.read<Dues>("me_dues")
        assertEquals(1, dues.owing.size)
        assertEquals("Riverside Strikers (demo)", dues.owing.single().clubName)
        assertEquals(1500L, dues.owing.single().owedCents)
        assertTrue(dues.hasAnything)
        assertTrue(Dues().owing.isEmpty())
        assertFalse(Dues().hasAnything)
    }

    @Test
    fun `the pay screen, with the details to copy`() {
        val pay = Captured.read<PayScreen>("pay_screen")
        assertEquals(AccountState.Active, pay.accountState)
        assertTrue(pay.canPay)
        assertEquals("8VF52 SHARMA", pay.reference)
        assertEquals("20-00-00", pay.account?.sortCode)
        assertEquals(
            "Amount: £15.00\nName: Riverside Strikers CC\nSort code: 20-00-00\nAccount number: 55779911\nReference: 8VF52 SHARMA",
            pay.copyAll(),
        )
    }

    @Test
    fun `the full account number never reaches a log through toString`() {
        val pay = Captured.read<PayScreen>("pay_screen")
        val printed = pay.account.toString() + pay.toString()
        assertFalse("printed: $printed", printed.contains("55779911"))
        assertTrue(printed.contains("••••9911"))
        val body = AddBankDetailsBody("Riverside", "200000", "55779911", password = "hunter2")
        assertFalse(body.toString().contains("55779911"))
        assertFalse(body.toString().contains("hunter2"))
    }

    @Test
    fun `nothing owed, and a claim waiting for the club`() {
        val settled = Captured.read<PayScreen>("pay_screen_nothing_owed")
        assertEquals(AccountState.NothingOwed, settled.accountState)
        assertNull(settled.account)
        assertFalse(settled.canPay)

        val waiting = Captured.read<PayScreen>("pay_screen_waiting")
        assertEquals(0L, waiting.owedCents)
        assertEquals(1500L, waiting.waitingCents)
        assertFalse("nothing left to pay", waiting.canPay)
        val claim = waiting.claims.single()
        assertTrue(claim.isClaimed)
        assertEquals(PaymentMethod.Transfer, claim.method)
        assertEquals("DS69N BENNETT", claim.reference)
    }

    @Test
    fun `the treasurer's overview`() {
        val money = Captured.read<MoneyOverview>("money_overview")
        assertTrue(money.settings.autoBill)
        assertEquals(24, money.settings.autoBillAfterHours)
        assertTrue(money.account.canManage)
        assertFalse(money.account.isOwner)
        assertEquals(PayoutState.Active, money.account.current?.state)
        assertEquals("9911", money.account.current?.last4)
        assertEquals(listOf("Tom Bennett"), money.toCheck.map { it.name })
        assertEquals(3, money.members.size)
        assertEquals(3000L, money.totals.owedCents)
        val bill = money.bills.single()
        assertEquals(4, bill.people)
        assertEquals(2, bill.unpaid)
        assertEquals(1, bill.waiting)
    }

    @Test
    fun `bank details as an admin and a member read them`() {
        val admin = Captured.read<PayoutAccounts>("payout_account_admin")
        assertTrue(admin.canManage)
        assertTrue(admin.isOwner)
        assertTrue(admin.current?.readable == true)
        val member = Captured.read<PayoutAccounts>("payout_account_member")
        assertFalse(member.canManage)
        assertNull(member.pending)
        val claimed = Captured.json.decodeFromString<List<Payment>>(Captured.text("payments_claimed"))
        assertEquals(1500L, claimed.single().amountCents)
    }

    /**
     * A word the server adds later must cost one label, not the screen: the
     * phones decode states leniently (§1 of the plan).
     */
    @Test
    fun `an unknown state, account state or method does not fail the whole response`() {
        val text = Captured.text("pay_screen_waiting")
            .replace("\"state\": \"waiting\"", "\"state\": \"disputed\"")
            .replace("\"account_state\": \"active\"", "\"account_state\": \"on_hold\"")
            .replace("\"method\": \"transfer\"", "\"method\": \"upi\"")
        val pay = Captured.json.decodeFromString<PayScreen>(text)
        assertEquals(ShareState.Unknown, pay.shares.single().state)
        assertEquals("", ShareState.Unknown.label)
        assertEquals(AccountState.Unknown, pay.accountState)
        assertEquals(PaymentMethod.Unknown, pay.claims.single().method)

        val overview = Captured.text("money_overview").replace("\"state\": \"active\"", "\"state\": \"quarantined\"")
        assertEquals(PayoutState.Unknown, Captured.json.decodeFromString<MoneyOverview>(overview).account.current?.state)

        val walkIn = Captured.json.decodeFromString<Candidate>("""{"user_id":"u9","name":"New Nick","rsvp":"not_invited","attended":null,"suggested":false}""")
        assertFalse(walkIn.wasAsked)
        assertEquals(CostMode.PerPlayer, CostMode.of("by_the_hour"))
    }

    // ---- amounts typed in ----

    @Test
    fun `amounts are read as people type them`() {
        assertEquals(750L, parseAmount("7.50"))
        assertEquals(750L, parseAmount("7.5"))
        assertEquals(700L, parseAmount("7"))
        assertEquals(750L, parseAmount("£7.50"))
        assertEquals(100_000L, parseAmount("1,000"))
        assertEquals(50L, parseAmount(".5"))
        assertNull(parseAmount(""))
        assertNull(parseAmount("0"))
        assertNull(parseAmount("7.505"))
        assertNull(parseAmount("seven"))
        assertNull(parseAmount("-5"))
        assertEquals("7.50", amountText(750))
        assertEquals("60", amountText(6000))
    }

    @Test
    fun `a cost asks above 100 a head and stops at the server's limits`() {
        assertEquals(CostCheck.Ok(6000), checkCost(CostMode.SplitTotal, "60"))
        assertEquals(CostCheck.Ok(10_000), checkCost(CostMode.PerPlayer, "100"))
        assertEquals(CostCheck.Confirm(15_000), checkCost(CostMode.PerPlayer, "150"))
        assertEquals("a total is shared, so a big one is not asked about", CostCheck.Ok(50_000), checkCost(CostMode.SplitTotal, "500"))
        assertTrue(checkCost(CostMode.PerPlayer, "1000.01") is CostCheck.Invalid)
        assertTrue(checkCost(CostMode.SplitTotal, "10000.01") is CostCheck.Invalid)
        assertTrue(checkCost(CostMode.SplitTotal, "") is CostCheck.Invalid)
    }

    @Test
    fun `bank details are checked before they are sent`() {
        assertEquals("Put the name exactly as it is on the account.", bankDetailsProblem(" ", "20-00-00", "55779911", "55779911"))
        assertEquals("A sort code is six digits, like 12-34-56.", bankDetailsProblem("Club", "20-00-0", "55779911", "55779911"))
        assertEquals("A UK account number is eight digits.", bankDetailsProblem("Club", "200000", "557799", "557799"))
        assertNotNull("the two typed numbers must agree", bankDetailsProblem("Club", "20 00 00", "55779911", "55779912"))
        assertNull(bankDetailsProblem("Club", "20 00 00", "5577 9911", "55779911"))
        assertNull("seven digits: the server adds the leading zero", bankDetailsProblem("Club", "200000", "5779911", "5779911"))
    }

    /** Every `pay.*` key the app asks for is in the table, so nobody reads a bare key. */
    @Test
    fun `every payments string the app uses exists`() {
        val english = Strings.keys(Language.EN)
        val sources = File("src/main/kotlin").walkTopDown().filter { it.extension == "kt" }.map { it.readText() }.joinToString("\n")
        val used = Regex("\"(pay\\.[a-z0-9_]+)\"").findAll(sources).map { it.groupValues[1] }.toSet()
        assertTrue("found no payments strings at all", used.size > 50)
        val missing = used.filter { it !in english && "$it.other" !in english }
        assertTrue("missing from en.json: $missing", missing.isEmpty())
    }
}

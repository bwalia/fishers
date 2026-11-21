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
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** The treasurer's side of step A: All arrived, screenshots, the setup wizard and the usual prices. */
@OptIn(ExperimentalCoroutinesApi::class)
class ClubMoneyEasyTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val club = "814f6802-c8e0-44c2-a9f7-f2a86c06c1d7"

    private open class Tara(var overview: MoneyOverview = Captured.read("money_overview")) : FakePaymentsApi() {
        var loads = 0
        val confirmed = mutableListOf<List<String>>()
        var skipped = 0
        val settings = mutableListOf<MoneySettingsBody>()
        val added = mutableListOf<AddBankDetailsBody>()
        override suspend fun money(clubId: String): MoneyOverview {
            loads++
            return overview
        }
        override suspend fun confirmMany(clubId: String, body: ConfirmManyBody): ConfirmedMany {
            confirmed += body.ids
            return ConfirmedMany(confirmed = body.ids.size - skipped, skipped = skipped)
        }
        override suspend fun screenshot(paymentId: String): ResponseBody =
            byteArrayOf(9, 8, 7).toResponseBody("image/png".toMediaType())
        override suspend fun updateMoneySettings(clubId: String, body: MoneySettingsBody): MoneySettings {
            settings += body
            return overview.settings.copy(
                defaultNetsMode = body.defaultNets?.mode,
                defaultNetsCents = body.defaultNets?.amountCents,
                defaultMatchFeeCents = body.defaultMatchFeeCents,
            )
        }
        override suspend fun addPayoutAccount(clubId: String, body: AddBankDetailsBody): PayoutAccounts {
            added += body
            return PayoutAccounts(
                canManage = true,
                current = PayoutAccount(id = "a1", holderName = body.holderName, last4 = body.accountNumber.takeLast(4), stateName = "active"),
            )
        }
    }

    /** A new club: nothing set up, and Aman can set it up. */
    private fun emptyClub() = Captured.read<MoneyOverview>("money_overview").copy(
        account = PayoutAccounts(canManage = true, isOwner = true),
        toCheck = emptyList(),
    )

    private fun model(api: FakePaymentsApi) = ClubMoneyViewModel(api, club, AttemptKeys { "k" }, saveDelayMs = 0)

    // ---- all arrived ----

    @Test
    fun `all arrived confirms every payment on the list in one go`() = runTest(dispatcher.scheduler) {
        val api = Tara()
        val model = model(api)
        model.load()
        advanceUntilIdle()
        val ids = api.overview.toCheck.map { it.id }
        assertTrue(ids.isNotEmpty())

        model.confirmAll()
        assertTrue("each row waits", model.state.value.deciding.containsAll(ids))
        advanceUntilIdle()

        assertEquals(listOf(ids), api.confirmed)
        val state = model.state.value
        assertEquals("1 payment marked as arrived.", state.message)
        assertFalse(state.confirmingAll)
        assertTrue(state.deciding.isEmpty())
        assertEquals("read again", 2, api.loads)
    }

    @Test
    fun `ones somebody else already checked are said, not failed`() = runTest(dispatcher.scheduler) {
        val api = Tara().apply {
            overview = overview.copy(toCheck = overview.toCheck + overview.toCheck.first().copy(id = "p2") + overview.toCheck.first().copy(id = "p3"))
            skipped = 1
        }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        model.confirmAll()
        advanceUntilIdle()
        assertEquals("2 payments marked as arrived. 1 had already been checked by someone else.", model.state.value.message)
    }

    @Test
    fun `all arrived with nothing to check sends nothing`() = runTest(dispatcher.scheduler) {
        val api = Tara(emptyClub())
        val model = model(api)
        model.load()
        advanceUntilIdle()
        model.confirmAll()
        advanceUntilIdle()
        assertTrue(api.confirmed.isEmpty())
    }

    // ---- screenshots ----

    @Test
    fun `a payment's screenshot is fetched when opened, and closed again`() = runTest(dispatcher.scheduler) {
        val api = Tara()
        val model = model(api)
        model.load()
        advanceUntilIdle()
        val payment = api.overview.toCheck.first().copy(hasScreenshot = true)

        model.openScreenshot(payment)
        assertNull("loading", model.state.value.screenshot?.bytes)
        advanceUntilIdle()
        assertArrayEquals(byteArrayOf(9, 8, 7), model.state.value.screenshot?.bytes)

        model.closeScreenshot()
        assertNull(model.state.value.screenshot)
    }

    @Test
    fun `no screenshot, nothing to open`() = runTest(dispatcher.scheduler) {
        val model = model(Tara())
        model.openScreenshot(Payment(id = "p", hasScreenshot = false))
        assertNull(model.state.value.screenshot)
    }

    @Test
    fun `a screenshot that cannot be fetched says why`() = runTest(dispatcher.scheduler) {
        val api = object : Tara() {
            override suspend fun screenshot(paymentId: String): ResponseBody = throw refused(404, "No picture with this payment")
        }
        val model = model(api)
        model.openScreenshot(Payment(id = "p", hasScreenshot = true))
        advanceUntilIdle()
        assertNull(model.state.value.screenshot)
        assertEquals("No picture with this payment", model.state.value.error)
    }

    // ---- the setup wizard ----

    @Test
    fun `a club with nothing set up opens on the wizard, and goes through its three steps`() = runTest(dispatcher.scheduler) {
        val api = Tara(emptyClub())
        val model = model(api)
        model.load()
        advanceUntilIdle()
        assertEquals(SetupStep.Bank, model.state.value.setup)
        assertNotNull("the bank form is ready", model.state.value.form)

        model.saveBankDetails("Aman Gill", "40-11-22", "12345678", "12345678", isPersonal = true, password = "password123")
        advanceUntilIdle()
        assertEquals("Aman Gill", api.added.single().holderName)
        assertEquals(SetupStep.Prices, model.state.value.setup)

        model.saveUsualPrices(CostMode.SplitTotal, "60", "5")
        advanceUntilIdle()
        assertEquals(DefaultPrice("split_total", 6000), api.settings.single().defaultNets)
        assertEquals(500L, api.settings.single().defaultMatchFeeCents)
        assertEquals(SetupStep.Done, model.state.value.setup)
        assertEquals(6000L, model.state.value.overview?.settings?.defaultNetsCents)

        model.finishSetup()
        assertNull(model.state.value.setup)
        assertFalse("set up now", model.state.value.offerSetup)
    }

    @Test
    fun `each step can be skipped, and an empty prices form is skipping too`() = runTest(dispatcher.scheduler) {
        val api = Tara(emptyClub())
        val model = model(api)
        model.load()
        advanceUntilIdle()
        model.skipSetupStep()
        assertEquals(SetupStep.Prices, model.state.value.setup)
        model.saveUsualPrices(CostMode.SplitTotal, "", "")
        advanceUntilIdle()
        assertTrue("nothing sent", api.settings.isEmpty())
        assertEquals(SetupStep.Done, model.state.value.setup)
    }

    @Test
    fun `a wrong price stays on the step, said beside its box`() = runTest(dispatcher.scheduler) {
        val api = Tara(emptyClub())
        val model = model(api)
        model.load()
        advanceUntilIdle()
        model.skipSetupStep()
        model.saveUsualPrices(CostMode.PerPlayer, "lots", "")
        advanceUntilIdle()
        assertEquals(SetupStep.Prices, model.state.value.setup)
        assertEquals("Type an amount, like 7.50.", model.state.value.prices?.netsProblem)
        assertTrue(api.settings.isEmpty())
    }

    @Test
    fun `not now leaves a card to come back to, and a reload does not push the wizard again`() = runTest(dispatcher.scheduler) {
        val api = Tara(emptyClub())
        val model = model(api)
        model.load()
        advanceUntilIdle()
        model.putOffSetup()
        assertNull(model.state.value.setup)
        assertTrue(model.state.value.offerSetup)

        model.load()
        advanceUntilIdle()
        assertNull(model.state.value.setup)

        model.startSetup()
        assertEquals(SetupStep.Bank, model.state.value.setup)
    }

    @Test
    fun `nobody is sent into the wizard who could not finish it, or whose club is set up`() = runTest(dispatcher.scheduler) {
        val notAdmin = Tara(emptyClub().copy(account = PayoutAccounts(canManage = false)))
        model(notAdmin).also { it.load(); advanceUntilIdle(); assertNull(it.state.value.setup); assertFalse(it.state.value.offerSetup) }

        val setUp = Tara()
        model(setUp).also { it.load(); advanceUntilIdle(); assertNull(it.state.value.setup) }
    }

    // ---- usual prices, later ----

    @Test
    fun `the usual prices can be changed from settings`() = runTest(dispatcher.scheduler) {
        val api = Tara()
        val model = model(api)
        model.load()
        advanceUntilIdle()
        model.openPrices()
        assertNotNull(model.state.value.prices)
        model.saveUsualPrices(CostMode.PerPlayer, "6.50", "")
        advanceUntilIdle()
        assertEquals(DefaultPrice("per_player", 650), api.settings.single().defaultNets)
        assertNull(model.state.value.prices)
        assertEquals("Usual prices saved.", model.state.value.message)
        assertNull("not in the wizard", model.state.value.setup)
    }
}

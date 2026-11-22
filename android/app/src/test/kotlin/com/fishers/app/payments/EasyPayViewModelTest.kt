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
import okhttp3.RequestBody
import okio.Buffer
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** The rewritten pay screen: the first-time guide, screenshots, and the refusals that mean "look again". */
@OptIn(ExperimentalCoroutinesApi::class)
class EasyPayViewModelTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val club = "814f6802-c8e0-44c2-a9f7-f2a86c06c1d7"

    /** Ravi, who owes £15 and then says he paid. Uploads are kept. */
    private open class Ravi : FakePaymentsApi() {
        var screen = Captured.read<PayScreen>("pay_screen")
        var loads = 0
        var claimFails: Throwable? = null
        var uploadFails: Throwable? = null
        val uploads = mutableListOf<Triple<String, String?, ByteArray>>()
        override suspend fun payScreen(clubId: String): PayScreen {
            loads++
            return screen
        }
        override suspend fun claimPayment(clubId: String, idempotencyKey: String, body: ClaimBody): Payment {
            claimFails?.let { claimFails = null; throw it }
            screen = Captured.read("stepA_pay_screen")
            return screen.claims.first()
        }
        override suspend fun uploadScreenshot(paymentId: String, image: RequestBody) {
            val bytes = Buffer().also { image.writeTo(it) }.readByteArray()
            uploads += Triple(paymentId, image.contentType()?.toString(), bytes)
            uploadFails?.let { uploadFails = null; throw it }
        }
    }

    private fun model(api: FakePaymentsApi, guide: PayGuideMemory = PayGuideMemory.InMemory()): PayViewModel {
        var n = 0
        return PayViewModel(api, club, AttemptKeys { "key-${++n}" }, guide)
    }

    @Test
    fun `the first time shows the guide, and a transfer from this phone makes it as usual`() = runTest(dispatcher.scheduler) {
        val guide = PayGuideMemory.InMemory()
        val model = model(Ravi(), guide)
        model.load()
        advanceUntilIdle()
        assertFalse(model.state.value.guideSeen)

        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()

        assertTrue(model.state.value.guideSeen)
        assertTrue("remembered on the phone", guide.seen())
        assertTrue("a phone that has paid before opens as usual", model(Ravi(), guide).state.value.guideSeen)
    }

    @Test
    fun `paying cash does not count as having learnt the bank transfer`() = runTest(dispatcher.scheduler) {
        val guide = PayGuideMemory.InMemory()
        val model = model(Ravi(), guide)
        model.load()
        advanceUntilIdle()
        model.claim(PaymentMethod.Cash)
        advanceUntilIdle()
        assertFalse(guide.seen())
        assertFalse(model.state.value.guideSeen)
    }

    @Test
    fun `a screenshot goes up as JPEG bytes for that payment, then the screen is read again`() = runTest(dispatcher.scheduler) {
        val api = Ravi().apply { screen = Captured.read("stepA_pay_screen") }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        val claim = model.state.value.pay!!.claims.first()
        val loadsBefore = api.loads

        val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 1, 2, 3)
        model.attachScreenshot(claim.id, jpeg)
        assertEquals("the row waits while it goes", claim.id, model.state.value.attaching)
        advanceUntilIdle()

        val (id, type, bytes) = api.uploads.single()
        assertEquals(claim.id, id)
        // As JSON {"image": base64}: one brand's edge passes only JSON bodies.
        assertEquals("application/json; charset=utf-8", type)
        val sent = kotlinx.serialization.json.Json.parseToJsonElement(bytes.decodeToString())
        val image = (sent as kotlinx.serialization.json.JsonObject)["image"]!!.toString().trim('"')
        assertArrayEquals(jpeg, java.util.Base64.getDecoder().decode(image))
        assertNull(model.state.value.attaching)
        assertEquals("Screenshot added. Thank you.", model.state.value.message)
        assertEquals(loadsBefore + 1, api.loads)
    }

    @Test
    fun `a screenshot for a payment already checked says so and shows where it is`() = runTest(dispatcher.scheduler) {
        val api = Ravi().apply {
            screen = Captured.read("stepA_pay_screen")
            uploadFails = refused(409, "The club has already checked that one.", "already_decided")
        }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        val loadsBefore = api.loads

        model.attachScreenshot(model.state.value.pay!!.claims.first().id, byteArrayOf(1))
        advanceUntilIdle()

        assertEquals("The club has already checked that one.", model.state.value.error)
        assertEquals("read again", loadsBefore + 1, api.loads)
    }

    @Test
    fun `a picture the server will not keep is refused in its own words`() = runTest(dispatcher.scheduler) {
        val api = Ravi().apply {
            screen = Captured.read("stepA_pay_screen")
            uploadFails = refused(415, "That isn't a picture we can keep (JPEG, PNG or WebP).", "not_an_image")
        }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        val loadsBefore = api.loads
        model.attachScreenshot(model.state.value.pay!!.claims.first().id, byteArrayOf(1))
        advanceUntilIdle()
        assertEquals("That isn't a picture we can keep (JPEG, PNG or WebP).", model.state.value.error)
        assertEquals("nothing changed, so nothing to read again", loadsBefore, api.loads)
    }

    @Test
    fun `the picker's own problem is shown like any other`() = runTest(dispatcher.scheduler) {
        val model = model(Ravi())
        model.screenshotProblem("That picture couldn't be opened.")
        assertEquals("That picture couldn't be opened.", model.state.value.error)
    }

    @Test
    fun `I've paid on a line the club already decided reads the screen again`() = runTest(dispatcher.scheduler) {
        val api = Ravi().apply { claimFails = refused(409, "The club has already checked that one.", "already_decided") }
        val model = model(api)
        model.load()
        advanceUntilIdle()
        val loadsBefore = api.loads
        model.claim(PaymentMethod.Transfer)
        advanceUntilIdle()
        assertEquals("The club has already checked that one.", model.state.value.error)
        assertEquals(loadsBefore + 1, api.loads)
        assertFalse(model.state.value.guideSeen)
    }
}

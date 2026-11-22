package com.fishers.app.payments

import com.fishers.app.EnglishStrings
import com.fishers.app.clubs.refused
import com.fishers.app.i18n.Language
import com.fishers.app.i18n.Strings
import com.fishers.app.views.payments.decodeStatement
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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.io.File

/** Step D: a bank statement read, grouped, worded, applied — and never printed. */
@OptIn(ExperimentalCoroutinesApi::class)
class StatementImportTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val club = "814f6802-c8e0-44c2-a9f7-f2a86c06c1d7"
    private val csv = "Date,Description,Amount\n22/11/2026,R SHARMA SHARMA,15.00\n22/11/2026,INTEREST,0.12\n"
    private val preview = Captured.read<StatementPreview>("stepBC_statement_preview")

    // ---- what the server sends ----

    @Test
    fun `the captured preview decodes into its three groups`() {
        assertEquals("GBP", preview.currency)
        assertEquals(StatementSummary(credits = 6, confirm = 2, record = 1, check = 2, unknown = 1, already = 0), preview.summary)
        assertEquals(listOf("Rohit Sharma", "Josh Turner", "Neha Patel"), preview.toApply.map { it.who })
        assertEquals(listOf(StatementAction.Confirm, StatementAction.Confirm, StatementAction.Record), preview.toApply.map { it.action })
        assertEquals(1, preview.toApply.first().paymentIds.size)
        assertEquals(listOf("different_amount", "shared_name"), preview.toCheck.map { it.why })
        assertEquals("nobody's name: the bank's words", listOf("INTEREST"), preview.unrecognised.map { it.who })
        assertTrue(preview.already.isEmpty())
        assertEquals("2026-11-22", preview.lines.first().date)
    }

    @Test
    fun `a word this version does not know is not applied`() {
        val line = preview.lines.first().copy(actionName = "refund")
        assertEquals(StatementAction.Unknown, line.action)
        assertFalse(line.canApply)
        assertEquals(StatementAction.Already, preview.lines.first().copy(actionName = "already").action)
    }

    @Test
    fun `under each ticked-off line, what applying it does`() {
        val (rohit, _, neha) = preview.toApply
        assertEquals("Said they'd paid: this ticks it off", rohit.matchWords())
        assertEquals("Said they'd paid, for 2 people: this ticks them off", rohit.copy(paymentIds = listOf("a", "b")).matchWords())
        assertEquals("Hadn't said they'd paid: recorded as paid", neha.matchWords())
    }

    // ---- needs a look, in words ----

    @Test
    fun `two members with one surname are named, from the club's members`() {
        val shared = preview.toCheck.single { it.why == "shared_name" }
        assertEquals(
            "Two members called SHARMA — the number was left off",
            shared.whyWords("GBP", names = listOf("Ravi Sharma", "Rohit Sharma", "Tom Bennett"), claims = emptyList()),
        )
        assertEquals(
            "3 members called SHARMA — the number was left off",
            shared.whyWords("GBP", names = listOf("Ravi Sharma", "Rohit Sharma", "Ria Sharma"), claims = emptyList()),
        )
        assertEquals("Two members share this name — the number was left off", shared.whyWords("GBP", emptyList(), emptyList()))
    }

    @Test
    fun `a different amount says what was said and what was sent, when it is known`() {
        val tom = preview.toCheck.single { it.why == "different_amount" }
        val said = Payment(id = "p1", userId = tom.userId, createdBy = tom.userId, name = "Tom Bennett", amountCents = 600, methodName = "transfer", status = "claimed")
        assertEquals("Said £6.00, sent £9.00", tom.whyWords("GBP", emptyList(), listOf(said)))
        assertEquals("Sent £9.00: not what they said they'd paid", tom.whyWords("GBP", emptyList(), emptyList()))
        assertEquals(
            "two waiting: which one is not known",
            "Sent £9.00: not what they said they'd paid",
            tom.whyWords("GBP", emptyList(), listOf(said, said.copy(id = "p2", amountCents = 500))),
        )
        assertEquals("Have a look at this one", tom.copy(why = "something_new").whyWords("GBP", emptyList(), emptyList()))
    }

    // ---- reading and applying ----

    private open class Treasurer : FakePaymentsApi() {
        val previews = mutableListOf<Pair<String?, String>>()
        val applied = mutableListOf<StatementBody>()
        var previewFails: Throwable? = null
        override suspend fun previewStatement(clubId: String, csv: RequestBody): StatementPreview {
            previews += csv.contentType()?.toString() to Buffer().also { csv.writeTo(it) }.readUtf8()
            previewFails?.let { previewFails = null; throw it }
            return Captured.read("stepBC_statement_preview")
        }
        override suspend fun applyStatement(clubId: String, body: StatementBody): StatementApplied {
            applied += body
            return StatementApplied(confirmed = 1, recorded = 1, skipped = 0)
        }
        override suspend fun moneyMembers(clubId: String): List<MoneyMember> =
            listOf(MoneyMember("u1", "Ravi Sharma"), MoneyMember("u2", "Rohit Sharma"))
        override suspend fun money(clubId: String): MoneyOverview = MoneyOverview()
    }

    @Test
    fun `the file goes as it is, every match starts ticked, and Apply sends only what is still ticked`() = runTest(dispatcher.scheduler) {
        val api = Treasurer()
        val model = StatementViewModel(api, club)
        model.read(csv)
        assertTrue(model.state.value.isReading)
        advanceUntilIdle()

        // As JSON {"csv": text}: one brand's edge passes only JSON bodies.
        val (type, sentText) = api.previews.single()
        assertEquals("application/json; charset=utf-8", type)
        assertEquals(csv, kotlinx.serialization.json.Json.parseToJsonElement(sentText).let {
            (it as kotlinx.serialization.json.JsonObject)["csv"]!!.let { v -> (v as kotlinx.serialization.json.JsonPrimitive).content }
        })
        val s = model.state.value
        assertEquals(preview.toApply.map { it.hash }.toSet(), s.ticked)
        assertEquals(listOf("Ravi Sharma", "Rohit Sharma"), s.names)

        val josh = preview.toApply[1]
        model.toggle(josh.hash)
        assertEquals(2, model.state.value.toSend.size)
        model.apply()
        advanceUntilIdle()

        val body = api.applied.single()
        assertEquals("the statement is read again by the server", csv, body.csv)
        assertEquals(preview.toApply.map { it.hash }.filter { it != josh.hash }, body.lines)
        assertEquals("2 payments ticked off.", model.state.value.done)
        assertNull(model.state.value.preview)
    }

    @Test
    fun `nothing is sent twice, and nothing with nothing ticked`() = runTest(dispatcher.scheduler) {
        val api = Treasurer()
        val model = StatementViewModel(api, club)
        model.read(csv)
        advanceUntilIdle()
        preview.toApply.forEach { model.toggle(it.hash) }
        model.apply()
        advanceUntilIdle()
        assertTrue(api.applied.isEmpty())

        model.toggle(preview.toApply.first().hash)
        model.apply()
        model.apply()
        advanceUntilIdle()
        assertEquals(1, api.applied.size)
    }

    @Test
    fun `lines done meanwhile are said, not failed`() {
        assertEquals("1 payment ticked off. 2 had changed since, so they were left alone.", StatementApplied(confirmed = 1, skipped = 2).words())
    }

    @Test
    fun `a statement the server cannot read says what to do, in the app's words`() = runTest(dispatcher.scheduler) {
        val api = Treasurer().apply {
            previewFails = refused(422, "Couldn't find the date and amount column. Export the statement as CSV from your bank and try again.", "unknown_statement")
        }
        val model = StatementViewModel(api, club)
        model.read("foo,bar\n1,2\n")
        advanceUntilIdle()
        assertEquals(
            "That doesn't look like a bank statement. Download it from your bank as a CSV file, then try again.",
            model.state.value.error,
        )
        assertNull(model.state.value.preview)

        api.previewFails = refused(422, "That file is empty.", "empty_statement")
        model.read("")
        advanceUntilIdle()
        assertEquals("That file is empty. Download the statement from your bank again.", model.state.value.error)

        api.previewFails = refused(403, "Only the club owner, a secretary or a treasurer can do that", "not_money_admin")
        model.read(csv)
        advanceUntilIdle()
        assertEquals("anything else in the server's words", "Only the club owner, a secretary or a treasurer can do that", model.state.value.error)
    }

    @Test
    fun `the statement never reaches a log line`() = runTest(dispatcher.scheduler) {
        val model = StatementViewModel(Treasurer(), club)
        model.read(csv)
        advanceUntilIdle()
        val printed = listOf(
            model.state.value.toString(),
            StatementBody(csv, listOf("h1")).toString(),
            preview.lines.joinToString(),
        ).joinToString("\n")
        assertFalse(printed.contains("SHARMA"))
        assertFalse(printed.contains("INTEREST"))
        assertEquals("StatementBody(1 lines)", StatementBody(csv, listOf("h1")).toString())
    }

    @Test
    fun `a file the bank saved in Windows-1252 keeps its pound signs`() {
        val utf8 = "Date,Amount\n22/11/2026,£15.00\n"
        assertEquals(utf8, decodeStatement(utf8.toByteArray(Charsets.UTF_8)))
        assertEquals(utf8, decodeStatement(utf8.toByteArray(charset("windows-1252"))))
    }

    /** Every `pa4.*` and `pw4.*` key the app asks for is in the table, so nobody reads a bare key. */
    @Test
    fun `every step D and security review string the app uses exists`() {
        val english = Strings.keys(Language.EN)
        val sources = File("src/main/kotlin").walkTopDown().filter { it.extension == "kt" }.map { it.readText() }.joinToString("\n")
        val used = Regex("\"(p[aw]4\\.[a-z0-9_]+)\"").findAll(sources).map { it.groupValues[1] }.toSet()
        assertTrue("found no step D strings", used.size > 30)
        val missing = used.filter { it !in english && "$it.other" !in english }
        assertTrue("missing from en.json: $missing", missing.isEmpty())
    }
}

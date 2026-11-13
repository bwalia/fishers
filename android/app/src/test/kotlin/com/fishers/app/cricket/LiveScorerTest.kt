package com.fishers.app.cricket

import com.fishers.app.EnglishStrings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * A whole match, played through the scorer's view model against the real
 * engine — the same Rust the server scores with — and a hand-written server.
 *
 * What is checked is what a scorer would see and what the server would be
 * sent: the score after each ball, the engine's refusals in its own words,
 * and that only what it accepted ever went up.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class LiveScorerTest {
    @get:Rule val english = EnglishStrings()
    @get:Rule val disk = TemporaryFolder()

    // See ClubsTest: runTest must share this dispatcher's scheduler.
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val h = MatchLog.home
    private val a = MatchLog.away
    private var ids = 0

    private fun scorer(api: FakeScoringApi, store: BallStore = FileBallStore(disk.root)) = LiveScorerViewModel(
        api = api,
        eventId = "e1",
        deviceId = "phone-1",
        store = store,
        myUserId = "u-me",
        newId = { "00000000-0000-4000-8000-%012d".format(++ids) },
        now = { null },
    )

    private val LiveScorerViewModel.view get() = state.value.view!!
    private val LiveScorerViewModel.inn get() = view.current!!

    @Test
    fun `a short match, ball by ball, to a result`() = runTest(dispatcher.scheduler) {
        val server = FakeScoringApi()
        val model = scorer(server)
        model.load()
        advanceUntilIdle()

        // What the setup wizard leaves: live, openers in, a bowler on, nothing to send.
        assertTrue(model.state.value.isLive)
        assertEquals(h[0], model.inn.strikerId)
        assertEquals(h[1], model.inn.nonStrikerId)
        assertEquals(a[0], model.inn.bowlerId)
        assertTrue("the device already holds the book, so nothing is claimed", server.claims.isEmpty())
        val setupEvents = server.log.size

        // A single: the batters cross.
        assertTrue(model.runs(1))
        assertEquals("1/0", model.inn.score)
        assertEquals(h[1], model.inn.strikerId)
        assertEquals("H1 has the single", 1, model.inn.batter(h[0])!!.runs)

        // A wide: a run, not a ball.
        assertTrue(model.extra("wide"))
        assertEquals("2/0", model.inn.score)
        assertEquals("0.1", model.inn.overs)

        // A no ball hit for four: five to the side, four to the batter, and a free hit.
        assertTrue(model.extra("no_ball", runs = 4, boundary = true, offTheBat = true))
        assertEquals("7/0", model.inn.score)
        assertEquals(4, model.inn.batter(h[1])!!.runs)
        assertEquals(1, model.inn.batter(h[1])!!.fours)
        assertTrue(model.inn.freeHit)

        // Bowled off a free hit is not out, and the engine says why.
        assertFalse(model.wicket(h[1], "bowled", newBatterId = h[2]))
        assertEquals("it is a free hit — only a run out can get them", model.state.value.error)
        assertEquals("7/0", model.inn.score)

        // Two, and the free hit is gone.
        assertTrue(model.runs(2))
        assertFalse(model.inn.freeHit)

        // Now bowled is out, and the new batter takes the striker's end.
        assertTrue(model.wicket(h[1], "bowled", newBatterId = h[2]))
        assertNull(model.state.value.error)
        assertEquals("9/1", model.inn.score)
        assertEquals(h[2], model.inn.strikerId)
        assertEquals("b A1", model.view.dismissalText(model.inn.batter(h[1])!!))
        assertEquals(Moment.Kind.Wicket, model.state.value.moment?.kind)

        assertTrue(model.runs(0))
        assertTrue(model.runs(4))
        assertTrue(model.runs(6))
        assertEquals("19/1", model.inn.score)
        assertEquals("1.0", model.inn.overs)
        assertEquals(Moment.Kind.Six, model.state.value.moment?.kind)

        // The over is done: the screen asks for a bowler, and the same one is refused.
        assertTrue(model.state.value.needsNewBowler)
        val choices = model.bowlerChoices()
        assertEquals("the over's bowler is offered, with the engine's reason against them",
            "A1 bowled it, and nobody bowls two in a row.", choices.first { it.player.id == a[0] }.refusal)
        assertNull(choices.first { it.player.id == a[1] }.refusal)
        assertFalse(model.changeBowler(a[0]))
        assertEquals("A1 bowled it, and nobody bowls two in a row.", model.state.value.error)
        assertFalse("nor can the next ball be bowled until somebody else is on", model.runs(1))

        assertTrue(model.changeBowler(a[1]))
        assertFalse(model.state.value.needsNewBowler)
        assertEquals(a[1], model.inn.bowlerId)

        // A single, taken back.
        assertTrue(model.runs(1))
        assertEquals("20/1", model.inn.score)
        assertTrue(model.undo())
        assertEquals("19/1", model.inn.score)
        assertEquals("1.0", model.inn.overs)

        // Six dots and the overs are up: the innings closes itself.
        repeat(6) { assertTrue(model.runs(0)) }
        assertEquals("innings_break", model.view.status)
        assertEquals(20, model.view.target)
        assertFalse(model.state.value.isLive)
        advanceUntilIdle()

        // Second innings: openers and a bowler.
        assertTrue(model.startInnings(a[0], a[1], h[0]))
        assertEquals("away", model.inn.batting)
        assertTrue(model.state.value.isLive)

        assertTrue(model.runs(6))
        assertEquals("Hemel need 14 off 11", model.view.chaseLine)
        assertTrue(model.runs(6))
        assertTrue(model.runs(6))
        assertTrue(model.runs(2))

        assertEquals("complete", model.view.status)
        assertEquals("Hemel won by 2 wickets (8 balls remaining)", model.view.margin)
        assertFalse(model.state.value.isLive)

        advanceUntilIdle()
        // Everything accepted went up, with this device's id, in order; nothing refused did.
        val sent = server.posted
        assertTrue(server.batches.all { it.deviceId == "phone-1" })
        assertEquals(22, sent.size)
        assertEquals((setupEvents + 1..setupEvents + 22).map { it.toLong() }, sent.map { it.seq })
        val types = sent.map { it.kind["type"]!!.jsonPrimitive.content }
        assertEquals(1, types.count { it == "wicket_recorded" })
        assertEquals(1, types.count { it == "bowler_changed" })
        assertEquals(1, types.count { it == "undo_last" })
        assertEquals(1, types.count { it == "innings_started" })
        assertEquals(0, model.state.value.unsent)
        assertEquals(SyncStatus.Saved, model.state.value.sync)
        assertEquals("the server's book is the phone's book", server.log.size, setupEvents + 22)
    }

    @Test
    fun `a wicket with nobody named to come in is refused in the engine's words`() = runTest(dispatcher.scheduler) {
        val model = scorer(FakeScoringApi())
        model.load()
        advanceUntilIdle()

        assertEquals("new batter required", model.check(Events.wicket(h[0], "caught", fielderId = a[1])))
        assertNull(model.check(Events.wicket(h[0], "caught", fielderId = a[1], newBatterId = h[2])))
    }

    @Test
    fun `a run out at the other end after a completed run`() = runTest(dispatcher.scheduler) {
        val model = scorer(FakeScoringApi())
        model.load()
        advanceUntilIdle()

        assertTrue(model.wicket(h[1], "run_out", fielderId = a[2], newBatterId = h[2], runs = 1))
        assertEquals("1/1", model.inn.score)
        assertEquals("the run counts to the striker", 1, model.inn.batter(h[0])!!.runs)
        assertTrue(model.inn.batter(h[1])!!.out)
        assertEquals("run out (A3)", model.view.dismissalText(model.inn.batter(h[1])!!))
    }

    @Test
    fun `somebody else holding the book stops this phone, and a captain can take it over`() = runTest(dispatcher.scheduler) {
        val server = FakeScoringApi().apply {
            scorerUser = "u-someone"
            scorerDevice = "their-phone"
        }
        val model = scorer(server)
        model.load()
        advanceUntilIdle()

        assertTrue(model.state.value.bookElsewhere)
        assertFalse(model.state.value.canScore)
        assertFalse("no ball is kept or sent from a phone without the book", model.runs(4))

        model.takeOver()
        advanceUntilIdle()

        assertTrue(server.claims.last().force)
        assertFalse(model.state.value.bookElsewhere)
        assertTrue(model.runs(4))
        advanceUntilIdle()
        assertEquals(1, server.posted.size)
    }

    @Test
    fun `a fixture with no match says so`() = runTest(dispatcher.scheduler) {
        val model = LiveScorerViewModel(FakeScoringApi(eventId = "other"), "e1", "phone-1", FileBallStore(disk.root))
        model.load()
        advanceUntilIdle()

        assertEquals("No match has been set up on this fixture yet.", model.state.value.error)
        assertFalse(model.state.value.canScore)
    }

    @Test
    fun `sharing mints a link for the share sheet`() = runTest(dispatcher.scheduler) {
        val model = scorer(FakeScoringApi())
        model.load()
        advanceUntilIdle()

        model.share(postToChat = false)
        advanceUntilIdle()

        assertEquals("https://example.test/live/t", model.state.value.share?.url)
        assertTrue(model.state.value.share!!.headline.contains("Lords"))
        model.shareShown()
        assertNull(model.state.value.share)
    }
}

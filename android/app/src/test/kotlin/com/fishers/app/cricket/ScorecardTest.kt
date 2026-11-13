package com.fishers.app.cricket

import com.fishers.app.EnglishStrings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** Following a match: the card, read again every ten seconds while the screen is open, and not after. */
@OptIn(ExperimentalCoroutinesApi::class)
class ScorecardTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun ball(seq: Long, runs: Int) =
        ScoringEvent("00000000-0000-4000-8000-%012d".format(900 + seq), seq, Events.delivery(runs))

    @Test
    fun `the card polls every ten seconds while open, picks up new balls, and stops when the screen goes`() =
        runTest(dispatcher.scheduler) {
            val server = FakeScoringApi()
            val model = ScorecardViewModel(server, "e1")

            val open = launch { model.follow() }
            runCurrent()

            assertEquals(1, server.scorecardCalls)
            val first = model.state.value.view!!
            assertEquals("Lords", first.homeName)
            assertEquals("0/0", first.current!!.score)
            assertEquals("H1", first.name(first.current!!.strikerId))

            // The scorer bowls a four meanwhile.
            server.log += ball(server.log.last().seq + 1, 4)

            advanceTimeBy(9_000)
            assertEquals("not before ten seconds", 1, server.scorecardCalls)
            advanceTimeBy(1_001)
            assertEquals(2, server.scorecardCalls)
            assertEquals("4/0", model.state.value.view!!.current!!.score)
            assertEquals(Moment.Kind.Four, model.state.value.moment?.kind)

            // The follower leaves the screen.
            open.cancel()
            advanceTimeBy(60_000)
            assertEquals("nothing polls behind anybody's back", 2, server.scorecardCalls)
        }

    @Test
    fun `a failed refresh keeps the card and marks it as not the latest`() = runTest(dispatcher.scheduler) {
        val server = FakeScoringApi()
        val model = ScorecardViewModel(server, "e1")

        model.refresh()
        assertFalse(model.state.value.stale)

        server.online = false
        model.refresh()

        assertTrue(model.state.value.stale)
        assertEquals("0/0", model.state.value.view!!.current!!.score)
    }

    @Test
    fun `batting, bowling, extras and the fall of wickets read as a card`() = runTest(dispatcher.scheduler) {
        val server = FakeScoringApi()
        var seq = server.log.last().seq
        fun add(kind: kotlinx.serialization.json.JsonObject) {
            server.log += ScoringEvent("00000000-0000-4000-8000-%012d".format(800 + ++seq), seq, kind)
        }
        add(Events.delivery(1))
        add(Events.extra("leg_bye", runs = 1))
        add(Events.extra("wide", runs = 2))
        add(Events.wicket(MatchLog.home[0], "caught", fielderId = MatchLog.away[2], newBatterId = MatchLog.home[2]))

        val model = ScorecardViewModel(server, "e1")
        model.refresh()
        val view = model.state.value.view!!
        val inn = view.current!!

        assertEquals("5/1", inn.score)
        assertEquals("(lb 1, w 3)", inn.extrasBreakdown)
        assertEquals(1, inn.fall.size)
        assertEquals("c A3 b A1", view.dismissalText(inn.batter(MatchLog.home[0])!!))
        assertEquals("0.3-0-4-1", inn.bowler(MatchLog.away[0])!!.figures)
        assertEquals(listOf("H1", "H2", "H3"), inn.batted.map { view.name(it.playerId) })

        val lines = Commentary.lines(view, inn)
        assertTrue("newest first, and the wicket names who", lines.first().text.contains("H1 c A3 b A1"))
        assertTrue(lines.first().isWicket)
    }
}

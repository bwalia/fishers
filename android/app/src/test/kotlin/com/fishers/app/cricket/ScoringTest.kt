package com.fishers.app.cricket

import com.fishers.app.FakeFishersApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.IOException

/**
 * These drive the real engine — the same Rust the server scores with, through
 * the generated bindings.
 *
 * That is deliberate. A test against a Kotlin stand-in would only prove the
 * stand-in agreed with itself, and the entire reason this engine is shared is
 * that hand-written copies of the Laws drifted apart.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ScoringTest {

    // `runTest` builds its own TestCoroutineScheduler unless it is handed
    // one, and a bare StandardTestDispatcher() builds a second. Work launched
    // on viewModelScope then sits on the dispatcher's scheduler while
    // advanceUntilIdle() drains runTest's, so the assertions run before the
    // view model has done anything — sometimes. It passed on every machine
    // here and failed in CI, which is the worst way to find out.
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val engine = Engine()

    private fun kind(vararg pairs: Pair<String, Any>) = JsonObject(
        pairs.associate { (k, v) ->
            k to when (v) {
                is Int -> JsonPrimitive(v)
                is Boolean -> JsonPrimitive(v)
                else -> JsonPrimitive(v.toString())
            }
        },
    )

    private fun event(seq: Long, kind: JsonObject) =
        ScoringEvent(clientEventId = "00000000-0000-0000-0000-00000000000$seq", seq = seq, kind = kind)

    private val prepared = listOf(
        event(1, kind(
            "type" to "match_prepared",
            "overs_limit" to 20,
            "home_name" to "Lords",
            "away_name" to "Hemel",
        )),
    )

    private fun match(canScore: Boolean = true) = CricketMatch(
        id = "m1", eventId = "e1", status = "preparing", oversLimit = 20,
        homeName = "Lords", awayName = "Hemel", canScore = canScore,
    )

    // ---- the engine itself ----

    @Test
    fun `a log replays through the shared engine`() {
        val state = engine.replay(prepared).getOrThrow()
        assertTrue(state.contains("Lords"))
    }

    @Test
    fun `the engine refuses an impossible ball, in its own words`() {
        val state = engine.replay(prepared).getOrThrow()
        // No innings has started, so there is nothing to bowl at.
        val refused = engine.apply(state, event(2, Events.delivery(4)))

        assertTrue(refused.isFailure)
        val words = engine.reason(refused.exceptionOrNull()!!)
        assertTrue("it says why: $words", words.isNotBlank())
    }

    @Test
    fun `accepts agrees with apply, so a button can be greyed out honestly`() {
        val state = engine.replay(prepared).getOrThrow()
        val ball = event(2, Events.delivery(1))

        assertFalse(engine.accepts(state, ball))
        assertTrue(engine.apply(state, ball).isFailure)
    }

    // ---- the screen's state ----

    @Test
    fun `a match loads, and a match with no innings has no scoreline`() = runTest(dispatcher.scheduler) {
        val model = ScoringViewModel(object : FakeFishersApi() {
            override suspend fun cricketMatch(eventId: String) = match()
            override suspend fun scoringEvents(matchId: String) = prepared
        }, "e1")

        model.load()
        advanceUntilIdle()

        assertNotNull(model.state.value.match)
        assertNull("nothing has been bowled, so there is nothing to show",
            model.state.value.score)
        assertNull("and that is not an error", model.state.value.error)
    }

    /**
     * The log is numbered, and an event carrying a sequence the log already
     * holds is a duplicate — the engine skips it, which is right for a log and
     * silent for a scorer. Numbering from the scoreline got this wrong: a match
     * with no innings has no scoreline, so every ball came out as seq 1, and
     * every ball after the first would have been swallowed without a word.
     */
    @Test
    fun `each ball is numbered past the log, not from the scoreline`() = runTest(dispatcher.scheduler) {
        val model = ScoringViewModel(object : FakeFishersApi() {
            override suspend fun cricketMatch(eventId: String) = match()
            override suspend fun scoringEvents(matchId: String) = prepared
        }, "e1")
        model.load()
        advanceUntilIdle()

        // `prepared` is one event, so the next must be 2 — not 1.
        val state = engine.replay(prepared).getOrThrow()
        assertEquals(1, engine.lastSeq(state))
    }

    /**
     * The log is the record. If it will not replay, the app says so rather
     * than drawing a score it made up from the last event it understood.
     */
    @Test
    fun `a book that will not replay is reported, not guessed at`() = runTest(dispatcher.scheduler) {
        val model = ScoringViewModel(object : FakeFishersApi() {
            override suspend fun cricketMatch(eventId: String) = match()
            override suspend fun scoringEvents(matchId: String) =
                listOf(event(1, kind("type" to "no_such_event")))
        }, "e1")

        model.load()
        advanceUntilIdle()

        assertNull("no invented score", model.state.value.score)
        assertTrue(model.state.value.error!!.contains("would not replay"))
    }

    /**
     * A ball the Laws refuse never reaches the server, so the scorer is told
     * at the moment they tap rather than four overs later.
     */
    @Test
    fun `a ball the engine refuses is never sent`() = runTest(dispatcher.scheduler) {
        var posted = 0
        val model = ScoringViewModel(object : FakeFishersApi() {
            override suspend fun cricketMatch(eventId: String) = match()
            override suspend fun scoringEvents(matchId: String) = prepared
            override suspend fun postScoringEvents(
                matchId: String,
                body: EventsBatch,
            ): CricketMatch {
                posted++
                return match()
            }
        }, "e1")
        model.load()
        advanceUntilIdle()

        model.runs(4) // no innings has started
        advanceUntilIdle()

        assertEquals("the server never heard about it", 0, posted)
        assertEquals(
            "and the scorer was told, in the engine's own words",
            "no live innings", model.state.value.error,
        )
    }

    /**
     * A ball the engine took stays on screen even when the send fails. It was
     * legal — the engine said so — and the scorer is mid-over. What they need
     * to know is that it has not gone up yet, not that it never happened.
     */
    @Test
    fun `a legal event that could not be sent still says it has not gone up`() = runTest(dispatcher.scheduler) {
        val model = ScoringViewModel(object : FakeFishersApi() {
            override suspend fun cricketMatch(eventId: String) = match()
            override suspend fun scoringEvents(matchId: String) = prepared
            override suspend fun postScoringEvents(
                matchId: String,
                body: EventsBatch,
            ): CricketMatch = throw IOException("no signal")
        }, "e1")
        model.load()
        advanceUntilIdle()

        // Calling a match off is legal from a prepared match — the toss is
        // not, because both captains have to agree the terms first.
        model.record(kind("type" to "match_abandoned", "reason" to "ground unplayable"))
        advanceUntilIdle()

        assertTrue(
            "it says it has not gone up, rather than that it never happened",
            model.state.value.error?.contains("Not sent yet") == true,
        )
        assertFalse(model.state.value.isSending)
    }

    // ---- what the scoreboard says ----

    @Test
    fun `overs read as a scorebook writes them`() {
        val line = Scoreline(
            battingIsHome = true, runs = 60, wickets = 2, legalBalls = 76,
            complete = false, homeName = "Lords", awayName = "Hemel",
            target = null, margin = null, status = "live", lastSeq = 1,
        )
        assertEquals("12.4", line.overs)
    }

    @Test
    fun `a chase says what is needed and off how many`() {
        val line = Scoreline(
            battingIsHome = false, runs = 142, wickets = 4, legalBalls = 96,
            complete = false, homeName = "Lords", awayName = "Hemel",
            target = 176, margin = null, status = "live", lastSeq = 1,
        )
        assertEquals("Needs 34 off 24", line.chase(20))
    }

    @Test
    fun `a finished match is not still asking for runs`() {
        val line = Scoreline(
            battingIsHome = false, runs = 176, wickets = 4, legalBalls = 100,
            complete = true, homeName = "Lords", awayName = "Hemel",
            target = 176, margin = "Hemel won by 6 wickets", status = "complete", lastSeq = 1,
        )
        assertNull(line.chase(20))
    }
}

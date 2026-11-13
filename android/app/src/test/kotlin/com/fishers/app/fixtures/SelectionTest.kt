package com.fishers.app.fixtures

import com.fishers.app.EnglishStrings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SelectionTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun player(
        id: String,
        state: SelectionState = SelectionState.Pool,
        rsvp: RsvpStatus? = RsvpStatus.Going,
        availability: AvailabilityStatus? = null,
    ) = SelectionCandidate(userId = id, name = id.uppercase(), state = state, rsvp = rsvp, availability = availability)

    private fun board(size: Int = 3, vararg players: SelectionCandidate, ranked: List<String> = emptyList()) = SelectionBoard(
        eventId = "e1", title = "Lords v Hemel", startsAt = "2099-09-27T12:30:00Z",
        requirements = SquadRequirements(size = size),
        candidates = players.toList(),
        ranked = ranked.map { RankedCandidate(it, it.uppercase()) },
    )

    private open inner class Board(val start: SelectionBoard) : FakeFixturesApi() {
        val sent = mutableListOf<SetSquadBody>()
        override suspend fun selectionBoard(id: String) = start
        override suspend fun setSquad(id: String, body: SetSquadBody): SelectionBoard {
            sent += body
            return start
        }
    }

    @Test
    fun `the board starts from whatever is already decided`() = runTest(dispatcher.scheduler) {
        val model = SelectionViewModel(Board(board(
            11,
            player("a", SelectionState.Selected),
            player("b", SelectionState.Confirmed),
            player("c", SelectionState.Reserve),
            player("d"),
        )), "e1")
        model.load()
        advanceUntilIdle()

        assertEquals(listOf("a", "b"), model.state.value.selected)
        assertEquals(listOf("c"), model.state.value.reserves)
        assertEquals(listOf("d"), model.state.value.pool.map { it.userId })
    }

    /** In → out; pool → in until the side is full, then onto the reserves. */
    @Test
    fun `tapping picks, and once the side is full a tap makes a reserve`() = runTest(dispatcher.scheduler) {
        val model = SelectionViewModel(Board(board(2, player("a"), player("b"), player("c"))), "e1")
        model.load()
        advanceUntilIdle()

        model.toggle("a")
        model.toggle("b")
        assertTrue(model.state.value.isFull)
        model.toggle("c")
        assertEquals(listOf("a", "b"), model.state.value.selected)
        assertEquals(listOf("c"), model.state.value.reserves)

        model.toggle("a")
        assertEquals("taken out of the side", listOf("b"), model.state.value.selected)
        model.toggle("c")
        assertEquals("a reserve tapped is out, not promoted", emptyList<String>(), model.state.value.reserves)
    }

    /**
     * The fixture's own answer beats the standing calendar: a player whose
     * calendar says busy but who said yes to this game is available for it.
     */
    @Test
    fun `whoever said no is kept apart, best first for the rest`() = runTest(dispatcher.scheduler) {
        val model = SelectionViewModel(Board(board(
            11,
            player("calendar_busy_said_yes", availability = AvailabilityStatus.Unavailable),
            player("said_no", rsvp = RsvpStatus.NotGoing),
            player("busy_no_answer", rsvp = null, availability = AvailabilityStatus.Unavailable),
            player("best"),
            ranked = listOf("best", "calendar_busy_said_yes"),
        )), "e1")
        model.load()
        advanceUntilIdle()

        assertEquals(listOf("best", "calendar_busy_said_yes"), model.state.value.pool.map { it.userId })
        assertEquals(listOf("said_no", "busy_no_answer"), model.state.value.saidNo.map { it.userId })
    }

    /** A suggestion fills the list for the captain to change. It tells nobody. */
    @Test
    fun `a suggested side is loaded for editing, not sent`() = runTest(dispatcher.scheduler) {
        val api = object : Board(board(2, player("a"), player("b"), player("c"))) {
            override suspend fun suggestSquad(id: String) = SquadProposal(
                selected = listOf(RankedCandidate("c", "C"), RankedCandidate("a", "A")),
                reserves = listOf(RankedCandidate("b", "B")),
                announcement = "Squad for Lords v Hemel — 2 named.",
            )
        }
        val model = SelectionViewModel(api, "e1")
        model.load()
        advanceUntilIdle()

        model.suggest()
        advanceUntilIdle()

        assertEquals(listOf("c", "a"), model.state.value.selected)
        assertEquals(listOf("b"), model.state.value.reserves)
        assertTrue(api.sent.isEmpty())
    }

    @Test
    fun `publishing sends the side, the reserves and the suggested announcement`() = runTest(dispatcher.scheduler) {
        val api = object : Board(board(2, player("a"), player("b"), player("c"))) {
            override suspend fun suggestSquad(id: String) = SquadProposal(
                selected = listOf(RankedCandidate("a", "A"), RankedCandidate("b", "B")),
                reserves = listOf(RankedCandidate("c", "C")),
                announcement = "Squad named.",
            )
        }
        val model = SelectionViewModel(api, "e1")
        model.load()
        advanceUntilIdle()
        model.suggest()
        advanceUntilIdle()

        model.publish()
        advanceUntilIdle()

        assertEquals(listOf(SetSquadBody(listOf("a", "b"), listOf("c"), "Squad named.", publish = true)), api.sent)
        assertNull("the proposal has gone out", model.state.value.proposal)
        assertEquals("Squad announced — everybody picked has been told.", model.state.value.message)
    }

    @Test
    fun `a draft is kept without telling anybody`() = runTest(dispatcher.scheduler) {
        val api = Board(board(2, player("a"), player("b")))
        val model = SelectionViewModel(api, "e1")
        model.load()
        advanceUntilIdle()
        model.toggle("a")

        model.saveDraft()
        advanceUntilIdle()

        assertEquals(listOf(SetSquadBody(listOf("a"), emptyList(), null, publish = false)), api.sent)
        assertEquals("Saved as a draft.", model.state.value.message)
    }

    @Test
    fun `an empty side cannot be published`() = runTest(dispatcher.scheduler) {
        val api = Board(board(2, player("a")))
        val model = SelectionViewModel(api, "e1")
        model.load()
        advanceUntilIdle()

        model.publish()
        advanceUntilIdle()

        assertTrue(api.sent.isEmpty())
    }

    @Test
    fun `a refused publish keeps the captain's side on screen`() = runTest(dispatcher.scheduler) {
        val model = SelectionViewModel(object : Board(board(2, player("a"))) {
            override suspend fun setSquad(id: String, body: SetSquadBody): SelectionBoard = throw httpError(403)
        }, "e1")
        model.load()
        advanceUntilIdle()
        model.toggle("a")

        model.publish()
        advanceUntilIdle()

        assertEquals(listOf("a"), model.state.value.selected)
        assertEquals("You do not have permission to do that.", model.state.value.error)
        assertFalse(model.state.value.isPublishing)
    }
}

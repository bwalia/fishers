package com.fishers.app.motm

import com.fishers.app.FakeFishersApi
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
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class MotmTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val now = Instant.parse("2026-09-23T12:00:00Z")

    private fun poll(
        status: String = "open",
        closesAt: String = "2026-09-23T18:00:00Z",
        canVote: Boolean = true,
        myVote: String? = null,
        tallyVisible: Boolean = false,
    ) = MotmPollView(
        id = "p1", eventId = "e1", title = "Man of the match",
        status = status, closesAt = closesAt,
        candidates = listOf(
            MotmCandidate("u1", "Ravi Patel", "home", 3),
            MotmCandidate("u2", "Tom Hardy", "away", 1),
        ),
        myVote = myVote, canVote = canVote, tallyVisible = tallyVisible, totalVotes = 4,
    )

    // ---- when a vote counts ----

    /**
     * Past its closing time the poll is over whether or not anybody has run
     * the close yet. Without this the answer depends on who asked last, and a
     * late vote lands on a match somebody has already announced the result of.
     */
    @Test
    fun `a poll past its closing time is shut even while it still says open`() {
        val stillOpenOnPaper = poll(status = "open", closesAt = "2026-09-23T11:00:00Z")

        assertFalse(stillOpenOnPaper.isOpen(now))
        assertFalse("and nobody may vote in it", stillOpenOnPaper.votingAllowed(now))
    }

    @Test
    fun `a closed poll is shut even if the clock says otherwise`() {
        assertFalse(poll(status = "closed").isOpen(now))
    }

    @Test
    fun `an open poll before its time is open`() {
        assertTrue(poll().isOpen(now))
        assertTrue(poll().votingAllowed(now))
    }

    @Test
    fun `somebody the server will not let vote cannot, however open the poll is`() {
        assertTrue(poll(canVote = false).isOpen(now))
        assertFalse(poll(canVote = false).votingAllowed(now))
    }

    /** An unparseable date is not a reason to let a vote through. */
    @Test
    fun `a closing time nobody can read is treated as closed`() {
        assertFalse(poll(closesAt = "not a date").isOpen(now))
    }

    @Test
    fun `candidates are split by side, the way the card shows them`() {
        assertEquals(listOf("Ravi Patel"), poll().home.map { it.displayName })
        assertEquals(listOf("Tom Hardy"), poll().away.map { it.displayName })
    }

    // ---- voting ----

    @Test
    fun `voting redraws from what the server said, not from what we hoped`() = runTest {
        val model = MotmViewModel(object : FakeFishersApi() {
            override suspend fun motmPoll(id: String) = poll()
            override suspend fun castMotmVote(id: String, body: CastMotmVoteRequest) =
                poll(myVote = body.candidateUserId, tallyVisible = true)
        }, "p1")
        model.load()
        advanceUntilIdle()

        model.vote("u1")
        advanceUntilIdle()

        assertEquals("u1", model.state.value.poll?.myVote)
        assertTrue("the server decided to show it", model.state.value.poll!!.tallyVisible)
    }

    /** Tapping who you already voted for takes it back, rather than casting twice. */
    @Test
    fun `voting for the same player again withdraws it`() = runTest {
        var withdrew = false
        val model = MotmViewModel(object : FakeFishersApi() {
            override suspend fun motmPoll(id: String) = poll(myVote = "u1", tallyVisible = true)
            override suspend fun withdrawMotmVote(id: String): MotmPollView {
                withdrew = true
                return poll(myVote = null)
            }
        }, "p1")
        model.load()
        advanceUntilIdle()

        model.vote("u1")
        advanceUntilIdle()

        assertTrue(withdrew)
        assertEquals(null, model.state.value.poll?.myVote)
    }

    @Test
    fun `a vote in a shut poll never reaches the server`() = runTest {
        val model = MotmViewModel(object : FakeFishersApi() {
            override suspend fun motmPoll(id: String) = poll(status = "closed")
            override suspend fun castMotmVote(id: String, body: CastMotmVoteRequest): MotmPollView =
                error("should not have been called")
        }, "p1")
        model.load()
        advanceUntilIdle()

        model.vote("u1")
        advanceUntilIdle()

        assertEquals(null, model.state.value.poll?.myVote)
    }
}

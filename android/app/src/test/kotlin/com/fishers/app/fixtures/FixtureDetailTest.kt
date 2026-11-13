package com.fishers.app.fixtures

import com.fishers.app.EnglishStrings
import com.fishers.app.motm.MotmPollView
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
import java.io.IOException

@OptIn(ExperimentalCoroutinesApi::class)
class FixtureDetailTest {
    @get:Rule val english = EnglishStrings()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val league = FishersEvent(
        id = "e1", clubId = "lords", title = "Lords CC v Hemel CC",
        subtype = EventSubtype.LeagueMatch, startAt = "2099-09-27T12:30:00Z", endAt = "2099-09-27T17:30:00Z",
    )

    private fun match(status: String, canScore: Boolean = false) =
        FixtureMatch(id = "m1", eventId = "e1", status = status, canScore = canScore)

    private fun board(vararg candidates: SelectionCandidate) = SelectionBoard(
        eventId = "e1", title = league.title, startsAt = league.startAt, candidates = candidates.toList(),
    )

    /** Everything answers; a test overrides what it is about. */
    private open inner class Fixture : FakeFixturesApi() {
        override suspend fun event(id: String) = league
        override suspend fun attendees(id: String) = emptyList<Attendee>()
        override suspend fun myRole(clubId: String) = ClubRole(permissions = listOf("respond_as_player"))
        override suspend fun selectionBoard(id: String) = board()
        override suspend fun cricketMatch(eventId: String): FixtureMatch = throw httpError(404)
        override suspend fun motm(eventId: String): MotmPollView = throw httpError(404)
    }

    // ---- the match card ----

    @Test
    fun `how far a match has got decides what the card offers`() {
        val scorer = true
        val follower = false
        val none = MatchOnFixture.NotStarted
        assertEquals(listOf(MatchAction.SetUp), matchActions(true, none, scorer))
        assertEquals("only a scorer can make the scorebook", emptyList<MatchAction>(), matchActions(true, none, follower))

        val setting = MatchOnFixture.of(match("toss", canScore = true))
        assertEquals(listOf(MatchAction.ContinueSetup), matchActions(true, setting, follower))
        assertEquals(listOf(MatchAction.Follow), matchActions(true, MatchOnFixture.of(match("toss")), scorer))

        val live = MatchOnFixture.of(match("live", canScore = true))
        assertEquals(listOf(MatchAction.Score, MatchAction.Follow), matchActions(true, live, follower))
        assertEquals(listOf(MatchAction.Follow), matchActions(true, MatchOnFixture.of(match("innings_break")), scorer))

        assertEquals(listOf(MatchAction.Scorecard), matchActions(true, MatchOnFixture.of(match("complete", canScore = true)), scorer))
        assertEquals(listOf(MatchAction.Scorecard), matchActions(true, MatchOnFixture.of(match("published")), follower))

        assertEquals("nets have no scorebook", emptyList<MatchAction>(), matchActions(false, none, scorer))
        assertEquals("not knowing offers nothing", emptyList<MatchAction>(), matchActions(true, MatchOnFixture.Unknown, scorer))
    }

    @Test
    fun `only a game of cricket has a scorebook`() {
        assertTrue(league.isCricketMatch)
        assertTrue(league.copy(subtype = EventSubtype.Tournament).isCricketMatch)
        assertFalse(league.copy(subtype = EventSubtype.Nets).isCricketMatch)
        assertFalse(league.copy(sport = "football").isCricketMatch)
    }

    /** A 404 means "set it up"; a dropped signal must not offer to set up a match that exists. */
    @Test
    fun `no match yet is told apart from not knowing`() = runTest(dispatcher.scheduler) {
        val none = FixtureDetailViewModel(Fixture(), "e1", "me")
        none.load()
        advanceUntilIdle()
        assertEquals(MatchOnFixture.NotStarted, none.state.value.match)

        val offline = FixtureDetailViewModel(object : Fixture() {
            override suspend fun cricketMatch(eventId: String): FixtureMatch = throw IOException("down")
        }, "e1", "me")
        offline.load()
        advanceUntilIdle()
        assertEquals(MatchOnFixture.Unknown, offline.state.value.match)
    }

    @Test
    fun `a scorer is offered to set the match up, a player is not`() = runTest(dispatcher.scheduler) {
        val captain = FixtureDetailViewModel(object : Fixture() {
            override suspend fun myRole(clubId: String) =
                ClubRole(permissions = listOf("manage_selection", "score_match"), isCaptain = true)
        }, "e1", "me")
        captain.load()
        advanceUntilIdle()
        assertEquals(listOf(MatchAction.SetUp), captain.state.value.matchActions())
        assertTrue(captain.state.value.canSelect)

        val player = FixtureDetailViewModel(Fixture(), "e1", "me")
        player.load()
        advanceUntilIdle()
        assertEquals(emptyList<MatchAction>(), player.state.value.matchActions())
        assertFalse(player.state.value.canSelect)
    }

    // ---- reading it ----

    /** A visiting player cannot see the home side's lists. The fixture itself must still show. */
    @Test
    fun `the fixture shows even when everything around it is refused`() = runTest(dispatcher.scheduler) {
        val model = FixtureDetailViewModel(object : Fixture() {
            override suspend fun attendees(id: String): List<Attendee> = throw httpError(403)
            override suspend fun myRole(clubId: String): ClubRole = throw httpError(403)
            override suspend fun selectionBoard(id: String): SelectionBoard = throw httpError(403)
        }, "e1", "me")
        model.load()
        advanceUntilIdle()

        val state = model.state.value
        assertEquals(league, state.event)
        assertNull(state.error)
        assertNull(state.board)
        assertFalse(state.isLoading)
    }

    @Test
    fun `a fixture that will not load says so`() = runTest(dispatcher.scheduler) {
        val model = FixtureDetailViewModel(object : Fixture() {
            override suspend fun event(id: String): FishersEvent = throw httpError(403)
        }, "e1", "me")
        model.load()
        advanceUntilIdle()

        assertNull(model.state.value.event)
        assertEquals("You do not have permission to do that.", model.state.value.error)
    }

    @Test
    fun `who is coming is available first, and your own answer is read from it`() = runTest(dispatcher.scheduler) {
        val model = FixtureDetailViewModel(object : Fixture() {
            override suspend fun attendees(id: String) = listOf(
                Attendee("a", "Zed", RsvpStatus.NotGoing),
                Attendee("me", "Me", RsvpStatus.Maybe),
                Attendee("b", "Amy", RsvpStatus.Invited),
                Attendee("c", "Bob", RsvpStatus.Going),
            )
        }, "e1", "me")
        model.load()
        advanceUntilIdle()

        assertEquals(listOf("Bob", "Me", "Amy", "Zed"), model.state.value.attendees.map { it.name })
        assertEquals(RsvpStatus.Maybe, model.state.value.myAnswer)
    }

    // ---- answering ----

    @Test
    fun `an answer the server refused is put back`() = runTest(dispatcher.scheduler) {
        val model = FixtureDetailViewModel(object : Fixture() {
            override suspend fun attendees(id: String) = listOf(Attendee("me", "Me", RsvpStatus.Maybe))
            override suspend fun rsvp(id: String, body: RsvpRequest): Unit = throw IOException("offline")
        }, "e1", "me")
        model.load()
        advanceUntilIdle()

        model.answer(RsvpStatus.Going)
        assertEquals("shown before the server answers", RsvpStatus.Going, model.state.value.myAnswer)
        advanceUntilIdle()

        assertEquals(RsvpStatus.Maybe, model.state.value.myAnswer)
        assertEquals(RsvpStatus.Maybe, model.state.value.attendees.single().status)
        assertTrue(model.state.value.error!!.isNotEmpty())
    }

    // ---- your place in the side ----

    @Test
    fun `a picked player sees their place, and nobody sees one before a side is picked`() = runTest(dispatcher.scheduler) {
        var boardNow = board(SelectionCandidate("me", "Me", state = SelectionState.Pool))
        val model = FixtureDetailViewModel(object : Fixture() {
            override suspend fun selectionBoard(id: String) = boardNow
        }, "e1", "me")
        model.load()
        advanceUntilIdle()
        assertNull(model.state.value.myPlace("me"))

        boardNow = board(SelectionCandidate("me", "Me", state = SelectionState.Selected))
        model.load()
        advanceUntilIdle()
        assertEquals(SelectionState.Selected, model.state.value.myPlace("me")!!.state)
    }

    @Test
    fun `pulling out tells the server, reloads the side and says so`() = runTest(dispatcher.scheduler) {
        var said: Boolean? = null
        var boardNow = board(SelectionCandidate("me", "Me", state = SelectionState.Selected))
        val model = FixtureDetailViewModel(object : Fixture() {
            override suspend fun selectionBoard(id: String) = boardNow
            override suspend fun respondToSelection(id: String, body: RespondToSelectionBody) {
                said = body.confirming
                boardNow = board(SelectionCandidate("me", "Me", state = SelectionState.Declined))
            }
        }, "e1", "me")
        model.load()
        advanceUntilIdle()

        model.respondToSelection(false)
        advanceUntilIdle()

        assertEquals(false, said)
        assertEquals(SelectionState.Declined, model.state.value.myPlace("me")!!.state)
        assertEquals("Told them you cannot play.", model.state.value.message)
    }

    // ---- calling it off ----

    @Test
    fun `calling it off sends the status and the reason, and says everybody was told`() = runTest(dispatcher.scheduler) {
        var sent: FixtureStatusBody? = null
        val model = FixtureDetailViewModel(object : Fixture() {
            override suspend fun updateFixtureStatus(id: String, body: FixtureStatusBody) {
                sent = body
            }
        }, "e1", "me")
        model.load()
        advanceUntilIdle()

        model.changeStatus(EventStatus.Postponed, "  Ground waterlogged ")
        advanceUntilIdle()

        assertEquals(FixtureStatusBody("postponed", "Ground waterlogged"), sent)
        assertEquals("Postponed — everybody has been told.", model.state.value.message)
    }

    @Test
    fun `an empty reason is left out rather than sent blank`() = runTest(dispatcher.scheduler) {
        var sent: FixtureStatusBody? = null
        val model = FixtureDetailViewModel(object : Fixture() {
            override suspend fun updateFixtureStatus(id: String, body: FixtureStatusBody) {
                sent = body
            }
        }, "e1", "me")
        model.load()
        advanceUntilIdle()

        model.changeStatus(EventStatus.Cancelled, "   ")
        advanceUntilIdle()

        assertEquals(FixtureStatusBody("cancelled", null), sent)
    }
}

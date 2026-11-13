package com.fishers.app.cricket

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
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * A ball scored with no signal is never lost.
 *
 * Each test drops the view model and makes a new one over the same folder —
 * which is what the app being killed mid-over and opened again looks like
 * from here: only what reached the disk survives.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class OfflineBallsTest {
    @get:Rule val english = EnglishStrings()
    @get:Rule val disk = TemporaryFolder()

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private var ids = 0

    private fun scorer(api: FakeScoringApi) = LiveScorerViewModel(
        api = api,
        eventId = "e1",
        deviceId = "phone-1",
        store = FileBallStore(disk.root),
        myUserId = "u-me",
        newId = { "00000000-0000-4000-8000-%012d".format(++ids) },
        now = { null },
    )

    private fun LiveScorerViewModel.score() = state.value.view!!.current!!.score

    @Test
    fun `balls scored offline are kept, survive the app being killed, and go up when the signal does`() =
        runTest(dispatcher.scheduler) {
            val server = FakeScoringApi()
            val before = server.log.size

            // Open with signal, then lose it at the start of the over.
            val first = scorer(server)
            first.load()
            advanceUntilIdle()
            server.online = false

            assertTrue(first.runs(1))
            assertTrue(first.runs(4))
            assertTrue(first.extra("wide"))
            advanceUntilIdle()

            assertEquals("6/0", first.score())
            assertEquals(3, first.state.value.unsent)
            assertEquals(SyncStatus.Offline, first.state.value.sync)
            assertEquals("nothing reached the server", before, server.log.size)

            // The app is killed. It opens again, still with no signal: the
            // over is there, from the phone's own book.
            val second = scorer(server)
            second.load()
            advanceUntilIdle()

            assertEquals("6/0", second.score())
            assertEquals(3, second.state.value.unsent)
            assertEquals(SyncStatus.Offline, second.state.value.sync)
            assertTrue("scoring carries on offline", second.state.value.isLive)

            assertTrue(second.runs(2))
            advanceUntilIdle()
            assertEquals(4, second.state.value.unsent)

            // The signal comes back.
            server.online = true
            second.onNetworkAvailable()
            advanceUntilIdle()

            assertEquals(0, second.state.value.unsent)
            assertEquals(SyncStatus.Saved, second.state.value.sync)
            assertEquals("all four, in one batch", 1, server.batches.size)
            assertEquals(4, server.posted.size)
            assertEquals(((before + 1)..(before + 4)).map { it.toLong() }, server.posted.map { it.seq })
            assertEquals(before + 4, server.log.size)
        }

    @Test
    fun `balls left on the phone go up when the match is opened again with signal`() = runTest(dispatcher.scheduler) {
        val server = FakeScoringApi()
        val before = server.log.size

        val first = scorer(server)
        first.load()
        advanceUntilIdle()
        server.online = false
        assertTrue(first.runs(6))
        assertTrue(first.runs(0))
        advanceUntilIdle()
        assertEquals(2, first.state.value.unsent)

        // Killed; reopened at home with wifi.
        server.online = true
        val second = scorer(server)
        second.load()
        advanceUntilIdle()

        assertEquals(0, second.state.value.unsent)
        assertEquals(2, server.posted.size)
        assertEquals(before + 2, server.log.size)
        assertEquals("6/0", second.score())
    }

    @Test
    fun `a match nobody reopens still sends what it left on the phone`() = runTest(dispatcher.scheduler) {
        val server = FakeScoringApi()
        val before = server.log.size
        val first = scorer(server)
        first.load()
        advanceUntilIdle()
        server.online = false
        assertTrue(first.runs(4))
        assertTrue(first.extra("bye", runs = 1))
        advanceUntilIdle()

        // Meanwhile the scorer's phone is not the only thing that moved: the
        // server took a ball from elsewhere, under the number this phone used.
        server.online = true
        server.log += ScoringEvent("00000000-0000-4000-8000-0000000000ff", before + 1L, Events.delivery(0))

        val sent = BookSweeper(server, FileBallStore(disk.root), "phone-1").sendLeftovers()

        assertEquals(2, sent)
        assertEquals("renumbered past the server's ball, not lost under it", before + 3, server.log.size)
        assertEquals(listOf(before + 2L, before + 3L), server.posted.map { it.seq })
        assertEquals("nothing left to send", 0, FileBallStore(disk.root).withUnsent().size)
    }

    @Test
    fun `the next ball sends the ones before it`() = runTest(dispatcher.scheduler) {
        val server = FakeScoringApi()
        val model = scorer(server)
        model.load()
        advanceUntilIdle()

        server.online = false
        assertTrue(model.runs(1))
        advanceUntilIdle()
        assertEquals(1, model.state.value.unsent)

        // A bar of signal between balls — nobody told the app — and the next tap.
        server.online = true
        assertTrue(model.runs(2))
        advanceUntilIdle()

        assertEquals(0, model.state.value.unsent)
        assertEquals(2, server.posted.size)
    }

    @Test
    fun `a batch the server took but whose answer was lost is not scored twice`() = runTest(dispatcher.scheduler) {
        var dropAnswer = true
        val server = object : FakeScoringApi() {
            override suspend fun postEvents(matchId: String, body: EventsBatch): CricketMatch {
                val reply = super.postEvents(matchId, body)
                if (dropAnswer) {
                    dropAnswer = false
                    throw java.io.IOException("the answer never arrived")
                }
                return reply
            }
        }
        val before = server.log.size
        val model = scorer(server)
        model.load()
        advanceUntilIdle()

        assertTrue(model.runs(4))
        advanceUntilIdle()
        assertEquals("it went, but the phone does not know", 1, model.state.value.unsent)

        model.onNetworkAvailable()
        advanceUntilIdle()

        assertEquals(0, model.state.value.unsent)
        assertEquals("the server kept it once", before + 1, server.log.size)
        assertNull(model.state.value.syncProblem)
    }
}

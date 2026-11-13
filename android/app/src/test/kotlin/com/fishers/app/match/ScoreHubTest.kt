package com.fishers.app.match

import com.fishers.app.EnglishStrings
import com.fishers.app.clubs.Club
import com.fishers.app.cricket.FileBallStore
import com.fishers.app.match.start.FixturePage
import com.fishers.app.match.start.FixtureRow
import com.fishers.app.match.start.HubDestination
import com.fishers.app.match.start.HubFilter
import com.fishers.app.match.start.OfflineCache
import com.fishers.app.match.start.ScoreHubViewModel
import com.fishers.app.season.MyClubRole
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
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

@OptIn(ExperimentalCoroutinesApi::class)
class ScoreHubTest {
    @get:Rule val english = EnglishStrings()

    // One scheduler for runTest and Dispatchers.Main — see ClubsTest.
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @get:Rule val disk = TemporaryFolder()

    private fun hub(server: Server, searchPause: Long = 350) = ScoreHubViewModel(
        api = server,
        store = FileBallStore(File(disk.root, "books")),
        cache = OfflineCache(File(disk.root, "cache")),
        searchPause = searchPause,
    )

    private data class Asked(val state: String?, val search: String?, val order: String, val page: Int)

    private fun row(event: String, club: String, status: String?) =
        FixtureRow(eventId = event, clubId = club, title = "A v B", startAt = "2026-11-14T12:00:00Z", matchStatus = status)

    private inner class Server(val pages: List<FixturePage>) : FakeMatchStartApi() {
        val asked = mutableListOf<Asked>()
        override suspend fun cricketFixtures(state: String?, search: String?, order: String, page: Int, perPage: Int): FixturePage {
            asked += Asked(state, search, order, page)
            return pages.getOrElse(page - 1) { FixturePage() }
        }
        override suspend fun myClubs() = listOf(Club("mine", "Lords CC"), Club("other", "Ashford CC"))
        override suspend fun myClubRole(clubId: String) =
            MyClubRole(permissions = if (clubId == "mine") listOf("score_match") else listOf("view_club"))
    }

    @Test
    fun `each row goes where somebody in your shoes would want it to`() = runTest(dispatcher.scheduler) {
        val model = hub(Server(listOf(FixturePage())))
        model.load()
        advanceUntilIdle()

        assertEquals(HubDestination.Scorecard("e1"), model.destination(row("e1", "mine", "complete")))
        assertEquals(HubDestination.Score("e2"), model.destination(row("e2", "mine", "live")))
        assertEquals(HubDestination.Score("e2"), model.destination(row("e2", "mine", "innings_break")))
        assertEquals(HubDestination.Scorecard("e3"), model.destination(row("e3", "other", "live")))
        assertEquals(HubDestination.Setup("e4"), model.destination(row("e4", "mine", null)))
        assertEquals(HubDestination.Setup("e5"), model.destination(row("e5", "mine", "toss")))
        assertEquals(HubDestination.Scorecard("e6"), model.destination(row("e6", "other", null)))
    }

    @Test
    fun `the filter, the search and the order are asked of the server, a page at a time`() = runTest(dispatcher.scheduler) {
        val server = Server(
            listOf(
                FixturePage(items = listOf(row("e1", "mine", "live")), total = 2, hasMore = true),
                FixturePage(items = listOf(row("e2", "mine", "live"), row("e1", "mine", "live")), total = 2, hasMore = false),
            ),
        )
        val model = hub(server, searchPause = 10)
        model.load()
        advanceUntilIdle()
        model.loadMore()
        advanceUntilIdle()
        assertEquals("a repeated row is not listed twice", listOf("e1", "e2"), model.state.value.rows.map { it.eventId })
        assertFalse(model.state.value.hasMore)

        model.setFilter(HubFilter.Live)
        advanceUntilIdle()
        model.setNewestFirst(true)
        advanceUntilIdle()
        model.setSearch("L")
        advanceUntilIdle()
        model.setSearch("Lo")
        advanceUntilIdle()

        assertEquals(Asked(null, null, "asc", 1), server.asked[0])
        assertEquals(Asked(null, null, "asc", 2), server.asked[1])
        assertEquals(Asked("live", null, "asc", 1), server.asked[2])
        assertEquals(Asked("live", null, "desc", 1), server.asked[3])
        // One letter is not sent — the server refuses it.
        assertEquals(Asked("live", null, "desc", 1), server.asked[4])
        assertEquals(Asked("live", "Lo", "desc", 1), server.asked[5])
    }
}

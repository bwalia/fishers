package com.fishers.app.home

import com.fishers.app.FakeFishersApi
import com.fishers.app.chat.ConversationSummary
import com.fishers.app.clubs.Club
import com.fishers.app.fixtures.EventStatus
import com.fishers.app.fixtures.FishersEvent
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
import org.junit.Test
import java.io.IOException
import java.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class HomeTest {

    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private val now = Instant.parse("2026-09-23T12:00:00Z")

    private fun event(id: String, at: String, status: EventStatus = EventStatus.Scheduled) =
        FishersEvent(id = id, clubId = "c", title = id, startAt = at, status = status)

    private fun chat(unread: Long) = ConversationSummary(
        id = "c$unread", kind = "club", title = "t",
        updatedAt = "2026-09-23T10:00:00Z", unreadCount = unread,
    )

    @Test
    fun `next up is the soonest fixture that is still on`() = runTest {
        val model = HomeViewModel(object : FakeFishersApi() {
            override suspend fun myFixtures() = listOf(
                event("later", "2026-10-01T12:00:00Z"),
                // Sooner, but called off — turning up to this is the mistake.
                event("cancelled", "2026-09-24T12:00:00Z", EventStatus.Cancelled),
                event("past", "2026-09-01T12:00:00Z"),
                event("soonest", "2026-09-26T12:00:00Z"),
            )
            override suspend fun conversations() = emptyList<ConversationSummary>()
            override suspend fun myClubs() = emptyList<Club>()
        })

        model.load(now)
        advanceUntilIdle()

        assertEquals("soonest", model.state.value.next?.id)
    }

    @Test
    fun `unread counts are added up across every thread`() = runTest {
        val model = HomeViewModel(object : FakeFishersApi() {
            override suspend fun myFixtures() = emptyList<FishersEvent>()
            override suspend fun conversations() = listOf(chat(2), chat(0), chat(5))
            override suspend fun myClubs() = listOf(Club("1", "Lords"), Club("2", "Hemel"))
        })

        model.load(now)
        advanceUntilIdle()

        assertEquals(7, model.state.value.unreadChats)
        assertEquals(2, model.state.value.clubCount)
    }

    /**
     * Each tile stands on its own. An overview that goes blank because the
     * chat service is unhappy is worse than one that is a tile short.
     */
    @Test
    fun `one endpoint failing costs its own tile and nothing else`() = runTest {
        val model = HomeViewModel(object : FakeFishersApi() {
            override suspend fun myFixtures() = listOf(event("next", "2026-09-26T12:00:00Z"))
            override suspend fun conversations(): List<ConversationSummary> =
                throw IOException("chat is down")
            override suspend fun myClubs() = listOf(Club("1", "Lords"))
        })

        model.load(now)
        advanceUntilIdle()

        assertEquals("next", model.state.value.next?.id)
        assertEquals(1, model.state.value.clubCount)
        assertEquals("the tile that failed reads as zero", 0, model.state.value.unreadChats)
        assertNull("and nothing shouts about it", model.state.value.error)
    }

    /** Everything failing is worth saying, because the screen is then empty. */
    @Test
    fun `everything failing does say so`() = runTest {
        val model = HomeViewModel(object : FakeFishersApi() {
            override suspend fun myFixtures(): List<FishersEvent> = throw IOException("down")
            override suspend fun conversations(): List<ConversationSummary> =
                throw IOException("down")
            override suspend fun myClubs(): List<Club> = throw IOException("down")
        })

        model.load(now)
        advanceUntilIdle()

        assertTrue(model.state.value.error!!.contains("connection"))
    }
}

package com.fishers.app.chat

import com.fishers.app.FakeFishersApi
import com.fishers.app.net.AuthTokens
import com.fishers.app.net.FishersApi
import com.fishers.app.net.LoginRequest
import com.fishers.app.net.PublicUser
import com.fishers.app.net.RefreshRequest
import com.fishers.app.net.RoleIntentPatch
import com.fishers.app.net.SignupRequest
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
import org.junit.Test
import java.io.IOException

@OptIn(ExperimentalCoroutinesApi::class)
class ChatViewModelTest {

    // `runTest` builds its own TestCoroutineScheduler unless it is handed
    // one, and a bare StandardTestDispatcher() builds a second. Work launched
    // on viewModelScope then sits on the dispatcher's scheduler while
    // advanceUntilIdle() drains runTest's, so the assertions run before the
    // view model has done anything — sometimes. It passed on every machine
    // here and failed in CI, which is the worst way to find out.
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun conversation(id: String, at: String, unread: Long = 0) = ConversationSummary(
        id = id, kind = "club", title = "Club $id",
        updatedAt = at, lastMessageAt = at, unreadCount = unread,
    )

    private fun message(id: String, body: String = "hello") = ChatMessage(
        id = id, conversationId = "c", senderId = "u", senderName = "Ravi",
        kind = "text", body = body, createdAt = "2026-09-23T10:00:00Z",
    )

    // ---- the list ----

    @Test
    fun `threads are newest first, whatever order they arrived in`() = runTest(dispatcher.scheduler) {
        val model = ChatListViewModel(object : FakeFishersApi() {
            override suspend fun conversations() = listOf(
                conversation("old", "2026-09-01T10:00:00Z"),
                conversation("new", "2026-09-23T10:00:00Z"),
                conversation("mid", "2026-09-10T10:00:00Z"),
            )
        })

        model.load()
        advanceUntilIdle()

        assertEquals(listOf("new", "mid", "old"), model.state.value.conversations.map { it.id })
    }

    /**
     * An empty list and a list that has not loaded look identical on screen and
     * mean opposite things. Telling somebody they have no chats when the request
     * is still in flight is a lie the app tells confidently.
     */
    @Test
    fun `an empty list is not claimed until the first load has answered`() = runTest(dispatcher.scheduler) {
        val model = ChatListViewModel(object : FakeFishersApi() {
            override suspend fun conversations() = emptyList<ConversationSummary>()
        })

        assertTrue("before loading, nothing is claimed", model.state.value.isFirstLoad)

        model.load()
        advanceUntilIdle()

        assertFalse("after loading, the emptiness is real", model.state.value.isFirstLoad)
        assertTrue(model.state.value.conversations.isEmpty())
    }

    @Test
    fun `a failed load says why and stops claiming to be loading`() = runTest(dispatcher.scheduler) {
        val model = ChatListViewModel(object : FakeFishersApi() {
            override suspend fun conversations(): List<ConversationSummary> =
                throw IOException("no route to host")
        })

        model.load()
        advanceUntilIdle()

        assertTrue(model.state.value.error!!.contains("connection"))
        assertFalse(model.state.value.isLoading)
        assertFalse(model.state.value.isFirstLoad)
    }

    // ---- a thread ----

    @Test
    fun `opening a thread marks it read`() = runTest(dispatcher.scheduler) {
        var markedRead: String? = null
        val model = ChatThreadViewModel(object : FakeFishersApi() {
            override suspend fun messages(id: String) = listOf(message("1"))
            override suspend fun markRead(id: String, body: MarkReadRequest) {
                markedRead = id
            }
        }, "c1")

        model.load()
        advanceUntilIdle()

        assertEquals("c1", markedRead)
    }

    /**
     * The badge being wrong until the next load is not worth an error in front
     * of somebody who is trying to read a message.
     */
    @Test
    fun `failing to mark it read does not spoil the thread`() = runTest(dispatcher.scheduler) {
        val model = ChatThreadViewModel(object : FakeFishersApi() {
            override suspend fun messages(id: String) = listOf(message("1"))
            override suspend fun markRead(id: String, body: MarkReadRequest) =
                throw IOException("offline")
        }, "c1")

        model.load()
        advanceUntilIdle()

        assertEquals(1, model.state.value.messages.size)
        assertNull("and says nothing about it", model.state.value.error)
    }

    /**
     * No optimistic append. A message that appears and then vanishes because
     * the send failed is worse than one that takes a moment: on bad signal,
     * somebody needs to know whether the other captain actually got it.
     */
    @Test
    fun `a message that failed to send is not left on screen as though it had`() = runTest(dispatcher.scheduler) {
        val model = ChatThreadViewModel(object : FakeFishersApi() {
            override suspend fun messages(id: String) = listOf(message("1"))
            override suspend fun markRead(id: String, body: MarkReadRequest) = Unit
            override suspend fun postMessage(id: String, body: PostMessageRequest): ChatMessage =
                throw IOException("offline")
        }, "c1")
        model.load()
        advanceUntilIdle()

        model.send("are we still on for Saturday?")
        advanceUntilIdle()

        assertEquals("only what the server has", 1, model.state.value.messages.size)
        assertTrue(model.state.value.error!!.contains("connection"))
        assertFalse(model.state.value.isSending)
    }

    @Test
    fun `a sent message appears once the server has it`() = runTest(dispatcher.scheduler) {
        val model = ChatThreadViewModel(object : FakeFishersApi() {
            override suspend fun messages(id: String) = listOf(message("1"))
            override suspend fun markRead(id: String, body: MarkReadRequest) = Unit
            override suspend fun postMessage(id: String, body: PostMessageRequest) =
                message("2", body.body)
        }, "c1")
        model.load()
        advanceUntilIdle()

        model.send("  on for Saturday  ")
        advanceUntilIdle()

        assertEquals(2, model.state.value.messages.size)
        assertEquals("trimmed", "on for Saturday", model.state.value.messages.last().body)
    }

    @Test
    fun `an empty message is not sent at all`() = runTest(dispatcher.scheduler) {
        val model = ChatThreadViewModel(object : FakeFishersApi() {
            override suspend fun messages(id: String) = emptyList<ChatMessage>()
            override suspend fun markRead(id: String, body: MarkReadRequest) = Unit
            override suspend fun postMessage(id: String, body: PostMessageRequest): ChatMessage =
                error("should not have been called")
        }, "c1")
        model.load()
        advanceUntilIdle()

        model.send("   ")
        advanceUntilIdle()

        assertTrue(model.state.value.messages.isEmpty())
    }

    @Test
    fun `an agent message is known by having no sender`() {
        val agent = ChatMessage("1", "c", null, null, "agent", "Nine said yes", "t")
        val system = ChatMessage("2", "c", null, null, "system", "Fixture moved", "t")
        val person = ChatMessage("3", "c", "u", "Ravi", "text", "Thanks", "t")

        assertTrue(agent.isAgent)
        assertTrue(system.isSystem)
        assertFalse(person.isAgent)
        assertFalse(person.isSystem)
    }
}

package com.fishers.app.chat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.net.FishersApi
import com.fishers.app.session.readableError
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ChatListState(
    val conversations: List<ConversationSummary> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    /** True before the first load answers, so an empty list is not mistaken
     *  for "you have no chats" while it is still fetching. */
    val isFirstLoad: Boolean = true,
)

class ChatListViewModel(private val api: FishersApi) : ViewModel() {

    private val _state = MutableStateFlow(ChatListState())
    val state: StateFlow<ChatListState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            runCatching { api.conversations() }
                .onSuccess {
                    _state.value = ChatListState(
                        // Newest first. The server orders these, but a list
                        // that re-sorts is a list that cannot be wrong after a
                        // message arrives out of band.
                        conversations = it.sortedByDescending { c -> c.lastMessageAt ?: c.updatedAt },
                        isFirstLoad = false,
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isFirstLoad = false,
                        error = readableError(it),
                    )
                }
        }
    }
}

data class ChatThreadState(
    val messages: List<ChatMessage> = emptyList(),
    val isLoading: Boolean = false,
    val isSending: Boolean = false,
    val error: String? = null,
    val isFirstLoad: Boolean = true,
)

class ChatThreadViewModel(
    private val api: FishersApi,
    private val conversationId: String,
) : ViewModel() {

    private val _state = MutableStateFlow(ChatThreadState())
    val state: StateFlow<ChatThreadState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            runCatching { api.messages(conversationId) }
                .onSuccess {
                    _state.value = ChatThreadState(messages = it, isFirstLoad = false)
                    // Opening a thread is reading it. Failing to say so is not
                    // worth telling anybody about — the badge is wrong until
                    // the next load, and that is all.
                    runCatching { api.markRead(conversationId, MarkReadRequest()) }
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isFirstLoad = false,
                        error = readableError(it),
                    )
                }
        }
    }

    /**
     * Send, and show it once the server has it.
     *
     * No optimistic append. A message that appears and then vanishes because
     * the send failed is worse than one that takes a moment: at a ground, on
     * bad signal, somebody needs to know whether the other captain actually
     * got it.
     */
    fun send(body: String) {
        val text = body.trim()
        if (text.isEmpty() || _state.value.isSending) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isSending = true, error = null)
            runCatching { api.postMessage(conversationId, PostMessageRequest(text)) }
                .onSuccess { sent ->
                    _state.value = _state.value.copy(
                        messages = _state.value.messages + sent,
                        isSending = false,
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        isSending = false,
                        error = readableError(it),
                    )
                }
        }
    }

    fun dismissError() {
        _state.value = _state.value.copy(error = null)
    }
}

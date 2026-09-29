package com.fishers.app.shop

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.net.FishersApi
import com.fishers.app.session.readableError
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class MarketState(
    val listings: List<Product> = emptyList(),
    val search: String = "",
    /** `null` is everything; otherwise "used" or "new". */
    val condition: String? = null,
    val isLoading: Boolean = false,
    val error: String? = null,
    val isFirstLoad: Boolean = true,
)

/** Kit for sale, across every club. */
class MarketViewModel(private val api: FishersApi) : ViewModel() {

    private val _state = MutableStateFlow(MarketState())
    val state: StateFlow<MarketState> = _state.asStateFlow()

    private var pending: Job? = null

    fun load() = fetch(debounce = false)

    fun search(text: String) {
        _state.value = _state.value.copy(search = text)
        // One request per search rather than one per letter.
        fetch(debounce = true)
    }

    fun filter(condition: String?) {
        _state.value = _state.value.copy(condition = condition)
        fetch(debounce = false)
    }

    private fun fetch(debounce: Boolean) {
        // Cancelling the previous request is what stops a slower earlier search
        // from landing on top of a later one.
        pending?.cancel()
        pending = viewModelScope.launch {
            if (debounce) delay(350)
            _state.value = _state.value.copy(isLoading = true, error = null)
            val current = _state.value
            runCatching { api.marketplace(current.condition, current.search.ifBlank { null }) }
                .onSuccess {
                    _state.value = _state.value.copy(
                        listings = it, isLoading = false, isFirstLoad = false, error = null,
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        isLoading = false, isFirstLoad = false, error = readableError(it),
                    )
                }
        }
    }
}

data class ListingState(
    val listing: MarketListing? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val reserving: Boolean = false,
    val reserved: Boolean = false,
    val asking: Boolean = false,
    /** Set once a conversation is open, for the screen to navigate to. */
    val openConversation: String? = null,
)

/** One listing, and the two things a buyer can do about it. */
class ListingViewModel(
    private val api: FishersApi,
    private val productId: String,
) : ViewModel() {

    private val _state = MutableStateFlow(ListingState())
    val state: StateFlow<ListingState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            runCatching { api.marketItem(productId) }
                .onSuccess { _state.value = _state.value.copy(listing = it, isLoading = false, error = null) }
                .onFailure {
                    _state.value = _state.value.copy(isLoading = false, error = readableError(it))
                }
        }
    }

    fun reserve() {
        val listing = _state.value.listing ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(reserving = true, error = null)
            runCatching {
                api.placeOrder(
                    PlaceOrderRequest(
                        clubId = listing.clubId,
                        items = listOf(OrderItemRequest(productId = listing.id, quantity = 1)),
                    ),
                )
            }
                .onSuccess {
                    _state.value = _state.value.copy(reserving = false, reserved = true)
                    load()
                }
                .onFailure {
                    _state.value = _state.value.copy(reserving = false, error = readableError(it))
                }
        }
    }

    /**
     * Straight into the thread rather than a box on this screen: the
     * conversation carries on there, and both of them already know where their
     * messages live.
     */
    fun ask() {
        viewModelScope.launch {
            _state.value = _state.value.copy(asking = true, error = null)
            runCatching { api.enquire(productId) }
                .onSuccess {
                    _state.value = _state.value.copy(asking = false, openConversation = it.conversationId)
                }
                .onFailure {
                    _state.value = _state.value.copy(asking = false, error = readableError(it))
                }
        }
    }

    /** Called once the screen has navigated, so going back does not re-open it. */
    fun conversationOpened() {
        _state.value = _state.value.copy(openConversation = null)
    }
}

package com.fishers.app.match.start

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.i18n.t
import com.fishers.app.net.MatchStartApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** The hub's filter, as `ScoreHubPane.StateFilter` has it. */
enum class HubFilter(val query: String?) {
    All(null), Live("live"), Upcoming("upcoming"), Finished("finished");

    val label: String
        get() = when (this) {
            All -> t("sc.all")
            Live -> t("rest.in_progress")
            Upcoming -> t("sc.not_started")
            Finished -> t("sc.finished")
        }
}

data class ScoreHubState(
    val filter: HubFilter = HubFilter.All,
    val search: String = "",
    val newestFirst: Boolean = false,
    val rows: List<FixtureRow> = emptyList(),
    val total: Int = 0,
    val page: Int = 1,
    val hasMore: Boolean = false,
    val isLoading: Boolean = false,
    val isFirstLoad: Boolean = true,
    val error: String? = null,
    /** Clubs where this person may score — whose live and half-set-up matches they can pick up. */
    val scoringClubs: Set<String> = emptySet(),
)

/** Where tapping a row goes. */
sealed interface HubDestination {
    data class Scorecard(val eventId: String) : HubDestination
    data class Score(val eventId: String) : HubDestination
    data class Setup(val eventId: String) : HubDestination
}

/**
 * Every cricket fixture this person can see, with the match on it — `ScoreHubPane`.
 *
 * Filtering, searching and paging happen in the database, as on iOS: a club
 * with a season behind it is not something to download and sift on a phone.
 */
class ScoreHubViewModel(
    private val api: MatchStartApi,
    private val perPage: Int = 20,
    /** How long typing has to pause before the search goes out. */
    private val searchPause: Long = 350,
) : ViewModel() {

    private val _state = MutableStateFlow(ScoreHubState())
    val state: StateFlow<ScoreHubState> = _state.asStateFlow()

    private var generation = 0
    private var searchJob: Job? = null

    fun load() {
        reload()
        loadScoringClubs()
    }

    fun setFilter(filter: HubFilter) {
        if (filter == _state.value.filter) return
        _state.value = _state.value.copy(filter = filter)
        reload()
    }

    fun setNewestFirst(newest: Boolean) {
        if (newest == _state.value.newestFirst) return
        _state.value = _state.value.copy(newestFirst = newest)
        reload()
    }

    /** One request per pause in typing, not per keystroke. */
    fun setSearch(text: String) {
        _state.value = _state.value.copy(search = text)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(searchPause)
            reload()
        }
    }

    fun reload() {
        val mine = ++generation
        val query = _state.value
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            runCatching { fetch(query, page = 1) }
                .onSuccess { first ->
                    if (mine != generation) return@onSuccess
                    _state.value = _state.value.copy(
                        rows = first.items,
                        total = first.total,
                        page = 1,
                        hasMore = first.hasMore,
                        isLoading = false,
                        isFirstLoad = false,
                    )
                }
                .onFailure {
                    if (mine != generation) return@onFailure
                    _state.value = _state.value.copy(
                        isLoading = false, isFirstLoad = false, error = apiWords(it),
                    )
                }
        }
    }

    fun loadMore() {
        val current = _state.value
        if (current.isLoading || !current.hasMore) return
        val mine = generation
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true)
            runCatching { fetch(current, page = current.page + 1) }
                .onSuccess { next ->
                    if (mine != generation) return@onSuccess
                    val seen = _state.value.rows.map { it.eventId }.toSet()
                    _state.value = _state.value.copy(
                        rows = _state.value.rows + next.items.filter { it.eventId !in seen },
                        page = current.page + 1,
                        hasMore = next.hasMore,
                        total = next.total,
                        isLoading = false,
                    )
                }
                .onFailure {
                    if (mine != generation) return@onFailure
                    _state.value = _state.value.copy(isLoading = false, error = apiWords(it))
                }
        }
    }

    /**
     * Where a row goes. A finished match is read, never re-scored; a live one
     * is scored by whoever may score it and followed by everyone else; a fixture
     * with no match, or one half set up, opens the setup for somebody who can
     * score it.
     */
    fun destination(row: FixtureRow): HubDestination {
        val mayScore = row.clubId in _state.value.scoringClubs
        return when (row.stage) {
            FixtureRow.Stage.Finished -> HubDestination.Scorecard(row.eventId)
            FixtureRow.Stage.Live ->
                if (mayScore) HubDestination.Score(row.eventId) else HubDestination.Scorecard(row.eventId)
            FixtureRow.Stage.SettingUp, FixtureRow.Stage.NotStarted ->
                if (mayScore) HubDestination.Setup(row.eventId) else HubDestination.Scorecard(row.eventId)
        }
    }

    private suspend fun fetch(query: ScoreHubState, page: Int): FixturePage {
        // One letter matches most of the table, and the API refuses it.
        val search = query.search.trim().takeIf { it.length >= 2 }
        return api.cricketFixtures(
            state = query.filter.query,
            search = search,
            order = if (query.newestFirst) "desc" else "asc",
            page = page,
            perPage = perPage,
        )
    }

    /** Which clubs this person may score in. Best effort: without it every row opens the scorecard. */
    private fun loadScoringClubs() {
        viewModelScope.launch {
            val clubs = runCatching { api.myClubs() }.getOrDefault(emptyList())
            val scoring = clubs.filter { club ->
                runCatching { api.myClubRole(club.id) }.getOrNull()
                    ?.permissions?.contains("score_match") == true
            }.map { it.id }.toSet()
            _state.value = _state.value.copy(scoringClubs = scoring)
        }
    }
}

package com.fishers.app.season

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.clubs.Club
import com.fishers.app.i18n.t
import com.fishers.app.net.FishersApi
import com.fishers.app.session.readableError
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import retrofit2.HttpException
import java.time.Year

enum class SeasonTab { Mine, Club }

/**
 * Where the stats screen should open: which tab, season and club.
 *
 * The website's address is `/stats?season=2026&club=<id>`, and the season
 * email and the `season_closed` push both carry it, so one parser serves a
 * notification tap, the profile button and the club screen alike.
 */
data class SeasonLink(
    val tab: SeasonTab = SeasonTab.Mine,
    val season: Int? = null,
    val clubId: String? = null,
) {
    companion object {
        /**
         * From a push's data. FCM carries strings only, and the season and
         * club arrive both as their own keys and inside `url` — either is
         * enough. Anything that is not about the stats page is not ours: null.
         */
        fun fromPush(
            url: String?,
            season: String? = null,
            clubId: String? = null,
            thisYear: Int = Year.now().value,
        ): SeasonLink? {
            val path = url?.substringBefore('?')
            if (path != "/stats" && (season == null || clubId == null)) return null
            val query = url?.substringAfter('?', "")
                ?.split('&')
                ?.mapNotNull { pair ->
                    pair.split('=', limit = 2).takeIf { it.size == 2 }?.let { it[0] to it[1] }
                }
                ?.toMap()
                .orEmpty()
            // A season from a link is somebody else's text: keep it to years
            // that could have been played, as the web does.
            val year = (season ?: query["season"])?.toIntOrNull()?.takeIf { it in 2000..thisYear + 1 }
            val tab = if (query["tab"] == "club") SeasonTab.Club else SeasonTab.Mine
            return SeasonLink(tab = tab, season = year, clubId = clubId ?: query["club"])
        }
    }
}

data class SeasonState(
    val tab: SeasonTab = SeasonTab.Mine,
    /** Null until the API has said which season it chose. */
    val season: Int? = null,
    val clubs: List<Club> = emptyList(),
    val clubId: String? = null,
    val game: PlayerGame? = null,
    val club: ClubSeason? = null,
    /** Only ever set for somebody who may close the season, and only while it is open. */
    val preview: ClosePreview? = null,
    val isLoading: Boolean = false,
    val error: String? = null,
    val isClosing: Boolean = false,
    /** What happened when the secretary pressed the button. */
    val closeNote: String? = null,
    val thisYear: Int = Year.now().value,
) {
    val seasons: List<Int>
        get() = pickerSeasons(
            thisYear, game?.seasons.orEmpty(), club?.seasons.orEmpty(), current = season,
        )
}

/**
 * Stats, for players first — `web/src/app/stats/page.tsx`.
 *
 * One model for both tabs, because they share the season picker: a player
 * looking at 2025 who switches to the club wants the club's 2025, not
 * whatever the club tab last showed.
 */
class SeasonViewModel(private val api: FishersApi) : ViewModel() {

    private val _state = MutableStateFlow(SeasonState())
    val state: StateFlow<SeasonState> = _state.asStateFlow()

    private var loading: Job? = null
    private var clubsLoaded = false

    /** Land somewhere specific — a notification, the profile, a club. */
    fun open(link: SeasonLink) {
        _state.update {
            it.copy(
                tab = link.tab,
                season = link.season,
                clubId = link.clubId ?: it.clubId,
                game = null,
                club = null,
                preview = null,
                closeNote = null,
                error = null,
            )
        }
        load()
    }

    fun selectTab(tab: SeasonTab) {
        if (tab == _state.value.tab) return
        _state.update { it.copy(tab = tab, error = null, closeNote = null) }
        load()
    }

    fun selectSeason(season: Int) {
        if (season == _state.value.season) return
        _state.update { it.copy(season = season, closeNote = null) }
        load()
    }

    fun selectClub(clubId: String) {
        _state.update { it.copy(clubId = clubId, tab = SeasonTab.Club, closeNote = null) }
        load()
    }

    fun load() {
        // A tap on another season while the last one is still loading: the
        // answer that arrives last must be the one that was asked for last.
        loading?.cancel()
        loading = viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            if (!clubsLoaded) {
                runCatching { api.myClubs() }.onSuccess { clubs ->
                    clubsLoaded = true
                    _state.update {
                        it.copy(
                            clubs = clubs.sortedBy { c -> c.name.lowercase() },
                            clubId = it.clubId ?: clubs.minByOrNull { c -> c.name.lowercase() }?.id,
                        )
                    }
                }
            }
            val s = _state.value
            when (s.tab) {
                SeasonTab.Mine -> runCatching { api.myGame(season = s.season) }
                    .onSuccess { game ->
                        _state.update {
                            it.copy(game = game, season = it.season ?: game.season, isLoading = false)
                        }
                    }
                    .onFailure { e -> fail(e, "ss.could_not_load") }

                SeasonTab.Club -> {
                    val clubId = s.clubId
                    if (clubId == null) {
                        _state.update { it.copy(club = null, isLoading = false) }
                        return@launch
                    }
                    runCatching { api.clubSeason(clubId, s.season) }
                        .onSuccess { club ->
                            _state.update {
                                it.copy(
                                    club = club,
                                    season = it.season ?: club.season,
                                    preview = null,
                                    isLoading = false,
                                )
                            }
                            loadPreview(club)
                        }
                        .onFailure { e ->
                            _state.update { it.copy(club = null) }
                            fail(e, "ss.could_not_load")
                        }
                }
            }
        }
    }

    /**
     * Ask what this person may do first: only somebody who runs the club's
     * operations is shown the box at all, and players never see a refusal
     * for something they did not ask to do.
     */
    private suspend fun loadPreview(club: ClubSeason) {
        if (club.closedAt != null) return
        val role = runCatching { api.myClubRole(club.clubId) }.getOrNull() ?: return
        if (!role.canCloseSeason) return
        val preview = runCatching { api.closeSeasonPreview(club.clubId, club.season) }.getOrNull()
        _state.update { if (it.club?.clubId == club.clubId) it.copy(preview = preview) else it }
    }

    /** Called after the confirmation, never before: it cannot be taken back. */
    fun close() {
        val club = _state.value.club ?: return
        if (_state.value.isClosing) return
        viewModelScope.launch {
            _state.update { it.copy(isClosing = true, closeNote = null) }
            runCatching { api.closeSeason(club.clubId, club.season) }
                .onSuccess { done ->
                    _state.update {
                        it.copy(
                            isClosing = false,
                            closeNote = t("ss.closed_now", vars = mapOf("n" to done.queued)),
                        )
                    }
                    load()
                }
                .onFailure { e ->
                    // 409: somebody closed it first. That is the outcome
                    // wanted, so show it as closed rather than as an error.
                    if (e is HttpException && e.code() == 409) {
                        _state.update { it.copy(isClosing = false) }
                        load()
                    } else {
                        _state.update {
                            it.copy(isClosing = false, closeNote = seasonError(e, "ss.could_not_close"))
                        }
                    }
                }
        }
    }

    private fun fail(e: Throwable, fallback: String) {
        if (e is kotlinx.coroutines.CancellationException) throw e
        _state.update { it.copy(isLoading = false, error = seasonError(e, fallback)) }
    }
}

/**
 * The connection and the server being down say so in the app's usual words;
 * anything else — a 403 for a club somebody has left, say — is this screen's
 * own sentence rather than "HTTP 403".
 */
internal fun seasonError(e: Throwable, fallback: String): String = when {
    e is java.io.IOException -> readableError(e)
    e is HttpException && e.code() in 500..599 -> readableError(e)
    else -> t(fallback)
}

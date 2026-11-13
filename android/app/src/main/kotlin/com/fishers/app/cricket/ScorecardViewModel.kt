package com.fishers.app.cricket

import androidx.lifecycle.ViewModel
import com.fishers.app.i18n.t
import com.fishers.app.net.ScoringApi
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import retrofit2.HttpException

data class ScorecardState(
    val loading: Boolean = true,
    val match: CricketMatch? = null,
    val view: MatchView? = null,
    val dls: DlsPar? = null,
    val error: String? = null,
    /** The last refresh failed; the card shown is the one before it. */
    val stale: Boolean = false,
    val moment: Moment? = null,
    val momentCount: Int = 0,
)

/**
 * Following a match somebody else is scoring. `CricketScorecardView.swift`.
 *
 * The card is the server's — `GET /cricket/matches/{id}/scorecard`, its own
 * fold of the log — read again every ten seconds while the screen is open.
 * [follow] is a suspend loop rather than a job this model starts, so the
 * screen that calls it decides when it stops: leaving the screen, or the app
 * going to the background, cancels it and nothing polls behind anybody's back.
 */
class ScorecardViewModel(
    private val api: ScoringApi,
    private val eventId: String,
    private val every: Long = 10_000,
) : ViewModel() {

    private val _state = MutableStateFlow(ScorecardState())
    val state: StateFlow<ScorecardState> = _state.asStateFlow()

    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }
    private var matchId: String? = null

    /**
     * Read the card now, then every [every] ms until cancelled. Even once it
     * is over: the award comes after the last ball, and a scorer who undoes
     * the last ball reopens the match.
     */
    suspend fun follow() {
        while (true) {
            refresh()
            delay(every)
        }
    }

    internal suspend fun refresh() {
        try {
            val id = matchId ?: api.matchForEvent(eventId).also { match ->
                matchId = match.id
                _state.update { it.copy(match = match) }
            }.id
            val card = api.scorecard(id)
            val view = json.decodeFromJsonElement(MatchView.serializer(), card)
            val dls = (card["dls"] as? JsonObject)?.let {
                runCatching { json.decodeFromJsonElement(DlsPar.serializer(), it) }.getOrNull()
            }
            _state.update {
                val moment = Moment.between(it.view, view)
                it.copy(
                    loading = false,
                    view = view,
                    dls = dls,
                    error = null,
                    stale = false,
                    moment = moment ?: it.moment,
                    momentCount = if (moment != null) it.momentCount + 1 else it.momentCount,
                )
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            _state.update {
                when {
                    // Nobody has set up the match on this fixture yet.
                    e is HttpException && e.code() == 404 && it.view == null ->
                        it.copy(loading = false, error = t("sc.no_match_on_this_fixture"))
                    // A card already on screen stays; it is only marked as not the latest.
                    it.view != null -> it.copy(loading = false, stale = true)
                    else -> it.copy(loading = false, error = serverWords(e))
                }
            }
        }
    }
}

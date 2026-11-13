package com.fishers.app.fixtures

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.i18n.t
import com.fishers.app.motm.MotmPollView
import com.fishers.app.net.FixturesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** How far the scorebook on a fixture has got. */
sealed interface MatchOnFixture {
    /** Not asked yet, or asking failed — say nothing rather than something wrong. */
    data object Unknown : MatchOnFixture
    /** The server says there is none: 404. */
    data object NotStarted : MatchOnFixture
    /** Made, and being set up — the toss, the sheets. */
    data class SettingUp(val match: FixtureMatch) : MatchOnFixture
    data class Live(val match: FixtureMatch) : MatchOnFixture
    data class Finished(val match: FixtureMatch) : MatchOnFixture

    companion object {
        fun of(match: FixtureMatch): MatchOnFixture = when (match.status) {
            "live", "innings_break" -> Live(match)
            "complete", "published" -> Finished(match)
            else -> SettingUp(match)
        }
    }
}

/** What the match card offers. Each one is a screen another area draws. */
enum class MatchAction {
    /** Make the scorebook: overs, sides, toss. */
    SetUp,
    /** Pick up where the setup left off. */
    ContinueSetup,
    Score,
    Follow,
    Scorecard,
}

/**
 * The buttons on a fixture's match card, from how far the match has got and
 * whether this person may score it. A pure function so the mapping is tested
 * rather than eyeballed.
 *
 * Before a match exists only a scorer can do anything; once one does, anybody
 * in either club can follow it.
 */
fun matchActions(isCricketMatch: Boolean, match: MatchOnFixture, canScoreHere: Boolean): List<MatchAction> {
    if (!isCricketMatch) return emptyList()
    return when (match) {
        MatchOnFixture.Unknown -> emptyList()
        MatchOnFixture.NotStarted -> if (canScoreHere) listOf(MatchAction.SetUp) else emptyList()
        is MatchOnFixture.SettingUp ->
            if (match.match.canScore) listOf(MatchAction.ContinueSetup) else listOf(MatchAction.Follow)
        is MatchOnFixture.Live ->
            if (match.match.canScore) listOf(MatchAction.Score, MatchAction.Follow) else listOf(MatchAction.Follow)
        is MatchOnFixture.Finished -> listOf(MatchAction.Scorecard)
    }
}

data class FixtureDetailState(
    val event: FishersEvent? = null,
    val venue: Venue? = null,
    val attendees: List<Attendee> = emptyList(),
    /** Your own answer to the fixture. */
    val myAnswer: RsvpStatus? = null,
    val role: ClubRole? = null,
    /** Null for somebody in the visiting club, who cannot see the home side's board. */
    val board: SelectionBoard? = null,
    val match: MatchOnFixture = MatchOnFixture.Unknown,
    val motm: MotmPollView? = null,
    val isLoading: Boolean = true,
    val isAnswering: Boolean = false,
    val isResponding: Boolean = false,
    val isChangingStatus: Boolean = false,
    /** Something went wrong — shown in red. */
    val error: String? = null,
    /** Something went right — shown quietly. */
    val message: String? = null,
) {
    /** Captains and secretaries: pick the side, call it off. */
    val canSelect: Boolean get() = role?.canSelect == true

    /** Only a game of cricket has a match card: nets and training have no scorebook. */
    val hasMatchCard: Boolean get() = event?.isCricketMatch == true

    /** What the page asks above your answer. Nobody "plays" at nets. */
    val question: String
        get() = if (event?.subtype?.isPractice == true) t("np.are_you_coming") else t("ev.are_you_playing")

    /** Your row on the selection board, once a side has been picked. */
    fun myPlace(meId: String?): SelectionCandidate? =
        meId?.let { board?.candidate(it) }?.takeIf { it.state != SelectionState.Pool }

    fun matchActions(): List<MatchAction> {
        val event = event ?: return emptyList()
        return matchActions(event.isCricketMatch, match, role?.canScore == true)
    }
}

/**
 * One fixture — `EventDetailView.swift`: when and where, your answer, who is
 * coming, the side and your place in it, and the match on the day.
 *
 * Only the fixture itself has to load. Everything else is somebody else's
 * business on a bad day — a visiting player cannot see the home side's board,
 * a fixture with no match has no scorebook — so each of those failing leaves
 * its own card out rather than emptying the page.
 */
class FixtureDetailViewModel(
    private val api: FixturesApi,
    private val eventId: String,
    /** Who is reading, to find their own answer and their own place in the side. */
    private val meId: String?,
) : ViewModel() {

    private val _state = MutableStateFlow(FixtureDetailState())
    val state: StateFlow<FixtureDetailState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            runCatching { api.event(eventId) }
                .onSuccess { event -> loadAround(event) }
                .onFailure {
                    _state.value = _state.value.copy(isLoading = false, error = fixtureError(it))
                }
        }
    }

    private suspend fun loadAround(event: FishersEvent) = coroutineScope {
        val attendees = async { runCatching { api.attendees(eventId) }.getOrNull() }
        val role = async { runCatching { api.myRole(event.clubId) }.getOrNull() }
        val board = async {
            if (event.hasSelection) runCatching { api.selectionBoard(eventId) }.getOrNull() else null
        }
        val venue = async {
            event.venueId?.let { id ->
                runCatching { api.venues(event.clubId) }.getOrNull()?.firstOrNull { it.id == id }
            }
        }
        val match = async { if (event.isCricketMatch) loadMatch() else MatchOnFixture.Unknown }
        val motm = async { runCatching { api.motm(eventId) }.getOrNull() }

        val people = attendees.await()
        val theBoard = board.await()
        _state.value = _state.value.copy(
            event = event,
            venue = venue.await(),
            attendees = people.orEmpty().sortedWith(ATTENDEE_ORDER),
            // The attendee list carries everybody's answer, yours included;
            // the board carries it too, for somebody who cannot see the list.
            myAnswer = people?.firstOrNull { it.userId == meId }?.status?.takeIf { it != RsvpStatus.Invited }
                ?: meId?.let { theBoard?.candidate(it)?.rsvp }?.takeIf { it != RsvpStatus.Invited }
                ?: event.myRsvp,
            role = role.await(),
            board = theBoard,
            match = match.await(),
            motm = motm.await(),
            isLoading = false,
        )
    }

    private suspend fun loadMatch(): MatchOnFixture =
        runCatching { api.cricketMatch(eventId) }.fold(
            onSuccess = { MatchOnFixture.of(it) },
            onFailure = { if (it.isNotFound()) MatchOnFixture.NotStarted else MatchOnFixture.Unknown },
        )

    /**
     * Answer it. Shown at once and put back if the server refuses — the same
     * rule as the list: an answer the server never took is worse than none.
     */
    fun answer(status: RsvpStatus) {
        val before = _state.value
        if (before.isAnswering || before.myAnswer == status) return
        _state.value = before.copy(
            myAnswer = status,
            isAnswering = true,
            error = null,
            message = null,
            attendees = before.attendees.map { if (it.userId == meId) it.copy(status = status) else it },
        )
        viewModelScope.launch {
            runCatching { api.rsvp(eventId, RsvpRequest(status)) }
                .onSuccess { _state.value = _state.value.copy(isAnswering = false) }
                .onFailure {
                    _state.value = _state.value.copy(
                        myAnswer = before.myAnswer,
                        attendees = before.attendees,
                        isAnswering = false,
                        error = fixtureError(it),
                    )
                }
        }
    }

    /** A picked player saying they are playing — or pulling out, which calls up a reserve. */
    fun respondToSelection(confirming: Boolean) {
        if (_state.value.isResponding) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isResponding = true, error = null, message = null)
            runCatching { api.respondToSelection(eventId, RespondToSelectionBody(confirming)) }
                .onSuccess {
                    val board = runCatching { api.selectionBoard(eventId) }.getOrNull()
                    _state.value = _state.value.copy(
                        board = board ?: _state.value.board,
                        isResponding = false,
                        message = if (confirming) t("ld.you_are_in") else t("ld.told_them_you_cannot_play"),
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(isResponding = false, error = fixtureError(it))
                }
        }
    }

    /**
     * Postpone it, call it off, or put it back on. Everybody who was asked is
     * told by the server, with the reason — which is why the reason is asked for.
     */
    fun changeStatus(status: EventStatus, note: String?) {
        if (_state.value.isChangingStatus) return
        val wire = when (status) {
            EventStatus.Postponed -> "postponed"
            EventStatus.Cancelled -> "cancelled"
            EventStatus.Scheduled -> "scheduled"
            else -> return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isChangingStatus = true, error = null, message = null)
            runCatching {
                api.updateFixtureStatus(eventId, FixtureStatusBody(wire, note?.trim()?.takeIf { it.isNotEmpty() }))
            }
                .onSuccess {
                    val event = runCatching { api.event(eventId) }.getOrNull()
                    _state.value = _state.value.copy(
                        event = event ?: _state.value.event?.copy(status = status, statusNote = note),
                        isChangingStatus = false,
                        message = when (status) {
                            EventStatus.Postponed -> t("ld.postponed_everybody_has_been_told")
                            EventStatus.Cancelled -> t("ld.called_off_everybody_has_been_told")
                            else -> t("ld.back_on")
                        },
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(isChangingStatus = false, error = fixtureError(it))
                }
        }
    }

    private companion object {
        /** Available first, then maybe, then the unanswered, then the noes; by name within each. */
        val ATTENDEE_ORDER = compareBy<Attendee>(
            {
                when (it.status) {
                    RsvpStatus.Going -> 0
                    RsvpStatus.Maybe -> 1
                    RsvpStatus.Invited -> 2
                    RsvpStatus.NotGoing -> 3
                }
            },
            { it.name.lowercase() },
        )
    }
}

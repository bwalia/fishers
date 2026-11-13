package com.fishers.app.fixtures

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.clubs.Club
import com.fishers.app.clubs.Team
import com.fishers.app.i18n.t
import com.fishers.app.net.FixturesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

/** The kinds of match the form offers. A cup is a tournament to the server. */
val MATCH_KINDS = listOf(EventSubtype.LeagueMatch, EventSubtype.Friendly, EventSubtype.Tournament)

data class CreateFixtureState(
    /** Only the clubs where this person may put a match in the diary. */
    val clubs: List<Club> = emptyList(),
    val isLoadingClubs: Boolean = true,
    val clubId: String? = null,
    val teams: List<Team> = emptyList(),
    val teamId: String? = null,
    val venues: List<Venue> = emptyList(),
    val venueId: String? = null,
    /** Saving a ground needs more than scheduling a match does. */
    val canAddGround: Boolean = false,
    val isAddingGround: Boolean = false,
    /** Typed, for a side that is not on the app. */
    val oppositionName: String = "",
    /** Picked from the search, for a side that is — their players get asked too. */
    val opponent: Opponent? = null,
    val searchResults: List<Opponent> = emptyList(),
    val isSearching: Boolean = false,
    val kind: EventSubtype = EventSubtype.LeagueMatch,
    val date: LocalDate,
    val time: LocalTime = LocalTime.of(13, 0),
    val isSaving: Boolean = false,
    val error: String? = null,
    /** Set once the server has the fixture; the screen becomes it. */
    val createdEventId: String? = null,
) {
    val club: Club? get() = clubs.firstOrNull { it.id == clubId }

    /** Whoever was picked from the search, else whatever was typed. */
    val theirName: String get() = opponent?.displayName ?: oppositionName.trim()
}

/**
 * The "Schedule a match" form — `ScheduleMatchSheet` in `FixturesView.swift`,
 * with the team, the kind of match and a new ground on top.
 *
 * Saving asks everyone in the club (and in the opposition's, when they are on
 * the app) whether they can play; the server does that, not this.
 */
class CreateFixtureViewModel(
    private val api: FixturesApi,
    /** The club to start on, when the form was opened from one. */
    private val preferredClubId: String? = null,
    private val zone: ZoneId = ZoneId.systemDefault(),
    private val now: () -> Instant = Instant::now,
) : ViewModel() {

    private val _state = MutableStateFlow(
        // Next week, one o'clock: when most club cricket starts, and far enough
        // off that the default is never already in the past.
        CreateFixtureState(date = now().atZone(zone).toLocalDate().plusDays(7)),
    )
    val state: StateFlow<CreateFixtureState> = _state.asStateFlow()

    private var search: Job? = null
    private var clubLoad: Job? = null
    /** Each club's answer to "what may I do here", asked once. */
    private val roles = mutableMapOf<String, ClubRole?>()

    /** The clubs where you may schedule, each asked separately — as iOS does. */
    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoadingClubs = true, error = null)
            runCatching { api.clubs() }
                .onSuccess { clubs ->
                    clubs.forEach { roles[it.id] = runCatching { api.myRole(it.id) }.getOrNull() }
                    val allowed = clubs.filter { roles[it.id]?.canManageEvents == true }
                        .sortedBy { it.name.lowercase() }
                    val first = allowed.firstOrNull { it.id == preferredClubId } ?: allowed.firstOrNull()
                    _state.value = _state.value.copy(clubs = allowed, isLoadingClubs = false)
                    first?.let { selectClub(it.id) }
                }
                .onFailure {
                    _state.value = _state.value.copy(isLoadingClubs = false, error = fixtureError(it))
                }
        }
    }

    /** The grounds and teams belong to whichever club is hosting, so both change with it. */
    fun selectClub(clubId: String) {
        val opponent = _state.value.opponent?.takeIf { it.clubId != clubId }
        _state.value = _state.value.copy(
            clubId = clubId, teams = emptyList(), teamId = null, venues = emptyList(), venueId = null,
            canAddGround = false, opponent = opponent, error = null,
        )
        clubLoad?.cancel()
        clubLoad = viewModelScope.launch {
            val teams = runCatching { api.teams(clubId) }.getOrDefault(emptyList())
            val venues = runCatching { api.venues(clubId) }.getOrDefault(emptyList())
            val role = roles[clubId]
            if (_state.value.clubId != clubId) return@launch
            _state.value = _state.value.copy(
                teams = teams,
                // One team is the side; nobody should have to pick it.
                teamId = teams.singleOrNull()?.id,
                venues = venues,
                // One ground is where they play.
                venueId = venues.singleOrNull()?.id,
                canAddGround = role?.canAddGround == true,
            )
        }
    }

    fun selectTeam(teamId: String?) {
        _state.value = _state.value.copy(teamId = teamId)
    }

    fun selectVenue(venueId: String?) {
        _state.value = _state.value.copy(venueId = venueId)
    }

    fun setKind(kind: EventSubtype) {
        _state.value = _state.value.copy(kind = kind)
    }

    fun setDate(date: LocalDate) {
        _state.value = _state.value.copy(date = date)
    }

    fun setTime(time: LocalTime) {
        _state.value = _state.value.copy(time = time)
    }

    /**
     * Who you are playing, typed. A scratch side that is not on the app is
     * only ever a name, and that is fine; one that is gets offered as they
     * type, so their players can be asked too.
     */
    fun setOppositionName(name: String) {
        _state.value = _state.value.copy(oppositionName = name, opponent = null, error = null)
        search(name)
    }

    fun pickOpponent(opponent: Opponent) {
        search?.cancel()
        _state.value = _state.value.copy(opponent = opponent, searchResults = emptyList(), isSearching = false, error = null)
    }

    /** Back to the typed name. */
    fun clearOpponent() {
        _state.value = _state.value.copy(opponent = null)
    }

    /** Looked up a beat after the last key — not once per letter. */
    private fun search(query: String) {
        search?.cancel()
        val term = query.trim()
        if (term.length < 2) {
            _state.value = _state.value.copy(searchResults = emptyList(), isSearching = false)
            return
        }
        search = viewModelScope.launch {
            delay(SEARCH_PAUSE_MS)
            _state.value = _state.value.copy(isSearching = true)
            val found = runCatching { api.searchOpponents(term) }.getOrDefault(emptyList())
            _state.value = _state.value.copy(
                // Your own club is not an opposition.
                searchResults = found.filter { it.clubId != _state.value.clubId },
                isSearching = false,
            )
        }
    }

    /** A new ground, saved to the club and chosen for this match. */
    fun addGround(name: String) {
        val clubId = _state.value.clubId ?: return
        val trimmed = name.trim()
        if (trimmed.isEmpty() || _state.value.isAddingGround) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isAddingGround = true, error = null)
            runCatching { api.createVenue(clubId, NewVenue(trimmed)) }
                .onSuccess { venue ->
                    _state.value = _state.value.copy(
                        venues = (_state.value.venues + venue).sortedBy { it.name.lowercase() },
                        venueId = venue.id,
                        isAddingGround = false,
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(isAddingGround = false, error = fixtureError(it))
                }
        }
    }

    /** When it starts, in the reader's own time zone. */
    fun startsAt(state: CreateFixtureState = _state.value): Instant =
        ZonedDateTime.of(state.date, state.time, zone).toInstant()

    /**
     * What is still missing, in the order the form asks — a dead button with
     * no explanation reads as a broken app. Empty when it can be saved.
     */
    fun missing(state: CreateFixtureState = _state.value): List<String> = buildList {
        if (state.club == null) add(t("ev.missing_which_club"))
        if (state.theirName.isEmpty()) add(t("ev.missing_who"))
        if (!startsAt(state).isAfter(now())) add(t("ev.missing_when"))
    }

    fun save() {
        val s = _state.value
        val club = s.club ?: return
        if (s.isSaving || missing(s).isNotEmpty()) return
        if (s.opponent?.clubId == club.id) {
            _state.value = s.copy(error = t("ld.your_side_and_the_opposition_are_the_s"))
            return
        }
        val start = startsAt(s)
        val body = CreateEventBody(
            clubId = club.id,
            opponentClubId = s.opponent?.clubId,
            teamId = s.teamId,
            // What the club plays. Hard-coding cricket filed every fixture as
            // a cricket match whatever the club turns out for.
            sport = club.sportTypes.firstOrNull() ?: "cricket",
            subtype = s.kind,
            title = "${club.name} v ${s.theirName}",
            venueId = s.venueId,
            startAt = start.toString(),
            // A cricket match runs most of an afternoon; nobody wants to type
            // an end time as well.
            endAt = start.plus(MATCH_LENGTH).toString(),
        )
        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true, error = null)
            runCatching { api.createEvent(body) }
                .onSuccess { _state.value = _state.value.copy(isSaving = false, createdEventId = it.id) }
                .onFailure { _state.value = _state.value.copy(isSaving = false, error = fixtureError(it)) }
        }
    }

    private companion object {
        const val SEARCH_PAUSE_MS = 300L
        val MATCH_LENGTH: Duration = Duration.ofHours(5)
    }
}

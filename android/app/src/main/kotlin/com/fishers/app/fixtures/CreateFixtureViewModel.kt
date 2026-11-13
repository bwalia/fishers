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
import java.util.UUID

/** The kinds of match the form offers. A cup is a tournament to the server. */
val MATCH_KINDS = listOf(EventSubtype.LeagueMatch, EventSubtype.Friendly, EventSubtype.Tournament)

/** What the form can make besides a match. */
val PRACTICE_KINDS = listOf(EventSubtype.Nets, EventSubtype.Training)

/** How long a session may run, in minutes. */
val SESSION_MINUTES = listOf(60, 90, 120, 180)

/** How many weeks a weekly series may run for, and how many it starts at. */
val SERIES_WEEKS = 2..12
const val DEFAULT_SERIES_WEEKS = 8

/** Nets take a while to get everybody through; training is a shorter hour and a half. */
fun defaultMinutes(kind: EventSubtype): Int = if (kind == EventSubtype.Training) 90 else 120

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
    /** Nets or training; null for a match, which is what the form has always made. */
    val practice: EventSubtype? = null,
    /** The session's name. Starts as the kind's own, "Nets" or "Training". */
    val name: String = "",
    val minutes: Int = defaultMinutes(EventSubtype.Nets),
    val note: String = "",
    val repeatWeekly: Boolean = false,
    val weeks: Int = DEFAULT_SERIES_WEEKS,
    val isSaving: Boolean = false,
    val error: String? = null,
    /** Weeks of a series already on the server — said when a later week fails. */
    val sessionsMade: Int = 0,
    /** Set once the server has the fixture; the screen becomes it. For a series, the first week. */
    val createdEventId: String? = null,
) {
    val club: Club? get() = clubs.firstOrNull { it.id == clubId }

    val isPractice: Boolean get() = practice != null

    /** Whoever was picked from the search, else whatever was typed. */
    val theirName: String get() = opponent?.displayName ?: oppositionName.trim()
}

/**
 * The "Schedule a match" form — `ScheduleMatchSheet` in `FixturesView.swift`,
 * with the team, the kind of match and a new ground on top.
 *
 * Saving asks everyone in the club (and in the opposition's, when they are on
 * the app) whether they can play; the server does that, not this.
 *
 * The same form schedules nets and training: no opposition and no kind of
 * match, but a name, a length, a note, and optionally the same slot every
 * week — one event per week, made one after another.
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

    /** The sessions being made, as first planned, and the ids of those the server has. */
    private var plan: List<CreateEventBody> = emptyList()
    private val made = mutableListOf<String>()

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
     * A match, nets or training. The name and the length follow the kind
     * until somebody changes them: "Nets" becomes "Training", but "Wednesday
     * nets" stays put.
     */
    fun setWhat(practice: EventSubtype?) {
        val s = _state.value
        if (practice == s.practice || (practice != null && !practice.isPractice)) return
        val nameIsDefault = s.name.isBlank() || PRACTICE_KINDS.any { s.name == it.label }
        val lengthIsDefault = PRACTICE_KINDS.any { s.minutes == defaultMinutes(it) }
        _state.value = s.copy(
            practice = practice,
            name = if (practice != null && nameIsDefault) practice.label else s.name,
            minutes = if (practice != null && lengthIsDefault) defaultMinutes(practice) else s.minutes,
            error = null,
        )
    }

    fun setName(name: String) {
        _state.value = _state.value.copy(name = name)
    }

    fun setMinutes(minutes: Int) {
        _state.value = _state.value.copy(minutes = minutes)
    }

    fun setNote(note: String) {
        _state.value = _state.value.copy(note = note)
    }

    fun setRepeatWeekly(on: Boolean) {
        _state.value = _state.value.copy(repeatWeekly = on)
    }

    fun setWeeks(weeks: Int) {
        _state.value = _state.value.copy(weeks = weeks.coerceIn(SERIES_WEEKS))
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
        // Nets have no opposition.
        if (!state.isPractice && state.theirName.isEmpty()) add(t("ev.missing_who"))
        if (!startsAt(state).isAfter(now())) add(t("ev.missing_when"))
    }

    fun save() {
        val s = _state.value
        val club = s.club ?: return
        if (s.isSaving || missing(s).isNotEmpty()) return
        if (s.isPractice) return schedule(s)
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

    /**
     * What a nets or training session sends: one body, or one per week of a
     * series. Each week is a week on in the scheduler's own zone, so seven
     * o'clock nets stay at seven when the clocks change; each ends its length
     * after it starts. No opposition, and no recurrence rule — every week is
     * an event of its own, which is what puts it in everybody's diary.
     */
    fun sessions(
        state: CreateFixtureState = _state.value,
        seriesId: String = UUID.randomUUID().toString(),
    ): List<CreateEventBody> {
        val club = state.club ?: return emptyList()
        val kind = state.practice ?: return emptyList()
        val first = ZonedDateTime.of(state.date, state.time, zone)
        val count = if (state.repeatWeekly) state.weeks else 1
        val length = Duration.ofMinutes(state.minutes.toLong())
        val note = state.note.trim().takeIf { it.isNotEmpty() }
        return (0 until count).map { week ->
            val start = first.plusWeeks(week.toLong()).toInstant()
            CreateEventBody(
                clubId = club.id,
                teamId = state.teamId,
                sport = club.sportTypes.firstOrNull() ?: "cricket",
                subtype = kind,
                title = state.name.trim().ifEmpty { kind.label },
                venueId = state.venueId,
                startAt = start.toString(),
                endAt = start.plus(length).toString(),
                metadata = SessionMetadata(
                    note = note,
                    seriesId = seriesId.takeIf { state.repeatWeekly },
                    seriesIndex = week.takeIf { state.repeatWeekly },
                    seriesCount = count.takeIf { state.repeatWeekly },
                ),
            )
        }
    }

    /**
     * Make the sessions one after another, stopping at the first refusal.
     *
     * Once any week is on the server the series is fixed: trying again sends
     * only the weeks still missing, as first planned and under the same series
     * id, so nobody is asked about the same Wednesday twice.
     */
    private fun schedule(s: CreateFixtureState) {
        if (made.isEmpty()) plan = sessions(s)
        val left = plan.drop(made.size)
        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true, error = null)
            for (body in left) {
                val event = runCatching { api.createEvent(body) }.getOrElse {
                    _state.value = _state.value.copy(isSaving = false, sessionsMade = made.size, error = fixtureError(it))
                    return@launch
                }
                made += event.id
            }
            _state.value = _state.value.copy(
                isSaving = false,
                sessionsMade = made.size,
                createdEventId = made.first(),
            )
        }
    }

    private companion object {
        const val SEARCH_PAUSE_MS = 300L
        val MATCH_LENGTH: Duration = Duration.ofHours(5)
    }
}

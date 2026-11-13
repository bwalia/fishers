package com.fishers.app.match.start

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.clubs.Club
import com.fishers.app.clubs.Team
import com.fishers.app.cricket.BallStore
import com.fishers.app.cricket.StoredBook
import com.fishers.app.i18n.t
import com.fishers.app.net.MatchStartApi
import com.fishers.app.net.PublicUser
import com.fishers.app.session.readableError
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.IOException
import java.time.Duration
import java.time.Instant
import java.util.UUID

/**
 * The server asked for a confirmed email or phone before it would make a club.
 *
 * Shown in place, with the server's own words and the code box, so a player who
 * registered a minute ago confirms and carries on rather than being sent off to
 * find a settings page.
 */
data class Verification(
    /** `email` or `phone`; null when the account has neither to confirm. */
    val channel: String?,
    /** Which call was refused, for whoever reads the bug report. */
    val refusedBy: String,
    /** What the server said. */
    val message: String,
    /** Masked address the code went to, once it has been sent. */
    val sentTo: String? = null,
    val code: String = "",
    val isBusy: Boolean = false,
    val error: String? = null,
)

data class StartMatchState(
    val isLoading: Boolean = true,
    /** The clubs list could not be read — so whether they have one is unknown. */
    val loadError: String? = null,
    /** Clubs where this person may put a fixture in (`manage_events`), as iOS decides. */
    val clubs: List<Club> = emptyList(),
    val clubId: String? = null,
    val teams: List<Team> = emptyList(),
    val teamId: String? = null,
    /** With no club to play for: the one thing asked, and the club made from it. */
    val newTeamName: String = "",
    val awayName: String = "",
    val opponent: ClubIdentity? = null,
    val kind: MatchKind = MatchKind.Friendly,
    val isStarting: Boolean = false,
    val error: String? = null,
    val verification: Verification? = null,
    /** Set once the fixture is made: the screen moves on to the setup. */
    val startedEventId: String? = null,
    /** No signal: the clubs are as this phone last saw them, and the match starts on the phone. */
    val offline: Boolean = false,
) {
    /** Nowhere to put a fixture: ask for a team name and make the club. */
    val needsATeam: Boolean get() = !isLoading && loadError == null && clubs.isEmpty()

    val club: Club? get() = clubs.firstOrNull { it.id == clubId }

    /** "Lords CC 2nd XI", or the club alone, or the name just typed. */
    val homeName: String
        get() {
            if (needsATeam) return newTeamName.trim()
            val club = club ?: return ""
            val team = teams.firstOrNull { it.id == teamId } ?: return club.name
            return "${club.name} ${team.name}"
        }

    /** What is still needed before the button works, in the words iOS uses. */
    val missing: String?
        get() = when {
            isLoading -> null
            needsATeam && newTeamName.trim().length < 2 -> t("ms.missing_team_name")
            !needsATeam && club == null -> t("ev.missing_which_club")
            awayName.isBlank() -> t("ev.missing_who")
            opponent != null && opponent.clubId == clubId -> t("sc.opposition_not_own_club")
            else -> null
        }
}

/**
 * A match arranged in the car park: who is playing whom, then straight on to the
 * setup. `QuickMatchSheet` in `ScoreHubView.swift`.
 *
 * Somebody with no club where they can make a fixture — a player who registered
 * a minute ago, say — is asked for their team's name and nothing else. The club
 * is made for them (informal, invite-only), then the fixture, in one go.
 *
 * With no signal, as on iOS, the match starts on the phone: the clubs are the
 * ones saved the last time there was signal ([OfflineCache]), the fixture's id
 * is minted here, and what the server must make — the club for a team with
 * none, the fixture — is written into the match's book ([PendingCreate]) for
 * [MatchRegistrar] to make when the signal comes back. A start that loses the
 * signal half way carries on the same way, from wherever it got to.
 */
class StartMatchViewModel(
    private val api: MatchStartApi,
    /** Clubs, teams and players saved for a day with no signal. */
    private val cache: OfflineCache,
    /** Where a match started with no signal is kept. */
    private val store: BallStore,
    /** This install, which holds the book of a match started here. */
    private val deviceId: String,
    private val myUserId: String? = null,
    /** Club to start from, when the screen was opened from one. */
    private val preferredClubId: String? = null,
    /** Which contact a code can confirm: `email`, `phone`, or none. */
    private val verifyChannel: String? = null,
    /** Hand the confirmed account back to the app. */
    private val onVerified: (PublicUser) -> Unit = {},
    private val now: () -> Instant = Instant::now,
    private val newId: () -> String = { UUID.randomUUID().toString() },
) : ViewModel() {

    private val _state = MutableStateFlow(StartMatchState())
    val state: StateFlow<StartMatchState> = _state.asStateFlow()

    /** The club made for a team with none, kept so a retry does not make a second. */
    private var madeClub: Club? = null

    /** Every club this person was in when the list was read — to know a club a lost answer made. */
    private var clubsBefore: List<String>? = null

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, loadError = null)
            runCatching { api.myClubs() }
                .onSuccess { all ->
                    clubsBefore = all.map { it.id }
                    val startable = startableOf(api, all)
                    cache.saveStartableClubs(startable)
                    val pick = startable.firstOrNull { it.id == preferredClubId } ?: startable.firstOrNull()
                    _state.value = _state.value.copy(
                        isLoading = false,
                        clubs = startable,
                        clubId = pick?.id,
                        offline = false,
                    )
                    pick?.let { loadTeams(it.id) }
                    // The players too, while there is signal: a team sheet at a
                    // ground with none is picked from what is saved now.
                    viewModelScope.launch { cache.warm(api, startable) }
                }
                .onFailure { failure ->
                    val saved = if (failure is IOException) cache.startableClubs() else null
                    _state.value = when {
                        saved != null -> {
                            val pick = saved.firstOrNull { it.id == preferredClubId } ?: saved.firstOrNull()
                            _state.value.copy(
                                isLoading = false,
                                clubs = saved,
                                clubId = pick?.id,
                                teams = pick?.let { cache.teams(it.id) }.orEmpty(),
                                offline = true,
                            )
                        }
                        // Whether they have a club is not known here, and a guess
                        // would make a second club for somebody who has one.
                        failure is IOException -> _state.value.copy(isLoading = false, loadError = t("ms.clubs_not_on_this_phone"))
                        else -> _state.value.copy(isLoading = false, loadError = readableError(failure))
                    }
                }
        }
    }

    fun selectClub(id: String) {
        if (id == _state.value.clubId) return
        _state.value = _state.value.copy(clubId = id, teamId = null, teams = emptyList())
        loadTeams(id)
    }

    fun selectTeam(id: String?) {
        _state.value = _state.value.copy(teamId = id)
    }

    fun setNewTeamName(name: String) {
        _state.value = _state.value.copy(newTeamName = name, error = null)
    }

    fun setKind(kind: MatchKind) {
        _state.value = _state.value.copy(kind = kind)
    }

    /** From the opposition picker: a name, and the club when they are on the platform. */
    fun setOpposition(name: String, identity: ClubIdentity?) {
        _state.value = _state.value.copy(awayName = name.trim(), opponent = identity, error = null)
    }

    /**
     * Club (made first, when there is none), then the fixture. With no signal —
     * from the start, or lost on the way — the rest is made on the phone.
     */
    fun start() {
        val s = _state.value
        if (s.isStarting || s.missing != null) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isStarting = true, error = null)
            // The phone's own id for the fixture: the book's name until the
            // server gives it one, and how a fixture whose answer was lost is
            // found again rather than made twice.
            val ref = newId()
            val at = now()
            if (s.offline) {
                startOffline(s, ref, at, clubId = if (s.needsATeam) madeClub?.id else s.clubId)
                return@launch
            }
            val clubId = if (s.needsATeam) {
                when (val made = makeClub(s.newTeamName.trim())) {
                    is MadeClub.Made -> made.id
                    MadeClub.NoSignal -> {
                        // It may have been made, answer lost: the sync looks
                        // for it before asking again.
                        startOffline(s, ref, at, clubId = null, clubAsked = true)
                        return@launch
                    }
                    MadeClub.Refused -> {
                        _state.value = _state.value.copy(isStarting = false)
                        return@launch
                    }
                }
            } else {
                checkNotNull(s.clubId)
            }
            runCatching { api.createEvent(fixture(s, clubId, ref, at)) }
                .onSuccess { _state.value = _state.value.copy(isStarting = false, startedEventId = it.id) }
                .onFailure {
                    if (it is IOException) {
                        startOffline(s, ref, at, clubId = clubId, fixtureAsked = true)
                    } else {
                        _state.value = _state.value.copy(isStarting = false, error = apiWords(it))
                    }
                }
        }
    }

    /** `CreateEventBody`, as `QuickMatchSheet.start()` fills it — and the phone's id for it in the metadata. */
    private fun fixture(s: StartMatchState, clubId: String, ref: String, at: Instant): NewFixture {
        val away = s.awayName.trim()
        val home = s.homeName
        return NewFixture(
            clubId = clubId,
            opponentClubId = s.opponent?.clubId,
            teamId = if (s.needsATeam) null else s.teamId,
            sport = "cricket",
            eventSubtype = s.kind.wire,
            title = "$home v $away",
            startAt = at.toString(),
            endAt = at.plus(Duration.ofHours(4)).toString(),
            capacity = 22,
            metadata = mapOf("opposition" to away, "home_name" to home, FixtureInfo.CLIENT_REF to ref),
        )
    }

    /**
     * The match started on the phone: its book, under the phone's id for the
     * fixture, saying what the server still has to make. The setup runs on
     * that book, and [MatchRegistrar] makes the rest when there is signal.
     */
    private fun startOffline(
        s: StartMatchState,
        ref: String,
        at: Instant,
        clubId: String?,
        clubAsked: Boolean = false,
        fixtureAsked: Boolean = false,
    ) {
        val matchId = newId()
        val book = StoredBook(
            eventId = ref,
            matchId = matchId,
            match = matchOnThePhone(
                matchId = matchId,
                eventId = ref,
                homeName = s.homeName,
                awayName = s.awayName.trim(),
                oversLimit = 20,
                clubId = clubId,
                opponentClubId = s.opponent?.clubId,
                deviceId = deviceId,
                userId = myUserId,
            ),
            create = PendingCreate(
                club = if (clubId == null) newClub(s.newTeamName.trim()) else null,
                clubId = clubId,
                clubsBefore = clubsBefore,
                clubAsked = clubAsked,
                fixture = fixture(s, clubId.orEmpty(), ref, at),
                fixtureAsked = fixtureAsked,
            ),
        )
        runCatching { store.update(ref) { book } }
            .onSuccess {
                _state.value = _state.value.copy(isStarting = false, offline = true, startedEventId = ref)
            }
            .onFailure {
                _state.value = _state.value.copy(isStarting = false, error = t("ms.could_not_save_match"))
            }
    }

    /** The screen has moved on; do not move it again on the way back. */
    fun started() {
        _state.value = _state.value.copy(startedEventId = null)
    }

    // MARK: Confirming the account, when making the club needs it

    fun setCode(code: String) {
        val v = _state.value.verification ?: return
        _state.value = _state.value.copy(verification = v.copy(code = code.filter(Char::isDigit).take(6), error = null))
    }

    fun sendCode() {
        val v = _state.value.verification ?: return
        val channel = v.channel ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(verification = v.copy(isBusy = true, error = null))
            runCatching { api.sendCode(channel) }
                .onSuccess { reply ->
                    val sentTo = runCatching { reply.jsonObject["sent_to"]?.jsonPrimitive?.content }.getOrNull()
                    _state.value = _state.value.copy(
                        verification = _state.value.verification?.copy(isBusy = false, sentTo = sentTo ?: ""),
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        verification = _state.value.verification?.copy(isBusy = false, error = apiWords(it)),
                    )
                }
        }
    }

    /** Confirm the code, then carry straight on with the match. */
    fun confirmCode() {
        val v = _state.value.verification ?: return
        val channel = v.channel ?: return
        if (v.code.length != 6) return
        viewModelScope.launch {
            _state.value = _state.value.copy(verification = v.copy(isBusy = true, error = null))
            runCatching { api.confirmCode(channel, ConfirmCode(v.code)) }
                .onSuccess { user ->
                    onVerified(user)
                    _state.value = _state.value.copy(verification = null)
                    start()
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        verification = _state.value.verification?.copy(isBusy = false, error = apiWords(it)),
                    )
                }
        }
    }

    private fun loadTeams(clubId: String) {
        viewModelScope.launch {
            val teams = runCatching { api.clubTeams(clubId) }
                .onSuccess { cache.saveTeams(clubId, it) }
                .getOrElse { cache.teams(clubId) }
            if (_state.value.clubId == clubId) _state.value = _state.value.copy(teams = teams)
        }
    }

    private sealed interface MadeClub {
        data class Made(val id: String) : MadeClub
        /** Refused; the state says why. */
        data object Refused : MadeClub
        data object NoSignal : MadeClub
    }

    /** Informal and invite-only: a side that turned up, not a club with a committee. */
    private fun newClub(name: String) = NewClub(
        name = name,
        sportTypes = listOf("cricket"),
        isInformalGroup = true,
        visibility = "invite_only",
    )

    /** The club for a team that has none. */
    private suspend fun makeClub(name: String): MadeClub {
        madeClub?.let { return MadeClub.Made(it.id) }
        return runCatching { api.createClub(newClub(name)) }.fold(
            onSuccess = { club ->
                madeClub = club
                MadeClub.Made(club.id)
            },
            onFailure = { error ->
                val refusal = refusalOf(error)
                when {
                    error is IOException -> return MadeClub.NoSignal
                    refusal?.code == "unverified" -> _state.value = _state.value.copy(
                        verification = Verification(
                            channel = verifyChannel,
                            refusedBy = "POST /clubs",
                            message = refusal.message,
                        ),
                    )
                    else -> _state.value = _state.value.copy(error = refusal?.message ?: readableError(error))
                }
                MadeClub.Refused
            },
        )
    }
}

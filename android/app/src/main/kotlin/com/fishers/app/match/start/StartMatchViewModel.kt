package com.fishers.app.match.start

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.clubs.Club
import com.fishers.app.clubs.Team
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
import java.time.Duration
import java.time.Instant

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
 * Online only. iOS also mints the fixture on the phone with no signal and posts
 * it later; that waits for an offline store on Android.
 *
 * Somebody with no club where they can make a fixture — a player who registered
 * a minute ago, say — is asked for their team's name and nothing else. The club
 * is made for them (informal, invite-only), then the fixture, in one go.
 */
class StartMatchViewModel(
    private val api: MatchStartApi,
    /** Club to start from, when the screen was opened from one. */
    private val preferredClubId: String? = null,
    /** Which contact a code can confirm: `email`, `phone`, or none. */
    private val verifyChannel: String? = null,
    /** Hand the confirmed account back to the app. */
    private val onVerified: (PublicUser) -> Unit = {},
    private val now: () -> Instant = Instant::now,
) : ViewModel() {

    private val _state = MutableStateFlow(StartMatchState())
    val state: StateFlow<StartMatchState> = _state.asStateFlow()

    /** The club made for a team with none, kept so a retry does not make a second. */
    private var madeClub: Club? = null

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, loadError = null)
            runCatching { api.myClubs() }
                .onSuccess { all ->
                    val startable = all.filter { club ->
                        runCatching { api.myClubRole(club.id) }.getOrNull()
                            ?.permissions?.contains("manage_events") == true
                    }
                    val pick = startable.firstOrNull { it.id == preferredClubId } ?: startable.firstOrNull()
                    _state.value = _state.value.copy(
                        isLoading = false,
                        clubs = startable,
                        clubId = pick?.id,
                    )
                    pick?.let { loadTeams(it.id) }
                }
                .onFailure {
                    _state.value = _state.value.copy(isLoading = false, loadError = readableError(it))
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

    /** Club (made first, when there is none), then the fixture. */
    fun start() {
        val s = _state.value
        if (s.isStarting || s.missing != null) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isStarting = true, error = null)
            val clubId = if (s.needsATeam) makeClub(s.newTeamName.trim()) else s.clubId
            if (clubId == null) {
                _state.value = _state.value.copy(isStarting = false)
                return@launch
            }
            val away = s.awayName.trim()
            val home = s.homeName
            val at = now()
            val body = NewFixture(
                clubId = clubId,
                opponentClubId = s.opponent?.clubId,
                teamId = if (s.needsATeam) null else s.teamId,
                sport = "cricket",
                eventSubtype = s.kind.wire,
                title = "$home v $away",
                startAt = at.toString(),
                endAt = at.plus(Duration.ofHours(4)).toString(),
                capacity = 22,
                metadata = mapOf("opposition" to away, "home_name" to home),
            )
            runCatching { api.createEvent(body) }
                .onSuccess { _state.value = _state.value.copy(isStarting = false, startedEventId = it.id) }
                .onFailure { _state.value = _state.value.copy(isStarting = false, error = apiWords(it)) }
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
            val teams = runCatching { api.clubTeams(clubId) }.getOrDefault(emptyList())
            if (_state.value.clubId == clubId) _state.value = _state.value.copy(teams = teams)
        }
    }

    /** The club for a team that has none. Null when it could not be made; the state says why. */
    private suspend fun makeClub(name: String): String? {
        madeClub?.let { return it.id }
        return runCatching {
            api.createClub(
                NewClub(
                    name = name,
                    sportTypes = listOf("cricket"),
                    isInformalGroup = true,
                    visibility = "invite_only",
                ),
            )
        }.fold(
            onSuccess = { club ->
                madeClub = club
                club.id
            },
            onFailure = { error ->
                val refusal = refusalOf(error)
                if (refusal?.code == "unverified") {
                    _state.value = _state.value.copy(
                        verification = Verification(
                            channel = verifyChannel,
                            refusedBy = "POST /clubs",
                            message = refusal.message,
                        ),
                    )
                } else {
                    _state.value = _state.value.copy(error = refusal?.message ?: readableError(error))
                }
                null
            },
        )
    }
}

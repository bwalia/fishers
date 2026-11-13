package com.fishers.app.clubs

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.i18n.t
import com.fishers.app.net.ClubsApi
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant

/** A new club's next steps, ticked off from what exists — never from what was tapped. */
data class SetupStep(val kind: Kind, val done: Boolean) {
    enum class Kind { Players, Team, Captain, Ground }

    val title: String
        get() = when (kind) {
            Kind.Players -> t("ld.add_your_players")
            Kind.Team -> t("ld.add_a_team")
            Kind.Captain -> t("ld.name_a_captain")
            Kind.Ground -> t("ld.add_your_ground")
        }

    val detail: String
        get() = when (kind) {
            Kind.Players -> t("ld.by_email_or_mobile_number_or_from_a_pr")
            Kind.Team -> t("cl.each_keeps_its_own_squad")
            Kind.Captain -> t("ld.captains_pick_the_side_and_run_the_sco")
            Kind.Ground -> t("ld.so_every_fixture_says_where_to_turn_up")
        }
}

/** One club's page — `ClubDetailView` in `ClubsTeamsView.swift`. */
data class ClubPageState(
    /** Null until it loads; the route already knows the name. */
    val club: Club? = null,
    /** What this person may do here. Null reads as a plain member: nothing extra shown. */
    val role: ClubRoleInfo? = null,
    /** On the books only. */
    val members: List<ClubMemberDetail> = emptyList(),
    val teams: List<Team> = emptyList(),
    val venues: List<Venue> = emptyList(),
    /** From yesterday on, earliest first. */
    val fixtures: List<ClubFixture> = emptyList(),
    val isLoading: Boolean = false,
    val isFirstLoad: Boolean = true,
    val error: String? = null,
    /** A team or ground on its way to the server. */
    val isSaving: Boolean = false,
    val formError: String? = null,
    /** Bumped each time a team or ground is added, so the form that asked can close. */
    val saved: Int = 0,
) {
    val isSecretary: Boolean get() = role?.isSecretary == true
    val runsClubOps: Boolean get() = role?.runsClubOps == true
    val managesEvents: Boolean get() = role?.managesEvents == true

    /** What the club is for: a match, as soon as there is anyone to play. Cricket only — it is cricket's scorer. */
    val canStartMatch: Boolean
        get() = club?.playsCricket != false && (role?.isSecretary == true || role?.scores == true)

    /** Teams are made in one of the club's sports. */
    val sports: List<String> get() = club?.sportTypes?.takeIf { it.isNotEmpty() } ?: listOf("cricket")

    val setup: List<SetupStep>
        get() = listOf(
            SetupStep(SetupStep.Kind.Players, done = members.size > 1),
            SetupStep(SetupStep.Kind.Team, done = teams.isNotEmpty()),
            SetupStep(SetupStep.Kind.Captain, done = members.any { it.role == UserRole.TeamCaptain || it.isCaptain }),
            SetupStep(SetupStep.Kind.Ground, done = venues.isNotEmpty()),
        )

    /** Shown to a secretary until there is nothing left on it. */
    val setupLeft: Boolean get() = isSecretary && setup.any { !it.done }
}

class ClubPageViewModel(
    private val api: ClubsApi,
    private val clubId: String,
    private val now: () -> Instant = Instant::now,
) : ViewModel() {

    private val _state = MutableStateFlow(ClubPageState())
    val state: StateFlow<ClubPageState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            runCatching {
                coroutineScope {
                    // The club is the one that must answer: refused, and this
                    // person is not in it, which the page has to say. The rest
                    // are what the page is made of, and one failing leaves its
                    // section empty rather than taking the page down.
                    val club = async { api.club(clubId) }
                    val role = async { runCatching { api.myRole(clubId) }.getOrNull() }
                    val members = async { runCatching { api.members(clubId) }.getOrDefault(emptyList()) }
                    val teams = async { runCatching { api.teams(clubId) }.getOrDefault(emptyList()) }
                    val venues = async { runCatching { api.venues(clubId) }.getOrDefault(emptyList()) }
                    val fixtures = async {
                        // From yesterday: a match that started this morning is
                        // still the one people open the club to find.
                        val from = now().minus(Duration.ofDays(1)).toString()
                        runCatching { api.clubFixtures(clubId, from = from).items }.getOrDefault(emptyList())
                    }
                    ClubPageState(
                        club = club.await(),
                        role = role.await(),
                        members = members.await().filter { it.isOnTheBooks },
                        teams = teams.await().sortedBy { it.name.lowercase() },
                        venues = venues.await(),
                        fixtures = fixtures.await().sortedBy { it.startAt },
                        isFirstLoad = false,
                        saved = _state.value.saved,
                    )
                }
            }
                .onSuccess { loaded -> _state.value = loaded }
                .onFailure { e ->
                    _state.update { it.copy(isLoading = false, isFirstLoad = false, error = saidWhy(e)) }
                }
        }
    }

    /** A 1st XI, a Sunday side. Needs `manage_club_ops`. */
    fun addTeam(name: String, sport: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty() || _state.value.isSaving) return
        save { api.createTeam(clubId, CreateTeamBody(trimmed, sport)) }
    }

    /** Where the club plays, so a fixture can say where to turn up. */
    fun addGround(name: String, address: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty() || _state.value.isSaving) return
        save { api.createVenue(clubId, CreateVenueBody(trimmed, address.trim().ifEmpty { null })) }
    }

    /** The form is closing without saving: its error goes with it. */
    fun clearFormError() = _state.update { it.copy(formError = null) }

    private fun save(call: suspend () -> Unit) {
        _state.update { it.copy(isSaving = true, formError = null) }
        viewModelScope.launch {
            runCatching { call() }
                .onSuccess {
                    _state.update { it.copy(isSaving = false, saved = it.saved + 1) }
                    load()
                }
                .onFailure { e -> _state.update { it.copy(isSaving = false, formError = saidWhy(e)) } }
        }
    }
}

/** One team, and who is in it — `TeamRosterView`. */
data class TeamRosterState(
    val members: List<TeamMemberRow>? = null,
    val failed: Boolean = false,
)

class TeamRosterViewModel(private val api: ClubsApi, private val teamId: String) : ViewModel() {
    private val _state = MutableStateFlow(TeamRosterState())
    val state: StateFlow<TeamRosterState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            runCatching { api.teamMembers(teamId) }
                .onSuccess { _state.value = TeamRosterState(members = it) }
                .onFailure { _state.value = TeamRosterState(failed = true) }
        }
    }
}

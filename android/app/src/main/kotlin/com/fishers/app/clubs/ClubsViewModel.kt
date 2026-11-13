package com.fishers.app.clubs

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.net.FishersApi
import com.fishers.app.session.readableError
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.decodeFromJsonElement

data class ClubsState(
    val clubs: List<Club> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val isFirstLoad: Boolean = true,
    /** What the search box holds. Filtered here: the list is every club already. */
    val query: String = "",
) {
    /** The clubs whose name or description has the search in it. */
    val shown: List<Club>
        get() {
            val q = query.trim()
            if (q.isEmpty()) return clubs
            return clubs.filter {
                it.name.contains(q, ignoreCase = true) ||
                    it.description?.contains(q, ignoreCase = true) == true
            }
        }

    /** Worth a search box: a list that fits on a screen does not need one. */
    val isSearchable: Boolean get() = clubs.size > SEARCH_FROM

    private companion object {
        const val SEARCH_FROM = 6
    }
}

class ClubsViewModel(private val api: FishersApi) : ViewModel() {

    private val _state = MutableStateFlow(ClubsState())
    val state: StateFlow<ClubsState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            runCatching { api.myClubs() }
                .onSuccess {
                    _state.value = ClubsState(
                        clubs = it.sortedBy { c -> c.name.lowercase() },
                        isFirstLoad = false,
                        query = _state.value.query,
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        isLoading = false, isFirstLoad = false, error = readableError(it),
                    )
                }
        }
    }

    fun search(query: String) {
        _state.value = _state.value.copy(query = query)
    }
}

data class ClubDetailState(
    val members: List<ClubMemberDetail> = emptyList(),
    val teams: List<Team> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val isFirstLoad: Boolean = true,
    /** A secretary's: the open link card shows only for them. */
    val canShareLink: Boolean = false,
    val joinLink: ClubJoinLink? = null,
    /** `<site>/invite/<token>` — what goes in the team WhatsApp group. */
    val joinLinkUrl: String? = null,
) {
    /** Only people actually on the books. Somebody who was asked and never
     *  answered is not in the side, and counting them is how a Saturday goes
     *  wrong. */
    val onTheBooks: List<ClubMemberDetail> get() = members.filter { it.isOnTheBooks }
    val invited: List<ClubMemberDetail>
        get() = members.filter { it.status == MembershipStatus.Invited }

    /** Who has left or been suspended: on the record, not in the side. */
    val former: List<ClubMemberDetail>
        get() = members.filter { it.status == MembershipStatus.Left || it.status == MembershipStatus.Suspended }

    /**
     * The people on the books, a heading per role — secretaries, captains,
     * vice captains, members, guests — as the secretary's screen lists them.
     * Roles nobody holds are left out rather than shown empty.
     */
    val byRole: List<Pair<UserRole, List<ClubMemberDetail>>>
        get() = UserRole.rosterOrder.mapNotNull { role ->
            onTheBooks.filter { it.role == role }.takeIf { it.isNotEmpty() }?.let { role to it }
        }
}

/**
 * A club's roster and its open link — the Members tab of Manage club. The
 * secretary's changes to the roster go through [ClubAdminViewModel], which
 * has this re-read once they land.
 */
class ClubDetailViewModel(
    private val api: FishersApi,
    private val clubId: String,
    /** The brand's site, which is where an invite link opens. */
    private val webBase: String,
) : ViewModel() {

    private val _state = MutableStateFlow(ClubDetailState())
    val state: StateFlow<ClubDetailState> = _state.asStateFlow()

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            runCatching { api.clubMembers(clubId) }
                .onSuccess { members ->
                    // Teams are a nicety; the roster is the reason somebody
                    // opened this. Failing to fetch them must not empty it.
                    val teams = runCatching { api.clubTeams(clubId) }.getOrDefault(emptyList())
                    // So is the club link, and only a secretary may see it.
                    val canShare = runCatching { api.myClubRole(clubId) }.getOrNull()
                        ?.permissions?.contains("invite_to_club") == true
                    val link = if (canShare) {
                        runCatching { api.clubJoinLink(clubId) }.getOrNull()
                            ?.takeIf { it !is JsonNull }
                            ?.let { json.decodeFromJsonElement<ClubJoinLink>(it) }
                    } else {
                        null
                    }
                    _state.value = ClubDetailState(
                        canShareLink = canShare,
                        joinLink = link,
                        joinLinkUrl = link?.let(::urlOf),
                        // Whoever runs the club first, then captains, then
                        // everyone alphabetically — the order somebody scans
                        // when they are looking for who to ask.
                        members = members.sortedWith(
                            compareByDescending<ClubMemberDetail> { it.role.runsTheClub }
                                .thenByDescending { it.isCaptain }
                                .thenBy { it.name.lowercase() },
                        ),
                        teams = teams,
                        isFirstLoad = false,
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        isLoading = false, isFirstLoad = false, error = readableError(it),
                    )
                }
        }
    }

    /** Switch the club link on; `fresh` turns the old one off for a new one. */
    fun makeJoinLink(fresh: Boolean) {
        viewModelScope.launch {
            runCatching { api.makeClubJoinLink(clubId, MakeJoinLink(fresh)) }
                .onSuccess { _state.value = _state.value.copy(joinLink = it, joinLinkUrl = urlOf(it), error = null) }
                .onFailure { _state.value = _state.value.copy(error = readableError(it)) }
        }
    }

    /** Nobody new joins through it; whoever already did stays in. */
    fun stopJoinLink() {
        viewModelScope.launch {
            runCatching { api.stopClubJoinLink(clubId) }
                .onSuccess { _state.value = _state.value.copy(joinLink = null, joinLinkUrl = null, error = null) }
                .onFailure { _state.value = _state.value.copy(error = readableError(it)) }
        }
    }

    private fun urlOf(link: ClubJoinLink) = "${webBase.trimEnd('/')}/invite/${link.token}"

    private companion object {
        val json = Json { ignoreUnknownKeys = true }
    }
}

package com.fishers.app.clubs

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.net.FishersApi
import com.fishers.app.session.readableError
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ClubsState(
    val clubs: List<Club> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val isFirstLoad: Boolean = true,
)

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
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        isLoading = false, isFirstLoad = false, error = readableError(it),
                    )
                }
        }
    }
}

data class ClubDetailState(
    val members: List<ClubMemberDetail> = emptyList(),
    val teams: List<Team> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val isFirstLoad: Boolean = true,
) {
    /** Only people actually on the books. Somebody who was asked and never
     *  answered is not in the side, and counting them is how a Saturday goes
     *  wrong. */
    val onTheBooks: List<ClubMemberDetail> get() = members.filter { it.isOnTheBooks }
    val invited: List<ClubMemberDetail>
        get() = members.filter { it.status == MembershipStatus.Invited }
}

class ClubDetailViewModel(
    private val api: FishersApi,
    private val clubId: String,
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
                    _state.value = ClubDetailState(
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
}

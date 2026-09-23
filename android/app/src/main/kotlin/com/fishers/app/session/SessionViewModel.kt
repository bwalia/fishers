package com.fishers.app.session

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.net.FishersApi
import com.fishers.app.net.LoginRequest
import com.fishers.app.net.PublicUser
import com.fishers.app.net.RoleIntentPatch
import com.fishers.app.net.Session
import com.fishers.app.net.SignupRequest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What they said they came to do. Asked on sign-up, changeable later. */
enum class RoleIntent(val wire: String, val title: String) {
    Secretary("secretary", "I run a club"),
    Player("player", "I play for a club"),
}

data class SessionState(
    val user: PublicUser? = null,
    val isAuthenticated: Boolean = false,
    val isLoading: Boolean = false,
    val error: String? = null,
    /** True until the first bootstrap finishes, so the app does not flash the
     *  sign-in form at somebody who is already signed in. */
    val isStarting: Boolean = true,
)

/**
 * `SessionStore.swift`'s opposite number.
 *
 * The tokens live in [Session]; this is what the screens watch.
 */
class SessionViewModel(
    private val api: FishersApi,
    private val session: Session,
) : ViewModel() {

    private val _state = MutableStateFlow(SessionState())
    val state: StateFlow<SessionState> = _state.asStateFlow()

    /**
     * Pick up where the last launch left off.
     *
     * A stored token is not proof of a session — it may have been revoked, or
     * the account deleted — so it is spent on a real call before the app acts
     * as though somebody is signed in. Failing that, the tokens are cleared
     * rather than left to fail every screen in turn.
     */
    fun bootstrap() {
        if (!session.isSignedIn) {
            _state.value = _state.value.copy(isStarting = false)
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true)
            runCatching { api.me() }
                .onSuccess {
                    _state.value = SessionState(user = it, isAuthenticated = true, isStarting = false)
                }
                .onFailure {
                    session.clear()
                    _state.value = SessionState(isStarting = false)
                }
        }
    }

    fun signIn(identifier: String, password: String) = authenticate(
        call = { api.login(LoginRequest(identifier.trim(), password)) },
    )

    /**
     * `role` is asked on the form, before there is an account to save it on,
     * so it goes up straight after. Failing to save it is not worth failing
     * the sign-up for — it can be asked again.
     */
    fun signUp(name: String, identifier: String, password: String, role: RoleIntent?) =
        authenticate(
            call = {
                val id = identifier.trim()
                api.signup(
                    SignupRequest(
                        name = name.trim(),
                        email = id.takeIf { it.contains("@") },
                        phone = id.takeUnless { it.contains("@") },
                        password = password,
                    )
                )
            },
            then = {
                if (role != null) {
                    runCatching { api.setRoleIntent(RoleIntentPatch(role.wire)) }
                        .onSuccess { user -> _state.value = _state.value.copy(user = user) }
                }
            },
        )

    fun signOut() {
        session.clear()
        _state.value = SessionState(isStarting = false)
    }

    fun dismissError() {
        _state.value = _state.value.copy(error = null)
    }

    private fun authenticate(
        call: suspend () -> com.fishers.app.net.AuthTokens,
        then: suspend () -> Unit = {},
    ) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            runCatching { call() }
                .onSuccess { tokens ->
                    session.set(tokens.asTokens())
                    _state.value = SessionState(
                        user = tokens.user,
                        isAuthenticated = true,
                        isStarting = false,
                    )
                    then()
                }
                .onFailure {
                    _state.value = _state.value.copy(isLoading = false, error = readableError(it))
                }
        }
    }
}

/**
 * What to put in front of somebody.
 *
 * A stack trace is not an answer. The two that matter are told apart because
 * they need different things from the reader: wrong details, or no signal.
 */
internal fun readableError(t: Throwable): String = when {
    t is retrofit2.HttpException && t.code() == 401 ->
        "That email or password was not right."
    t is retrofit2.HttpException && t.code() == 429 ->
        "Too many tries. Give it a minute."
    t is retrofit2.HttpException && t.code() in 500..599 ->
        "The server is having trouble. Try again shortly."
    t is java.io.IOException ->
        "No connection. Check the signal and try again."
    else -> t.message ?: "Something went wrong."
}

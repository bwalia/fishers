package com.fishers.app.views

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.session.SessionViewModel
import com.fishers.app.views.auth.AuthScreen

/**
 * Not signed in → the form; signed in → the tabs — `RootView.swift`.
 *
 * The third branch iOS has, the quick start, is not ported yet: it asks for a
 * sport and a squad number and both are skippable, so leaving it out costs
 * nothing but a screen.
 *
 * The starting state matters. A stored token is spent on a real call before the
 * app believes in it, and until that answers neither branch is right — showing
 * the sign-in form to somebody who is signed in is the worse of the two, so
 * neither is shown.
 */
@Composable
fun RootScreen(viewModel: SessionViewModel, modifier: Modifier = Modifier) {
    val state by viewModel.state.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) { viewModel.bootstrap() }

    AnimatedContent(
        targetState = when {
            state.isStarting -> Destination.Starting
            state.isAuthenticated -> Destination.SignedIn
            else -> Destination.Auth
        },
        transitionSpec = {
            fadeIn(tween(250)) togetherWith fadeOut(tween(250))
        },
        label = "root",
        modifier = modifier.fillMaxSize(),
    ) { destination ->
        when (destination) {
            Destination.Starting -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                CircularProgressIndicator()
            }

            Destination.Auth -> AuthScreen(
                state = state,
                onSignIn = viewModel::signIn,
                onSignUp = viewModel::signUp,
            )

            Destination.SignedIn -> MainTabScreen(
                user = state.user,
                onSignOut = viewModel::signOut,
            )
        }
    }
}

private enum class Destination { Starting, Auth, SignedIn }

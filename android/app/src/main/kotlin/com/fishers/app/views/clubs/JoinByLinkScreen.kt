package com.fishers.app.views.clubs

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.R
import com.fishers.app.clubs.JoinByLinkState
import com.fishers.app.clubs.JoinByLinkState.Stage
import com.fishers.app.clubs.JoinByLinkViewModel
import com.fishers.app.i18n.t
import com.fishers.app.net.ClubsApi
import com.fishers.app.views.fixtures.FixtureRoute
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator

/**
 * An invite link opened in the app — what it is to, who sent it, and Join.
 * Worded as the website's `/invite/[token]` page words it, refusals included.
 * Opened only once somebody is signed in (MainActivity waits for that).
 */
@Composable
internal fun JoinByLinkPage(token: String) {
    val nav = LocalNavigator.current
    val deps = LocalAppDeps.current
    val model = remember(token) { JoinByLinkViewModel(deps.service<ClubsApi>(), token) }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(token) { model.load() }
    // In: the link becomes the thing it was to. The user is re-read, because
    // what they are a member of has just changed.
    LaunchedEffect(state.joined) {
        val joined = state.joined ?: return@LaunchedEffect
        deps.reloadUser()
        when {
            joined.eventId != null -> nav.replace(FixtureRoute(joined.eventId))
            joined.clubId != null -> nav.replace(ClubRoute(joined.clubId, joined.clubName ?: ""))
            else -> nav.pop()
        }
    }

    ClubScreen(title = t("nav.join")) {
        JoinByLinkBody(state, onJoin = model::join, onRetry = model::load, onClose = nav::pop)
    }
}

@Composable
private fun JoinByLinkBody(state: JoinByLinkState, onJoin: () -> Unit, onRetry: () -> Unit, onClose: () -> Unit) {
    val brand = stringResource(R.string.brand_name)
    if (state.stage == Stage.Checking || state.stage == Stage.Joined) {
        Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
        return
    }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        val preview = state.preview
        if (state.stage == Stage.Failed) {
            Icon(Icons.Filled.LinkOff, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(32.dp))
            Text(t("rest.that_link_did_not_work"), style = MaterialTheme.typography.headlineSmall)
            state.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            // A preview that never came back may just be no signal.
            if (preview == null) {
                OutlinedButton(onClick = onRetry, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("rest.try_again")) }
            } else {
                Hint(state.advice)
            }
            OutlinedButton(onClick = onClose, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.close")) }
            return@Column
        }

        Text(
            preview?.joining?.let { t("jl.join_club", vars = mapOf("club" to it)) } ?: t("rest.you_have_been_invited"),
            style = MaterialTheme.typography.headlineSmall,
        )
        preview?.eventTitle?.let { Text(it, style = MaterialTheme.typography.titleMedium) }
        // An open link is from the club, not a person: naming whoever made it
        // would read as though they had picked you.
        if (preview?.open == false) {
            preview.invitedByName?.let { Hint(t("jl.invited_by", vars = mapOf("name" to it))) }
        }

        if (state.needsVerifying) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.VerifiedUser, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text(t("cl.confirm_its_you_first"), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(start = 8.dp))
            }
            state.error?.let { Text(it) }
            Hint(t("cl.confirm_on_the_website", vars = mapOf("brand" to brand)))
        } else {
            state.error?.let { ErrorLine(it) }
        }

        Button(
            onClick = onJoin,
            enabled = state.stage == Stage.Ready,
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
        ) {
            if (state.stage == Stage.Joining) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                Text(t("rest.joining"), modifier = Modifier.padding(start = 8.dp))
            } else {
                Text(t("nav.join"))
            }
        }
    }
}

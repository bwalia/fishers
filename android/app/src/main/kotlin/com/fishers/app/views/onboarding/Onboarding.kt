package com.fishers.app.views.onboarding

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.SportsCricket
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.i18n.t
import com.fishers.app.net.ProfileApi
import com.fishers.app.onboarding.Gate
import com.fishers.app.onboarding.PendingInvite
import com.fishers.app.onboarding.PendingInvitesViewModel
import com.fishers.app.onboarding.PrefsQuickStartMemory
import com.fishers.app.onboarding.QuickStartState
import com.fishers.app.onboarding.QuickStartViewModel
import com.fishers.app.session.RoleIntent
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Between signing in and the tabs: the quick start for somebody who has not
 * yet said what they play — `RootView.swift` and `QuickStartView.swift`.
 * Shows [content] once there is nothing to ask.
 *
 * Somebody past it on this phone goes straight through without a request;
 * anyone else is asked only if their profile has no sport on it.
 */
@Composable
fun SignedInGate(content: @Composable () -> Unit) {
    val deps = LocalAppDeps.current
    val userId = deps.user()?.id
    if (userId == null) {
        content()
        return
    }
    val context = LocalContext.current
    val model = remember(userId) {
        QuickStartViewModel(
            api = deps.service<ProfileApi>(),
            memory = PrefsQuickStartMemory(context),
            userId = userId,
            onUser = { deps.setUser(it.toPublicUser()) },
        )
    }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(model) { model.check() }

    when (state.gate) {
        Gate.Done -> content()
        Gate.Checking -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
        Gate.Ask -> QuickStartScreen(
            state = state,
            onRole = model::pickRole,
            onSport = model::toggleSport,
            onPhone = model::setPhone,
            onContinue = model::finish,
            onSkip = model::skip,
        )
    }
}

/**
 * What you play, and a number your captain can reach you on. Both can be
 * skipped: the first minute is for getting somebody into a club and a match,
 * not for filling in a form.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun QuickStartScreen(
    state: QuickStartState,
    onRole: (RoleIntent) -> Unit,
    onSport: (com.fishers.app.profile.Sport) -> Unit,
    onPhone: (String) -> Unit,
    onContinue: () -> Unit,
    onSkip: () -> Unit,
) {
    Column(Modifier.fillMaxSize().imePadding()) {
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 24.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    t("rest.hi_name", vars = mapOf("name" to state.firstName.ifBlank { t("pf.there") })),
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    t("rest.two_quick_things"),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (state.asksRole) {
                Question(t("rest.im_here_to")) {
                    RoleChooser(selection = state.role, compact = true, onPick = onRole)
                }
            }

            val main = state.sports.firstOrNull()
            Question(
                t("rest.what_do_you_play"),
                note = if (state.sports.size > 1 && main != null) {
                    t("rest.is_your_main_sport", vars = mapOf("sport" to main.label))
                } else {
                    null
                },
            ) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    state.offered.forEach { sport ->
                        FilterChip(
                            selected = sport in state.sports,
                            onClick = { onSport(sport) },
                            label = { Text(sport.label) },
                        )
                    }
                }
            }

            if (state.asksPhone) {
                Question(t("rest.your_mobile_number"), note = t("rest.so_your_captain_can_reach_you_on_match")) {
                    OutlinedTextField(
                        value = state.phone,
                        onValueChange = onPhone,
                        placeholder = { Text(t("cl.07700_900123")) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }

            state.error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium) }
        }

        HorizontalDivider()
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Button(
                onClick = onContinue,
                enabled = state.canContinue,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            ) {
                if (state.saving) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                } else {
                    Text(t("le.continue"))
                }
            }
            TextButton(onClick = onSkip, enabled = !state.saving, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(t("rest.skip_for_now"))
            }
        }
    }
}

@Composable
private fun Question(title: String, note: String? = null, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        content()
        note?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * "I run a club" or "I play for a club" — `RoleChooserView.swift`. Picks only;
 * whoever shows it decides when it is saved.
 */
@Composable
fun RoleChooser(selection: RoleIntent?, compact: Boolean = false, onPick: (RoleIntent) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        RoleIntent.entries.forEach { role ->
            val selected = selection == role
            Surface(
                shape = RoundedCornerShape(12.dp),
                border = BorderStroke(
                    if (selected) 2.dp else 1.dp,
                    if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .selectable(selected = selected, role = Role.RadioButton, onClick = { onPick(role) }),
            ) {
                Row(
                    Modifier.heightIn(min = 48.dp).padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        if (role == RoleIntent.Secretary) Icons.Filled.Groups else Icons.Filled.SportsCricket,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                    )
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(role.title, style = MaterialTheme.typography.titleSmall)
                        if (!compact) {
                            Text(
                                t(
                                    if (role == RoleIntent.Secretary) {
                                        "le.secretary_or_organiser_you_set_up_the"
                                    } else {
                                        "le.set_up_your_player_profile_send_it_to"
                                    },
                                ),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    Icon(
                        if (selected) Icons.Filled.CheckCircle else Icons.Outlined.RadioButtonUnchecked,
                        contentDescription = null,
                        tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
                    )
                }
            }
        }
    }
}

/**
 * Invitations waiting for this account, with Accept — `PendingInvitesSection.swift`.
 * Draws nothing when there are none.
 *
 * Asking to confirm a contact first is not a dead end: the refusal comes with
 * the way to do it, and the invite is still here afterwards.
 */
@Composable
fun PendingInvitesSection() {
    val deps = LocalAppDeps.current
    val nav = LocalNavigator.current
    val model = remember { PendingInvitesViewModel(deps.service<ProfileApi>(), onAccepted = deps.reloadUser) }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { model.load() }

    if (state.invites.isEmpty()) return

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    t("rest.waiting_for_you"),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.weight(1f),
                )
                Text("${state.invites.size}", style = MaterialTheme.typography.labelMedium)
            }
            state.invites.forEach { invite ->
                InviteRow(invite, busy = state.busy == invite.id, enabled = state.busy == null) { model.accept(invite) }
            }
            val error = state.error
            if (error != null) {
                Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                if (state.needsVerification) {
                    OutlinedButton(onClick = { nav.push(VerifyAccountRoute()) }) {
                        Text(t("rest.confirm_email_or_phone"))
                    }
                }
            } else {
                Text(
                    t(if (state.invites.size == 1) "cl.somebody_has_invited_you" else "cl.people_have_invited_you"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun InviteRow(invite: PendingInvite, busy: Boolean, enabled: Boolean, onAccept: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(invite.title, style = MaterialTheme.typography.titleSmall)
            Text(
                inviteSubtitle(invite),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.width(8.dp))
        Button(onClick = onAccept, enabled = enabled) {
            if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text(t("le.accept"))
        }
    }
}

/** "from Ravi · sent 12 Nov". */
private fun inviteSubtitle(invite: PendingInvite): String {
    val sent = runCatching {
        OffsetDateTime.parse(invite.createdAt).format(DateTimeFormatter.ofPattern("d MMM", Locale.getDefault()))
    }.getOrNull()
    return listOfNotNull(
        invite.invitedByName?.let { t("pf.invite_from", vars = mapOf("name" to it)) },
        sent?.let { t("pf.invite_sent", vars = mapOf("date" to it)) },
    ).joinToString(" · ")
}

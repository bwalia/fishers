package com.fishers.app.views.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.i18n.t
import com.fishers.app.net.ProfileApi
import com.fishers.app.onboarding.VerifyState
import com.fishers.app.onboarding.VerifyViewModel
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator
import com.fishers.app.views.nav.Route
import com.fishers.app.views.profile.RouteBar
import com.fishers.app.views.profile.SectionCard

/**
 * Confirming an email or a number, outside any other flow — `VerifyAccountScreen`
 * in `ProfileView.swift`. Reached from the profile's strength card and from
 * any refusal that says a confirmed contact is needed first.
 */
class VerifyAccountRoute : Route {
    @Composable
    override fun Content() {
        val deps = LocalAppDeps.current
        val nav = LocalNavigator.current
        val model = remember {
            VerifyViewModel(deps.service<ProfileApi>()) { me ->
                deps.setUser(me.toPublicUser())
                nav.pop()
            }
        }
        val state by model.state.collectAsStateWithLifecycle()
        LaunchedEffect(Unit) { model.load() }

        Column(Modifier.fillMaxSize().imePadding()) {
            RouteBar(t("rest.confirm_its_you"), onBack = nav::pop)
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                val status = state.status
                SectionCard(title = null, footer = t("rest.starting_club_needs_confirmed")) {
                    when {
                        status != null && status.canVerify -> VerifyContactView(
                            state = state,
                            onChannel = model::selectChannel,
                            onCode = model::typeCode,
                            onConfirm = model::confirm,
                            onSend = model::send,
                        )
                        state.failed || status != null -> Text(
                            t("rest.codes_cannot_be_sent"),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        else -> Box(Modifier.fillMaxWidth(), Alignment.Center) { CircularProgressIndicator() }
                    }
                }
            }
        }
    }
}

/**
 * The code field, Confirm, and "Send a new code" — `VerifyContactView.swift`.
 * The field is there from the start: signing up already sent the first code.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VerifyContactView(
    state: VerifyState,
    onChannel: (com.fishers.app.onboarding.VerificationChannel) -> Unit,
    onCode: (String) -> Unit,
    onConfirm: () -> Unit,
    onSend: () -> Unit,
) {
    val status = state.status ?: return
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            t("rest.confirm_your_channel", vars = mapOf("noun" to state.channel.noun)),
            style = MaterialTheme.typography.titleMedium,
        )

        if (status.channels.size > 1) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                status.channels.forEachIndexed { index, channel ->
                    SegmentedButton(
                        selected = state.channel == channel,
                        onClick = { onChannel(channel) },
                        shape = SegmentedButtonDefaults.itemShape(index, status.channels.size),
                    ) { Text(channel.tabLabel) }
                }
            }
        }

        Text(
            boldMarkdown(
                t("rest.enter_the_6_digit_code", vars = mapOf("verb" to state.channel.sentVerb, "address" to state.address)),
            ),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            val label = t("rest.verification_code")
            OutlinedTextField(
                value = state.code,
                onValueChange = onCode,
                placeholder = { Text(t("rest.x"), Modifier.fillMaxWidth(), textAlign = TextAlign.Center) },
                singleLine = true,
                textStyle = MaterialTheme.typography.titleLarge.copy(
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center,
                ),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
                modifier = Modifier.weight(1f).semantics { contentDescription = label },
            )
            Button(
                onClick = onConfirm,
                enabled = state.canConfirm,
                modifier = Modifier.heightIn(min = 48.dp).widthIn(min = 88.dp),
            ) {
                if (state.busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text(t("le.confirm"))
            }
        }

        TextButton(onClick = onSend, enabled = state.wait == 0, modifier = Modifier.heightIn(min = 48.dp)) {
            Text(
                if (state.wait > 0) {
                    t("rest.send_a_new_code_in", vars = mapOf("n" to state.wait))
                } else {
                    t("rest.send_a_new_code")
                },
            )
        }

        state.note?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        state.error?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error) }
    }
}

/** The dictionary marks the address `**like this**`; drawn bold rather than with the stars. */
private fun boldMarkdown(text: String) = buildAnnotatedString {
    text.split("**").forEachIndexed { index, part ->
        if (index % 2 == 1) withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(part) } else append(part)
    }
}

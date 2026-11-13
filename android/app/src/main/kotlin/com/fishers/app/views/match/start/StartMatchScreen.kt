package com.fishers.app.views.match.start

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.unit.dp
import com.fishers.app.R
import com.fishers.app.i18n.t
import com.fishers.app.match.start.MatchKind
import com.fishers.app.match.start.StartMatchState
import com.fishers.app.match.start.Verification

/** The quick start — `QuickMatchSheet` in `ScoreHubView.swift`. */
@Composable
fun StartMatchScreen(
    state: StartMatchState,
    onBack: () -> Unit,
    onRetry: () -> Unit,
    onClub: (String) -> Unit,
    onTeam: (String?) -> Unit,
    onTeamName: (String) -> Unit,
    onPickOpposition: () -> Unit,
    onKind: (MatchKind) -> Unit,
    onStart: () -> Unit,
    onStartAClub: () -> Unit,
    onSendCode: () -> Unit,
    onCode: (String) -> Unit,
    onConfirmCode: () -> Unit,
    onEditProfile: () -> Unit,
) {
    val brand = stringResource(R.string.brand_name)
    StartPage(title = t("cl.start_a_match"), onBack = onBack) {
        if (state.isLoading) {
            Loading()
            return@StartPage
        }
        state.loadError?.let {
            ErrorLine(it)
            OutlinedButton(onClick = onRetry, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("rest.try_again")) }
            return@StartPage
        }

        SectionTitle(t("sr.your_side"))
        if (state.needsATeam) {
            // Somebody with no club to play for is asked one thing, and the club
            // is made for them. The full club form is there for whoever wants it.
            OutlinedTextField(
                value = state.newTeamName,
                onValueChange = onTeamName,
                label = { Text(t("ms.your_team_name")) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Words,
                    imeAction = ImeAction.Next,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
            Footnote(t("ms.your_team_explainer"))
            TextButton(onClick = onStartAClub, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(t("ms.or_start_a_club"))
            }
        } else {
            if (state.clubs.size > 1) {
                Choices(state.clubs.map { it.id }, state.clubId, { id -> state.clubs.first { it.id == id }.name }, onClub)
            } else {
                Text(state.club?.name.orEmpty(), style = MaterialTheme.typography.titleMedium)
            }
            if (state.teams.isNotEmpty()) {
                Choices(
                    listOf<String?>(null) + state.teams.map { it.id },
                    state.teamId,
                    { id -> if (id == null) t("rest.the_club") else state.teams.first { it.id == id }.name },
                    onTeam,
                )
            }
        }

        SectionTitle(t("ev.the_opposition"))
        OutlinedButton(onClick = onPickOpposition, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
            Column(Modifier.fillMaxWidth()) {
                Text(t("sc.opposition"), style = MaterialTheme.typography.labelMedium)
                Text(state.awayName.ifBlank { t("sc.choose_ellipsis") }, style = MaterialTheme.typography.titleMedium)
            }
        }
        Footnote(
            state.opponent?.let {
                t("sc.opponent_on_brand_sentence", vars = mapOf("club" to it.clubName.ifBlank { it.name }, "brand" to brand))
            } ?: t("ms.find_them_or_type"),
        )

        SectionTitle(t("sc.kind_of_match"))
        Choices(MatchKind.entries, state.kind, { it.label }, onKind)

        state.verification?.let { VerifyCard(it, onSendCode, onCode, onConfirmCode, onEditProfile) }
        ErrorLine(state.error)

        BigButton(
            t("sc.start_scoring"),
            onClick = onStart,
            enabled = state.missing == null && state.verification == null,
            busy = state.isStarting,
        )
        state.missing?.let { Footnote(t("sc.still_needed", vars = mapOf("what" to it))) }
    }
}

/** The server wants a confirmed email or phone first. Its words, then the code, here. */
@Composable
private fun VerifyCard(
    v: Verification,
    onSend: () -> Unit,
    onCode: (String) -> Unit,
    onConfirm: () -> Unit,
    onEditProfile: () -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                if (v.channel == "phone") t("le.confirm_your_phone") else t("le.confirm_your_email"),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(v.message, style = MaterialTheme.typography.bodyMedium)
            when {
                v.channel == null -> OutlinedButton(onClick = onEditProfile, modifier = Modifier.heightIn(min = 48.dp)) {
                    Text(t("cl.edit_profile"))
                }
                v.sentTo == null -> BigButton(t("fp.send_code"), onClick = onSend, busy = v.isBusy)
                else -> {
                    if (v.sentTo.isNotBlank()) Footnote(t("ms.code_sent", vars = mapOf("address" to v.sentTo)))
                    OutlinedTextField(
                        value = v.code,
                        onValueChange = onCode,
                        label = { Text(t("rest.verification_code")) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    BigButton(t("le.confirm"), onClick = onConfirm, enabled = v.code.length == 6, busy = v.isBusy)
                    TextButton(onClick = onSend, enabled = !v.isBusy, modifier = Modifier.heightIn(min = 48.dp)) {
                        Text(t("rest.send_a_new_code"))
                    }
                }
            }
            ErrorLine(v.error)
        }
    }
}

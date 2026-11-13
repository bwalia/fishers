package com.fishers.app.views.match.start

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.R
import com.fishers.app.i18n.t
import com.fishers.app.match.start.ClubIdentity
import com.fishers.app.match.start.OppositionViewModel
import com.fishers.app.net.MatchStartApi

/**
 * Who you are playing — `OppositionPickerView.swift`, drawn over the screen that
 * asked. Back closes it without choosing.
 */
@Composable
internal fun OppositionPicker(
    api: MatchStartApi,
    onPick: (name: String, identity: ClubIdentity?) -> Unit,
    onCancel: () -> Unit,
) {
    BackHandler(onBack = onCancel)
    val model = routeViewModel { OppositionViewModel(api) }
    val state by model.state.collectAsStateWithLifecycle()
    val brand = stringResource(R.string.brand_name)
    var typed by rememberSaveable { mutableStateOf("") }

    LaunchedEffect(state.found) { state.found?.let { onPick(it.displayName, it) } }

    StartPage(title = t("sc.opposition"), onBack = onCancel) {
        SectionTitle(t("ms.their_code"))
        OutlinedTextField(
            value = state.code,
            onValueChange = model::setCode,
            label = { Text(t("ms.club_code")) },
            placeholder = { Text(t("rest.https_play_abc123_or_just_the_code")) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
            keyboardActions = KeyboardActions(onGo = { model.lookUp() }),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedButton(
            onClick = model::lookUp,
            enabled = state.code.isNotBlank() && !state.isLookingUp,
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
        ) {
            if (state.isLookingUp) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            else Text(t("ms.find_by_code"))
        }
        Footnote(t("sc.qr_under_clubs"))
        ErrorLine(state.message)

        SectionTitle(t("rest.search_by_name"))
        OutlinedTextField(
            value = state.query,
            onValueChange = model::setQuery,
            label = { Text(t("rest.club_or_team")) },
            singleLine = true,
            trailingIcon = { if (state.isSearching) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) },
            modifier = Modifier.fillMaxWidth(),
        )
        state.results.forEach { identity ->
            Column(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .clickable { onPick(identity.displayName, identity) }
                    .padding(vertical = 10.dp),
            ) {
                Text(identity.displayName, style = MaterialTheme.typography.bodyLarge)
                if (identity.isTeam) identity.sport?.let { Footnote(it.replaceFirstChar(Char::uppercase)) }
            }
            HorizontalDivider()
        }
        if (state.searched && state.results.isEmpty() && !state.isSearching) {
            Footnote(t("sc.nothing_found_type_name"))
        }

        SectionTitle(t("sc.or_just_type_it"))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = typed,
                onValueChange = { typed = it },
                label = { Text(t("sc.opposition_name")) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Words,
                    imeAction = ImeAction.Done,
                ),
                keyboardActions = KeyboardActions(onDone = { if (typed.isNotBlank()) onPick(typed.trim(), null) }),
                modifier = Modifier.weight(1f),
            )
            Button(
                onClick = { onPick(typed.trim(), null) },
                enabled = typed.isNotBlank(),
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(t("sc.use")) }
        }
        Footnote(t("sc.scratch_side_only_a_name", vars = mapOf("brand" to brand)))
    }
}

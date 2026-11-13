package com.fishers.app.views.clubs

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.R
import com.fishers.app.clubs.CreateClubState
import com.fishers.app.clubs.CreateClubViewModel
import com.fishers.app.clubs.sportLabel
import com.fishers.app.i18n.t
import com.fishers.app.net.ClubsApi
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator

/**
 * Starting a club. Whoever makes it is its first secretary, so this is also
 * how a new account gets somewhere to add people to. Once made, the form
 * becomes the club — with what to do next on it.
 */
@Composable
internal fun CreateClubPage() {
    val nav = LocalNavigator.current
    val deps = LocalAppDeps.current
    val model = remember { CreateClubViewModel(deps.service<ClubsApi>()) }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { model.loadSports() }
    LaunchedEffect(state.created) {
        state.created?.let { nav.replace(ClubRoute(it.id, it.name, welcome = true)) }
    }

    ClubScreen(title = t("cl.start_a_club")) {
        CreateClubForm(
            state = state,
            onName = model::setName,
            onSport = model::toggleSport,
            onPublic = model::setPublic,
            onDescription = model::setDescription,
            onInformal = model::setInformal,
            onCreate = model::create,
        )
    }
}

@Composable
private fun CreateClubForm(
    state: CreateClubState,
    onName: (String) -> Unit,
    onSport: (String) -> Unit,
    onPublic: (Boolean) -> Unit,
    onDescription: (String) -> Unit,
    onInformal: (Boolean) -> Unit,
    onCreate: () -> Unit,
) {
    val brand = stringResource(R.string.brand_name)
    Column(
        Modifier
            .fillMaxSize()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        SectionHeading(t("cl.step_club_name"))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ClubCrest(state.name.ifBlank { t("lc.your_club") }, "00", size = 48.dp)
            OutlinedTextField(
                value = state.name,
                onValueChange = onName,
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                label = { Text(t("cl.club_name")) },
                placeholder = { Text("$brand CC") },
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
            )
        }
        Hint(t("cl.how_your_players_and_the_clubs_you_pla"))

        SectionHeading(t("cl.step_sports_played"))
        state.offered.forEach { sport ->
            val picked = sport in state.sports
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .toggleable(value = picked, role = Role.Checkbox, onValueChange = { onSport(sport) }),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Checkbox(checked = picked, onCheckedChange = null)
                Text(sportLabel(sport), modifier = Modifier.padding(start = 12.dp))
            }
        }
        Hint(t("cl.pick_every_one_you_play_teams_are_set"))

        SectionHeading(t("cl.step_who_can_find"))
        Visibility(
            selected = !state.isPublic,
            icon = Icons.Filled.Lock,
            title = t("lc.invite_only"),
            detail = t("cl.kept_out_of_search"),
            onClick = { onPublic(false) },
        )
        Visibility(
            selected = state.isPublic,
            icon = Icons.Filled.Groups,
            title = t("lc.anyone_can_find_it"),
            detail = t("lc.other_clubs_can_find_you_by_name_when"),
            onClick = { onPublic(true) },
        )

        SectionHeading(t("cl.step_description"))
        OutlinedTextField(
            value = state.description,
            onValueChange = onDescription,
            modifier = Modifier.fillMaxWidth(),
            minLines = 2,
            maxLines = 5,
            placeholder = { Text(t("cl.sunday_friendlies_hemel_hempstead")) },
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
        )
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .toggleable(value = state.isInformal, role = Role.Switch, onValueChange = onInformal),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(t("cl.friend_group_not_a_club"), modifier = Modifier.weight(1f))
            Switch(checked = state.isInformal, onCheckedChange = null)
        }
        Hint(t("cl.where_and_when_you_play_it_shows_on_th"))

        if (state.needsVerifying) {
            Row(Modifier.padding(top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.VerifiedUser, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text(
                    t("cl.confirm_its_you_first"),
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.padding(start = 8.dp),
                )
            }
            Hint(t("cl.confirm_on_the_website", vars = mapOf("brand" to brand)))
        }
        state.error?.let { ErrorLine(it, Modifier.padding(top = 8.dp)) }

        Hint(state.missing ?: t("lc.you_become_its_secretary_so_you_can_ad"), Modifier.padding(top = 16.dp))
        Button(
            onClick = onCreate,
            enabled = state.canSave,
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(bottom = 16.dp),
        ) {
            if (state.isSaving) {
                CircularProgressIndicator(Modifier.padding(end = 8.dp).size(18.dp), strokeWidth = 2.dp)
            }
            Text(t("cl.create"))
        }
    }
}

@Composable
private fun Visibility(selected: Boolean, icon: ImageVector, title: String, detail: String, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Hint(detail)
        }
        RadioButton(selected = selected, onClick = null)
    }
}

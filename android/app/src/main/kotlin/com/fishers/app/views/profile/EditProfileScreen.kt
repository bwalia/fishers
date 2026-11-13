package com.fishers.app.views.profile

import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.fishers.app.i18n.t
import com.fishers.app.profile.AgeGroup
import com.fishers.app.profile.Division
import com.fishers.app.profile.EditProfileState
import com.fishers.app.profile.ProfileForm
import com.fishers.app.profile.SkillTier
import com.fishers.app.profile.Sport
import com.fishers.app.profile.SportStats
import com.fishers.app.profile.StatField
import com.fishers.app.profile.TRAVEL_RADII
import com.fishers.app.profile.TransportMode
import com.fishers.app.profile.Weekday
import com.fishers.app.profile.labelOf

/**
 * Every field a profile holds — `ProfileEditView.swift` and the four forms in
 * `ProfileForms.swift`, on one scrolling page rather than four sub-pages: a
 * phone scrolls more happily than it drills down and back.
 *
 * Whatever is filled in saves; a profile is finished a bit at a time.
 */
@Composable
internal fun EditProfileScreen(
    state: EditProfileState,
    onEdit: ((ProfileForm) -> ProfileForm) -> Unit,
    onSave: () -> Unit,
    onBack: () -> Unit,
    onRetry: () -> Unit,
    onPickPhoto: () -> Unit,
) {
    Column(Modifier.fillMaxSize().imePadding()) {
        RouteBar(t("cl.edit_profile"), onBack = onBack) {
            if (state.isSaving) {
                CircularProgressIndicator(Modifier.padding(12.dp).size(24.dp), strokeWidth = 2.dp)
            } else {
                TextButton(onClick = onSave, enabled = state.canSave) { Text(t("lc.save")) }
            }
        }

        val me = state.me
        when {
            me == null && state.isLoading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
            me == null -> Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(state.loadError ?: t("rest.something_went_wrong_try_again"), color = MaterialTheme.colorScheme.error)
                TextButton(onClick = onRetry) { Text(t("rest.try_again")) }
            }
            else -> Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                val form = state.form
                state.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }

                PhotoRow(form.name.ifBlank { me.name }, me.avatarUrl, state.photoBusy, state.photoError, onPickPhoto)

                SectionCard(t("rest.about_you")) {
                    OutlinedTextField(
                        value = form.name,
                        onValueChange = { v -> onEdit { it.copy(name = v) } },
                        label = { Text(t("rest.full_name")) },
                        isError = !form.isNameValid,
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = form.phone,
                        onValueChange = { v -> onEdit { it.copy(phone = v) } },
                        label = { Text(t("cl.mobile")) },
                        placeholder = { Text(t("cl.07700_900123")) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }

                SectionCard(t("rest.emergency_contact"), footer = t("rest.only_club_admins_see_this")) {
                    OutlinedTextField(
                        value = form.emergencyContact,
                        onValueChange = { v -> onEdit { it.copy(emergencyContact = v) } },
                        placeholder = { Text(t("rest.name_dot_number")) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }

                SportsSection(form, state.sportsShown, onEdit)

                form.selectedSports.forEach { sport -> SportDetailSection(sport, form, onEdit) }

                LogisticsSection(form, onEdit)

                Text(
                    t("rest.reliability_is_server_worked"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(
                    onClick = onSave,
                    enabled = state.canSave,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                ) {
                    if (state.isSaving) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) else Text(t("lc.save"))
                }
            }
        }
    }
}

@Composable
private fun PhotoRow(name: String, avatarUrl: String?, busy: Boolean, error: String?, onPick: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Avatar(name, avatarUrl, 72.dp)
        Spacer(Modifier.width(16.dp))
        Column {
            TextButton(onClick = onPick, enabled = !busy, modifier = Modifier.heightIn(min = 48.dp)) {
                if (busy) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                } else {
                    Text(if (avatarUrl == null) t("ld.add_a_photo") else t("ld.change_your_photo"))
                }
            }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SportsSection(form: ProfileForm, shown: List<Sport>, onEdit: ((ProfileForm) -> ProfileForm) -> Unit) {
    SectionCard(t("rest.sports")) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            shown.forEach { sport ->
                FilterChip(
                    selected = form.isSelected(sport),
                    onClick = { onEdit { it.toggle(sport) } },
                    label = { Text(sport.label) },
                )
            }
        }
        if (form.selectedSports.size > 1) {
            Text(t("cl.main_sport"), style = MaterialTheme.typography.titleSmall)
            Text(t("rest.shown_first_on_profile"), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                form.selectedSports.forEach { sport ->
                    FilterChip(
                        selected = form.primarySport == sport,
                        onClick = { onEdit { it.copy(primarySport = sport) } },
                        label = { Text(sport.label) },
                    )
                }
            }
        }
    }
}

/** One sport's standard, position, league and numbers — `SportDetailForm`. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SportDetailSection(sport: Sport, form: ProfileForm, onEdit: ((ProfileForm) -> ProfileForm) -> Unit) {
    val detail = form.detail(sport)
    SectionCard(sport.label) {
        Text(t("rest.your_standard"), style = MaterialTheme.typography.titleSmall)
        SkillTier.entries.forEach { tier ->
            val selected = detail.tier == tier
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .selectable(selected, role = Role.RadioButton) {
                        onEdit { f -> f.mutate(sport) { it.copy(skillLevel = tier.wire) } }
                    }
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(selected = selected, onClick = null)
                Spacer(Modifier.width(8.dp))
                Column(Modifier.weight(1f)) {
                    Text(tier.label, style = MaterialTheme.typography.bodyMedium)
                    Text(tier.blurb, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        Hint(
            detail.tier?.next?.let { t("rest.next_rung_up", vars = mapOf("level" to it.label)) }
                ?: t("rest.be_honest_captains_balance"),
        )

        if (sport.positions.isNotEmpty()) {
            Text(t("rest.position"), style = MaterialTheme.typography.titleSmall)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                sport.positions.forEach { option ->
                    FilterChip(
                        selected = detail.position == option.value,
                        onClick = {
                            onEdit { f ->
                                f.mutate(sport) { it.copy(position = if (it.position == option.value) null else option.value) }
                            }
                        },
                        label = { Text(option.label) },
                    )
                }
            }
        }

        Text(t("rest.team_and_league"), style = MaterialTheme.typography.titleSmall)
        OutlinedTextField(
            value = detail.teamName.orEmpty(),
            onValueChange = { v -> onEdit { f -> f.mutate(sport) { it.copy(teamName = v.ifBlank { null }) } } },
            label = { Text(t("rest.team_you_play_for")) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        ChoiceField(t("tn.age_group"), detail.ageBand?.label, AgeGroup.entries, { it.label }) { group ->
            onEdit { f -> f.mutate(sport) { it.copy(ageGroup = group?.wire) } }
        }
        if (sport.usesDivisions) {
            ChoiceField(t("rest.division_you_play_in"), detail.division?.label, Division.entries, { it.label }) { d ->
                onEdit { f -> f.mutate(sport) { it.copy(currentDivision = d?.wire) } }
            }
            ChoiceField(t("rest.division_youre_aiming_for"), detail.target?.label, Division.entries, { it.label }) { d ->
                onEdit { f -> f.mutate(sport) { it.copy(targetDivision = d?.wire) } }
            }
        }
        OutlinedTextField(
            value = detail.yearsPlaying?.toString().orEmpty(),
            onValueChange = { v ->
                val years = SportStats.clampWhole(v, 0..60).toIntOrNull()?.takeIf { it > 0 }
                onEdit { f -> f.mutate(sport) { it.copy(yearsPlaying = years) } }
            },
            label = { Text(t("cl.years_playing")) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.fillMaxWidth(),
        )

        Text(
            t("rest.your_sport_stats", vars = mapOf("sport" to sport.label.lowercase())),
            style = MaterialTheme.typography.titleSmall,
        )
        sport.statFields.forEach { field ->
            StatFieldRow(field, detail.stats[field.key].orEmpty()) { v -> onEdit { it.withStat(sport, field.key, v) } }
        }
        Hint(t("rest.all_optional_player_card"))
    }
}

/** One stat from the catalog — `StatFieldRow`. */
@Composable
private fun StatFieldRow(field: StatField, value: String, onChange: (String) -> Unit) {
    when (val kind = field.kind) {
        is StatField.Kind.Pick -> {
            ChoiceField(field.label, kind.options.labelOf(value.ifBlank { null }), kind.options, { it.label }) {
                onChange(it?.value.orEmpty())
            }
            field.footnote?.let { Hint(it) }
        }
        else -> OutlinedTextField(
            value = value,
            onValueChange = { typed ->
                onChange(
                    when (kind) {
                        is StatField.Kind.Whole -> SportStats.clampWhole(typed, kind.range)
                        is StatField.Kind.Decimal -> typed.filter { it.isDigit() || it == '.' }.take(6)
                        else -> typed
                    },
                )
            },
            label = { Text(field.label) },
            placeholder = (kind as? StatField.Kind.Decimal)?.let { { Text(it.placeholder) } },
            supportingText = field.footnote?.let { { Text(it) } },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                keyboardType = when (kind) {
                    is StatField.Kind.Whole -> KeyboardType.Number
                    is StatField.Kind.Decimal -> KeyboardType.Decimal
                    else -> KeyboardType.Text
                },
            ),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** Where they are based and how they travel — `LogisticsForm`. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun LogisticsSection(form: ProfileForm, onEdit: ((ProfileForm) -> ProfileForm) -> Unit) {
    SectionCard(t("rest.travel_and_logistics")) {
        OutlinedTextField(
            value = form.area,
            onValueChange = { v -> onEdit { it.copy(area = v) } },
            label = { Text(t("rest.area_or_town")) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = form.postcode,
            onValueChange = { v -> onEdit { it.copy(postcode = v) } },
            label = { Text(t("rest.postcode_first_part")) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false),
            modifier = Modifier.fillMaxWidth(),
        )

        ChoiceField(
            t("ld.will_travel"),
            t("pf.n_miles", vars = mapOf("n" to form.travelRadiusMiles)),
            TRAVEL_RADII,
            { t("pf.n_miles", vars = mapOf("n" to it)) },
            allowNone = false,
        ) { miles -> miles?.let { m -> onEdit { it.copy(travelRadiusMiles = m) } } }
        ChoiceField(t("ld.transport"), form.transport?.label, TransportMode.entries, { it.label }) { mode ->
            onEdit { it.copy(transport = mode) }
        }
        if (form.transport?.offersLifts == true) {
            ChoiceField(t("pf.spare_seats"), "${form.spareSeats}", (0..6).toList(), { "$it" }, allowNone = false) { n ->
                n?.let { seats -> onEdit { it.copy(spareSeats = seats) } }
            }
        }
        Hint(t("rest.away_fixtures_lifts"))

        Text(t("rest.usual_days"), style = MaterialTheme.typography.titleSmall)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Weekday.entries.forEach { day ->
                val on = day.number in form.preferredDays
                FilterChip(
                    selected = on,
                    onClick = {
                        onEdit {
                            it.copy(preferredDays = if (on) it.preferredDays - day.number else it.preferredDays + day.number)
                        }
                    },
                    label = { Text(day.shortLabel) },
                )
            }
        }
        Hint(t("rest.availability_starting_point"))

        OutlinedTextField(
            value = form.notes,
            onValueChange = { v -> onEdit { it.copy(notes = v) } },
            label = { Text(t("tn.anything_else")) },
            placeholder = { Text(t("rest.no_saturdays_example")) },
            minLines = 2,
            maxLines = 4,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun Hint(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

/**
 * A labelled choice from a short list, with "Not set" unless [allowNone] is
 * false — `OptionMenu`. A whole-row target, so it is easy to hit.
 */
@Composable
internal fun <T> ChoiceField(
    label: String,
    selected: String?,
    options: List<T>,
    optionLabel: (T) -> String,
    allowNone: Boolean = true,
    onPick: (T?) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clip(RoundedCornerShape(8.dp))
                .clickable(role = Role.DropdownList) { open = true }
                .padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            Text(
                selected ?: t("rest.not_set"),
                style = MaterialTheme.typography.bodyMedium,
                color = if (selected == null) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.primary,
            )
            Icon(Icons.Filled.ArrowDropDown, contentDescription = null)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            if (allowNone) {
                DropdownMenuItem(text = { Text(t("rest.not_set")) }, onClick = { open = false; onPick(null) })
            }
            options.forEach { option ->
                DropdownMenuItem(text = { Text(optionLabel(option)) }, onClick = { open = false; onPick(option) })
            }
        }
    }
}

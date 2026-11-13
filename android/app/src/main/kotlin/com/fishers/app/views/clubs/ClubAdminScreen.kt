package com.fishers.app.views.clubs

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.R
import com.fishers.app.clubs.ClubAdminState
import com.fishers.app.clubs.ClubAdminViewModel
import com.fishers.app.clubs.ClubDetailState
import com.fishers.app.clubs.ClubDetailViewModel
import com.fishers.app.clubs.ClubMemberDetail
import com.fishers.app.clubs.ClubSettings
import com.fishers.app.clubs.RoleChoice
import com.fishers.app.clubs.UserRole
import com.fishers.app.clubs.money
import com.fishers.app.i18n.t
import com.fishers.app.net.ClubsApi
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator
import com.fishers.app.views.profile.PlayerProfileRoute
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * The club secretary's screen — `ClubAdminView.swift`: who is in the club,
 * who runs it, the link the squad joins through, the policy, and who still
 * owes money. Everyone in the club may read the roster; only a secretary sees
 * the buttons that change it.
 */
@Composable
internal fun ManageClubPage(clubId: String, clubName: String, startAdding: Boolean) {
    val deps = LocalAppDeps.current
    val nav = LocalNavigator.current
    // The roster and the club link were ClubDetailViewModel's before this
    // screen existed, and still are; the secretary's actions are the admin
    // model's, and each one that changes the roster has it re-read.
    val detail = remember(clubId) { ClubDetailViewModel(deps.api, clubId, deps.webBase) }
    val admin = remember(clubId) { ClubAdminViewModel(deps.service<ClubsApi>(), clubId, deps.webBase) }
    val roster by detail.state.collectAsStateWithLifecycle()
    val state by admin.state.collectAsStateWithLifecycle()
    LaunchedEffect(clubId) {
        detail.load()
        admin.load()
    }
    LaunchedEffect(state.changed) { if (state.changed > 0) detail.load() }

    var tab by rememberSaveable { mutableIntStateOf(0) }
    var adding by rememberSaveable { mutableStateOf(startAdding) }
    var editing by remember { mutableStateOf<ClubMemberDetail?>(null) }

    ClubScreen(
        title = t("cl.manage_club"),
        actions = {
            if (state.canManage) {
                IconButton(onClick = { adding = true }) {
                    Icon(Icons.Filled.PersonAdd, contentDescription = t("cl.add_a_member"))
                }
            }
        },
    ) {
        TabRow(selectedTabIndex = tab) {
            listOf(t("cl.members"), t("rest.policy"), t("cl.fees")).forEachIndexed { index, label ->
                Tab(selected = tab == index, onClick = { tab = index }, text = { Text(label) })
            }
        }
        when (tab) {
            0 -> RosterTab(
                clubName = clubName,
                roster = roster,
                canManage = state.canManage,
                onAdd = { adding = true },
                onOpen = { nav.push(PlayerProfileRoute(it.userId, it.name)) },
                onRole = { editing = it },
                onMakeLink = detail::makeJoinLink,
                onStopLink = detail::stopJoinLink,
            )
            1 -> PolicyTab(state, onChange = admin::changeSettings)
            else -> FeesTab(state, onChase = admin::chaseFees)
        }
    }

    // Opened from a new club's welcome: only once it is known this person may add.
    if (adding && state.canManage) {
        AddMemberDialog(
            clubName = clubName,
            state = state,
            onAdd = { identifier, role ->
                admin.addMember(identifier, role)
                adding = false
                admin.clearInvite()
            },
            onMakeInvite = admin::makeInvite,
            onDismiss = {
                adding = false
                admin.clearInvite()
            },
        )
    }
    editing?.let { member ->
        RoleDialog(
            member = member,
            onSave = { choice ->
                admin.setRole(member, choice)
                editing = null
            },
            onRemove = {
                admin.remove(member)
                editing = null
            },
            onDismiss = { editing = null },
        )
    }
    state.error?.let { error ->
        AlertDialog(
            onDismissRequest = admin::dismissError,
            title = { Text(t("le.something_went_wrong")) },
            text = { Text(error) },
            confirmButton = { TextButton(onClick = admin::dismissError) { Text(t("rest.ok")) } },
        )
    }
}

// ---- members ----

@Composable
private fun RosterTab(
    clubName: String,
    roster: ClubDetailState,
    canManage: Boolean,
    onAdd: () -> Unit,
    onOpen: (ClubMemberDetail) -> Unit,
    onRole: (ClubMemberDetail) -> Unit,
    onMakeLink: (Boolean) -> Unit,
    onStopLink: () -> Unit,
) {
    if (roster.isFirstLoad && roster.isLoading) {
        Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
        return
    }
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (canManage) {
            item {
                Button(onClick = onAdd, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                    Icon(Icons.Filled.PersonAdd, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(t("cl.add_a_member"), modifier = Modifier.padding(start = 8.dp))
                }
            }
        } else {
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Info, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Hint(t("cl.only_secretary_changes_roles"), Modifier.padding(start = 8.dp))
                }
            }
        }
        if (roster.canShareLink) {
            item { JoinLinkCard(clubName, roster, onMakeLink, onStopLink) }
        }
        roster.error?.let { item { ErrorLine(it) } }

        roster.byRole.forEach { (role, members) ->
            group("role-${role.name}", role.displayName, members) { member ->
                MemberRow(member, canManage, onOpen = { onOpen(member) }, onRole = { onRole(member) })
            }
        }
        group("invited", t("rest.asked_not_answered"), roster.invited) { member ->
            MemberRow(member, canManage, muted = true, onOpen = { onOpen(member) }, onRole = { onRole(member) })
        }
        group("former", t("cl.no_longer_in_the_club"), roster.former) { member ->
            Text(
                member.name,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(vertical = 8.dp),
            )
        }
        if (roster.members.isEmpty() && !roster.isLoading) {
            item {
                Column(Modifier.padding(vertical = 24.dp)) {
                    Text(t("cl.no_members_yet"), style = MaterialTheme.typography.titleMedium)
                    Hint(t("cl.add_players_by_signup_email"))
                }
            }
        }
    }
}

private fun LazyListScope.group(
    key: String,
    heading: String,
    members: List<ClubMemberDetail>,
    row: @Composable (ClubMemberDetail) -> Unit,
) {
    if (members.isEmpty()) return
    item(key = "heading-$key") { SectionHeading("$heading · ${members.size}") }
    items(members, key = { "$key-${it.userId}" }) { row(it) }
}

/**
 * Two targets, because there are two things to do with a name. The person
 * opens their record — anybody can. The role badge is the button that changes
 * it, and only a secretary sees it as one.
 */
@Composable
private fun MemberRow(
    member: ClubMemberDetail,
    canManage: Boolean,
    muted: Boolean = false,
    onOpen: () -> Unit,
    onRole: () -> Unit,
) {
    val choice = member.roleChoice
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier
                .weight(1f)
                .clickable(onClick = onOpen)
                .semantics(mergeDescendants = true) {
                    contentDescription = t("cl.member_open_profile", vars = mapOf("name" to member.name, "role" to choice.label))
                }
                .padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Initials(member.name)
            Column {
                Text(
                    member.name,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium,
                    color = if (muted) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
                )
                if (member.subtitle.isNotEmpty()) Hint(member.subtitle)
                Hint(member.contact)
            }
        }
        RoleBadge(
            choice = choice,
            onClick = if (canManage) onRole else null,
            spoken = t("cl.change_role_now", vars = mapOf("name" to member.name, "role" to choice.label)),
        )
    }
    HorizontalDivider()
}

@Composable
private fun Initials(name: String) {
    Box(
        Modifier.size(36.dp).background(MaterialTheme.colorScheme.secondaryContainer, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            name.split(' ').filter { it.isNotEmpty() }.take(2).joinToString("") { it.first().uppercase() },
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSecondaryContainer,
        )
    }
}

@Composable
private fun RoleBadge(choice: RoleChoice, onClick: (() -> Unit)?, spoken: String) {
    val scheme = MaterialTheme.colorScheme
    val colour = when (choice.role) {
        UserRole.ClubAdmin, UserRole.SuperAdmin -> scheme.secondary
        UserRole.TeamCaptain -> scheme.primary
        UserRole.TeamViceCaptain -> scheme.tertiary
        UserRole.Member, UserRole.Guest -> scheme.onSurfaceVariant
    }
    val badge = @Composable {
        Text(
            choice.shortLabel,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            color = colour,
            modifier = Modifier
                .background(colour.copy(alpha = 0.14f), RoundedCornerShape(50))
                .padding(horizontal = 8.dp, vertical = 3.dp),
        )
    }
    if (onClick == null) {
        badge()
    } else {
        Box(
            Modifier
                .heightIn(min = 48.dp)
                .clickable(role = Role.Button, onClick = onClick)
                .semantics { contentDescription = spoken }
                .padding(horizontal = 4.dp),
            contentAlignment = Alignment.Center,
        ) { badge() }
    }
}

/**
 * One link for the whole squad — the website's `ClubJoinLink`. An invite made
 * for a person is spent by the first one through it, so the link a secretary
 * dropped into the team WhatsApp group let one player in and told the rest it
 * had been used. This one is never used up, until the secretary turns it off.
 */
@Composable
private fun JoinLinkCard(
    clubName: String,
    state: ClubDetailState,
    onMake: (fresh: Boolean) -> Unit,
    onStop: () -> Unit,
) {
    val context = LocalContext.current
    val brand = stringResource(R.string.brand_name)
    // true: make a new link; false: turn it off. Both ask first, as the website does.
    var confirm by remember { mutableStateOf<Boolean?>(null) }
    val url = state.joinLinkUrl

    Card(
        Modifier.fillMaxWidth().padding(top = 8.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(t("jl.title"), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
            Hint(t("jl.explainer"))
            if (url == null) {
                Button(onClick = { onMake(false) }, modifier = Modifier.heightIn(min = 48.dp)) {
                    Icon(Icons.Filled.Link, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(t("jl.make_link"), modifier = Modifier.padding(start = 8.dp))
                }
            } else {
                Text(url, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = {
                        shareText(
                            context,
                            t("jl.whatsapp_message", vars = mapOf("club" to clubName, "brand" to brand, "url" to url)),
                        )
                    }, modifier = Modifier.heightIn(min = 48.dp)) {
                        Icon(Icons.Filled.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                        Text(t("sc.share"), modifier = Modifier.padding(start = 8.dp))
                    }
                    OutlinedButton(onClick = { confirm = true }, modifier = Modifier.heightIn(min = 48.dp)) {
                        Text(t("jl.new_link"))
                    }
                }
                TextButton(onClick = { confirm = false }, modifier = Modifier.heightIn(min = 48.dp)) {
                    Text(t("jl.turn_off"), color = MaterialTheme.colorScheme.error)
                }
                val uses = state.joinLink?.uses ?: 0
                Hint(t("jl.joined_through_it", count = uses, vars = mapOf("n" to uses)))
            }
        }
    }

    confirm?.let { fresh ->
        AlertDialog(
            onDismissRequest = { confirm = null },
            text = { Text(if (fresh) t("jl.confirm_new_link") else t("jl.confirm_turn_off")) },
            confirmButton = {
                TextButton(onClick = {
                    confirm = null
                    if (fresh) onMake(true) else onStop()
                }) { Text(if (fresh) t("jl.new_link") else t("jl.turn_off")) }
            },
            dismissButton = { TextButton(onClick = { confirm = null }) { Text(t("sc.cancel")) } },
        )
    }
}

/**
 * Add somebody already on the app by what they signed up with — or, for
 * somebody who is not, make a link for one person to open.
 */
@Composable
private fun AddMemberDialog(
    clubName: String,
    state: ClubAdminState,
    onAdd: (identifier: String, role: UserRole) -> Unit,
    onMakeInvite: (email: String?) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val brand = stringResource(R.string.brand_name)
    var identifier by rememberSaveable { mutableStateOf("") }
    var role by rememberSaveable { mutableStateOf(UserRole.Member) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(t("cl.add_a_member")) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                OutlinedTextField(
                    value = identifier,
                    onValueChange = { identifier = it },
                    singleLine = true,
                    label = { Text(t("cl.email_or_mobile_number")) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, autoCorrectEnabled = false),
                    modifier = Modifier.fillMaxWidth(),
                )
                Hint(t("cl.whatever_they_signed_up_with"))
                Text(t("cl.role"), style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = 8.dp))
                listOf(UserRole.ClubAdmin, UserRole.TeamCaptain, UserRole.TeamViceCaptain, UserRole.Member, UserRole.Guest)
                    .forEach { option ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .heightIn(min = 48.dp)
                                .selectable(selected = role == option, role = Role.RadioButton) { role = option },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = role == option, onClick = null)
                            Text(option.displayName, modifier = Modifier.padding(start = 12.dp))
                        }
                    }
                HorizontalDivider(Modifier.padding(vertical = 8.dp))
                val url = state.inviteUrl
                if (url == null) {
                    TextButton(
                        onClick = { onMakeInvite(identifier) },
                        modifier = Modifier.heightIn(min = 48.dp),
                    ) {
                        Icon(Icons.Filled.Link, contentDescription = null, modifier = Modifier.size(18.dp))
                        Text(t("cl.make_an_invite_link_instead"), modifier = Modifier.padding(start = 8.dp))
                    }
                } else {
                    Text(url, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                    OutlinedButton(
                        onClick = {
                            shareText(
                                context,
                                t("jl.whatsapp_message", vars = mapOf("club" to clubName, "brand" to brand, "url" to url)),
                            )
                        },
                        modifier = Modifier.heightIn(min = 48.dp),
                    ) {
                        Icon(Icons.Filled.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                        Text(t("cl.share_the_link"), modifier = Modifier.padding(start = 8.dp))
                    }
                }
                Hint(t("cl.invite_link_explainer", vars = mapOf("brand" to brand)))
            }
        },
        confirmButton = {
            TextButton(onClick = { onAdd(identifier, role) }, enabled = identifier.isNotBlank()) { Text(t("sc.add")) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(t("sc.cancel")) } },
    )
}

/**
 * Appointing a captain is the most consequential thing a secretary does, so
 * each role says what it lets somebody do.
 */
@Composable
private fun RoleDialog(
    member: ClubMemberDetail,
    onSave: (RoleChoice) -> Unit,
    onRemove: () -> Unit,
    onDismiss: () -> Unit,
) {
    var choice by remember(member.userId) { mutableStateOf(member.roleChoice) }
    var confirmRemove by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(member.name) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Text(t("cl.role"), style = MaterialTheme.typography.labelLarge)
                RoleChoice.appointable.forEach { option ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .selectable(selected = choice == option, role = Role.RadioButton) { choice = option }
                            .padding(vertical = 6.dp),
                        verticalAlignment = Alignment.Top,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        RadioButton(selected = choice == option, onClick = null)
                        Column {
                            Text(option.label, style = MaterialTheme.typography.titleSmall)
                            Hint(option.responsibilities)
                        }
                    }
                }
                Hint(t("cl.must_keep_one_secretary"), Modifier.padding(vertical = 8.dp))
                TextButton(onClick = { confirmRemove = true }, modifier = Modifier.heightIn(min = 48.dp)) {
                    Text(t("cl.remove_from_the_club_action"), color = MaterialTheme.colorScheme.error)
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(choice) }, enabled = choice != member.roleChoice) { Text(t("lc.save")) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(t("sc.cancel")) } },
    )
    if (confirmRemove) {
        AlertDialog(
            onDismissRequest = { confirmRemove = false },
            title = { Text(t("cl.remove_from_the_club", vars = mapOf("name" to member.name))) },
            text = { Text(t("cl.past_record_stays")) },
            confirmButton = {
                TextButton(
                    onClick = { confirmRemove = false; onRemove() },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text(t("cl.remove")) }
            },
            dismissButton = { TextButton(onClick = { confirmRemove = false }) { Text(t("sc.cancel")) } },
        )
    }
}

// ---- policy ----

/** How the club runs itself: how much the assistant does, and how hard people are chased. */
@Composable
private fun PolicyTab(state: ClubAdminState, onChange: ((ClubSettings) -> ClubSettings) -> Unit) {
    val settings = state.settings
    if (settings == null) {
        Box(Modifier.fillMaxSize(), Alignment.Center) {
            if (state.isLoading) CircularProgressIndicator() else Hint(t("rest.something_went_wrong_plain"))
        }
        return
    }
    val enabled = state.canSetPolicy
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (!enabled) Hint(t("cl.only_secretary_changes_roles"))

        SectionHeading(t("cl.picking_a_side"))
        listOf(
            "off" to t("cl.captains_do_it_no_help_offered"),
            "suggest" to t("cl.offer_a_squad_and_wait_for_the_captain"),
            "auto_publish" to t("cl.announce_a_squad_without_asking"),
        ).forEach { (value, label) ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .selectable(
                        selected = settings.selectionAutonomy == value,
                        enabled = enabled,
                        role = Role.RadioButton,
                    ) { onChange { it.copy(selectionAutonomy = value) } },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(selected = settings.selectionAutonomy == value, onClick = null, enabled = enabled)
                Text(label, modifier = Modifier.padding(start = 12.dp))
            }
        }
        Hint(
            when (settings.selectionAutonomy) {
                "auto_publish" -> t("lc.sides_go_out_on_their_own_a_captain_ca")
                "suggest" -> t("lc.nothing_is_announced_until_a_captain_s")
                else -> t("lc.nothing_is_suggested_at_all")
            },
        )

        SectionHeading(t("cl.chasing_the_squad"))
        Stepper(t("lc.ask_for_confirmation"), settings.confirmLeadHours, t("cl.hours_before_the_start"), 6, enabled) { n ->
            onChange { it.copy(confirmLeadHours = n) }
        }
        Stepper(t("lc.drop_anyone_who_has_not_confirmed"), settings.dropLeadHours, t("cl.hours_before_reserves_move_up"), 6, enabled) { n ->
            onChange { it.copy(dropLeadHours = n) }
        }
        Hint(t("cl.reconfirm_then_reserve"))

        SectionHeading(t("lb.match_fees"))
        Stepper(t("lc.chase_an_unpaid_fee_after"), settings.feeChaseAfterHours, t("cl.hours_from_the_fixture"), 6, enabled) { n ->
            onChange { it.copy(feeChaseAfterHours = n) }
        }
        Stepper(t("lc.stop_chasing_after"), settings.feeChaseMaxReminders, t("cl.reminders_so_nobody_is_nagged"), 1, enabled) { n ->
            onChange { it.copy(feeChaseMaxReminders = n) }
        }
        Hint(t("cl.then_daily_until_paid"))

        if (state.isSaving) {
            Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                Hint(t("la.saving"), Modifier.padding(start = 8.dp))
            }
        }
    }
}

/** A number with − and + either side, the way the iPhone's stepper reads. */
@Composable
private fun Stepper(label: String, value: Int, unit: String, step: Int, enabled: Boolean, onValue: (Int) -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            Hint("$value $unit")
        }
        IconButton(onClick = { onValue(value - step) }, enabled = enabled && value > 0) {
            Icon(Icons.Filled.Remove, contentDescription = t("cl.step_down", vars = mapOf("what" to label)))
        }
        Text("$value", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(horizontal = 4.dp))
        IconButton(onClick = { onValue(value + step) }, enabled = enabled) {
            Icon(Icons.Filled.Add, contentDescription = t("cl.step_up", vars = mapOf("what" to label)))
        }
    }
}

// ---- fees ----

/**
 * Who has not paid for what. One row per person per fixture, because that is
 * how anybody actually chases: "you owe for the Watford game".
 */
@Composable
private fun FeesTab(state: ClubAdminState, onChase: () -> Unit) {
    val fees = state.fees
    if (fees == null) {
        Box(Modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
            if (state.isLoading) CircularProgressIndicator() else Hint(t("cl.fees_are_for_captains"))
        }
        return
    }
    val currency = fees.owed.firstOrNull()?.currency
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        item {
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                Text(t("cl.outstanding"), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                Text(money(fees.totalCents, currency), style = MaterialTheme.typography.titleMedium)
            }
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                Text(t("rest.people"), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                Text("${fees.count}", style = MaterialTheme.typography.titleMedium)
            }
            HorizontalDivider()
        }
        if (fees.owed.isEmpty()) {
            item {
                Row(Modifier.padding(vertical = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Verified, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                    Text(t("cl.everyone_has_paid"), modifier = Modifier.padding(start = 8.dp))
                }
            }
            return@LazyColumn
        }
        item { SectionHeading(t("cl.who_owes")) }
        items(fees.owed, key = { "${it.userId}-${it.eventId}" }) { fee ->
            Column(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                Row {
                    Text(fee.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                    Text(money((fee.amountCents ?: 0).toLong(), fee.currency))
                }
                Hint("${fee.fixture} · ${shortDate(fee.startAt)}")
                if (fee.remindersSent > 0) {
                    Text(
                        t("cl.n_reminders_sent", count = fee.remindersSent, vars = mapOf("n" to fee.remindersSent)),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.tertiary,
                    )
                }
            }
            HorizontalDivider()
        }
        if (state.canChase) {
            item {
                Button(
                    onClick = onChase,
                    enabled = !state.isChasing,
                    modifier = Modifier.padding(top = 12.dp).heightIn(min = 48.dp),
                ) {
                    Text(if (state.isChasing) t("fp.sending") else t("cl.send_reminders_now"))
                }
                Hint(t("cl.scheduler_does_this_itself"), Modifier.padding(top = 4.dp))
                state.note?.let { Text(it, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 4.dp)) }
            }
        }
    }
}

private fun shortDate(iso: String): String =
    runCatching {
        DateTimeFormatter.ofPattern("d MMM", Locale.forLanguageTag(com.fishers.app.i18n.Strings.language.code))
            .withZone(ZoneId.systemDefault())
            .format(Instant.parse(iso))
    }.getOrDefault(iso)

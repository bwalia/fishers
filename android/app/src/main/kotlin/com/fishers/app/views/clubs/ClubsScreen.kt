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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.SportsCricket
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.fishers.app.clubs.Club
import com.fishers.app.clubs.ClubsState
import com.fishers.app.clubs.UserRole
import com.fishers.app.clubs.sportLabel
import com.fishers.app.i18n.t
import com.fishers.app.theme.FishersTheme

/**
 * The clubs this person belongs to — `ClubsTeamsView.swift`: each club with
 * what you are in it, a way to start one, and for somebody in none, how to get
 * into one.
 */
@Composable
fun ClubsScreen(
    state: ClubsState,
    onOpen: (Club) -> Unit,
    onStartClub: () -> Unit,
    onSearch: (String) -> Unit,
    onShareProfile: () -> Unit,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
    profileError: String? = null,
) {
    if (state.isFirstLoad && state.isLoading) {
        Box(modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
        return
    }

    LazyColumn(
        modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(t("nav.clubs"), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f))
                if (state.clubs.isNotEmpty()) {
                    Button(onClick = onStartClub) {
                        Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                        Text(t("cl.start_a_club"), modifier = Modifier.padding(start = 6.dp))
                    }
                }
            }
        }

        state.error?.let { error ->
            item {
                Column {
                    ErrorLine(error)
                    TextButton(onClick = onRetry) { Text(t("rest.try_again")) }
                }
            }
        }

        if (state.clubs.isEmpty()) {
            if (state.error == null) {
                item { EmptyClubs(onStartClub, onShareProfile, profileError) }
            }
            return@LazyColumn
        }

        if (state.isSearchable) {
            item {
                OutlinedTextField(
                    value = state.query,
                    onValueChange = onSearch,
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                    placeholder = { Text(t("cl.search_by_name_or_description")) },
                )
            }
        }

        val shown = state.shown
        if (shown.isEmpty()) {
            item {
                Column(Modifier.padding(vertical = 16.dp)) {
                    Text(t("cl.no_clubs_match"), style = MaterialTheme.typography.titleMedium)
                    TextButton(onClick = { onSearch("") }) { Text(t("cl.clear_filters")) }
                }
            }
        }
        itemsIndexed(shown, key = { _, club -> club.id }) { index, club ->
            ClubRow(club, onOpen = { onOpen(club) })
            if (index < shown.lastIndex) HorizontalDivider()
        }

        item {
            SectionHeading(t("cl.your_player_profile"))
            OutlinedButton(onClick = onShareProfile, modifier = Modifier.heightIn(min = 48.dp)) {
                Icon(Icons.Filled.Link, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(t("cl.send_profile_to_another_club"), modifier = Modifier.padding(start = 8.dp))
            }
            profileError?.let { ErrorLine(it) }
            Hint(t("cl.secretary_can_invite_you"), Modifier.padding(top = 4.dp))
        }

        item { HowClubsWork() }
    }
}

/** One club in the list: its crest, what it is, and what you are in it. */
@Composable
private fun ClubRow(club: Club, onOpen: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .clickable(onClick = onOpen)
            .padding(vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ClubCrest(club.name, club.id)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    club.name,
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                club.roleLabel?.let { RolePill(it) }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    if (club.isPublic) Icons.Filled.Public else Icons.Filled.Lock,
                    contentDescription = null,
                    modifier = Modifier.size(14.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Hint(
                    if (club.isPublic) t("lc.anyone_can_find_it") else t("lc.invite_only"),
                    Modifier.padding(start = 4.dp),
                )
            }
            club.description?.takeIf { it.isNotBlank() }?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                club.memberCount?.let { n ->
                    Count(Icons.Filled.Groups, n, t("cl.n_members", count = n, vars = mapOf("n" to n)))
                }
                club.teamCount?.let { n ->
                    Count(Icons.Filled.Shield, n, t("cl.n_teams", count = n, vars = mapOf("n" to n)))
                }
                if (club.sportTypes.isNotEmpty()) {
                    Hint(club.sportTypes.joinToString(" · ") { sportLabel(it) })
                }
            }
        }
    }
}

@Composable
private fun Count(icon: androidx.compose.ui.graphics.vector.ImageVector, n: Int, spoken: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = spoken },
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Hint("$n", Modifier.padding(start = 3.dp))
    }
}

@Composable
internal fun RolePill(label: String) {
    Text(
        label.uppercase(),
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.Bold,
        color = MaterialTheme.colorScheme.onSecondaryContainer,
        modifier = Modifier
            .padding(start = 6.dp)
            .background(MaterialTheme.colorScheme.secondaryContainer, RoundedCornerShape(50))
            .padding(horizontal = 8.dp, vertical = 3.dp),
    )
}

/**
 * Somebody in no club yet: start one, or get into the one they play for.
 * Getting in is a link from the secretary, or an invitation that waits on
 * Home — said here, because a new player has no other way to know.
 */
@Composable
private fun EmptyClubs(onStartClub: () -> Unit, onShareProfile: () -> Unit, profileError: String?) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(t("cl.not_in_a_club_yet"), style = MaterialTheme.typography.titleLarge)
        Hint(t("cl.start_your_own_or_get_invited_into_the"))

        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Groups, contentDescription = null)
                    Text(t("cl.i_run_a_club"), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 8.dp))
                }
                Hint(t("cl.set_it_up_in_a_minute_you_become_its_s"))
                Button(onClick = onStartClub, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                    Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(t("cl.start_a_club"), modifier = Modifier.padding(start = 6.dp))
                }
            }
        }

        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.SportsCricket, contentDescription = null)
                    Text(t("cl.i_play_for_a_club"), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 8.dp))
                }
                Text(t("cl.join_with_the_club_link"), style = MaterialTheme.typography.bodyMedium)
                Text(t("cl.invitations_wait_on_home"), style = MaterialTheme.typography.bodyMedium)
                Hint(t("cl.send_your_profile_link_to_the_secretar"))
                OutlinedButton(onClick = onShareProfile, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                    Icon(Icons.Filled.Link, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(t("rest.send_my_profile_to_a_club"), modifier = Modifier.padding(start = 8.dp))
                }
                profileError?.let { ErrorLine(it) }
            }
        }

        HowClubsWork()
    }
}

/** The four facts that explain the rest of the app. */
@Composable
private fun HowClubsWork() {
    val steps = listOf(
        t("cl.secretary_runs_the_club") to t("cl.members_roles_teams_grounds"),
        t("cl.players_join_by_invite") to t("cl.added_by_email_or_link"),
        t("cl.captains_pick_the_side") to t("cl.everyone_says_captain_picks"),
        t("cl.matches_are_scored_live") to t("cl.ball_by_ball_public_page"),
    )
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionHeading(t("cl.how_clubs_work"))
        steps.forEachIndexed { index, (title, detail) ->
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.semantics(mergeDescendants = true) {},
            ) {
                Box(
                    Modifier.size(24.dp).background(MaterialTheme.colorScheme.primary, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("${index + 1}", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onPrimary)
                }
                Column {
                    Text(title, style = MaterialTheme.typography.titleSmall)
                    Hint(detail)
                }
            }
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun ClubsPreview() {
    FishersTheme {
        ClubsScreen(
            state = ClubsState(
                isFirstLoad = false,
                clubs = listOf(
                    Club("1", "Lords CC", listOf("cricket"), "Sunday friendlies", role = UserRole.ClubAdmin,
                        isCaptain = true, memberCount = 18, teamCount = 2),
                    Club("2", "Southall Strikers", listOf("cricket"), visibility = "public",
                        role = UserRole.Member, memberCount = 31, teamCount = 3),
                ),
            ),
            onOpen = {}, onStartClub = {}, onSearch = {}, onShareProfile = {}, onRetry = {},
        )
    }
}

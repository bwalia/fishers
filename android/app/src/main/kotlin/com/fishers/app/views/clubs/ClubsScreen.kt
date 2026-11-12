package com.fishers.app.views.clubs

import com.fishers.app.i18n.t
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import android.content.Intent
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.fishers.app.R
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.fishers.app.clubs.Club
import com.fishers.app.clubs.ClubDetailState
import com.fishers.app.clubs.ClubMemberDetail
import com.fishers.app.clubs.ClubsState
import com.fishers.app.theme.FishersTheme

/** The clubs this person belongs to — `ClubsTeamsView.swift`. */
@Composable
fun ClubsScreen(
    state: ClubsState,
    onOpen: (Club) -> Unit,
    modifier: Modifier = Modifier,
) {
    when {
        state.isFirstLoad && state.isLoading ->
            Box(modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }

        state.clubs.isEmpty() -> Box(modifier.fillMaxSize().padding(32.dp), Alignment.Center) {
            Text(
                state.error ?: t("cl.not_in_a_club_yet"),
                style = MaterialTheme.typography.bodyMedium,
            )
        }

        else -> LazyColumn(modifier.fillMaxSize()) {
            items(state.clubs, key = { it.id }) { club ->
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clickable { onOpen(club) }
                        .padding(16.dp),
                ) {
                    Text(club.name, style = MaterialTheme.typography.titleMedium)
                    club.description?.let {
                        Text(
                            it,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                        )
                    }
                }
                HorizontalDivider()
            }
        }
    }
}

/**
 * One club's roster.
 *
 * Whoever runs the club first, then captains, then everybody else — the order
 * somebody scans when they are working out who to ask. People who were invited
 * and have not answered sit apart, because they are not in the side yet and a
 * roster that counts them is wrong on a Saturday.
 */
@Composable
fun ClubDetailScreen(
    clubName: String,
    state: ClubDetailState,
    modifier: Modifier = Modifier,
    onOpenSeason: (() -> Unit)? = null,
    onMakeLink: (fresh: Boolean) -> Unit = {},
    onStopLink: () -> Unit = {},
) {
    if (state.isFirstLoad && state.isLoading) {
        Box(modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
        return
    }

    LazyColumn(
        modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item {
            Text(clubName, style = MaterialTheme.typography.headlineSmall)
        }
        // The season's record and leaderboards, under the name: what a member
        // opens a club to check after a Saturday, before who is on the books.
        onOpenSeason?.let { open ->
            item {
                OutlinedButton(onClick = open) { Text(t("ss.club_season")) }
            }
        }
        state.error?.let {
            item {
                Text(it, color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall)
            }
        }
        if (state.canShareLink) {
            item { JoinLinkCard(clubName, state, onMakeLink, onStopLink) }
        }
        if (state.teams.isNotEmpty()) {
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    state.teams.forEach { AssistChip(onClick = {}, label = { Text(it.name) }) }
                }
            }
        }
        if (state.onTheBooks.isNotEmpty()) {
            item { Heading("${state.onTheBooks.size} on the books") }
            items(state.onTheBooks, key = { it.userId }) { MemberRow(it) }
        }
        if (state.invited.isNotEmpty()) {
            item { Heading(t("rest.asked_not_answered")) }
            items(state.invited, key = { it.userId }) { MemberRow(it, muted = true) }
        }
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

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Heading(t("jl.title"))
        Text(t("jl.explainer"), style = MaterialTheme.typography.bodySmall)
        if (url == null) {
            Button(onClick = { onMake(false) }) { Text(t("jl.make_link")) }
        } else {
            Text(url, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = {
                    val message = t(
                        "jl.whatsapp_message",
                        vars = mapOf("club" to clubName, "brand" to brand, "url" to url),
                    )
                    val send = Intent(Intent.ACTION_SEND)
                        .setType("text/plain")
                        .putExtra(Intent.EXTRA_TEXT, message)
                    context.startActivity(Intent.createChooser(send, null))
                }) { Text(t("sc.share")) }
                OutlinedButton(onClick = { confirm = true }) { Text(t("jl.new_link")) }
            }
            TextButton(onClick = { confirm = false }) { Text(t("jl.turn_off")) }
            val uses = state.joinLink?.uses ?: 0
            Text(
                t("jl.joined_through_it", count = uses, vars = mapOf("n" to uses)),
                style = MaterialTheme.typography.bodySmall,
            )
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

@Composable
private fun Heading(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 8.dp),
    )
}

@Composable
private fun MemberRow(member: ClubMemberDetail, muted: Boolean = false) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            member.name,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = if (member.isCaptain) FontWeight.Bold else FontWeight.Normal,
            color = if (muted) MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
            else MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f),
        )
        // Only worth saying when it is not just "Member" — a column of the
        // same word down the side of a roster is noise.
        if (member.isCaptain || member.role.runsTheClub) {
            Text(
                if (member.isCaptain) t("sc.captain") else member.role.label,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.secondary,
            )
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun ClubDetailPreview() {
    FishersTheme {
        ClubDetailScreen(
            "Lords CC",
            ClubDetailState(
                isFirstLoad = false,
                members = listOf(
                    ClubMemberDetail("1", "Ravi Patel",
                        role = com.fishers.app.clubs.UserRole.ClubAdmin),
                    ClubMemberDetail("2", "Tom Hardy", isCaptain = true),
                    ClubMemberDetail("3", "Sam Ali"),
                ),
            ),
        )
    }
}

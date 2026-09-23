package com.fishers.app.views.clubs

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
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
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
                state.error ?: "You are not in a club yet.",
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
        state.error?.let {
            item {
                Text(it, color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall)
            }
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
            item { Heading("Asked, not answered") }
            items(state.invited, key = { it.userId }) { MemberRow(it, muted = true) }
        }
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
                if (member.isCaptain) "Captain" else member.role.label,
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

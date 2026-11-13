package com.fishers.app.views.match.start

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.fishers.app.i18n.t
import com.fishers.app.match.start.PhoneMatch
import com.fishers.app.views.match.MatchSetupRoute
import com.fishers.app.views.match.ScoreMatchRoute
import com.fishers.app.views.nav.Navigator

/**
 * "On this phone" — `ScoreHubView.swift`'s local section: the matches whose
 * book is here, each a tap from carrying on, with what it is still waiting to
 * send. Read from the disk, so it is there with no signal at all.
 */
@Composable
fun OnThisPhone(matches: List<PhoneMatch>, onOpen: (PhoneMatch) -> Unit, note: String? = null) {
    if (matches.isEmpty()) return
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(t("sc.on_this_phone"), style = MaterialTheme.typography.titleMedium)
            note?.let { Footnote(it) }
            matches.forEachIndexed { i, match ->
                if (i > 0) HorizontalDivider()
                PhoneMatchRow(match, onClick = { onOpen(match) })
            }
        }
    }
}

@Composable
private fun PhoneMatchRow(match: PhoneMatch, onClick: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(onClick = onClick)
            .semantics(mergeDescendants = true) {}
            .padding(vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(match.title, style = MaterialTheme.typography.titleMedium, maxLines = 2)
        Footnote(
            when {
                match.unsentBalls > 0 ->
                    t("sc.n_balls_waiting_to_send", count = match.unsentBalls, vars = mapOf("n" to match.unsentBalls))
                match.waiting -> t("ev.waiting_to_sync")
                match.settingUp -> t("sc.match_setup")
                else -> t("sync.saved")
            },
        )
        ErrorLine(match.problem)
    }
}

/** Where a match on this phone opens: the setup until an innings has started, the scorer after. */
fun Navigator.open(match: PhoneMatch) {
    push(if (match.settingUp) MatchSetupRoute(match.eventId) else ScoreMatchRoute(match.eventId))
}

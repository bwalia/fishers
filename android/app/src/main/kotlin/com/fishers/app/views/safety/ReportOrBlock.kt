package com.fishers.app.views.safety

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.fishers.app.i18n.t
import com.fishers.app.net.FishersApi
import com.fishers.app.safety.BlockRequest
import com.fishers.app.safety.ReportReason
import com.fishers.app.safety.ReportRequest
import com.fishers.app.safety.ReportSubjectKind
import kotlinx.coroutines.launch

/**
 * Reporting something, and blocking whoever posted it.
 *
 * Two dialogs behind one pair of buttons, because they are one decision in the
 * person's head — "I do not want this". `personId` is null where there is
 * nobody to block: the app's own notes, or a club rather than a member.
 *
 * It takes the API rather than a view model. There is no state worth keeping
 * between openings — a report is sent once, and a block is handed to whoever
 * has a list to update.
 */
@Composable
fun ReportOrBlock(
    api: FishersApi,
    kind: ReportSubjectKind,
    subjectId: String,
    personId: String? = null,
    personName: String? = null,
    onBlocked: (String) -> Unit = {},
) {
    val scope = rememberCoroutineScope()
    var reporting by remember { mutableStateOf(false) }
    var confirmingBlock by remember { mutableStateOf(false) }
    var reason by remember { mutableStateOf(ReportReason.ABUSE) }
    var note by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var outcome by remember { mutableStateOf<String?>(null) }
    var sent by remember { mutableStateOf(false) }

    if (sent) {
        Text(t("mod.reported"), style = MaterialTheme.typography.labelSmall)
        return
    }

    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        TextButton(onClick = { reporting = true }) { Text(t("mod.report")) }
        if (personId != null) {
            TextButton(onClick = { confirmingBlock = true }) { Text(t("mod.block")) }
        }
    }

    if (reporting) {
        AlertDialog(
            onDismissRequest = { reporting = false },
            title = { Text(t("mod.report_this")) },
            text = {
                Column {
                    Text(t("mod.what_is_wrong"), style = MaterialTheme.typography.labelLarge)
                    ReportReason.entries.forEach { option ->
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                // The whole row, not only the dot: a 20dp
                                // target is not a target.
                                .selectable(
                                    selected = reason == option,
                                    onClick = { reason = option },
                                )
                                .padding(vertical = 8.dp),
                        ) {
                            RadioButton(selected = reason == option, onClick = null)
                            Text(option.label, Modifier.padding(start = 8.dp))
                        }
                    }
                    OutlinedTextField(
                        value = note,
                        onValueChange = { if (it.length <= 2000) note = it },
                        label = { Text(t("mod.anything_else")) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp),
                    )
                }
            },
            confirmButton = {
                TextButton(
                    enabled = !busy,
                    onClick = {
                        busy = true
                        scope.launch {
                            try {
                                api.report(
                                    ReportRequest(
                                        subjectKind = kind.wire,
                                        subjectId = subjectId,
                                        reason = reason.wire,
                                        note = note.trim().ifEmpty { null },
                                    )
                                )
                                reporting = false
                                sent = true
                                outcome = t("mod.report_sent")
                            } catch (_: Exception) {
                                outcome = t("mod.report_would_not_send")
                            }
                            busy = false
                        }
                    },
                ) { Text(t("mod.send_report")) }
            },
            dismissButton = {
                TextButton(onClick = { reporting = false }) { Text(t("sc.cancel")) }
            },
        )
    }

    if (confirmingBlock && personId != null) {
        AlertDialog(
            onDismissRequest = { confirmingBlock = false },
            title = {
                Text(
                    personName?.let { t("mod.block_name", vars = mapOf("name" to it)) }
                        ?: t("mod.block")
                )
            },
            text = { Text(t("mod.block_explains")) },
            confirmButton = {
                TextButton(
                    enabled = !busy,
                    onClick = {
                        busy = true
                        scope.launch {
                            try {
                                api.block(BlockRequest(userId = personId))
                                confirmingBlock = false
                                onBlocked(personId)
                            } catch (_: Exception) {
                                outcome = t("mod.block_would_not_save")
                            }
                            busy = false
                        }
                    },
                ) { Text(t("mod.block")) }
            },
            dismissButton = {
                TextButton(onClick = { confirmingBlock = false }) { Text(t("sc.cancel")) }
            },
        )
    }

    outcome?.let { message ->
        AlertDialog(
            onDismissRequest = { outcome = null },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { outcome = null }) { Text(t("rest.ok")) } },
        )
    }
}

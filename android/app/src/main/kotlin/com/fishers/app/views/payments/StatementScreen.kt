package com.fishers.app.views.payments

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.clubs.money
import com.fishers.app.i18n.t
import com.fishers.app.net.PaymentsApi
import com.fishers.app.payments.StatementLine
import com.fishers.app.payments.StatementPreview
import com.fishers.app.payments.StatementState
import com.fishers.app.payments.StatementViewModel
import com.fishers.app.payments.dayMonth
import com.fishers.app.payments.matchWords
import com.fishers.app.payments.whyWords
import com.fishers.app.views.clubs.ClubScreen
import com.fishers.app.views.clubs.SectionHeading
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

/**
 * Payments → Import a bank statement (§12): pick the CSV from the bank, then
 * three groups — ticked off (each can be unticked), needs a look (with why),
 * not recognised (folded away) — and one button, Apply.
 */
@Composable
internal fun StatementPage(clubId: String) {
    val deps = LocalAppDeps.current
    val nav = LocalNavigator.current
    val model = remember(clubId) { StatementViewModel(deps.service<PaymentsApi>(), clubId) }
    val state by model.state.collectAsStateWithLifecycle()
    val pick = rememberStatementPicker(onReady = model::read, onProblem = model::fileProblem)

    ClubScreen(title = t("pw4.import_statement")) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val preview = state.preview
            when {
                state.isReading -> Row(Modifier.fillMaxWidth().padding(vertical = 24.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(32.dp))
                    Text(t("pw4.reading_statement"), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(start = 16.dp))
                }
                state.done != null -> {
                    Text(state.done ?: "", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
                    Button(onClick = { nav.pop() }, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
                        Text(t("pa4.back_to_payments"), style = MaterialTheme.typography.titleMedium)
                    }
                    TextButton(onClick = pick, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("pa4.import_another")) }
                }
                preview == null -> {
                    state.error?.let { Failure(it) }
                    Text(t("pw4.import_help"), style = MaterialTheme.typography.bodyLarge)
                    Button(onClick = pick, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
                        Icon(Icons.Filled.UploadFile, contentDescription = null)
                        Text(t("pw4.choose_statement"), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(start = 8.dp))
                    }
                }
                else -> Review(preview, state, onToggle = model::toggle, onApply = model::apply, onAnother = pick)
            }
        }
    }
}

@Composable
private fun Failure(text: String) {
    Text(text, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.error)
}

/** What the statement matched, in three groups, and Apply. */
@Composable
private fun Review(
    preview: StatementPreview,
    state: StatementState,
    onToggle: (String) -> Unit,
    onApply: () -> Unit,
    onAnother: () -> Unit,
) {
    val currency = preview.currency
    val n = preview.lines.size
    Text(
        if (n == 0) t("pw4.statement_no_money_in") else t("pw4.statement_money_in", count = n, vars = mapOf("n" to n)),
        style = MaterialTheme.typography.bodyLarge,
    )

    // ---- ticked off ----
    if (preview.toApply.isNotEmpty()) {
        Heading(t("pw4.ticked_off", vars = mapOf("n" to preview.toApply.size)))
        Body(t("pw4.ticked_off_help"))
        preview.toApply.forEach { line ->
            val ticked = line.hash in state.ticked
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 56.dp)
                    .toggleable(value = ticked, role = Role.Checkbox, enabled = !state.isApplying, onValueChange = { onToggle(line.hash) }),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Checkbox(checked = ticked, onCheckedChange = null)
                LineWords(
                    line,
                    currency,
                    under = line.matchWords(),
                    modifier = Modifier.padding(start = 12.dp).weight(1f),
                )
            }
            HorizontalDivider()
        }
    }

    // ---- needs a look ----
    if (preview.toCheck.isNotEmpty()) {
        Heading(t("pw4.needs_a_look", vars = mapOf("n" to preview.toCheck.size)))
        Body(t("pw4.needs_a_look_help"))
        preview.toCheck.forEach { line ->
            LineWords(line, currency, under = line.whyWords(currency, state.names, state.claims), warn = true)
            HorizontalDivider()
        }
    }

    // ---- not recognised, and done before: folded away ----
    if (preview.unrecognised.isNotEmpty()) {
        Folded(t("pw4.not_recognised", vars = mapOf("n" to preview.unrecognised.size)), t("pw4.not_recognised_help"), preview.unrecognised, currency)
    }
    if (preview.already.isNotEmpty()) {
        Folded(t("pw4.already_done", vars = mapOf("n" to preview.already.size)), null, preview.already, currency)
    }

    state.error?.let { Failure(it) }
    val ticked = state.toSend.size
    if (preview.toApply.isNotEmpty()) {
        Button(onClick = onApply, enabled = ticked > 0 && !state.isApplying, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
            Text(if (state.isApplying) t("pa4.applying") else t("pw4.apply_n", vars = mapOf("n" to ticked)), style = MaterialTheme.typography.titleMedium)
        }
    }
    OutlinedButton(onClick = onAnother, enabled = !state.isApplying, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
        Text(t("pw4.choose_another"))
    }
}

@Composable
private fun Heading(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 8.dp).semantics { heading() },
    )
}

/** "Ravi Sharma   £15.00" over "21 Nov · They said they'd paid". */
@Composable
private fun LineWords(line: StatementLine, currency: String, under: String?, warn: Boolean = false, modifier: Modifier = Modifier) {
    Column(modifier.padding(vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(line.who, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f).padding(end = 8.dp))
            Text(money(line.amountCents, currency), style = MaterialTheme.typography.titleMedium)
        }
        Body(listOfNotNull(dayMonth(line.date).takeIf { it.isNotEmpty() }, line.text.takeIf { line.name != null && it.isNotBlank() }).joinToString(" · "))
        under?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = if (warn) AMBER else MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}

/** A group nobody needs to act on: its count, opened with a tap. */
@Composable
private fun Folded(title: String, hint: String?, lines: List<StatementLine>, currency: String) {
    var open by rememberSaveable(title) { mutableStateOf(false) }
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(role = Role.Button) { open = !open }
            .padding(top = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            hint?.let { Body(it) }
        }
        Icon(if (open) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, contentDescription = null)
    }
    if (open) {
        lines.forEach { line ->
            LineWords(line, currency, under = null)
            HorizontalDivider()
        }
    }
}

// ---- picking the file ----

/** More than a club's year of banking: anything bigger is not a statement. */
private const val MAX_STATEMENT_BYTES = 2_000_000

/**
 * The system file picker, for the CSV a bank's website exports: banks label
 * it CSV, Excel or plain text. The file is read as text here, on the phone,
 * and handed on — never kept anywhere else.
 */
@Composable
private fun rememberStatementPicker(onReady: (String) -> Unit, onProblem: (String) -> Unit): () -> Unit {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            when (val read = withContext(Dispatchers.IO) { readStatement(context, uri) }) {
                is ReadStatement.Ready -> onReady(read.text)
                ReadStatement.TooBig -> onProblem(t("pw4.statement_too_long"))
                ReadStatement.Unreadable -> onProblem(t("pw4.statement_unknown"))
            }
        }
    }
    return { launcher.launch(arrayOf("text/csv", "text/comma-separated-values", "application/vnd.ms-excel", "text/plain")) }
}

private sealed interface ReadStatement {
    class Ready(val text: String) : ReadStatement {
        override fun toString() = "Ready(${text.length} chars)"
    }
    data object TooBig : ReadStatement
    data object Unreadable : ReadStatement
}

private fun readStatement(context: Context, uri: Uri): ReadStatement {
    val bytes = runCatching {
        context.contentResolver.openInputStream(uri)?.use { input ->
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(16 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                if (out.size() + n > MAX_STATEMENT_BYTES) return ReadStatement.TooBig
                out.write(buffer, 0, n)
            }
            out.toByteArray()
        }
    }.getOrNull() ?: return ReadStatement.Unreadable
    return ReadStatement.Ready(decodeStatement(bytes))
}

/**
 * UTF-8 when it is; otherwise Windows-1252, which is what a lot of UK banks
 * still export — the £ in an amount column would otherwise come out garbled.
 */
internal fun decodeStatement(bytes: ByteArray): String = try {
    Charsets.UTF_8.newDecoder()
        .onMalformedInput(CodingErrorAction.REPORT)
        .onUnmappableCharacter(CodingErrorAction.REPORT)
        .decode(ByteBuffer.wrap(bytes))
        .toString()
} catch (_: CharacterCodingException) {
    String(bytes, Charset.forName("windows-1252"))
}

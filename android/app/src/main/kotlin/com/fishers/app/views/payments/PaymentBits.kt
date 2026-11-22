package com.fishers.app.views.payments

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.PersistableBundle
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.fishers.app.i18n.t
import com.fishers.app.payments.Share
import com.fishers.app.payments.ShareState

/**
 * Put text on the clipboard. The account number and "copy all" are marked
 * sensitive, so Android 13's clipboard preview does not show them to whoever
 * is looking over a shoulder; older phones get a toast, as they show nothing.
 */
internal fun copy(context: Context, label: String, text: String, sensitive: Boolean = false) {
    val clip = ClipData.newPlainText(label, text)
    if (sensitive && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        clip.description.extras = PersistableBundle().apply { putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true) }
    }
    context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(clip)
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
        Toast.makeText(context, t("pay.copied"), Toast.LENGTH_SHORT).show()
    }
}

/** A state as a word, coloured as the money it means: paid green, waiting amber, owed red. */
@Composable
internal fun StateLabel(state: ShareState) {
    if (state == ShareState.Unknown) return
    Text(
        state.label,
        style = MaterialTheme.typography.labelLarge,
        color = when (state) {
            ShareState.Paid, ShareState.Covered -> Color(0xFF2E7D32)
            ShareState.Waiting, ShareState.PartPaid -> AMBER
            ShareState.Owed -> MaterialTheme.colorScheme.error
            else -> MaterialTheme.colorScheme.onSurfaceVariant
        },
    )
}

/**
 * A line's state as a word. A covered line says why it is nothing to pay,
 * from the server's `cover` and never its English: "Free ✓" for a free price
 * (a coach), otherwise "Covered by your pass ✓" — or, for the people running
 * it ([admin]), "Covered by a pass ✓".
 */
@Composable
internal fun StateLabel(share: Share, admin: Boolean = false) {
    if (!share.isCovered) return StateLabel(share.state)
    Text(
        when {
            share.isFreePrice -> t("pa3.free_tick")
            admin -> t("pw4.covered_by_a_pass")
            else -> t("pa3.covered_by_your_pass")
        },
        style = MaterialTheme.typography.labelLarge,
        color = Color(0xFF2E7D32),
    )
}

/** Dark enough to read on the light amber card, and on the dark theme's surface. */
internal val AMBER = Color(0xFF9A5B00)

/** "These bank details changed on…", "Waiting for the club to confirm" — said, not shouted. */
@Composable
internal fun AmberNote(text: String, modifier: Modifier = Modifier) {
    Card(
        modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF3E0), contentColor = Color(0xFF5C3600)),
    ) {
        Text(text, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(12.dp))
    }
}

/** For something that must stop a payment: frozen details. */
@Composable
internal fun StopNote(text: String, modifier: Modifier = Modifier) {
    Card(
        modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
    ) {
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onErrorContainer,
            modifier = Modifier.padding(12.dp),
        )
    }
}

/** A label and an amount on one line: "Collected   £30.00". */
@Composable
internal fun AmountLine(label: String, amount: String, strong: Boolean = false) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Text(
            amount,
            style = if (strong) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyMedium,
            fontWeight = if (strong) FontWeight.SemiBold else null,
        )
    }
}

/**
 * Asks why before doing something people are told about: letting somebody
 * off, turning a payment down, cancelling a bill. [required] keeps the button
 * dead until there is a reason, because the server will ask for one anyway.
 */
@Composable
internal fun ReasonDialog(
    title: String,
    explainer: String? = null,
    placeholder: String? = null,
    confirm: String,
    required: Boolean = true,
    destructive: Boolean = false,
    onConfirm: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var reason by rememberSaveable { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                explainer?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                OutlinedTextField(
                    value = reason,
                    onValueChange = { if (it.length <= 200) reason = it },
                    label = { Text(t(if (required) "sc.reason" else "pay.reason_optional")) },
                    placeholder = placeholder?.let { { Text(it) } },
                    minLines = 2,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(reason) },
                enabled = !required || reason.isNotBlank(),
                colors = if (destructive) ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)
                else ButtonDefaults.textButtonColors(),
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(confirm) }
        },
        dismissButton = {
            // Not "Cancel": beside "Cancel the bill" it reads as the same thing.
            TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("pay.not_now")) }
        },
    )
}

/** An amount of money, typed: a decimal keyboard and the currency's symbol in front. */
@Composable
internal fun AmountField(
    value: String,
    onValue: (String) -> Unit,
    label: String,
    currency: String?,
    error: String? = null,
    modifier: Modifier = Modifier,
) {
    OutlinedTextField(
        value = value,
        onValueChange = { typed -> onValue(typed.filter { it.isDigit() || it == '.' || it == ',' }.take(10)) },
        label = { Text(label) },
        prefix = currency?.let { code -> symbolOf(code)?.let { { Text(it) } } },
        singleLine = true,
        isError = error != null,
        supportingText = error?.let { { Text(it) } },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        modifier = modifier.fillMaxWidth(),
    )
}

/** "£" for GBP, "₹" for INR; null when the phone does not know it, rather than a code in the box. */
private fun symbolOf(currency: String): String? =
    runCatching { java.util.Currency.getInstance(currency).getSymbol(java.util.Locale.UK) }
        .getOrNull()
        ?.takeIf { it != currency }

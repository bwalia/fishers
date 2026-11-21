package com.fishers.app.views.payments

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.fishers.app.clubs.money
import com.fishers.app.i18n.t
import com.fishers.app.payments.BankDetails
import com.fishers.app.payments.ClubMoneyState
import com.fishers.app.payments.ClubMoneyViewModel
import com.fishers.app.payments.CostMode
import com.fishers.app.payments.MoneySettings
import com.fishers.app.payments.OpenScreenshot
import com.fishers.app.payments.PricesForm
import com.fishers.app.payments.SetupStep
import com.fishers.app.payments.amountText
import com.fishers.app.payments.payeeLine
import com.fishers.app.payments.usualNetsWords
import com.fishers.app.payments.whoseAccount
import com.fishers.app.views.clubs.SectionHeading

/**
 * Setting up payments, the first time (§5.3): where players send money, with
 * exactly what they will see; what the club usually charges; then how a bill
 * reaches the group. Each step can be skipped, and the whole of it put off.
 */
@Composable
internal fun SetupWizard(step: SetupStep, state: ClubMoneyState, model: ClubMoneyViewModel) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            t("pa2.step_n_of_3", vars = mapOf("n" to step.ordinal + 1)),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
        )
        when (step) {
            SetupStep.Bank -> BankStep(state, model)
            SetupStep.Prices -> PricesStep(state, model)
            SetupStep.Done -> DoneStep(onDone = model::finishSetup)
        }
        if (step != SetupStep.Done) {
            TextButton(onClick = model::putOffSetup, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("pay.not_now")) }
        }
    }
}

@Composable
private fun BankStep(state: ClubMoneyState, model: ClubMoneyViewModel) {
    val form = state.form ?: com.fishers.app.payments.BankForm()
    val entry = rememberBankEntry()
    Text(t("pa2.setup_bank_title"), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
    Body(t("pa2.setup_bank_body"))
    BankDetailsFields(entry, form, changing = false)

    // Exactly what a player is shown, as it is typed.
    SectionHeading(t("pa2.players_will_see"))
    val preview = BankDetails(
        holderName = entry.holder.trim().ifEmpty { "…" },
        sortCode = entry.sortCode.filter(Char::isDigit).chunked(2).joinToString("-").ifEmpty { "…" },
        accountNumber = entry.number.filter(Char::isDigit).ifEmpty { "…" },
        isPersonal = entry.personal,
    )
    Card(
        Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(preview.payeeLine(), style = MaterialTheme.typography.titleMedium)
            Body(preview.whoseAccount())
            HorizontalDivider()
            PreviewLine(t("pa2.row_name"), preview.holderName)
            PreviewLine(t("pay.sort_code"), preview.sortCode, mono = true)
            PreviewLine(t("pay.account_number"), preview.accountNumber, mono = true)
            PreviewLine(t("pa2.row_reference"), t("pa2.reference_example"))
        }
    }

    Button(
        onClick = { model.saveBankDetails(entry.holder, entry.sortCode, entry.number, entry.again, entry.personal, entry.password) },
        enabled = !form.isSaving,
        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
    ) { Text(if (form.isSaving) t("la.saving") else t("pa2.save_and_continue")) }
    OutlinedButton(onClick = model::skipSetupStep, enabled = !form.isSaving, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
        Text(t("pa2.skip_step"))
    }
}

@Composable
private fun PreviewLine(label: String, value: String, mono: Boolean = false) {
    Column {
        Body(label)
        Text(value, style = MaterialTheme.typography.bodyLarge, fontFamily = if (mono) FontFamily.Monospace else null)
    }
}

@Composable
private fun PricesStep(state: ClubMoneyState, model: ClubMoneyViewModel) {
    val form = state.prices ?: PricesForm()
    val prices = rememberPricesEntry(state.overview?.settings)
    Text(t("pa2.setup_prices_title"), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
    Body(t("pa2.setup_prices_body"))
    UsualPricesFields(prices, form, state.currency)
    Button(
        onClick = { model.saveUsualPrices(prices.mode, prices.nets, prices.fee) },
        enabled = !form.isSaving,
        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
    ) { Text(if (form.isSaving) t("la.saving") else t("pa2.save_and_continue")) }
    OutlinedButton(onClick = model::skipSetupStep, enabled = !form.isSaving, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
        Text(t("pa2.skip_step"))
    }
}

@Composable
private fun DoneStep(onDone: () -> Unit) {
    Text(t("pa2.setup_done_title"), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
    Text(t("pa2.setup_done_body"), style = MaterialTheme.typography.bodyLarge)
    Button(onClick = onDone, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text(t("pa2.done")) }
}

/** On the Payments page, for a money admin who put the wizard off. */
@Composable
internal fun SetupCard(onStart: () -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(t("pa2.setup_title"), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
            Body(t("pa2.setup_card_body"))
            Button(onClick = onStart, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text(t("pa2.setup_title")) }
        }
    }
}

// ---- the usual prices ----

/** The prices as typed: plain amounts and a choice, kept across the phone turning round. */
internal class PricesEntry(mode: CostMode, nets: String, fee: String) {
    var mode by mutableStateOf(mode)
    var nets by mutableStateOf(nets)
    var fee by mutableStateOf(fee)

    companion object {
        val Saver: Saver<PricesEntry, Any> = listSaver(
            save = { listOf(it.mode.wire, it.nets, it.fee) },
            restore = { PricesEntry(CostMode.of(it[0] as String), it[1] as String, it[2] as String) },
        )
    }
}

/** Starting from the club's usual prices, when it has some. */
@Composable
private fun rememberPricesEntry(settings: MoneySettings?): PricesEntry =
    rememberSaveable(saver = PricesEntry.Saver) {
        val usual = settings?.usualNets
        PricesEntry(
            mode = usual?.mode ?: CostMode.SplitTotal,
            nets = usual?.let { amountText(it.amountCents) } ?: "",
            fee = settings?.defaultMatchFeeCents?.takeIf { it > 0 }?.let(::amountText) ?: "",
        )
    }

@Composable
private fun UsualPricesFields(prices: PricesEntry, form: PricesForm, currency: String) {
    Text(t("pa2.usual_nets"), style = MaterialTheme.typography.titleMedium)
    CostModeChoice(prices.mode, onMode = { prices.mode = it })
    AmountField(
        value = prices.nets,
        onValue = { prices.nets = it },
        label = if (prices.mode == CostMode.SplitTotal) t("pay.total_cost") else t("pay.each_pays"),
        currency = currency,
        error = form.netsProblem,
    )
    Text(t("pa2.usual_match_fee"), style = MaterialTheme.typography.titleMedium)
    AmountField(
        value = prices.fee,
        onValue = { prices.fee = it },
        label = t("pay.each_pays"),
        currency = currency,
        error = form.feeProblem,
    )
}

/** Settings → Usual prices: what they are, and the way to change them. */
@Composable
internal fun UsualPricesPart(settings: MoneySettings, currency: String, onChange: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        SectionHeading(t("pa2.usual_prices"))
        val nets = usualNetsWords(settings, currency)
        val fee = settings.defaultMatchFeeCents?.takeIf { it > 0 }
        if (nets == null && fee == null) {
            Body(t("pa2.usual_prices_none"))
        } else {
            nets?.let { Text(t("pa2.usual_nets_line", vars = mapOf("cost" to it)), style = MaterialTheme.typography.bodyLarge) }
            fee?.let { Text(t("pa2.usual_match_line", vars = mapOf("amount" to money(it, currency))), style = MaterialTheme.typography.bodyLarge) }
        }
        TextButton(onClick = onChange, modifier = Modifier.heightIn(min = 48.dp)) {
            Text(if (settings.hasUsualPrices) t("pa2.change_usual_prices") else t("pa2.set_usual_prices"))
        }
    }
}

@Composable
internal fun UsualPricesDialog(
    form: PricesForm,
    settings: MoneySettings,
    currency: String,
    onSave: (CostMode, String, String) -> Unit,
    onDismiss: () -> Unit,
) {
    val prices = rememberPricesEntry(settings)
    AlertDialog(
        onDismissRequest = { if (!form.isSaving) onDismiss() },
        title = { Text(t("pa2.usual_prices")) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Body(t("pa2.setup_prices_body"))
                UsualPricesFields(prices, form, currency)
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(prices.mode, prices.nets, prices.fee) },
                enabled = !form.isSaving,
                modifier = Modifier.heightIn(min = 48.dp),
            ) { Text(if (form.isSaving) t("la.saving") else t("lc.save")) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !form.isSaving, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.cancel")) }
        },
    )
}

// ---- a payment's screenshot ----

/** The picture that came with a payment, as large as the screen allows. */
@Composable
internal fun ScreenshotDialog(open: OpenScreenshot, onClose: () -> Unit) {
    val bytes = open.bytes
    val image = remember(bytes) {
        bytes?.let { runCatching { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() }.getOrNull() }
    }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text(t("pa2.screenshot_from", vars = mapOf("name" to open.payment.name))) },
        text = {
            Box(Modifier.fillMaxWidth().heightIn(min = 200.dp), contentAlignment = Alignment.Center) {
                when {
                    bytes == null -> CircularProgressIndicator()
                    image == null -> Body(t("pa2.screenshot_cant_open"))
                    else -> Image(
                        bitmap = image,
                        contentDescription = t("pa2.screenshot_from", vars = mapOf("name" to open.payment.name)),
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        },
        confirmButton = { TextButton(onClick = onClose, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("sc.close")) } },
    )
}

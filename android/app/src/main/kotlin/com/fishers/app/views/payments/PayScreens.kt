package com.fishers.app.views.payments

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.fishers.app.clubs.money
import com.fishers.app.i18n.t
import com.fishers.app.net.PaymentsApi
import com.fishers.app.payments.AccountState
import com.fishers.app.payments.BankDetails
import com.fishers.app.payments.ClubDues
import com.fishers.app.payments.Dues
import com.fishers.app.payments.DuesViewModel
import com.fishers.app.payments.PassHolder
import com.fishers.app.payments.PassPlan
import com.fishers.app.payments.PayScreen
import com.fishers.app.payments.PersonDues
import com.fishers.app.payments.PayState
import com.fishers.app.payments.PayViewModel
import com.fishers.app.payments.Payment
import com.fishers.app.payments.PaymentMethod
import com.fishers.app.payments.Share
import com.fishers.app.payments.detailsToSend
import com.fishers.app.payments.oweHeadline
import com.fishers.app.payments.payeeLine
import com.fishers.app.payments.payeeShortName
import com.fishers.app.payments.shortDay
import com.fishers.app.payments.waitingLine
import com.fishers.app.payments.waitingWords
import com.fishers.app.payments.whoseAccount
import com.fishers.app.views.components.ButtonLabel
import com.fishers.app.views.components.ButtonRow
import kotlinx.coroutines.delay
import com.fishers.app.views.clubs.ClubScreen
import com.fishers.app.views.clubs.ErrorLine
import com.fishers.app.views.clubs.SectionHeading
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator

/**
 * Pay one club, top to bottom in plain words (§5.2 of
 * docs/CLUB_PAYMENTS_V2_PLAN.md): what you owe and what for, who the money
 * goes to, the four things to copy into a banking app, a first-time guide,
 * then "I've paid" or "I paid cash". After saying so: a screenshot, if you
 * like, and Undo.
 */
@Composable
internal fun PayPage(clubId: String, clubName: String, forEveryone: Boolean = false) {
    val deps = LocalAppDeps.current
    val context = LocalContext.current
    val model = remember(clubId, forEveryone) {
        PayViewModel(
            deps.service<PaymentsApi>(),
            clubId,
            guide = payGuidePrefs(context.applicationContext),
            me = deps.user()?.id,
            forEveryone = forEveryone,
        )
    }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(clubId) { model.load() }

    // Which waiting payment the picker is choosing a picture for. Saved:
    // the phone may let this screen go while the picker is open.
    var picturing by rememberSaveable { mutableStateOf<String?>(null) }
    val pickPicture = rememberScreenshotPicker(
        onReady = { bytes -> picturing?.let { model.attachScreenshot(it, bytes) } },
        onProblem = model::screenshotProblem,
    )

    val name = state.pay?.clubName?.takeIf { it.isNotBlank() } ?: clubName
    ClubScreen(title = if (name.isBlank()) t("pay.pay_the_club") else t("pay.pay_club", vars = mapOf("club" to name))) {
        val pay = state.pay
        when {
            pay == null && state.isLoading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
            pay == null -> Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ErrorLine(state.error ?: t("rest.something_went_wrong_plain"))
                TextButton(onClick = model::load, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("rest.try_again")) }
            }
            else -> PayBody(
                pay = pay,
                state = state,
                onClaim = model::claim,
                onUndo = model::undo,
                onAddPicture = { claim -> picturing = claim.id; pickPicture() },
                onToggleFriend = model::toggleFriend,
                onNoFriends = model::clearFriends,
                onGetPass = model::getPass,
                onCancelPass = model::cancelPass,
                onPayForEveryone = model::payForEveryone,
            )
        }
    }
}

@Composable
private fun PayBody(
    pay: PayScreen,
    state: PayState,
    onClaim: (PaymentMethod) -> Unit,
    onUndo: (Payment) -> Unit,
    onAddPicture: (Payment) -> Unit,
    onToggleFriend: (String) -> Unit,
    onNoFriends: () -> Unit,
    onGetPass: (PassPlan, String?) -> Unit,
    onCancelPass: (PassHolder) -> Unit,
    onPayForEveryone: () -> Unit,
) {
    val context = LocalContext.current
    val paying = state.payingCents
    val scroll = rememberScrollState()
    // "Thanks", "Undone" and any trouble are said at the top, and the buttons
    // that cause them are far below: go up to where it is said, with the
    // waiting payment and its Undo, rather than leave the person among the
    // passes the page has just shrunk to.
    LaunchedEffect(state.message, state.error) {
        if (state.message != null || state.error != null) scroll.animateScrollTo(0)
    }
    Column(
        Modifier.fillMaxSize().verticalScroll(scroll).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        // ---- 1. how much, and what for ----
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            when {
                state.forEveryone && state.othersOwing.isNotEmpty() -> {
                    Text(
                        t("pa3.pay_for_everyone_headline", vars = mapOf("amount" to money(paying, pay.currency))),
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.semantics { heading() },
                    )
                    EveryoneLines(pay, state)
                }
                pay.owedCents > 0 -> Text(
                    pay.oweHeadline(),
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.semantics { heading() },
                )
                pay.waitingCents <= 0 && pay.claims.isEmpty() && pay.standingOrderCents > 0 ->
                    Text(
                        t("pw5.so_pays_amount", vars = mapOf("amount" to money(pay.standingOrderCents, pay.currency))),
                        style = MaterialTheme.typography.headlineSmall,
                    )
                pay.waitingCents <= 0 && pay.claims.isEmpty() ->
                    Text(t("pay.all_paid_up"), style = MaterialTheme.typography.headlineSmall)
            }
            if (!state.forEveryone && state.friendsTicked.isNotEmpty()) {
                Text(
                    t("pa3.with_friends_total", count = state.friendsTicked.size, vars = mapOf("amount" to money(paying, pay.currency), "n" to state.friendsTicked.size)),
                    style = MaterialTheme.typography.titleMedium,
                )
            }
            if (pay.creditCents > 0) {
                Body(t("pay.you_have_credit", vars = mapOf("amount" to money(pay.creditCents, pay.currency))))
            }
        }

        state.message?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary) }
        state.error?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.error) }

        // A parent here for their own payment (or who has just undone one
        // made for a junior): the people they pay for still owe, and this is
        // the way to pay for them too.
        if (!state.forEveryone && state.othersOwing.isNotEmpty()) {
            val everyone = (pay.owedCents) + state.othersOwing.sumOf { it.dues.owedCents }
            OutlinedButton(
                onClick = onPayForEveryone,
                enabled = !state.isClaiming,
                modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
            ) { Text(t("pa3.pay_for_everyone", vars = mapOf("amount" to money(everyone, pay.currency))), style = MaterialTheme.typography.titleMedium) }
        }

        // ---- 6. said you've paid: waiting, with a picture and Undo ----
        // Payments made for somebody else (a junior, a friend) are among them.
        if (pay.claims.isNotEmpty()) {
            WaitingCard(pay, state, onUndo = onUndo, onAddPicture = onAddPicture)
        }

        // Friends on the same session, paid for in the same payment.
        if (!state.forEveryone && state.friends.isNotEmpty() && paying > 0) {
            FriendsPart(state, pay.currency, onToggle = onToggleFriend, onClose = onNoFriends)
        }

        if (paying > 0) {
            val account = pay.account
            when (pay.accountState) {
                AccountState.Active -> if (account != null) {
                    // ---- 2. who the money goes to ----
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(account.payeeLine(), style = MaterialTheme.typography.titleLarge)
                        Body(account.whoseAccount())
                    }
                    account.changedAt?.let { AmberNote(t("pay.details_changed_on", vars = mapOf("date" to shortDay(it)))) }

                    // ---- 3. the four things to copy ----
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(vertical = 8.dp, horizontal = 16.dp)) {
                            BigCopyRow(t("pa2.row_name"), account.holderName)
                            HorizontalDivider()
                            BigCopyRow(t("pay.sort_code"), account.sortCode, mono = true)
                            HorizontalDivider()
                            BigCopyRow(t("pay.account_number"), account.accountNumber, mono = true, sensitive = true)
                            HorizontalDivider()
                            BigCopyRow(t("pa2.row_reference"), pay.reference, mono = true)
                        }
                    }

                    // ---- 4. first time? ----
                    PayGuide(pay, account, seen = state.guideSeen, amountCents = paying)

                    // ---- 5. the two big buttons ----
                    Button(
                        onClick = { onClaim(PaymentMethod.Transfer) },
                        enabled = !state.isClaiming,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
                    ) {
                        Text(
                            when {
                                state.isClaiming -> t("pay.sending")
                                state.forEveryone && state.payingForOthers -> t("pw3.ive_paid_for_everyone")
                                else -> t("pay.ive_paid")
                            },
                            style = MaterialTheme.typography.titleMedium,
                        )
                    }
                    CashButton(state, onClaim)

                    // ---- 7. somebody else does the banking ----
                    OutlinedButton(
                        onClick = { shareAnywhere(context, pay.detailsToSend(paying, forOthers = state.payingForOthers)) },
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    ) {
                        Icon(Icons.Filled.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                        Text(t("pa2.send_details"), modifier = Modifier.padding(start = 8.dp))
                    }
                    Body(t("pa2.send_details_hint"))
                }
                AccountState.Frozen -> StopNote(t("pay.details_being_checked"))
                AccountState.None -> {
                    Body(t("pay.no_details_pay_secretary"))
                    CashButton(state, onClaim)
                }
                AccountState.Unreadable -> {
                    Body(t("pay.details_need_entering_again"))
                    CashButton(state, onClaim)
                }
                // Anybody with something to pay — theirs, a junior's, a
                // standing order — is shown the details now, so there is
                // nobody left to send to the secretary for them.
                else -> CashButton(state, onClaim)
            }
        }

        // ---- what for ----
        if (pay.shares.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                SectionHeading(t("pay.what_its_for"))
                pay.shares.forEach { ShareLine(it) }
            }
        }

        // ---- passes ----
        PassesPart(state, clubName = pay.clubName, onGet = onGetPass, onCancel = onCancelPass)
    }
}

/** "You £5.62 · Jas Gill £8.63 · Arjun Gill £5.63": who "Pay for everyone" is for. */
@Composable
private fun EveryoneLines(pay: PayScreen, state: PayState) {
    Column {
        if (pay.owedCents > 0) AmountLine(t("nav.you"), money(pay.owedCents, pay.currency))
        state.othersOwing.forEach { person ->
            AmountLine(person.name, money(person.dues.owedCents, person.dues.currency))
        }
    }
}

/**
 * "I'm paying for friends too": tick who else from the same session this
 * payment covers, each with what they owe there — the most it can pay for
 * them. Each is recorded under your reference. Switched off, nobody else is
 * in the payment.
 */
@Composable
private fun FriendsPart(state: PayState, currency: String, onToggle: (String) -> Unit, onClose: () -> Unit) {
    var open by rememberSaveable { mutableStateOf(state.friendsTicked.isNotEmpty()) }
    Column {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .toggleable(value = open, role = Role.Switch, enabled = !state.isClaiming, onValueChange = { on ->
                    open = on
                    if (!on) onClose()
                }),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f).padding(end = 12.dp)) {
                Text(t("pa3.paying_for_friends"), style = MaterialTheme.typography.titleMedium)
                Body(t("pa3.paying_for_friends_hint"))
            }
            Switch(checked = open, onCheckedChange = null)
        }
        if (open) {
            state.friends.forEach { friend ->
                val ticked = friend.userId in state.friendsTicked
                Row(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .toggleable(value = ticked, role = Role.Checkbox, enabled = !state.isClaiming, onValueChange = { onToggle(friend.userId) }),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Checkbox(checked = ticked, onCheckedChange = null)
                    Text(friend.name, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(start = 12.dp).weight(1f))
                    Text(money(friend.owedCents, currency), style = MaterialTheme.typography.bodyLarge)
                }
            }
        }
    }
}

/** "I paid cash": as big as "I've paid", but outlined — cash at the ground is how a lot of clubs are paid. */
@Composable
private fun CashButton(state: PayState, onClaim: (PaymentMethod) -> Unit) {
    OutlinedButton(
        onClick = { onClaim(PaymentMethod.Cash) },
        enabled = !state.isClaiming,
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
    ) {
        Text(
            if (state.forEveryone && state.payingForOthers) t("pw3.paid_cash_for_everyone") else t("pay.i_paid_cash"),
            style = MaterialTheme.typography.titleMedium,
        )
    }
}

/** Secondary words, still big enough to read on a phone held at arm's length. */
@Composable
internal fun Body(text: String, modifier: Modifier = Modifier) {
    Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = modifier)
}

/**
 * One thing to copy: what it is, the value big, and a Copy button a thumb can
 * hit — banking apps ask for them one box at a time. The button says
 * "Copied" for a moment, because older phones show nothing when it works.
 */
@Composable
internal fun BigCopyRow(label: String, value: String, mono: Boolean = false, sensitive: Boolean = false) {
    val context = LocalContext.current
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) {
        if (copied) {
            delay(2000)
            copied = false
        }
    }
    Row(
        Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f).padding(end = 8.dp)) {
            Body(label)
            Text(
                value,
                style = MaterialTheme.typography.titleLarge,
                fontFamily = if (mono) FontFamily.Monospace else null,
            )
        }
        OutlinedButton(
            onClick = {
                copy(context, label, value, sensitive = sensitive)
                copied = true
            },
            modifier = Modifier.heightIn(min = 48.dp).semantics {
                contentDescription = t("pay.copy_what", vars = mapOf("what" to label))
            },
        ) {
            Icon(if (copied) Icons.Filled.Check else Icons.Filled.ContentCopy, contentDescription = null, modifier = Modifier.size(18.dp))
            Text(if (copied) t("pay.copied") else t("pa2.copy"), modifier = Modifier.padding(start = 6.dp))
        }
    }
}

/**
 * "First time? Here's how": three steps, each with its picture. Once this
 * phone has paid by transfer, "Pay Aman as usual" instead — with the steps
 * still a tap away.
 */
@Composable
private fun PayGuide(pay: PayScreen, account: BankDetails, seen: Boolean, amountCents: Long = pay.owedCents) {
    var open by rememberSaveable { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (seen) Body(t("pa2.pay_as_usual", vars = mapOf("name" to account.payeeShortName)))
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clickable(role = Role.Button) { open = !open },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.AutoMirrored.Filled.HelpOutline, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Text(
                if (seen) t("pa2.guide_again") else t("pa2.first_time"),
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(start = 8.dp).weight(1f),
            )
            Icon(if (open) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, contentDescription = null)
        }
        if (open) {
            GuideStep(1, Icons.Filled.PhoneAndroid, t("pa2.guide_1_title"), t("pa2.guide_1_body"))
            GuideStep(2, Icons.Filled.PersonAdd, t("pa2.guide_2_title"), t("pa2.guide_2_body"))
            GuideStep(
                3,
                Icons.Filled.ContentPaste,
                t("pa2.guide_3_title"),
                t("pa2.guide_3_body", vars = mapOf("amount" to money(amountCents, pay.currency), "reference" to pay.reference)),
            )
        }
    }
}

@Composable
private fun GuideStep(n: Int, icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, body: String) {
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.Top) {
        Box(
            Modifier.size(56.dp).background(MaterialTheme.colorScheme.primaryContainer, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimaryContainer, modifier = Modifier.size(28.dp))
        }
        Column(Modifier.padding(start = 12.dp).weight(1f)) {
            Text("$n. $title", style = MaterialTheme.typography.titleMedium)
            Text(body, style = MaterialTheme.typography.bodyLarge)
        }
    }
}

/**
 * What you've said you paid, waiting for the club to check: each with a
 * screenshot to add (for a transfer) and Undo.
 */
@Composable
private fun WaitingCard(pay: PayScreen, state: PayState, onUndo: (Payment) -> Unit, onAddPicture: (Payment) -> Unit) {
    Card(
        Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF3E0), contentColor = Color(0xFF5C3600)),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(pay.account.waitingLine(), style = MaterialTheme.typography.titleMedium)
            pay.claims.forEachIndexed { i, claim ->
                if (i > 0) HorizontalDivider()
                WaitingRow(
                    claim = claim,
                    me = state.me,
                    payee = pay.account?.payeeShortName,
                    undoing = state.undoing == claim.id,
                    attaching = state.attaching == claim.id,
                    onUndo = { onUndo(claim) },
                    onAddPicture = { onAddPicture(claim) },
                )
            }
        }
    }
}

@Composable
private fun WaitingRow(
    claim: Payment,
    me: String?,
    payee: String?,
    undoing: Boolean,
    attaching: Boolean,
    onUndo: () -> Unit,
    onAddPicture: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            claim.waitingWords(me),
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium,
        )
        shortDay(claim.createdAt).takeIf { it.isNotEmpty() }?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
        val canPicture = claim.method != PaymentMethod.Cash && !claim.hasScreenshot
        when {
            claim.hasScreenshot -> Text(t("pa2.screenshot_with_it"), style = MaterialTheme.typography.bodyMedium)
            canPicture -> Text(
                if (payee != null) t("pa2.screenshot_hint", vars = mapOf("name" to payee)) else t("pa2.screenshot_hint_club"),
                style = MaterialTheme.typography.bodyMedium,
            )
        }
        val labels = listOfNotNull(t("pa2.add_screenshot").takeIf { canPicture }, t("pay.undo"))
        ButtonRow(labels = labels) { i, m ->
            if (canPicture && i == 0) {
                OutlinedButton(onClick = onAddPicture, enabled = !attaching, modifier = m.heightIn(min = 48.dp)) {
                    ButtonLabel(if (attaching) t("pa2.screenshot_sending") else t("pa2.add_screenshot"))
                }
            } else {
                TextButton(onClick = onUndo, enabled = !undoing, modifier = m.heightIn(min = 48.dp)) { ButtonLabel(t("pay.undo")) }
            }
        }
    }
}

/**
 * "Friday nets · Fri 20 Nov   £15.00 Owed", "Match balls · by 6 Dec", or
 * "Tuesday nets   Covered by your pass ✓" — a covered line has no amount and
 * nothing to tap.
 */
@Composable
internal fun ShareLine(share: Share, trailing: @Composable () -> Unit = {}) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(end = 8.dp)) {
            Text(share.title, style = MaterialTheme.typography.bodyLarge)
            share.whenWords().takeIf { it.isNotEmpty() }?.let { Body(it) }
        }
        Column(horizontalAlignment = Alignment.End) {
            if (!share.isCovered) Text(money(share.amountCents, share.currency), style = MaterialTheme.typography.bodyLarge)
            StateLabel(share)
        }
        trailing()
    }
}

// ---- what you owe, across clubs ----

/**
 * "You owe £15.00 to Riverside Strikers" — on Home and in Profile. Opens the
 * list by club. [showSettled] keeps it up for waiting amounts and credit too,
 * which Profile wants and Home does not.
 */
@Composable
fun YouOweCard(dues: Dues?, showSettled: Boolean = false, onOpen: () -> Unit) {
    if (dues == null) return
    val owing = dues.owing
    if (owing.isEmpty() && !(showSettled && dues.hasAnything)) return
    Card(
        Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = onOpen)
            .semantics(mergeDescendants = true) { contentDescription = t("pay.open_what_you_owe") },
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                if (owing.isEmpty()) t("pay.payments") else t("pay.you_owe"),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            owing.forEach { club ->
                Text(
                    t("pay.amount_to_club", vars = mapOf("amount" to money(club.owedCents, club.currency), "club" to club.clubName)),
                    style = MaterialTheme.typography.titleMedium,
                )
            }
            // Waiting, a club at a time: yours and that of everybody you pay for.
            (dues.clubs.map { it.clubId to it } + dues.people.map { (it.dues.clubId.ifEmpty { it.clubId }) to it.dues })
                .groupBy({ it.first }, { it.second })
                .values
                .forEach { club ->
                    val waiting = club.sumOf { it.waitingCents }
                    if (waiting > 0) {
                        Body(t("pay.amount_waiting_to_confirm", vars = mapOf("amount" to money(waiting, club.first().currency))))
                    }
                }
            // Nothing owed is nothing to pay: just the way in to see it.
            Text(
                if (owing.isEmpty()) t("pay.see_details") else t("pay.tap_to_pay"),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

/** Everything you owe, a club at a time, each with the way to pay it. */
@Composable
internal fun DuesPage() {
    val deps = LocalAppDeps.current
    val nav = LocalNavigator.current
    val model = remember { DuesViewModel(deps.service<PaymentsApi>()) }
    val state by model.state.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { model.load() }

    ClubScreen(title = t("pay.payments")) {
        val dues = state.dues
        when {
            dues == null && state.isLoading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
            dues == null -> Column(Modifier.padding(24.dp)) {
                ErrorLine(state.error ?: t("rest.something_went_wrong_plain"))
                TextButton(onClick = model::load, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("rest.try_again")) }
            }
            dues.clubs.isEmpty() && dues.people.isEmpty() -> Box(Modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
                Text(t("pay.nothing_owed_anywhere"), style = MaterialTheme.typography.bodyLarge)
            }
            else -> Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                val ids = (dues.clubs.map { it.clubId } + dues.people.map { it.dues.clubId.ifEmpty { it.clubId } }).distinct()
                ids.forEach { id ->
                    val own = dues.clubs.firstOrNull { it.clubId == id }
                    val people = dues.peopleIn(id)
                    val name = own?.clubName?.takeIf { it.isNotBlank() } ?: people.firstOrNull()?.dues?.clubName.orEmpty()
                    ClubDuesCard(
                        own = own,
                        people = people,
                        clubName = name,
                        onPay = { nav.push(PayRoute(id, name)) },
                        onPayEveryone = { nav.push(PayRoute(id, name, forEveryone = true)) },
                    )
                }
            }
        }
    }
}

/**
 * One club: what you owe, then each person you pay for as their own block,
 * and one button. With people to pay for it is Pay for everyone — one
 * payment, one reference — because that is what a parent wants to do.
 */
@Composable
private fun ClubDuesCard(
    own: ClubDues?,
    people: List<PersonDues>,
    clubName: String,
    onPay: () -> Unit,
    onPayEveryone: () -> Unit,
) {
    val currency = own?.currency ?: people.firstOrNull()?.dues?.currency ?: "GBP"
    val othersOwe = people.sumOf { it.dues.owedCents }
    val total = (own?.owedCents ?: 0) + othersOwe
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(clubName, style = MaterialTheme.typography.titleMedium)
            if (own != null) {
                if (people.isNotEmpty()) {
                    Text(t("nav.you"), style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp).semantics { heading() })
                }
                DuesBlock(own, owedLabel = t("pay.you_owe"))
            }
            people.forEach { person ->
                HorizontalDivider(Modifier.padding(vertical = 8.dp))
                Text(person.name, style = MaterialTheme.typography.titleSmall, modifier = Modifier.semantics { heading() })
                DuesBlock(person.dues, owedLabel = t("pa3.they_owe"))
            }
            when {
                othersOwe > 0 -> Button(onClick = onPayEveryone, modifier = Modifier.fillMaxWidth().padding(top = 8.dp).heightIn(min = 56.dp)) {
                    Text(t("pa3.pay_for_everyone", vars = mapOf("amount" to money(total, currency))), style = MaterialTheme.typography.titleMedium)
                }
                (own?.owedCents ?: 0) > 0 -> Button(onClick = onPay, modifier = Modifier.fillMaxWidth().padding(top = 8.dp).heightIn(min = 48.dp)) {
                    Text(t("pay.pay"))
                }
                // Somewhere to undo a claim made by mistake.
                (own?.waitingCents ?: 0) > 0 -> TextButton(onClick = onPay, modifier = Modifier.heightIn(min = 48.dp)) { Text(t("pay.see_details")) }
            }
        }
    }
}

/** What one person owes a club, what is waiting, their credit, and the lines. */
@Composable
private fun DuesBlock(club: ClubDues, owedLabel: String) {
    when {
        club.owedCents > 0 -> AmountLine(owedLabel, money(club.owedCents, club.currency), strong = true)
        club.waitingCents <= 0 -> Body(t("pay.all_paid_up"))
    }
    if (club.waitingCents > 0) {
        Body(t("pay.amount_waiting_to_confirm", vars = mapOf("amount" to money(club.waitingCents, club.currency))))
    }
    if (club.creditCents > 0) {
        Body(t("pay.you_have_credit", vars = mapOf("amount" to money(club.creditCents, club.currency))))
    }
    club.shares.forEach { ShareLine(it) }
}

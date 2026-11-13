package com.fishers.app.views.profile

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.fishers.app.R
import com.fishers.app.i18n.Language
import com.fishers.app.i18n.Strings
import com.fishers.app.i18n.t
import com.fishers.app.net.FishersApi
import com.fishers.app.net.ProfileApi
import com.fishers.app.net.PublicUser
import com.fishers.app.profile.Me
import com.fishers.app.profile.PlayerLocation
import com.fishers.app.profile.ProfileState
import com.fishers.app.profile.ProfileStrength
import com.fishers.app.profile.ProfileViewModel
import com.fishers.app.profile.ReliabilityScore
import com.fishers.app.profile.SportProfile
import com.fishers.app.profile.SportStats
import com.fishers.app.profile.Totals
import com.fishers.app.profile.UserAchievement
import com.fishers.app.profile.Weekday

import com.fishers.app.profile.labelOf
import com.fishers.app.season.SeasonLink
import com.fishers.app.season.SeasonTab
import com.fishers.app.season.SeasonViewModel
import com.fishers.app.umpire.PendingUmpireReviewsViewModel
import com.fishers.app.umpire.UmpireViewModel
import com.fishers.app.views.nav.LocalAppDeps
import com.fishers.app.views.nav.LocalNavigator
import com.fishers.app.views.onboarding.ShareProfileCard
import com.fishers.app.views.onboarding.VerifyAccountRoute
import com.fishers.app.views.safety.BlockedListCard
import com.fishers.app.views.season.SeasonPage
import com.fishers.app.views.umpire.PendingUmpireReviewsCard
import com.fishers.app.views.umpire.UmpiringCard

/**
 * The Profile tab — a player's own page, `ProfileView.swift`: the face, the
 * numbers, the details, then the account.
 *
 * The figures come from the seasons on record, so they are computed; the rest
 * is what the player has told us about themselves.
 */
@Composable
fun ProfileTabRoot(
    user: PublicUser?,
    api: FishersApi,
    season: SeasonViewModel,
    pendingReviews: PendingUmpireReviewsViewModel,
    umpiring: UmpireViewModel,
    /** Held by the tab screen, because a notification tap opens it from outside. */
    myGameOpen: Boolean,
    onMyGameOpen: (Boolean) -> Unit,
    onOpenFixturesTab: () -> Unit,
    onOpenClubsTab: () -> Unit,
    onSignOut: () -> Unit,
    onDeleteAccount: (password: String, onError: (String) -> Unit) -> Unit,
) {
    if (myGameOpen) {
        BackHandler { onMyGameOpen(false) }
        SeasonPage(
            season = season,
            meId = user?.id,
            onOpenFixtures = { onMyGameOpen(false); onOpenFixturesTab() },
            onOpenClubs = { onMyGameOpen(false); onOpenClubsTab() },
        )
        return
    }

    val deps = LocalAppDeps.current
    val nav = LocalNavigator.current
    // Kept by the activity rather than the tab, so coming back to Profile
    // shows the page at once and refreshes it underneath.
    val model: ProfileViewModel = viewModel(
        key = "profile:${user?.id}",
        factory = viewModelFactory {
            initializer {
                ProfileViewModel(deps.service<ProfileApi>(), deps.webBase) { deps.setUser(it.toPublicUser()) }
            }
        },
    )
    val state by model.state.collectAsStateWithLifecycle()
    // On every visit, and whenever the person changes underneath — a save, a
    // confirmed contact, a new photo.
    LaunchedEffect(user) { model.load() }

    val me = state.me
    val pickPhoto = rememberPhotoPicker(onBytes = model::uploadPhoto, onUnreadable = model::photoUnreadable)

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        ProfileHero(
            name = me?.name ?: user?.name ?: t("rest.signed_in"),
            avatarUrl = me?.avatarUrl ?: user?.avatarUrl,
            club = state.club,
            main = me?.primaryProfile,
            photoBusy = state.photoBusy,
            photoError = state.photoError,
            onPickPhoto = pickPhoto,
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = { nav.push(EditProfileRoute()) },
                modifier = Modifier.weight(1f).heightIn(min = 48.dp),
            ) {
                Icon(Icons.Filled.Edit, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(t("cl.edit_profile"))
            }
            // The player's own season, near the top: it is the part of a
            // profile somebody opens it to see.
            OutlinedButton(
                onClick = {
                    season.open(SeasonLink(tab = SeasonTab.Mine))
                    onMyGameOpen(true)
                },
                modifier = Modifier.weight(1f).heightIn(min = 48.dp),
            ) { Text(t("ss.my_game")) }
        }

        if (me == null) {
            if (state.error != null) {
                Text(state.error!!, color = MaterialTheme.colorScheme.error)
                TextButton(onClick = model::load) { Text(t("rest.try_again")) }
            } else {
                Box(Modifier.fillMaxWidth(), Alignment.Center) { CircularProgressIndicator() }
            }
        } else {
            ProfileBody(me, state, onEdit = { nav.push(EditProfileRoute()) }, onVerify = { nav.push(VerifyAccountRoute()) },
                onCareer = { nav.push(CareerStatsRoute(state.seasons)) }, onGetLink = model::makeShareLink)
        }

        val pendingState by pendingReviews.state.collectAsStateWithLifecycle()
        LaunchedEffect(Unit) { pendingReviews.load() }
        PendingUmpireReviewsCard(
            state = pendingState,
            onReview = { matchId, umpireId, rating, comment ->
                pendingReviews.review(matchId, umpireId, rating, comment)
                umpiring.load()
            },
        )

        val umpState by umpiring.state.collectAsStateWithLifecycle()
        LaunchedEffect(Unit) { umpiring.load() }
        UmpiringCard(state = umpState, isMine = true, onWilling = umpiring::setWilling)

        BlockedListCard(api = api)

        AccountCard(
            verified = me?.isVerified ?: true,
            onVerify = { nav.push(VerifyAccountRoute()) },
            onSignOut = onSignOut,
            onDeleteAccount = onDeleteAccount,
        )
    }
}

/** Everything that needs the whole record, in the order iOS reads it. */
@Composable
private fun ProfileBody(
    me: Me,
    state: ProfileState,
    onEdit: () -> Unit,
    onVerify: () -> Unit,
    onCareer: () -> Unit,
    onGetLink: () -> Unit,
) {
    val strength = ProfileStrength(me)
    if (!strength.isComplete) {
        StrengthCard(strength, verified = me.isVerified, onComplete = onEdit, onVerify = onVerify)
    }

    CareerCard(state.seasons, onCareer)

    state.stats?.achievements?.takeIf { it.isNotEmpty() }?.let { HonoursCard(it) }

    val first = me.name.trim().split(" ").firstOrNull()?.takeIf { it.isNotBlank() } ?: me.name
    SectionCard(t("rest.about_person", vars = mapOf("name" to first))) {
        LabeledRow(t("rest.email"), me.email ?: "—")
        LabeledRow(t("cl.mobile"), me.phone ?: "—")
        me.emergencyContact?.takeIf { it.isNotBlank() }?.let { LabeledRow(t("cl.in_an_emergency"), it) }
    }

    me.reliability?.let { ReliabilityCard(it) }

    me.sportProfiles.forEach { SportCard(it, isMain = it.sport == me.primarySport) }

    me.location?.takeUnless { it.isEmpty }?.let { LocationCard(it) }

    SectionCard(t("rest.joining_a_club"), footer = t("cl.secretary_can_invite_you")) {
        Text(t("rest.drop_it_in_whatsapp"), style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        ShareProfileCard(link = state.shareLink, busy = state.shareBusy, error = state.shareError, onGetLink = onGetLink)
    }
}

/** "Your profile is 35% complete" — with what to add next and a way to add it. Gone at 100%. */
@Composable
private fun StrengthCard(strength: ProfileStrength, verified: Boolean, onComplete: () -> Unit, onVerify: () -> Unit) {
    SectionCard(title = null) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            StrengthRing(strength.percent)
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    t("rest.profile_percent_complete", vars = mapOf("percent" to strength.percent)),
                    style = MaterialTheme.typography.titleSmall,
                )
                Text(
                    t("rest.so_captains_can_see", vars = mapOf("what" to strength.nextUp)),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Button(onClick = onComplete, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
            Text(t("rest.complete_profile"))
        }
        // Confirming is the one step the edit form cannot do.
        if (!verified) {
            OutlinedButton(onClick = onVerify, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                Icon(Icons.Filled.VerifiedUser, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(t("rest.confirm_email_or_phone"))
            }
        }
    }
}

@Composable
private fun StrengthRing(percent: Int) {
    val label = t("rest.profile_percent_aria", vars = mapOf("percent" to percent))
    Box(Modifier.size(52.dp).semantics { contentDescription = label }, Alignment.Center) {
        CircularProgressIndicator(
            progress = { percent / 100f },
            modifier = Modifier.size(52.dp),
            strokeWidth = 5.dp,
            trackColor = MaterialTheme.colorScheme.outlineVariant,
        )
        Text("$percent%", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
    }
}

/** Career totals, the latest season, and the way into every season by discipline. */
@Composable
private fun CareerCard(seasons: List<com.fishers.app.profile.PlayerSeasonStats>, onOpen: () -> Unit) {
    if (seasons.isEmpty()) {
        SectionCard(t("cl.career")) {
            Text(
                t("rest.worked_out_from_matches_on", vars = mapOf("brand" to stringResource(R.string.brand_name))),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }
    val totals = Totals(seasons)
    SectionCard(
        t("cl.career"),
        footer = t("rest.across_n_seasons", count = seasons.size, vars = mapOf("n" to seasons.size)),
    ) {
        FigureGrid(
            listOf(
                "${totals.matches}" to t("rest.matches"),
                "${totals.runs}" to t("rest.runs"),
                "${totals.wickets}" to t("rest.wickets"),
                "${totals.catches}" to t("rest.catches"),
            ),
        )
        val latest = seasons.maxBy { it.seasonYear }
        Text(
            t(
                "rest.season_stats_aria",
                vars = mapOf("year" to latest.seasonYear, "runs" to latest.runs, "wickets" to latest.wickets, "matches" to latest.matches),
            ),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedButton(onClick = onOpen, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
            Text(t("cl.season_stats"))
        }
    }
}

@Composable
private fun HonoursCard(honours: List<UserAchievement>) {
    SectionCard(t("rest.honours")) {
        honours.forEach { award ->
            Column {
                Text(award.title, style = MaterialTheme.typography.titleSmall)
                award.description?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                award.seasonYear?.let {
                    Text(t("pf.season_year", vars = mapOf("year" to it)), style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/** The breakdown a player sees for their own score — `ReliabilityCard`. */
@Composable
private fun ReliabilityCard(reliability: ReliabilityScore) {
    SectionCard(
        t("rest.reliability"),
        footer = t("rest.based_on_n_invites", count = reliability.sampleSize, vars = mapOf("n" to reliability.sampleSize)),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                if (reliability.isUnproven) "–" else "${reliability.score}",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.width(14.dp))
            Column {
                Text(reliability.bandLabel, style = MaterialTheme.typography.titleSmall)
                Text(reliability.bandBlurb, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (reliability.isUnproven) {
            Text(
                t("rest.after_n_games_becomes_score", vars = mapOf("n" to ReliabilityScore.MINIMUM_SAMPLE)),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            Meter(t("ld.turned_up_when_going"), reliability.attendanceRate)
            Meter(t("ld.answered_the_invite"), reliability.responseRate)
            Meter(t("cl.paid_match_fees"), reliability.paymentRate)
            LabeledRow(t("rest.late_drop_outs"), "${reliability.lateCancellations}")
        }
    }
}

@Composable
private fun Meter(label: String, value: Double) {
    val fraction = value.coerceIn(0.0, 1.0).toFloat()
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        LabeledRow(label, "${Math.round(fraction * 100)}%")
        LinearProgressIndicator(progress = { fraction }, modifier = Modifier.fillMaxWidth())
    }
}

/** One sport: the standard, the position, the league and the numbers. */
@Composable
internal fun SportCard(profile: SportProfile, isMain: Boolean) {
    val sport = profile.sportKind
    val title = (sport?.label ?: profile.sport) + if (isMain) "  ·  ${t("rest.main_sport_badge")}" else ""
    SectionCard(title) {
        profile.tier?.let { tier ->
            LabeledRow(t("rest.level"), tier.label)
            tier.next?.let {
                Text(t("rest.working_towards", vars = mapOf("level" to it.label)), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        profile.position?.takeIf { it.isNotBlank() }?.let {
            LabeledRow(t("rest.position"), sport?.positions?.labelOf(it) ?: it)
        }
        profile.teamName?.takeIf { it.isNotBlank() }?.let { LabeledRow(t("cl.team"), it) }
        profile.division?.let { division ->
            val target = profile.target?.takeIf { it.ordinal > division.ordinal }
            LabeledRow(t("rest.division"), division.label + (target?.let { " → ${it.shortLabel}" } ?: ""))
        }
        profile.ageBand?.let { LabeledRow(t("tn.age_group"), it.label) }
        profile.yearsPlaying?.takeIf { it > 0 }?.let { LabeledRow(t("cl.years_playing"), "$it") }
        SportStats.summary(profile).forEach { (label, value) -> LabeledRow(label, value) }
    }
}

@Composable
private fun LocationCard(location: PlayerLocation) {
    SectionCard(t("rest.travel_and_logistics")) {
        location.summary?.let { LabeledRow(t("rest.based"), it) }
        location.travelRadiusMiles?.let { LabeledRow(t("ld.will_travel"), t("pf.n_miles", vars = mapOf("n" to it))) }
        location.transportMode?.let { mode ->
            LabeledRow(t("ld.transport"), mode.label)
            val seats = location.spareSeats ?: 0
            if (mode.offersLifts && seats > 0) LabeledRow(t("pf.spare_seats"), "$seats")
        }
        val days = location.preferredDays.orEmpty().mapNotNull(Weekday::of).sortedBy { it.ordinal }
        if (days.isNotEmpty()) LabeledRow(t("rest.usual_days"), days.joinToString(", ") { it.shortLabel })
        location.notes?.takeIf { it.isNotBlank() }?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Language, confirming a contact, signing out, and the way out for good. */
@Composable
private fun AccountCard(
    verified: Boolean,
    onVerify: () -> Unit,
    onSignOut: () -> Unit,
    onDeleteAccount: (password: String, onError: (String) -> Unit) -> Unit,
) {
    var confirmSignOut by remember { mutableStateOf(false) }
    val brand = stringResource(R.string.brand_name)
    val webBase = LocalAppDeps.current.webBase
    val uri = LocalUriHandler.current
    SectionCard(t("rest.account"), footer = t("rest.deleting_removes_everything")) {
        if (!verified) {
            TextButton(onClick = onVerify, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(t("rest.confirm_email_or_phone"))
            }
        }
        LanguagePicker()
        // On the website, because the stores want a policy anybody can read
        // without an account.
        TextButton(onClick = { uri.openUri("$webBase/privacy") }, modifier = Modifier.heightIn(min = 48.dp)) {
            Text(t("rest.privacy"))
        }
        TextButton(onClick = { confirmSignOut = true }, modifier = Modifier.heightIn(min = 48.dp)) {
            Text(t("nav.sign_out"))
        }
        DeleteAccountCard(onDelete = onDeleteAccount)
    }
    if (confirmSignOut) {
        AlertDialog(
            onDismissRequest = { confirmSignOut = false },
            title = { Text(t("rest.sign_out_of_brand", vars = mapOf("brand" to brand))) },
            text = { Text(t("rest.sign_back_in_anytime")) },
            confirmButton = {
                TextButton(onClick = { confirmSignOut = false; onSignOut() }) {
                    Text(t("nav.sign_out"), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmSignOut = false }) { Text(t("sc.cancel")) } },
        )
    }
}

/**
 * Which language the app speaks.
 *
 * Each listed in its own script and never translated — a picker offering
 * "Punjabi" in English is no use to the person who needs it. Choosing one
 * redraws every screen: `t()` reads `Strings.language`, which is Compose
 * state, so the subscription is automatic.
 */
@Composable
fun LanguagePicker() {
    val context = LocalContext.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(t("lang.label"), style = MaterialTheme.typography.labelLarge)
        Language.entries.forEach { language ->
            FilterChip(
                selected = Strings.language == language,
                onClick = { Strings.set(context, language) },
                label = { Text(language.native) },
            )
        }
    }
}

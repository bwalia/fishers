package com.fishers.app.views.payments

import androidx.compose.runtime.Composable
import com.fishers.app.payments.MoneyLink
import com.fishers.app.views.fixtures.FixtureRoute
import com.fishers.app.views.nav.Route

// Paying the club by bank transfer: the pay screen, what you owe, and the
// treasurer's page. The event's money section is part of the fixture page.

/**
 * Pay one club: the details to copy, and "I've paid". [forEveryone] pays for
 * you and everybody you pay for, in one payment.
 */
data class PayRoute(val clubId: String, val clubName: String = "", val forEveryone: Boolean = false) : Route {
    @Composable override fun Content() = PayPage(clubId, clubName, forEveryone)
}

/** Everything you owe, a club at a time. From the "you owe" card. */
class DuesRoute : Route {
    @Composable override fun Content() = DuesPage()

    // One list, however it was opened: two pushes of it are the same screen.
    override fun equals(other: Any?): Boolean = other is DuesRoute
    override fun hashCode(): Int = DuesRoute::class.hashCode()
}

/**
 * The treasurer's page on its own, as a notification opens it. [payIfNotAdmin]
 * sends anybody the server says it is not for on to the pay screen instead —
 * a `club_id` notification is for a treasurer or a payer, and only the server
 * knows which this person is.
 */
data class ClubPaymentsRoute(val clubId: String, val name: String = "", val payIfNotAdmin: Boolean = false) : Route {
    @Composable override fun Content() = ClubPaymentsPage(clubId, name, payIfNotAdmin)
}

/** Payments → Passes, for money admins. */
data class PassesAdminRoute(val clubId: String, val currency: String = "GBP") : Route {
    @Composable override fun Content() = PassesAdminPage(clubId, currency)
}

/** Payments → Group fees, for money admins. [openBillId] opens one straight away: a group fee tapped on the overview. */
data class GroupFeesRoute(val clubId: String, val currency: String = "GBP", val openBillId: String? = null) : Route {
    @Composable override fun Content() = GroupFeesPage(clubId, currency, openBillId)
}

/** Payments → Import a bank statement, for money admins. */
data class StatementRoute(val clubId: String) : Route {
    @Composable override fun Content() = StatementPage(clubId)
}

/** Payments → Prices for juniors, students…, and who pays for whom. */
data class PricesRoute(val clubId: String) : Route {
    @Composable override fun Content() = PricesPage(clubId)
}

/** The screen a tapped payments notification opens. */
fun MoneyLink.route(): Route = when (this) {
    is MoneyLink.Event -> FixtureRoute(eventId)
    is MoneyLink.Pay -> PayRoute(clubId)
    is MoneyLink.ClubMoney -> ClubPaymentsRoute(clubId, payIfNotAdmin = true)
}

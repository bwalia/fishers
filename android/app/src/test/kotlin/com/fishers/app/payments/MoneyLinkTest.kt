package com.fishers.app.payments

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Where a tapped payments notification lands — §11's routing table. */
class MoneyLinkTest {

    @Test
    fun `an event id opens the event, whatever the kind`() {
        for (kind in listOf("bill_issued", "bill_updated", "bill_cancelled", "bill_who_came", "bill_auto_sent", "bill_not_sent", null)) {
            assertEquals(kind.toString(), MoneyLink.Event("e1"), MoneyLink.fromPush(kind, "e1", "c1"))
        }
    }

    @Test
    fun `a payer's notifications open the pay screen`() {
        for (kind in listOf("fee_reminder", "payment_confirmed", "payment_rejected")) {
            assertEquals(kind, MoneyLink.Pay("c1"), MoneyLink.fromPush(kind, null, "c1"))
        }
    }

    @Test
    fun `a treasurer's notifications open the money page`() {
        for (kind in listOf("payment_claimed", "payments_to_check", "payout_details_changed", "payout_details_frozen")) {
            assertEquals(kind, MoneyLink.ClubMoney("c1"), MoneyLink.fromPush(kind, null, "c1"))
        }
    }

    /** FCM's data carries the payload's keys and not the kind: route by the payload, as the doc says. */
    @Test
    fun `with no kind, a club id opens the money page, which sends a payer on to pay`() {
        assertEquals(MoneyLink.ClubMoney("c1"), MoneyLink.fromPush(null, null, "c1"))
        assertEquals(MoneyLink.ClubMoney("c1"), MoneyLink.fromPush(null, " ", "c1"))
    }

    @Test
    fun `anything it does not understand opens nothing, and never throws`() {
        assertNull(MoneyLink.fromPush("some_future_kind", null, "c1"))
        assertNull(MoneyLink.fromPush("payment_claimed", null, null))
        assertNull(MoneyLink.fromPush(null, null, null))
        assertNull(MoneyLink.fromPush("", "", ""))
    }

    @Test
    fun `pass and group fee notifications open the pay screen, a paused pass the money page`() {
        listOf("pass_started", "pass_charge", "pass_behind", "pass_cancelled", "pass_price_changed", "pass_sessions_left", "collection_issued")
            .forEach { kind -> assertEquals(kind, MoneyLink.Pay("c1"), MoneyLink.fromPush(kind, null, "c1")) }
        // Told to the person and to money admins alike: the money page sends a player on.
        assertEquals(MoneyLink.ClubMoney("c1"), MoneyLink.fromPush("pass_suspended", null, "c1"))
    }
}

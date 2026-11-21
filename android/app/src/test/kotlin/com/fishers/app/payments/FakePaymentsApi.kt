package com.fishers.app.payments

import com.fishers.app.net.PaymentsApi
import kotlinx.serialization.json.Json

/**
 * [PaymentsApi] with every call refusing by default, as the other fakes do: a
 * test overrides what it exercises, and anything else being reached fails by
 * name. Every endpoint in the interface is here — release builds skip test
 * compilation, so one missing would only fail later.
 */
open class FakePaymentsApi : PaymentsApi {
    override suspend fun addPayoutAccount(clubId: String, body: AddBankDetailsBody): PayoutAccounts =
        error("addPayoutAccount not expected")
    override suspend fun freezePayoutAccount(clubId: String, accountId: String, body: ReasonBody): PayoutAccounts =
        error("freezePayoutAccount not expected")
    override suspend fun unfreezePayoutAccount(clubId: String, accountId: String): PayoutAccounts =
        error("unfreezePayoutAccount not expected")
    override suspend fun retirePayoutAccount(clubId: String, accountId: String): PayoutAccounts =
        error("retirePayoutAccount not expected")
    override suspend fun money(clubId: String): MoneyOverview = error("money not expected")
    override suspend fun updateMoneySettings(clubId: String, body: MoneySettingsBody): MoneySettings =
        error("updateMoneySettings not expected")
    override suspend fun confirmPayment(paymentId: String): Payment = error("confirmPayment not expected")
    override suspend fun rejectPayment(paymentId: String, body: ReasonBody): Payment = error("rejectPayment not expected")
    override suspend fun recordPayment(clubId: String, idempotencyKey: String, body: RecordBody): Payment =
        error("recordPayment not expected")
    override suspend fun refund(clubId: String, idempotencyKey: String, body: RecordBody): Payment = error("refund not expected")
    override suspend fun waiveShare(shareId: String, body: ReasonBody): Share = error("waiveShare not expected")
    override suspend fun setCost(eventId: String, body: CostBody): CostResponse = error("setCost not expected")
    override suspend fun removeCost(eventId: String): Unit = error("removeCost not expected")
    override suspend fun bill(eventId: String): EventMoney = error("bill not expected")
    override suspend fun previewBill(eventId: String, body: BillBody): BillPreview = error("previewBill not expected")
    override suspend fun sendBill(eventId: String, body: BillBody): EventMoney = error("sendBill not expected")
    override suspend fun voidBill(eventId: String, body: ReasonBody): EventMoney = error("voidBill not expected")
    override suspend fun myDues(): Dues = error("myDues not expected")
    override suspend fun payScreen(clubId: String): PayScreen = error("payScreen not expected")
    override suspend fun claimPayment(clubId: String, idempotencyKey: String, body: ClaimBody): Payment =
        error("claimPayment not expected")
    override suspend fun cancelClaim(paymentId: String): Unit = error("cancelClaim not expected")
}

/** The responses captured from the running API (`.dev/payments/examples/`), as `Network` decodes them. */
object Captured {
    val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
    }

    fun text(name: String): String =
        requireNotNull(Captured::class.java.getResource("/payments/$name.json")) { "no fixture $name" }.readText()

    inline fun <reified T> read(name: String): T = json.decodeFromString(text(name))
}

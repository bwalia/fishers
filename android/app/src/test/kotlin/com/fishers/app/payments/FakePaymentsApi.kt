package com.fishers.app.payments

import com.fishers.app.clubs.ClubMemberDetail
import com.fishers.app.clubs.Team
import com.fishers.app.net.PaymentsApi
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import okhttp3.RequestBody
import okhttp3.ResponseBody

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
    override suspend fun usualPrices(clubId: String): MoneySettings = error("usualPrices not expected")
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
    override suspend fun billLink(eventId: String): BillLink = error("billLink not expected")
    override suspend fun disableBillLink(eventId: String): DisabledLinks = error("disableBillLink not expected")
    override suspend fun cashAtGround(eventId: String, idempotencyKey: String, body: CashBody): CashRecorded =
        error("cashAtGround not expected")
    override suspend fun confirmMany(clubId: String, body: ConfirmManyBody): ConfirmedMany = error("confirmMany not expected")
    override suspend fun screenshot(paymentId: String): ResponseBody = error("screenshot not expected")
    override suspend fun uploadScreenshot(paymentId: String, image: RequestBody): Unit = error("uploadScreenshot not expected")

    // ---- steps B and C ----
    override suspend fun priceTypes(clubId: String): List<PriceType> = error("priceTypes not expected")
    override suspend fun addPriceType(clubId: String, body: PriceTypeBody): PriceType = error("addPriceType not expected")
    override suspend fun changePriceType(priceTypeId: String, body: PriceTypeBody): PriceType = error("changePriceType not expected")
    override suspend fun setMemberPriceType(clubId: String, userId: String, body: MemberPriceTypeBody): Unit =
        error("setMemberPriceType not expected")
    override suspend fun passes(clubId: String, all: Boolean?): List<PassPlan> = error("passes not expected")
    override suspend fun addPass(clubId: String, body: NewPassBody): PassPlan = error("addPass not expected")
    override suspend fun changePass(passId: String, body: PassChangeBody): PassPlan = error("changePass not expected")
    override suspend fun passHolders(passId: String): List<PassHolder> = error("passHolders not expected")
    override suspend fun addToPass(passId: String, body: AddHolderBody): PassHolder = error("addToPass not expected")
    override suspend fun joinPass(passId: String, body: JoinPassBody): PassHolder = error("joinPass not expected")
    override suspend fun cancelPass(holderId: String): PassHolder = error("cancelPass not expected")
    override suspend fun keepCovering(holderId: String, body: KeepCoveringBody): PassHolder = error("keepCovering not expected")
    override suspend fun myPasses(): List<PassHolder> = error("myPasses not expected")
    override suspend fun addGroupFee(clubId: String, idempotencyKey: String, body: NewGroupFeeBody): GroupFee =
        error("addGroupFee not expected")
    override suspend fun groupFees(clubId: String): List<GroupFee> = error("groupFees not expected")
    override suspend fun groupFee(billId: String): GroupFee = error("groupFee not expected")
    override suspend fun cancelGroupFee(billId: String, body: ReasonBody): GroupFee = error("cancelGroupFee not expected")
    override suspend fun currentGroupFeeLink(billId: String): JsonElement = error("currentGroupFeeLink not expected")
    override suspend fun groupFeeLink(billId: String): BillLink = error("groupFeeLink not expected")
    override suspend fun disableGroupFeeLink(billId: String): DisabledLinks = error("disableGroupFeeLink not expected")
    override suspend fun setPayer(clubId: String, memberId: String, body: PayerBody): Unit = error("setPayer not expected")
    override suspend fun addJunior(clubId: String, body: ManagedMemberBody): ManagedMember = error("addJunior not expected")
    override suspend fun payForOthers(clubId: String, idempotencyKey: String, body: ForOthersBody): ForOthers =
        error("payForOthers not expected")
    override suspend fun moneyMembers(clubId: String): List<MoneyMember> = error("moneyMembers not expected")
    override suspend fun clubMembers(clubId: String): List<ClubMemberDetail> = error("clubMembers not expected")
    override suspend fun clubTeams(clubId: String): List<Team> = error("clubTeams not expected")

    // ---- step D ----
    override suspend fun previewStatement(clubId: String, csv: RequestBody): StatementPreview = error("previewStatement not expected")
    override suspend fun applyStatement(clubId: String, body: StatementBody): StatementApplied = error("applyStatement not expected")
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

package com.fishers.app.net

import com.fishers.app.payments.AddBankDetailsBody
import com.fishers.app.payments.BillBody
import com.fishers.app.payments.BillPreview
import com.fishers.app.payments.ClaimBody
import com.fishers.app.payments.CostBody
import com.fishers.app.payments.CostResponse
import com.fishers.app.payments.Dues
import com.fishers.app.payments.EventMoney
import com.fishers.app.payments.MoneyOverview
import com.fishers.app.payments.MoneySettings
import com.fishers.app.payments.MoneySettingsBody
import com.fishers.app.payments.PayScreen
import com.fishers.app.payments.Payment
import com.fishers.app.payments.PayoutAccounts
import com.fishers.app.payments.ReasonBody
import com.fishers.app.payments.RecordBody
import com.fishers.app.payments.Share
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path

/**
 * Paying the club by bank transfer — `backend/api/src/routes/club_payments.rs`,
 * §11 of docs/PAY_BY_BANK_TRANSFER.md. Its own interface, like every area's.
 *
 * Refusals are `{"error": "<sentence>", "code": "<stable>"}`. Two of them are
 * not what they look like: 428 `reauth_required` and 403 `wrong_password` on
 * the bank details form mean "type your password", never "signed out".
 *
 * The three calls that make a payment carry an `Idempotency-Key`: one per
 * attempt, the same on a retry, so a tap on a bad signal is one payment.
 */
interface PaymentsApi {

    // ---- the club's bank details ----

    // Read through `money`, whose `account` is the same view: there is no
    // screen that shows the details to anybody but a money admin.

    /** Add, or change (live in 24 hours). 428 `reauth_required`, 403 `wrong_password`. */
    @POST("clubs/{id}/payout-account")
    suspend fun addPayoutAccount(@Path("id") clubId: String, @Body body: AddBankDetailsBody): PayoutAccounts

    @POST("clubs/{id}/payout-account/{aid}/freeze")
    suspend fun freezePayoutAccount(
        @Path("id") clubId: String,
        @Path("aid") accountId: String,
        @Body body: ReasonBody,
    ): PayoutAccounts

    /** The owner only: 403 `owner_only` for anyone else. */
    @POST("clubs/{id}/payout-account/{aid}/unfreeze")
    suspend fun unfreezePayoutAccount(@Path("id") clubId: String, @Path("aid") accountId: String): PayoutAccounts

    /** Removes the details, or cancels a change still waiting. */
    @POST("clubs/{id}/payout-account/{aid}/retire")
    suspend fun retirePayoutAccount(@Path("id") clubId: String, @Path("aid") accountId: String): PayoutAccounts

    // ---- the treasurer's side ----

    /** 403 for anybody who is not the owner, a secretary or a treasurer. */
    @GET("clubs/{id}/money")
    suspend fun money(@Path("id") clubId: String): MoneyOverview

    @PUT("clubs/{id}/payments/settings")
    suspend fun updateMoneySettings(@Path("id") clubId: String, @Body body: MoneySettingsBody): MoneySettings

    /** 409 `already_decided`: somebody else got there first. */
    @POST("payments/{pid}/confirm")
    suspend fun confirmPayment(@Path("pid") paymentId: String): Payment

    @POST("payments/{pid}/reject")
    suspend fun rejectPayment(@Path("pid") paymentId: String, @Body body: ReasonBody): Payment

    /** Cash at the ground, or a transfer nobody claimed. Confirmed at once. */
    @POST("clubs/{id}/payments/record")
    suspend fun recordPayment(
        @Path("id") clubId: String,
        @Header("Idempotency-Key") idempotencyKey: String,
        @Body body: RecordBody,
    ): Payment

    /** At most their credit: 400 `more_than_credit`. */
    @POST("clubs/{id}/payments/refund")
    suspend fun refund(
        @Path("id") clubId: String,
        @Header("Idempotency-Key") idempotencyKey: String,
        @Body body: RecordBody,
    ): Payment

    @POST("shares/{sid}/waive")
    suspend fun waiveShare(@Path("sid") shareId: String, @Body body: ReasonBody): Share

    // ---- an event's cost and bill ----

    /** 409 `already_billed` once billed: re-split instead. */
    @PUT("events/{id}/cost")
    suspend fun setCost(@Path("id") eventId: String, @Body body: CostBody): CostResponse

    @DELETE("events/{id}/cost")
    suspend fun removeCost(@Path("id") eventId: String)

    @GET("events/{id}/bill")
    suspend fun bill(@Path("id") eventId: String): EventMoney

    /** 422 `no_attendees`, `bad_amount`, `amount_limit`. */
    @POST("events/{id}/bill/preview")
    suspend fun previewBill(@Path("id") eventId: String, @Body body: BillBody): BillPreview

    /** Send, or re-split with `version`. 409 `version_conflict`, `already_billed`, `no_cost`. */
    @POST("events/{id}/bill")
    suspend fun sendBill(@Path("id") eventId: String, @Body body: BillBody): EventMoney

    /** Anything already paid becomes credit. */
    @POST("events/{id}/bill/void")
    suspend fun voidBill(@Path("id") eventId: String, @Body body: ReasonBody): EventMoney

    // ---- the player's side ----

    @GET("me/dues")
    suspend fun myDues(): Dues

    /** The bank details in full, while you owe the club something. Rate-limited (429). */
    @GET("clubs/{id}/pay")
    suspend fun payScreen(@Path("id") clubId: String): PayScreen

    /** "I've paid" / "I paid cash". 409 `nothing_owed` is not a failure: refresh. */
    @POST("clubs/{id}/payments")
    suspend fun claimPayment(
        @Path("id") clubId: String,
        @Header("Idempotency-Key") idempotencyKey: String,
        @Body body: ClaimBody,
    ): Payment

    /** Undo a claim, while nobody has confirmed it. 409 `already_decided` after. */
    @DELETE("payments/{pid}")
    suspend fun cancelClaim(@Path("pid") paymentId: String)
}

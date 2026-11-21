package com.fishers.app.net

import com.fishers.app.clubs.ClubMemberDetail
import com.fishers.app.clubs.Team
import com.fishers.app.payments.AddBankDetailsBody
import com.fishers.app.payments.AddHolderBody
import com.fishers.app.payments.BillBody
import com.fishers.app.payments.BillLink
import com.fishers.app.payments.BillPreview
import com.fishers.app.payments.CashBody
import com.fishers.app.payments.CashRecorded
import com.fishers.app.payments.ClaimBody
import com.fishers.app.payments.ConfirmManyBody
import com.fishers.app.payments.ConfirmedMany
import com.fishers.app.payments.CostBody
import com.fishers.app.payments.CostResponse
import com.fishers.app.payments.DisabledLinks
import com.fishers.app.payments.Dues
import com.fishers.app.payments.EventMoney
import com.fishers.app.payments.ForOthers
import com.fishers.app.payments.ForOthersBody
import com.fishers.app.payments.GroupFee
import com.fishers.app.payments.JoinPassBody
import com.fishers.app.payments.KeepCoveringBody
import com.fishers.app.payments.ManagedMember
import com.fishers.app.payments.ManagedMemberBody
import com.fishers.app.payments.MemberPriceTypeBody
import com.fishers.app.payments.MoneyOverview
import com.fishers.app.payments.MoneySettings
import com.fishers.app.payments.MoneySettingsBody
import com.fishers.app.payments.NewGroupFeeBody
import com.fishers.app.payments.NewPassBody
import com.fishers.app.payments.PassChangeBody
import com.fishers.app.payments.PassHolder
import com.fishers.app.payments.PassPlan
import com.fishers.app.payments.PayScreen
import com.fishers.app.payments.Payment
import com.fishers.app.payments.PayerBody
import com.fishers.app.payments.PayoutAccounts
import com.fishers.app.payments.PriceType
import com.fishers.app.payments.PriceTypeBody
import com.fishers.app.payments.ReasonBody
import com.fishers.app.payments.RecordBody
import com.fishers.app.payments.Share
import okhttp3.RequestBody
import okhttp3.ResponseBody
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query

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

    /** The club's usual prices, for anybody who schedules (a captain too) — only the price fields are filled. */
    @GET("clubs/{id}/payments/defaults")
    suspend fun usualPrices(@Path("id") clubId: String): MoneySettings

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

    // ---- easy paying (step A, `easy_paying.rs`) ----

    /**
     * The bill's pay link and the words to post with it, for whoever runs
     * the session. Reuses the open link. 409 `no_bill` until the bill is sent.
     */
    @POST("events/{id}/bill/link")
    suspend fun billLink(@Path("id") eventId: String): BillLink

    /** Closes every open link for the bill. */
    @POST("events/{id}/bill/link/disable")
    suspend fun disableBillLink(@Path("id") eventId: String): DisabledLinks

    /**
     * Who handed over cash at the ground. A money admin's tick is received;
     * anybody else's waits for the treasurer. A share already paid or said to
     * be is skipped, so a retry cannot pay twice; the key is sent all the same.
     */
    @POST("events/{id}/bill/cash")
    suspend fun cashAtGround(
        @Path("id") eventId: String,
        @Header("Idempotency-Key") idempotencyKey: String,
        @Body body: CashBody,
    ): CashRecorded

    /** "All arrived". One somebody else already decided is skipped. */
    @POST("clubs/{id}/payments/confirm")
    suspend fun confirmMany(@Path("id") clubId: String, @Body body: ConfirmManyBody): ConfirmedMany

    /** Money admins only: the picture that came with a payment, when `has_screenshot`. */
    @GET("payments/{pid}/screenshot")
    suspend fun screenshot(@Path("pid") paymentId: String): ResponseBody

    /**
     * Your own claim's picture: raw JPEG, PNG or WebP, at most 1 MB. 415
     * `not_an_image`, 400 `too_big`, 409 `already_decided`.
     */
    @POST("payments/{pid}/screenshot")
    suspend fun uploadScreenshot(@Path("pid") paymentId: String, @Body image: RequestBody)

    // ---- passes, prices for juniors and others, group fees (steps B and C, `passes.rs`) ----

    /** The club's groups with their own price. Any member may read them. */
    @GET("clubs/{id}/price-types")
    suspend fun priceTypes(@Path("id") clubId: String): List<PriceType>

    /** Money admins. 409 `name_taken`, `guest_type_taken` (one guest price a club). */
    @POST("clubs/{id}/price-types")
    suspend fun addPriceType(@Path("id") clubId: String, @Body body: PriceTypeBody): PriceType

    @PATCH("price-types/{id}")
    suspend fun changePriceType(@Path("id") priceTypeId: String, @Body body: PriceTypeBody): PriceType

    /** A member's group; null is the standard price. 204. */
    @PUT("clubs/{id}/members/{user_id}/price-type")
    suspend fun setMemberPriceType(
        @Path("id") clubId: String,
        @Path("user_id") userId: String,
        @Body body: MemberPriceTypeBody,
    )

    /** The passes the club offers, each with your own on it (`mine`). `all` (admins) adds ones no longer offered. */
    @GET("clubs/{id}/passes")
    suspend fun passes(@Path("id") clubId: String, @Query("all") all: Boolean? = null): List<PassPlan>

    @POST("clubs/{id}/passes")
    suspend fun addPass(@Path("id") clubId: String, @Body body: NewPassBody): PassPlan

    /** A new price applies to later payments; everybody on a monthly pass is told. */
    @PATCH("passes/{id}")
    suspend fun changePass(@Path("id") passId: String, @Body body: PassChangeBody): PassPlan

    /** Money admins: who is on it, and how each stands. */
    @GET("passes/{id}/holders")
    suspend fun passHolders(@Path("id") passId: String): List<PassHolder>

    /** Money admins. The first payment is charged at once. 409 `already_on_pass`. */
    @POST("passes/{id}/holders")
    suspend fun addToPass(@Path("id") passId: String, @Body body: AddHolderBody): PassHolder

    /** "Get this pass". `not_open`, `not_eligible`, `not_their_payer`, 409 `already_on_pass`. */
    @POST("passes/{id}/join")
    suspend fun joinPass(@Path("id") passId: String, @Body body: JoinPassBody): PassHolder

    /** A monthly pass covers to the end of the month already charged. 409 `already_cancelled`. */
    @POST("pass-holders/{id}/cancel")
    suspend fun cancelPass(@Path("id") holderId: String): PassHolder

    @PUT("pass-holders/{id}/keep-covering")
    suspend fun keepCovering(@Path("id") holderId: String, @Body body: KeepCoveringBody): PassHolder

    /** Your passes, and those of the people you pay for; monthly ones with their standing order. */
    @GET("me/passes")
    suspend fun myPasses(): List<PassHolder>

    /**
     * A group fee. Everybody in it is told. The key is sent as on every money
     * call, though the server does not read it here yet. 422 for an amount it
     * cannot split.
     */
    @POST("clubs/{id}/collections")
    suspend fun addGroupFee(
        @Path("id") clubId: String,
        @Header("Idempotency-Key") idempotencyKey: String,
        @Body body: NewGroupFeeBody,
    ): GroupFee

    /** The 50 newest, totals only. Money admins. */
    @GET("clubs/{id}/collections")
    suspend fun groupFees(@Path("id") clubId: String): List<GroupFee>

    /** Everyone's lines for a money admin; only your own for a member. */
    @GET("collections/{bill_id}")
    suspend fun groupFee(@Path("bill_id") billId: String): GroupFee

    /** Anything paid becomes credit, and its pay link closes. `reason_required`. */
    @POST("collections/{bill_id}/void")
    suspend fun cancelGroupFee(@Path("bill_id") billId: String, @Body body: ReasonBody): GroupFee

    /** A group fee's pay link and the words to post with it: the same shape as a session's. */
    @POST("bills/{bill_id}/link")
    suspend fun groupFeeLink(@Path("bill_id") billId: String): BillLink

    @POST("bills/{bill_id}/link/disable")
    suspend fun disableGroupFeeLink(@Path("bill_id") billId: String): DisabledLinks

    /** Who pays for a member; null: they pay for themselves. 204. */
    @PUT("clubs/{id}/members/{member_id}/payer")
    suspend fun setPayer(@Path("id") clubId: String, @Path("member_id") memberId: String, @Body body: PayerBody)

    /** A junior by name, with no sign-in of their own, and who pays for them. */
    @POST("clubs/{id}/members/managed")
    suspend fun addJunior(@Path("id") clubId: String, @Body body: ManagedMemberBody): ManagedMember

    /**
     * One payment for several people. `not_their_payer`; 409 `nothing_owed`
     * when nobody picked owes anything. The same key on every retry.
     */
    @POST("clubs/{id}/payments/for-others")
    suspend fun payForOthers(
        @Path("id") clubId: String,
        @Header("Idempotency-Key") idempotencyKey: String,
        @Body body: ForOthersBody,
    ): ForOthers

    /** The roster, for picking who goes on a pass, a group fee, or pays for whom. */
    @GET("clubs/{id}/members")
    suspend fun clubMembers(@Path("id") clubId: String): List<ClubMemberDetail>

    /** The club's teams, for "a group fee for the 1st XI". */
    @GET("clubs/{id}/teams")
    suspend fun clubTeams(@Path("id") clubId: String): List<Team>
}

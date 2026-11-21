package com.fishers.app.payments

import com.fishers.app.clubs.Refusal
import com.fishers.app.clubs.refusalOf
import com.fishers.app.clubs.saidWhy
import kotlinx.coroutines.delay
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import retrofit2.HttpException
import retrofit2.Response
import java.util.UUID

/**
 * One `Idempotency-Key` per attempt at a payment.
 *
 * Made on the first try and handed out again for every retry of the same
 * request, so "I've paid" tapped twice on one bar of signal is one claim. It
 * is dropped once the server has given an answer — a later payment is a new
 * attempt — but kept when the request may or may not have landed (no signal,
 * a 5xx), because that is exactly when the retry must be recognised.
 */
class AttemptKeys(private val mint: () -> String = { UUID.randomUUID().toString() }) {
    private val keys = mutableMapOf<Any, String>()

    @Synchronized
    fun keyFor(attempt: Any): String = keys.getOrPut(attempt) { mint() }

    /** The attempt is over: it worked, or the server said no. */
    @Synchronized
    fun settled(attempt: Any) {
        keys.remove(attempt)
    }

    /**
     * After a failure: forget the key only if the server answered it. Takes
     * the refusal already read, because an error body can be read only once.
     * `busy` is no answer: the payment it was busy saving may be this one,
     * so the next tap must carry the same key to be recognised.
     */
    fun failed(attempt: Any, refusal: Refusal?) {
        if ((refusal?.status ?: 0) in 400..499 && refusal?.code != "busy") settled(attempt)
    }
}

/**
 * A refusal that means "what you are looking at is out of date": somebody else
 * changed the bill, decided the payment, or it was already billed. The answer
 * is to reload and show the server's sentence, not to call it a failure.
 */
val Refusal.meansReload: Boolean
    get() = status == 409 || code == "not_members" || code == "not_live"

/** The server's own sentence for a refusal, the app's words for anything else. */
fun failureText(error: Throwable, refusal: Refusal? = refusalOf(error)): String = saidWhy(error, refusal)

/** How long a payment waits before its one retry after `busy`. */
const val BUSY_RETRY_MS = 1_000L

private val JSON = "application/json".toMediaType()

/**
 * A payment POST, tried once more if the server says `busy` (409): another
 * request is saving a payment for the same person this moment — a double tap,
 * usually. After about a second, quietly, with the same Idempotency-Key, so
 * the retry answers with the first payment. Anything else, or `busy` twice,
 * goes to the caller as it came.
 *
 * Reading the refusal uses up its body, so a 409 that is not `busy`
 * (`nothing_owed`, `already_decided`) is handed on as a fresh copy the caller
 * can still read.
 */
suspend fun <T> retryIfBusy(waitMs: Long = BUSY_RETRY_MS, call: suspend () -> T): T {
    try {
        return call()
    } catch (e: HttpException) {
        if (e.code() != 409) throw e
        val body = runCatching { e.response()?.errorBody()?.string() }.getOrNull().orEmpty()
        fun copy() = HttpException(Response.error<Any>(409, body.toResponseBody(JSON)))
        if (refusalOf(copy())?.code != "busy") throw copy()
    }
    delay(waitMs)
    return call()
}

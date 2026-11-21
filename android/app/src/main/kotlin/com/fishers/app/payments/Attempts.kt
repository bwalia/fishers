package com.fishers.app.payments

import com.fishers.app.clubs.Refusal
import com.fishers.app.clubs.refusalOf
import com.fishers.app.clubs.saidWhy
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
     */
    fun failed(attempt: Any, refusal: Refusal?) {
        if ((refusal?.status ?: 0) in 400..499) settled(attempt)
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

package com.fishers.app.clubs

import com.fishers.app.session.readableError
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import retrofit2.HttpException

/**
 * What the server said when it said no: `{"error": "...", "code": "..."}`.
 *
 * The club screens need both halves. The words, because the API's are more use
 * than "HTTP 409" — "this is the club's last secretary — appoint another one
 * first" is the whole answer. The code, because a few refusals mean something
 * the app acts on: `unverified`, `removed_from_club`.
 */
data class Refusal(val status: Int, val code: String?, val message: String?) {
    val isUnverified: Boolean get() = code == "unverified"
}

/** The refusal inside a failed call, or null when it never reached the server. */
fun refusalOf(error: Throwable): Refusal? {
    val http = error as? HttpException ?: return null
    // Read once: an error body is a stream, and a second read is empty.
    val body = runCatching { http.response()?.errorBody()?.string() }.getOrNull()
    val fields = body?.let { runCatching { Json.parseToJsonElement(it).jsonObject }.getOrNull() }
    return Refusal(
        status = http.code(),
        code = fields?.get("code")?.jsonPrimitive?.contentOrNull,
        message = fields?.get("error")?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() },
    )
}

/**
 * Something a person can read about a failure: the server's own words for a
 * refusal, and the app's for everything else — no signal, a server in trouble.
 *
 * Pass the [Refusal] when it has been read already: the body can be read once.
 */
fun saidWhy(error: Throwable, refusal: Refusal? = refusalOf(error)): String =
    refusal?.message?.takeIf { refusal.status in 400..499 && refusal.status != 401 }
        ?: readableError(error)

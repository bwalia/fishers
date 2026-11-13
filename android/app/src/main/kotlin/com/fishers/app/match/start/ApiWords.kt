package com.fishers.app.match.start

import com.fishers.app.session.readableError
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import retrofit2.HttpException

/**
 * What the server said when it refused, read out of `{"error": …, "code": …}`.
 *
 * `readableError` speaks for the cases a person cannot do anything about — no
 * signal, a server in trouble. A refusal is different: "someone else is scoring
 * this match" and "confirm your email first" are the server telling the person
 * what to do next, and "HTTP 409" in their place says nothing at all.
 */
data class Refusal(val status: Int, val message: String, val code: String?)

fun refusalOf(error: Throwable): Refusal? {
    if (error !is HttpException) return null
    val status = error.code()
    if (status !in 400..499 || status == 401) return null
    val body = runCatching { error.response()?.errorBody()?.string() }.getOrNull() ?: return null
    val json = runCatching { Json.parseToJsonElement(body).jsonObject }.getOrNull() ?: return null
    val message = runCatching { json["error"]?.jsonPrimitive?.content }.getOrNull()?.takeIf { it.isNotBlank() }
        ?: return null
    val code = runCatching { json["code"]?.jsonPrimitive?.content }.getOrNull()
    return Refusal(status, message.replaceFirstChar { it.uppercase() }, code)
}

/** The server's own words when it refused; otherwise what the app says about signal and the like. */
fun apiWords(error: Throwable): String = refusalOf(error)?.message ?: readableError(error)

/** Whether this was the server saying "not found" — a match nobody has set up yet. */
fun isNotFound(error: Throwable): Boolean = error is HttpException && error.code() == 404

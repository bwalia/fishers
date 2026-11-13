package com.fishers.app.fixtures

import com.fishers.app.i18n.t
import com.fishers.app.session.readableError
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import retrofit2.HttpException

/** Whether the server said "there is none" — no match yet, no vote yet. */
internal fun Throwable.isNotFound(): Boolean = this is HttpException && code() == 404

/**
 * What to tell somebody when a fixture call fails.
 *
 * A refusal says so in words. Anything else the server explained — "a club
 * cannot play itself", "end_at must be after start_at" — is passed on, because
 * "HTTP 400" tells a secretary nothing about which box to change. The rest
 * goes through the app's usual wording.
 */
internal fun fixtureError(error: Throwable): String {
    if (error is HttpException) {
        when (error.code()) {
            403 -> return t("rest.no_permission_to_do_that")
            in 400..499 -> if (error.code() != 401 && error.code() != 429) {
                serverMessage(error)?.let { return it }
            }
        }
    }
    return readableError(error)
}

private fun serverMessage(error: HttpException): String? = runCatching {
    val body = error.response()?.errorBody()?.string() ?: return null
    Json.parseToJsonElement(body).jsonObject["error"]?.jsonPrimitive?.content
}.getOrNull()?.takeIf { it.isNotBlank() }?.replaceFirstChar { it.uppercase() }

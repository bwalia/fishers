package com.fishers.app.profile

import com.fishers.app.i18n.t
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import retrofit2.HttpException

/**
 * What the API said when it refused: `{"error": "…", "code": "…"}`.
 *
 * The `code` is the machine-readable reason a screen can act on —
 * `unverified` means "send them to confirm a contact", not "show an error".
 * `readableError` cannot be used for these screens: it reads a 401 as a wrong
 * password, which is the sign-in form's meaning and nobody else's.
 */
data class ApiFailure(val status: Int?, val message: String?, val code: String?) {
    val isUnverified: Boolean get() = code == "unverified"
    val isRemovedFromClub: Boolean get() = code == "removed_from_club"

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun of(failure: Throwable): ApiFailure {
            if (failure !is HttpException) return ApiFailure(null, null, null)
            // Read once: an error body is a stream, and a second read is empty.
            val body = runCatching { failure.response()?.errorBody()?.string() }.getOrNull()
            val fields = body?.let { runCatching { json.parseToJsonElement(it).jsonObject }.getOrNull() }
            return ApiFailure(
                status = failure.code(),
                message = fields?.get("error")?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() },
                code = fields?.get("code")?.jsonPrimitive?.contentOrNull,
            )
        }
    }
}

/**
 * What to put in front of somebody when a profile or onboarding call fails.
 *
 * The API's own sentence when it sent one — it names the actual problem ("that
 * is not a JPEG, PNG or WebP") — and otherwise the general words for the kind
 * of failure. No signal reads as no signal.
 *
 * Pass [api] when the caller has already read the failure for its code: the
 * body can only be read once.
 */
fun profileError(
    failure: Throwable,
    api: ApiFailure = ApiFailure.of(failure),
    fallbackKey: String = "rest.something_went_wrong_try_again",
): String {
    if (failure is java.io.IOException) return t("rest.no_connection_check_signal")
    return when {
        api.isRemovedFromClub -> t("jl.removed_from_club")
        api.isUnverified -> t("rest.starting_club_needs_confirmed")
        api.status == 429 && api.message == null -> t("rest.too_many_tries")
        api.status != null && api.status >= 500 -> t("rest.server_having_trouble")
        api.message != null -> api.message.replaceFirstChar { it.uppercaseChar() }
        else -> t(fallbackKey)
    }
}

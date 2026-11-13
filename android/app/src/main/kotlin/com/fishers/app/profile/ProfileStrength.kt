package com.fishers.app.profile

import com.fishers.app.i18n.t

/**
 * How much of a profile is filled in, and what is worth adding next —
 * `ProfileStrength.swift`.
 *
 * Nothing here is needed to use the app: a name and a sport get somebody
 * picked. The rest is what makes a player someone a captain recognises, so it
 * is counted and asked for, never demanded. Same order and weights as the
 * API's count (`ProfileStrength::of`), so the phone and the server say the same
 * next thing — counted here rather than read from the server only because the
 * server's sentence is English.
 */
class ProfileStrength(me: Me) {
    data class Item(val id: String, private val titleKey: String, val weight: Int, val done: Boolean) {
        val title: String get() = t(titleKey)
    }

    val items: List<Item> = run {
        val main = me.primaryProfile
        val location = me.location
        listOf(
            Item("name", "rest.your_name", 10, me.name.isNotBlank()),
            Item("sport", "rest.what_you_play", 15, main != null),
            Item("phone", "rest.your_mobile_number", 10, me.phone.nonEmpty() != null),
            Item("photo", "rest.a_photo", 15, me.avatarUrl.nonEmpty() != null),
            Item("standard", "rest.the_standard_you_play_at", 15, main?.skillLevel.nonEmpty() != null),
            Item("position", "rest.your_position", 10, main?.position.nonEmpty() != null),
            Item("verified", "rest.a_confirmed_email_or_number", 10, me.isVerified),
            Item(
                "area", "rest.where_youre_based", 5,
                location?.area.nonEmpty() != null || location?.postcode.nonEmpty() != null,
            ),
            Item("travel", "rest.how_you_get_to_games", 5, location?.transport != null),
            Item("emergency", "rest.an_emergency_contact", 5, me.emergencyContact.nonEmpty() != null),
        )
    }

    val percent: Int get() = items.filter { it.done }.sumOf { it.weight }
    val isComplete: Boolean get() = percent >= 100

    /** Most valuable first; a stable sort, so equal weights keep the order above. */
    val missing: List<Item> get() = items.filterNot { it.done }.sortedByDescending { it.weight }

    /** "Add a photo, the standard you play at and your position" — the three that count most. */
    val nextUp: String
        get() {
            val top = missing.take(3).map { it.title.replaceFirstChar { c -> c.lowercaseChar() } }
            return when (top.size) {
                0 -> ""
                1 -> t("rest.add_one_thing", vars = mapOf("thing" to top[0]))
                else -> t(
                    "rest.add_list_and_last",
                    vars = mapOf("list" to top.dropLast(1).joinToString(", "), "last" to top.last()),
                )
            }
        }
}

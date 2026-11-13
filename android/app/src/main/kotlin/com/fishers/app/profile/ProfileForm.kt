package com.fishers.app.profile

/**
 * Editable copy of everything on a player's profile — `ProfileFormModel.swift`.
 *
 * Immutable, so each edit is a `copy` the view model swaps in, and what a save
 * sends is a function of this alone ([toUpdate]) — the part worth testing.
 */
data class ProfileForm(
    val name: String = "",
    val phone: String = "",
    val emergencyContact: String = "",
    /** Ordered: the first pick is offered as the main sport. */
    val selectedSports: List<Sport> = emptyList(),
    val primarySport: Sport? = null,
    /** Keyed by the sport's wire name. Kept for a sport until it is deselected. */
    val details: Map<String, SportProfile> = emptyMap(),
    val area: String = "",
    val postcode: String = "",
    val travelRadiusMiles: Int = 10,
    val transport: TransportMode? = null,
    val spareSeats: Int = 0,
    val preferredDays: Set<Int> = emptySet(),
    val notes: String = "",
) {
    val isNameValid: Boolean get() = name.isNotBlank()

    fun isSelected(sport: Sport) = sport in selectedSports

    /** On, or off — and off forgets that sport's details, as iOS does. */
    fun toggle(sport: Sport): ProfileForm =
        if (sport in selectedSports) {
            val left = selectedSports - sport
            copy(
                selectedSports = left,
                details = details - sport.wire,
                primarySport = if (primarySport == sport) left.firstOrNull() else primarySport,
            )
        } else {
            copy(selectedSports = selectedSports + sport, primarySport = primarySport ?: sport)
        }

    fun detail(sport: Sport): SportProfile = details[sport.wire] ?: SportProfile(sport = sport.wire)

    fun mutate(sport: Sport, change: (SportProfile) -> SportProfile): ProfileForm =
        copy(details = details + (sport.wire to change(detail(sport))))

    /** Stats are stored as strings; blank removes the entry rather than storing "". */
    fun withStat(sport: Sport, key: String, value: String): ProfileForm = mutate(sport) { profile ->
        profile.copy(stats = if (value.isBlank()) profile.stats - key else profile.stats + (key to value))
    }

    fun toUpdate(): ProfileUpdate = ProfileUpdate.of(
        name = name.trim(),
        sportProfiles = selectedSports.map(::detail),
        primarySport = (primarySport ?: selectedSports.firstOrNull())?.wire,
        phone = phone.nonEmpty(),
        emergencyContact = emergencyContact.nonEmpty(),
        location = PlayerLocation(
            area = area.nonEmpty(),
            postcode = postcode.nonEmpty(),
            travelRadiusMiles = travelRadiusMiles,
            transport = transport?.wire,
            spareSeats = if (transport?.offersLifts == true) spareSeats else null,
            preferredDays = preferredDays.sorted().takeIf { it.isNotEmpty() },
            notes = notes.nonEmpty(),
        ),
    )

    companion object {
        fun from(me: Me?): ProfileForm {
            if (me == null) return ProfileForm()
            val profiles = me.sportProfiles
            val location = me.location
            return ProfileForm(
                name = me.name,
                phone = me.phone.orEmpty(),
                emergencyContact = me.emergencyContact.orEmpty(),
                selectedSports = profiles.mapNotNull { it.sportKind }.distinct(),
                primarySport = Sport.named(me.primarySport) ?: profiles.firstNotNullOfOrNull { it.sportKind },
                // Keyed by the canonical spelling, so an old "padel" profile is
                // found again under "paddle" and saved back under it.
                details = profiles.mapNotNull { p -> p.sportKind?.let { it.wire to p.copy(sport = it.wire) } }.toMap(),
                area = location?.area.orEmpty(),
                postcode = location?.postcode.orEmpty(),
                travelRadiusMiles = location?.travelRadiusMiles ?: 10,
                transport = location?.transportMode,
                spareSeats = location?.spareSeats ?: 0,
                preferredDays = location?.preferredDays.orEmpty().toSet(),
                notes = location?.notes.orEmpty(),
            )
        }
    }
}

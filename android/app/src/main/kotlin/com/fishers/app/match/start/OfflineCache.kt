package com.fishers.app.match.start

import android.content.Context
import com.fishers.app.clubs.Club
import com.fishers.app.clubs.ClubMemberDetail
import com.fishers.app.clubs.Team
import com.fishers.app.net.MatchStartApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.io.File

/**
 * What starting a match needs that only the server knows — your clubs, their
 * teams, who plays for them — saved the last time there was signal, for a
 * ground that has none. `OfflineCache.swift`.
 *
 * A player is kept as a team sheet needs them and no more: an id, a name,
 * whether they captain. A roster's phone numbers and addresses have no
 * business in a file kept for picking a batting order.
 */
class OfflineCache(private val dir: File) {

    @Serializable
    data class Player(
        val id: String,
        val name: String,
        @SerialName("is_captain") val isCaptain: Boolean = false,
    )

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private val clubs = ListSerializer(Club.serializer())
    private val teams = ListSerializer(Team.serializer())
    private val players = ListSerializer(Player.serializer())

    /** Clubs where you may put a fixture in (`manage_events`), as last heard. */
    fun saveStartableClubs(list: List<Club>) = write("startable-clubs", clubs, list)

    /** Null when this phone has never been told — which is not the same as none. */
    fun startableClubs(): List<Club>? = read("startable-clubs", clubs)

    fun saveTeams(clubId: String, list: List<Team>) = write("teams-${safe(clubId)}", teams, list)

    fun teams(clubId: String): List<Team> = read("teams-${safe(clubId)}", teams).orEmpty()

    fun saveRoster(clubId: String, members: List<ClubMemberDetail>) = write(
        "roster-${safe(clubId)}",
        players,
        members.filter { it.isOnTheBooks }.map { Player(it.userId, it.name, it.isCaptain) },
    )

    fun roster(clubId: String): List<Player> = read("roster-${safe(clubId)}", players).orEmpty()

    private fun safe(id: String) = id.filter { it.isLetterOrDigit() || it == '-' }

    private fun <T> read(name: String, serializer: KSerializer<T>): T? = synchronized(lock) {
        val f = File(dir, "$name.json")
        if (!f.exists()) return@synchronized null
        runCatching { json.decodeFromString(serializer, f.readText()) }.getOrNull()
    }

    /** A side file renamed over the old one, so a half-written file is never what is read. */
    private fun <T> write(name: String, serializer: KSerializer<T>, value: T) {
        synchronized(lock) {
            runCatching {
                dir.mkdirs()
                val target = File(dir, "$name.json")
                val temp = File(dir, "$name.json.tmp")
                temp.writeText(json.encodeToString(serializer, value))
                if (!temp.renameTo(target)) {
                    target.delete()
                    temp.renameTo(target)
                }
            }
        }
    }

    companion object {
        private val lock = Any()

        fun forApp(context: Context) = OfflineCache(File(context.applicationContext.filesDir, "offline-cache"))
    }
}

/**
 * Each club's teams and players, while there is signal to fetch them. Best
 * effort: a club that will not answer keeps what was saved for it before.
 */
suspend fun OfflineCache.warm(api: MatchStartApi, clubs: List<Club>) {
    for (club in clubs) {
        runCatching { api.clubTeams(club.id) }.onSuccess { saveTeams(club.id, it) }
        runCatching { api.clubMembers(club.id) }.onSuccess { saveRoster(club.id, it) }
    }
}

/**
 * The clubs you may start a match for, read now and saved for the day there
 * is no signal — with their teams and players. Throws when the clubs cannot be
 * read, and then nothing saved before is touched.
 */
suspend fun OfflineCache.refresh(api: MatchStartApi): List<Club> {
    val startable = startableOf(api, api.myClubs())
    saveStartableClubs(startable)
    warm(api, startable)
    return startable
}

/** Of [clubs], those where this person may put a fixture in — what iOS offers "Start a match" for. */
internal suspend fun startableOf(api: MatchStartApi, clubs: List<Club>): List<Club> = clubs.filter { club ->
    runCatching { api.myClubRole(club.id) }.getOrNull()?.permissions?.contains("manage_events") == true
}

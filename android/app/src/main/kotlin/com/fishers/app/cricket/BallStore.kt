package com.fishers.app.cricket

import android.content.Context
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/**
 * A match's book as this phone holds it: the whole log, and which of it the
 * server has not acknowledged yet.
 *
 * The whole log rather than only the unsent part, so a scorer who loses
 * signal and then closes the app can open the match again at the ground and
 * carry on — the engine replays it here exactly as the server would.
 */
@Serializable
data class StoredBook(
    @SerialName("event_id") val eventId: String,
    @SerialName("match_id") val matchId: String,
    /** The match as last heard from the server, for opening it with no signal. */
    val match: CricketMatch? = null,
    val log: List<ScoringEvent> = emptyList(),
    /** `client_event_id`s scored here that the server has not confirmed. */
    val pending: List<String> = emptyList(),
    /**
     * Balls that were scored here but could not be put back on top of the
     * server's book — somebody else scored over them while this phone was
     * offline. Never thrown away: they are the scorer's record of the over.
     */
    val stranded: List<ScoringEvent> = emptyList(),
) {
    val unsent: List<ScoringEvent>
        get() = pending.toSet().let { ids -> log.filter { it.clientEventId in ids } }
}

/**
 * Where books are kept. Every write is a read-modify-write of the stored copy
 * under one lock, never "save what I have in memory": two screens on the same
 * match (one leaving, one opening) must not overwrite each other's balls.
 */
interface BallStore {
    fun read(eventId: String): StoredBook?

    /** Change the stored book in one step. `null` in, when nothing is stored yet. */
    fun update(eventId: String, change: (StoredBook?) -> StoredBook?): StoredBook?

    /** Every book with something still to send — for a sweep at launch. */
    fun withUnsent(): List<StoredBook>
}

/** One small JSON file a match, in the app's own storage. */
class FileBallStore(private val dir: File) : BallStore {

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private fun file(eventId: String) = File(dir, "${eventId.filter { it.isLetterOrDigit() || it == '-' }}.json")

    override fun read(eventId: String): StoredBook? = synchronized(lock) { readLocked(eventId) }

    override fun update(eventId: String, change: (StoredBook?) -> StoredBook?): StoredBook? = synchronized(lock) {
        val next = change(readLocked(eventId))
        if (next == null) {
            file(eventId).delete()
        } else {
            write(eventId, next)
        }
        next
    }

    override fun withUnsent(): List<StoredBook> = synchronized(lock) {
        dir.listFiles { f -> f.name.endsWith(".json") }.orEmpty()
            .mapNotNull { readLocked(it.name.removeSuffix(".json")) }
            .filter { it.pending.isNotEmpty() }
    }

    private fun readLocked(eventId: String): StoredBook? {
        val f = file(eventId)
        if (!f.exists()) return null
        return runCatching { json.decodeFromString(StoredBook.serializer(), f.readText()) }.getOrNull()
    }

    /**
     * Written to a side file and renamed over the old one, so a phone that
     * dies mid-write leaves the last good book rather than half of a new one.
     */
    private fun write(eventId: String, book: StoredBook) {
        dir.mkdirs()
        val target = file(eventId)
        val temp = File(dir, target.name + ".tmp")
        temp.writeText(json.encodeToString(StoredBook.serializer(), book))
        if (!temp.renameTo(target)) {
            target.delete()
            temp.renameTo(target)
        }
    }

    companion object {
        private val lock = Any()

        /** The app's own: nothing else reads it, and it goes with an uninstall. */
        fun forApp(context: Context) = FileBallStore(File(context.applicationContext.filesDir, "cricket-books"))
    }
}

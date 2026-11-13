package com.fishers.app.cricket

import android.content.Context
import com.fishers.app.match.start.PendingCreate
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
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
    /**
     * A match started with no signal: what the server still has to be told
     * before any of the log can go up — the club, the fixture, the match.
     * Null once it has all three, and for every match that began online.
     */
    val create: PendingCreate? = null,
    /**
     * Left where a book used to be when it moved to the fixture's id on the
     * server ([BallStore.move]), pointing on — so a screen opened before the
     * move still finds the match by the id it was given.
     */
    @SerialName("moved_to") val movedTo: String? = null,
) {
    val unsent: List<ScoringEvent>
        get() = pending.toSet().let { ids -> log.filter { it.clientEventId in ids } }

    /** Balls among the unsent. The setup's events go up too, but nobody calls those balls. */
    val unsentBalls: Int
        get() = unsent.count { it.kind["type"]?.jsonPrimitive?.contentOrNull in BALLS }

    /** Anything at all the server has not got. */
    val hasWork: Boolean get() = create != null || pending.isNotEmpty()
}

private val BALLS = setOf("delivery_recorded", "extras_recorded", "wicket_recorded")

/** A book put back together, and the engine's state for its log. */
internal class Merged(val book: StoredBook, val state: String)

/**
 * The server's book, with anything this phone scored that it has not got
 * laid back on top — renumbered after the server's last ball, and each one
 * checked by the engine again. One the engine now refuses (somebody else
 * scored over it while this phone was offline) is kept aside, never dropped.
 *
 * Renumbering is what makes this safe: the server skips, without a word, an
 * event whose number it already holds — so a ball sent under a stale number
 * would be lost on the server even though it was sent.
 */
internal fun Engine.merge(
    eventId: String,
    match: CricketMatch,
    serverLog: List<ScoringEvent>,
    serverState: String,
    held: StoredBook?,
): Merged {
    val serverIds = serverLog.map { it.clientEventId }.toSet()
    val sameMatch = held?.matchId == match.id
    val mine = held?.takeIf { sameMatch }?.unsent.orEmpty().filter { it.clientEventId !in serverIds }
    val log = serverLog.toMutableList()
    val pending = mutableListOf<String>()
    val stranded = held?.stranded.orEmpty().toMutableList()
    // The fixture's match was set up again under a new id: what this phone
    // held for the old one cannot go into the new book, and must not vanish.
    if (held != null && !sameMatch) stranded += held.unsent
    var folded = serverState
    for (event in mine) {
        val renumbered = event.copy(seq = lastSeq(folded) + 1)
        next(log, folded, renumbered)
            .onSuccess {
                folded = it
                log += renumbered
                pending += renumbered.clientEventId
            }
            .onFailure { stranded += event }
    }
    return Merged(StoredBook(eventId, match.id, match, log, pending, stranded), folded)
}

/**
 * Where books are kept. Every write is a read-modify-write of the stored copy
 * under one lock, never "save what I have in memory": two screens on the same
 * match (one leaving, one opening) must not overwrite each other's balls.
 *
 * A book that has moved ([move]) is still found by its old id: reads and
 * writes follow it to where it went.
 */
interface BallStore {
    fun read(eventId: String): StoredBook?

    /** Change the stored book in one step. `null` in, when nothing is stored yet. */
    fun update(eventId: String, change: (StoredBook?) -> StoredBook?): StoredBook?

    /** Every book with something still to send — for a sweep at launch. */
    fun withUnsent(): List<StoredBook>

    /** Every book on this phone, the most recently written first. */
    fun all(): List<StoredBook>

    /**
     * File the book under [to] — the fixture's id on the server, once it has
     * one — and leave [from] pointing there. Safe to repeat.
     */
    fun move(from: String, to: String): StoredBook?

    /** The id a book is filed under now: [eventId], or where it moved to. */
    fun resolve(eventId: String): String = read(eventId)?.eventId ?: eventId
}

/** One small JSON file a match, in the app's own storage. */
class FileBallStore(private val dir: File) : BallStore {

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private fun file(eventId: String) = File(dir, "${eventId.filter { it.isLetterOrDigit() || it == '-' }}.json")

    override fun read(eventId: String): StoredBook? = synchronized(lock) { readLocked(where(eventId)) }

    override fun update(eventId: String, change: (StoredBook?) -> StoredBook?): StoredBook? = synchronized(lock) {
        val key = where(eventId)
        val next = change(readLocked(key))
        if (next == null) {
            file(key).delete()
        } else {
            write(key, next)
        }
        next
    }

    override fun withUnsent(): List<StoredBook> = all().filter { it.hasWork }

    override fun all(): List<StoredBook> = synchronized(lock) {
        dir.listFiles { f -> f.name.endsWith(".json") }.orEmpty()
            .sortedByDescending { it.lastModified() }
            .mapNotNull { readLocked(it.name.removeSuffix(".json")) }
            .filter { it.movedTo == null }
    }

    override fun move(from: String, to: String): StoredBook? = synchronized(lock) {
        if (from == to) return@synchronized readLocked(to)
        val book = readLocked(from) ?: return@synchronized readLocked(to)
        if (book.movedTo != null) return@synchronized readLocked(book.movedTo)
        // The new file first: a phone that dies between the two writes has
        // the book twice and moves it again next time — never none.
        val moved = book.copy(eventId = to, match = book.match?.copy(eventId = to))
        write(to, moved)
        write(from, StoredBook(eventId = from, matchId = book.matchId, movedTo = to))
        moved
    }

    /** Where [eventId]'s book is kept now: one step on, if it moved. */
    private fun where(eventId: String): String = readLocked(eventId)?.movedTo ?: eventId

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

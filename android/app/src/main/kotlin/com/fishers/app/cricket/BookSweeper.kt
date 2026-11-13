package com.fishers.app.cricket

import com.fishers.app.net.ScoringApi
import kotlinx.coroutines.CancellationException

/**
 * Balls left on this phone from a match nobody has opened since — the app was
 * killed mid-over and the scorer went home. `sweepOthers` in
 * `CricketSyncService.swift`.
 *
 * Each book is laid back on top of the server's, exactly as opening the
 * match would ([merge]), then sent. Anything that fails stays on the disk for
 * the next sweep or the next time the match is opened; nothing here deletes a
 * ball.
 */
class BookSweeper(
    private val api: ScoringApi,
    private val store: BallStore,
    private val deviceId: String,
    private val engine: Engine = Engine(),
) {
    /** Send every book's unsent balls but [skip]'s — the match on screen sends its own. Returns how many went. */
    suspend fun sendLeftovers(skip: String? = null): Int {
        var sent = 0
        for (book in store.withUnsent()) {
            if (book.eventId == skip) continue
            try {
                sent += send(book)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                // No signal, or the book is somebody else's now: it waits.
            }
        }
        return sent
    }

    private suspend fun send(book: StoredBook): Int {
        val match = api.match(book.matchId)
        val serverLog = api.events(book.matchId)
        val serverState = engine.replay(serverLog).getOrNull() ?: return 0
        val merged = store.update(book.eventId) { held -> engine.merge(book.eventId, match, serverLog, serverState, held).book }
        val unsent = merged?.unsent.orEmpty()
        if (unsent.isEmpty()) return 0
        api.postEvents(match.id, EventsBatch(deviceId = deviceId, events = unsent.take(500)))
        val gone = unsent.take(500).map { it.clientEventId }.toSet()
        store.update(book.eventId) { held -> held?.copy(pending = held.pending.filterNot { it in gone }) }
        return gone.size
    }
}

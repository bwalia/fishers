package com.fishers.app.match.start

import com.fishers.app.cricket.BallStore
import com.fishers.app.cricket.CricketMatch
import com.fishers.app.cricket.StoredBook
import com.fishers.app.net.MatchStartApi
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import retrofit2.HttpException
import java.time.Instant

// A match played with no signal, start to finish: started on the phone, set
// up on the phone, scored on the phone — and put on the server, in order, the
// next time there is a network. `CricketSyncService.swift`'s offline create.

/**
 * What the server has not been told yet about a match started on this phone,
 * kept in the match's book ([StoredBook.create]) until it has.
 *
 * Each step is written back as it lands, so a sync that stops part way — the
 * signal going again, the app killed — carries on from there next time.
 */
@Serializable
data class PendingCreate(
    /** The club to make first, for somebody who had none to play for. */
    val club: NewClub? = null,
    /** The club the fixture is for, once there is one. */
    @SerialName("club_id") val clubId: String? = null,
    /** The clubs this person was in before [club] was asked for — so the one a lost answer made can be told apart. */
    @SerialName("clubs_before") val clubsBefore: List<String>? = null,
    @SerialName("club_asked") val clubAsked: Boolean = false,
    /** The fixture to make; its `club_id` is filled in once the club exists. Null for one the server has. */
    val fixture: NewFixture? = null,
    @SerialName("fixture_asked") val fixtureAsked: Boolean = false,
    /** The fixture's id on the server, once it has one. */
    @SerialName("server_event_id") val serverEventId: String? = null,
    /** The match to make on it, under the id this phone gave it. Written when the terms are first put. */
    val match: NewMatch? = null,
    /** Why the server last said no, in its own words — "confirm your email first", say. */
    val problem: String? = null,
)

/**
 * Puts a match that was started with no signal on the server — the club (for
 * somebody who had none), the fixture, the match under the id this phone gave
 * it, the book claimed for this phone — after which its log goes up like any
 * other ([com.fishers.app.cricket.BookSweeper], the scorer).
 *
 * The server picks the fixture's id, so the book moves to it
 * ([BallStore.move]); the phone's id is left pointing there, for a screen that
 * is still holding it. The match keeps the phone's id: the server takes the
 * one it is given.
 *
 * `POST /clubs` and `POST /events` make a second one when asked twice, so
 * neither is asked twice blind: the book says "asked" before the question goes,
 * and a later try first looks for what an answer that never arrived made —
 * the club by its name among clubs that were not there before, the fixture by
 * the phone's id in its metadata. The match is create-or-get by fixture, the
 * claim is by device and the events are by `client_event_id`, so those are safe
 * to send again as they are.
 */
class MatchRegistrar(
    private val api: MatchStartApi,
    private val store: BallStore,
    private val deviceId: String,
) {
    /**
     * Put [eventId]'s match on the server if it is not there yet, and hand back
     * its book — filed under the server's id once there is one. Throws when a
     * step fails; whatever landed before it is kept for the next try.
     */
    suspend fun register(eventId: String): StoredBook = lock.withLock {
        val book = checkNotNull(store.read(eventId)) { "no book on this phone for $eventId" }
        val create = book.create ?: return@withLock book
        // Nothing is made until the terms are put: a match left on its first
        // page is not worth a fixture in somebody's diary.
        if (create.match == null) return@withLock book
        try {
            steps(book, create)
        } catch (e: HttpException) {
            store.update(eventId) { held -> held?.copy(create = held.create?.copy(problem = apiWords(e))) }
            throw e
        }
    }

    private suspend fun steps(start: StoredBook, first: PendingCreate): StoredBook {
        var book = start
        var create = first
        fun keep(next: PendingCreate) {
            create = next
            book = store.update(book.eventId) { held -> (held ?: book).copy(create = next) } ?: book
        }

        // 1. The club, for somebody who had none to play for.
        if (create.serverEventId == null && create.clubId == null) {
            val wanted = checkNotNull(create.club) { "no club to make" }
            val mine = api.myClubs()
            val before = create.clubsBefore.orEmpty().toSet()
            val made = if (create.clubAsked) mine.firstOrNull { it.name == wanted.name && it.id !in before } else null
            val clubId = made?.id ?: run {
                keep(create.copy(clubsBefore = create.clubsBefore ?: mine.map { it.id }, clubAsked = true))
                api.createClub(wanted).id
            }
            keep(create.copy(clubId = clubId))
        }

        // 2. The fixture. The server picks its id; the book follows it.
        if (create.serverEventId == null) {
            val fixture = checkNotNull(create.fixture) { "no fixture to make" }
                .copy(clubId = checkNotNull(create.clubId))
            val found = if (create.fixtureAsked) find(fixture) else null
            val id = found ?: run {
                keep(create.copy(fixtureAsked = true))
                api.createEvent(fixture).id
            }
            keep(create.copy(serverEventId = id))
        }
        val serverId = checkNotNull(create.serverEventId)
        if (book.eventId != serverId) book = checkNotNull(store.move(book.eventId, serverId))

        // 3. The match, under this phone's id.
        val made = api.createMatch(serverId, checkNotNull(create.match))
        if (made.id != book.matchId) {
            // The fixture had a match already, set up on another phone. What
            // this phone wrote cannot go into somebody else's book: it is kept
            // aside, as a ball somebody else scored over is — never dropped.
            book = checkNotNull(
                store.update(serverId) { held ->
                    val h = held ?: book
                    h.copy(matchId = made.id, match = null, log = emptyList(), pending = emptyList(), stranded = h.stranded + h.unsent)
                },
            )
        }

        // 4. The book is this phone's, as the setup would have claimed it.
        api.claimScorer(made.id, ClaimScorer(deviceId = deviceId, force = false))
        return checkNotNull(store.update(serverId) { held -> (held ?: book).copy(create = null) })
    }

    /** The fixture an earlier ask made, if it did: this club, this start, the phone's own id on it. */
    private suspend fun find(fixture: NewFixture): String? {
        val ref = fixture.metadata[FixtureInfo.CLIENT_REF] ?: return null
        val at = runCatching { Instant.parse(fixture.startAt) }.getOrNull() ?: return null
        return api.clubFixtures(fixture.clubId, at.minusSeconds(60).toString(), at.plusSeconds(60).toString())
            .items.firstOrNull { it.clientRef == ref }?.id
    }

    private companion object {
        /** One registration at a time in the whole app: two at once would both ask for the fixture. */
        val lock = Mutex()
    }
}

/**
 * The match as this phone holds it before the server has heard of it: this
 * phone may score it and holds its book, which is all the scorer asks.
 */
internal fun matchOnThePhone(
    matchId: String,
    eventId: String,
    homeName: String,
    awayName: String,
    oversLimit: Int,
    clubId: String?,
    opponentClubId: String?,
    deviceId: String,
    userId: String?,
) = CricketMatch(
    id = matchId,
    eventId = eventId,
    status = "scheduled",
    oversLimit = oversLimit,
    homeName = homeName,
    awayName = awayName,
    canScore = true,
    activeScorerUserId = userId,
    activeScorerDeviceId = deviceId,
    clubId = clubId,
    opponentClubId = opponentClubId,
    myClubSide = "home",
)

/** The server's match, as a book on this phone keeps it: claimed by this phone, which the setup has done. */
internal fun SetupMatch.onThePhone(deviceId: String) = CricketMatch(
    id = id,
    eventId = eventId,
    status = status,
    oversLimit = oversLimit,
    homeName = homeName,
    awayName = awayName,
    lastSeq = lastSeq,
    canScore = canScore,
    activeScorerUserId = activeScorerUserId,
    activeScorerDeviceId = deviceId,
    clubId = clubId.takeIf { it.isNotBlank() },
    opponentClubId = opponentClubId,
    myClubSide = myClubSide?.let { if (it == Side.Home) "home" else "away" },
)

/** A match whose book is on this phone, as "On this phone" lists it. */
data class PhoneMatch(
    val eventId: String,
    /** "Gully Kings v Southall Strikers". */
    val title: String,
    /** Balls scored here that the server has not got. */
    val unsentBalls: Int,
    /** Anything at all still to send: the match itself, its setup, balls. */
    val waiting: Boolean,
    /** Why the server last refused it, in its words. */
    val problem: String?,
    /** No innings yet: it opens on the setup rather than the scorer. */
    val settingUp: Boolean,
)

private val over = setOf("complete", "published")

/**
 * "On this phone": every match whose book is here and is not over and done
 * with — anything still to send, or a match still being played. Newest first.
 * It is the way back to a match at a ground with no signal, so it is read from
 * the disk and never waits on the network.
 */
fun phoneMatches(books: List<StoredBook>): List<PhoneMatch> = books
    .filter { it.hasWork || it.match?.status !in over }
    .map { book ->
        PhoneMatch(
            eventId = book.eventId,
            title = book.match?.let { "${it.homeName} v ${it.awayName}" } ?: book.create?.fixture?.title.orEmpty(),
            unsentBalls = book.unsentBalls,
            waiting = book.hasWork,
            problem = book.create?.problem,
            settingUp = book.log.none { it.kind["type"]?.jsonPrimitive?.contentOrNull == "innings_started" },
        )
    }

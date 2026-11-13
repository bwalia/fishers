package com.fishers.app.cricket

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.i18n.t
import com.fishers.app.match.start.MatchRegistrar
import com.fishers.app.net.ScoringApi
import com.fishers.app.session.readableError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import retrofit2.HttpException
import java.io.IOException
import java.time.Instant
import java.util.UUID

enum class SyncStatus { Saved, Syncing, Offline }

/** A live link, minted and waiting for the share sheet. */
data class ShareLink(val url: String, val headline: String)

/** One of the fielding side, and whether the engine would let them bowl now. */
data class BowlerChoice(
    val player: Player,
    val figures: String?,
    /** The engine's reason they may not bowl, or null when they may. */
    val refusal: String?,
    val isBowling: Boolean,
)

/** Somebody the book can be handed to. */
data class HandoverCandidate(val userId: String, val name: String, val group: String)

data class ScorerState(
    val loading: Boolean = true,
    val match: CricketMatch? = null,
    val view: MatchView? = null,
    /** Events written here that the server has not confirmed — balls, and the setup of a match started offline. */
    val unsent: Int = 0,
    /** Of those, the balls: what the bar counts for the scorer. */
    val unsentBalls: Int = 0,
    val sync: SyncStatus = SyncStatus.Saved,
    /** What the engine refused, in its own words — or why the match would not open. */
    val error: String? = null,
    /** Why the balls are not going up, when it is something other than signal. */
    val syncProblem: String? = null,
    /** Somebody else holds the book. A captain may take it from a dead phone. */
    val bookElsewhere: Boolean = false,
    val handedOver: Boolean = false,
    /** Balls this phone scored that somebody else's scoring overtook. Kept, not sent. */
    val stranded: Int = 0,
    val moment: Moment? = null,
    /** Bumped for every moment, so the same kind twice running still shows. */
    val momentCount: Int = 0,
    val notice: String? = null,
    val share: ShareLink? = null,
    val isWorking: Boolean = false,
    val candidates: List<HandoverCandidate> = emptyList(),
) {
    val canScore: Boolean get() = match?.canScore == true && !bookElsewhere && !handedOver
    val isLive: Boolean get() = canScore && view?.isLive == true
    val needsNewBowler: Boolean get() = canScore && view?.needsNewBowler == true
    val canUndo: Boolean get() = canScore && view?.innings?.isNotEmpty() == true
}

/**
 * The live scorer. `LiveScorerView.swift` and `CricketMatchStore.swift`.
 *
 * Every ball goes through the engine — the same Rust the server scores with —
 * before anything else happens to it. If the engine refuses, the scorer is
 * told why at the moment they tap, and nothing is kept or sent. If it accepts,
 * the ball is written to this phone's book on disk *first*, then shown, then
 * sent. So a ball scored with no signal is never lost: it is on the disk
 * before the screen moves, it survives the app being killed, and it goes up
 * the next time there is a network, the next ball is scored, or the match is
 * opened again.
 */
class LiveScorerViewModel(
    private val api: ScoringApi,
    private val eventId: String,
    private val deviceId: String,
    private val store: BallStore,
    private val myUserId: String? = null,
    /** Puts a match started with no signal on the server before its balls go. */
    private val registrar: MatchRegistrar? = null,
    private val engine: Engine = Engine(),
    private val newId: () -> String = { UUID.randomUUID().toString() },
    private val now: () -> String? = { Instant.now().toString() },
) : ViewModel() {

    private val _state = MutableStateFlow(ScorerState())
    val state: StateFlow<ScorerState> = _state.asStateFlow()

    /** The engine's own JSON, as it handed it back, and the log it is a fold of. */
    private var engineState: String? = null
    private var log: List<ScoringEvent> = emptyList()
    private var matchId: String? = null
    private var sending = false
    private var rereads = 0

    // ---- opening the match ----

    fun load() {
        viewModelScope.launch { open() }
    }

    internal suspend fun open() {
        _state.update { it.copy(loading = it.view == null, error = null) }
        val held = store.read(eventId)
        var stored = held
        // Started with no signal: the server has not heard of this match, so
        // it is put there first — or, with no signal still, scored from here.
        if (held?.create != null) {
            val registered = registrar?.let { runCatching { it.register(eventId) } }
                ?: Result.failure(IOException("not on the server yet"))
            val book = registered.getOrElse { failure ->
                if (failure is CancellationException) throw failure
                openFromPhone(held, failure)
                return
            }
            if (book.create != null) {
                // Not set up far enough to put on the server yet.
                openFromPhone(book, IOException("not on the server yet"))
                return
            }
            stored = book
        }
        // The book follows the fixture to its id on the server.
        val fixture = stored?.eventId ?: eventId
        val fetched = runCatching {
            val match = api.matchForEvent(fixture)
            match to api.events(match.id)
        }
        val (match, serverLog) = fetched.getOrElse { failure ->
            if (failure is CancellationException) throw failure
            if (stored != null) {
                openFromPhone(stored, failure)
            } else {
                _state.update {
                    it.copy(
                        loading = false,
                        error = if (failure is HttpException && failure.code() == 404) {
                            t("sc.no_match_on_this_fixture")
                        } else {
                            serverWords(failure)
                        },
                    )
                }
            }
            return
        }
        if (!adopt(match, serverLog)) return
        claimIfNeeded(match)
        send()
    }

    /**
     * The server's book, with anything this phone scored that it has not got
     * laid back on top — renumbered after the server's last ball, and each one
     * checked by the engine again. One the engine now refuses (somebody else
     * scored over it while this phone was offline) is kept aside, never dropped.
     */
    private fun adopt(match: CricketMatch, serverLog: List<ScoringEvent>): Boolean {
        val serverState = engine.replay(serverLog).getOrElse {
            // The log is the record. If it will not replay, say so rather than
            // draw a score made up from the last event that happened to parse.
            _state.update { s ->
                s.copy(loading = false, match = match, error = t("sc.book_would_not_replay", vars = mapOf("detail" to engine.reason(it))))
            }
            return false
        }
        var folded = serverState
        val book = store.update(eventId) { held ->
            engine.merge(match.eventId, match, serverLog, serverState, held).also { folded = it.state }.book
        }!!
        matchId = match.id
        log = book.log
        engineState = folded
        _state.update {
            it.copy(
                loading = false,
                match = match,
                view = engine.view(folded),
                unsent = book.pending.size,
                unsentBalls = book.unsentBalls,
                stranded = book.stranded.size,
                error = if (book.stranded.isNotEmpty()) {
                    t("sc.n_balls_could_not_be_added", count = book.stranded.size, vars = mapOf("n" to book.stranded.size))
                } else {
                    null
                },
            )
        }
        return true
    }

    /** No signal at the ground: carry on from what this phone already holds. */
    private fun openFromPhone(book: StoredBook, failure: Throwable) {
        val folded = engine.replay(book.log).getOrElse {
            _state.update { s -> s.copy(loading = false, error = engine.reason(it)) }
            return
        }
        matchId = book.matchId
        log = book.log
        engineState = folded
        _state.update {
            it.copy(
                loading = false,
                match = book.match,
                view = engine.view(folded),
                unsent = book.pending.size,
                unsentBalls = book.unsentBalls,
                stranded = book.stranded.size,
                sync = SyncStatus.Offline,
                syncProblem = if (failure is IOException) null else serverWords(failure),
            )
        }
    }

    /**
     * The setup normally claims the book for this phone before handing over.
     * If it did not — opened from a fixture, or on another phone — claim it
     * now; if somebody else has it, say so and offer the take-over.
     */
    private suspend fun claimIfNeeded(match: CricketMatch) {
        if (!match.canScore || match.activeScorerDeviceId == deviceId) return
        if (match.activeScorerUserId != null && myUserId != null && match.activeScorerUserId != myUserId) {
            _state.update { it.copy(bookElsewhere = true) }
            return
        }
        runCatching { api.claimScorer(match.id, ClaimScorerBody(deviceId, force = false)) }
            .onSuccess { claimed -> _state.update { it.copy(match = claimed, bookElsewhere = false) } }
            .onFailure { failure ->
                if (failure is CancellationException) throw failure
                if (failure is HttpException && failure.code() == 409) {
                    _state.update { it.copy(bookElsewhere = true) }
                }
            }
    }

    // ---- scoring ----

    fun runs(n: Int, shot: Shot? = null) = record(Events.delivery(n, shot = shot))

    fun extra(kind: String, runs: Int = 0, boundary: Boolean = false, offTheBat: Boolean = false, shot: Shot? = null) =
        record(Events.extra(kind, runs, boundary, offTheBat, shot))

    fun wicket(
        batterId: String,
        kind: String,
        fielderId: String? = null,
        newBatterId: String? = null,
        runs: Int = 0,
        onExtra: Boolean = false,
    ) = record(Events.wicket(batterId, kind, fielderId, newBatterId, runs, onExtra))

    /** The engine refuses the same bowler twice running; its reason is shown. */
    fun changeBowler(bowlerId: String) = record(Events.bowlerChanged(bowlerId))

    fun undo() = record(Events.undo())

    /** Openers and a bowler for the innings about to start. */
    fun startInnings(strikerId: String, nonStrikerId: String, bowlerId: String): Boolean {
        val view = _state.value.view ?: return false
        val batting = if (view.innings.isEmpty()) view.firstBatting else view.nextBatting ?: return false
        return record(
            Events.inningsStarted(
                index = view.innings.size,
                batting = batting,
                strikerId = strikerId,
                nonStrikerId = nonStrikerId,
                bowlerId = bowlerId,
                superOver = view.nextIsSuperOver,
            ),
        )
    }

    fun endInnings(declared: Boolean = false, forfeited: Boolean = false) =
        record(Events.inningsCompleted(declared, forfeited))

    /** A declaration game that ran out of time. */
    fun drawn() = record(Events.matchCompleted(null, "Match drawn"))

    fun award(playerId: String) = record(Events.playerOfTheMatch(playerId))

    fun penalty(runs: Int, reason: String, toSide: String?) = record(Events.penaltyRuns(runs, reason, toSide))

    /** Why the engine would refuse this now, or null — for greying out "Out" with a reason. */
    fun check(kind: JsonObject): String? {
        val current = engineState ?: return t("sc.loading_match")
        return engine.refusal(current, probe(current, kind))
    }

    /** Everybody in the field, and the engine's answer for each: may they bowl now? */
    fun bowlerChoices(): List<BowlerChoice> {
        val current = engineState ?: return emptyList()
        val view = _state.value.view ?: return emptyList()
        val inn = view.current ?: return emptyList()
        return view.players(inn.bowling).map { player ->
            BowlerChoice(
                player = player,
                figures = inn.bowler(player.id)?.takeIf { it.balls > 0 || it.runs > 0 }?.figures,
                refusal = engine.refusal(current, probe(current, Events.bowlerChanged(player.id))),
                isBowling = inn.bowlerId == player.id,
            )
        }
    }

    /**
     * Check, keep, show, send — in that order.
     *
     * Kept on disk before the screen moves, so the app being killed between
     * the tap and the send loses nothing. Returns whether the engine took it,
     * so a sheet only closes on a ball that counted.
     */
    internal fun record(kind: JsonObject): Boolean {
        val current = engineState ?: return false
        val id = matchId ?: return false
        if (!_state.value.canScore) return false

        // Numbered from the engine's own state: a sequence the log already
        // holds is a duplicate, skipped without a word.
        val event = ScoringEvent(clientEventId = newId(), seq = engine.lastSeq(current) + 1, kind = kind, at = now())
        val next = engine.next(log, current, event).getOrElse {
            _state.update { s -> s.copy(error = engine.reason(it)) }
            return false
        }
        // A ball that cannot be kept on the phone is not taken at all: shown
        // but not saved, it would be lost the moment the app was.
        val book = runCatching {
            store.update(eventId) { held ->
                val base = held ?: StoredBook(eventId, id, _state.value.match)
                base.copy(log = base.log + event, pending = base.pending + event.clientEventId)
            }!!
        }.getOrElse {
            _state.update { s -> s.copy(error = t("sc.could_not_save_ball")) }
            return false
        }
        log = log + event
        engineState = next
        val before = _state.value.view
        val after = engine.view(next)
        val moment = Moment.between(before, after)
        _state.update {
            it.copy(
                view = after,
                unsent = book.pending.size,
                unsentBalls = book.unsentBalls,
                error = null,
                moment = moment ?: it.moment,
                momentCount = if (moment != null) it.momentCount + 1 else it.momentCount,
            )
        }
        flush()
        return true
    }

    private fun probe(state: String, kind: JsonObject) =
        ScoringEvent(clientEventId = PROBE_ID, seq = engine.lastSeq(state) + 1, kind = kind)

    // ---- sending ----

    /** Fire and forget: scoring never waits on the network. */
    fun flush() {
        viewModelScope.launch { send() }
    }

    /** The network came back. */
    fun onNetworkAvailable() = flush()

    /**
     * While the screen is in front: send whatever is waiting now, then try
     * again every [every] ms for as long as anything is. The screen runs this
     * and cancels it, so nothing retries once the scorer has gone.
     */
    suspend fun keepSending(every: Long = 15_000) {
        while (true) {
            if (_state.value.unsent > 0) send()
            delay(every)
        }
    }

    /**
     * Send everything unconfirmed, oldest first, until nothing is left or
     * something stops it. One at a time: a ball scored while a batch is in
     * flight goes in the next one, never in two.
     */
    internal suspend fun send() {
        val id = matchId ?: return
        if (sending || _state.value.handedOver) return
        sending = true
        try {
            // A match started with no signal goes on the server first; then
            // it is opened again from there, which sends what is waiting.
            if (store.read(eventId)?.create != null) {
                val registrar = registrar ?: return
                _state.update { it.copy(sync = SyncStatus.Syncing) }
                val registered = try {
                    registrar.register(eventId)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    notSent(e)
                    return
                }
                if (registered.create != null) {
                    _state.update { it.copy(sync = SyncStatus.Offline) }
                    return
                }
                sending = false
                open()
                return
            }
            while (true) {
                val unsent = store.read(eventId)?.unsent.orEmpty()
                if (unsent.isEmpty()) {
                    _state.update { it.copy(sync = SyncStatus.Saved, unsent = 0, unsentBalls = 0) }
                    return
                }
                _state.update { it.copy(sync = SyncStatus.Syncing) }
                val batch = unsent.take(MAX_BATCH)
                val reply = try {
                    api.postEvents(id, EventsBatch(deviceId = deviceId, events = batch))
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    notSent(e)
                    return
                }
                val sent = batch.map { it.clientEventId }.toSet()
                val book = store.update(eventId) { held ->
                    held?.copy(pending = held.pending.filterNot { it in sent }, match = reply)
                }
                _state.update {
                    it.copy(
                        match = reply,
                        unsent = book?.pending?.size ?: 0,
                        unsentBalls = book?.unsentBalls ?: 0,
                        syncProblem = null,
                        bookElsewhere = false,
                    )
                }
                // The server numbers its book itself. If it ends short of the
                // last ball sent, it skipped some as already-held numbers —
                // its book and this phone's have parted, and the way back is
                // to read its book and lay the unsent balls on top again.
                // Once: a second parting in a row is for a person to look at.
                if (reply.lastSeq < batch.last().seq) {
                    if (rereads++ == 0) {
                        sending = false
                        open()
                    } else {
                        _state.update { it.copy(syncProblem = t("sc.books_disagree")) }
                    }
                    return
                }
                rereads = 0
            }
        } finally {
            sending = false
        }
    }

    private fun notSent(e: Throwable) {
        when {
            // Ordinary no signal: the bar already says offline.
            e is IOException -> _state.update { it.copy(sync = SyncStatus.Offline, syncProblem = null) }
            // No amount of retrying fixes this one: somebody else has the book.
            e is HttpException && e.code() == 409 -> _state.update {
                it.copy(sync = SyncStatus.Offline, syncProblem = t("sc.another_device_is_scoring"), bookElsewhere = true)
            }
            else -> _state.update { it.copy(sync = SyncStatus.Offline, syncProblem = serverWords(e)) }
        }
    }

    // ---- the book ----

    /** The scorer's phone died: a captain takes the book, and it is logged. */
    fun takeOver() {
        val id = matchId ?: return
        viewModelScope.launch {
            _state.update { it.copy(isWorking = true) }
            runCatching { api.claimScorer(id, ClaimScorerBody(deviceId, force = true)) }
                .onSuccess { claimed ->
                    _state.update { it.copy(match = claimed, bookElsewhere = false, syncProblem = null, isWorking = false) }
                    send()
                }
                .onFailure { failure ->
                    if (failure is CancellationException) throw failure
                    _state.update { it.copy(syncProblem = serverWords(failure), isWorking = false) }
                }
        }
    }

    /** Officials first — usually who it should go to — then each side. Never yourself, never twice. */
    fun loadCandidates() {
        val id = matchId ?: return
        viewModelScope.launch {
            val officials = runCatching { api.officials(id) }.getOrDefault(emptyList())
            val squads = runCatching { api.squads(id) }.getOrNull()
            val seen = mutableSetOf<String>().apply { myUserId?.let(::add) }
            val view = _state.value.view
            val people = buildList {
                officials.forEach { if (seen.add(it.userId)) add(HandoverCandidate(it.userId, it.name, t("sc.umpires"))) }
                squads?.home?.let { side ->
                    val group = side.teamName.ifBlank { view?.homeName ?: t("sc.home_default") }
                    side.players.forEach { if (seen.add(it.id)) add(HandoverCandidate(it.id, it.name, group)) }
                }
                squads?.away?.let { side ->
                    val group = side.teamName.ifBlank { view?.awayName ?: t("sc.away_default") }
                    side.players.forEach { if (seen.add(it.id)) add(HandoverCandidate(it.id, it.name, group)) }
                }
            }
            _state.update { it.copy(candidates = people) }
        }
    }

    /** Everything scored so far goes up before the book moves, or it would be stranded here. */
    fun handOver(toUserId: String) {
        val id = matchId ?: return
        viewModelScope.launch {
            _state.update { it.copy(isWorking = true) }
            send()
            if (_state.value.unsent > 0) {
                _state.update { it.copy(isWorking = false, notice = t("sc.send_before_handing_over")) }
                return@launch
            }
            runCatching { api.handOver(id, HandoverBody(toUserId)) }
                .onSuccess { moved ->
                    _state.update {
                        it.copy(match = moved, handedOver = true, isWorking = false, notice = t("sc.handed_the_book_over"))
                    }
                }
                .onFailure { failure ->
                    if (failure is CancellationException) throw failure
                    _state.update { it.copy(isWorking = false, notice = serverWords(failure)) }
                }
        }
    }

    /** Rain, bad light: the card survives as no result. The last over goes up first. */
    fun abandon(reason: String) {
        val id = matchId ?: return
        viewModelScope.launch {
            _state.update { it.copy(isWorking = true) }
            send()
            runCatching { api.abandon(id, AbandonBody(reason.trim())) }
                .onSuccess {
                    _state.update { it.copy(isWorking = false) }
                    open()
                }
                .onFailure { failure ->
                    if (failure is CancellationException) throw failure
                    _state.update { it.copy(isWorking = false, notice = serverWords(failure)) }
                }
        }
    }

    // ---- sharing ----

    /** Mint a live link, then hand it to the share sheet: WhatsApp, Mail, the rest. */
    fun share(postToChat: Boolean) {
        val id = matchId
        if (id == null) {
            _state.update { it.copy(notice = t("sc.match_not_synced_yet")) }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(isWorking = true) }
            runCatching { api.shareScoreboard(id, ShareScoreboardBody(postToChat = postToChat, ttlHours = 48)) }
                .onSuccess { link ->
                    val view = _state.value.view
                    val headline = t(
                        "sc.live_scoreboard_headline",
                        vars = mapOf("home" to (view?.homeName ?: ""), "away" to (view?.awayName ?: "")),
                    )
                    _state.update {
                        it.copy(
                            isWorking = false,
                            share = ShareLink(link.url, headline),
                            notice = if (postToChat && link.conversationId != null) {
                                t("cl.link_ready_to_share")
                            } else {
                                t("cl.link_ready_pick_whatsapp")
                            },
                        )
                    }
                }
                .onFailure { failure ->
                    if (failure is CancellationException) throw failure
                    _state.update { it.copy(isWorking = false, notice = serverWords(failure)) }
                }
        }
    }

    fun shareShown() = _state.update { it.copy(share = null) }

    fun dismissError() = _state.update { it.copy(error = null) }

    fun dismissNotice() = _state.update { it.copy(notice = null) }

    private companion object {
        /** The server refuses more than this in one batch. */
        const val MAX_BATCH = 500

        /** A well-formed id for asking the engine "would you?" — never kept or sent. */
        const val PROBE_ID = "00000000-0000-4000-8000-000000000000"
    }
}

/**
 * What the server said, when it said something a person can read — its
 * refusals come as `{"error": "..."}` — and otherwise the app's usual words
 * for a failure.
 */
internal fun serverWords(failure: Throwable): String {
    if (failure is HttpException && failure.code() in 400..499) {
        val said = runCatching {
            val body = failure.response()?.errorBody()?.string() ?: return@runCatching null
            Json.parseToJsonElement(body).jsonObject["error"]?.jsonPrimitive?.contentOrNull
        }.getOrNull()
        if (!said.isNullOrBlank()) return said
    }
    return readableError(failure)
}

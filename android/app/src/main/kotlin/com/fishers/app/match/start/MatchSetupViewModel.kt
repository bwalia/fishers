package com.fishers.app.match.start

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.cricket.BallStore
import com.fishers.app.cricket.Engine
import com.fishers.app.cricket.ScoringEvent
import com.fishers.app.cricket.StoredBook
import com.fishers.app.i18n.t
import com.fishers.app.net.MatchStartApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.IOException
import java.time.Instant
import java.util.UUID

data class MatchSetupState(
    val isLoading: Boolean = true,
    val step: SetupStep = SetupStep.Terms,
    val title: String = "",
    // The terms page
    val homeName: String = "",
    val awayName: String = "",
    /** The opposition, when they are a club on the platform. */
    val opponent: ClubIdentity? = null,
    val opponentClubId: String? = null,
    val conditions: MatchConditions = MatchConditions.standard(20),
    /** What the log says, as the engine folded it. */
    val book: SetupBook = SetupBook(),
    val matchId: String? = null,
    /** This match cannot be set up from here, and why — another phone has the book, say. */
    val blocked: String? = null,
    /** Being written on this phone, to go up when there is signal. */
    val offline: Boolean = false,
    val isBusy: Boolean = false,
    val error: String? = null,
    // The toss
    val tossWinner: Side = Side.Home,
    val tossDecision: TossCall = TossCall.Bat,
    // The team sheets
    val homeSheet: List<MatchPlayer> = emptyList(),
    val awaySheet: List<MatchPlayer> = emptyList(),
    val homeCaptain: String? = null,
    val awayCaptain: String? = null,
    val homeKeeper: String? = null,
    val awayKeeper: String? = null,
    val umpires: List<MatchPlayer> = emptyList(),
    val scorers: List<MatchPlayer> = emptyList(),
    /** Who the home side picks from: the fixture's squad, or the club. */
    val clubPlayers: List<MatchPlayer> = emptyList(),
    /** The visitors' members, when they are a club here. Typed otherwise. */
    val opponentPlayers: List<MatchPlayer> = emptyList(),
    /** Each club's captains, marked as they are picked. */
    val captains: Set<String> = emptySet(),
    // The openers
    val strikerId: String? = null,
    val nonStrikerId: String? = null,
    val bowlerId: String? = null,
) {
    fun sheet(side: Side) = if (side == Side.Home) homeSheet else awaySheet
    fun captain(side: Side) = if (side == Side.Home) homeCaptain else awayCaptain
    fun keeper(side: Side) = if (side == Side.Home) homeKeeper else awayKeeper
    fun pool(side: Side) = if (side == Side.Home) clubPlayers else opponentPlayers
    fun named(side: Side) = book.xi(side).isNotEmpty()

    /** Who bats first: what the book says once the toss is in, the toss form until then. */
    val battingFirst: Side
        get() = book.battingFirst ?: if (tossDecision == TossCall.Bat) tossWinner else tossWinner.opposite

    /** Players still free to pick for one side — nobody plays for both. */
    fun available(side: Side): List<MatchPlayer> {
        val taken = (homeSheet + awaySheet).map { it.id }.toSet()
        return pool(side).filter { it.id !in taken }
    }

    val canPropose: Boolean get() = homeName.isNotBlank() && awayName.isNotBlank() && !isBusy && blocked == null
}

/**
 * Setting a match up, from the terms to the first ball — `CricketScoringFlowView.swift`.
 *
 * iOS writes every step into the match's event log and syncs the log; so does
 * this, so the scorer, the website and iOS all read the same match. Each step
 * is applied by the engine first — the server's own rules — and only what it
 * accepts is sent:
 *
 *  1. the terms: `match_prepared` (once) and `conditions_proposed`, after the
 *     match is made (`POST /events/{id}/cricket-match`, device-chosen id) and
 *     the book claimed for this phone (`claim-scorer`)
 *  2. both captains: `conditions_agreed` for each side
 *  3. the toss: `toss_recorded`
 *  4. the team sheets: `xi_selected` for each side, then `officials_appointed`
 *     when anybody was named — and members named are appointed on the API too,
 *     so they may score
 *  5. the openers: `innings_started` — and the scorer takes over
 *
 * A match somebody already set up is picked up where its log got to, read from
 * the server rather than from whatever this phone remembers.
 *
 * With no signal it all happens on the phone instead, as on iOS: each event is
 * applied by the engine just the same and written to the match's book on this
 * phone ([BallStore]) rather than sent, and the scorer opens from that book.
 * The book goes up when the signal does — the match first, if the server has
 * never heard of it ([MatchRegistrar]), then the log. That is a match started
 * offline (its book says what to make), a fixture whose match could not be made
 * for want of signal, and a setup the signal dropped out of half way.
 */
class MatchSetupViewModel(
    private val api: MatchStartApi,
    private val eventId: String,
    /** This install, for the scoring lock. */
    private val deviceId: String,
    /** Who is holding the phone — the name put against the proposal. */
    private val userName: String?,
    /** This phone's books: where the setup goes with no signal. */
    private val store: BallStore,
    /** The players saved the last time there was signal. */
    private val cache: OfflineCache,
    private val myUserId: String? = null,
    private val engine: Engine = Engine(),
    private val newId: () -> String = { UUID.randomUUID().toString() },
    private val now: () -> Instant = Instant::now,
) : ViewModel() {

    private val _state = MutableStateFlow(MatchSetupState())
    val state: StateFlow<MatchSetupState> = _state.asStateFlow()

    /** The engine's own JSON, as it handed it back. */
    private var engineState: String? = null
    /** The log [engineState] is a fold of. */
    private var log: List<ScoringEvent> = emptyList()
    private var clubId: String? = null
    private var mySide: Side? = null

    /** Writing to this phone's book, not the server. Once on, on for the screen. */
    private var local = false

    /** The fixture's id on the server: the one this screen was opened with, or where its book moved. */
    private var serverEventId = eventId

    /** The match as the server last answered it. */
    private var serverMatch: SetupMatch? = null

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            val held = store.read(eventId)
            if (held != null && held.hasWork) {
                // Begun on this phone and not all on the server yet: carried on
                // from here. It goes up with the scorer, or the next sweep.
                openLocal(held)
            } else {
                serverEventId = held?.eventId ?: eventId
                loadFromServer(held)
            }
            _state.value = _state.value.copy(isLoading = false)
        }
    }

    private suspend fun loadFromServer(held: StoredBook?) {
        val info = runCatching { api.event(serverEventId) }.getOrNull()
        clubId = info?.clubId
        val (home, away) = namesOf(info)
        _state.value = _state.value.copy(
            title = info?.title.orEmpty(),
            homeName = home,
            awayName = away,
            opponentClubId = info?.opponentClubId,
        )
        val found = runCatching { api.matchForEvent(serverEventId) }
        val match = found.getOrNull()
        val failure = found.exceptionOrNull()
        when {
            match != null -> adopt(match)
            // No signal, and this phone has the match's book: carry on from it.
            failure is IOException && held != null -> openLocal(held)
            else -> {
                when {
                    isNotFound(failure!!) -> Unit
                    // No signal and nothing here: the match is made on this phone.
                    failure is IOException -> goLocal()
                    else -> _state.value = _state.value.copy(error = apiWords(failure))
                }
                // No match yet: the terms page, with the club's roster warming
                // up for the team sheets.
                loadRosters()
            }
        }
    }

    // MARK: Step 1 — the terms

    fun setHomeName(name: String) = update { copy(homeName = name) }
    fun setAwayName(name: String) = update { copy(awayName = name, opponent = null) }
    fun setOpposition(name: String, identity: ClubIdentity?) = update {
        copy(awayName = name, opponent = identity, opponentClubId = identity?.clubId ?: opponentClubId)
    }
    fun setConditions(conditions: MatchConditions) = update { copy(conditions = conditions) }
    fun setOvers(overs: Int) = update { copy(conditions = conditions.withOvers(overs)) }

    /** Make the match if there is none, take the book, and put the terms on the table. */
    fun propose() {
        val s = _state.value
        if (!s.canPropose) return
        launchBusy {
            if (_state.value.matchId == null && !create()) return@launchBusy
            if (local) noteTerms()
            // Create-or-get may have handed back a match somebody else had got
            // further with. Then that is where this phone is.
            if (_state.value.book.step !in setOf(SetupStep.Terms, SetupStep.Agreement)) {
                update { copy(step = book.step) }
                return@launchBusy
            }
            val current = _state.value
            val by = mySide ?: Side.Home
            val events = buildList {
                if (current.book.lastSeq == 0L) {
                    add(SetupEvents.matchPrepared(current.conditions.oversLimit, current.homeName.trim(), current.awayName.trim()))
                }
                add(
                    SetupEvents.conditionsProposed(
                        current.conditions,
                        by = by,
                        byName = userName?.takeIf { it.isNotBlank() } ?: current.book.name(by),
                    ),
                )
            }
            if (post(events)) update { copy(step = SetupStep.Agreement) }
        }
    }

    // MARK: Step 2 — both captains agree

    fun agree(side: Side, captainName: String) {
        val name = captainName.trim()
        if (name.isEmpty()) {
            update { copy(error = t("sc.put_a_name_against_agreement")) }
            return
        }
        launchBusy { post(listOf(SetupEvents.conditionsAgreed(side, name))) }
    }

    /** The other captain may have agreed from their own phone. Not with no signal: nobody could have. */
    fun refresh() = launchBusy { if (!local) resync() }

    fun continueToToss() {
        if (_state.value.book.bothAgreed) update { copy(step = SetupStep.Toss) }
    }

    fun changeTerms() = update { copy(step = SetupStep.Terms) }

    /** The name a captain's agreement is suggested under: the home one is usually holding the phone. */
    fun suggestedCaptain(side: Side): String = if (side == Side.Home) userName.orEmpty() else ""

    // MARK: Step 3 — the toss

    fun setToss(winner: Side) = update { copy(tossWinner = winner) }
    fun setTossDecision(decision: TossCall) = update { copy(tossDecision = decision) }

    fun recordToss() {
        val s = _state.value
        launchBusy {
            if (post(listOf(SetupEvents.tossRecorded(s.tossWinner, s.tossDecision)))) {
                update { copy(step = SetupStep.Sheets) }
            }
        }
    }

    // MARK: Step 4 — the team sheets

    fun addPlayer(side: Side, player: MatchPlayer) = update {
        if ((homeSheet + awaySheet).any { it.id == player.id }) return@update this
        val next = sheet(side) + player
        // Picking a club's captain marks them C, until somebody chooses otherwise.
        val captain = captain(side) ?: player.id.takeIf { it in captains }
        withSheet(side, next).withCaptain(side, captain)
    }

    /** A guest, or one of an opposition that is only a name: a fresh id, as iOS mints. */
    fun addGuest(side: Side, name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        addPlayer(side, MatchPlayer(newId(), trimmed))
    }

    fun removePlayer(side: Side, id: String) = update {
        val next = sheet(side).filterNot { it.id == id }
        var out = withSheet(side, next)
        if (captain(side) == id) out = out.withCaptain(side, next.firstOrNull { it.id in captains }?.id)
        if (keeper(side) == id) out = out.withKeeper(side, null)
        out
    }

    /** Batting order: one place up, or down. */
    fun movePlayer(side: Side, id: String, up: Boolean) = update {
        val list = sheet(side).toMutableList()
        val at = list.indexOfFirst { it.id == id }
        val to = if (up) at - 1 else at + 1
        if (at < 0 || to !in list.indices) return@update this
        list.add(to, list.removeAt(at))
        withSheet(side, list)
    }

    fun setCaptain(side: Side, id: String?) = update { withCaptain(side, id) }
    fun setKeeper(side: Side, id: String?) = update { withKeeper(side, id) }

    fun addOfficial(umpire: Boolean, player: MatchPlayer) = update {
        if ((umpires + scorers).any { it.id == player.id }) return@update this
        if (umpire) copy(umpires = umpires + player) else copy(scorers = scorers + player)
    }

    fun addOfficialGuest(umpire: Boolean, name: String) {
        val trimmed = name.trim()
        if (trimmed.isNotEmpty()) addOfficial(umpire, MatchPlayer(newId(), trimmed))
    }

    fun removeOfficial(id: String) = update {
        copy(umpires = umpires.filterNot { it.id == id }, scorers = scorers.filterNot { it.id == id })
    }

    /**
     * Name one side. Each captain names their own, and the engine will not
     * start until both are in — so it is one side at a time, as on iOS.
     */
    fun confirmSheet(side: Side) {
        val s = _state.value
        if (s.named(side)) return
        if (s.sheet(side).size < 2) {
            update { copy(error = t("ms.sheet_needs_two")) }
            return
        }
        launchBusy {
            val ok = post(listOf(SetupEvents.xiSelected(side, s.sheet(side), s.captain(side), s.keeper(side))))
            if (ok && _state.value.named(side.opposite)) finishSheets()
        }
    }

    /** Both sides named: the officials, if anybody was named, then the openers. */
    fun continueToOpeners() = launchBusy { finishSheets() }

    private suspend fun finishSheets() {
        val s = _state.value
        if (!s.named(Side.Home) || !s.named(Side.Away)) return
        val officials = MatchOfficials(s.umpires, s.scorers)
        val wanted = officials.umpires.isNotEmpty() || officials.scorers.isNotEmpty()
        if (wanted && officials != s.book.officials) {
            if (!post(listOf(SetupEvents.officialsAppointed(officials)))) return
            // On the book either way; telling the API who may score needs signal.
            if (!local) appointMembers(officials)
        }
        enterOpeners()
    }

    // MARK: Step 5 — the openers

    fun setStriker(id: String?) = update { copy(strikerId = id) }
    fun setNonStriker(id: String?) = update { copy(nonStrikerId = id) }
    fun setBowler(id: String?) = update { copy(bowlerId = id) }

    fun startInnings() {
        val s = _state.value
        val striker = s.strikerId
        val nonStriker = s.nonStrikerId
        val bowler = s.bowlerId
        if (striker == null || nonStriker == null || bowler == null || striker == nonStriker) {
            update { copy(error = t("sc.pick_two_batters_and_bowler")) }
            return
        }
        launchBusy {
            if (post(listOf(SetupEvents.inningsStarted(s.battingFirst, striker, nonStriker, bowler)))) {
                update { copy(step = SetupStep.Scoring) }
            }
        }
    }

    fun dismissError() = update { copy(error = null) }

    // MARK: The match on the server

    /** The match as it is to be made: the terms page as it stands, under [matchId]. */
    private fun newMatch(matchId: String): NewMatch {
        val s = _state.value
        return NewMatch(
            matchId = matchId,
            oversLimit = s.conditions.oversLimit,
            homeName = s.homeName.trim(),
            awayName = s.awayName.trim(),
            opponentClubId = s.opponent?.clubId ?: s.opponentClubId,
        )
    }

    /**
     * `POST /events/{id}/cricket-match` with an id chosen here, then take the
     * book. With no signal the match is made on this phone, under the same id,
     * and made on the server when there is some.
     */
    private suspend fun create(): Boolean {
        val body = newMatch(newId())
        if (local) return createLocal(body)
        return runCatching { api.createMatch(serverEventId, body) }.fold(
            onSuccess = { match -> adopt(match, fresh = true) },
            onFailure = {
                // It may have landed, answer lost: the server makes it the same
                // match again later, because the id is the one chosen here.
                if (it is IOException) {
                    createLocal(body)
                } else {
                    update { copy(error = apiWords(it)) }
                    false
                }
            },
        )
    }

    /**
     * Take a match the server has: claim the book for this phone, read its log
     * through the engine, and go to wherever it had got to.
     */
    private suspend fun adopt(match: SetupMatch, fresh: Boolean = false): Boolean {
        serverMatch = match
        serverEventId = match.eventId
        mySide = match.myClubSide
        clubId = clubId ?: match.clubId.takeIf { it.isNotBlank() }
        update {
            copy(
                matchId = match.id,
                opponentClubId = match.opponentClubId ?: opponentClubId,
            )
        }
        if (!match.canScore) {
            update { copy(blocked = t("sc.need_scoring_permission")) }
            return false
        }
        runCatching { api.claimScorer(match.id, ClaimScorer(deviceId = deviceId, force = false)) }
            .onFailure {
                update { copy(blocked = apiWords(it)) }
                return false
            }
        if (!resync()) return false
        val book = _state.value.book
        update {
            if (book.lastSeq == 0L) {
                // Nothing in the log yet. A tournament's terms come with the match.
                val terms = match.state?.get("conditions")
                    ?.let { runCatching { SetupJson.decodeFromJsonElement<MatchConditions>(it) }.getOrNull() }
                copy(
                    conditions = if (fresh) conditions else terms ?: MatchConditions.standard(match.oversLimit),
                    homeName = if (fresh) homeName else match.homeName,
                    awayName = if (fresh) awayName else match.awayName,
                )
            } else {
                pickUp(book)
            }
        }
        if (_state.value.step == SetupStep.Openers) enterOpeners()
        loadRosters()
        return true
    }

    /** The wizard as far as [book] has got: names, terms, sheets, the toss — and the page after. */
    private fun MatchSetupState.pickUp(book: SetupBook) = copy(
        homeName = book.homeName,
        awayName = book.awayName,
        conditions = book.conditions ?: conditions,
        homeSheet = book.players(Side.Home),
        awaySheet = book.players(Side.Away),
        homeCaptain = book.homeCaptain,
        awayCaptain = book.awayCaptain,
        homeKeeper = book.homeKeeper,
        awayKeeper = book.awayKeeper,
        umpires = book.officials.umpires,
        scorers = book.officials.scorers,
        tossWinner = book.tossWinner ?: tossWinner,
        tossDecision = book.tossDecision ?: tossDecision,
        step = book.step,
    )

    // MARK: The match on this phone

    /** No signal, and nothing here yet: the match is made on this phone when the terms are put. */
    private fun goLocal() {
        local = true
        update { copy(offline = true) }
    }

    /** Carry on from the book on this phone — the engine replays it, as the scorer's does. */
    private suspend fun openLocal(book: StoredBook) {
        val folded = engine.replay(book.log).getOrElse {
            update { copy(blocked = t("ms.book_would_not_replay", vars = mapOf("reason" to engine.reason(it)))) }
            return
        }
        local = true
        engineState = folded
        log = book.log
        serverEventId = book.create?.serverEventId ?: book.eventId
        clubId = book.create?.clubId
            ?: book.create?.fixture?.clubId?.takeIf { it.isNotBlank() }
            ?: book.match?.clubId
        val setup = SetupBook.read(folded)
        val match = book.match
        update {
            val here = copy(
                offline = true,
                matchId = book.matchId,
                book = setup,
                title = book.create?.fixture?.title ?: title,
                opponentClubId = match?.opponentClubId ?: book.create?.fixture?.opponentClubId ?: opponentClubId,
            )
            if (setup.lastSeq == 0L) {
                here.copy(
                    homeName = match?.homeName ?: homeName,
                    awayName = match?.awayName ?: awayName,
                    conditions = match?.oversLimit?.takeIf { it > 0 }?.let { MatchConditions.standard(it) } ?: conditions,
                )
            } else {
                here.pickUp(setup)
            }
        }
        if (_state.value.step == SetupStep.Openers) enterOpeners()
        loadRosters()
    }

    /** The match made on this phone, to be made on the server under the same id when there is signal. */
    private fun createLocal(body: NewMatch): Boolean {
        val fresh = engine.replay(emptyList()).getOrElse {
            update { copy(error = engine.reason(it)) }
            return false
        }
        val match = matchOnThePhone(
            matchId = body.matchId,
            eventId = serverEventId,
            homeName = body.homeName,
            awayName = body.awayName,
            oversLimit = body.oversLimit,
            clubId = clubId,
            opponentClubId = body.opponentClubId,
            deviceId = deviceId,
            userId = myUserId,
        )
        val saved = runCatching {
            store.update(eventId) { held ->
                StoredBook(
                    eventId = held?.eventId ?: serverEventId,
                    matchId = body.matchId,
                    match = match,
                    // Anything an older book here had not sent is kept, never dropped.
                    stranded = held?.let { it.stranded + it.unsent }.orEmpty(),
                    create = PendingCreate(serverEventId = serverEventId, match = body),
                )
            }
        }
        if (saved.isFailure) {
            update { copy(error = t("ms.could_not_save_match")) }
            return false
        }
        local = true
        engineState = fresh
        log = emptyList()
        update { copy(matchId = body.matchId, offline = true, error = null) }
        return true
    }

    /**
     * The terms as first put, for making the match on the server — and the
     * names, for the list of matches on this phone. Only while the server has
     * not got the match: after that the log is what says.
     */
    private fun noteTerms() {
        val id = _state.value.matchId ?: return
        val body = newMatch(id)
        runCatching {
            store.update(eventId) { held ->
                val create = held?.create ?: return@update held
                held.copy(
                    create = if (held.log.isEmpty() || create.match == null) create.copy(match = body) else create,
                    match = held.match?.copy(homeName = body.homeName, awayName = body.awayName, oversLimit = body.oversLimit),
                )
            }
        }
    }

    /**
     * Written to the phone's book as unsent, after the engine took them —
     * exactly what the scorer does with a ball. False when the phone could not
     * keep them, and then nothing moves on.
     */
    private fun keep(events: List<ScoringEvent>, next: String): Boolean {
        val id = _state.value.matchId ?: return false
        val ids = events.map { it.clientEventId }
        val saved = runCatching {
            store.update(eventId) { held ->
                val base = held?.takeIf { it.matchId == id } ?: StoredBook(
                    eventId = held?.eventId ?: serverEventId,
                    matchId = id,
                    match = serverMatch?.onThePhone(deviceId),
                    log = log,
                    stranded = held?.let { it.stranded + it.unsent }.orEmpty(),
                )
                base.copy(log = base.log + events, pending = base.pending + ids)
            }!!
        }.getOrElse {
            update { copy(error = t("ms.could_not_save_match")) }
            return false
        }
        engineState = next
        log = saved.log
        update { copy(book = SetupBook.read(next), error = null) }
        return true
    }

    /** The server's log, kept on the phone too: where the setup carries on from if the signal goes. */
    private fun mirror() {
        val match = serverMatch ?: return
        runCatching {
            store.update(eventId) { held ->
                // Never over the top of something this phone has not sent.
                if (held != null && held.hasWork) {
                    held
                } else {
                    StoredBook(
                        eventId = match.eventId,
                        matchId = match.id,
                        match = match.onThePhone(deviceId),
                        log = log,
                        stranded = held?.stranded.orEmpty(),
                    )
                }
            }
        }
    }

    // MARK: Writing the log

    /**
     * Apply locally, then send what the engine accepted. The server's answer is
     * checked against the engine's count: if the log moved underneath us — a
     * captain agreeing from their own phone — the log is read again and the
     * wizard follows it, rather than carrying on from a book that is not the
     * one on the server.
     *
     * With no signal, what the engine accepted is kept on the phone instead
     * ([keep]) and the setup carries on from there.
     */
    private suspend fun post(kinds: List<JsonObject>): Boolean {
        val id = _state.value.matchId ?: return false
        var next = engineState ?: return false
        val events = mutableListOf<ScoringEvent>()
        for (kind in kinds) {
            val event = ScoringEvent(
                clientEventId = newId(),
                seq = engine.lastSeq(next) + 1,
                kind = kind,
                at = now().toString(),
            )
            next = engine.apply(next, event).getOrElse {
                update { copy(error = engine.reason(it)) }
                return false
            }
            events += event
        }
        if (local) return keep(events, next)
        return runCatching { api.postEvents(id, SetupBatch(deviceId = deviceId, events = events)) }.fold(
            onSuccess = { reply ->
                if (reply.lastSeq == engine.lastSeq(next)) {
                    engineState = next
                    log = log + events
                    mirror()
                    update { copy(book = SetupBook.read(next), error = null) }
                    true
                } else {
                    resync()
                    update { copy(step = book.step) }
                    false
                }
            },
            onFailure = {
                if (it is IOException) {
                    // The signal went. Carry on from this phone; if the send
                    // did land, its client_event_ids make the next one a no-op.
                    goLocal()
                    keep(events, next)
                } else {
                    update { copy(error = apiWords(it)) }
                    // A timeout may still have landed. The server's log decides.
                    resync()
                    false
                }
            },
        )
    }

    /** Read the log again and fold it. */
    private suspend fun resync(): Boolean {
        val id = _state.value.matchId ?: return false
        return runCatching { api.matchEvents(id) }.fold(
            onSuccess = { serverLog ->
                engine.replay(serverLog).fold(
                    onSuccess = { folded ->
                        engineState = folded
                        log = serverLog
                        mirror()
                        update { copy(book = SetupBook.read(folded)) }
                        true
                    },
                    onFailure = {
                        update { copy(blocked = t("ms.book_would_not_replay", vars = mapOf("reason" to engine.reason(it)))) }
                        false
                    },
                )
            },
            onFailure = {
                update { copy(error = apiWords(it)) }
                false
            },
        )
    }

    /** Members named as officials may score, so the API is told as well — as iOS does. */
    private suspend fun appointMembers(officials: MatchOfficials) {
        val id = _state.value.matchId ?: return
        val members = (_state.value.clubPlayers + _state.value.opponentPlayers).map { it.id }.toSet()
        for (umpire in officials.umpires.filter { it.id in members }) {
            runCatching { api.appointOfficial(id, Official(umpire.id, "umpire")) }
        }
        for (scorer in officials.scorers.filter { it.id in members }) {
            runCatching { api.appointOfficial(id, Official(scorer.id, "scorer")) }
        }
    }

    private fun enterOpeners() = update {
        val batting = battingFirst
        val bat = book.players(batting)
        val bowl = book.players(batting.opposite)
        copy(
            step = SetupStep.Openers,
            strikerId = strikerId ?: bat.getOrNull(0)?.id,
            nonStrikerId = nonStrikerId ?: bat.getOrNull(1)?.id,
            bowlerId = bowlerId ?: bowl.firstOrNull()?.id,
        )
    }

    /**
     * Who each side picks from. The match's squad first — it is the fixture's
     * own selection, and it can read the visitors' club where a scorer could
     * not — then the clubs directly, for a match that is not on the server yet.
     */
    private suspend fun loadRosters() {
        val squads = _state.value.matchId?.takeIf { !local }?.let { runCatching { api.squads(it) }.getOrNull() }
        val home = squads?.home?.players.orEmpty()
        val away = squads?.away?.players.orEmpty()
        var captains = (home + away).filter { it.isCaptain }.map { it.id }.toSet()

        val clubPlayers = if (home.isNotEmpty()) {
            home.map { MatchPlayer(it.id, it.name, it.batsLeft) }
        } else {
            val members = clubId?.let { roster(it) }.orEmpty()
            captains = captains + members.filter { it.isCaptain }.map { it.id }
            members.map { MatchPlayer(it.id, it.name) }
        }
        val opponentPlayers = if (away.isNotEmpty()) {
            away.map { MatchPlayer(it.id, it.name, it.batsLeft) }
        } else {
            // Usually refused — a scorer is in the home club only — and then
            // the visitors are typed, as on iOS.
            _state.value.opponentClubId?.let { roster(it) }.orEmpty()
                .map { MatchPlayer(it.id, it.name) }
        }
        update { copy(clubPlayers = clubPlayers, opponentPlayers = opponentPlayers, captains = captains) }
    }

    /**
     * A club's players: asked for, and saved for a day with no signal — or,
     * with none now, as they were saved. A team sheet with nobody to pick from
     * is where an offline match would otherwise stop.
     */
    private suspend fun roster(clubId: String): List<OfflineCache.Player> {
        if (!local) {
            runCatching { api.clubMembers(clubId) }.getOrNull()?.let { members ->
                cache.saveRoster(clubId, members)
                return members.filter { it.isOnTheBooks }.map { OfflineCache.Player(it.userId, it.name, it.isCaptain) }
            }
        }
        return cache.roster(clubId)
    }

    private fun launchBusy(block: suspend () -> Unit) {
        if (_state.value.isBusy) return
        viewModelScope.launch {
            update { copy(isBusy = true, error = null) }
            try {
                block()
            } finally {
                update { copy(isBusy = false) }
            }
        }
    }

    private inline fun update(change: MatchSetupState.() -> MatchSetupState) {
        _state.value = _state.value.change()
    }

    private fun MatchSetupState.withSheet(side: Side, players: List<MatchPlayer>) =
        if (side == Side.Home) copy(homeSheet = players) else copy(awaySheet = players)

    private fun MatchSetupState.withCaptain(side: Side, id: String?) =
        if (side == Side.Home) copy(homeCaptain = id) else copy(awayCaptain = id)

    private fun MatchSetupState.withKeeper(side: Side, id: String?) =
        if (side == Side.Home) copy(homeKeeper = id) else copy(awayKeeper = id)

    private companion object {
        /**
         * The names the fixture was made with: the quick start writes them into
         * the metadata, as iOS does; a fixture made elsewhere says "A v B" in its
         * title more often than not.
         */
        fun namesOf(info: FixtureInfo?): Pair<String, String> {
            val meta = runCatching { info?.metadata?.jsonObject }.getOrNull()
            fun field(key: String) = runCatching { (meta?.get(key) as? JsonPrimitive)?.content }.getOrNull()
                ?.takeIf { it.isNotBlank() }
            val parts = info?.title?.split(" v ", " vs ", limit = 2)?.map { it.trim() }
                ?.takeIf { it.size == 2 && it.all(String::isNotBlank) }
            val home = field("home_name") ?: parts?.get(0) ?: t("sc.home_default")
            val away = field("opposition") ?: parts?.get(1) ?: t("sc.away_default")
            return home to away
        }
    }
}

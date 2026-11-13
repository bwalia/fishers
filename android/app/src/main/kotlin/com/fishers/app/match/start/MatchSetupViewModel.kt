package com.fishers.app.match.start

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.cricket.Engine
import com.fishers.app.cricket.ScoringEvent
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
 */
class MatchSetupViewModel(
    private val api: MatchStartApi,
    private val eventId: String,
    /** This install, for the scoring lock. */
    private val deviceId: String,
    /** Who is holding the phone — the name put against the proposal. */
    private val userName: String?,
    private val engine: Engine = Engine(),
    private val newId: () -> String = { UUID.randomUUID().toString() },
    private val now: () -> Instant = Instant::now,
) : ViewModel() {

    private val _state = MutableStateFlow(MatchSetupState())
    val state: StateFlow<MatchSetupState> = _state.asStateFlow()

    /** The engine's own JSON, as it handed it back. */
    private var engineState: String? = null
    private var clubId: String? = null
    private var mySide: Side? = null

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            val info = runCatching { api.event(eventId) }.getOrNull()
            clubId = info?.clubId
            val (home, away) = namesOf(info)
            _state.value = _state.value.copy(
                title = info?.title.orEmpty(),
                homeName = home,
                awayName = away,
                opponentClubId = info?.opponentClubId,
            )
            runCatching { api.matchForEvent(eventId) }
                .onSuccess { match -> adopt(match) }
                .onFailure {
                    if (!isNotFound(it)) _state.value = _state.value.copy(error = apiWords(it))
                    // No match yet: the terms page, with the club's roster warming
                    // up for the team sheets.
                    loadRosters()
                }
            _state.value = _state.value.copy(isLoading = false)
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

    /** The other captain may have agreed from their own phone. */
    fun refresh() = launchBusy { resync() }

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
            appointMembers(officials)
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

    /** `POST /events/{id}/cricket-match` with an id chosen here, then take the book. */
    private suspend fun create(): Boolean {
        val s = _state.value
        val body = NewMatch(
            matchId = newId(),
            oversLimit = s.conditions.oversLimit,
            homeName = s.homeName.trim(),
            awayName = s.awayName.trim(),
            opponentClubId = s.opponent?.clubId ?: s.opponentClubId,
        )
        return runCatching { api.createMatch(eventId, body) }.fold(
            onSuccess = { match -> adopt(match, fresh = true) },
            onFailure = {
                update { copy(error = apiWords(it)) }
                false
            },
        )
    }

    /**
     * Take a match the server has: claim the book for this phone, read its log
     * through the engine, and go to wherever it had got to.
     */
    private suspend fun adopt(match: SetupMatch, fresh: Boolean = false): Boolean {
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
                copy(
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
            }
        }
        if (_state.value.step == SetupStep.Openers) enterOpeners()
        loadRosters()
        return true
    }

    /**
     * Apply locally, then send what the engine accepted. The server's answer is
     * checked against the engine's count: if the log moved underneath us — a
     * captain agreeing from their own phone — the log is read again and the
     * wizard follows it, rather than carrying on from a book that is not the
     * one on the server.
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
        return runCatching { api.postEvents(id, SetupBatch(deviceId = deviceId, events = events)) }.fold(
            onSuccess = { reply ->
                if (reply.lastSeq == engine.lastSeq(next)) {
                    engineState = next
                    update { copy(book = SetupBook.read(next), error = null) }
                    true
                } else {
                    resync()
                    update { copy(step = book.step) }
                    false
                }
            },
            onFailure = {
                update { copy(error = apiWords(it)) }
                // A timeout may still have landed. The server's log decides.
                resync()
                false
            },
        )
    }

    /** Read the log again and fold it. */
    private suspend fun resync(): Boolean {
        val id = _state.value.matchId ?: return false
        return runCatching { api.matchEvents(id) }.fold(
            onSuccess = { log ->
                engine.replay(log).fold(
                    onSuccess = { folded ->
                        engineState = folded
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
        val squads = _state.value.matchId?.let { runCatching { api.squads(it) }.getOrNull() }
        val home = squads?.home?.players.orEmpty()
        val away = squads?.away?.players.orEmpty()
        var captains = (home + away).filter { it.isCaptain }.map { it.id }.toSet()

        val clubPlayers = if (home.isNotEmpty()) {
            home.map { MatchPlayer(it.id, it.name, it.batsLeft) }
        } else {
            val members = clubId?.let { runCatching { api.clubMembers(it) }.getOrNull() }.orEmpty()
                .filter { it.isOnTheBooks }
            captains = captains + members.filter { it.isCaptain }.map { it.userId }
            members.map { MatchPlayer(it.userId, it.name) }
        }
        val opponentPlayers = if (away.isNotEmpty()) {
            away.map { MatchPlayer(it.id, it.name, it.batsLeft) }
        } else {
            // Usually refused — a scorer is in the home club only — and then
            // the visitors are typed, as on iOS.
            _state.value.opponentClubId?.let { runCatching { api.clubMembers(it) }.getOrNull() }.orEmpty()
                .filter { it.isOnTheBooks }
                .map { MatchPlayer(it.userId, it.name) }
        }
        update { copy(clubPlayers = clubPlayers, opponentPlayers = opponentPlayers, captains = captains) }
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

package com.fishers.app.cricket

import com.fishers.app.net.ScoringApi
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import retrofit2.HttpException
import retrofit2.Response
import java.io.IOException

/**
 * A server, by hand: one match, its log, and the scorer lock — enough to see
 * what the scorer sent and to take the signal away.
 *
 * Its book is folded by the real engine, as the server's is, so a test that
 * plays a match through the view model checks the same rules end to end.
 */
open class FakeScoringApi(
    val eventId: String = "e1",
    val matchId: String = "m1",
    setup: List<ScoringEvent> = MatchLog.setup(),
) : ScoringApi {

    val log = setup.toMutableList()
    val batches = mutableListOf<EventsBatch>()
    val claims = mutableListOf<ClaimScorerBody>()
    var online = true
    var canScore = true
    var scorerDevice: String? = "phone-1"
    var scorerUser: String? = "u-me"
    var scorecardCalls = 0

    private val engine = Engine()

    val posted: List<ScoringEvent> get() = batches.flatMap { it.events }

    fun header(lastSeq: Long = log.lastOrNull()?.seq ?: 0) = CricketMatch(
        id = matchId, eventId = eventId, status = "live", oversLimit = 2,
        homeName = "Lords", awayName = "Hemel", lastSeq = lastSeq,
        canScore = canScore, activeScorerUserId = scorerUser, activeScorerDeviceId = scorerDevice,
    )

    private fun reachable() {
        if (!online) throw IOException("no signal")
    }

    override suspend fun matchForEvent(eventId: String): CricketMatch {
        reachable()
        if (eventId != this.eventId) throw httpError(404, "cricket match not started")
        return header()
    }

    override suspend fun match(matchId: String) = reachable().let { header() }

    override suspend fun events(matchId: String): List<ScoringEvent> = reachable().let { log.toList() }

    /** Skips what it already holds by `client_event_id`, as `apply_event_batch` does. */
    override suspend fun postEvents(matchId: String, body: EventsBatch): CricketMatch {
        reachable()
        if (scorerDevice != null && scorerDevice != body.deviceId && scorerUser != "u-me") {
            throw httpError(409, "someone else is the active scorer for this match")
        }
        batches += body
        val seen = log.map { it.clientEventId }.toSet()
        for (event in body.events) {
            if (event.clientEventId in seen || event.seq <= (log.lastOrNull()?.seq ?: 0)) continue
            log += event
        }
        // Folded by the engine, so a ball the Laws refuse would show up here as a failure.
        engine.replay(log).getOrThrow()
        return header()
    }

    override suspend fun claimScorer(matchId: String, body: ClaimScorerBody): CricketMatch {
        reachable()
        claims += body
        if (!body.force && scorerUser != null && scorerUser != "u-me") {
            throw httpError(409, "someone else is scoring this match")
        }
        scorerUser = "u-me"
        scorerDevice = body.deviceId
        return header()
    }

    override suspend fun scorecard(matchId: String): JsonObject {
        reachable()
        scorecardCalls++
        val state = engine.replay(log).getOrThrow()
        return kotlinx.serialization.json.Json.parseToJsonElement(state) as JsonObject
    }

    override suspend fun shareScoreboard(matchId: String, body: ShareScoreboardBody) =
        reachable().let { ScoreboardShare(token = "t", url = "https://example.test/live/t") }

    override suspend fun handOver(matchId: String, body: HandoverBody): CricketMatch =
        reachable().let { header().copy(canScore = false) }

    override suspend fun officials(matchId: String) = emptyList<MatchOfficialRow>()

    override suspend fun squads(matchId: String) = MatchSquads()

    override suspend fun abandon(matchId: String, body: AbandonBody): CricketMatch = header()

    override suspend fun commentary(matchId: String, body: CommentaryRequest) = BallCommentary()

    companion object {
        fun httpError(code: Int, message: String) = HttpException(
            Response.error<Any>(code, """{"error":"$message"}""".toResponseBody("application/json".toMediaType())),
        )
    }
}

/**
 * A two-over match, three a side, set up the way the setup wizard leaves it:
 * terms agreed, toss made, both sheets in, openers and a bowler named.
 */
object MatchLog {
    val home = listOf("00000000-0000-4000-8000-00000000a001", "00000000-0000-4000-8000-00000000a002", "00000000-0000-4000-8000-00000000a003")
    val away = listOf("00000000-0000-4000-8000-00000000b001", "00000000-0000-4000-8000-00000000b002", "00000000-0000-4000-8000-00000000b003")
    val names = (home.mapIndexed { i, id -> id to "H${i + 1}" } + away.mapIndexed { i, id -> id to "A${i + 1}" }).toMap()

    private fun id(n: Int) = "00000000-0000-4000-8000-0000000c%04d".format(n)

    fun setup(): List<ScoringEvent> {
        val kinds = listOf(
            buildJsonObject {
                put("type", "match_prepared"); put("overs_limit", 2)
                put("home_name", "Lords"); put("away_name", "Hemel")
            },
            buildJsonObject {
                put("type", "conditions_proposed")
                putJsonObject("conditions") {
                    put("overs_limit", 2); put("overs_per_bowler", 0)
                    put("ground", "open"); put("ball", "white")
                }
                put("by", "home"); put("by_name", "Home captain")
            },
            buildJsonObject { put("type", "conditions_agreed"); put("side", "away"); put("captain_name", "Away captain") },
            buildJsonObject { put("type", "toss_recorded"); put("winner", "home"); put("decision", "bat") },
            sheet("home", home),
            sheet("away", away),
            Events.inningsStarted(0, "home", home[0], home[1], away[0]),
        )
        return kinds.mapIndexed { i, kind -> ScoringEvent(id(i + 1), (i + 1).toLong(), kind) }
    }

    private fun sheet(side: String, ids: List<String>) = buildJsonObject {
        put("type", "xi_selected"); put("side", side)
        put("players", kotlinx.serialization.json.JsonArray(ids.map { pid ->
            buildJsonObject { put("id", pid); put("name", names.getValue(pid)) }
        }))
        put("captain_id", kotlinx.serialization.json.JsonNull)
        put("keeper_id", kotlinx.serialization.json.JsonNull)
    }
}

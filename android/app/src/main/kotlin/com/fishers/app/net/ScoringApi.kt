package com.fishers.app.net

import com.fishers.app.cricket.AbandonBody
import com.fishers.app.cricket.BallCommentary
import com.fishers.app.cricket.ClaimScorerBody
import com.fishers.app.cricket.CommentaryRequest
import com.fishers.app.cricket.CricketMatch
import com.fishers.app.cricket.EventsBatch
import com.fishers.app.cricket.HandoverBody
import com.fishers.app.cricket.MatchOfficialRow
import com.fishers.app.cricket.MatchSquads
import com.fishers.app.cricket.ScoreboardShare
import com.fishers.app.cricket.ScoringEvent
import com.fishers.app.cricket.ShareScoreboardBody
import kotlinx.serialization.json.JsonObject
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path

/**
 * Scoring a match and following one, from `backend/api/src/routes/cricket.rs`
 * and `scoreboard_share.rs`.
 *
 * Its own interface rather than more of [FishersApi], so this area and the
 * others built alongside it do not edit one file. `FishersApi` keeps its three
 * older cricket calls for the screen this one replaces.
 */
interface ScoringApi {

    /** The match on a fixture. 404 until somebody has set one up. */
    @GET("events/{id}/cricket-match")
    suspend fun matchForEvent(@Path("id") eventId: String): CricketMatch

    @GET("cricket/matches/{id}")
    suspend fun match(@Path("id") matchId: String): CricketMatch

    /** The whole log, oldest first. The state is a fold over it. */
    @GET("cricket/matches/{id}/events")
    suspend fun events(@Path("id") matchId: String): List<ScoringEvent>

    /**
     * Send what this phone scored. The server skips anything it already has
     * by `client_event_id`, so a batch whose answer was lost can go again.
     * 409 when somebody else holds the book.
     */
    @POST("cricket/matches/{id}/events")
    suspend fun postEvents(
        @Path("id") matchId: String,
        @Body body: EventsBatch,
    ): CricketMatch

    /** Take the book for this device. `force` takes it off a dead phone, on the record. */
    @POST("cricket/matches/{id}/claim-scorer")
    suspend fun claimScorer(
        @Path("id") matchId: String,
        @Body body: ClaimScorerBody,
    ): CricketMatch

    /**
     * The card for somebody following: the match state with the result
     * extras flattened onto it. Kept as JSON and read twice — once as the
     * state, once for the DLS par — because the two share one object.
     */
    @GET("cricket/matches/{id}/scorecard")
    suspend fun scorecard(@Path("id") matchId: String): JsonObject

    /** A live link anyone can open, for WhatsApp and the rest. */
    @POST("cricket/matches/{id}/share")
    suspend fun shareScoreboard(
        @Path("id") matchId: String,
        @Body body: ShareScoreboardBody,
    ): ScoreboardShare

    /** Pass the book on. Only the person holding it can. */
    @POST("cricket/matches/{id}/handover")
    suspend fun handOver(
        @Path("id") matchId: String,
        @Body body: HandoverBody,
    ): CricketMatch

    @GET("cricket/matches/{id}/officials")
    suspend fun officials(@Path("id") matchId: String): List<MatchOfficialRow>

    @GET("cricket/matches/{id}/squad")
    suspend fun squads(@Path("id") matchId: String): MatchSquads

    /** Rain, bad light, ground unfit: the card stays, the result is "no result". */
    @POST("cricket/matches/{id}/abandon")
    suspend fun abandon(
        @Path("id") matchId: String,
        @Body body: AbandonBody,
    ): CricketMatch

    /** A line of colour for one ball, when the server has a model to ask. */
    @POST("cricket/matches/{id}/commentary")
    suspend fun commentary(
        @Path("id") matchId: String,
        @Body body: CommentaryRequest,
    ): BallCommentary
}

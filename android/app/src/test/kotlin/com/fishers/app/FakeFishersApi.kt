package com.fishers.app

import com.fishers.app.chat.ChatMessage
import com.fishers.app.chat.ConversationSummary
import com.fishers.app.chat.MarkReadRequest
import com.fishers.app.chat.PostMessageRequest
import com.fishers.app.clubs.Club
import com.fishers.app.clubs.ClubMemberDetail
import com.fishers.app.clubs.Team
import com.fishers.app.cricket.CricketMatch
import com.fishers.app.cricket.EventsBatch
import com.fishers.app.cricket.ScoringEvent
import com.fishers.app.fixtures.FishersEvent
import com.fishers.app.fixtures.RsvpRequest
import com.fishers.app.motm.CastMotmVoteRequest
import com.fishers.app.motm.MotmPollView
import com.fishers.app.net.AuthTokens
import com.fishers.app.net.FishersApi
import com.fishers.app.net.LoginRequest
import com.fishers.app.net.PublicUser
import com.fishers.app.net.RefreshRequest
import com.fishers.app.net.RoleIntentPatch
import com.fishers.app.net.SignupRequest
import com.fishers.app.umpire.AvailableUmpire
import com.fishers.app.umpire.MatchUmpire
import com.fishers.app.umpire.PendingUmpireReview
import com.fishers.app.umpire.UmpireProfile
import com.fishers.app.umpire.UmpireReview
import com.fishers.app.umpire.UmpireReviewBody
import com.fishers.app.umpire.UmpiringPatch

/**
 * One fake for every test, with each call refusing by default.
 *
 * Refusing rather than returning an empty answer is the point: a test that
 * silently passes because a call it did not expect returned `emptyList()` is a
 * test that has stopped checking anything. Each test overrides what it means to
 * exercise, and anything else being reached fails loudly and by name.
 *
 * Return types are written out rather than inferred. `error()` is `Nothing`,
 * which infers as the return type and then refuses to be overridden by a method
 * that returns `Unit` — which is every void endpoint here.
 */
open class FakeFishersApi : FishersApi {

    // ---- auth ----
    override suspend fun login(body: LoginRequest): AuthTokens = error("login not expected")
    override suspend fun signup(body: SignupRequest): AuthTokens = error("signup not expected")
    override suspend fun refresh(body: RefreshRequest): AuthTokens = error("refresh not expected")
    override suspend fun me(): PublicUser = error("me not expected")
    override suspend fun setRoleIntent(body: RoleIntentPatch): PublicUser =
        error("setRoleIntent not expected")

    // ---- cricket ----
    override suspend fun cricketMatch(eventId: String): CricketMatch =
        error("cricketMatch not expected")

    override suspend fun scoringEvents(matchId: String): List<ScoringEvent> =
        error("scoringEvents not expected")

    override suspend fun postScoringEvents(matchId: String, body: EventsBatch): CricketMatch =
        error("postScoringEvents not expected")

    // ---- umpiring ----
    override suspend fun myUmpiring(): UmpireProfile = error("myUmpiring not expected")
    override suspend fun umpiringOf(userId: String): UmpireProfile =
        error("umpiringOf not expected")

    override suspend fun setUmpiring(body: UmpiringPatch): UmpireProfile =
        error("setUmpiring not expected")

    override suspend fun pendingUmpireReviews(): List<PendingUmpireReview> =
        error("pendingUmpireReviews not expected")

    override suspend fun matchUmpires(matchId: String): List<MatchUmpire> =
        error("matchUmpires not expected")

    override suspend fun reviewUmpire(
        matchId: String,
        umpireId: String,
        body: UmpireReviewBody,
    ): UmpireReview = error("reviewUmpire not expected")

    // `Unit`, spelled out: `error()` is `Nothing`, which infers as the return
    // type and then refuses to override a method that returns `Unit`.
    override suspend fun withdrawUmpireReview(matchId: String, umpireId: String): Unit =
        error("withdrawUmpireReview not expected")

    override suspend fun clubUmpires(clubId: String): List<AvailableUmpire> =
        error("clubUmpires not expected")

    // ---- clubs ----
    override suspend fun myClubs(): List<Club> = error("myClubs not expected")
    override suspend fun clubMembers(id: String): List<ClubMemberDetail> =
        error("clubMembers not expected")

    override suspend fun clubTeams(id: String): List<Team> = error("clubTeams not expected")

    // ---- fixtures ----
    override suspend fun myFixtures(): List<FishersEvent> = error("myFixtures not expected")
    override suspend fun event(id: String): FishersEvent = error("event not expected")
    override suspend fun rsvp(id: String, body: RsvpRequest): Unit = error("rsvp not expected")

    // ---- man of the match ----
    override suspend fun motmPoll(id: String): MotmPollView = error("motmPoll not expected")
    override suspend fun motmForEvent(eventId: String): MotmPollView =
        error("motmForEvent not expected")

    override suspend fun castMotmVote(id: String, body: CastMotmVoteRequest): MotmPollView =
        error("castMotmVote not expected")

    override suspend fun withdrawMotmVote(id: String): MotmPollView =
        error("withdrawMotmVote not expected")

    // ---- chat ----
    override suspend fun conversations(): List<ConversationSummary> =
        error("conversations not expected")

    override suspend fun messages(id: String): List<ChatMessage> = error("messages not expected")

    override suspend fun postMessage(id: String, body: PostMessageRequest): ChatMessage =
        error("postMessage not expected")

    override suspend fun markRead(id: String, body: MarkReadRequest): Unit =
        error("markRead not expected")
}

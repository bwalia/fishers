package com.fishers.app

import com.fishers.app.chat.ChatMessage
import com.fishers.app.chat.ConversationSummary
import com.fishers.app.chat.MarkReadRequest
import com.fishers.app.chat.PostMessageRequest
import com.fishers.app.motm.CastMotmVoteRequest
import com.fishers.app.motm.MotmPollView
import com.fishers.app.net.AuthTokens
import com.fishers.app.net.FishersApi
import com.fishers.app.net.LoginRequest
import com.fishers.app.net.PublicUser
import com.fishers.app.net.RefreshRequest
import com.fishers.app.net.RoleIntentPatch
import com.fishers.app.net.SignupRequest

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
    override suspend fun login(body: LoginRequest): AuthTokens = error("login not expected")
    override suspend fun signup(body: SignupRequest): AuthTokens = error("signup not expected")
    override suspend fun refresh(body: RefreshRequest): AuthTokens = error("refresh not expected")
    override suspend fun me(): PublicUser = error("me not expected")
    override suspend fun setRoleIntent(body: RoleIntentPatch): PublicUser =
        error("setRoleIntent not expected")

    override suspend fun conversations(): List<ConversationSummary> =
        error("conversations not expected")

    override suspend fun messages(id: String): List<ChatMessage> = error("messages not expected")

    override suspend fun postMessage(id: String, body: PostMessageRequest): ChatMessage =
        error("postMessage not expected")

    override suspend fun markRead(id: String, body: MarkReadRequest): Unit =
        error("markRead not expected")

    override suspend fun motmPoll(id: String): MotmPollView = error("motmPoll not expected")
    override suspend fun motmForEvent(eventId: String): MotmPollView =
        error("motmForEvent not expected")

    override suspend fun castMotmVote(id: String, body: CastMotmVoteRequest): MotmPollView =
        error("castMotmVote not expected")

    override suspend fun withdrawMotmVote(id: String): MotmPollView =
        error("withdrawMotmVote not expected")
}

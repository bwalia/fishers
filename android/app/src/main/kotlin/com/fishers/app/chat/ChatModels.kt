package com.fishers.app.chat

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * The server's shapes, from `backend/domain/src/chat.rs`.
 *
 * Named as the wire names them. Dates arrive as ISO-8601 strings and stay
 * strings here: the only thing the list does with one is sort and format it,
 * and parsing every timestamp on the way in to re-render it on the way out is
 * work done twice for a screen that scrolls.
 */
@Serializable
data class ConversationSummary(
    val id: String,
    val kind: String,
    val title: String,
    @SerialName("club_id") val clubId: String? = null,
    @SerialName("team_id") val teamId: String? = null,
    @SerialName("event_id") val eventId: String? = null,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("last_message_body") val lastMessageBody: String? = null,
    @SerialName("last_message_at") val lastMessageAt: String? = null,
    @SerialName("unread_count") val unreadCount: Long = 0,
    @SerialName("pending_proposals") val pendingProposals: Long = 0,
) {
    val hasUnread: Boolean get() = unreadCount > 0
}

@Serializable
data class ChatMessage(
    val id: String,
    @SerialName("conversation_id") val conversationId: String,
    /** Null when the agent wrote it. */
    @SerialName("sender_id") val senderId: String? = null,
    @SerialName("sender_name") val senderName: String? = null,
    /** `text` | `system` | `agent` */
    val kind: String,
    val body: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("edited_at") val editedAt: String? = null,
) {
    val isAgent: Boolean get() = kind == "agent" || senderId == null
    val isSystem: Boolean get() = kind == "system"
}

@Serializable
data class PostMessageRequest(val body: String)

@Serializable
data class MarkReadRequest(
    @SerialName("read_at") val readAt: String? = null,
)

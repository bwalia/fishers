/// Club chat, as the API serves it (`backend/domain/src/chat.rs`).
///
/// Every club already lives in a group chat somewhere; this is the one that
/// knows about the fixtures, so the assistant can read "I can't make Sunday"
/// and offer to set that person's availability.

export type ConversationSummary = {
  id: string;
  club_id: string | null;
  team_id: string | null;
  event_id: string | null;
  /// `club` | `team` | `event` | `direct`
  kind: string;
  title: string;
  updated_at: string;
  last_message_body: string | null;
  last_message_at: string | null;
  unread_count: number;
  pending_proposals: number;
};

export type ChatMessage = {
  id: string;
  conversation_id: string;
  /// Absent when the assistant wrote it.
  sender_id: string | null;
  sender_name: string | null;
  /// `text` | `system` | `agent`
  kind: string;
  body: string;
  metadata: Record<string, unknown>;
  created_at: string;
  edited_at: string | null;
};

/// Something the assistant thinks should happen, waiting on a human.
///
/// Nothing is ever applied on its own: a proposal is a suggestion with its
/// reasoning attached, and somebody with the authority accepts or dismisses it.
export type AgentProposal = {
  id: string;
  conversation_id: string;
  /// `availability` | `rsvp` | `selection` | …
  kind: string;
  subject_user_id: string | null;
  event_id: string | null;
  payload: Record<string, unknown>;
  rationale: string;
  /// `high` | `medium` | `low`
  confidence: string;
  /// `pending` | `applied` | `dismissed` | `failed`
  status: string;
  created_at: string;
};

export type AgentAnalysis = {
  proposals: AgentProposal[];
  summary: string | null;
};

export const CONVERSATION_KIND: Record<string, string> = {
  club: "Club",
  team: "Team",
  event: "Fixture",
  direct: "Direct",
};

export const PROPOSAL_KIND: Record<string, string> = {
  availability: "Set availability",
  rsvp: "Answer a fixture",
  selection: "Change the squad",
  fee: "Chase a fee",
};

/// "14:32" today, "Tue 14:32" this week, "12 Sep" beyond it.
///
/// A chat list where every row says the full date is unreadable; the useful
/// thing is how long ago, and that changes shape with distance.
export function chatTime(iso: string | null): string {
  if (!iso) return "";
  const at = new Date(iso);
  const now = new Date();
  const sameDay = at.toDateString() === now.toDateString();
  if (sameDay) {
    return at.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
  }
  const days = (now.getTime() - at.getTime()) / 86_400_000;
  if (days < 7) {
    return at.toLocaleString("en-GB", {
      weekday: "short", hour: "2-digit", minute: "2-digit",
    });
  }
  return at.toLocaleDateString("en-GB", { day: "numeric", month: "short" });
}

/// Messages arrive newest-last and are grouped under the day they were sent,
/// because a wall of times with no dates loses the reader by the second scroll.
export function byDay(messages: ChatMessage[]): { day: string; messages: ChatMessage[] }[] {
  const out: { day: string; messages: ChatMessage[] }[] = [];
  for (const message of messages) {
    const day = dayLabel(message.created_at);
    const last = out[out.length - 1];
    if (last?.day === day) last.messages.push(message);
    else out.push({ day, messages: [message] });
  }
  return out;
}

function dayLabel(iso: string): string {
  const at = new Date(iso);
  const today = new Date();
  const yesterday = new Date(today);
  yesterday.setDate(today.getDate() - 1);
  if (at.toDateString() === today.toDateString()) return "Today";
  if (at.toDateString() === yesterday.toDateString()) return "Yesterday";
  return at.toLocaleDateString("en-GB", {
    weekday: "long", day: "numeric", month: "long",
  });
}

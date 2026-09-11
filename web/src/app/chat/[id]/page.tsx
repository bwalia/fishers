"use client";

import { use, useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { api, getAccessToken, getStoredUser, readErr } from "@/lib/api";
import { subscribeLive } from "@/lib/live";
import { refreshInbox } from "@/lib/inbox";
import {
  byDay,
  chatTime,
  mergeMessages,
  PROPOSAL_KIND,
  type AgentAnalysis,
  type AgentProposal,
  type ChatMessage,
  type ConversationSummary,
} from "@/lib/chat";
import { Avatar } from "@/components/Avatar";
import { Icon } from "@/components/Icon";

/// A safety net, not the mechanism: new messages arrive over the live stream
/// the moment they are posted. This only catches up if the stream is down.
const POLL_MS = 30_000;

/// One thread.
///
/// The assistant reads the same messages everybody else does and offers what
/// it thinks should follow — never applying anything itself. A proposal is a
/// suggestion with its reasoning attached, and somebody with the authority
/// accepts it or throws it away.
export default function ChatThreadPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const [thread, setThread] = useState<ConversationSummary | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [proposals, setProposals] = useState<AgentProposal[]>([]);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [thinking, setThinking] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const foot = useRef<HTMLDivElement>(null);
  /// At the bottom and following along. Scrolled up to read history, a new
  /// message must not yank you away from what you were reading. State for the
  /// render, mirrored in a ref for the effect that reacts to new messages.
  const [following, setFollowingState] = useState(true);
  const followingRef = useRef(true);
  const setFollowing = (v: boolean) => {
    followingRef.current = v;
    setFollowingState(v);
  };
  /// The newest message you have seen. "N new" counts the messages after it,
  /// rather than counting updates: one refresh can bring five messages.
  const [seenAt, setSeenAt] = useState(0);
  const lastTop = useRef(0);
  const me = getStoredUser();

  const load = useCallback(async () => {
    try {
      const [rows, pending] = await Promise.all([
        api<ChatMessage[]>("GET", `/conversations/${id}/messages?limit=200`),
        api<AgentProposal[]>("GET", `/conversations/${id}/proposals`).catch(
          () => [] as AgentProposal[]
        ),
      ]);
      // Merged, not replaced: a message you sent while this was in flight is
      // already on screen and would otherwise vanish until the next fetch.
      // Filtered to this thread, since the page is reused between threads.
      setMessages((prev) => mergeMessages(prev.filter((m) => m.conversation_id === id), rows));
      setProposals(pending.filter((p) => p.status === "pending"));
      setError(null);
    } catch (err) {
      setError(readErr(err, "Could not load this thread"));
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to read this thread.");
      setLoading(false);
      return;
    }
    // The title is only in the list, so fetch that once for the heading.
    api<ConversationSummary[]>("GET", "/conversations")
      .then((all) => setThread(all.find((t) => t.id === id) ?? null))
      .catch(() => {});
    load();
    // Marking read is fire-and-forget: failing to clear a badge is not worth
    // an error in front of somebody who is reading the thread anyway.
    api("POST", `/conversations/${id}/read`, {}).then(refreshInbox, () => {});
    const timer = window.setInterval(load, POLL_MS);
    // Live: a message in this thread refetches it (the event carries ids,
    // never content) and marks it read, since it is on screen.
    const stop = subscribeLive((e) => {
      if (e.type === "resync" || (e.type === "message" && e.conversation_id === id)) {
        load();
        if (e.type === "message") api("POST", `/conversations/${id}/read`, {}).then(refreshInbox, () => {});
      }
    });
    return () => {
      window.clearInterval(timer);
      stop();
    };
  }, [id, load]);

  // A new thread starts at the bottom.
  useEffect(() => {
    setFollowing(true);
    setSeenAt(0);
    setMessages([]);
  }, [id]);

  // Follow the conversation down as it grows — when you are already at the
  // bottom, or when the new message is yours.
  const newest = messages[messages.length - 1];
  const markSeen = () => newest && setSeenAt(Date.parse(newest.created_at));
  useEffect(() => {
    if (!newest) return;
    if (followingRef.current || newest.sender_id === me?.id) {
      foot.current?.scrollIntoView({ block: "end" });
      if (newest.sender_id === me?.id) setFollowing(true);
      markSeen();
    }
  }, [newest?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  const unseen = following
    ? 0
    : messages.filter((m) => Date.parse(m.created_at) > seenAt && m.sender_id !== me?.id).length;

  const jumpDown = () => {
    foot.current?.scrollIntoView({ block: "end", behavior: "smooth" });
    setFollowing(true);
    markSeen();
  };

  const days = useMemo(() => byDay(messages), [messages]);

  const send = async () => {
    const body = draft.trim();
    if (!body) return;
    setSending(true);
    setError(null);
    try {
      const sent = await api<ChatMessage>("POST", `/conversations/${id}/messages`, { body });
      // Shown straight away rather than waiting for it to come back on the
      // live stream — it will, and the merge collapses the two by id.
      setMessages((prev) => mergeMessages(prev, [sent]));
      setDraft("");
    } catch (err) {
      setError(readErr(err, "That message did not send"));
    } finally {
      setSending(false);
    }
  };

  const analyse = async () => {
    setThinking(true);
    setError(null);
    try {
      const out = await api<AgentAnalysis>("POST", `/conversations/${id}/agent/analyse`, {});
      setProposals(out.proposals.filter((p) => p.status === "pending"));
      await load();
    } catch (err) {
      setError(readErr(err, "The assistant could not read this thread"));
    } finally {
      setThinking(false);
    }
  };

  const decide = async (proposal: AgentProposal, apply: boolean) => {
    // Off the list straight away — a card you have already answered should not
    // sit there looking undecided while the request is in flight.
    setProposals((prev) => prev.filter((p) => p.id !== proposal.id));
    try {
      await api("POST", `/agent/proposals/${proposal.id}/${apply ? "apply" : "dismiss"}`, {});
      await load();
    } catch (err) {
      setError(readErr(err, "That did not go through"));
      setProposals((prev) => [...prev, proposal]);
    }
  };

  return (
    <main id="main" className="thread">
      <header className="thread-top">
        <Link className="btn ghost sm" href="/chat">
          <Icon name="arrowLeft" size={14} /> Chats
        </Link>
        <h1>{thread?.title ?? "Thread"}</h1>
        {/* It works for a club, on the club's threads — and has no business
            reading a private chat. */}
        {thread && thread.kind !== "direct" && (
          <button className="btn ghost sm" type="button" disabled={thinking} onClick={analyse}>
            <Icon name="sparkle" size={14} /> {thinking ? "Reading…" : "Ask the assistant"}
          </button>
        )}
      </header>

      {error && <p className="error">{error}</p>}

      {proposals.length > 0 && (
        <section className="proposals" aria-label="Suggestions from the assistant">
          {proposals.map((p) => (
            <article key={p.id} className="proposal">
              <header>
                <span className="tag gold">{PROPOSAL_KIND[p.kind] ?? p.kind}</span>
                <span className="subtle">{p.confidence} confidence</span>
              </header>
              <p>{p.rationale}</p>
              <div className="field-row">
                <button className="btn primary sm" type="button" onClick={() => decide(p, true)}>
                  Do it
                </button>
                <button className="btn ghost sm" type="button" onClick={() => decide(p, false)}>
                  No thanks
                </button>
              </div>
            </article>
          ))}
        </section>
      )}

      <div
        className="thread-scroll"
        onScroll={(e) => {
          // Stop following only when they scroll UP. A scroll event arrives a
          // frame late, and in a busy thread more messages may have rendered
          // by then: measured against the taller list, a follow-along scroll
          // looked like "no longer at the bottom" and the view stopped keeping
          // up with nobody having touched it. Growth never moves scrollTop up;
          // a person reading back does.
          const el = e.currentTarget;
          const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 80;
          const wentUp = el.scrollTop < lastTop.current - 2;
          lastTop.current = el.scrollTop;
          if (atBottom) {
            if (!followingRef.current) setFollowing(true);
            markSeen();
          } else if (wentUp && followingRef.current) {
            setFollowing(false);
          }
        }}
      >
        {loading && <div className="skeleton" style={{ height: 200 }} />}

        {!loading && messages.length === 0 && (
          <div className="empty">
            <Icon name="chat" size={28} />
            <p>Nothing here yet. Say something.</p>
          </div>
        )}

        {days.map((day) => (
          <div key={day.day}>
            <p className="thread-day">{day.day}</p>
            {day.messages.map((m) => (
              <Bubble key={m.id} message={m} mine={m.sender_id === me?.id} />
            ))}
          </div>
        ))}
        <div ref={foot} />
        {unseen > 0 && (
          <button type="button" className="thread-new" onClick={jumpDown}>
            {unseen} new message{unseen === 1 ? "" : "s"} <span aria-hidden="true">↓</span>
          </button>
        )}
      </div>

      <form
        className="thread-compose"
        onSubmit={(e) => {
          e.preventDefault();
          void send();
        }}
      >
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder={
            thread?.kind === "direct"
              ? `Message ${thread.title}`
              : thread?.kind === "team"
                ? "Message the team"
                : thread?.kind === "event"
                  ? "Message everyone in this fixture"
                  : "Message the club"
          }
          aria-label="Message"
          maxLength={4000}
        />
        <button className="btn primary" type="submit" disabled={sending || !draft.trim()}>
          <Icon name="send" size={16} />
          <span className="sr-only">Send</span>
        </button>
      </form>
    </main>
  );
}

function Bubble({ message, mine }: { message: ChatMessage; mine: boolean }) {
  // A note the app wrote itself — somebody joined, a squad went up. It is not
  // anybody's message, so it does not get a bubble or a face.
  if (message.kind === "system") {
    return <p className="thread-system">{message.body}</p>;
  }

  const fromAgent = message.kind === "agent" || !message.sender_id;
  const who = fromAgent ? "Assistant" : message.sender_name ?? "Somebody";

  return (
    <div className={`bubble-row${mine ? " mine" : ""}`}>
      {!mine && (
        <Avatar name={who} size={30} className={fromAgent ? "agent" : undefined} />
      )}
      <div className={`bubble${fromAgent ? " agent" : ""}`}>
        {!mine && <p className="bubble-who">{who}</p>}
        <p className="bubble-body">{message.body}</p>
        <time className="bubble-at" dateTime={message.created_at}>
          {chatTime(message.created_at)}
        </time>
      </div>
    </div>
  );
}

"use client";

import { use, useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { api, getAccessToken, getStoredUser, readErr } from "@/lib/api";
import {
  byDay,
  chatTime,
  PROPOSAL_KIND,
  type AgentAnalysis,
  type AgentProposal,
  type ChatMessage,
  type ConversationSummary,
} from "@/lib/chat";
import { Avatar } from "@/components/Avatar";
import { Icon } from "@/components/Icon";

const POLL_MS = 5_000;

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
  const me = getStoredUser();

  const load = useCallback(async () => {
    try {
      const [rows, pending] = await Promise.all([
        api<ChatMessage[]>("GET", `/conversations/${id}/messages?limit=200`),
        api<AgentProposal[]>("GET", `/conversations/${id}/proposals`).catch(
          () => [] as AgentProposal[]
        ),
      ]);
      setMessages(rows);
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
    api("POST", `/conversations/${id}/read`, {}).catch(() => {});
    const timer = window.setInterval(load, POLL_MS);
    return () => window.clearInterval(timer);
  }, [id, load]);

  // Follow the conversation down as it grows, the way a chat should.
  const count = messages.length;
  useEffect(() => {
    foot.current?.scrollIntoView({ block: "end" });
  }, [count]);

  const days = useMemo(() => byDay(messages), [messages]);

  const send = async () => {
    const body = draft.trim();
    if (!body) return;
    setSending(true);
    setError(null);
    try {
      const sent = await api<ChatMessage>("POST", `/conversations/${id}/messages`, { body });
      // Append rather than reload: the poll is up to five seconds away and a
      // chat that swallows your message for that long feels broken.
      setMessages((prev) => (prev.some((m) => m.id === sent.id) ? prev : [...prev, sent]));
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
        <button className="btn ghost sm" type="button" disabled={thinking} onClick={analyse}>
          <Icon name="sparkle" size={14} /> {thinking ? "Reading…" : "Ask the assistant"}
        </button>
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

      <div className="thread-scroll">
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
          placeholder="Message the club"
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

"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { PushPrompt } from "@/components/PushPrompt";
import { subscribeLive } from "@/lib/live";
import { api, getAccessToken, readErr } from "@/lib/api";
import { chatTime, CONVERSATION_KIND, type ConversationSummary } from "@/lib/chat";
import { Icon } from "@/components/Icon";
import { NewChat } from "@/components/NewChat";

/// Every thread you are in, busiest first.
///
/// The API already orders by last activity and counts what you have not read,
/// so this does no sorting of its own — two places deciding what "recent"
/// means is how a list and its badge drift apart.
export default function ChatListPage() {
  const [threads, setThreads] = useState<ConversationSummary[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [starting, setStarting] = useState(false);

  const load = useCallback(async () => {
    try {
      setThreads(await api<ConversationSummary[]>("GET", "/conversations"));
      setError(null);
    } catch (err) {
      setError(readErr(err, "Could not load your chats"));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to see your club chats.");
      setLoading(false);
      return;
    }
    load();
    // Any message in any of your threads moves it up and bumps its unread
    // count, so the list refetches on every one; joining or leaving a thread
    // changes the list itself. The slow poll is only a safety net.
    const stop = subscribeLive((e) => {
      if (e.type === "message" || e.type === "conversations" || e.type === "resync") load();
    });
    const timer = window.setInterval(load, 60_000);
    return () => {
      window.clearInterval(timer);
      stop();
    };
  }, [load]);

  return (
    <main id="main">
      <section className="hero">
        <h1>Chats</h1>
        <p>Message anyone in your clubs, or start a thread for a club or a team.</p>
        {!error && (
          <button className="btn primary" type="button" onClick={() => setStarting(true)}>
            <Icon name="plus" size={16} /> New chat
          </button>
        )}
      </section>

      {error && <p className="error">{error}</p>}
      {!error && !loading && <PushPrompt context="new messages from your clubs" />}

      {loading && <div className="skeleton" style={{ height: 200 }} />}

      {!loading && !error && threads.length === 0 && (
        <div className="panel empty">
          <Icon name="chat" size={28} />
          <p>No chats yet. Message a teammate, or start a thread for your club or a team.</p>
        </div>
      )}

      {threads.length > 0 && (
        <ul className="thread-list">
          {threads.map((t) => (
            <li key={t.id}>
              <Link href={`/chat/${t.id}`} className="thread-row">
                <span className="thread-mark" aria-hidden>
                  <Icon name={t.event_id ? "calendar" : t.kind === "direct" ? "chat" : "users"} size={18} />
                </span>
                <span className="thread-body">
                  <span className="thread-head">
                    <strong>{t.title}</strong>
                    <span className="subtle">{chatTime(t.last_message_at ?? t.updated_at)}</span>
                  </span>
                  <span className="thread-last">
                    {t.last_message_body ?? <em>No messages yet</em>}
                  </span>
                </span>
                <span className="thread-badges">
                  {t.unread_count > 0 && (
                    <span className="tag" aria-label={`${t.unread_count} unread`}>
                      {t.unread_count}
                    </span>
                  )}
                  {t.pending_proposals > 0 && (
                    <span className="tag gold" title="The assistant has something for you">
                      {t.pending_proposals}
                    </span>
                  )}
                  <span className="tag grey">{CONVERSATION_KIND[t.kind] ?? t.kind}</span>
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}

      {starting && <NewChat onClose={() => setStarting(false)} />}
    </main>
  );
}

"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { PushPrompt } from "@/components/PushPrompt";
import { subscribeLive } from "@/lib/live";
import { api, readErr } from "@/lib/api";
import { chatTime, CONVERSATION_KIND, type ConversationSummary } from "@/lib/chat";
import { Icon } from "@/components/Icon";
import { NewChat } from "@/components/NewChat";
import { useRequireAuth } from "@/lib/require-auth";
import { useT } from "@/lib/i18n/provider";

/// Every thread you are in, busiest first.
///
/// The API already orders by last activity and counts what you have not read,
/// so this does no sorting of its own — two places deciding what "recent"
/// means is how a list and its badge drift apart.
export default function ChatListPage() {
  const t = useT();
  const authed = useRequireAuth();
  const [threads, setThreads] = useState<ConversationSummary[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [starting, setStarting] = useState(false);

  const load = useCallback(async () => {
    try {
      setThreads(await api<ConversationSummary[]>("GET", "/conversations"));
      setError(null);
    } catch (err) {
      setError(readErr(err, t("le.could_not_load_your_chats")));
    } finally {
      setLoading(false);
    }
  }, [t]);

  useEffect(() => {
    if (!authed) return;
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
  }, [load, authed]);

  if (!authed) return <main id="main" />;

  return (
    <main id="main">
      <section className="hero">
        <h1>Chats</h1>
        <p>{t("cl.message_anyone_in_your_clubs_or_start")}</p>
        {!error && (
          <button className="btn primary" type="button" onClick={() => setStarting(true)}>
            <Icon name="plus" size={16} /> {t("cl.new_chat")}
          </button>
        )}
      </section>

      {error && <p className="error">{error}</p>}
      {!error && !loading && <PushPrompt context="new messages from your clubs" />}

      {loading && <div className="skeleton" style={{ height: 200 }} />}

      {!loading && !error && threads.length === 0 && (
        <div className="panel empty">
          <Icon name="chat" size={28} />
          <p>{t("cl.no_chats_yet_message_a_teammate_or_sta")}</p>
        </div>
      )}

      {threads.length > 0 && (
        <ul className="thread-list">
          {threads.map((thread) => (
            <li key={thread.id}>
              <Link href={`/chat/${thread.id}`} className="thread-row">
                <span className="thread-mark" aria-hidden>
                  <Icon name={thread.event_id ? "calendar" : thread.kind === "direct" ? "chat" : "users"} size={18} />
                </span>
                <span className="thread-body">
                  <span className="thread-head">
                    <strong>{thread.title}</strong>
                    <span className="subtle">{chatTime(thread.last_message_at ?? thread.updated_at)}</span>
                  </span>
                  <span className="thread-last">
                    {thread.last_message_body ?? <em>{t("cl.no_messages_yet")}</em>}
                  </span>
                </span>
                <span className="thread-badges">
                  {thread.unread_count > 0 && (
                    <span className="tag" aria-label={`${thread.unread_count} unread`}>
                      {thread.unread_count}
                    </span>
                  )}
                  {thread.pending_proposals > 0 && (
                    <span className="tag gold" title={t("cl.the_assistant_has_something_for_you")}>
                      {thread.pending_proposals}
                    </span>
                  )}
                  <span className="tag grey">{CONVERSATION_KIND[thread.kind] ?? thread.kind}</span>
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

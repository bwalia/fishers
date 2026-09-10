"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { api, getAccessToken, readErr, type Club } from "@/lib/api";
import { chatTime, CONVERSATION_KIND, type ConversationSummary } from "@/lib/chat";
import { Icon } from "@/components/Icon";

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
    // A thread you are not looking at still gets messages. Slower than the
    // open thread polls, because a list only needs to be roughly right.
    const timer = window.setInterval(load, 20_000);
    return () => window.clearInterval(timer);
  }, [load]);

  return (
    <main id="main">
      <section className="hero">
        <h1>Chats</h1>
        <p>Your clubs, your teams, and the thread for each fixture.</p>
        {!error && (
          <button className="btn primary" type="button" onClick={() => setStarting(true)}>
            <Icon name="plus" size={16} /> Start a thread
          </button>
        )}
      </section>

      {error && <p className="error">{error}</p>}

      {loading && <div className="skeleton" style={{ height: 200 }} />}

      {!loading && !error && threads.length === 0 && (
        <div className="panel empty">
          <Icon name="chat" size={28} />
          <p>No threads yet. Start one for your club and everybody in it can join in.</p>
        </div>
      )}

      {threads.length > 0 && (
        <ul className="thread-list">
          {threads.map((t) => (
            <li key={t.id}>
              <Link href={`/chat/${t.id}`} className="thread-row">
                <span className="thread-mark" aria-hidden>
                  <Icon name={t.event_id ? "calendar" : "users"} size={18} />
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

      {starting && <StartThread onClose={() => setStarting(false)} onStarted={load} />}
    </main>
  );
}

/// A new thread belongs to a club — that is who can see it.
function StartThread({ onClose, onStarted }: { onClose: () => void; onStarted: () => void }) {
  const [clubs, setClubs] = useState<Club[]>([]);
  const [clubId, setClubId] = useState("");
  const [title, setTitle] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api<Club[]>("GET", "/clubs")
      .then((rows) => {
        setClubs(rows);
        if (rows[0]) setClubId(rows[0].id);
      })
      .catch(() => setError("Could not load your clubs"));
  }, []);

  const create = async () => {
    setBusy(true);
    setError(null);
    try {
      await api("POST", "/conversations", { title: title.trim(), club_id: clubId, kind: "club" });
      onStarted();
      onClose();
    } catch (err) {
      setError(readErr(err, "Could not start that thread"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel">
      <h2>Start a thread</h2>
      <div className="setup-fields">
        <label>
          Club
          <select value={clubId} onChange={(e) => setClubId(e.target.value)}>
            {clubs.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
        </label>
        <label>
          What is it about
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Sunday XI, kit orders, winter nets"
            maxLength={120}
          />
        </label>
      </div>
      {error && <p className="error">{error}</p>}
      <div className="field-row" style={{ marginTop: "var(--s4)" }}>
        <button
          className="btn primary"
          type="button"
          disabled={busy || !title.trim() || !clubId}
          onClick={create}
        >
          {busy ? "Starting…" : "Start it"}
        </button>
        <button className="btn" type="button" onClick={onClose}>Cancel</button>
      </div>
    </div>
  );
}

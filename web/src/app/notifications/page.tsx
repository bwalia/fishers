"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import {
  api,
  getAccessToken,
  kindLabel,
  notificationLine,
  readErr,
  type AppNotification,
  type NotificationPage,
} from "@/lib/api";
import { Icon } from "@/components/Icon";
import { PushToggle } from "@/components/PushToggle";

const PER_PAGE = 20;

/// Everything you have been told, one page at a time.
///
/// The filtering, counting and paging all happen in the database. An active
/// club generates thousands of these over a season, and shipping the lot to a
/// browser so it can slice twenty out is the kind of thing that works until
/// the day it does not.
export default function NotificationsPage() {
  const [feed, setFeed] = useState<NotificationPage | null>(null);
  const [page, setPage] = useState(1);
  const [kind, setKind] = useState("");
  const [unreadOnly, setUnreadOnly] = useState(false);
  const [search, setSearch] = useState("");
  /// Debounced, so typing does not fire a query per keystroke.
  const [term, setTerm] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const timer = setTimeout(() => {
      // The server refuses one character; asking is just a wasted round trip.
      setTerm(search.trim().length >= 2 ? search.trim() : "");
      setPage(1);
    }, 300);
    return () => clearTimeout(timer);
  }, [search]);

  const load = useCallback(async () => {
    setBusy(true);
    try {
      const query = new URLSearchParams({
        page: String(page),
        per_page: String(PER_PAGE),
      });
      if (kind) query.set("kind", kind);
      if (unreadOnly) query.set("unread", "true");
      if (term) query.set("q", term);
      setFeed(await api<NotificationPage>("GET", `/notifications?${query}`));
      setError(null);
    } catch (err) {
      setError(readErr(err, "Could not load your notifications"));
    } finally {
      setBusy(false);
    }
  }, [page, kind, unreadOnly, term]);

  useEffect(() => {
    if (!getAccessToken()) {
      setError("Sign in to see your notifications.");
      return;
    }
    load();
  }, [load]);

  const markAll = async () => {
    await api("POST", "/notifications/read", {}).catch(() => {});
    load();
  };

  const open = async (n: AppNotification) => {
    if (n.read_at) return;
    await api("POST", "/notifications/read", { id: n.id }).catch(() => {});
    load();
  };

  const filtered = Boolean(kind || unreadOnly || term);
  const from = feed ? (feed.page - 1) * feed.per_page + 1 : 0;
  const to = feed ? Math.min(feed.page * feed.per_page, feed.total) : 0;

  return (
    <main id="main">
      <section className="hero">
        <h1>Notifications</h1>
        <p>Everything the club has told you, newest first.</p>
      </section>

      {error && <p className="error">{error}</p>}

      <PushToggle />

      <div className="panel">
        <div className="panel-head">
          <h2>
            {feed
              ? feed.total === 0
                ? filtered ? "Nothing matches" : "Nothing yet"
                : `Showing ${from}–${to} of ${feed.total}`
              : "Loading…"}
          </h2>
          {(feed?.unread ?? 0) > 0 && (
            <button className="btn ghost sm" type="button" onClick={markAll}>
              Mark all read ({feed?.unread})
            </button>
          )}
        </div>

        <div className="setup-fields">
          <label>
            Search
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="A fixture, a club, a name"
            />
            {search.length === 1 && (
              <span className="subtle">Two characters or more.</span>
            )}
          </label>
          <label>
            Kind
            <select
              value={kind}
              onChange={(e) => { setKind(e.target.value); setPage(1); }}
            >
              <option value="">Everything</option>
              {/* Only the kinds this person has actually been sent, so the
                  filter never offers a choice that returns nothing. */}
              {(feed?.kinds ?? []).map((k) => (
                <option key={k} value={k}>{kindLabel(k)}</option>
              ))}
            </select>
          </label>
        </div>

        <label className="field-inline">
          <input
            type="checkbox"
            checked={unreadOnly}
            onChange={(e) => { setUnreadOnly(e.target.checked); setPage(1); }}
          />
          Unread only
        </label>

        {!feed && <div className="skeleton" style={{ height: 240, marginTop: "var(--s4)" }} />}

        {feed && feed.items.length === 0 && (
          <div className="empty">
            <Icon name="inbox" size={28} />
            <p>
              {filtered
                ? "Nothing matches that. Try a different filter."
                : "Nothing yet. This fills up as your club gets going."}
            </p>
          </div>
        )}

        {feed && feed.items.length > 0 && (
          <ul className="note-list">
            {feed.items.map((n) => {
              const line = notificationLine(n);
              const inner = (
                <>
                  <span className="note-kind">{kindLabel(n.type)}</span>
                  <span className="note-title">{line.title}</span>
                  {line.when && <span className="note-when">{line.when}</span>}
                  <time className="subtle" dateTime={n.sent_at}>
                    {new Date(n.sent_at).toLocaleString("en-GB", {
                      day: "numeric", month: "short", hour: "2-digit", minute: "2-digit",
                    })}
                  </time>
                </>
              );
              return (
                <li key={n.id} className={n.read_at ? undefined : "unread"}>
                  {line.href ? (
                    <Link href={line.href} onClick={() => open(n)}>{inner}</Link>
                  ) : (
                    <button type="button" onClick={() => open(n)}>{inner}</button>
                  )}
                </li>
              );
            })}
          </ul>
        )}

        {feed && feed.total > feed.per_page && (
          <div className="pager">
            <button
              className="btn"
              type="button"
              disabled={busy || feed.page <= 1}
              onClick={() => setPage((p) => p - 1)}
            >
              <Icon name="arrowLeft" size={16} /> Newer
            </button>
            <span className="subtle">
              Page {feed.page} of {Math.max(1, Math.ceil(feed.total / feed.per_page))}
            </span>
            <button
              className="btn"
              type="button"
              disabled={busy || !feed.has_more}
              onClick={() => setPage((p) => p + 1)}
            >
              Older <Icon name="arrowLeft" size={16} className="flip" />
            </button>
          </div>
        )}
      </div>
    </main>
  );
}

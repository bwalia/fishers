"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import {
  api,
  getAccessToken,
  notificationLine,
  type AppNotification,
} from "@/lib/api";
import { Icon } from "@/components/Icon";
import { subscribeLive } from "@/lib/live";

/// How many the panel shows. A dropdown is a glance, not an archive — the
/// rest are a click away on /notifications, where they are paged.
const PREVIEW = 6;

type Feed = { unread: number; items: AppNotification[] };

/// What is waiting for you.
///
/// Push is still an APNs stub, so opening the app is the only delivery that
/// works — which makes this the difference between "the other captain was
/// told" being true and being a hope.
export function NotificationBell() {
  const [feed, setFeed] = useState<Feed>({ unread: 0, items: [] });
  const [open, setOpen] = useState(false);
  const boxRef = useRef<HTMLDivElement>(null);

  const load = useCallback(async () => {
    if (!getAccessToken()) return;
    try {
      setFeed(await api<Feed>("GET", `/notifications?per_page=${PREVIEW}`));
    } catch {
      // A bell that cannot load is a bell with nothing in it.
    }
  }, []);

  useEffect(() => {
    load();
    // A new notification — or one read on another device — updates the badge
    // the moment it happens. The slow poll is only a safety net for when the
    // live stream is down.
    const stop = subscribeLive((e) => {
      if (e.type === "notification" || e.type === "resync") load();
    });
    const timer = setInterval(load, 120_000);
    return () => {
      clearInterval(timer);
      stop();
    };
  }, [load]);

  useEffect(() => {
    if (!open) return;
    const away = (e: MouseEvent) => {
      if (!boxRef.current?.contains(e.target as Node)) setOpen(false);
    };
    const esc = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    document.addEventListener("mousedown", away);
    document.addEventListener("keydown", esc);
    return () => {
      document.removeEventListener("mousedown", away);
      document.removeEventListener("keydown", esc);
    };
  }, [open]);

  if (!getAccessToken()) return null;

  const openFeed = async () => {
    const next = !open;
    setOpen(next);
    if (next) await load();
  };

  const markAllRead = async () => {
    await api("POST", "/notifications/read", {});
    load();
  };

  return (
    <div className="bell" ref={boxRef}>
      <button
        type="button"
        className="bell-button"
        aria-label={feed.unread ? `${feed.unread} unread notifications` : "Notifications"}
        aria-expanded={open}
        onClick={openFeed}
      >
        <Icon name="inbox" size={18} />
        {feed.unread > 0 && <span className="bell-dot">{feed.unread > 9 ? "9+" : feed.unread}</span>}
      </button>

      {open && (
        <div className="bell-panel" role="dialog" aria-label="Notifications">
          <div className="bell-head">
            <strong>Notifications</strong>
            {feed.unread > 0 && (
              <button className="btn ghost sm" type="button" onClick={markAllRead}>
                Mark all read
              </button>
            )}
          </div>
          {feed.items.length === 0 && <p className="muted">Nothing waiting for you.</p>}
          <ul className="bell-list">
            {feed.items.map((n) => {
              const line = notificationLine(n);
              const body = (
                <>
                  <span>{line.title}</span>
                  {/* Which fixture, not just when the notification was sent —
                      two clubs play each other more than once a season. */}
                  {line.when && <span className="bell-when">{line.when}</span>}
                  <span className="subtle">{new Date(n.sent_at).toLocaleString()}</span>
                </>
              );
              return (
                <li key={n.id} className={n.read_at ? "" : "unread"}>
                  {line.href ? (
                    <Link
                      className="bell-item"
                      href={line.href}
                      onClick={async () => {
                        setOpen(false);
                        await api("POST", "/notifications/read", { id: n.id });
                        load();
                      }}
                    >
                      {body}
                    </Link>
                  ) : (
                    <span className="bell-item">{body}</span>
                  )}
                </li>
              );
            })}
          </ul>
          <Link className="bell-all" href="/notifications" onClick={() => setOpen(false)}>
            View all notifications
          </Link>
        </div>
      )}
    </div>
  );
}

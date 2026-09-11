"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import {
  api,
  getAccessToken,
  getStoredUser,
  notificationLine,
  type AppNotification,
} from "@/lib/api";
import type { ChatMessage } from "@/lib/chat";
import { threadTitle } from "@/lib/inbox";
import { subscribeLive } from "@/lib/live";
import { Icon, type IconName } from "@/components/Icon";

type Alert = { id: string; icon: IconName; title: string; body?: string; href: string };

const SHOW_MS = 6000;

/// Something happened while you were elsewhere in the app: a chat message, an
/// invite to approve, a fixture to answer. A note in the corner that says what
/// and takes you there — rather than a number changing somewhere you might not
/// be looking.
///
/// Not for the thread you are reading (you can see it), and not for what you
/// did yourself. With the tab closed, web push does this job instead; the
/// service worker stays quiet while a Fishers tab is in front of you, so the
/// two never say the same thing twice.
export function LiveAlerts() {
  const pathname = usePathname();
  const router = useRouter();
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [signedIn, setSignedIn] = useState(false);
  const seen = useRef(new Set<string>());

  // Signing in or out happens by navigating, so check on every page.
  useEffect(() => setSignedIn(!!getAccessToken()), [pathname]);

  useEffect(() => {
    if (!signedIn) return;
    const add = (a: Alert) => {
      if (seen.current.has(a.id)) return;
      seen.current.add(a.id);
      setAlerts((prev) => [a, ...prev].slice(0, 3));
    };
    return subscribeLive(async (e) => {
      try {
        if (e.type === "message") {
          if (window.location.pathname === `/chat/${e.conversation_id}`) return;
          const [m] = await api<ChatMessage[]>("GET", `/conversations/${e.conversation_id}/messages?limit=1`);
          if (!m || m.id !== e.id || m.sender_id === getStoredUser()?.id || m.kind === "system") return;
          const where = threadTitle(e.conversation_id);
          add({
            id: `m:${m.id}`,
            icon: "chat",
            title: `${m.sender_name ?? "The assistant"}${where ? ` · ${where}` : ""}`,
            body: m.body,
            href: `/chat/${e.conversation_id}`,
          });
        } else if (e.type === "notification") {
          const feed = await api<{ items: AppNotification[] }>("GET", "/notifications?per_page=1");
          const n = feed.items[0];
          // The same event fires when something is marked read elsewhere.
          if (!n || n.read_at) return;
          const line = notificationLine(n);
          add({ id: `n:${n.id}`, icon: "inbox", title: line.title, href: line.href ?? "/notifications" });
        }
      } catch {
        /* an alert that could not be built is one nobody misses */
      }
    });
  }, [signedIn]);

  if (alerts.length === 0) return null;
  return (
    <div className="live-alerts" role="region" aria-label="Alerts">
      {alerts.map((a) => (
        <AlertCard
          key={a.id}
          alert={a}
          onOpen={() => {
            setAlerts((prev) => prev.filter((x) => x.id !== a.id));
            router.push(a.href);
          }}
          onClose={() => setAlerts((prev) => prev.filter((x) => x.id !== a.id))}
        />
      ))}
    </div>
  );
}

function AlertCard({ alert, onOpen, onClose }: { alert: Alert; onOpen: () => void; onClose: () => void }) {
  const [hover, setHover] = useState(false);
  // In a ref, so a new alert arriving (a new onClose from the parent) does not
  // restart every other alert's countdown.
  const close = useRef(onClose);
  close.current = onClose;
  // Hovering holds it: nobody should lose a message while reaching for it.
  useEffect(() => {
    if (hover) return;
    const t = setTimeout(() => close.current(), SHOW_MS);
    return () => clearTimeout(t);
  }, [hover]);

  return (
    <div
      className="live-alert"
      role="status"
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
    >
      <button type="button" className="live-alert-open" onClick={onOpen}>
        <span className="live-alert-icon" aria-hidden="true">
          <Icon name={alert.icon} size={18} />
        </span>
        <span className="live-alert-text">
          <strong>{alert.title}</strong>
          {alert.body && <span>{alert.body}</span>}
        </span>
      </button>
      <button type="button" className="live-alert-close" onClick={onClose} aria-label="Dismiss">
        ×
      </button>
    </div>
  );
}

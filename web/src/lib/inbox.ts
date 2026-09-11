/// Unread chats, in one place, for everything that shows a count.
///
/// The top bar and the phone's tab bar both show it; each fetching its own
/// copy on every message would be two requests for one number. This keeps one
/// list, refetched when the live stream says a thread moved — debounced, so a
/// burst of messages is one fetch.

import { useSyncExternalStore } from "react";
import { api, getAccessToken } from "@/lib/api";
import { subscribeLive } from "@/lib/live";
import type { ConversationSummary } from "@/lib/chat";

let threads: ConversationSummary[] = [];
const listeners = new Set<() => void>();
let stopLive: (() => void) | null = null;
let pending: ReturnType<typeof setTimeout> | null = null;

/// Fetch now. Also for whoever changes the count without an event — reading a
/// thread marks it read, and nothing is broadcast for that.
export async function refreshInbox() {
  if (!getAccessToken()) return;
  try {
    threads = await api<ConversationSummary[]>("GET", "/conversations");
  } catch {
    return;
  }
  for (const l of listeners) l();
}

function soon() {
  if (pending) clearTimeout(pending);
  pending = setTimeout(refreshInbox, 250);
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  if (listeners.size === 1) {
    void refreshInbox();
    stopLive = subscribeLive((e) => {
      if (e.type === "message" || e.type === "conversations" || e.type === "resync") soon();
    });
  }
  return () => {
    listeners.delete(listener);
    if (listeners.size === 0) {
      stopLive?.();
      stopLive = null;
    }
  };
}

const unread = () => threads.reduce((n, t) => n + (t.unread_count ?? 0), 0);

export function useUnreadChats(): number {
  return useSyncExternalStore(subscribe, unread, () => 0);
}

export function threadTitle(id: string): string | undefined {
  return threads.find((t) => t.id === id)?.title;
}

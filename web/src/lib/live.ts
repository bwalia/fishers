/// What changed, pushed from the API as it happens (`GET /stream`).
///
/// One connection per tab, shared by every component that listens: the thread,
/// the chat list and the bell all subscribe here rather than each opening
/// their own. Read with fetch rather than EventSource because fetch can send
/// the Authorization header — EventSource cannot, and the alternative is a
/// token in the URL, where the edge's access log would keep it.
///
/// Events say what changed, never the content. Subscribers re-fetch through
/// the normal endpoints, which do their own access checks.

import { apiV1, usableToken } from "@/lib/api";

export type LiveEvent =
  /// A new message in one of your threads.
  | { type: "message"; conversation_id: string; id: string }
  /// A notification arrived for you, or one was read on another device.
  | { type: "notification" }
  /// You joined or left a thread.
  | { type: "conversations" }
  /// Connected (or reconnected), or events may have been missed: re-fetch.
  | { type: "resync" };

type Handler = (event: LiveEvent) => void;

const handlers = new Set<Handler>();
let abort: AbortController | null = null;
let retry = 0;
let retryTimer: ReturnType<typeof setTimeout> | null = null;

/// Listen for live changes. Returns the unsubscribe function — made for a
/// useEffect cleanup. The connection opens with the first subscriber and
/// closes with the last.
export function subscribeLive(handler: Handler): () => void {
  handlers.add(handler);
  if (handlers.size === 1) connect();
  return () => {
    handlers.delete(handler);
    if (handlers.size === 0) disconnect();
  };
}

function emit(event: LiveEvent) {
  for (const h of handlers) {
    try {
      h(event);
    } catch {
      /* one broken subscriber must not starve the rest */
    }
  }
}

function disconnect() {
  abort?.abort();
  abort = null;
  if (retryTimer) clearTimeout(retryTimer);
  retryTimer = null;
  retry = 0;
}

/// Back off 1s, 2s, 4s … up to 30s, with jitter so a server restart does not
/// bring every open tab back in the same instant.
function reconnectLater() {
  if (handlers.size === 0) return;
  const wait = Math.min(30_000, 1000 * 2 ** retry) * (0.75 + Math.random() / 2);
  retry += 1;
  retryTimer = setTimeout(connect, wait);
}

async function connect() {
  if (handlers.size === 0) return;
  const token = await usableToken();
  if (!token) return reconnectLater(); // signed out; nothing to hear
  const controller = new AbortController();
  abort = controller;
  try {
    const res = await fetch(`${apiV1()}/stream`, {
      headers: { Authorization: `Bearer ${token}`, Accept: "text/event-stream" },
      cache: "no-store",
      signal: controller.signal,
    });
    if (!res.ok || !res.body) throw new Error(`stream ${res.status}`);
    retry = 0;
    await read(res.body, controller);
  } catch {
    // Closed on purpose (last subscriber left) — but a stall is not on purpose.
    if (controller.signal.aborted && controller.signal.reason !== STALLED) return;
  }
  if (abort === controller) reconnectLater();
}

/// The server sends a keep-alive every 20s. Nothing for 50s means the
/// connection died without saying so — a laptop that slept, a network that
/// changed — and fetch would otherwise wait on it for minutes.
const STALLED = "stalled";
const STALL_MS = 50_000;

/// The SSE wire format: `event:` and `data:` lines, a blank line ends an
/// event, and lines starting with ":" are keep-alive comments.
async function read(body: ReadableStream<Uint8Array>, controller: AbortController) {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let watchdog = setTimeout(() => controller.abort(STALLED), STALL_MS);
  try {
    for (;;) {
      const { value, done } = await reader.read();
      clearTimeout(watchdog);
      if (done) return;
      watchdog = setTimeout(() => controller.abort(STALLED), STALL_MS);
      buffer += decoder.decode(value, { stream: true });
      let end: number;
      while ((end = buffer.search(/\r?\n\r?\n/)) >= 0) {
        const block = buffer.slice(0, end);
        buffer = buffer.slice(end).replace(/^\r?\n\r?\n/, "");
        dispatch(block);
      }
    }
  } finally {
    clearTimeout(watchdog);
  }
}

function dispatch(block: string) {
  let name = "message";
  let data = "";
  for (const line of block.split(/\r?\n/)) {
    if (line.startsWith(":")) continue;
    const colon = line.indexOf(":");
    const field = colon < 0 ? line : line.slice(0, colon);
    const value = colon < 0 ? "" : line.slice(colon + 1).replace(/^ /, "");
    if (field === "event") name = value;
    else if (field === "data") data += (data ? "\n" : "") + value;
  }
  if (!data) return;
  let payload: Record<string, string> = {};
  try {
    payload = JSON.parse(data);
  } catch {
    return;
  }
  switch (name) {
    // Connected: whatever happened while we were not is only in a fetch.
    case "ready":
    case "resync":
      return emit({ type: "resync" });
    case "message":
      return emit({ type: "message", conversation_id: payload.conversation_id, id: payload.id });
    case "notification":
      return emit({ type: "notification" });
    case "conversations":
      return emit({ type: "conversations" });
  }
}

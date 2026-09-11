/// What changed, pushed from the API as it happens.
///
/// Two kinds of stream, one reader:
///   - `subscribeLive` — signed in. One connection per tab (`GET /stream`),
///     shared by every component that listens: a thread, the chat list, the
///     bell, a scorecard all subscribe here rather than each opening their own.
///   - `watchScoreboard` — a shared scoreboard link, no sign-in: that match only.
///
/// Read with fetch rather than EventSource because fetch can send the
/// Authorization header — EventSource cannot, and the alternative is a token
/// in the URL, where the edge's access log would keep it.
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
  /// A match changed — a ball, the toss, a handover, the result. `seq` is its
  /// position in the event log.
  | { type: "match"; id: string; seq: number }
  /// Connected (or reconnected), or events may have been missed: re-fetch.
  | { type: "resync" };

type Handler = (event: LiveEvent) => void;

// ---- the shared, signed-in stream -------------------------------------------

const handlers = new Set<Handler>();
let stopShared: (() => void) | null = null;

/// Listen for live changes. Returns the unsubscribe function — made for a
/// useEffect cleanup. The connection opens with the first subscriber and
/// closes with the last.
export function subscribeLive(handler: Handler): () => void {
  handlers.add(handler);
  if (handlers.size === 1) {
    stopShared = openStream(
      async () => {
        const token = await usableToken();
        return token ? { url: `${apiV1()}/stream`, headers: { Authorization: `Bearer ${token}` } } : null;
      },
      (e) => {
        for (const h of handlers) {
          try {
            h(e);
          } catch {
            /* one broken subscriber must not starve the rest */
          }
        }
      }
    );
  }
  return () => {
    handlers.delete(handler);
    if (handlers.size === 0) {
      stopShared?.();
      stopShared = null;
    }
  };
}

/// A shared scoreboard link's own stream: no sign-in, that one match.
export function watchScoreboard(token: string, handler: Handler): () => void {
  return openStream(
    async () => ({ url: `${apiV1()}/public/scoreboard/${encodeURIComponent(token)}/stream` }),
    handler
  );
}

// ---- one reader for both ----------------------------------------------------

/// The server sends a keep-alive every 20s. Nothing for 50s means the
/// connection died without saying so — a laptop that slept, a network that
/// changed — and fetch would otherwise wait on it for minutes.
const STALLED = "stalled";
const STALL_MS = 50_000;

/// Opens a stream and keeps it open: reconnects with jittered backoff after a
/// drop, and straight away after the server's normal ten-minute recycle.
/// Returns the function that closes it for good.
function openStream(
  target: () => Promise<{ url: string; headers?: Record<string, string> } | null>,
  onEvent: Handler
): () => void {
  let closed = false;
  let abort: AbortController | null = null;
  let retry = 0;
  let timer: ReturnType<typeof setTimeout> | null = null;

  // 1s, 2s, 4s … up to 30s, with jitter so a server restart does not bring
  // every open tab back in the same instant.
  const later = () => {
    if (closed) return;
    const wait = Math.min(30_000, 1000 * 2 ** retry) * (0.75 + Math.random() / 2);
    retry += 1;
    timer = setTimeout(connect, wait);
  };

  async function connect() {
    if (closed) return;
    const t = await target();
    if (!t) return later(); // signed out; nothing to hear
    const controller = new AbortController();
    abort = controller;
    try {
      const res = await fetch(t.url, {
        headers: { ...t.headers, Accept: "text/event-stream" },
        cache: "no-store",
        signal: controller.signal,
      });
      if (!res.ok || !res.body) throw new Error(`stream ${res.status}`);
      retry = 0;
      await read(res.body, controller, onEvent);
    } catch {
      // Closed on purpose — but a stall is not on purpose.
      if (closed || (controller.signal.aborted && controller.signal.reason !== STALLED)) return;
    }
    later();
  }

  connect();
  return () => {
    closed = true;
    abort?.abort();
    if (timer) clearTimeout(timer);
  };
}

/// The SSE wire format: `event:` and `data:` lines, a blank line ends an
/// event, and lines starting with ":" are keep-alive comments.
async function read(body: ReadableStream<Uint8Array>, controller: AbortController, onEvent: Handler) {
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
        const e = parse(block);
        if (e) onEvent(e);
      }
    }
  } finally {
    clearTimeout(watchdog);
  }
}

function parse(block: string): LiveEvent | null {
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
  if (!data) return null;
  let p: Record<string, unknown> = {};
  try {
    p = JSON.parse(data);
  } catch {
    return null;
  }
  switch (name) {
    // Connected: whatever happened while we were not is only in a fetch.
    case "ready":
    case "resync":
      return { type: "resync" };
    case "message":
      return { type: "message", conversation_id: String(p.conversation_id), id: String(p.id) };
    case "notification":
      return { type: "notification" };
    case "conversations":
      return { type: "conversations" };
    case "match":
      return { type: "match", id: String(p.id), seq: Number(p.seq) };
    default:
      return null;
  }
}

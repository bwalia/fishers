import type { T } from "@/lib/i18n";
/// What a scorer keeps when the network goes.
///
/// Two things live here, per match: the last state the engine produced, and the
/// balls that have not reached the server. Both in IndexedDB rather than an
/// HTTP cache, because they are not responses — they are the scorer's work, and
/// losing them loses the match.
///
/// The shape mirrors what the API already accepts: a batch of events keyed by a
/// `client_event_id` the browser mints. The server applies a batch it has
/// already seen as nothing at all, so a flush that half-succeeds and is retried
/// cannot double-count a ball.

const DB_NAME = "fishers-scoring";
const DB_VERSION = 1;
const STORE = "matches";

export type OutboxEntry = {
  matchId: string;
  /// The whole match as the API returns it, with the engine's state inside it.
  ///
  /// The state alone is not enough: it holds the runs but not who is allowed to
  /// score, and a scorer who restored from it was told "nobody is scoring this
  /// match" on their own book. Kept as the API's own shape rather than parsed
  /// into ours, which would be a second copy of the model to keep in step.
  match: unknown;
  /// Events the server has not acknowledged, oldest first.
  pending: unknown[];
  /// The last seq the engine has applied, so a queued ball numbers itself
  /// correctly without asking the server.
  lastSeq: number;
  deviceId: string;
  updatedAt: number;
};

function open(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE)) {
        db.createObjectStore(STORE, { keyPath: "matchId" });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function tx<T>(mode: IDBTransactionMode, fn: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const db = await open();
  return new Promise<T>((resolve, reject) => {
    const store = db.transaction(STORE, mode).objectStore(STORE);
    const req = fn(store);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  }).finally(() => db.close());
}

export async function load(matchId: string): Promise<OutboxEntry | undefined> {
  try {
    return await tx("readonly", (s) => s.get(matchId) as IDBRequest<OutboxEntry>);
  } catch {
    // A browser with storage turned off is a browser that cannot score
    // offline. It should still score online, so this is never fatal.
    return undefined;
  }
}

export async function save(entry: OutboxEntry): Promise<void> {
  try {
    await tx("readwrite", (s) => s.put({ ...entry, updatedAt: Date.now() }));
  } catch {
    /* see load() */
  }
}

/// Everything with work still queued — what a sweep on reconnect looks at.
export async function pendingMatches(): Promise<OutboxEntry[]> {
  try {
    const all = await tx("readonly", (s) => s.getAll() as IDBRequest<OutboxEntry[]>);
    return all.filter((e) => e.pending.length > 0);
  } catch {
    return [];
  }
}

export async function clear(matchId: string): Promise<void> {
  try {
    await tx("readwrite", (s) => s.delete(matchId));
  } catch {
    /* see load() */
  }
}

/// How the scorer's screen describes itself.
///
/// The words are iOS's, because a club that uses both should not have to learn
/// two vocabularies for the same three states.
export type SyncState = "saved" | "syncing" | "offline";

export function syncLabel(state: SyncState, queued: number, t: T): string {
  if (state === "saved") return t("sync.saved");
  if (state === "syncing") return t("le.syncing");
  return t("sync.offline_balls", { n: queued, count: queued });
}

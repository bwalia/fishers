# Chat Scaling Runbook

How chat is built to scale, what is already done, and the moves that are
deliberately deferred — each with a **trigger** (when to do it), a **how**, and
the **risk**. Read this before "optimising" chat or reacting to a scale alarm.

Backend: `backend/api/src/routes/chat.rs` → `backend/db/src/repos/chat.rs` →
Postgres. Real-time: triggers in
`backend/db/migrations/20260911000002_live_events.sql` → `NOTIFY` →
`backend/api/src/routes/live.rs` → SSE. Frontend: `web/src/app/chat/`,
`web/src/lib/inbox.ts`.

The same document for opsapi's chat is `CHAT_SCALING_RUNBOOK.md` at the root of
that repo. The two systems made different choices; the comparison at the bottom
is worth reading before copying either.

---

## 1. What is already done (do NOT redo)

- **Message list is keyset-paginated.** `list_messages` pages on
  `created_at < $before` with `ORDER BY created_at DESC` and a limit clamped to
  1..200, against `idx_messages_conversation (conversation_id, created_at
  DESC)`. O(log n) at any depth. **Never reintroduce `OFFSET`.**
- **Unread counts are bounded.** Both the unread count and the pending-proposal
  count in `list_for_user` stop at 100; the UI renders `99+` via
  `unreadLabel()` in `web/src/lib/chat.ts`. Measured on 205,800 messages with
  one thread 200,000 behind: 50.2ms → 1.7ms, and unchanged (0.46ms) for a user
  who is caught up. **Do not turn either back into an unbounded count.**
- **The nav bell agrees with the chips by construction.** `inbox.ts` sums the
  per-thread counts; a capped thread contributes 100, which puts the sum past
  99 on its own, and both render through the same `unreadLabel()`.
- **Push fan-out is off the request.** `post_message` commits the message and
  returns; the member lookup and the per-device sends happen in a spawned task.
  **Do not move it back inline** — its cost grows with the size of the room.
- **Real-time is cross-replica already.** Publishers are `AFTER INSERT`
  triggers that `pg_notify` on one channel; every API replica `LISTEN`s and
  forwards to its own SSE clients. This is why chat works on `fishers-prod`'s
  two replicas with no Redis. **Do not "fix" this with Redis** (see §3).
- **The live payload is ids only.** Never message content. The browser
  re-fetches through the access-checked endpoint, so a fan-out mistake can at
  worst say "something changed", never what.
- **The publishers are database triggers, not application code**, so a write
  path added later cannot forget to publish. `NOTIFY` is transactional: it
  fires on commit and never for a rolled-back write.

---

## 2. Deferred — with triggers

### 2a. Partition or archive `messages`

- **Status:** one regular table. No archive table, no rotation.
- **Trigger:** approaching **~100M rows**, or when vacuum time, index bloat or
  backup duration on that table becomes a problem. Watch
  `pg_stat_user_tables.n_live_tup` and table size.
- **Do first, because it may remove the need:** decide a **retention policy**.
  What is the oldest message anyone can actually read? With an answer, this
  becomes a batched delete-or-move on a schedule instead of a live-table
  migration.
- **How:** an archival job (lower risk — batches of ~10k off-peak, idempotent
  and resumable), or declarative `PARTITION BY RANGE (created_at)` with monthly
  partitions (better long-term, much bigger job).
- **Risk:** partitioning a populated table is create-new + backfill + swap.
  Needs a window or dual-write. Rehearse on a copy, have a rollback, never run
  it casually against a shared database.

### 2b. Covering index on the message list

- **Trigger:** only when `EXPLAIN (ANALYZE, BUFFERS)` shows the heap fetch
  dominating `list_messages`. It does not today.
- **How:** add `INCLUDE (sender_id, kind, body, metadata)` to
  `idx_messages_conversation`.
- **Risk:** a wider index is more to keep in cache and slower to write. Measure
  before and after; this is a trade, not a free win.

### 2c. Full-text search

- **Trigger:** when searching chat becomes a feature anyone asked for.
- **How:** `tsvector` column + GIN, maintained by trigger.
- **Risk:** the index grows with the table and is expensive to rebuild. Decide
  up front whether search covers archived messages or only hot ones.

### 2d. SSE backpressure and client backoff

- **Status:** every connected browser also polls on a timer regardless of
  whether its stream is healthy.
- **Trigger:** real concurrency — when SSE connection count per pod or the
  steady-state request rate from idle tabs shows up in the metrics.
- **How:** back the poll off while the stream is live, drop the stream when the
  tab is hidden, and bound the per-connection send queue.

### 2e. A durable push outbox

- **Status:** the fan-out is spawned, so a pod dying mid-send loses those
  pushes. The message itself is safe, and SSE plus polling still deliver it.
- **Trigger:** only if a missed notification is ever judged worse than the
  complexity. It has not been.
- **How:** a table with status and attempt count, drained by a worker.
  `notifications_log` is a **log**, not an outbox — no status, no attempts — so
  it would need both. Note `spawn_scheduler` ticks every 300s under an advisory
  lock, which is far too slow for chat: this needs its own faster loop.

### 2f. Replacing `pg_notify`

- **Trigger:** beyond roughly **50 replicas**, where every replica receiving
  every event stops being free.
- **How:** a broker keyed by conversation, so a replica only receives events
  for conversations it holds connections for.
- **Risk:** gives up the two properties §1 relies on — transactional publish,
  and publishers that cannot be forgotten because they are triggers.

---

## 3. How this differs from opsapi, and why

Both repos have chat; the designs diverge, and each is better at something.

| | fishers | opsapi |
|---|---|---|
| transport | SSE + Postgres `NOTIFY` | WebSocket hub, in-process registry |
| multi-replica | **works today** | **breaks on 2+ pods**; Redis deferred |
| unread count | capped (as of this runbook) | capped (`LIMIT 100`) |
| pagination | keyset | keyset |
| search | none | GIN `search_vector` |
| archival | none | archive table exists, nothing rotates |

fishers' `NOTIFY` design solves for free the thing opsapi has to build Redis
for. The cost is §2f: one global channel, every replica filtered locally. That
is the right trade at two replicas and the wrong one at five hundred.

**So do not copy opsapi's Redis hub here**, and do not copy fishers' `NOTIFY`
there — opsapi runs one worker with an in-process registry, which is cheaper
still until it scales out.

---

## 4. What to watch

- **DB:** `pg_stat_statements` for `list_for_user` and `list_messages`,
  `messages` row count and size, index bloat, connections vs `max_connections`.
- **Real-time:** SSE connections per pod, reconnect rate.
- **App:** p95 on `GET /conversations` (the fan-out of counts) and
  `GET /conversations/{id}/messages`.

## 5. Load-bearing invariants

- `list_messages` stays keyset-paginated. No `OFFSET`.
- Unread and proposal counts stay bounded, and the UI keeps rendering `99+`
  through one shared `unreadLabel()`.
- Push fan-out stays off the request path.
- The live payload stays ids only.
- The publishers stay database triggers.
- Delivery keeps working across 2+ replicas.
- New per-message work is O(1) **per page**, never per message. No N+1.

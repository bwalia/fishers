# Fishers platform architecture (Phase 2)

Fishers is one club experience — not a stack of disconnected modules. Cricket is the first sport; the platform underneath must stay multi-sport ready.

## Product spine

```text
Club → Members → Teams → Matches → Match activity
  → Communication → Statistics → Payments → Club identity → AI
```

One source of truth. The mobile app, chat, and AI all read and write through the same domain services.

## Domain layers

| Layer | Examples | Owns truth? |
|-------|----------|-------------|
| **Platform** | Club, Member, Team, Event, Chat, Payment, Notification | Yes |
| **Sport (cricket today)** | Match, Innings, Delivery, Scorecard | Yes for that sport’s rules |
| **AI** | Conversation context, proposals, tools | **No** — consumes platform + sport |

Sport engines emit **platform events** when something club-meaningful happens (match completed, squad published). They do not invent parallel member/payment/chat stores.

## Platform events

Table `platform_events` is an append-only club activity log.

Kinds include: `availability_changed`, `squad_changed`, `squad_published`, `match_started`, `match_completed`, `agent_proposal_applied`, `payment_chase_issued`, `recognition_recorded`.

Emitted (best-effort) from:

- Cricket claim-scorer / match complete sync
- Selection publish
- Agent proposal apply

Downstream (stats, notifications, AI briefing) should subscribe to these events rather than duplicating business rules.

## Chat agent = platform conversational interface

```text
App / Chat → Agent (proposals) → Human apply → Domain services → Postgres
                ↑
         Club briefing (shared context builder)
```

Rules:

- LLM **never** writes the database and never becomes a second source of truth.
- Analyse / apply use `Permission::UseAdminAssistant` (and kind-specific perms such as `ManageSelection` for squad).
- Apply goes through `services/agent_apply` — same invite/availability paths as the UI.
- Context comes from `services/club_briefing` (roster, fixtures, availability, fees, transcript + recent platform activity).

## Permissions

One matrix: `backend/domain/src/rbac.rs`. AI tools inherit it. Asking the assistant never grants extra authority.

## iOS club context

`ClubContextStore` holds `activeClubId` + role for Home, Chat, and Shop so each screen does not invent its own club picker.

## Multi-sport

New sports add their own match/rules/stats modules (like `domain/cricket`) and emit the same platform events. Clubs, members, chat, AI, payments, and admin stay shared.

## What Phase 2 deliberately did not do

Full LLM tool-calling, automatic system-initiated chat posts, MOTM UI, ecommerce provider adapters, and a notification outbox worker — those build on this spine without rewriting it.

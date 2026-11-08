# RBAC — roles & invite-to-play

Fishers gates admin actions with a permission matrix. Roles live on `club_members.role` (and optionally `team_members.role`).

## Roles (product → storage)

| Product name | Stored as | Who |
|---|---|---|
| **Club secretary** | `club_admin` | Roster, club/team/event invites, venues, fees, selection oversight |
| **Team captain** | `team_captain` | Invite to play, create fixtures, pick/publish squad, score matches |
| **Vice captain** | `team_vice_captain` | Score matches, help with selection |
| **Member** | `member` | Availability, RSVP, shop, chat |
| **Guest** | `guest` | Same as member for a one-off invitee |
| **Super admin** | `super_admin` | Platform ops |

Aliases accepted when parsing: `secretary` / `club_secretary` → `club_admin`, `captain` → `team_captain`, `vice_captain` → `team_vice_captain`.

## Permissions

Defined in `backend/domain/src/rbac.rs` (unit-tested):

| Permission | Secretary | Captain | Vice | Member |
|---|---|---|---|---|
| `invite_to_club` | ✓ | | | |
| `invite_to_team` | ✓ | ✓ | | |
| `invite_to_event` (**invite to play**) | ✓ | ✓ | ✓ | |
| `manage_events` | ✓ | ✓ | | |
| `manage_selection` | ✓ | ✓ | ✓ | |
| `score_match` | ✓ | ✓ | ✓ | |
| `manage_members` | ✓ | | | |
| `manage_club_ops` | ✓ | | | |
| `use_admin_assistant` | ✓ | ✓ | | |
| `respond_as_player` / `view_club` | ✓ | ✓ | ✓ | ✓ |

Match scorers without a club role can be listed on `cricket_match_officials` — see [CRICKET_SCORING.md](CRICKET_SCORING.md).

## API enforcement

- `POST /events/{id}/invite` — captain or secretary only
- `POST /invites` — permission depends on `target_type` (`club` / `team` / `event`)
- `POST /clubs/{id}/members` — secretary only (appoint captains here)
- `POST /clubs/{id}/teams|venues` — secretary (`manage_club_ops`)
- `POST /events` — captain or secretary (`manage_events`)
- Cricket scoring routes — `score_match` or match official

Helpers: `backend/api/src/rbac.rs`. **Every route goes through them.** Selection,
chat and tournament routes each used to carry their own hardcoded
`club_admin | team_captain | super_admin` check, which locked vice captains out
of the permissions this table grants them and ignored a captaincy recorded on
the team rather than the club. Those copies are gone; if you add a route, gate
it with `require_permission` and a `Permission`, never a role list.

## Club accounts — the owner and treasurers only

Club money is the one place where "the secretary can do everything" stops.
The books (`/clubs/{id}/accounts/…`) open for exactly two kinds of person:

- the club's **owner** (`clubs.owner_id`), and
- an active member the club has made its **treasurer**.

Nobody else — not a secretary, not a captain, not a super admin — gets in. The
refusal is a 403 with code `accounts_forbidden`. Every accounts route starts
with `require_accounts_access` in `backend/api/src/rbac.rs`; hiding the link in
a client is not the protection.

**Treasurer is a flag, not a role.** It lives on the membership as
`club_members.is_treasurer`, beside the role, for two reasons: a small club's
secretary is very often its treasurer too, and phones already installed decode
`role` as a closed list — a new value there would fail the whole member list on
iOS, while an extra `is_treasurer` key is simply ignored.

| Method | Path | Who |
|---|---|---|
| `PUT` | `/clubs/{id}/members/{user_id}/treasurer` | owner or secretary — `{"is_treasurer": true}` |
| `GET` | `/clubs/{id}/my-role` | adds `is_owner`, `is_treasurer`, `can_open_accounts` |
| any | `/clubs/{id}/accounts/…` | owner or treasurer |
| `POST` | `/clubs/{id}/accounts/periods/{pid}/reopen` | owner only |

Appointing a treasurer gives the person who appointed them no access to the
books. Every change to the books, and every appointment, is in the accounts
audit trail. See [CLUB_ACCOUNTS.md](CLUB_ACCOUNTS.md).

## Who can change roles

A **club secretary** appoints and stands down captains, vice captains and
members, from **Clubs → the club → ⋯ → Manage club**. The API refuses to remove
a club's last secretary, so a club can never end up with nobody able to run it.

| Method | Path | Who |
|---|---|---|
| `GET` | `/clubs/{id}/members` | any member — names, roles, contact |
| `POST` | `/clubs/{id}/members` | secretary — add by `user_id` or `email` |
| `PATCH` | `/clubs/{id}/members/{user_id}` | secretary — `{"role": "captain"}` |
| `DELETE` | `/clubs/{id}/members/{user_id}` | secretary |
| `GET/PATCH` | `/clubs/{id}/settings` | read: any member · write: `manage_club_ops` |

Club settings are the selection and fee policy: how much the assistant may do
(`off` / `suggest` / `auto_publish`), the reconfirm and drop windows, and how
hard match fees are chased.

## Client

`GET /clubs/{id}/my-role` returns:

```json
{
  "role": "club_admin",
  "display_name": "Club secretary",
  "is_secretary": true,
  "is_captain": true,
  "can_invite_to_play": true,
  "can_score_match": true,
  "permissions": ["view_club", "invite_to_event", "score_match", "..."]
}
```

iOS: `ClubRole` / `ClubRoleInfo` in `ios/Fishers/Models/RBAC.swift`, `FishersAPI.myClubRole(clubId:)`.

## How to test invite-to-play

1. As **secretary** (`club_admin`): `POST /clubs/{id}/members` with `"role":"team_captain"` for a player.
2. As **captain**: `POST /events/{id}/invite` `{ "user_id": "…" }` → 200.
3. As **member**: same invite → **403** (`Member cannot invite_to_event`).
4. `GET /clubs/{id}/my-role` as each user and check `can_invite_to_play`.

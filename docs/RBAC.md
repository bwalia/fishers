# RBAC — roles & invite-to-play

Fishers gates admin actions with a permission matrix. Roles live on `club_members.role` (and optionally `team_members.role`).

## Roles (product → storage)

| Product name | Stored as | Who |
|---|---|---|
| **Club secretary** | `club_admin` | Roster, club/team/event invites, venues, fees, selection oversight |
| **Team captain** | `team_captain` | Invite to play, create fixtures, pick/publish squad |
| **Member** | `member` | Availability, RSVP, shop, chat |
| **Guest** | `guest` | Same as member for a one-off invitee |
| **Super admin** | `super_admin` | Platform ops |

Aliases accepted when parsing: `secretary` / `club_secretary` → `club_admin`, `captain` → `team_captain`.

## Permissions

Defined in `backend/domain/src/rbac.rs` (unit-tested):

| Permission | Secretary | Captain | Member |
|---|---|---|---|
| `invite_to_club` | ✓ | | |
| `invite_to_team` | ✓ | ✓ | |
| `invite_to_event` (**invite to play**) | ✓ | ✓ | |
| `manage_events` | ✓ | ✓ | |
| `manage_selection` | ✓ | ✓ | |
| `manage_members` | ✓ | | |
| `manage_club_ops` | ✓ | | |
| `use_admin_assistant` | ✓ | ✓ | |
| `respond_as_player` / `view_club` | ✓ | ✓ | ✓ |

## API enforcement

- `POST /events/{id}/invite` — captain or secretary only
- `POST /invites` — permission depends on `target_type` (`club` / `team` / `event`)
- `POST /clubs/{id}/members` — secretary only (appoint captains here)
- `POST /clubs/{id}/teams|venues` — secretary (`manage_club_ops`)
- `POST /events` — captain or secretary (`manage_events`)

Helpers: `backend/api/src/rbac.rs`.

## Client

`GET /clubs/{id}/my-role` returns:

```json
{
  "role": "club_admin",
  "display_name": "Club secretary",
  "is_secretary": true,
  "is_captain": true,
  "can_invite_to_play": true,
  "permissions": ["view_club", "invite_to_event", "..."]
}
```

iOS: `ClubRole` / `ClubRoleInfo` in `ios/Fishers/Models/RBAC.swift`, `FishersAPI.myClubRole(clubId:)`.

## How to test invite-to-play

1. As **secretary** (`club_admin`): `POST /clubs/{id}/members` with `"role":"team_captain"` for a player.
2. As **captain**: `POST /events/{id}/invite` `{ "user_id": "…" }` → 200.
3. As **member**: same invite → **403** (`Member cannot invite_to_event`).
4. `GET /clubs/{id}/my-role` as each user and check `can_invite_to_play`.

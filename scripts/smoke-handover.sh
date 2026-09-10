#!/usr/bin/env bash
# Who may be handed the book, and what happens when an umpire is named.
#
# The bug this pins down: the book could only go to an officer of the home
# club, so a scorer at the ground was offered one name. It goes to anybody
# playing now, either side — and whoever holds it can write in it, which is a
# separate rule that has to move with it.
#
#   ./scripts/smoke-handover.sh [http://127.0.0.1:7312]
set -euo pipefail

BASE="${1:-http://127.0.0.1:7312}/api/v1"
export SMOKE_BASE="$BASE"

curl -sf "${1:-http://127.0.0.1:7312}/health" >/dev/null || {
  echo "no API at ${1:-http://127.0.0.1:7312} — start one first" >&2
  exit 1
}

python3 - <<'PY'
import json, os, time, urllib.request, urllib.error, uuid

BASE = os.environ["SMOKE_BASE"]
STAMP = int(time.time())
failures = []


def call(method, path, body=None, token=None):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json"}, method=method)
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw.decode()[:160]


def check(label, got, want):
    ok = got == want
    print(f"{'ok  ' if ok else 'FAIL'} {label}: {got!r}")
    if not ok:
        failures.append(f"{label}: got {got!r}, wanted {want!r}")


def club(prefix, name, players):
    _, sec = call("POST", "/auth/signup", {
        "name": f"{prefix} Secretary", "email": f"{prefix}{STAMP}@t.test",
        "password": "password123"})
    tok = sec["access_token"]
    _, c = call("POST", "/clubs", {"name": name, "sport_types": ["cricket"]}, tok)
    people = {}
    for i, who in enumerate(players):
        _, u = call("POST", "/auth/signup", {
            "name": who, "email": f"{prefix}p{i}{STAMP}@t.test", "password": "password123"})
        call("POST", f"/clubs/{c['id']}/members", {
            "identifier": f"{prefix}p{i}{STAMP}@t.test",
            "role": "team_captain" if i == 0 else "member"}, tok)
        people[who] = {"token": u["access_token"], "id": u["user"]["id"]}
    return tok, c, people


home_tok, home, home_people = club("hh", "Handover Home CC", ["H Captain", "H Bat", "H Keeper"])
away_tok, away, away_people = club("ha", "Handover Away CC", ["A Captain", "A Bat", "A Keeper"])

# Somebody in neither team and neither club — the control.
_, outsider = call("POST", "/auth/signup", {
    "name": "Passing Stranger", "email": f"hx{STAMP}@t.test", "password": "password123"})

_, event = call("POST", "/events", {
    "club_id": home["id"], "sport": "cricket", "event_subtype": "league_match",
    "title": f"Handover {STAMP}", "start_at": "2026-09-12T13:00:00Z",
    "end_at": "2026-09-12T18:00:00Z"}, home_tok)
_, match = call("POST", f"/events/{event['id']}/cricket-match", {
    "overs_limit": 20, "home_name": home["name"], "away_name": away["name"],
    "opponent_club_id": away["id"]}, home_tok)
MID = match["id"]

# --- Umpire named while the book is free takes it --------------------------

check("nobody holds the book yet",
      call("GET", f"/cricket/matches/{MID}", token=home_tok)[1]["active_scorer_user_id"],
      None)

status, _ = call("POST", f"/cricket/matches/{MID}/officials",
                 {"user_id": away_people["A Keeper"]["id"], "role": "umpire"}, home_tok)
check("a secretary can name an umpire from the other side", status, 200)
check("and the book is in the umpire's hands",
      call("GET", f"/cricket/matches/{MID}", token=home_tok)[1]["active_scorer_user_id"],
      away_people["A Keeper"]["id"])

# --- Naming a second umpire must not take it off them ----------------------

call("POST", f"/cricket/matches/{MID}/officials",
     {"user_id": home_people["H Keeper"]["id"], "role": "umpire"}, home_tok)
check("a second umpire does not take the book off the first",
      call("GET", f"/cricket/matches/{MID}", token=home_tok)[1]["active_scorer_user_id"],
      away_people["A Keeper"]["id"])

umpire = away_people["A Keeper"]["token"]

# --- Name the XIs, so there is somebody "playing" --------------------------

def sheet(people):
    return [{"id": p["id"], "name": who, "bats_left": False} for who, p in people.items()]


home_sheet, away_sheet = sheet(home_people), sheet(away_people)
home_xi = [p["id"] for p in home_sheet]
away_xi = [p["id"] for p in away_sheet]
check("the home captain names their side",
      call("POST", f"/cricket/matches/{MID}/xi",
           {"side": "home", "players": home_sheet, "captain_id": home_xi[0]}, home_tok)[0], 200)
check("and the away captain names theirs",
      call("POST", f"/cricket/matches/{MID}/xi",
           {"side": "away", "players": away_sheet, "captain_id": away_xi[0]}, away_tok)[0], 200)

# --- The rule the bug was about --------------------------------------------

status, body = call("POST", f"/cricket/matches/{MID}/handover",
                    {"to_user_id": home_people["H Captain"]["id"]}, umpire)
check("the umpire hands it to the home captain", status, 200)

status, _ = call("POST", f"/cricket/matches/{MID}/handover",
                 {"to_user_id": away_people["A Bat"]["id"]},
                 home_people["H Captain"]["token"])
check("who hands it across to an ordinary opposition player", status, 200)

opposition_bat = away_people["A Bat"]["token"]

status, body = call("POST", f"/cricket/matches/{MID}/handover",
                    {"to_user_id": outsider["user"]["id"]}, opposition_bat)
check("but not to somebody in neither club", status, 400)
check("and it says why", "not playing this match" in json.dumps(body), True)

# In the club but left out of the XI — the twelfth man, who very often keeps
# the book. The squad screen offers them, so the server has to take them.
_, twelfth = call("POST", "/auth/signup", {
    "name": "Twelfth Man", "email": f"h12{STAMP}@t.test", "password": "password123"})
call("POST", f"/clubs/{home['id']}/members",
     {"identifier": f"h12{STAMP}@t.test", "role": "member"}, home_tok)
status, _ = call("POST", f"/cricket/matches/{MID}/handover",
                 {"to_user_id": twelfth["user"]["id"]}, opposition_bat)
check("a club member left out of the XI can still take it", status, 200)
status, _ = call("POST", f"/cricket/matches/{MID}/handover",
                 {"to_user_id": away_people["A Bat"]["id"]}, twelfth["access_token"])
check("and hand it back", status, 200)

status, _ = call("POST", f"/cricket/matches/{MID}/handover",
                 {"to_user_id": home_people["H Bat"]["id"]}, home_tok)
check("only whoever holds it can pass it on", status, 403)

# --- Holding it is what lets you write in it -------------------------------

def toss(seq):
    return [{"client_event_id": str(uuid.uuid4()), "seq": seq,
             "kind": {"type": "toss_recorded", "winner": "home", "decision": "bat"}}]


status, body = call("POST", f"/cricket/matches/{MID}/events",
                    {"device_id": "smoke-away", "events": toss(1)}, opposition_bat)
check("an opposition player holding the book can score with it", status, 200)

# The captain let it go two steps ago. They still have `score_match` for their
# own club, so the refusal has to be about the book, not about permission.
status, body = call("POST", f"/cricket/matches/{MID}/events",
                    {"device_id": "smoke-home", "events": toss(2)},
                    home_people["H Captain"]["token"])
check("a captain who let it go is refused for the book, not the role", status, 409)
check("and is told so", "active scorer" in json.dumps(body), True)

# And a plain member who never held it is refused earlier, on the role.
status, _ = call("POST", f"/cricket/matches/{MID}/events",
                 {"device_id": "smoke-nobody", "events": toss(2)},
                 home_people["H Bat"]["token"])
check("a member who never held it cannot score at all", status, 403)

print()
if failures:
    print("FAILURES:")
    for f in failures:
        print(" -", f)
    raise SystemExit(1)
print("all good")
PY

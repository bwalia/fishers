#!/usr/bin/env bash
# Seed a demo account so the web dashboard has something to show.
# Creates demo@fishers.test / password123 with a club, fixtures, shop stock and
# a part-scored cricket match, then prints the live scoreboard link.
#
#   ./scripts/seed-demo.sh                       # against http://127.0.0.1:7312
#   API_BASE=http://192.168.1.70:7312 ./scripts/seed-demo.sh
set -euo pipefail

API_BASE="${API_BASE:-http://127.0.0.1:7312}"

curl -sf -m 5 "${API_BASE}/health" >/dev/null || {
  echo "No API at ${API_BASE} — start it with ./scripts/start.sh first." >&2
  exit 1
}

API_BASE="$API_BASE" python3 - <<'PY'
import json, os, urllib.request, urllib.error, uuid, datetime

API = os.environ["API_BASE"] + "/api/v1"
EMAIL, PASSWORD = "demo@fishers.test", "password123"

def call(method, path, body=None, token=None):
    req = urllib.request.Request(
        API + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json",
                 **({"Authorization": f"Bearer {token}"} if token else {})},
        method=method)
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {path} -> {e.code}: {e.read().decode()[:200]}") from None

# Some list endpoints are paged ({"items": [...]}), others still return a bare
# array. Reading either the same way keeps seeding working as more of them are
# paged — iterating the envelope silently yields its keys instead of its rows.
def rows(data):
    return data["items"] if isinstance(data, dict) and "items" in data else data

# Re-runnable: sign in if the demo account already exists.
try:
    auth = call("POST", "/auth/login", {"email": EMAIL, "password": PASSWORD})
    print(f"signed in as {EMAIL}")
except RuntimeError:
    auth = call("POST", "/auth/signup",
                {"name": "Demo Captain", "email": EMAIL, "password": PASSWORD})
    print(f"created {EMAIL}")
tok = auth["access_token"]

CLUB = "London Lords CC"
club = next((c for c in rows(call("GET", "/clubs", None, tok)) if c["name"] == CLUB), None)
if club:
    print(f"club: {CLUB} (existing)")
else:
    club = call("POST", "/clubs", {
        "name": CLUB, "sport_types": ["cricket"],
        "visibility": "invite_only",
        "description": "Weekly nets, Saturday league & Sunday socials"}, tok)
    print(f"club: {CLUB}")

now = datetime.datetime.now(datetime.timezone.utc)
iso = lambda d: d.isoformat().replace("+00:00", "Z")

have = {e["title"] for e in rows(call("GET", f"/events?club_id={club['id']}", None, tok))}
for title, subtype, days, cap, fee in [
    ("Wednesday Nets", "nets", 2, 18, 600),
    ("Saturday League vs Hemel", "league_match", 4, 22, 1500),
    ("Sunday Social Cricket", "social", 5, 24, 800),
]:
    if title in have:
        continue
    call("POST", "/events", {
        "club_id": club["id"], "sport": "cricket", "event_subtype": subtype,
        "title": title, "start_at": iso(now + datetime.timedelta(days=days)),
        "end_at": iso(now + datetime.timedelta(days=days, hours=4)),
        "capacity": cap, "fee_amount_cents": fee}, tok)
print("fixtures: 3")

stocked = {p["name"] for p in rows(call("GET", f"/clubs/{club['id']}/products", None, tok))}
for name, category, cents in [
    ("Kookaburra Match Ball", "equipment", 2400),
    ("Gray-Nicolls Player Bat", "equipment", 18500),
    ("Club Training Shirt", "merchandise", 3200),
    ("Club Cap", "merchandise", 1400),
    ("Bowling Machine Hire (1hr)", "kit_hire", 2000),
    ("Match Tea", "food", 500),
]:
    if name in stocked:
        continue
    call("POST", f"/clubs/{club['id']}/products", {
        "name": name, "category": category, "price_cents": cents,
        "currency": "GBP", "stock": 12}, tok)
print("shop: 6 products")

# A live match, part-scored, so the public scoreboard has something to render.
LIVE = "Lords vs Hemel — live"
event = next((e for e in rows(call("GET", f"/events?club_id={club['id']}", None, tok))
              if e["title"] == LIVE), None)
if event is None:
    event = call("POST", "/events", {
        "club_id": club["id"], "sport": "cricket", "event_subtype": "league_match",
        "title": LIVE, "start_at": iso(now),
        "end_at": iso(now + datetime.timedelta(hours=4)), "capacity": 22}, tok)
# POST is create-or-get, so this is safe to repeat.
match = call("POST", f"/events/{event['id']}/cricket-match", {
    "overs_limit": 20, "home_name": "Lords", "away_name": "Hemel"}, tok)
call("POST", f"/cricket/matches/{match['id']}/claim-scorer", {"device_id": "seed"}, tok)

already_scored = call("GET", f"/cricket/matches/{match['id']}", None, tok).get("last_seq", 0) > 0

player = lambda n: {"id": str(uuid.uuid4()), "name": n, "bats_left": n.endswith("4")}
home = [player(f"Lords {i}") for i in range(1, 12)]
away = [player(f"Hemel {i}") for i in range(1, 12)]

seq, events = 0, []
def ev(kind):
    global seq
    seq += 1
    events.append({"client_event_id": str(uuid.uuid4()), "seq": seq, "kind": kind,
                   "at": iso(datetime.datetime.now(datetime.timezone.utc))})

conditions = {"overs_limit": 20, "overs_per_bowler": 4, "ground": "open",
              "ball": "white", "powerplay_overs": 6,
              "fielders_outside_powerplay": 2, "fielders_outside_normal": 5,
              "fielders_behind_square_leg": 2, "target_overs_per_hour": 14}

ev({"type": "match_prepared", "overs_limit": 20, "home_name": "Lords", "away_name": "Hemel"})
ev({"type": "conditions_proposed", "by": "home", "by_name": "Ravi", "conditions": conditions})
ev({"type": "conditions_agreed", "side": "away", "captain_name": "Sam"})
ev({"type": "officials_appointed", "officials": {
    "umpires": [{"id": str(uuid.uuid4()), "name": "Alan Umpire", "bats_left": False}],
    "scorers": []}})
ev({"type": "toss_recorded", "winner": "home", "decision": "bat"})
ev({"type": "xi_selected", "side": "home", "players": home, "captain_id": home[0]["id"]})
ev({"type": "xi_selected", "side": "away", "players": away, "captain_id": away[0]["id"]})
ev({"type": "innings_started", "innings_index": 0, "batting": "home",
    "striker_id": home[0]["id"], "non_striker_id": home[1]["id"],
    "bowler_id": away[0]["id"], "super_over": False})
ev({"type": "field_set", "outside_circle": 2, "behind_square_leg": 2})

shots = [
    (4, "drive", 280, True, False), (1, "glance", 150, False, False),
    (0, None, 0, False, False), (6, "loft", 20, False, True),
    (2, "cut", 250, False, False), (1, "flick", 95, False, False),
]
for runs, kind, angle, four, six in shots:
    ev({"type": "delivery_recorded", "runs": runs, "is_legal": True,
        "is_boundary_four": four, "is_boundary_six": six,
        # A defended dot has no shot to plot — the wheel only shows real strokes.
        "shot": None if kind is None else
                {"angle": angle, "kind": kind, "reach": 1.0 if four or six else 0.5}})
ev({"type": "bowler_changed", "bowler_id": away[1]["id"]})
ev({"type": "extras_recorded", "kind": "wide", "runs": 1, "boundary": False,
    "off_the_bat": False, "shot": None})
ev({"type": "delivery_recorded", "runs": 4, "is_legal": True, "is_boundary_four": True,
    "is_boundary_six": False, "shot": {"angle": 200, "kind": "sweep", "reach": 1.0}})
ev({"type": "wicket_recorded", "kind": "bowled", "batter_id": home[0]["id"],
    "new_batter_id": home[2]["id"], "runs": 0})

if already_scored:
    state = call("GET", f"/cricket/matches/{match['id']}", None, tok)["state"]
    suffix = " (existing)"
else:
    state = call("POST", f"/cricket/matches/{match['id']}/events",
                 {"device_id": "seed", "events": events}, tok)["state"]
    suffix = ""
inn = state["innings"][0]
print(f"match: {inn['runs']}/{inn['wickets']} ({inn['legal_balls']} balls){suffix}")

# --- a finished match, so the season boards have something in them ----------
# Season stats are only written when a match completes, and only for players
# who are real users — a guest id matches no row, so the insert finds nothing.
SQUAD = [("Ravi Sharma", False), ("Sam Blake", True), ("Tom Reed", False),
         ("Alex Khan", False), ("Joe Miller", False), ("Dan Foster", True)]
squad = []
for i, (name, left) in enumerate(SQUAD):
    email = f"player{i + 1}@fishers.test"
    try:
        a = call("POST", "/auth/login", {"email": email, "password": PASSWORD})
    except RuntimeError:
        a = call("POST", "/auth/signup", {"name": name, "email": email, "password": PASSWORD})
    uid = a["user"]["id"]
    try:
        call("POST", f"/clubs/{club['id']}/members", {"user_id": uid, "role": "member"}, tok)
    except RuntimeError:
        pass  # already a member
    squad.append({"id": uid, "name": name, "bats_left": left})

RESULT = "League vs Watford — result"
revent = next((e for e in rows(call("GET", f"/events?club_id={club['id']}", None, tok))
               if e["title"] == RESULT), None)
if revent is None:
    revent = call("POST", "/events", {
        "club_id": club["id"], "sport": "cricket", "event_subtype": "league_match",
        "title": RESULT, "start_at": iso(now - datetime.timedelta(days=7)),
        "end_at": iso(now - datetime.timedelta(days=7) + datetime.timedelta(hours=4)),
        "capacity": 22}, tok)
rmatch = call("POST", f"/events/{revent['id']}/cricket-match", {
    "overs_limit": 1, "home_name": "London Lords", "away_name": "Watford"}, tok)
call("POST", f"/cricket/matches/{rmatch['id']}/claim-scorer", {"device_id": "seed"}, tok)

if call("GET", f"/cricket/matches/{rmatch['id']}", None, tok)["state"]["status"] != "complete":
    seq, events = 0, []
    lords, watford = squad[:3], squad[3:]
    rc = dict(conditions, overs_limit=1, overs_per_bowler=1, powerplay_overs=0)
    ev({"type": "match_prepared", "overs_limit": 1,
        "home_name": "London Lords", "away_name": "Watford"})
    ev({"type": "conditions_proposed", "by": "home", "by_name": "Ravi", "conditions": rc})
    ev({"type": "conditions_agreed", "side": "away", "captain_name": "Alex"})
    ev({"type": "toss_recorded", "winner": "home", "decision": "bat"})
    ev({"type": "xi_selected", "side": "home", "players": lords, "captain_id": lords[0]["id"]})
    ev({"type": "xi_selected", "side": "away", "players": watford, "captain_id": watford[0]["id"]})
    ev({"type": "innings_started", "innings_index": 0, "batting": "home",
        "striker_id": lords[0]["id"], "non_striker_id": lords[1]["id"],
        "bowler_id": watford[0]["id"], "super_over": False})
    for runs, kind, angle in [(4, "drive", 285), (2, "cut", 250), (6, "loft", 15),
                              (1, "glance", 150), (0, None, 0), (4, "sweep", 205)]:
        ev({"type": "delivery_recorded", "runs": runs, "is_legal": True,
            "is_boundary_four": runs == 4, "is_boundary_six": runs == 6,
            "shot": None if kind is None else {"angle": angle, "kind": kind, "reach": 1.0}})
    # 17 all told; Watford need 18 off the over and fall short.
    ev({"type": "innings_started", "innings_index": 1, "batting": "away",
        "striker_id": watford[0]["id"], "non_striker_id": watford[1]["id"],
        "bowler_id": lords[0]["id"], "super_over": False})
    for runs, kind, angle in [(1, "flick", 95), (4, "drive", 300), (2, "cut", 255)]:
        ev({"type": "delivery_recorded", "runs": runs, "is_legal": True,
            "is_boundary_four": runs == 4, "is_boundary_six": False,
            "shot": {"angle": angle, "kind": kind, "reach": 0.9}})
    ev({"type": "wicket_recorded", "kind": "bowled", "batter_id": watford[0]["id"],
        "new_batter_id": watford[2]["id"], "runs": 0})
    for _ in range(2):
        ev({"type": "delivery_recorded", "runs": 1, "is_legal": True,
            "is_boundary_four": False, "is_boundary_six": False, "shot": None})
    rstate = call("POST", f"/cricket/matches/{rmatch['id']}/events",
                  {"device_id": "seed", "events": events}, tok)["state"]
    print(f"result match: {rstate.get('margin') or rstate['status']}")
else:
    print("result match: already played")

share = call("POST", f"/cricket/matches/{match['id']}/share", {"post_to_chat": False}, tok)
print()
print(f"  Sign in    {EMAIL} / {PASSWORD}")
print(f"  Live link  {share['url']}")
PY

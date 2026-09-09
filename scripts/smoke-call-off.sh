#!/usr/bin/env bash
# Calling a match off, and the line between abandoning and deleting.
#
# A match with balls in it is a record of something that happened to real
# people: it gets abandoned, and the scorecard survives. One nobody has scored
# in was a mistake, and is deleted.
#
#   ./scripts/smoke-call-off.sh [http://127.0.0.1:7312]
set -euo pipefail

BASE="${1:-http://127.0.0.1:7312}/api/v1"
export SMOKE_BASE="$BASE"
curl -sf "${1:-http://127.0.0.1:7312}/health" >/dev/null || {
  echo "no API at ${1:-http://127.0.0.1:7312}" >&2; exit 1; }

python3 - <<'PY'
import json, os, time, uuid, urllib.error, urllib.request

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
        people[who] = u["access_token"]
    return tok, c, people


CONDITIONS = {"overs_limit": 20, "overs_per_bowler": 4, "ground": "open", "ball": "white",
              "powerplay_overs": 6, "fielders_outside_powerplay": 2,
              "fielders_outside_normal": 5, "target_overs_per_hour": 0}

home_tok, home, home_people = club("ch", "Call-off Home CC", ["H Captain", "H Two", "H Three"])
away_tok, away, away_people = club("ca", "Call-off Away CC", ["A Captain", "A Two", "A Three"])
plain = home_people["H Two"]


def new_match(title):
    _, event = call("POST", "/events", {
        "club_id": home["id"], "sport": "cricket", "event_subtype": "league_match",
        "title": title, "start_at": "2026-09-08T13:00:00Z",
        "end_at": "2026-09-08T18:00:00Z"}, home_tok)
    _, m = call("POST", f"/events/{event['id']}/cricket-match", {
        "overs_limit": 20, "home_name": home["name"], "away_name": away["name"],
        "opponent_club_id": away["id"]}, home_tok)
    call("POST", f"/cricket/matches/{m['id']}/claim-scorer", {"device_id": "smoke"}, home_tok)
    return m["id"]


# --- Nothing scored: it was a mistake, so it can go -------------------------
mistake = new_match(f"Called off by mistake {STAMP}")
check("a plain member cannot delete a match",
      call("DELETE", f"/cricket/matches/{mistake}", token=plain)[0], 403)
check("the secretary can", call("DELETE", f"/cricket/matches/{mistake}", token=home_tok)[0], 200)
check("and it is gone", call("GET", f"/cricket/matches/{mistake}", token=home_tok)[0], 404)

# --- Balls bowled: it happened, so it is abandoned --------------------------
played = new_match(f"Rained off {STAMP}")
call("POST", f"/cricket/matches/{played}/propose",
     {"conditions": CONDITIONS, "by": "home", "by_name": "H Captain"}, home_tok)
call("POST", f"/cricket/matches/{played}/agree",
     {"side": "away", "captain_name": "A Captain"}, home_tok)
_, cur = call("GET", f"/cricket/matches/{played}", token=home_tok)
call("POST", f"/cricket/matches/{played}/events", {"events": [{
    "client_event_id": str(uuid.uuid4()), "seq": cur["last_seq"] + 1,
    "kind": {"type": "toss_recorded", "winner": "home", "decision": "bat"}}]}, home_tok)

_, squad = call("GET", f"/cricket/matches/{played}/squad", token=home_tok)
for side, key in (("home", "home"), ("away", "away")):
    picks = squad[key]["players"][:3]
    call("POST", f"/cricket/matches/{played}/xi", {
        "side": side,
        "players": [{"id": p["id"], "name": p["name"], "bats_left": False} for p in picks],
        "captain_id": picks[0]["id"], "keeper_id": picks[1]["id"]}, home_tok)

_, st = call("GET", f"/cricket/matches/{played}", token=home_tok)
xi = st["state"]["home_xi"]
bowler = st["state"]["away_xi"][0]
seq = st["last_seq"]
events = [
    {"client_event_id": str(uuid.uuid4()), "seq": seq + 1,
     "kind": {"type": "innings_started", "innings_index": 0, "batting": "home",
              "striker_id": xi[0], "non_striker_id": xi[1], "bowler_id": bowler}},
    {"client_event_id": str(uuid.uuid4()), "seq": seq + 2,
     "kind": {"type": "delivery_recorded", "runs": 4, "is_legal": True,
              "is_boundary_four": True, "is_boundary_six": False}},
]
status, _ = call("POST", f"/cricket/matches/{played}/events", {"events": events}, home_tok)
check("a ball is bowled", status, 200)

# A scorer with several fixtures against the same side will open the wrong one.
# Recording a toss there used to be accepted and set the status back to
# selecting XI, unpicking a game in progress.
_, playing = call("GET", f"/cricket/matches/{played}", token=home_tok)
status, refused = call("POST", f"/cricket/matches/{played}/events", {"events": [{
    "client_event_id": str(uuid.uuid4()), "seq": playing["last_seq"] + 1,
    "kind": {"type": "toss_recorded", "winner": "away", "decision": "bowl"}}]}, home_tok)
check("a started match refuses another toss", status, 409)
check("and says why", "already started" in str(refused), True)
_, intact = call("GET", f"/cricket/matches/{played}", token=home_tok)
check("the innings is untouched",
      intact["state"]["innings"][0]["runs"], playing["state"]["innings"][0]["runs"])
check("the status is untouched", intact["state"]["status"], playing["state"]["status"])
check("and the log did not move", intact["last_seq"], playing["last_seq"])
check("the fixture date is on the match, so you know which one it is",
      intact.get("start_at") is not None, True)

check("a played match cannot be deleted",
      call("DELETE", f"/cricket/matches/{played}", token=home_tok)[0], 409)
check("a plain member cannot abandon it",
      call("POST", f"/cricket/matches/{played}/abandon", {"reason": "rain"}, plain)[0], 403)

status, done = call("POST", f"/cricket/matches/{played}/abandon", {"reason": "rain"}, home_tok)
check("the secretary abandons it", status, 200)
check("no winner", done["state"]["winner"], None)
check("it says why", done["state"]["margin"], "Abandoned — rain (no result)")
check("and it is over", done["state"]["status"], "complete")
check("the runs scored are still there", done["state"]["innings"][0]["runs"], 4)
check("abandoning twice is refused",
      call("POST", f"/cricket/matches/{played}/abandon", {"reason": "again"}, home_tok)[0], 409)
check("a reason is optional",
      call("POST", f"/cricket/matches/{new_match('No reason ' + str(STAMP))}/abandon",
           {}, home_tok)[1]["state"]["margin"], "Abandoned — no result")

# --- The scoring list: filtered, sorted and paged in the database -----------
status, page = call("GET", "/cricket/fixtures?per_page=2", token=home_tok)
check("fixtures come back paged", status, 200)
check("a page is the size asked for", len(page["items"]) <= 2, True)
check("with a total to count against", page["total"] >= 3, True)
check("and knows there is more", page["has_more"], True)
_, page2 = call("GET", "/cricket/fixtures?per_page=2&page=2", token=home_tok)
check("page two is different",
      page["items"][0]["event_id"] != page2["items"][0]["event_id"], True)
_, finished = call("GET", "/cricket/fixtures?state=finished", token=home_tok)
check("finished means finished",
      all(f["match_status"] in ("complete", "published") for f in finished["items"]), True)
_, upcoming = call("GET", "/cricket/fixtures?state=upcoming", token=home_tok)
check("upcoming means nobody has started it",
      all(f["match_id"] is None for f in upcoming["items"]), True)
_, hits = call("GET", f"/cricket/fixtures?q=Rained", token=home_tok)
check("search finds it by title", hits["total"] >= 1, True)
for bad in ("state=sideways", "order=x", "page=0", "per_page=500", "q=a"):
    check(f"'{bad}' is refused", call("GET", f"/cricket/fixtures?{bad}", token=home_tok)[0], 400)

print()
if failures:
    print(f"{len(failures)} failed:")
    for f in failures:
        print("  -", f)
    raise SystemExit(1)
print("all good")
PY

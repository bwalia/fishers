#!/usr/bin/env bash
# The season, the award and the books, against a running API.
#
# Each check is a gap found reviewing #242 and #244:
#  - player of the match is given after the last ball, and a player's season
#    never saw it, because their line for the match was written on the last
#    ball and never again;
#  - closing a season on a server that cannot send mail said "N emails on
#    their way" and marked them sent;
#  - next year's season could be closed before it was played;
#  - a secretary could make themselves treasurer and open the books.
#
#   ./scripts/smoke-season-fixes.sh [http://127.0.0.1:7312]
set -euo pipefail

BASE="${1:-http://127.0.0.1:7312}/api/v1"
export SMOKE_BASE="$BASE"

curl -sf "${1:-http://127.0.0.1:7312}/health" >/dev/null || {
  echo "no API at ${1:-http://127.0.0.1:7312} — start one first" >&2
  exit 1
}

python3 - <<'PY'
import datetime, json, os, time, urllib.error, urllib.request, uuid

BASE = os.environ["SMOKE_BASE"]
STAMP = int(time.time())
YEAR = datetime.date.today().year
failures = []


def call(method, path, body=None, token=None):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json"},
        method=method,
    )
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, (json.loads(raw) if raw else None)


def check(label, got, want):
    ok = got == want
    print(f"{'ok  ' if ok else 'FAIL'} {label}: {got!r}")
    if not ok:
        failures.append(f"{label}: got {got!r}, wanted {want!r}")


def signup(name):
    _, u = call("POST", "/auth/signup", {
        "name": name, "email": f"{name.lower().replace(' ', '')}{STAMP}@t.test",
        "password": "password123"})
    return u["access_token"], u["user"]["id"]


owner, _ = signup("Season Owner")
_, club = call("POST", "/clubs", {
    "name": f"Season Fixes CC {STAMP}", "sport_types": ["cricket"], "visibility": "invite_only"}, owner)
cid = club["id"]
people = {}
for who in ["Home Opener", "Home Partner", "Second Secretary"]:
    tok, uid = signup(who)
    call("POST", f"/clubs/{cid}/members", {
        "identifier": f"{who.lower().replace(' ', '')}{STAMP}@t.test",
        "role": "club_admin" if who == "Second Secretary" else "member"}, owner)
    people[who] = (tok, uid)

# --- A one-over match, scored ball by ball ---------------------------------
_, event = call("POST", "/events", {
    "club_id": cid, "sport": "cricket", "event_subtype": "league_match",
    "title": f"Season fixes {STAMP}", "start_at": f"{YEAR}-06-06T13:00:00Z",
    "end_at": f"{YEAR}-06-06T18:00:00Z"}, owner)
_, match = call("POST", f"/events/{event['id']}/cricket-match",
                {"overs_limit": 1, "home_name": club["name"], "away_name": "The Visitors"}, owner)
MID = match["id"]
h1, h2 = people["Home Opener"][1], people["Home Partner"][1]
a1, a2 = str(uuid.uuid4()), str(uuid.uuid4())
status, body = call("POST", f"/cricket/matches/{MID}/xi", {"side": "home", "captain_id": h1, "players": [
    {"id": h1, "name": "Home Opener", "bats_left": False},
    {"id": h2, "name": "Home Partner", "bats_left": False}]}, owner)
check("the home side is named", status, 200)
if status != 200: print("   ->", body)
status, body = call("POST", f"/cricket/matches/{MID}/xi", {"side": "away", "captain_id": a1, "players": [
    {"id": a1, "name": "Away One", "bats_left": False},
    {"id": a2, "name": "Away Two", "bats_left": False}]}, owner)
check("and the away side", status, 200)
if status != 200: print("   ->", body)

# The terms first: nobody tosses until both sides have agreed them. Against
# an opposition with no club on the app, the scorer agrees for both.
call("POST", f"/cricket/matches/{MID}/claim-scorer", {"device_id": "smoke-season"}, owner)
TERMS = {"overs_limit": 1, "overs_per_bowler": 1, "ground": "open", "ball": "white",
         "powerplay_overs": 0, "fielders_outside_powerplay": 2,
         "fielders_outside_normal": 5, "target_overs_per_hour": 0}
check("terms proposed", call("POST", f"/cricket/matches/{MID}/propose",
      {"conditions": TERMS, "by": "home", "by_name": "Home Opener"}, owner)[0], 200)
check("and agreed", call("POST", f"/cricket/matches/{MID}/agree",
      {"side": "away", "captain_name": "Away One"}, owner)[0], 200)

# Creating the match and naming the sides are events in its log already; the
# scorer's numbering carries on from them, or the server takes a repeat.
seq = call("GET", f"/cricket/matches/{MID}", token=owner)[1]["last_seq"]
def score(*kinds):
    global seq
    events = []
    for k in kinds:
        seq += 1
        events.append({"client_event_id": str(uuid.uuid4()), "seq": seq, "kind": k})
    return call("POST", f"/cricket/matches/{MID}/events", {"device_id": "smoke-season", "events": events}, owner)

def ball(runs, six=False):
    return {"type": "delivery_recorded", "runs": runs, "is_legal": True,
            "is_boundary_four": False, "is_boundary_six": six}

plan = [
    {"type": "toss_recorded", "winner": "home", "decision": "bat"},
    {"type": "innings_started", "innings_index": 0, "batting": "home",
     "striker_id": h1, "non_striker_id": h2, "bowler_id": a1},
    *[ball(2) for _ in range(6)],
    {"type": "innings_started", "innings_index": 1, "batting": "away",
     "striker_id": a1, "non_striker_id": a2, "bowler_id": h1},
    ball(6, six=True), ball(6, six=True), ball(1)]
status = 200
for i, k in enumerate(plan):
    status, body = score(k)
    if status != 200:
        print(f"   -> event {i} {k['type']}: {body}")
        st = call("GET", f"/cricket/matches/{MID}", token=owner)[1]["state"]
        print("   state:", st["status"], st.get("overs_limit"), st.get("conditions", {}).get("overs_limit"),
              [(x["runs"], x["wickets"], x["legal_balls"], x["complete"], x.get("overs_available"), x.get("wickets_allowed")) for x in st["innings"]])
        break
check("a one-over match is scored", status, 200)
_, m = call("GET", f"/cricket/matches/{MID}", token=owner)
check("and finished", m["state"]["status"] in ("complete", "published"), True)

opener_tok = people["Home Opener"][0]
_, game = call("GET", f"/me/game?season={YEAR}&club_id={cid}", token=opener_tok)
check("the opener's season has the match", game["totals"]["matches"], 1)
check("and no award yet", game["totals"]["player_of_match"], 0)

status, _ = score({"type": "player_of_the_match", "player_id": h1})
check("player of the match is given after the last ball", status, 200)
_, game = call("GET", f"/me/game?season={YEAR}&club_id={cid}", token=opener_tok)
check("and their season now counts it", game["totals"]["player_of_match"], 1)

# --- Closing the season ------------------------------------------------------
status, _ = call("GET", f"/clubs/{cid}/seasons/{YEAR + 1}/close", token=owner)
check("next season cannot be previewed for closing", status, 400)
status, _ = call("POST", f"/clubs/{cid}/seasons/{YEAR + 1}/close", token=owner)
check("nor closed", status, 400)

status, preview = call("GET", f"/clubs/{cid}/seasons/{YEAR}/close", token=owner)
check("this season's close preview", status, 200)
mail_on = preview.get("email_on")
check("says whether this server can send mail", isinstance(mail_on, bool), True)
if not mail_on:
    check("and promises no emails when it cannot", preview["will_email"], 0)
status, closed = call("POST", f"/clubs/{cid}/seasons/{YEAR}/close", token=owner)
check("closing it", status, 200)
check("reports what the preview did", closed["queued"], preview["will_email"])
check("and the same about mail", closed["email_on"], mail_on)
check("closing twice is refused", call("POST", f"/clubs/{cid}/seasons/{YEAR}/close", token=owner)[0], 409)

# --- Who can make a treasurer ------------------------------------------------
sec_tok, sec_id = people["Second Secretary"]
status, body = call("PUT", f"/clubs/{cid}/members/{sec_id}/treasurer", {"is_treasurer": True}, sec_tok)
check("a secretary cannot make themselves treasurer", status, 403)
check("and is told why", (body or {}).get("code"), "treasurer_self_appointment")
check("so still cannot open the books", call("GET", f"/clubs/{cid}/accounts", token=sec_tok)[0], 403)
check("a secretary can make somebody else treasurer",
      call("PUT", f"/clubs/{cid}/members/{h2}/treasurer", {"is_treasurer": True}, sec_tok)[0], 200)
check("the owner can make the secretary treasurer",
      call("PUT", f"/clubs/{cid}/members/{sec_id}/treasurer", {"is_treasurer": True}, owner)[0], 200)
check("who can then step down themselves",
      call("PUT", f"/clubs/{cid}/members/{sec_id}/treasurer", {"is_treasurer": False}, sec_tok)[0], 200)

print()
if failures:
    print(f"{len(failures)} failed:")
    for f in failures:
        print("  -", f)
    raise SystemExit(1)
print("all good")
PY

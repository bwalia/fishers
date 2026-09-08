#!/usr/bin/env bash
# Starting a match between two Fishers clubs, from both sides.
#
# The visiting captain is the one this checks. Every step here was once
# impossible for them: they could not see the fixture, could not open the
# match, were never told terms had been proposed, and could not agree them.
#
#   ./scripts/smoke-match-setup.sh [http://127.0.0.1:7312]
set -euo pipefail

BASE="${1:-http://127.0.0.1:7312}/api/v1"
export SMOKE_BASE="$BASE"

curl -sf "${1:-http://127.0.0.1:7312}/health" >/dev/null || {
  echo "no API at ${1:-http://127.0.0.1:7312} — start one first" >&2
  exit 1
}

python3 - <<'PY'
import json, os, time, uuid, urllib.error, urllib.request

BASE = os.environ["SMOKE_BASE"]
STAMP = int(time.time())
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


home_tok, home, _ = club("hm", "Smoke Home CC", ["Home Captain"])
away_tok, away, away_people = club("aw", "Smoke Away CC", ["Away Captain", "Away Player"])
away_cap = away_people["Away Captain"]
away_plain = away_people["Away Player"]

_, event = call("POST", "/events", {
    "club_id": home["id"], "sport": "cricket", "event_subtype": "league_match",
    "title": f"Smoke fixture {STAMP}",
    "start_at": "2026-09-08T13:00:00Z", "end_at": "2026-09-08T18:00:00Z"}, home_tok)
status, match = call("POST", f"/events/{event['id']}/cricket-match", {
    "overs_limit": 20, "home_name": home["name"], "away_name": away["name"],
    "opponent_club_id": away["id"]}, home_tok)
check("match created", status, 200)
mid = match["id"]

# The visitors have to be able to find and open their own fixture.
# `/events` pages now: the fixture is searched for by name rather than hoped
# to be on page one of a database with a season in it.
_, theirs = call("GET", f"/events?q=Smoke+fixture+{STAMP}", token=away_cap)
check("the away club sees the fixture",
      any(e["id"] == event["id"] for e in theirs["items"]), True)
check("and the page says how many there are", theirs["total"] >= 1, True)
check("the away captain can open the match",
      call("GET", f"/cricket/matches/{mid}", token=away_cap)[0], 200)
check("and its scorecard", call("GET", f"/cricket/matches/{mid}/scorecard", token=away_cap)[0], 200)
check("and reach it through the fixture",
      call("GET", f"/events/{event['id']}/cricket-match", token=away_cap)[0], 200)

# Who may speak for whom. The app shows forms off this, so it has to agree
# with what the endpoints will actually accept.
_, seen_by_scorer = call("GET", f"/cricket/matches/{mid}", token=home_tok)
check("the scorer speaks for both sides", seen_by_scorer["my_sides"], ["home", "away"])
_, seen_by_cap = call("GET", f"/cricket/matches/{mid}", token=away_cap)
check("a captain speaks for their own", seen_by_cap["my_sides"], ["away"])
check("a plain player for neither",
      call("GET", f"/cricket/matches/{mid}", token=away_plain)[1]["my_sides"], [])
# Distinct from my_sides: the scorer may act for both but plays for one, and
# the proposal defaults off this. Proposing counts as agreeing, so defaulting
# to the opposition silently signs on their behalf and leaves them nothing to
# accept — which is exactly what happened.
check("the scorer plays for the home side", seen_by_scorer["my_club_side"], "home")
check("their captain plays for the away side", seen_by_cap["my_club_side"], "away")

# Terms proposed by the home side, through the door a captain can also use.
call("POST", f"/cricket/matches/{mid}/claim-scorer", {"device_id": "smoke"}, home_tok)
CONDITIONS = {"overs_limit": 20, "overs_per_bowler": 4, "ground": "open",
              "ball": "white", "powerplay_overs": 6, "fielders_outside_powerplay": 2,
              "fielders_outside_normal": 5, "target_overs_per_hour": 0}
status, proposed = call("POST", f"/cricket/matches/{mid}/propose", {
    "conditions": CONDITIONS, "by": "home", "by_name": "Home Captain"}, home_tok)
check("terms proposed", status, 200)
# Nothing emits `match_prepared` through this door, so the names have to be
# seeded server-side or a replay loses them to "Home" and "Away".
check("the team names survive the log",
      (proposed["state"]["home_name"], proposed["state"]["away_name"]),
      (home["name"], away["name"]))
check("a captain cannot propose for the other side",
      call("POST", f"/cricket/matches/{mid}/propose",
           {"conditions": CONDITIONS, "by": "home", "by_name": "x"}, away_cap)[0], 403)
# Nor can the scorer, even though they may act for both. Proposing counts as
# agreeing, so proposing "on behalf of" the opposition signed for a club that
# had not seen the terms and left them nothing to accept.
check("nor can the scorer propose for the opposition",
      call("POST", f"/cricket/matches/{mid}/propose",
           {"conditions": CONDITIONS, "by": "away", "by_name": "Away Captain"}, home_tok)[0],
      403)
check("so the side that proposed is the only one signed",
      (proposed["state"]["agreed_home"], proposed["state"]["agreed_away"]),
      ("Home Captain", None))

# Somebody has to actually be told.
_, feed = call("GET", "/notifications", token=away_cap)
check("the away captain is notified", feed["unread"], 1)
check("in words, with the match attached",
      (feed["items"][0]["type"], feed["items"][0]["payload"]["match_id"]),
      ("match_terms_proposed", mid))
check("the proposer is not notified",
      call("GET", "/notifications", token=home_tok)[1]["unread"], 0)
check("nor is a player who cannot agree",
      call("GET", "/notifications", token=away_plain)[1]["unread"], 0)

# And be able to act on it, from their own phone, without the book.
status, after = call("POST", f"/cricket/matches/{mid}/agree",
                     {"side": "away", "captain_name": "Away Captain"}, away_cap)
check("the away captain agrees without the book", status, 200)
check("both sides are now agreed",
      bool(after["state"]["agreed_home"]) and bool(after["state"]["agreed_away"]), True)
check("the away captain cannot agree for the home side",
      call("POST", f"/cricket/matches/{mid}/agree",
           {"side": "home", "captain_name": "Home Captain"}, away_cap)[0], 403)
check("an empty name is refused",
      call("POST", f"/cricket/matches/{mid}/agree",
           {"side": "home", "captain_name": "  "}, home_tok)[0], 400)
check("a plain player cannot agree for their side",
      call("POST", f"/cricket/matches/{mid}/agree",
           {"side": "away", "captain_name": "Away Player"}, away_plain)[0], 403)

# Proposing for your own side leaves the opposition something to accept.
check("proposing signs only the proposer",
      (proposed["state"]["agreed_home"], proposed["state"]["agreed_away"]),
      ("Home Captain", None))

# Naming a side is the captain's own job, book or no book.
_, squad = call("GET", f"/cricket/matches/{mid}/squad", token=away_cap)
check("the away captain may pick their own side", squad["away"]["can_pick"], True)
check("and not the other one", squad["home"]["can_pick"], False)
_, cur = call("GET", f"/cricket/matches/{mid}", token=home_tok)
call("POST", f"/cricket/matches/{mid}/events", {"events": [{
    "client_event_id": str(uuid.uuid4()), "seq": cur["last_seq"] + 1,
    "kind": {"type": "toss_recorded", "winner": "home", "decision": "bat"}}]}, home_tok)
picks = squad["away"]["players"][:2]
# The home side goes first, and naming it has to put the ball in the other
# side's court — nothing else tells them, and the match cannot start until both
# are in.
call("POST", "/notifications/read", {}, away_cap)
_, home_squad = call("GET", f"/cricket/matches/{mid}/squad", token=home_tok)
home_picks = home_squad["home"]["players"][:2]
check("the home side is named",
      call("POST", f"/cricket/matches/{mid}/xi", {
          "side": "home",
          "players": [{"id": p["id"], "name": p["name"], "bats_left": False} for p in home_picks],
          "captain_id": home_picks[0]["id"], "keeper_id": None}, home_tok)[0], 200)
_, waiting_feed = call("GET", "/notifications", token=away_cap)
check("the away captain is asked to pick",
      waiting_feed["items"][0]["type"] if waiting_feed["items"] else None,
      "match_pick_your_xi")

check("the away captain confirms their XI without the book",
      call("POST", f"/cricket/matches/{mid}/xi", {
          "side": "away",
          "players": [{"id": p["id"], "name": p["name"], "bats_left": False} for p in picks],
          "captain_id": picks[0]["id"], "keeper_id": None}, away_cap)[0], 200)
_, done = call("GET", f"/cricket/matches/{mid}", token=home_tok)
check("both named, so the match is ready", done["state"]["status"], "ready")

# Marking read is what clears the bell — one at a time, then the rest.
# Re-read: the feed captured earlier has been marked read since.
_, latest = call("GET", "/notifications", token=away_cap)
before = latest["unread"]
unread_id = next(n["id"] for n in latest["items"] if n["read_at"] is None)
call("POST", "/notifications/read", {"id": unread_id}, away_cap)
check("reading one drops the count",
      call("GET", "/notifications", token=away_cap)[1]["unread"], before - 1)
call("POST", "/notifications/read", {}, away_cap)
check("and reading all clears it",
      call("GET", "/notifications", token=away_cap)[1]["unread"], 0)

print()
if failures:
    print(f"{len(failures)} failed:")
    for f in failures:
        print("  -", f)
    raise SystemExit(1)
print("all good")
PY

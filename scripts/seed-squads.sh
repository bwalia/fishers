#!/usr/bin/env bash
# Fill out the two demo clubs with a squad each, so there is something to pick
# from on the team-sheet screen.
#
# Players are created through the real signup endpoint, so they are proper
# accounts (password123) that can sign in and be picked, not rows poked into
# the database.
#
#   ./scripts/seed-squads.sh [http://127.0.0.1:7312]
set -euo pipefail

BASE="${1:-http://127.0.0.1:7312}"
export SEED_BASE="$BASE/api/v1"

curl -sf "$BASE/health" >/dev/null || {
  echo "no API at $BASE — ./scripts/start.sh first" >&2
  exit 1
}

python3 - <<'PY'
import json, os, subprocess, urllib.error, urllib.request

BASE = os.environ["SEED_BASE"]

# Batting order-ish: openers, top order, all-rounders, keeper, then the bowlers.
LORDS = [
    ("Marcus Hall", "bat"), ("Priya Nair", "bat"), ("Callum Reid", "bat"),
    ("Ibrahim Sesay", "all"), ("Nathan Brooks", "all"), ("Yusuf Ali", "wk"),
    ("Elliot Payne", "bowl"),
]
NEW_CLUB = [
    ("Harpreet Gill", "bat"), ("Danny Osei", "bat"), ("Faisal Mahmood", "bat"),
    ("Owen Fletcher", "bat"), ("Arjun Menon", "all"), ("Liam Doherty", "all"),
    ("Zubair Khan", "all"), ("Scott McLean", "wk"), ("Rehan Aziz", "bowl"),
    ("Josh Whitfield", "bowl"), ("Kwame Boateng", "bowl"), ("Vikas Rana", "bowl"),
    ("Aaron Pike", "bowl"),
]

ROLE_TEXT = {"bat": "Batter", "bowl": "Bowler", "all": "All-rounder", "wk": "Wicketkeeper"}


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


def slug(name):
    return name.lower().replace(" ", ".")


def ensure_player(name, position):
    """Sign them up, or reuse the account if it is already there."""
    email = f"{slug(name)}@fishers.test"
    status, body = call("POST", "/auth/signup", {
        "name": name, "email": email, "password": "password123"})
    if status == 200:
        token = body["access_token"]
        # A position on the profile is what the selection board reads.
        call("PATCH", "/me", {"position_role": ROLE_TEXT[position],
                              "primary_sport": "cricket"}, token)
    return email


def psql(sql):
    return subprocess.run(
        ["docker", "exec", "-i", "fishers-postgres", "psql", "-U", "fishers",
         "-d", "fishers", "-tAc", sql],
        capture_output=True, text=True, check=True).stdout.strip()


def club_id(name, owner_email=None):
    """The oldest club with this name, optionally pinned to an owner.

    A local database collects test clubs with the same name; the owner
    narrows it when you know theirs. Set NEW_CLUB_OWNER to pin the away side
    rather than putting somebody's address in the repository.
    """
    where = f"c.name = '{name}'"
    if owner_email:
        where += f" AND u.email = '{owner_email}'"
    return psql(
        f"SELECT c.id FROM clubs c JOIN users u ON u.id = c.owner_id "
        f"WHERE {where} ORDER BY c.created_at LIMIT 1"
    )


def add_by_sql(club, email, role="member"):
    """For a club whose secretary password we do not hold.

    Exactly what `add_member` writes, including reactivating anyone who had
    been removed.
    """
    psql(
        f"INSERT INTO club_members (club_id, user_id, role, status) "
        f"SELECT '{club}', id, '{role}', 'active' FROM users WHERE email = '{email}' "
        f"ON CONFLICT (club_id, user_id) DO UPDATE SET status = 'active'"
    )


def squad_size(club):
    return int(psql(
        f"SELECT count(*) FROM club_members WHERE club_id = '{club}' AND status = 'active'"))


lords = club_id("London Lords CC", "demo@fishers.test")
newclub = club_id("New Club", os.environ.get("NEW_CLUB_OWNER"))
if not lords or not newclub:
    raise SystemExit("could not find both demo clubs — is this the right database?")

# London Lords has a secretary whose password the seed script sets, so it goes
# through the API like a real secretary would.
_, auth = call("POST", "/auth/login", {
    "identifier": "demo@fishers.test", "password": "password123"})
lords_token = auth["access_token"] if isinstance(auth, dict) else None

print(f"London Lords CC  {lords}")
for name, position in LORDS:
    email = ensure_player(name, position)
    if lords_token:
        status, _ = call("POST", f"/clubs/{lords}/members", {"identifier": email}, lords_token)
        if status != 200:
            add_by_sql(lords, email)
    else:
        add_by_sql(lords, email)
    print(f"  + {name} ({ROLE_TEXT[position]})")

print(f"\nNew Club         {newclub}")
for name, position in NEW_CLUB:
    email = ensure_player(name, position)
    add_by_sql(newclub, email)
    print(f"  + {name} ({ROLE_TEXT[position]})")

# Each side needs a captain, or there is nobody to name against the terms.
for club, email in ((lords, "player1@fishers.test"),
                    (newclub, "harpreet.gill@fishers.test")):
    psql(f"UPDATE club_members SET role = 'team_captain' "
         f"WHERE club_id = '{club}' "
         f"AND user_id = (SELECT id FROM users WHERE email = '{email}')")

print(f"\nLondon Lords CC: {squad_size(lords)} players")
print(f"New Club:        {squad_size(newclub)} players")
print("\nEveryone signs in with their own address and password123.")
PY

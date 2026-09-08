#!/usr/bin/env bash
# Club creation, roster and invites against a running API.
#
# Every step here has already been a bug: a member with no email address broke
# the whole roster, `identifier` on its own was rejected as a malformed body,
# and somebody removed from the club kept coming back because the roster query
# never filtered on status.
#
#   ./scripts/smoke-clubs.sh [http://127.0.0.1:7312]
set -euo pipefail

BASE="${1:-http://127.0.0.1:7312}/api/v1"
export SMOKE_BASE="$BASE"

curl -sf "${1:-http://127.0.0.1:7312}/health" >/dev/null || {
  echo "no API at ${1:-http://127.0.0.1:7312} — start one first" >&2
  exit 1
}

python3 - <<'PY'
import json, os, time, urllib.error, urllib.request

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
        return e.code, (json.loads(raw) if raw else None)


def check(label, got, want):
    ok = got == want
    print(f"{'ok  ' if ok else 'FAIL'} {label}: {got!r}")
    if not ok:
        failures.append(f"{label}: got {got!r}, wanted {want!r}")


# A brand new account creates a club and is its secretary.
_, sec = call("POST", "/auth/signup", {
    "name": "Smoke Secretary", "email": f"smoke{STAMP}@t.test", "password": "password123"})
tok = sec["access_token"]
status, club = call("POST", "/clubs", {
    "name": f"Smoke CC {STAMP}", "sport_types": ["cricket"], "visibility": "invite_only"}, tok)
check("club created", status, 200)
cid = club["id"]

_, role = call("GET", f"/clubs/{cid}/my-role", token=tok)
check("creator is the secretary", role["is_secretary"], True)

_, mine = call("GET", "/clubs", token=tok)
check("the list says what you are", next(c["role"] for c in mine if c["id"] == cid), "club_admin")

# Somebody who registered with a mobile number and has no address at all.
phone = f"0770099{STAMP}"
call("POST", "/auth/signup", {"name": "Phone Player", "phone": phone, "password": "password123"})
status, _ = call("POST", f"/clubs/{cid}/members", {"identifier": phone, "role": "team_captain"}, tok)
check("added by mobile number", status, 200)

status, roster = call("GET", f"/clubs/{cid}/members", token=tok)
check("roster renders a member with no email", status, 200)
check("both on the roster", len(roster), 2)
check("their email is null, not missing",
      [m["email"] for m in roster if m["name"] == "Phone Player"], [None])

# Nobody by that name, and nothing given at all.
status, body = call("POST", f"/clubs/{cid}/members", {"identifier": "ghost@nowhere.test"}, tok)
check("unknown identifier is a 404", status, 404)
status, _ = call("POST", f"/clubs/{cid}/members", {"role": "member"}, tok)
check("an empty body is a 400, not a 422", status, 400)

# Removal sticks, and re-adding brings them back.
target = next(m["user_id"] for m in roster if m["name"] == "Phone Player")
call("DELETE", f"/clubs/{cid}/members/{target}", token=tok)
_, roster = call("GET", f"/clubs/{cid}/members", token=tok)
check("a removed member is gone from the roster", len(roster), 1)
status, _ = call("POST", f"/clubs/{cid}/members", {"identifier": phone}, tok)
check("re-adding them works", status, 200)
_, roster = call("GET", f"/clubs/{cid}/members", token=tok)
check("and they are back", len(roster), 2)

# A club must never lose its last secretary.
me = next(m["user_id"] for m in roster if m["role"] == "club_admin")
status, _ = call("PATCH", f"/clubs/{cid}/members/{me}", {"role": "member"}, tok)
check("the last secretary cannot stand down", status, 409)
status, _ = call("DELETE", f"/clubs/{cid}/members/{me}", token=tok)
check("nor be removed", status, 409)

# An invite joins somebody with no account, once.
_, invite = call("POST", "/invites", {
    "target_type": "club", "target_id": cid, "invited_email": "stranger@nowhere.test"}, tok)
_, newbie = call("POST", "/auth/signup", {
    "name": "Newbie", "email": f"nb{STAMP}@t.test", "password": "password123"})
status, _ = call("POST", f"/invites/{invite['token']}/accept", token=newbie["access_token"])
check("invite accepted", status, 200)
status, _ = call("POST", f"/invites/{invite['token']}/accept", token=newbie["access_token"])
check("and cannot be reused", status, 404)
_, theirs = call("GET", "/clubs", token=newbie["access_token"])
check("they are in the club", [c["id"] for c in theirs], [cid])

# A plain member may read the roster but not change it.
status, _ = call("POST", f"/clubs/{cid}/members",
                 {"identifier": f"smoke{STAMP}@t.test"}, newbie["access_token"])
check("a member cannot add people", status, 403)

# --- Opposition search -----------------------------------------------------
# Invite-only means undiscoverable; teams resolve by QR so they must resolve by
# name too; and a prefix match is what you meant.
_, pub = call("POST", "/clubs", {
    "name": f"Zulu Public CC {STAMP}", "sport_types": ["cricket"], "visibility": "public"}, tok)
call("POST", "/clubs", {
    "name": f"Zulu Private CC {STAMP}", "sport_types": ["cricket"], "visibility": "invite_only"}, tok)
call("POST", f"/clubs/{pub['id']}/teams", {"name": f"Zulu Colts {STAMP}", "sport": "cricket"}, tok)
call("POST", "/clubs", {
    "name": f"Old Zephyr CC {STAMP}", "sport_types": ["cricket"], "visibility": "public"}, tok)
call("POST", "/clubs", {
    "name": f"Zephyr Town CC {STAMP}", "sport_types": ["cricket"], "visibility": "public"}, tok)

import urllib.parse
def search(term, token):
    status, rows = call("GET", "/opponents/search?q=" + urllib.parse.quote(term), token=token)
    return [r["name"] for r in rows] if status == 200 else [f"HTTP {status}"]

# The stamp is in every name this run made and nothing else, so it isolates
# them from whatever else the database holds.
outsider = newbie["access_token"]
found = search(str(STAMP), outsider)
check("an invite-only club is not discoverable",
      any("Private" in n for n in found), False)
check("a public one is", any("Public" in n for n in found), True)
check("its teams are too", any("Colts" in n for n in found), True)
check("but the owner still finds their own private club",
      any("Private" in n for n in search(str(STAMP), tok)), True)
zephyrs = [n for n in search("Zephyr", outsider) if str(STAMP) in n]
check("a prefix match ranks first", zephyrs[0].startswith("Zephyr"), True)
check("one letter is refused",
      call("GET", "/opponents/search?q=a", token=tok)[0], 400)

print()
if failures:
    print(f"{len(failures)} failed:")
    for f in failures:
        print("  -", f)
    raise SystemExit(1)
print("all good")
PY

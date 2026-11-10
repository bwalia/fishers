#!/usr/bin/env bash
# The club's open link, against a running API.
#
# The bug this exists for: a secretary shared one invite link with the whole
# squad, the first player through it used it up, and everybody else was told
# it had already been used. An open link is never used up, and stops letting
# people in only when the club turns it off.
#
#   ./scripts/smoke-open-link.sh [http://127.0.0.1:7312]
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


def signup(name):
    _, u = call("POST", "/auth/signup", {
        "name": name, "email": f"{name.lower().replace(' ', '')}{STAMP}@t.test",
        "password": "password123"})
    return u["access_token"]


sec = signup("Open Secretary")
_, club = call("POST", "/clubs", {
    "name": f"Open Link CC {STAMP}", "sport_types": ["cricket"], "visibility": "invite_only"}, sec)
cid = club["id"]

check("no link until one is made", call("GET", f"/clubs/{cid}/join-link", token=sec), (200, None))

status, link = call("POST", f"/clubs/{cid}/join-link", {}, sec)
check("link made", status, 200)
check("it is open", link["open"], True)
token = link["token"]
_, again = call("POST", f"/clubs/{cid}/join-link", {}, sec)
check("asking again hands back the same link", again["token"], token)

status, seen = call("GET", f"/invites/{token}")
check("anyone can see what the link is to", status, 200)
check("it names the club", seen["club_name"], club["name"])
check("and is usable", seen["usable"], True)

players = [signup(f"Open Player {i}") for i in range(3)]
for i, p in enumerate(players):
    check(f"player {i + 1} joins through the one link",
          call("POST", f"/invites/{token}/accept", token=p)[0], 200)
check("following it again when already in is fine",
      call("POST", f"/invites/{token}/accept", token=players[0])[0], 200)
_, members = call("GET", f"/clubs/{cid}/members", token=sec)
check("all three are in the club", len(members), 4)
_, link = call("GET", f"/clubs/{cid}/join-link", token=sec)
check("the link counts each of them once", link["uses"], 3)
check("the link is still live", link["status"], "pending")

check("a player cannot see the link settings",
      call("GET", f"/clubs/{cid}/join-link", token=players[0])[0], 403)
check("nor make one", call("POST", f"/clubs/{cid}/join-link", {}, players[0])[0], 403)

_, fresh = call("POST", f"/clubs/{cid}/join-link", {"fresh": True}, sec)
check("a new link is a new token", fresh["token"] != token, True)
late = signup("Late Player")
check("the old link no longer lets anyone in",
      call("POST", f"/invites/{token}/accept", token=late)[0], 404)
check("and says so before sign-in", call("GET", f"/invites/{token}")[1]["usable"], False)
check("the new one does", call("POST", f"/invites/{fresh['token']}/accept", token=late)[0], 200)

check("turning it off", call("DELETE", f"/clubs/{cid}/join-link", token=sec)[0], 204)
check("leaves no link", call("GET", f"/clubs/{cid}/join-link", token=sec)[1], None)
check("and lets nobody else in",
      call("POST", f"/invites/{fresh['token']}/accept", token=signup("Too Late"))[0], 404)
_, members = call("GET", f"/clubs/{cid}/members", token=sec)
check("those already in stay in", len(members), 5)

# A one-use invite still works exactly as before.
_, one = call("POST", "/invites", {
    "target_type": "club", "target_id": cid, "invited_email": "one@nowhere.test"}, sec)
check("a one-use invite is not open", one["open"], False)
check("first use works", call("POST", f"/invites/{one['token']}/accept", token=signup("One Use"))[0], 200)
check("second use does not",
      call("POST", f"/invites/{one['token']}/accept", token=signup("Second Use"))[0], 404)

check("an unknown link is a 404", call("GET", "/invites/deadbeef")[0], 404)

# --- Somebody the club removed stays removed --------------------------------
# The link is still in their WhatsApp. Following it must not undo the
# secretary's decision, nor hand back a role or the club's books.
_, gone = call("POST", "/auth/signup", {
    "name": "Removed Captain", "email": f"removedcaptain{STAMP}@t.test",
    "password": "password123"})
gone_tok, gone_id = gone["access_token"], gone["user"]["id"]
_, live = call("POST", f"/clubs/{cid}/join-link", {}, sec)
check("the removed-to-be joins through the link",
      call("POST", f"/invites/{live['token']}/accept", token=gone_tok)[0], 200)
check("is made a captain",
      call("PATCH", f"/clubs/{cid}/members/{gone_id}", {"role": "team_captain"}, sec)[0], 200)
check("and the treasurer",
      call("PUT", f"/clubs/{cid}/members/{gone_id}/treasurer", {"is_treasurer": True}, sec)[0], 200)
check("so can open the books", call("GET", f"/clubs/{cid}/my-role", token=gone_tok)[1]["can_open_accounts"], True)

uses_before = call("GET", f"/clubs/{cid}/join-link", token=sec)[1]["uses"]
check("the secretary removes them", call("DELETE", f"/clubs/{cid}/members/{gone_id}", token=sec)[0], 200)
status, body = call("POST", f"/invites/{live['token']}/accept", token=gone_tok)
check("the open link will not let them back in", status, 403)
check("and says why", (body or {}).get("code"), "removed_from_club")
_, members = call("GET", f"/clubs/{cid}/members", token=sec)
check("they are not back in the club", gone_id in [m["user_id"] for m in members], False)
check("nor in the books", call("GET", f"/clubs/{cid}/accounts", token=gone_tok)[0] in (403, 404), True)
_, live_after = call("GET", f"/clubs/{cid}/join-link", token=sec)
check("and the refusal counted nobody", live_after["uses"], uses_before)

_, back = call("POST", "/invites", {
    "target_type": "club", "target_id": cid, "invited_user_id": gone_id}, sec)
check("a secretary's own invitation still readmits them",
      call("POST", f"/invites/{back['token']}/accept", token=gone_tok)[0], 200)
_, role = call("GET", f"/clubs/{cid}/my-role", token=gone_tok)
check("as a member, not the captain they were", role["role"], "member")
check("and not the treasurer", role["is_treasurer"], False)
check("so not into the books", role["can_open_accounts"], False)
check("once readmitted, the open link is fine again",
      call("POST", f"/invites/{live['token']}/accept", token=gone_tok)[0], 200)

print()
if failures:
    print(f"{len(failures)} failed:")
    for f in failures:
        print("  -", f)
    raise SystemExit(1)
print("all good")
PY

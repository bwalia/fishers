#!/usr/bin/env bash
# Ticketed club events: the dinner, the quiz, presentation night.
#
# Two holes this pins shut. The columns were on `events` but nothing wrote
# them, so a ticketed event could not be created at all — the booking screen
# was unreachable. And `guests_allowed` was invisible to every client, so a
# form offering a guest field got "this event allows 0 guests per member" from
# a server nobody could ask first.
#
#   ./scripts/smoke-tickets.sh [http://127.0.0.1:7312]
set -euo pipefail

BASE="${1:-http://127.0.0.1:7312}/api/v1"
export SMOKE_BASE="$BASE"

curl -sf "${1:-http://127.0.0.1:7312}/health" >/dev/null || {
  echo "no API at ${1:-http://127.0.0.1:7312} — start one first" >&2
  exit 1
}

python3 - <<'PY'
import json, os, time, urllib.request, urllib.error

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
            return e.code, raw.decode()[:200]


def check(label, got, want):
    ok = got == want
    print(f"{'ok  ' if ok else 'FAIL'} {label}: {got!r}")
    if not ok:
        failures.append(f"{label}: got {got!r}, wanted {want!r}")


_, sec = call("POST", "/auth/signup", {
    "name": "Ticket Secretary", "email": f"tk{STAMP}@t.test", "password": "password123"})
tok = sec["access_token"]
_, club = call("POST", "/clubs", {"name": f"Ticket CC {STAMP}", "sport_types": ["cricket"]}, tok)

# A member who will bring guests.
_, guest_bringer = call("POST", "/auth/signup", {
    "name": "Brings People", "email": f"tkb{STAMP}@t.test", "password": "password123"})
call("POST", f"/clubs/{club['id']}/members",
     {"identifier": f"tkb{STAMP}@t.test", "role": "member"}, tok)
member = guest_bringer["access_token"]

# --- A ticketed event can be created at all -------------------------------

status, event = call("POST", "/events", {
    "club_id": club["id"], "sport": "cricket", "event_subtype": "social",
    "title": f"Presentation Night {STAMP}",
    "start_at": "2026-10-24T19:00:00Z", "end_at": "2026-10-24T23:00:00Z",
    "ticket_price_cents": 3500, "ticket_capacity": 4, "guests_allowed": 2}, tok)
check("a ticketed event can be created", status, 200)
check("the price is kept", event.get("ticket_price_cents"), 3500)
check("so is the capacity", event.get("ticket_capacity"), 4)
check("and the guest limit", event.get("guests_allowed"), 2)

EID = event["id"]

# --- The limit reaches the screen that has to respect it -------------------

_, booking = call("GET", f"/events/{EID}/tickets", token=member)
check("the booking screen is told the guest limit",
      booking["summary"]["guests_allowed"], 2)
check("and what a place costs", booking["summary"]["ticket_price_cents"], 3500)

# --- Booking, and the money -----------------------------------------------

status, ticket = call("POST", f"/events/{EID}/tickets",
                      {"guests": 2, "guest_names": "Two friends"}, member)
check("a member books themselves and two guests", status, 200)
check("charged for three places", ticket.get("amount_cents"), 3 * 3500)

status, _ = call("POST", f"/events/{EID}/tickets", {"guests": 3}, member)
check("but not for more guests than allowed", status, 409)

_, booking = call("GET", f"/events/{EID}/tickets", token=tok)
check("the headcount counts guests, not bookings",
      booking["summary"]["headcount"], 3)
check("and the money is outstanding until paid",
      booking["summary"]["outstanding_cents"], 3 * 3500)

# --- Capacity is a headcount, not a booking count -------------------------

_, latecomer = call("POST", "/auth/signup", {
    "name": "Turned Away", "email": f"tkl{STAMP}@t.test", "password": "password123"})
call("POST", f"/clubs/{club['id']}/members",
     {"identifier": f"tkl{STAMP}@t.test", "role": "member"}, tok)
status, _ = call("POST", f"/events/{EID}/tickets", {"guests": 2},
                 latecomer["access_token"])
check("three more into a room for four is refused", status, 409)

status, _ = call("POST", f"/events/{EID}/tickets", {"guests": 0},
                 latecomer["access_token"])
check("but the last single place is free", status, 200)

# --- Cancelling gives the place back ---------------------------------------

# Paying opens a Stripe intent; the ticket only turns "paid" when the webhook
# lands. Anything that tells a member they have paid before then leaves the
# club chasing somebody who thinks they are square.
status, intent = call("POST", f"/tickets/{ticket['id']}/pay", None, member)
check("paying opens a payment intent", status, 200)
check("for the right amount", intent.get("amount_cents"), 3 * 3500)
check("and the ticket is still reserved until it clears",
      intent.get("ticket_status"), "reserved")

status, _ = call("POST", f"/tickets/{ticket['id']}/cancel", None, member)
check("and cancelled", status, 200)
_, booking = call("GET", f"/events/{EID}/tickets", token=tok)
check("which gives the three places back", booking["summary"]["headcount"], 1)

print()
if failures:
    print("FAILURES:")
    for f in failures:
        print(" -", f)
    raise SystemExit(1)
print("all good")
PY

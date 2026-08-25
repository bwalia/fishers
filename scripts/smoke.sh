#!/usr/bin/env bash
# Local smoke test for Fishers API (does not print tokens).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/backend"
set -a
# shellcheck disable=SC1091
source "$ROOT/.env"
set +a

cargo run -p fishers-api >/tmp/fishers-api.log 2>&1 &
API_PID=$!
cleanup() { kill "$API_PID" 2>/dev/null || true; }
trap cleanup EXIT

for _ in $(seq 1 40); do
  curl -sf http://localhost:8080/health >/dev/null && break
  sleep 0.5
done

curl -sf http://localhost:8080/health >/dev/null
echo "health: ok"

python3 - <<'PY'
import json, urllib.request

def post(path, body, token=None):
    req = urllib.request.Request(
        f"http://localhost:8080/api/v1{path}",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", **({"Authorization": f"Bearer {token}"} if token else {})},
        method="POST",
    )
    with urllib.request.urlopen(req) as r:
        return json.load(r)

auth = post("/auth/signup", {
    "name": "Admin Lords",
    "email": f"admin+{__import__('uuid').uuid4().hex[:8]}@londonlords.test",
    "password": "password123",
})
token = auth["access_token"]
club = post("/clubs", {
    "name": "London Lords CC",
    "sport_types": ["cricket"],
    "visibility": "invite_only",
    "description": "Weekly nets & summer matches",
}, token)
event = post("/events", {
    "club_id": club["id"],
    "sport": "cricket",
    "event_subtype": "nets",
    "title": "Wednesday Nets",
    "start_at": "2026-06-03T17:00:00Z",
    "end_at": "2026-06-03T19:00:00Z",
    "recurrence_rule": "FREQ=WEEKLY;BYDAY=WE",
    "capacity": 18,
    "fee_amount_cents": 600,
    "metadata": {"lane_count": 3, "bowling_machine": True},
}, token)
print(f"club: {club['name']}")
print(f"event: {event['title']} ({event['event_subtype']})")
print("smoke: ok")
PY

#!/usr/bin/env bash
# Start Postgres + Fishers API for Simulator/local client use.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

docker compose up -d
until docker exec fishers-postgres pg_isready -U fishers -d fishers >/dev/null 2>&1; do sleep 1; done

cd "$ROOT/backend"
set -a
# shellcheck disable=SC1091
source "$ROOT/.env"
set +a
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/backend/target}"
export DATABASE_URL="${DATABASE_URL:-postgres://fishers:fishers@localhost:5433/fishers}"
export API_HOST="${API_HOST:-0.0.0.0}"
export API_PORT="${API_PORT:-8080}"

echo "Building fishers-api…"
cargo build -p fishers-api
BIN="$CARGO_TARGET_DIR/debug/fishers-api"

if lsof -nP -iTCP:"$API_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Something already listens on :$API_PORT — leaving it alone."
  curl -sf "http://127.0.0.1:${API_PORT}/health" && echo && exit 0
  echo "Port busy but /health failed; stop the other process and retry." >&2
  exit 1
fi

echo "Fishers API → http://127.0.0.1:${API_PORT}  (Simulator uses this)"
exec "$BIN"

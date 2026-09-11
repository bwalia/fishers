#!/usr/bin/env bash
# The local stack, start to finish: Postgres, the Fishers API, the Next.js
# dashboard, and the iOS app in a Simulator — all pointed at this Mac's LAN
# address so a phone on the same Wi-Fi can join in.
#
#   ./scripts/start.sh              start everything
#   ./scripts/start.sh --no-ios     skip the Simulator (fastest)
#   ./scripts/start.sh --ios-only   rebuild and relaunch just the app
#   ./scripts/start.sh --status     what is running, and where
#   ./scripts/start.sh --logs api   follow a service's log
#   ./scripts/start.sh --stop       stop the API and dashboard
#   ./scripts/start.sh --stop --all also stop Postgres
#   ./scripts/start.sh --restart    stop, then start
#   ./scripts/start.sh --seed       start, then seed the demo account
#   ./scripts/start.sh --reset      wipe the database and start clean
#
# Services run detached with pidfiles under .dev/, so re-running is safe and
# Ctrl-C during an Xcode build does not take the API down with it.
#
# Ports are fixed (7311 web / 7312 API / 7313 Postgres) and overridable in .env.
# They deliberately do not drift onto free ports any more: a moving API port is
# what left the app, the dashboard and share links pointing at nothing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RUN_DIR="$ROOT/.dev/run"
LOG_DIR="$ROOT/.dev/logs"
DERIVED_DATA="$ROOT/.dev/DerivedData"
mkdir -p "$RUN_DIR" "$LOG_DIR"

PG_CONTAINER=fishers-postgres
API_DOCKER_CONTAINER=fishers-api-dev

# ── output ───────────────────────────────────────────────────────────────────

if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; N=$'\033[0m'
else
  B=""; DIM=""; RED=""; GRN=""; YEL=""; N=""
fi

step() { printf '\n%s==> %s%s\n' "$B" "$*" "$N"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '    %s! %s%s\n' "$YEL" "$*" "$N" >&2; }
die()  { printf '\n%sx %s%s\n' "$RED" "$*" "$N" >&2; exit 1; }
ok()   { printf '    %s✓%s %s\n' "$GRN" "$N" "$*"; }

# ── options ──────────────────────────────────────────────────────────────────

DO_STOP=0 DO_STATUS=0 DO_LOGS="" STOP_ALL=0
WANT_IOS=1 WANT_WEB=1 WANT_API=1
DO_SEED=0 DO_RESET=0 FORCE_RESTART=0
SIM_DEVICE="${FISHERS_SIM_DEVICE:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --stop)     DO_STOP=1 ;;
    --all)      STOP_ALL=1 ;;
    --restart)  FORCE_RESTART=1 ;;
    --status)   DO_STATUS=1 ;;
    --logs)     DO_LOGS="${2:-all}"; [ $# -gt 1 ] && shift ;;
    --no-ios)   WANT_IOS=0 ;;
    --no-web)   WANT_WEB=0 ;;
    --api-only) WANT_IOS=0; WANT_WEB=0 ;;
    --ios-only) WANT_API=0; WANT_WEB=0 ;;
    --seed)     DO_SEED=1 ;;
    --reset)    DO_RESET=1 ;;
    --device)   SIM_DEVICE="${2:?--device needs a Simulator name}"; shift ;;
    -h|--help)  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          die "unknown option: $1 (--help for the list)" ;;
  esac
  shift
done

# ── configuration ────────────────────────────────────────────────────────────

if [ ! -f .env ]; then
  cp .env.example .env
  info "Created .env from .env.example"
fi

# What the caller asked for on the command line, before .env is read. Sourcing
# .env overwrites everything it names, so `API_PORT=7399 ./scripts/start.sh`
# used to be quietly ignored — the environment has to win over the file for a
# one-off override to mean anything.
for var in POSTGRES_PORT API_PORT WEB_PORT RUST_LOG; do
  eval "_cli_${var}=\${${var}:-}"
done

set -a
# shellcheck disable=SC1091
source "$ROOT/.env"
set +a

for var in POSTGRES_PORT API_PORT WEB_PORT RUST_LOG; do
  eval "_was=\$_cli_${var}"
  [ -n "$_was" ] && eval "${var}=\$_was"
done
unset _was

POSTGRES_PORT="${POSTGRES_PORT:-7313}"
API_PORT="${API_PORT:-7312}"
WEB_PORT="${WEB_PORT:-7311}"

# The address a phone, a Simulator and a browser on another machine can all use.
# Taken from whichever interface holds the default route, so a Wi-Fi/Ethernet
# switch or a new DHCP lease is picked up on the next run rather than needing a
# source edit. VPN tunnels hold the default route without an IPv4 address of
# their own, hence the fallback sweep.
lan_ip() {
  local ip="" iface
  iface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
  [ -n "$iface" ] && ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
  if [ -z "$ip" ]; then
    for iface in $(networksetup -listallhardwareports 2>/dev/null \
                   | awk '/^Device: /{print $2}'); do
      ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
      [ -n "$ip" ] && break
    done
  fi
  echo "${ip:-127.0.0.1}"
}

LAN_IP="${FISHERS_LAN_IP:-$(lan_ip)}"
WEB_BASE="http://${LAN_IP}:${WEB_PORT}"
API_BASE="http://${LAN_IP}:${API_PORT}"
DATABASE_URL="postgres://fishers:fishers@localhost:${POSTGRES_PORT}/fishers"

# ── process plumbing ─────────────────────────────────────────────────────────

pidfile() { echo "$RUN_DIR/$1.pid"; }
logfile() { echo "$LOG_DIR/$1.log"; }

# The PID we started, if it is still the process we started. A pidfile whose
# process died — or whose number has been recycled by something unrelated — is
# treated as absent rather than trusted.
service_pid() {
  local f; f="$(pidfile "$1")"
  [ -f "$f" ] || return 1
  local pid; pid="$(cat "$f" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || { rm -f "$f"; return 1; }
  echo "$pid"
}

port_pid() { lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null | head -1; }
pid_cmd()  { ps -o command= -p "$1" 2>/dev/null | head -1; }
pid_cwd()  { lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1; }
pid_pgid() { ps -o pgid= -p "$1" 2>/dev/null | tr -d ' '; }

# Services are launched with job control on, so each gets a process group of its
# own and the whole tree can be signalled at once — `npx next dev` in particular
# is a wrapper whose child holds the socket, and killing only the wrapper is
# what used to leave the port occupied. The guard matters: without job control
# a background job shares this script's group, and the group kill would take the
# script down with it.
kill_tree() { # pid
  local pid=$1 pgid
  pgid="$(pid_pgid "$pid")"
  if [ -n "$pgid" ] && [ "$pgid" != "$(pid_pgid $$)" ]; then
    kill -- "-$pgid" 2>/dev/null || true
  fi
  kill "$pid" 2>/dev/null || true
}

# Launch a service detached, in its own process group, recording its PID.
spawn() { # service-name working-dir command...
  local name=$1 dir=$2; shift 2
  : > "$(logfile "$name")"
  ( cd "$dir"
    set -m
    nohup "$@" >>"$(logfile "$name")" 2>&1 &
    echo $! > "$(pidfile "$name")" )
}

# Free a port we are entitled to free. Ours means: the process we recorded, a
# fishers-api binary, or a Next dev server running out of this checkout. Anything
# else is somebody else's work and stops the script instead of being killed.
claim_port() { # port service-name human-name [soft]
  local port=$1 name=$2 human=$3 soft=${4:-} pid cmd cwd
  pid="$(port_pid "$port")" || true
  [ -n "$pid" ] || return 0

  local ours=0
  local known; known="$(service_pid "$name" 2>/dev/null || true)"
  [ -n "$known" ] && [ "$known" = "$pid" ] && ours=1
  cmd="$(pid_cmd "$pid")"
  case "$cmd" in
    *fishers-api*) ours=1 ;;
    *next*)        cwd="$(pid_cwd "$pid")"; [ -n "$cwd" ] && case "$cwd" in "$ROOT"*) ours=1 ;; esac ;;
  esac

  if [ "$ours" != 1 ]; then
    # --stop should report a stranger on the port, not refuse to finish.
    if [ -n "$soft" ]; then
      warn "port ${port} (${human}) is held by PID ${pid} — not ours, left alone: ${cmd:-unknown}"
      return 0
    fi
    die "port ${port} (${human}) is held by PID ${pid}: ${cmd:-unknown}
    That is not part of this project, so it has been left alone. Stop it, or
    set $( [ "$name" = web ] && echo WEB_PORT || echo API_PORT )= to a spare port in .env and re-run."
  fi

  info "stopping the previous ${human} (PID ${pid})"
  kill_tree "$pid"
  local i=0
  while [ -n "$(port_pid "$port")" ] && [ $i -lt 20 ]; do sleep 0.25; i=$((i + 1)); done
  [ -n "$(port_pid "$port")" ] && kill -9 "$pid" 2>/dev/null || true
  i=0
  while [ -n "$(port_pid "$port")" ] && [ $i -lt 20 ]; do sleep 0.25; i=$((i + 1)); done
  [ -z "$(port_pid "$port")" ] || die "port ${port} is still held after asking PID ${pid} to stop."
  rm -f "$(pidfile "$name")"
}

# Poll until a check passes, giving up rather than hanging forever, and bailing
# out early if the process we are waiting on has already died.
wait_for() { # description timeout-seconds pidfile-name-or-empty command...
  local desc=$1 timeout=$2 guard=$3; shift 3
  local deadline=$(( $(date +%s) + timeout ))
  printf '    %s' "$desc"
  until "$@" >/dev/null 2>&1; do
    if [ -n "$guard" ] && ! service_pid "$guard" >/dev/null 2>&1; then
      printf ' %sfailed%s\n' "$RED" "$N"
      echo >&2
      tail -30 "$(logfile "$guard")" >&2 2>/dev/null || true
      die "the ${guard} exited during startup — its last output is above ($(logfile "$guard"))."
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      printf ' %stimed out after %ss%s\n' "$RED" "$timeout" "$N"
      return 1
    fi
    printf '.'; sleep 1
  done
  printf ' %sok%s\n' "$GRN" "$N"
}

api_ready()  { curl -sf -m 3 "http://127.0.0.1:${API_PORT}/health/ready" >/dev/null; }
api_alive()  { curl -sf -m 3 "http://127.0.0.1:${API_PORT}/health" >/dev/null; }
web_ready()  { curl -sf -m 5 -o /dev/null "http://127.0.0.1:${WEB_PORT}/login"; }
pg_ready()   { docker exec "$PG_CONTAINER" pg_isready -U fishers -d fishers >/dev/null 2>&1; }

# ── stop / status / logs ─────────────────────────────────────────────────────

stop_services() {
  local pid
  for name in web api; do
    if pid="$(service_pid "$name")"; then
      info "stopping ${name} (PID ${pid})"
      kill_tree "$pid"
      rm -f "$(pidfile "$name")"
    fi
  done
  # Ports first, pidfiles second: a run from before pidfiles existed still gets
  # cleared, which is the case that used to leave a port stuck.
  for spec in "web:${WEB_PORT}:dashboard" "api:${API_PORT}:API"; do
    IFS=: read -r name port human <<<"$spec"
    [ -n "$(port_pid "$port")" ] && claim_port "$port" "$name" "$human" soft
  done
  docker rm -f "$API_DOCKER_CONTAINER" >/dev/null 2>&1 || true
}

if [ "$DO_STOP" = 1 ]; then
  step "Stopping"
  stop_services
  if [ "$STOP_ALL" = 1 ]; then
    docker compose down >/dev/null 2>&1 || true
    ok "API, dashboard and Postgres stopped (the data volume is kept)."
  else
    ok "API and dashboard stopped. Postgres is still up — --stop --all takes it down too."
  fi
  exit 0
fi

if [ -n "$DO_LOGS" ]; then
  case "$DO_LOGS" in
    all) exec tail -n 40 -F "$LOG_DIR"/*.log ;;
    *)   f="$(logfile "$DO_LOGS")"
         [ -f "$f" ] || die "no log at $f — services write api.log, web.log and ios-build.log."
         exec tail -n 200 -F "$f" ;;
  esac
fi

if [ "$DO_STATUS" = 1 ]; then
  step "Status"
  if docker ps --filter "name=^${PG_CONTAINER}$" --format '{{.Names}}' | grep -q .; then
    pg_ready && ok "Postgres   ${DATABASE_URL}" || warn "Postgres   container is up but not accepting connections"
  else
    warn "Postgres   not running"
  fi
  if api_ready; then ok "API        ${API_BASE}  (database reachable)"
  elif api_alive; then warn "API        answering on ${API_BASE} but its database is not reachable"
  else warn "API        not running"; fi
  if web_ready; then ok "Dashboard  ${WEB_BASE}/login"
  else warn "Dashboard  not running"; fi
  # The plain-text listing has a trailing space after "(Booted)", so parse JSON.
  booted="$(xcrun simctl list devices booted -j 2>/dev/null \
    | jq -r '[.devices[][] | select(.state=="Booted") | .name] | join(", ")' 2>/dev/null)"
  [ -n "$booted" ] && ok "Simulator  ${booted}" || warn "Simulator  none booted"
  echo
  exit 0
fi

if [ "$FORCE_RESTART" = 1 ]; then
  step "Restarting"
  stop_services
fi

step "Local addresses"
if [ "$LAN_IP" = "127.0.0.1" ]; then
  warn "no LAN address found — loopback only, so phones on the Wi-Fi will not reach this."
else
  ok "this Mac is ${LAN_IP} on the LAN"
fi

# ── Postgres ─────────────────────────────────────────────────────────────────

if [ "$WANT_API" = 1 ]; then
  step "Postgres"

  if [ "$DO_RESET" = 1 ]; then
    info "--reset: removing the database volume"
    stop_services
    docker compose down -v >/dev/null 2>&1 || true
  fi

  docker info >/dev/null 2>&1 || die "Docker is not running — start Docker Desktop / Rancher Desktop and re-run."

  # A container published on a different port than we now want is recreated
  # rather than left to confuse things; the named volume keeps the data.
  running_pg_port="$(docker inspect "$PG_CONTAINER" \
    --format '{{with index .NetworkSettings.Ports "5432/tcp"}}{{(index . 0).HostPort}}{{end}}' 2>/dev/null || true)"
  if [ -n "$running_pg_port" ] && [ "$running_pg_port" != "$POSTGRES_PORT" ]; then
    info "Postgres is published on ${running_pg_port}, want ${POSTGRES_PORT} — recreating"
    docker compose down >/dev/null 2>&1 || true
  fi

  # Rancher Desktop publishes container ports through an ssh mux that can hold
  # the port for a moment after the container goes, so a start straight after a
  # stop is retried rather than reported as a clash. A port genuinely held by
  # something else is named, because "port is already allocated" on its own does
  # not say what to go and stop.
  compose_up() { POSTGRES_PORT="$POSTGRES_PORT" docker compose up -d >"$LOG_DIR/compose.log" 2>&1; }
  if ! compose_up; then
    sleep 2
    if ! compose_up; then
      holder="$(port_pid "$POSTGRES_PORT")" || true
      [ -n "$holder" ] && warn "port ${POSTGRES_PORT} is held by PID ${holder}: $(pid_cmd "$holder")"
      tail -5 "$LOG_DIR/compose.log" >&2 2>/dev/null || true
      die "could not start Postgres on :${POSTGRES_PORT}.
    Stop whatever holds the port, or set POSTGRES_PORT in .env to a spare one."
    fi
  fi
  wait_for "waiting for Postgres" 60 "" pg_ready \
    || die "Postgres never became ready — 'docker logs ${PG_CONTAINER}' has the detail."
  ok "postgres://fishers:fishers@localhost:${POSTGRES_PORT}/fishers"
fi

# ── API ──────────────────────────────────────────────────────────────────────

API_ENV=(
  "API_HOST=[::]"
  "API_PORT=${API_PORT}"
  "DATABASE_URL=${DATABASE_URL}"
  "JWT_SECRET=${JWT_SECRET:-dev-secret-not-for-production-use-only}"
  "JWT_ACCESS_TTL_SECS=${JWT_ACCESS_TTL_SECS:-900}"
  "JWT_REFRESH_TTL_SECS=${JWT_REFRESH_TTL_SECS:-2592000}"
  "RUST_LOG=${RUST_LOG:-fishers_api=debug,tower_http=info,sqlx=warn}"
  "PUBLIC_WEB_BASE=${WEB_BASE}"
  "CORS_ALLOWED_ORIGINS=${WEB_BASE},http://127.0.0.1:${WEB_PORT},http://localhost:${WEB_PORT},http://[::1]:${WEB_PORT}"
  "DLS_G50=${DLS_G50:-245}"
  "FISHERS_AGENT_MODEL=${FISHERS_AGENT_MODEL:-claude-opus-5}"
  "OLLAMA_MODEL=${OLLAMA_MODEL:-llama3.1:8b}"
  # Uploads go to the MinIO in docker-compose. The API writes to the container
  # on the compose network; the browser fetches from the published port, which
  # is a different address for the same bucket.
  "S3_ENDPOINT=${S3_ENDPOINT:-http://minio:9000}"
  "S3_BUCKET=${S3_BUCKET:-fishers}"
  "S3_ACCESS_KEY=${S3_ACCESS_KEY:-fishers}"
  "S3_SECRET_KEY=${S3_SECRET_KEY:-fishers-dev-secret}"
  "S3_PUBLIC_BASE=${S3_PUBLIC_BASE:-http://localhost:${MINIO_PORT:-9002}/${S3_BUCKET:-fishers}}"
)

# Optional integrations are passed only when they are actually configured.
# Passing them through empty is not the same as leaving them unset: an empty
# DLS_RESOURCE_TABLE made the API try to open "" and log a read error on every
# single start, which is noise that trains you to ignore the log.
for var in ANTHROPIC_API_KEY STRIPE_SECRET_KEY STRIPE_WEBHOOK_SECRET DLS_RESOURCE_TABLE OLLAMA_URL \
           SMTP_HOST SMTP_PORT SMTP_TLS SMTP_USERNAME SMTP_PASSWORD EMAIL_FROM \
           WHATSAPP_TOKEN WHATSAPP_PHONE_NUMBER_ID WHATSAPP_TEMPLATE WHATSAPP_TEMPLATE_LANG \
           WHATSAPP_DEFAULT_COUNTRY; do
  [ -n "${!var:-}" ] && API_ENV+=( "${var}=${!var}" )
done

if [ "$WANT_API" = 1 ]; then
  step "API"

  # Reuse a healthy API; replace one that only *looks* healthy. /health is a
  # constant string, so an API whose Postgres has gone away keeps answering it
  # while every real request hangs — that is the failure this checks for.
  if api_ready && [ "$FORCE_RESTART" != 1 ]; then
    ok "already running and serving on :${API_PORT}"
  else
    api_alive && info "the API on :${API_PORT} cannot reach its database — restarting it" || true
    claim_port "$API_PORT" api "API"

    if command -v cargo >/dev/null 2>&1; then
      # Build in the foreground: compile errors belong on screen, not buried in
      # a log. And run the binary directly rather than under `cargo run`, whose
      # PID is the wrapper's — killing it used to leave the server on the port.
      info "building (first run takes a few minutes)"
      (cd backend && cargo build -p fishers-api 2>&1 | tail -40) \
        || die "cargo build failed — see the output above."
      BIN="$ROOT/backend/target/debug/fishers-api"
      [ -x "$BIN" ] || die "cargo build succeeded but $BIN is missing."

      spawn api "$ROOT/backend" env "${API_ENV[@]}" "$BIN"
      wait_for "starting" 90 api api_ready \
        || die "the API started but never reported ready — $(logfile api) has the detail."
    else
      # No local Rust toolchain: build and run in the image CI uses. The cargo
      # volumes keep rebuilds incremental across runs.
      info "no local cargo — building in Docker (first run takes a few minutes)"
      PG_NETWORK="$(docker inspect "$PG_CONTAINER" \
        --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
      DOCKER_ENV=()
      for kv in "${API_ENV[@]}"; do
        case "$kv" in
          DATABASE_URL=*) DOCKER_ENV+=( -e "DATABASE_URL=postgres://fishers:fishers@postgres:5432/fishers" ) ;;
          *)              DOCKER_ENV+=( -e "$kv" ) ;;
        esac
      done
      docker rm -f "$API_DOCKER_CONTAINER" >/dev/null 2>&1 || true
      docker run -d --name "$API_DOCKER_CONTAINER" \
        --network "$PG_NETWORK" \
        -p "${API_PORT}:${API_PORT}" \
        -v "$ROOT/backend:/w" \
        -v fishers-cargo-registry:/usr/local/cargo/registry \
        -v fishers-cargo-target:/w/target \
        -w /w "${DOCKER_ENV[@]}" \
        rust:slim cargo run -p fishers-api >/dev/null \
        || die "could not start the API container."
      info "follow the build with: docker logs -f ${API_DOCKER_CONTAINER}"
      wait_for "compiling and starting" 1800 "" api_ready \
        || { docker logs --tail 30 "$API_DOCKER_CONTAINER" >&2 2>&1 || true
             die "the API container never became ready."; }
    fi
    ok "${API_BASE}  ·  swagger at ${API_BASE}/swagger-ui"
  fi
fi

# ── Web ──────────────────────────────────────────────────────────────────────

if [ "$WANT_WEB" = 1 ]; then
  step "Dashboard"

  if web_ready && [ "$FORCE_RESTART" != 1 ]; then
    ok "already running on :${WEB_PORT}"
  else
    claim_port "$WEB_PORT" web "dashboard"

    # `next build` and `next dev` share .next. A production build left in there
    # makes dev serve stale server chunks and die with "Cannot find module
    # './NNN.js'". Only a build writes BUILD_ID, so it is a safe thing to test.
    if [ -e web/.next/BUILD_ID ]; then
      info "clearing a production build out of .next so dev can use it"
      rm -rf web/.next
    fi

    # npm rewrites node_modules/.package-lock.json on every install but leaves
    # the directory's own mtime alone, so that file is the honest thing to
    # compare against — comparing the directory reinstalled on every run.
    if [ ! -d web/node_modules ] \
       || [ web/package.json -nt web/node_modules/.package-lock.json ] \
       || [ web/package-lock.json -nt web/node_modules/.package-lock.json ]; then
      info "installing web dependencies"
      (cd web && npm install --no-audit --no-fund >>"$(logfile web-install)" 2>&1) \
        || die "npm install failed — see $(logfile web-install)."
    fi

    # Only the port is pinned. The browser derives the host from the page it
    # loaded, so the dashboard keeps working when DHCP changes this machine's
    # address — which silently broke it before, because the LAN IP was baked in
    # at build time.
    cat > web/.env.local <<EOF
# Generated by scripts/start.sh — re-run it after changing ports.
NEXT_PUBLIC_API_PORT=${API_PORT}
EOF

    # --hostname :: is dual-stack on macOS, so one listener serves loopback,
    # the LAN address and IPv6 clients alike.
    spawn web "$ROOT/web" npx next dev --hostname :: -p "$WEB_PORT"
    wait_for "starting" 120 web web_ready \
      || die "the dashboard never answered on :${WEB_PORT} — $(logfile web) has the detail."
    ok "${WEB_BASE}"
  fi

  # The address the tester actually opens, checked from the address they use —
  # loopback working proves nothing about the LAN.
  if [ "$LAN_IP" != "127.0.0.1" ]; then
    if curl -sf -m 5 -o /dev/null "${WEB_BASE}/login"; then
      ok "${WEB_BASE}/login reachable"
    else
      warn "${WEB_BASE}/login did not answer — a firewall may be blocking :${WEB_PORT}."
    fi
    curl -sf -m 5 "${API_BASE}/health/ready" >/dev/null \
      && ok "${API_BASE} reachable" \
      || warn "${API_BASE} did not answer — phones and the Simulator will not sign in."
  fi
fi

# ── Seed ─────────────────────────────────────────────────────────────────────

if [ "$DO_SEED" = 1 ]; then
  step "Demo data"
  API_BASE="http://127.0.0.1:${API_PORT}" ./scripts/seed-demo.sh || warn "seeding failed — the stack is still up."
fi

# ── iOS ──────────────────────────────────────────────────────────────────────

if [ "$WANT_IOS" = 1 ]; then
  step "iOS Simulator"

  if ! xcrun simctl help >/dev/null 2>&1; then
    warn "no Simulator tooling — install Xcode, then 'sudo xcode-select -s /Applications/Xcode.app'."
    warn "skipping the app; the API and dashboard above are still up."
    WANT_IOS=0
  elif ! command -v jq >/dev/null 2>&1; then
    warn "jq is not installed, and picking a Simulator needs it — 'brew install jq'."
    warn "skipping the app; the API and dashboard above are still up."
    WANT_IOS=0
  fi
fi

if [ "$WANT_IOS" = 1 ]; then
  # Pick a device: one already booted, then a requested name, then the newest
  # iPhone available. Booting a second Simulator when one is open is slow and
  # confusing, so a booted device always wins.
  UDID="$(xcrun simctl list devices booted -j 2>/dev/null \
    | jq -r '[.devices[][] | select(.state=="Booted")][0].udid // empty')"
  DEVICE_NAME=""

  if [ -n "$UDID" ] && [ -n "$SIM_DEVICE" ]; then
    booted_name="$(xcrun simctl list devices booted -j | jq -r --arg u "$UDID" '[.devices[][] | select(.udid==$u)][0].name')"
    [ "$booted_name" = "$SIM_DEVICE" ] || UDID=""
  fi

  if [ -z "$UDID" ]; then
    UDID="$(xcrun simctl list devices available -j 2>/dev/null | jq -r --arg want "$SIM_DEVICE" '
      [ .devices | to_entries[]
        | select(.key | test("iOS"))
        | .key as $runtime | .value[]
        | select(.isAvailable == true)
        | select(($want == "") or (.name == $want))
        | { udid, name, runtime: $runtime } ]
      | sort_by(.runtime) | reverse
      | ( map(select(.name | startswith("iPhone"))) + . )
      | .[0].udid // empty')"
  fi

  [ -n "$UDID" ] || die "no iOS Simulator available${SIM_DEVICE:+ named \"$SIM_DEVICE\"}.
    'xcrun simctl list devices available' shows the list; Xcode ▸ Settings ▸ Components installs more."

  DEVICE_NAME="$(xcrun simctl list devices -j | jq -r --arg u "$UDID" '[.devices[][] | select(.udid==$u)][0].name')"
  info "device: ${DEVICE_NAME}"

  # XcodeGen output is gitignored, so a checkout that adds a Swift file leaves
  # it on disk but absent from the target. Regenerate only when the file list or
  # the spec has moved, because rewriting the pbxproj makes an open Xcode reload.
  SPEC="$ROOT/ios/project.yml"
  STAMP="$ROOT/ios/.xcodegen-stamp"
  current_stamp() {
    { find "$ROOT/ios/Fishers" "$ROOT/ios/FishersTests" -type f 2>/dev/null | LC_ALL=C sort
      cat "$SPEC"; } | shasum -a 256 | cut -d' ' -f1
  }
  now_stamp="$(current_stamp)"
  if [ ! -f "$ROOT/ios/Fishers.xcodeproj/project.pbxproj" ] \
     || [ ! -f "$STAMP" ] || [ "$now_stamp" != "$(cat "$STAMP")" ]; then
    command -v xcodegen >/dev/null 2>&1 || die "the Xcode project is out of date and xcodegen is not installed — 'brew install xcodegen'."
    info "regenerating Fishers.xcodeproj"
    (cd ios && xcodegen generate --quiet) || die "xcodegen failed — run it in ios/ to see why."
    current_stamp > "$STAMP"
  fi

  # Boot before building: xcodebuild against a shut-down device is slower and,
  # on some Xcode versions, fails outright.
  sim_booted() {
    [ "$(xcrun simctl list devices -j 2>/dev/null \
         | jq -r --arg u "$UDID" '[.devices[][] | select(.udid==$u)][0].state')" = "Booted" ]
  }
  if ! sim_booted; then
    info "booting ${DEVICE_NAME}"
    xcrun simctl boot "$UDID" 2>/dev/null || true
    wait_for "waiting for boot" 120 "" sim_booted \
      || die "the Simulator did not finish booting — open Simulator.app and check."
  fi
  open -a Simulator --args -CurrentDeviceUDID "$UDID" >/dev/null 2>&1 || true

  info "building (output in $(logfile ios-build))"
  set +e
  xcodebuild \
    -project ios/Fishers.xcodeproj \
    -scheme Fishers \
    -configuration Debug \
    -destination "id=${UDID}" \
    -derivedDataPath "$DERIVED_DATA" \
    -quiet \
    CODE_SIGNING_ALLOWED=NO \
    build >"$(logfile ios-build)" 2>&1
  build_status=$?
  set -e
  if [ $build_status -ne 0 ]; then
    grep -E "error:|BUILD FAILED|xcodebuild:" "$(logfile ios-build)" | head -20 >&2 || true
    die "the iOS build failed — $(logfile ios-build) has the full output."
  fi

  APP="$(find "$DERIVED_DATA/Build/Products" -maxdepth 2 -name 'Fishers.app' -type d 2>/dev/null | head -1)"
  [ -n "$APP" ] || die "the build succeeded but no Fishers.app was produced under $DERIVED_DATA."

  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || echo com.fishers.app)"

  # A stale copy left running would keep the old server address, so it goes
  # first. Uninstalling as well would drop the offline scoring store, which is
  # the thing most worth keeping between runs.
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$APP" || die "could not install the app on ${DEVICE_NAME}."

  # Today's LAN address, handed over at launch rather than compiled in.
  #
  # Written to the app's defaults first, which persist in the device's data
  # container: tapping the icon on the Simulator's home screen, or hitting Run
  # in Xcode, then reaches the same API as this script started. The launch
  # arguments repeat it in the argument domain, which wins for this launch and
  # covers the case where the defaults write is not permitted.
  xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" FishersAPIBaseURL "$API_BASE" >/dev/null 2>&1 || true
  xcrun simctl spawn "$UDID" defaults write "$BUNDLE_ID" FishersWebBaseURL "$WEB_BASE" >/dev/null 2>&1 || true

  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" \
    -FishersAPIBaseURL "$API_BASE" -FishersWebBaseURL "$WEB_BASE" >/dev/null \
    || die "the app was installed but would not launch — 'xcrun simctl launch $UDID $BUNDLE_ID' shows why."
  ok "Fishers launched on ${DEVICE_NAME}, talking to ${API_BASE}"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

cat <<EOF

${B}Ready.${N}

  Dashboard   ${WEB_BASE}/login        ${DIM}(also http://127.0.0.1:${WEB_PORT}/login)${N}
  API         ${API_BASE}
  Swagger     ${API_BASE}/swagger-ui
  Postgres    postgres://fishers:fishers@localhost:${POSTGRES_PORT}/fishers

  ${DIM}Logs      ./scripts/start.sh --logs api | web | ios-build
  Status    ./scripts/start.sh --status
  Stop      ./scripts/start.sh --stop        (--all takes Postgres down too)
  Demo data ./scripts/seed-demo.sh           demo@fishers.test / password123${N}

EOF

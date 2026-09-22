#!/usr/bin/env bash
# Copy named keys from the local .env into a ring's vault config.
#
#   scripts/vault-copy-from-env.sh <int|test|acc|prod> KEY [KEY...]
#   scripts/vault-copy-from-env.sh <ring> --stdin KEY     # value on stdin
#
# For the keys that are not generated — Stripe, Google, Anthropic — which
# vault-seed-ring.sh deliberately leaves to a person. This puts the ones you
# already have locally where a ring can read them, without opening the vault UI
# and without a value ever reaching a terminal, a shell history or a process
# list.
#
# Values are never printed. The summary names keys and says added or replaced,
# and nothing else.
#
# Read-modify-write, because a KV v2 write replaces the whole object: every key
# already at the path is preserved. The named keys win, because replacing them
# is the point of running this.
#
#   export KUBECONFIG=~/.kube/k3s1.yaml
#   scripts/vault-copy-from-env.sh int STRIPE_SECRET_KEY NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY
#
# A webhook signing secret is NOT one to copy from .env: it belongs to one
# endpoint, and the one in .env is for `stripe listen` on your laptop. A ring's
# comes from the endpoint in Stripe's dashboard and has no business being in a
# local file at all, so --stdin puts it straight in the vault:
#
#   scripts/vault-copy-from-env.sh int --stdin STRIPE_WEBHOOK_SECRET
#   (paste the value, then Ctrl-D — it is not echoed and not in your history)
#
# The vault path is kv/fishers/<ring>/config; the ring runs in its own
# `fishers-<ring>` namespace. Both are true at once and they are not the same
# thing.
#
# Auth: VAULT_TOKEN, or KUBECONFIG pointing at the cluster.
set -euo pipefail

RING="${1:-}"
case "$RING" in int|test|acc|prod) shift ;; *)
  echo "usage: $0 <int|test|acc|prod> KEY [KEY...]" >&2; exit 2 ;;
esac
FROM_STDIN=false
if [ "${1:-}" = "--stdin" ]; then
  FROM_STDIN=true
  shift
  [ "$#" -eq 1 ] || { echo "--stdin takes exactly one key" >&2; exit 2; }
fi
[ "$#" -gt 0 ] || { echo "name at least one key to copy" >&2; exit 2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/.env}"
if ! $FROM_STDIN && [ ! -f "$ENV_FILE" ]; then
  echo "no $ENV_FILE to read from" >&2; exit 1
fi

VAULT_ADDR="${VAULT_ADDR:-https://vault.workstation.co.uk}"
URL="$VAULT_ADDR/v1/kv/data/fishers/$RING/config"

for cmd in curl jq; do
  command -v "$cmd" >/dev/null || { echo "needs $cmd" >&2; exit 1; }
done

# The vault token is the platform's, not this product's: it lives in `int`
# wherever Fishers itself runs, which is its own `fishers-<ring>` namespace.
# vault-seed-ring.sh looks in the same place.
if [ -z "${VAULT_TOKEN:-}" ]; then
  for ns in int "fishers-$RING" "$RING"; do
    VAULT_TOKEN=$(kubectl -n "$ns" get secret wslvault-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)
    [ -n "$VAULT_TOKEN" ] && break
  done
  [ -n "$VAULT_TOKEN" ] || { echo "set VAULT_TOKEN, or KUBECONFIG to the k3s cluster" >&2; exit 1; }
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

code=$(curl -sS -o "$tmp/cur" -w '%{http_code}' -H "X-Vault-Token: $VAULT_TOKEN" "$URL")
case "$code" in
  200) jq -c '.data.data // {}' "$tmp/cur" > "$tmp/current.json" ;;
  404) echo '{}' > "$tmp/current.json" ;;
  *)   echo "reading kv/fishers/$RING/config failed: HTTP $code" >&2; exit 1 ;;
esac

echo '{}' > "$tmp/new.json"
missing=()

if $FROM_STDIN; then
  key="$1"
  case "$key" in *[!A-Za-z0-9_]*|'') echo "not a key name: $key" >&2; exit 2 ;; esac
  # `read -s` keeps it off the screen; a here-doc or a pipe works too, which is
  # what makes this usable from a script as well as by hand.
  if [ -t 0 ]; then
    printf 'value for %s (not echoed): ' "$key" >&2
    IFS= read -r -s value || true
    echo >&2
  else
    IFS= read -r value || true
  fi
  [ -n "$value" ] || { echo "nothing given for $key" >&2; exit 2; }
  jq -c --arg k "$key" --arg v "$value" '. + {($k): $v}' "$tmp/new.json" > "$tmp/new.next" \
    && mv "$tmp/new.next" "$tmp/new.json"
  set --
fi

# The last assignment of a key wins, matching how a shell sources the file.
for key in "$@"; do
  case "$key" in *[!A-Za-z0-9_]*|'') echo "not a key name: $key" >&2; exit 2 ;; esac
  value=$(awk -F= -v k="$key" '
    $1 == k { v = substr($0, index($0, "=") + 1); sub(/^["'"'"']/, "", v); sub(/["'"'"']$/, "", v); last = v }
    END { printf "%s", last }' "$ENV_FILE")
  if [ -z "$value" ]; then missing+=("$key"); continue; fi
  jq -c --arg k "$key" --arg v "$value" '. + {($k): $v}' "$tmp/new.json" > "$tmp/new.next" \
    && mv "$tmp/new.next" "$tmp/new.json"
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "not set in $ENV_FILE, so not copied: ${missing[*]}" >&2
fi
[ "$(jq -r 'keys | length' "$tmp/new.json")" -gt 0 ] || { echo "nothing to copy."; exit 0; }

# What this will do, by key name only.
# `.key` has to be captured first: inside `$cur[0] | has(...)` the dot is the
# vault object, not the entry, so `has(.key)` asks for a field called "key".
jq -r --slurpfile cur "$tmp/current.json" '
  to_entries[] | . as $e |
  "  " + (if ($cur[0] | has($e.key)) then
            (if $cur[0][$e.key] == $e.value then "unchanged" else "replaced " end)
          else "added    " end) + "  " + $e.key' "$tmp/new.json"

# Named keys win; everything else at the path is preserved untouched.
jq -c -s '.[0] * .[1]' "$tmp/current.json" "$tmp/new.json" > "$tmp/merged.json"
code=$(curl -sS -o /dev/null -w '%{http_code}' -H "X-Vault-Token: $VAULT_TOKEN" \
  -X POST -H "Content-Type: application/json" \
  --data "$(jq -c -n --slurpfile d "$tmp/merged.json" '{data: $d[0]}')" "$URL")
case "$code" in
  200|204) echo "written to kv/fishers/$RING/config" ;;
  *)       echo "writing failed: HTTP $code" >&2; exit 1 ;;
esac

echo "keys now at the path:"
curl -sS -H "X-Vault-Token: $VAULT_TOKEN" "$URL" | jq -r '.data.data | keys[] | "  " + .'

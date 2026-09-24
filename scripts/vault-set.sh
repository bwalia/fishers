#!/usr/bin/env bash
# Set one key in a brand's ring config, with the value on stdin.
#
#   openssl rand -base64 48 | scripts/vault-set.sh gullycricket int JWT_SECRET
#
# On stdin so the value never reaches a shell history, a process list or this
# terminal. Read-modify-write, so it adds to the ring's config rather than
# replacing it.
#
# Auth: VAULT_TOKEN, or KUBECONFIG pointing at the cluster.
set -euo pipefail

BRAND="${1:-}"
RING="${2:-}"
KEY="${3:-}"
if [ -z "$BRAND" ] || [ -z "$RING" ] || [ -z "$KEY" ]; then
  echo "usage: <value on stdin> | $0 <brand> <ring> <KEY>" >&2
  exit 2
fi
case "$RING" in int|test|acc|prod) ;; *) echo "ring must be int|test|acc|prod" >&2; exit 2 ;; esac

VALUE=$(cat)
[ -n "$VALUE" ] || { echo "nothing on stdin" >&2; exit 2; }

VAULT_ADDR="${VAULT_ADDR:-https://vault.workstation.co.uk}"
URL="$VAULT_ADDR/v1/kv/data/$BRAND/$RING/config"

if [ -z "${VAULT_TOKEN:-}" ]; then
  for ns in int "fishers-$RING" "$RING" wslvault; do
    VAULT_TOKEN=$(kubectl -n "$ns" get secret wslvault-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)
    [ -n "$VAULT_TOKEN" ] && break
  done
  [ -n "${VAULT_TOKEN:-}" ] || { echo "set VAULT_TOKEN, or KUBECONFIG to the k3s cluster" >&2; exit 1; }
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -sS -o "$tmp/cur" -H "X-Vault-Token: $VAULT_TOKEN" "$URL" >/dev/null || true

# The value goes in through a file and jq's --rawfile, never an argument: an
# argument is visible in `ps` for as long as the process lives.
printf '%s' "$VALUE" > "$tmp/value"
jq -n --slurpfile cur "$tmp/cur" --arg key "$KEY" --rawfile value "$tmp/value" \
  '{data: (($cur[0].data.data // {}) + {($key): $value})}' > "$tmp/body"

code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
  -H "X-Vault-Token: $VAULT_TOKEN" -H 'Content-Type: application/json' \
  --data @"$tmp/body" "$URL")
case "$code" in 200|204) echo "set $KEY in kv/$BRAND/$RING/config (${#VALUE} bytes)" ;;
  *) echo "write failed (HTTP $code)" >&2; exit 1 ;;
esac

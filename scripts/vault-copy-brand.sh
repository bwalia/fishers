#!/usr/bin/env bash
# Seed one brand's ring config from another's.
#
#   scripts/vault-copy-brand.sh <from-brand> <to-brand> <ring>
#
# For standing a new brand up quickly: it copies every key at
# kv/<from>/<ring>/config to kv/<to>/<ring>/config.
#
# It does NOT copy JWT_SECRET. That key is what signs a session, so sharing it
# means a token minted by one brand authenticates on the other — and since a
# new brand starts with an empty database and no sessions, a fresh one costs
# nothing. Pass --same-jwt if you genuinely want them shared.
#
# Nothing is printed. Values go from the vault to the vault; the only output is
# which keys moved, by name.
#
# Auth: VAULT_TOKEN, or KUBECONFIG pointing at the cluster.
set -euo pipefail

FROM="${1:-}"
TO="${2:-}"
RING="${3:-}"
SAME_JWT=false
for arg in "$@"; do [ "$arg" = "--same-jwt" ] && SAME_JWT=true; done

if [ -z "$FROM" ] || [ -z "$TO" ] || [ -z "$RING" ]; then
  echo "usage: $0 <from-brand> <to-brand> <ring> [--same-jwt]" >&2
  exit 2
fi
case "$RING" in int|test|acc|prod) ;; *) echo "ring must be int|test|acc|prod" >&2; exit 2 ;; esac

VAULT_ADDR="${VAULT_ADDR:-https://vault.workstation.co.uk}"
SRC="$VAULT_ADDR/v1/kv/data/$FROM/$RING/config"
DST="$VAULT_ADDR/v1/kv/data/$TO/$RING/config"

if [ -z "${VAULT_TOKEN:-}" ]; then
  for ns in int "fishers-$RING" "$RING" wslvault; do
    VAULT_TOKEN=$(kubectl -n "$ns" get secret wslvault-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)
    [ -n "$VAULT_TOKEN" ] && break
  done
  [ -n "${VAULT_TOKEN:-}" ] || { echo "set VAULT_TOKEN, or KUBECONFIG to the k3s cluster" >&2; exit 1; }
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

code=$(curl -sS -o "$tmp/src" -w '%{http_code}' -H "X-Vault-Token: $VAULT_TOKEN" "$SRC")
[ "$code" = 200 ] || { echo "cannot read kv/$FROM/$RING/config (HTTP $code)" >&2; exit 1; }

# What is already at the destination, so this is a merge rather than a wipe:
# a brand that has had a key set by hand must not lose it to a reseed.
curl -sS -o "$tmp/dst" -H "X-Vault-Token: $VAULT_TOKEN" "$DST" >/dev/null || true

jq_prog='
  (.src.data.data // {}) as $s
  | (.dst.data.data // {}) as $d
  | ($d + $s) as $merged
  | if $same_jwt then $merged
    else $merged | if $d.JWT_SECRET then .JWT_SECRET = $d.JWT_SECRET else del(.JWT_SECRET) end
    end
  | {data: .}'

jq -n --slurpfile src "$tmp/src" --slurpfile dst "$tmp/dst" \
  --argjson same_jwt "$SAME_JWT" \
  '{src: $src[0], dst: ($dst[0] // {})} | '"$jq_prog" > "$tmp/body"

code=$(curl -sS -o "$tmp/out" -w '%{http_code}' -X POST \
  -H "X-Vault-Token: $VAULT_TOKEN" -H 'Content-Type: application/json' \
  --data @"$tmp/body" "$DST")
case "$code" in 200|204) ;; *) echo "write failed (HTTP $code)" >&2; exit 1 ;; esac

echo "copied into kv/$TO/$RING/config:"
jq -r '.data | keys[] | "  " + .' "$tmp/body"

if [ "$SAME_JWT" = false ]; then
  echo
  echo "JWT_SECRET was not copied. Set one for $TO:"
  echo "  openssl rand -base64 48 | scripts/vault-set.sh $TO $RING JWT_SECRET"
fi

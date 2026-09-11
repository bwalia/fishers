#!/usr/bin/env bash
# Put a ring's generated secrets into WSLVault at kv/fishers/<ring>/config.
#
#   scripts/vault-seed-ring.sh <int|test|acc|prod>
#
# Then run "Deploy Single Environment" for that ring. That is the whole of
# standing a ring up.
#
# Only ever ADDS keys that are missing; an existing value is never touched. So
# it is safe to re-run, and it cannot rotate a key out from under a running
# ring — rotating JWT_SECRET logs everybody out, and rotating the VAPID pair
# silently breaks every push subscription already handed out. Rotate those on
# purpose, in the vault, not by re-running this.
#
#   scripts/vault-seed-ring.sh <ring> --rotate-vapid
#
# replaces the VAPID pair — for a ring seeded before September 2026, when
# vapid-keys.sh produced a private key that did not match its public one, so
# every push was refused and every subscription dropped. Those subscriptions
# are already dead; browsers make fresh ones against the new key on their own.
#
# Generated here: JWT_SECRET, S3_ACCESS_KEY, S3_SECRET_KEY, VAPID_PUBLIC_KEY,
# VAPID_PRIVATE_KEY. Add the rest in the vault by hand when a ring needs them —
# STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, ANTHROPIC_API_KEY — and they reach
# the API on the next deploy with no chart change.
#
# The database password is deliberately not here: the Zalando operator
# generates it and the API reads it from the operator's own Secret.
#
# Auth: VAULT_TOKEN, or — with KUBECONFIG pointing at the cluster — the token
# the platform's ClusterSecretStore already uses.
set -euo pipefail

RING="${1:-}"
case "$RING" in int|test|acc|prod) ;; *) echo "usage: $0 <int|test|acc|prod> [--rotate-vapid]" >&2; exit 2 ;; esac
ROTATE_VAPID=false
[ "${2:-}" = "--rotate-vapid" ] && ROTATE_VAPID=true

VAULT_ADDR="${VAULT_ADDR:-https://vault.workstation.co.uk}"
PATH_KV="fishers/$RING/config"
URL="$VAULT_ADDR/v1/kv/data/$PATH_KV"
HERE="$(cd "$(dirname "$0")" && pwd)"

for cmd in curl jq openssl; do
  command -v "$cmd" >/dev/null || { echo "needs $cmd" >&2; exit 1; }
done

if [ -z "${VAULT_TOKEN:-}" ]; then
  VAULT_TOKEN=$(kubectl -n int get secret wslvault-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)
  [ -n "$VAULT_TOKEN" ] || { echo "set VAULT_TOKEN, or KUBECONFIG to the k3s cluster" >&2; exit 1; }
fi
auth=(-H "X-Vault-Token: $VAULT_TOKEN")

# Current contents. A 404 is a ring that has never been seeded.
code=$(curl -sS -o /tmp/vault-seed.$$ -w '%{http_code}' "${auth[@]}" "$URL")
case "$code" in
  200) current=$(jq -c '.data.data // {}' /tmp/vault-seed.$$) ;;
  404) current='{}' ;;
  *)   echo "reading kv/$PATH_KV failed: HTTP $code" >&2; cat /tmp/vault-seed.$$ >&2; rm -f /tmp/vault-seed.$$; exit 1 ;;
esac
rm -f /tmp/vault-seed.$$

if $ROTATE_VAPID; then
  current=$(jq -c 'del(.VAPID_PRIVATE_KEY, .VAPID_PUBLIC_KEY)' <<<"$current")
fi

has() { jq -e --arg k "$1" 'has($k) and (.[$k] | length > 0)' <<<"$current" >/dev/null; }

generated='{}'
add() { generated=$(jq -c --arg k "$1" --arg v "$2" '. + {($k): $v}' <<<"$generated"); }

has JWT_SECRET    || add JWT_SECRET    "$(openssl rand -hex 32)"
# MinIO wants a root user of 3+ characters and a password of 8+.
has S3_ACCESS_KEY || add S3_ACCESS_KEY "fishers$(openssl rand -hex 8)"
has S3_SECRET_KEY || add S3_SECRET_KEY "$(openssl rand -hex 24)"
# A pair: generate both or neither, never half of one.
if ! has VAPID_PRIVATE_KEY || ! has VAPID_PUBLIC_KEY; then
  pair=$("$HERE/vapid-keys.sh")
  add VAPID_PRIVATE_KEY "$(sed -n 's/^VAPID_PRIVATE_KEY=//p' <<<"$pair")"
  add VAPID_PUBLIC_KEY  "$(sed -n 's/^VAPID_PUBLIC_KEY=//p'  <<<"$pair")"
fi

added=$(jq -r 'keys | join(", ")' <<<"$generated")
if [ -z "$added" ]; then
  echo "kv/$PATH_KV already has every generated key — nothing to do."
  exit 0
fi

# Existing values win the merge: `$current * $generated` would let a generated
# value replace one somebody set by hand.
merged=$(jq -c -n --argjson gen "$generated" --argjson cur "$current" '$gen + $cur')
code=$(curl -sS -o /dev/null -w '%{http_code}' "${auth[@]}" -X POST \
  -H "Content-Type: application/json" \
  --data "$(jq -c -n --argjson d "$merged" '{data: $d}')" "$URL")
case "$code" in
  200|204) ;;
  *) echo "writing kv/$PATH_KV failed: HTTP $code" >&2; exit 1 ;;
esac

echo "kv/$PATH_KV: added $added"
echo "keys now: $(jq -r 'keys | join(", ")' <<<"$merged")"
echo "Next: run \"Deploy Single Environment\" with ENV=$RING."

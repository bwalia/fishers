#!/usr/bin/env bash
# Generate a VAPID key pair for browser push.
#
# VAPID (RFC 8292) is how a push service knows which server a notification came
# from. The browser subscribes with the public key; the server signs each push
# with the private one. They are a pair — changing either invalidates every
# subscription already handed out, so generate once per environment and keep
# the private half out of the repo.
#
#   ./scripts/vapid-keys.sh
#
# Then set VAPID_PRIVATE_KEY, VAPID_PUBLIC_KEY and VAPID_SUBJECT on the API.
set -euo pipefail

command -v openssl >/dev/null || { echo "needs openssl" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

openssl ecparam -name prime256v1 -genkey -noout -out "$tmp/key.pem" 2>/dev/null

# base64url, unpadded — the encoding both the browser and jwt-simple expect.
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# The private scalar: 32 raw bytes, which is what ES256KeyPair::from_bytes
# wants. Read from the printed hex rather than sliced out of the DER — the
# DER carries the curve OID after the key, so a tail of it is not the key.
#
# Left-padded to 64 hex characters, not tailed: openssl omits leading zero
# bytes, so roughly one key in 256 prints short and a `tail -c 64` silently
# produces a 31-byte scalar that every push then fails to sign with.
priv_hex=$(openssl ec -in "$tmp/key.pem" -text -noout 2>/dev/null \
  | sed -n '/^priv:/,/^pub:/p' | grep -o '[0-9a-f][0-9a-f]:' | tr -d ':\n')
priv_hex=$(printf '%064s' "$priv_hex" | tr ' ' '0')
private=$(printf '%s' "$priv_hex" | xxd -r -p | b64url)

# The public point, uncompressed SEC1: 0x04 || X || Y, 65 bytes. This one is
# genuinely at the end of the DER, after the algorithm identifier.
public=$(openssl ec -in "$tmp/key.pem" -pubout -outform DER 2>/dev/null \
  | tail -c 65 | b64url)

cat <<EOF
# Browser push. The public key is safe to ship to a browser; the private one
# is a secret — treat it like a signing key, because it is one.
VAPID_PRIVATE_KEY=$private
VAPID_PUBLIC_KEY=$public
# Who a push service should contact about traffic from this server.
VAPID_SUBJECT=mailto:hello@fishers.cloud
EOF

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
# wants. Taken from the SEC1 DER, where a P-256 key is always stored at its
# full 32 bytes (zero-padded, never trimmed) straight after a fixed 7-byte
# header: 30 77 02 01 01 04 20.
#
# Not from `openssl ec -text`: that prints the key as "ab:cd:…:ef" with no
# colon after the last byte, so grepping for "xx:" pairs silently drops it —
# and the result is a private key that does not match the public one, which
# the push service answers with 403 "invalid JWT" for every single push.
der="$tmp/key.der"
openssl ec -in "$tmp/key.pem" -outform DER -out "$der" 2>/dev/null
[ "$(head -c 7 "$der" | xxd -p)" = "30770201010420" ] || { echo "unexpected key encoding" >&2; exit 1; }
private=$(tail -c +8 "$der" | head -c 32 | b64url)

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

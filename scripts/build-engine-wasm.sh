#!/usr/bin/env bash
# The cricket engine, compiled for the browser.
#
#   ./scripts/build-engine-wasm.sh [--check]
#
# Writes `web/src/engine/` from `backend/wasm`. The output is committed, because
# the web CI job has node and nothing else and `npm run build` has to work on a
# machine with no Rust — so the artefact is checked in and this script is what
# regenerates it. `--check` regenerates into a temporary directory and fails if
# the committed copy has drifted, which is what CI runs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/web/src/engine"
CHECK=false
[ "${1:-}" = "--check" ] && CHECK=true

command -v cargo >/dev/null || { echo "no cargo on PATH — source ~/.cargo/env" >&2; exit 1; }
rustup target list --installed | grep -q wasm32-unknown-unknown \
  || rustup target add wasm32-unknown-unknown

command -v wasm-bindgen >/dev/null || {
  # The CLI and the crate have to be the same version or the bindings are
  # rejected at load time, which is a confusing way to find out.
  version=$(grep -A1 'name = "wasm-bindgen"' "$ROOT/backend/Cargo.lock" | grep version | head -1 | sed 's/.*"\(.*\)".*/\1/')
  echo "installing wasm-bindgen-cli $version"
  cargo install wasm-bindgen-cli --version "$version"
}

cd "$ROOT/backend"
cargo build -p fishers-wasm --target wasm32-unknown-unknown --release

dest="$OUT"
$CHECK && dest="$(mktemp -d)"
rm -rf "$dest" && mkdir -p "$dest"
wasm-bindgen --target web --out-dir "$dest" \
  target/wasm32-unknown-unknown/release/fishers_wasm.wasm

if $CHECK; then
  if diff -r "$OUT" "$dest" >/dev/null 2>&1; then
    echo "web/src/engine is up to date with backend/wasm"
  else
    echo "::error::web/src/engine has drifted from backend/wasm — run ./scripts/build-engine-wasm.sh" >&2
    diff -rq "$OUT" "$dest" >&2 || true
    exit 1
  fi
  rm -rf "$dest"
else
  echo "wrote $OUT"
fi

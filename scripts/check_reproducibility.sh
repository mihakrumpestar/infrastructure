#!/usr/bin/env bash
set -euo pipefail

# check_reproducibility.sh — Bitwise reproducibility check for NixOS flake outputs
#
# Builds the same derivation in two independent stores (local + temp),
# then compares them with diffoscope as the sole ground truth.
#
# Both stores persist between runs — the temp store accumulates the
# independent build result. On subsequent runs, only changed derivations
# are rebuilt (nix determines this naturally).
#
# Process:
#   1. Build reference in the default (local) store
#   2. Copy reference OUT of the store (plain dir, immune to Nix)
#   3. Build again in the persistent temp store
#   4. diffoscope between the two independent build outputs
#
# Usage:
#   ./scripts/check_reproducibility.sh                           # personal-workstation
#   ./scripts/check_reproducibility.sh --host kiosk              # specific host
#   ./scripts/check_reproducibility.sh --force-source-rebuild    # block binary cache

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

HOST="personal-workstation"
FORCE_SOURCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --force-source-rebuild) FORCE_SOURCE=1; shift ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

OUTDIR="/tmp/reproducibility/$HOST/$(date +%Y%m%dT%H%M%S)"
mkdir -p "$OUTDIR"

# Persistent temp store — accumulates independent build outputs.
# Naturally persists between runs; Nix only rebuilds what changed.
TMP_STORE="/tmp/reproducibility/.store-$HOST"
mkdir -p "$TMP_STORE/nix/store"

STORE_URL="local?root=$TMP_STORE"
TOPLEVEL_ATTR=".#nixosConfigurations.$HOST.config.system.build.toplevel"

echo "=== Reproducibility Check: $HOST ==="
echo "  cache:      $([ "$FORCE_SOURCE" -eq 1 ] && echo "blocked (source only)" || echo "enabled")"
echo "  temp store: $TMP_STORE"
echo "  output:     $OUTDIR"
echo ""

DRV_PATH=$(nix eval --raw "$TOPLEVEL_ATTR.drvPath")
echo "  derivation: $DRV_PATH"

# ---------------------------------------------------------------------------
# Build 1: reference in the default (local) store
# ---------------------------------------------------------------------------
echo ""
echo "--- Build 1 (reference, local store) ---"
nix build "$TOPLEVEL_ATTR" --out-link "$OUTDIR/build1" 2>&1 | tee "$OUTDIR/build1.log"
BUILD1_PATH=$(readlink -f "$OUTDIR/build1")
echo "  path: $BUILD1_PATH"

# ---------------------------------------------------------------------------
# Copy reference OUT of the store (immune to any Nix operations)
# ---------------------------------------------------------------------------
echo ""
echo "--- Copy reference out of store ---"
rsync -a "$BUILD1_PATH/" "$OUTDIR/build1-copy/" 2>&1 | tee "$OUTDIR/rsync.log"
echo "  copied to: $OUTDIR/build1-copy"

# ---------------------------------------------------------------------------
# Build 2: in the persistent temp store (independent of local store).
# Dependencies already in the temp store are reused; anything new is
# fetched from the binary cache or built locally.
# ---------------------------------------------------------------------------
echo ""
echo "--- Build 2 (persistent temp store, independent rebuild) ---"

BUILD2_ARGS=("$TOPLEVEL_ATTR" --store "$STORE_URL" --out-link "$OUTDIR/build2")
if [[ "$FORCE_SOURCE" -eq 1 ]]; then
  echo "  blocking binary cache (force rebuild from source)"
  BUILD2_ARGS+=(--option substituters "")
fi

nix build "${BUILD2_ARGS[@]}" 2>&1 | tee "$OUTDIR/build2.log"
echo "  build complete"

# Resolve build2's output path.
# The out-link points to the LOGICAL path (/nix/store/xxx), but the actual
# files are in the temp store at $TMP_STORE/nix/store/xxx.
BUILD2_LOGICAL=$(readlink -f "$OUTDIR/build2")
BUILD2_PATH="$TMP_STORE$BUILD2_LOGICAL"
echo "  logical path: $BUILD2_LOGICAL"
echo "  actual path:  $BUILD2_PATH"

# ---------------------------------------------------------------------------
# diffoscope — independent bitwise comparison (sole ground truth)
# ---------------------------------------------------------------------------
echo ""
echo "--- diffoscope ---"

DIFFOSCOPE_HTML="$OUTDIR/diffoscope.html"
DIFFOSCOPE_JSON="$OUTDIR/diffoscope.json"

set +e
nix run nixpkgs#diffoscopeMinimal -- \
  --exclude-directory-metadata recursive \
  --html "$DIFFOSCOPE_HTML" \
  --json "$DIFFOSCOPE_JSON" \
  "$OUTDIR/build1-copy" "$BUILD2_PATH" 2>&1 | tee "$OUTDIR/diffoscope.log"
DIFFOSCOPE_EXIT=$?
set -euo pipefail

if [[ "$DIFFOSCOPE_EXIT" -eq 0 ]]; then
  echo "  no differences"
  RESULT="REPRODUCIBLE"
elif [[ "$DIFFOSCOPE_EXIT" -eq 1 ]]; then
  echo "  differences found (see $DIFFOSCOPE_HTML)"
  RESULT="NOT REPRODUCIBLE"
else
  echo "  error (exit $DIFFOSCOPE_EXIT)"
  RESULT="ERROR"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
# External tool (hashrat) for whole-directory hash — avoids circular nix verification
dir_hash() {
  local h
  h=$(hashrat -sha256 -t -dir "$1" 2>/dev/null) && echo "${h%% *}" || echo "N/A"
}
BUILD1_HASH=$(dir_hash "$OUTDIR/build1-copy")
BUILD2_HASH=$(dir_hash "$BUILD2_PATH")

echo ""
echo "=== Summary ==="
echo "  host:       $HOST"
echo "  cache:      $([ "$FORCE_SOURCE" -eq 1 ] && echo "blocked" || echo "enabled")"
echo "  build1:     $BUILD1_PATH"
echo "  build1-copy:$OUTDIR/build1-copy"
echo "  build1-hash:$BUILD1_HASH"
echo "  build2:     $BUILD2_PATH"
echo "  build2-hash:$BUILD2_HASH"
echo "  result:     $RESULT"
echo "  report:     $OUTDIR"
echo "  diffoscope: file://$DIFFOSCOPE_HTML"

case "$RESULT" in
  REPRODUCIBLE) exit 0 ;;
  "NOT REPRODUCIBLE") exit 1 ;;
  *) exit 2 ;;
esac

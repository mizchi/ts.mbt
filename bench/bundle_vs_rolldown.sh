#!/usr/bin/env bash
# Benchmark `mtsc --bundle` (with / without `--mangle`) against
# `rolldown` (with / without `--minify`) on a synthetic corpus.
#
# Usage:
#   bench/bundle_vs_rolldown.sh [count=200] [warmups=2] [runs=10]
#
# Set `MTSC_BIN` to point at the binary; defaults to the release
# build under `_build`. `BENCH_DIR` controls the corpus / output
# directory (default `_build/bench`).
#
# Prereqs:
#   - hyperfine
#   - pnpm (the repo's package.json pulls rolldown in via devDeps)
#   - moon-built `mtsc` binary
#
# The script:
#   1. Generates a `count`-file TS corpus under $BENCH_DIR/corpus
#   2. Runs `mtsc` and `rolldown` once each as a smoke check
#   3. Runs hyperfine over the four configurations, writing a
#      markdown report to $BENCH_DIR/report.md.

set -euo pipefail

cd "$(dirname "$0")/.."

COUNT="${1:-200}"
WARMUPS="${2:-2}"
RUNS="${3:-10}"
BENCH_DIR="${BENCH_DIR:-_build/bench}"
CORPUS="$BENCH_DIR/corpus"
OUT="$BENCH_DIR/out"
REPORT="$BENCH_DIR/report.md"

if [ -z "${MTSC_BIN:-}" ]; then
  # Prefer the release build; fall back to debug if release isn't there.
  if [ -x "_build/native/release/build/cmd/mtsc/mtsc.exe" ]; then
    MTSC_BIN="_build/native/release/build/cmd/mtsc/mtsc.exe"
  else
    MTSC_BIN="_build/native/debug/build/cmd/mtsc/mtsc.exe"
  fi
fi

if [ ! -x "$MTSC_BIN" ]; then
  echo "mtsc binary not found at $MTSC_BIN — run \`moon build --target native --release\`" >&2
  exit 1
fi

mkdir -p "$BENCH_DIR" "$OUT"

echo "==> Generating corpus ($COUNT modules) under $CORPUS"
node bench/gen_corpus.mjs "$CORPUS" "$COUNT"

echo "==> Smoke run (correctness check)"
"$MTSC_BIN" "$CORPUS/entry.ts" --bundle                                              -o "$OUT/mtsc.js"
"$MTSC_BIN" "$CORPUS/entry.ts" --bundle --treeshake                                  -o "$OUT/mtsc.ts.js"
"$MTSC_BIN" "$CORPUS/entry.ts" --bundle --mangle                                     -o "$OUT/mtsc.mangle.js"
"$MTSC_BIN" "$CORPUS/entry.ts" --bundle --treeshake --mangle                         -o "$OUT/mtsc.ts.mangle.js"
"$MTSC_BIN" "$CORPUS/entry.ts" --bundle --fold --treeshake --mangle --minify         -o "$OUT/mtsc.full.js"
"$MTSC_BIN" "$CORPUS/entry.ts" --bundle --fold --treeshake --mangle --mangle-properties --minify -o "$OUT/mtsc.full.mp.js"
node_modules/.bin/rolldown "$CORPUS/entry.ts" -o "$OUT/rolldown.js"             -f esm > /dev/null
node_modules/.bin/rolldown "$CORPUS/entry.ts" -o "$OUT/rolldown.min.js"         -f esm --minify > /dev/null

want="$(node "$OUT/mtsc.js")"
for f in "$OUT/mtsc.ts.js" "$OUT/mtsc.mangle.js" "$OUT/mtsc.ts.mangle.js" "$OUT/mtsc.full.js" "$OUT/mtsc.full.mp.js" "$OUT/rolldown.js" "$OUT/rolldown.min.js"; do
  got="$(node "$f")"
  if [ "$got" != "$want" ]; then
    echo "smoke mismatch: $f differs from mtsc.js" >&2
    echo "want: $want" >&2
    echo "got:  $got"  >&2
    exit 1
  fi
done
echo "    output: $want"

echo "==> Bundle sizes (bytes)"
{
  echo "| tool                     | size |"
  echo "|--------------------------|-----:|"
  for f in "$OUT/mtsc.js" "$OUT/mtsc.ts.js" "$OUT/mtsc.mangle.js" "$OUT/mtsc.ts.mangle.js" "$OUT/mtsc.full.js" "$OUT/mtsc.full.mp.js" "$OUT/rolldown.js" "$OUT/rolldown.min.js"; do
    name="$(basename "$f")"
    size="$(wc -c < "$f")"
    printf "| %-24s | %5d |\n" "$name" "$size"
  done
} | tee "$BENCH_DIR/sizes.md"

echo ""
echo "==> hyperfine — warmups=$WARMUPS runs=$RUNS"

hyperfine \
  --warmup "$WARMUPS" \
  --runs "$RUNS" \
  --export-markdown "$REPORT" \
  --command-name "mtsc --bundle"                          "$MTSC_BIN $CORPUS/entry.ts --bundle -o $OUT/mtsc.js" \
  --command-name "mtsc --bundle --treeshake"              "$MTSC_BIN $CORPUS/entry.ts --bundle --treeshake -o $OUT/mtsc.ts.js" \
  --command-name "mtsc --bundle --mangle"                 "$MTSC_BIN $CORPUS/entry.ts --bundle --mangle -o $OUT/mtsc.mangle.js" \
  --command-name "mtsc --bundle --treeshake --mangle"     "$MTSC_BIN $CORPUS/entry.ts --bundle --treeshake --mangle -o $OUT/mtsc.ts.mangle.js" \
  --command-name "mtsc --bundle --fold --treeshake --mangle --minify" \
                                                          "$MTSC_BIN $CORPUS/entry.ts --bundle --fold --treeshake --mangle --minify -o $OUT/mtsc.full.js" \
  --command-name "mtsc + --mangle-properties (type-safe)" \
                                                          "$MTSC_BIN $CORPUS/entry.ts --bundle --fold --treeshake --mangle --mangle-properties --minify -o $OUT/mtsc.full.mp.js" \
  --command-name "rolldown"                               "node_modules/.bin/rolldown $CORPUS/entry.ts -o $OUT/rolldown.js -f esm" \
  --command-name "rolldown --minify"                      "node_modules/.bin/rolldown $CORPUS/entry.ts -o $OUT/rolldown.min.js -f esm --minify"

echo ""
echo "Report written to $REPORT"
echo "Sizes  written to $BENCH_DIR/sizes.md"

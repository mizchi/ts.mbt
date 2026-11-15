#!/usr/bin/env bash
# Field data: does `mtsc --noEmit` type-check univer (dream-num/univer)?
#
# univer is a 58-package pnpm monorepo of ordinary application TypeScript
# (decorator DI, React UI, a spreadsheet engine), and its own CI type-checks
# it with `tsrs --noEmit`, a port of TypeScript 7.1 — so TS7 accepting it is
# the reference, and every diagnostic `mtsc` reports on it is a false
# positive. It is checked out OUTSIDE the repo (it is ~1 GB with
# dependencies) and installed with `--ignore-scripts`, which also skips the
# `prepare` scripts that generate four files (`*.generated`, `*.gen`,
# `icon-map`): TS7's only errors on the checkout are those missing files
# and their cascades, and `mtsc` reports them as unresolved imports rather
# than type errors.
#
# usage: scripts/field_univer.sh <work dir> [mtsc binary]
#   <work dir>/univer        the checkout (cloned on first run)
#   <work dir>/runs/<stamp>  per-package output, `unique.txt`, `times.txt`
#
# Each package is checked from its `src/index.ts`, so the shared core is
# checked once per package; `unique.txt` folds the duplicates by
# rewriting `packages/A/node_modules/@univerjs/B/` to `packages/B/`.
set -euo pipefail

WORK=${1:?usage: field_univer.sh <work dir> [mtsc binary]}
MTSC=${2:-$(pwd)/_build/native/release/build/cmd/mtsc/mtsc.exe}
TAG=v1.5.0
TSC=$(pwd)/node_modules/typescript/bin/tsc

mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)
if [ ! -d "$WORK/univer" ]; then
  git clone --depth 1 --branch "$TAG" https://github.com/dream-num/univer "$WORK/univer"
  # pnpm 12 writes a multi-document lockfile older pnpm rejects.
  (cd "$WORK/univer" && npx -y pnpm@12.16.1 install --frozen-lockfile --ignore-scripts)
fi

OUT="$WORK/runs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
cd "$WORK/univer"
ls -d packages/*/src/index.ts | sort > "$OUT/entries.txt"
export MTSC OUT
xargs -P 4 -I{} sh -c '
  p=$(echo {} | cut -d/ -f2)
  s=$(date +%s%N)
  timeout 900 "$MTSC" {} --noEmit > "$OUT/$p.mtsc.txt" 2>&1 || true
  e=$(date +%s%N)
  echo "$p $(( (e - s) / 1000000 ))" >> "$OUT/times.txt"
' < "$OUT/entries.txt"

cat "$OUT"/*.mtsc.txt | { grep 'type error' || true; } |
  sed -E ':a; s#(type error in )packages/[^/ ]+/node_modules/@univerjs/([^/ ]+)/#\1packages/\2/#; ta' |
  sed -E ':b; s#@packages/[^/ `]+/node_modules/@univerjs/([^/ `]+)/#@packages/\1/#; tb' |
  sort -u > "$OUT/unique.txt"
echo "mtsc: $(wc -l < "$OUT/unique.txt") unique diagnostics in $(sed -E 's/^mtsc: type error in ([^ ]+) .*/\1/' "$OUT/unique.txt" | sort -u | wc -l) files, $(awk '{s += $2} END {print s / 1000}' "$OUT/times.txt") s summed over $(wc -l < "$OUT/times.txt") packages"
sed -E 's/^mtsc: type error in [^ ]+ \[.*\]: (.*)$/\1/' "$OUT/unique.txt" |
  sed -E 's/`[^`]*`/`_`/g; s/[0-9]+/N/g' | sort | uniq -c | sort -rn | head -15 || true

# The reference: TS7 over each package's own tsconfig. Opt in with
# FIELD_TS7=1 — it is the slower half, and its answer changes only when the
# checkout or the compiler does.
if [ "${FIELD_TS7:-0}" = 1 ]; then
  for c in $(ls -d packages/*/tsconfig.json | sort); do
    p=$(echo "$c" | cut -d/ -f2)
    node "$TSC" -p "$c" --noEmit > "$OUT/$p.ts7.txt" 2>&1 || true
  done
  # At v1.5.0 every one of these is a missing generated file (TS2307) or
  # its cascade: TS7006 in `clsx.ts`, TS2731 / TS2677 / TS18046 in the
  # emoji picker, TS2322 / TS2345 in `hyphen.spec.ts`.
  echo "TS7 errors by code:"
  cat "$OUT"/*.ts7.txt | { grep -oE 'error TS[0-9]+' || true; } | sort | uniq -c | sort -rn
fi

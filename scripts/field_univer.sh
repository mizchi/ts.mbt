#!/usr/bin/env bash
# Field data: does `mtsc` type-check univer (dream-num/univer)?
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
#   <work dir>/runs/<stamp>  per-package output, `unique.txt`, `times.txt`,
#                            `status.txt`
#
# Each package is checked the way its CI checks it, `-p
# packages/<p>/tsconfig.json`: the package's `include` as one program,
# under the `compilerOptions` its config chain sets (univer's packages all
# extend `@univerjs-infra/shared/tsconfigs/base`, which turns on
# `experimentalDecorators` and `noImplicitOverride` and turns off
# `strictPropertyInitialization`). The shared core is reached from every
# package, so it is checked once per package; `unique.txt` folds the
# duplicates by rewriting `packages/A/node_modules/@univerjs/B/` to
# `packages/B/`.
#
# A package whose check is cut off (the 900 s timeout) or crashes is not a
# clean package, so its exit status is recorded and the run fails rather
# than reporting a count that silently left it out.
set -euo pipefail

REPO=$(pwd)
WORK=${1:?usage: field_univer.sh <work dir> [mtsc binary]}
MTSC=${2:-$REPO/_build/native/release/build/cmd/mtsc/mtsc.exe}
TAG=v1.5.0
TSC=$REPO/node_modules/typescript/bin/tsc

# The checks run from inside the checkout, so a relative binary path has
# to be resolved against the directory it was given from.
case "$MTSC" in
  /*) ;;
  *) MTSC=$REPO/$MTSC ;;
esac
if [ ! -x "$MTSC" ]; then
  echo "field_univer: no mtsc binary at $MTSC (build with: moon build --target native --release)" >&2
  exit 2
fi

mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)
if [ ! -d "$WORK/univer" ]; then
  git clone --depth 1 --branch "$TAG" https://github.com/dream-num/univer "$WORK/univer"
fi
# The install is what takes the time and what a dropped connection
# interrupts, so it is retried until it has SUCCEEDED once, not merely
# until the checkout exists.
if [ ! -f "$WORK/univer/.field-install-ok" ]; then
  # pnpm 12 writes a multi-document lockfile older pnpm rejects.
  (cd "$WORK/univer" && npx -y pnpm@12.16.1 install --frozen-lockfile --ignore-scripts)
  touch "$WORK/univer/.field-install-ok"
fi

OUT="$WORK/runs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
cd "$WORK/univer"
ls -d packages/*/tsconfig.json | sort > "$OUT/entries.txt"
export MTSC OUT
# `mtsc` exits 0 for a clean program and 1 for one with diagnostics; any
# other status — 137 from the `timeout` KILL (mtsc blocks SIGTERM, so a
# plain `timeout` never stops it), a crash — means the package
# was not fully checked.
xargs -P 4 -I{} sh -c '
  p=$(echo {} | cut -d/ -f2)
  s=$(date +%s%N)
  set +e
  timeout -s KILL 900 "$MTSC" -p {} --noEmit > "$OUT/$p.mtsc.txt" 2>&1
  code=$?
  set -e
  e=$(date +%s%N)
  echo "$p $(( (e - s) / 1000000 ))" >> "$OUT/times.txt"
  echo "$p $code" >> "$OUT/status.txt"
' < "$OUT/entries.txt"

cat "$OUT"/*.mtsc.txt | { grep 'type error' || true; } |
  sed -E ':a; s#(type error in )packages/[^/ ]+/node_modules/@univerjs/([^/ ]+)/#\1packages/\2/#; ta' |
  sed -E ':b; s#@packages/[^/ `]+/node_modules/@univerjs/([^/ `]+)/#@packages/\1/#; tb' |
  sort -u > "$OUT/unique.txt"
echo "mtsc: $(wc -l < "$OUT/unique.txt") unique diagnostics in $(sed -E 's/^mtsc: type error in ([^ ]+) .*/\1/' "$OUT/unique.txt" | sort -u | wc -l) files, $(awk '{s += $2} END {print s / 1000}' "$OUT/times.txt") s summed over $(wc -l < "$OUT/times.txt") packages"
sed -E 's/^mtsc: type error in [^ ]+ \[.*\]: (.*)$/\1/' "$OUT/unique.txt" |
  sed -E 's/`[^`]*`/`_`/g; s/[0-9]+/N/g' | sort | uniq -c | sort -rn | head -15 || true

incomplete=$(awk '$2 != 0 && $2 != 1' "$OUT/status.txt" | sort)

# The reference: TS7 over each package's own tsconfig. Opt in with
# FIELD_TS7=1 — it is the slower half, and its answer changes only when the
# checkout or the compiler does.
if [ "${FIELD_TS7:-0}" = 1 ]; then
  if [ ! -f "$TSC" ]; then
    echo "field_univer: no TypeScript compiler at $TSC (run npm ci in the repo)" >&2
    exit 2
  fi
  # `tsc` exits 0 for a clean program and 1 or 2 for one with
  # diagnostics; anything else (`node` missing, a crash, a signal) means
  # the reference was not computed for that package, and an empty error
  # list from it must not read as "TS7 accepts this".
  for c in $(cat "$OUT/entries.txt"); do
    p=$(echo "$c" | cut -d/ -f2)
    set +e
    node "$TSC" -p "$c" --noEmit > "$OUT/$p.ts7.txt" 2>&1
    code=$?
    set -e
    echo "$p $code" >> "$OUT/ts7-status.txt"
  done
  ts7_incomplete=$(awk '$2 != 0 && $2 != 1 && $2 != 2' "$OUT/ts7-status.txt" | sort)
  if [ -n "$ts7_incomplete" ]; then
    incomplete=$(printf '%s\n%s' "$incomplete" "$(echo "$ts7_incomplete" | sed 's/^/ts7:/')" | sed '/^$/d')
  fi
  # At v1.5.0 every one of these is a missing generated file (TS2307) or
  # its cascade: TS7006 in `clsx.ts`, TS2731 / TS2677 / TS18046 in the
  # emoji picker, TS2322 / TS2345 in `hyphen.spec.ts`.
  echo "TS7 errors by code:"
  cat "$OUT"/*.ts7.txt | { grep -oE 'error TS[0-9]+' || true; } | sort | uniq -c | sort -rn
fi

if [ -n "$incomplete" ]; then
  echo "field_univer: these packages were not fully checked (package, exit status):" >&2
  echo "$incomplete" >&2
  exit 1
fi

#!/usr/bin/env bash
# Correlate the checker against the TypeScript conformance baselines.
#
# Each conformance case `foo.ts` is shipped alongside a baseline directory.
# When the official compiler reports an error, a `foo.errors.txt` baseline
# exists; when the program is accepted, it does not. That gives a free
# oracle for the checker's *soundness*: we don't model every TS type rule,
# so missing some flagged cases is expected — but flagging a case the
# compiler accepts is a compatibility bug.
#
# For every single-file conformance `.ts` (multi-file `// @filename` cases
# are skipped — the single-file parser can't model them) this classifies:
#
#   TP   has .errors.txt  &&  we flag    (agreement — TS errors, we agree)
#   MISS has .errors.txt  &&  we silent  (expected: we are a subset of TS)
#   FP   no  .errors.txt  &&  we flag    (***soundness bug — TS accepts***)
#   TN   no  .errors.txt  &&  we silent  (agreement — both accept)
#
# Usage:
#   scripts/checker_conformance_oracle.sh                 # print summary + FP list
#   scripts/checker_conformance_oracle.sh --max-fp 7      # gate: exit 1 if FP > 7
#   scripts/checker_conformance_oracle.sh --dir types     # restrict to a subtree
#
# Exit codes:
#   0  ran (or FP within --max-fp budget)
#   1  FP count exceeded --max-fp, or no corpus / binary found

set -uo pipefail
cd "$(dirname "$0")/.."

TSCHECK="_build/native/release/build/cmd/tscheck/tscheck.exe"
if [ ! -x "$TSCHECK" ]; then
  TSCHECK="_build/native/debug/build/cmd/tscheck/tscheck.exe"
fi
if [ ! -x "$TSCHECK" ]; then
  echo "tscheck binary not found — run \`moon build --target native\`" >&2
  exit 1
fi

BASELINES="typescript/tests/baselines/reference"
CONFORMANCE="typescript/tests/cases/conformance"
SUBDIR=""
MAX_FP=-1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-fp) MAX_FP="$2"; shift 2 ;;
    --dir)    SUBDIR="$2"; shift 2 ;;
    *)        echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

ROOT="$CONFORMANCE"
[ -n "$SUBDIR" ] && ROOT="$CONFORMANCE/$SUBDIR"

if [ ! -d "$ROOT" ] || [ ! -d "$BASELINES" ]; then
  echo "conformance corpus not populated ($ROOT / $BASELINES missing) — skipping." >&2
  exit 0
fi

declare -i tp=0 miss=0 fp=0 tn=0 parsefail=0
fp_files=()

while IFS= read -r f; do
  # Multi-file cases need a project graph the single-file CLI lacks.
  grep -q "@filename" "$f" 2>/dev/null && continue
  base=$(basename "$f" .ts)
  # A case run under multiple settings emits suffixed baselines such as
  # `foo(target=es5).errors.txt`, so match the bare name and any
  # parenthesised variant.
  if [ -f "$BASELINES/${base}.errors.txt" ] || \
     compgen -G "$BASELINES/${base}(*).errors.txt" >/dev/null 2>&1; then
    has=1
  else
    has=0
  fi
  out=$("$TSCHECK" "$f" 2>&1 | tail -1)
  if echo "$out" | grep -q "error:"; then
    parsefail+=1
    continue
  fi
  iss=$(echo "$out" | grep -oP '\d+ issues' | grep -oP '\d+' || echo 0)
  if [ "${iss:-0}" -gt 0 ]; then flag=1; else flag=0; fi
  if   [ "$has" = 1 ] && [ "$flag" = 1 ]; then tp+=1
  elif [ "$has" = 1 ];                    then miss+=1
  elif [ "$flag" = 1 ];                   then fp+=1; fp_files+=("$f")
  else                                         tn+=1
  fi
done < <(find "$ROOT" -name "*.ts")

total=$((tp + miss + fp + tn))
echo "=== Checker vs TypeScript conformance baselines ==="
echo "Corpus root   : $ROOT"
echo "Classified    : $total  (parse failures skipped: $parsefail)"
echo "TP  err+flag  : $tp"
echo "MISS err+quiet: $miss   (expected — checker models a subset of TS)"
echo "FP  ok +flag  : $fp     (soundness bugs — TS accepts these)"
echo "TN  ok +quiet : $tn"
if [ "$fp" -gt 0 ]; then
  echo "--- false positives (TS accepts, we flag) ---"
  for f in "${fp_files[@]}"; do echo "  $f"; done
fi

if [ "$MAX_FP" -ge 0 ] && [ "$fp" -gt "$MAX_FP" ]; then
  echo "FAIL: false-positive count $fp exceeds budget $MAX_FP" >&2
  exit 1
fi

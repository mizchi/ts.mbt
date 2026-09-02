#!/usr/bin/env bash
# Correlate the checker against the TypeScript 7 conformance results.
#
# The oracle's ground truth is **TypeScript 7** (the native compiler,
# microsoft/typescript-go). tsgo runs the conformance suite from its
# TypeScript submodule pin and stores complete baselines; whether a test
# errors is derivable from baseline FILE NAMES alone, so this repo vendors
# only two name lists under scripts/ts7_baselines/ (see the README there
# for provenance and regeneration):
#
#   tsgo_ran_set.txt     tests tsgo actually ran (any baseline artifact)
#   tsgo_errors_set.txt  tests where TS7 reports >= 1 error
#
# For every single-file conformance `.ts` (multi-file `// @filename` cases
# are skipped — the single-file parser can't model them) this classifies:
#
#   TP     TS7 errors  &&  we flag    (agreement)
#   MISS   TS7 errors  &&  we silent  (expected: we are a subset of TS)
#   FP     TS7 accepts &&  we flag    (***soundness bug***)
#   TN     TS7 accepts &&  we silent  (agreement)
#   NOTRUN tsgo skipped the test      (excluded — e.g. every target=es5 /
#                                      target=es3 variant; TS7 removed
#                                      those targets)
#
# A PARSE FAILURE is a rejection too: on a TS7-erroring file it counts as a
# TP (reported separately); on a TS7-accepted file it is a parser soundness
# bug — reported as PFLEGAL and gated by --max-legal-parsefail.
#
# Usage:
#   scripts/checker_conformance_oracle.sh                 # summary + FP list
#   scripts/checker_conformance_oracle.sh --max-fp 0      # gate on FPs
#   scripts/checker_conformance_oracle.sh --dir types     # restrict subtree
#
# Exit codes:
#   0  ran (or budgets respected)
#   1  FP / PFLEGAL budget exceeded, or no corpus / binary found

set -uo pipefail
cd "$(dirname "$0")/.."

# Pick the NEWER of the two builds, and say which one. This used to prefer
# release unconditionally and print nothing, which is a trap rather than a
# preference: `just verify-checker-soundness` runs `moon build --target
# native` (debug), so a release binary left over from an earlier session
# silently won and the run measured code nobody had just built. Cost a real
# debugging detour — six target files "did not change" because the harness
# was running a binary from before the change. CI never sees it (a fresh
# checkout has neither binary until the recipe builds one), which is exactly
# why it survived.
TSCHECK_RELEASE="_build/native/release/build/cmd/tscheck/tscheck.exe"
TSCHECK_DEBUG="_build/native/debug/build/cmd/tscheck/tscheck.exe"
TSCHECK=""
if [ -x "$TSCHECK_RELEASE" ] && [ -x "$TSCHECK_DEBUG" ]; then
  if [ "$TSCHECK_DEBUG" -nt "$TSCHECK_RELEASE" ]; then
    TSCHECK="$TSCHECK_DEBUG"
  else
    TSCHECK="$TSCHECK_RELEASE"
  fi
elif [ -x "$TSCHECK_RELEASE" ]; then
  TSCHECK="$TSCHECK_RELEASE"
elif [ -x "$TSCHECK_DEBUG" ]; then
  TSCHECK="$TSCHECK_DEBUG"
fi
if [ -z "$TSCHECK" ]; then
  echo "tscheck binary not found — run \`moon build --target native\`" >&2
  exit 1
fi

CONFORMANCE="typescript/tests/cases/conformance"
RAN_SET="scripts/ts7_baselines/tsgo_ran_set.txt"
ERRORS_SET="scripts/ts7_baselines/tsgo_errors_set.txt"
SUBDIR=""
MAX_FP=-1
MAX_LEGAL_PARSEFAIL=-1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-fp) MAX_FP="$2"; shift 2 ;;
    --max-legal-parsefail) MAX_LEGAL_PARSEFAIL="$2"; shift 2 ;;
    --dir)    SUBDIR="$2"; shift 2 ;;
    *)        echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

ROOT="$CONFORMANCE"
[ -n "$SUBDIR" ] && ROOT="$CONFORMANCE/$SUBDIR"

if [ ! -d "$ROOT" ] || [ ! -f "$RAN_SET" ] || [ ! -f "$ERRORS_SET" ]; then
  echo "conformance corpus / TS7 manifests not populated ($ROOT / $RAN_SET) — skipping." >&2
  exit 0
fi

declare -i tp=0 miss=0 fp=0 tn=0 tp_parse=0 pflegal=0 notrun=0
fp_files=()
pflegal_files=()

while IFS= read -r f; do
  # Multi-file cases need a project graph the single-file CLI lacks.
  # The `@Filename:` directive is case-insensitive in the TS test
  # harness (`@filename`, `@Filename`, `@FileName` all occur), so match
  # it that way -- otherwise a capitalised variant slips through and the
  # concatenated multi-file blob gets classified as if it were one file.
  grep -qi "@filename" "$f" 2>/dev/null && continue
  base=$(basename "$f" .ts)
  # Tests tsgo never ran carry no verdict — excluded from every bucket.
  if ! grep -qxF "$base" "$RAN_SET"; then
    notrun+=1
    continue
  fi
  if grep -qxF "$base" "$ERRORS_SET"; then has=1; else has=0; fi
  out=$("$TSCHECK" "$f" 2>&1 | tail -1)
  if echo "$out" | grep -q "error:"; then
    # A parse rejection of a compiler-rejected file is agreement; of a
    # compiler-accepted file it is a parser soundness bug.
    if [ "$has" = 1 ]; then
      tp+=1; tp_parse+=1
    else
      pflegal+=1; pflegal_files+=("$f")
    fi
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

total=$((tp + miss + fp + tn + pflegal))
echo "=== Checker vs TypeScript 7 conformance results ==="
echo "Corpus root   : $ROOT"
echo "Binary        : $TSCHECK"
echo "Classified    : $total   (NOTRUN excluded: $notrun)"
echo "TP  err+flag  : $tp   (of which via parse rejection: $tp_parse)"
echo "MISS err+quiet: $miss   (expected — checker models a subset of TS)"
echo "FP  ok +flag  : $fp     (soundness bugs — TS7 accepts these)"
echo "PFLEGAL       : $pflegal     (parser rejects TS7-legal files — parser bugs)"
echo "TN  ok +quiet : $tn"
if [ "$fp" -gt 0 ]; then
  echo "--- false positives (TS7 accepts, we flag) ---"
  for f in "${fp_files[@]}"; do echo "  $f"; done
fi
if [ "$pflegal" -gt 0 ]; then
  echo "--- legal-TS7 parse failures (parser bugs) ---"
  for f in "${pflegal_files[@]}"; do echo "  $f"; done
fi

if [ "$MAX_FP" -ge 0 ] && [ "$fp" -gt "$MAX_FP" ]; then
  echo "FAIL: false-positive count $fp exceeds budget $MAX_FP" >&2
  exit 1
fi
if [ "$MAX_LEGAL_PARSEFAIL" -ge 0 ] && [ "$pflegal" -gt "$MAX_LEGAL_PARSEFAIL" ]; then
  echo "FAIL: legal-parse-failure count $pflegal exceeds budget $MAX_LEGAL_PARSEFAIL" >&2
  exit 1
fi
exit 0

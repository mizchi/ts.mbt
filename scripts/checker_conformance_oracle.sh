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
# The MISS bucket is reported as TWO numbers, because one could rank
# nothing: it summed work worth doing now with files nobody should ever
# fix, so it answered neither "are we done?" nor "what next?" — the defect
# that retired docs/checker-priority.md. scripts/checker_out_of_scope.txt
# declares the second half, one path per line with its reason;
# docs/checker-triage.md is the argument. `MISS (in scope)` is the real
# backlog and can legitimately reach zero.
#
# The scope file is NOT a suppression list and cannot hide a soundness bug:
# it only ever moves a file between the two MISS columns, so an FP on a
# listed file is still an FP and still counts against --max-fp. Entries
# that have stopped being MISSes are reported as STALE.
#
# Usage:
#   scripts/checker_conformance_oracle.sh                 # summary + FP list
#   scripts/checker_conformance_oracle.sh --max-fp 0      # gate on FPs
#   scripts/checker_conformance_oracle.sh --max-miss 157  # gate the backlog
#   scripts/checker_conformance_oracle.sh --dir types     # restrict subtree
#
# Exit codes:
#   0  ran (or budgets respected)
#   1  FP / PFLEGAL / in-scope MISS budget exceeded, or no corpus / binary

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
SCOPE_FILE="scripts/checker_out_of_scope.txt"
SUBDIR=""
MAX_FP=-1
MAX_LEGAL_PARSEFAIL=-1
MAX_MISS=-1
MISS_LIST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-fp) MAX_FP="$2"; shift 2 ;;
    --max-legal-parsefail) MAX_LEGAL_PARSEFAIL="$2"; shift 2 ;;
    # Gate the IN-SCOPE backlog. A budget here catches the regression
    # nothing else can see: a rule that stops firing takes a file from TP
    # to MISS, which every other number in this report absorbs silently.
    --max-miss) MAX_MISS="$2"; shift 2 ;;
    # Declared out of scope, one path per line (see the header). `--scope-file
    # /dev/null` reports the old single MISS number.
    --scope-file) SCOPE_FILE="$2"; shift 2 ;;
    --dir)    SUBDIR="$2"; shift 2 ;;
    # Write every IN-SCOPE MISS file's path to FILE. The counts alone say
    # how many we miss and nothing about WHICH, so ranking the remaining
    # work means having the list; taking it from this loop rather than a
    # second script is what keeps the two from disagreeing about what a
    # MISS is. Declared-out-of-scope paths are excluded, because a ranking
    # that includes them ranks work nobody intends to do.
    --miss-list) MISS_LIST="$2"; shift 2 ;;
    *)        echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

ROOT="$CONFORMANCE"
[ -n "$SUBDIR" ] && ROOT="$CONFORMANCE/$SUBDIR"

if [ ! -d "$ROOT" ] || [ ! -f "$RAN_SET" ] || [ ! -f "$ERRORS_SET" ]; then
  echo "conformance corpus / TS7 manifests not populated ($ROOT / $RAN_SET) — skipping." >&2
  exit 0
fi

# The declared out-of-scope set. `oos_seen` records which entries were
# actually observed as a MISS this run, so an entry that has stopped being
# one is reported rather than left to rot — the reason a path is here can
# go away (a rule lands, the local compiler moves), and a scope file whose
# entries are never re-checked is how a suppression list starts.
declare -A oos_reason=()
declare -A oos_seen=()
if [ -f "$SCOPE_FILE" ]; then
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    p="${line%%[[:space:]]*}"
    [ -z "$p" ] && continue
    oos_reason["$p"]="${line#"$p"}"
  done < "$SCOPE_FILE"
fi

declare -i tp=0 miss=0 oos=0 fp=0 tn=0 tp_parse=0 pflegal=0 notrun=0
fp_files=()
pflegal_files=()
[ -n "$MISS_LIST" ] && : > "$MISS_LIST"

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
  elif [ "$has" = 1 ]; then
    # Only the MISS bucket splits. Nothing above this point consults the
    # scope file, so a listed file can still be a TP, an FP or a PFLEGAL
    # exactly as before — being out of scope withholds a rule, it does not
    # excuse a wrong answer.
    if [ -n "${oos_reason[$f]+x}" ]; then
      oos+=1; oos_seen["$f"]=1
    else
      miss+=1
      [ -n "$MISS_LIST" ] && echo "$f" >> "$MISS_LIST"
    fi
  elif [ "$flag" = 1 ];                   then fp+=1; fp_files+=("$f")
  else                                         tn+=1
  fi
done < <(find "$ROOT" -name "*.ts")

total=$((tp + miss + oos + fp + tn + pflegal))
echo "=== Checker vs TypeScript 7 conformance results ==="
echo "Corpus root   : $ROOT"
echo "Binary        : $TSCHECK"
echo "Classified    : $total   (NOTRUN excluded: $notrun)"
echo "TP  err+flag  : $tp   (of which via parse rejection: $tp_parse)"
echo "MISS in scope : $miss   (the backlog — this one can reach zero)"
echo "OUT OF SCOPE  : $oos     (declared in $SCOPE_FILE)"
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

# An entry whose reason has expired. Only meaningful over the whole
# corpus — with --dir most entries are simply outside the subtree.
if [ -z "$SUBDIR" ] && [ "${#oos_reason[@]}" -gt 0 ]; then
  stale=()
  for p in "${!oos_reason[@]}"; do
    [ -n "${oos_seen[$p]+x}" ] || stale+=("$p")
  done
  if [ "${#stale[@]}" -gt 0 ]; then
    echo "--- STALE scope entries (listed, but no longer a MISS) ---"
    echo "    Each is now a TP, an FP, out of the corpus, or NOTRUN. Remove"
    echo "    it from $SCOPE_FILE — an entry nobody re-checks is how a scope"
    echo "    file turns into a suppression list."
    for p in $(printf '%s\n' "${stale[@]}" | sort); do echo "  $p"; done
  fi
fi

if [ "$MAX_FP" -ge 0 ] && [ "$fp" -gt "$MAX_FP" ]; then
  echo "FAIL: false-positive count $fp exceeds budget $MAX_FP" >&2
  exit 1
fi
if [ "$MAX_LEGAL_PARSEFAIL" -ge 0 ] && [ "$pflegal" -gt "$MAX_LEGAL_PARSEFAIL" ]; then
  echo "FAIL: legal-parse-failure count $pflegal exceeds budget $MAX_LEGAL_PARSEFAIL" >&2
  exit 1
fi
if [ "$MAX_MISS" -ge 0 ] && [ "$miss" -gt "$MAX_MISS" ]; then
  echo "FAIL: in-scope MISS count $miss exceeds budget $MAX_MISS" >&2
  echo "      A rule that used to fire has gone quiet, or a file moved out" >&2
  echo "      of the declared scope. Lower the budget when it improves." >&2
  exit 1
fi
exit 0

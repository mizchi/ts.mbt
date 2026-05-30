#!/usr/bin/env bash
# Measure checker issue-count precision across a corpus of TypeScript files.
#
# Runs `tscheck` on every .ts / .tsx file it finds (TypeScript conformance
# corpus when available, bench/realworld fixtures always) and records the
# issue count per file in a JSON baseline file.
#
# Usage:
#   scripts/checker_precision.sh                       # print summary
#   scripts/checker_precision.sh --out baseline.json   # save baseline
#   scripts/checker_precision.sh --compare baseline.json  # diff vs saved
#
# Exit codes:
#   0  no regressions (or just printing / saving)
#   1  regressions detected (issue count changed on one or more files)

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

MODE="print"
BASELINE_FILE=""
COMPARE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)      MODE="save"; BASELINE_FILE="$2"; shift 2 ;;
    --compare)  MODE="compare"; COMPARE_FILE="$2"; shift 2 ;;
    *)          echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# ---- Collect corpus files ----
# Priority: TypeScript conformance corpus (if submodule populated),
# then bench/realworld fixtures, then src/**/*.ts (parser + checker tests).
CORPUS_DIRS=()
if [ -f "typescript/src/compiler/checker.ts" ]; then
  CORPUS_DIRS+=("typescript/src/compiler" "typescript/src/lib" "typescript/src/services")
fi
CORPUS_DIRS+=("bench/realworld" "fixtures" "src/parser" "src/checker")

declare -A COUNTS  # file -> issue_count

total=0
parse_errors=0

for dir in "${CORPUS_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then
    continue
  fi
  while IFS= read -r -d '' f; do
    # Skip ambient-only .d.ts (checker can't report function-body issues)
    [[ "$f" == *.d.ts ]] && continue
    out=$("$TSCHECK" "$f" 2>&1 || true)
    if echo "$out" | grep -q "parse error:"; then
      parse_errors=$((parse_errors + 1))
      COUNTS["$f"]=-1  # -1 = parse error
    else
      # Extract issue count from "checked 1x — N funcs, M issues total"
      issues=$(echo "$out" | grep -oP '\d+ issues' | grep -oP '\d+' || echo 0)
      COUNTS["$f"]=${issues:-0}
    fi
    total=$((total + 1))
  done < <(find "$dir" -maxdepth 3 -name "*.ts" -o -name "*.tsx" | sort -z 2>/dev/null || true)
done

if [ "$total" -eq 0 ]; then
  echo "No TypeScript files found in corpus directories." >&2
  echo "Populate the 'typescript' submodule or add .ts files to bench/realworld." >&2
  exit 0
fi

# ---- Build JSON output ----
json_lines=()
for f in $(echo "${!COUNTS[@]}" | tr ' ' '\n' | sort); do
  c="${COUNTS[$f]}"
  json_lines+=("  $(printf '%q' "$f"): $c")
done
json="{
$(IFS=$'\n'; echo "${json_lines[*]}")
}"

# ---- Mode dispatch ----
case "$MODE" in
  print)
    echo "=== Checker precision sweep ==="
    echo "Files checked : $total"
    echo "Parse errors  : $parse_errors"
    pass=$((total - parse_errors))
    pct=$((pass * 100 / total))
    echo "Parse rate    : $pass/$total (${pct}%)"
    total_issues=0
    for c in "${COUNTS[@]}"; do
      [[ "$c" -gt 0 ]] && total_issues=$((total_issues + c))
    done
    echo "Total issues  : $total_issues"
    ;;

  save)
    mkdir -p "$(dirname "$BASELINE_FILE")"
    echo "$json" > "$BASELINE_FILE"
    echo "Saved baseline: $BASELINE_FILE ($total files)"
    ;;

  compare)
    if [ ! -f "$COMPARE_FILE" ]; then
      echo "Baseline file not found: $COMPARE_FILE" >&2
      exit 1
    fi
    python3 scripts/checker_precision_compare.py "$COMPARE_FILE" <(echo "$json")
    ;;
esac

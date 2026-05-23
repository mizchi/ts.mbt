#!/usr/bin/env bash
# Run a peak-RSS + wall-clock sweep over the TypeScript compiler
# source using the `tscheck` CLI. Requires `hyperfine` and
# `/usr/bin/time` (GNU time, not the shell builtin).
#
# Usage:
#   scripts/bench-memory.sh                   # full sweep
#   scripts/bench-memory.sh --file <path>     # just one file
#
# Output sections:
#   1. Per-file peak RSS (single-shot)
#   2. Memory expansion ratio (input bytes -> peak RSS)
#   3. Parse-only vs parse+check RSS delta
#   4. RSS growth with --iters N
#   5. hyperfine on parse vs full pipeline (5 iterations each)

set -u

BIN="_build/native/release/build/cmd/tscheck/tscheck.exe"
if [[ ! -x "$BIN" ]]; then
  echo "build $BIN first: moon build --target native --release" >&2
  exit 1
fi
if ! command -v /usr/bin/time >/dev/null; then
  echo "needs GNU time (apt install time)" >&2
  exit 1
fi
if ! command -v hyperfine >/dev/null; then
  echo "needs hyperfine (apt install hyperfine)" >&2
  exit 1
fi

FILES=(
  typescript/src/lib/es5.d.ts
  typescript/src/lib/dom.generated.d.ts
  typescript/src/compiler/scanner.ts
  typescript/src/compiler/parser.ts
  typescript/src/compiler/checker.ts
)

# Allow --file <path> override.
if [[ "${1:-}" == "--file" && -n "${2:-}" ]]; then
  FILES=("$2")
fi

echo "================================================================"
echo "1. Per-file peak RSS (single-shot, parse + check)"
echo "================================================================"
printf "%-50s %12s %12s %10s\n" "file" "size (KB)" "elapsed (ms)" "RSS (KB)"
for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    continue
  fi
  size=$(stat -c %s "$f")
  size_kb=$(( size / 1024 ))
  out=$(/usr/bin/time -f "%e %M" "$BIN" "$f" 2>&1 >/dev/null)
  elapsed=$(echo "$out" | awk '{print $1}')
  rss=$(echo "$out" | awk '{print $2}')
  elapsed_ms=$(awk "BEGIN { printf \"%.0f\", $elapsed * 1000 }")
  printf "%-50s %12d %12s %10s\n" "$f" "$size_kb" "$elapsed_ms" "$rss"
done

echo
echo "================================================================"
echo "2. Memory expansion (input KB / peak RSS KB)"
echo "================================================================"
printf "%-50s %12s %10s %12s\n" "file" "input (KB)" "RSS (KB)" "input/RSS"
for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    continue
  fi
  size=$(stat -c %s "$f")
  size_kb=$(( size / 1024 ))
  rss=$(/usr/bin/time -f "%M" "$BIN" "$f" 2>&1 >/dev/null | tail -1)
  ratio=$(awk "BEGIN { printf \"%.2f\", $size_kb / $rss }")
  printf "%-50s %12d %10d %12s\n" "$f" "$size_kb" "$rss" "$ratio"
done

echo
echo "================================================================"
echo "3. Parse-only vs parse+check peak RSS (delta = checker's extra)"
echo "================================================================"
printf "%-50s %12s %12s %12s\n" "file" "parse RSS" "+check RSS" "Δ (KB)"
for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    continue
  fi
  rss_p=$(/usr/bin/time -f "%M" "$BIN" --parse "$f" 2>&1 >/dev/null | tail -1)
  rss_c=$(/usr/bin/time -f "%M" "$BIN"         "$f" 2>&1 >/dev/null | tail -1)
  delta=$(( rss_c - rss_p ))
  printf "%-50s %12d %12d %12d\n" "$f" "$rss_p" "$rss_c" "$delta"
done

echo
echo "================================================================"
echo "4. RSS growth with --iters N (checker.ts)"
echo "================================================================"
TARGET="${FILES[-1]}"
printf "%-8s %14s %14s\n" "iters" "parse RSS(KB)" "+check RSS(KB)"
for n in 1 5 10 20; do
  rss_p=$(/usr/bin/time -f "%M" "$BIN" --parse --iters "$n" "$TARGET" 2>&1 >/dev/null | tail -1)
  rss_c=$(/usr/bin/time -f "%M" "$BIN"         --iters "$n" "$TARGET" 2>&1 >/dev/null | tail -1)
  printf "%-8d %14s %14s\n" "$n" "$rss_p" "$rss_c"
done

echo
echo "================================================================"
echo "5. hyperfine: parse-only vs parse+check (5 iterations each, scanner.ts)"
echo "================================================================"
hyperfine --warmup 2 --runs 10 --shell=none \
  "$BIN --parse --iters 5 typescript/src/compiler/scanner.ts" \
  "$BIN         --iters 5 typescript/src/compiler/scanner.ts"

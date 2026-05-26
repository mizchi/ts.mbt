#!/usr/bin/env bash
# Smoke-test mtsc bundles against real-world ESM packages.
# Each fixture must:
#   1. Parse via `node --check`.
#   2. Execute end-to-end and emit a known marker line.
set -uo pipefail
cd "$(dirname "$0")/../.."
MTSC=_build/native/release/build/cmd/mtsc/mtsc.exe

fixture() {
  local name="$1" entry="$2" expected="$3" flags="${4:---bundle --fold --treeshake --mangle --mangle-properties --minify}"
  $MTSC "$entry" $flags -o "/tmp/rw_${name}.js" 2>/dev/null
  if [ ! -s "/tmp/rw_${name}.js" ]; then
    echo "[$name] BUNDLER CRASH"; return 1
  fi
  if ! node --check "/tmp/rw_${name}.js" 2>/dev/null; then
    echo "[$name] PARSE FAIL"; return 1
  fi
  local size=$(wc -c < "/tmp/rw_${name}.js")
  local out=$(timeout 30 node "/tmp/rw_${name}.js" 2>&1 | head -1)
  if [[ "$out" == *"$expected"* ]]; then
    echo "[$name] OK size=${size}  out=${out:0:60}"
  else
    echo "[$name] WRONG OUTPUT size=${size}  expected=${expected}  got=${out:0:60}"; return 1
  fi
}

fixture "preact"  bench/realworld/preact-entry.ts  "preact vnode: object div x"
fixture "drizzle" bench/realworld/drizzle-entry.ts "drizzle ok: true"
fixture "zod"     bench/realworld/zod-entry.ts     "zod ok: ada 36 1"
fixture "datefns" bench/realworld/datefns-entry.ts "date-fns ok: 2026-04-11 100"
fixture "yjs"     bench/realworld/yjs-entry.ts     "yjs ok: 3 42 6"
fixture "effect"  bench/realworld/effect-entry.ts  "effect ok: 21"
# TypeScript ships only as CJS — bundles cleanly through `import "typescript"`
# (side-effect) and references the runtime `ts` global. Full minify still
# hangs at runtime on the 4MB output, so use the mangle-but-not-minify
# variant which exercises every linker / mangle / treeshake path.
fixture "typescript" bench/realworld/typescript-side.ts "typescript ok:" \
  "--bundle --fold --treeshake --mangle --mangle-properties"

# Hono is loaded via dynamic import (default export pattern) — wrap it.
cat > /tmp/_hono_run.mjs << 'JS'
import app from '/tmp/rw_hono.js';
const r = await app.request('/');
console.log('hono /:', r.status, await r.text());
JS
$MTSC bench/hono-real/entry.ts --bundle --fold --treeshake --mangle --mangle-properties --minify -o /tmp/rw_hono.js 2>/dev/null
if node --check /tmp/rw_hono.js 2>/dev/null; then
  out=$(node /tmp/_hono_run.mjs 2>&1 | head -1)
  size=$(wc -c < /tmp/rw_hono.js)
  if [[ "$out" == *"200"*"hello"* ]]; then
    echo "[hono] OK size=${size}  out=${out:0:60}"
  else
    echo "[hono] WRONG OUTPUT size=${size}  got=${out:0:60}"
  fi
else
  echo "[hono] PARSE FAIL"
fi

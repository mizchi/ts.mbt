#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

verify_moonbit_to_typescript_example() {
  local root="_build/examples/moonbit-to-typescript"

  rm -rf "$root"
  mkdir -p "$root"

  moon run src -- \
    --input examples/counter \
    --out "$root/dist" >/dev/null

  cat > "$root/tsconfig.json" <<'EOF'
{
  "compilerOptions": {
    "strict": true,
    "noEmit": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "baseUrl": ".",
    "lib": ["es2020"]
  },
  "files": [
    "dist/index.d.ts",
    "dist/child/index.d.ts"
  ]
}
EOF

  [ -f "$root/dist/package.json" ]
  [ -f "$root/dist/index.js" ]
  [ -f "$root/dist/index.js.map" ]
  [ -f "$root/dist/AUTOLINK_DIAGNOSTICS.md" ]
  [ ! -f "$root/dist/moon.pkg.json" ]
  [ ! -f "$root/dist/moon.pkg" ]
  [ ! -f "$root/dist/AUTOLINK_FACADE.mbt" ]
  [ ! -f "$root/dist/TSMBT_GLUE.mbt" ]
  grep -F '"name": "@examples/counter"' "$root/dist/package.json" >/dev/null
  grep -F '"import": "./index.js"' "$root/dist/package.json" >/dev/null
  grep -F '"./child": { "types": "./child/index.d.ts" }' "$root/dist/package.json" >/dev/null
  grep -F 'export function create' "$root/dist/index.d.ts" >/dev/null
  grep -F 'export function counter_label' "$root/dist/index.d.ts" >/dev/null
  grep -F 'export interface Item' "$root/dist/child/index.d.ts" >/dev/null
  pnpm exec tsc -p "$root/tsconfig.json" --pretty false
  node --input-type=module - <<'EOF'
const mod = await import("./_build/examples/moonbit-to-typescript/dist/index.js");
const counter = mod.create("demo", { id: 7, name: "item" });
if (mod.counter_label(counter) !== "demo") {
  throw new Error("counter_label returned an unexpected value");
}
if (mod.summarize(counter) !== "demo:item#7") {
  throw new Error("summarize returned an unexpected value");
}
EOF
}

verify_typescript_to_moonbit_example() {
  local root="_build/examples/typescript-to-moonbit"
  local out="$root/dist"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  cp examples/typescript-to-moonbit/runtime/greetings.js "$root/runtime/greetings.js"

  moon run src -- \
    --input examples/typescript-to-moonbit/src/index.d.ts \
    --out "$out" \
    --direction ts-to-mbt \
    --module-spec ../runtime/greetings.js >/dev/null

  cat > "$out/moon.mod.json" <<'EOF'
{
  "name": "examples/typescript_to_moonbit",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$out/bridge_test.mbt" <<'EOF'
test "generated TypeScript to MoonBit example" {
  assert_eq(greet("MoonBit"), "Hello, MoonBit")
  assert_eq(double(21.0), 42.0)
}
EOF

  [ -f "$out/moon.pkg.json" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  grep -F 'pub extern "js" fn greet(name : String) -> String' "$out/bridge.mbt" >/dev/null
  grep -F 'pub extern "js" fn double(value : Double) -> Double' "$out/bridge.mbt" >/dev/null
  moon -C "$out" check --target js
  moon -C "$out" test --target js
}

verify_moonbit_to_typescript_example
verify_typescript_to_moonbit_example

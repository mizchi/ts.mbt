#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

verify_typescript_scaffold_fixture() {
  local root="_build/scaffold_mbti_to_ts"
  local rewrite_map="$repo_root/fixtures/mbti_typescript_package/import-rewrites.json"

  rm -rf "$root"
  mkdir -p "$root"

  moon run src -- emit-typescript-scaffold-from-mbti \
    fixtures/mbti_typescript_package/pkg.generated.mbti \
    "$root/out" \
    "$rewrite_map" >/dev/null

  cat > "$root/demo-debug.d.ts" <<'EOF'
export interface Debug {}
EOF

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
    "out/index.d.ts",
    "out/child/index.d.ts",
    "demo-debug.d.ts"
  ]
}
EOF

  [ -f "$root/out/moon.pkg.json" ]
  [ -f "$root/out/package.json" ]
  [ -f "$root/out/AUTOLINK_DIAGNOSTICS.md" ]
  grep -F '"name": "@demo/pkg"' "$root/out/package.json" >/dev/null
  grep -F '"./child": { "types": "./child/index.d.ts" }' "$root/out/package.json" >/dev/null
  grep -F 'Item::new' "$root/out/AUTOLINK_DIAGNOSTICS.md" >/dev/null
  pnpm exec tsc -p "$root/tsconfig.json" --pretty false
}

verify_typescript_facade_scaffold_fixture() {
  local root="_build/scaffold_mbti_to_ts_facade"

  rm -rf "$root"
  mkdir -p "$root"

  moon run src -- emit-typescript-facade-scaffold-from-mbti \
    fixtures/mbti_typescript_facade_package/pkg.generated.mbti \
    "$root/out" >/dev/null

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
    "out/index.d.ts",
    "out/child/index.d.ts"
  ]
}
EOF

  [ -f "$root/out/moon.pkg.json" ]
  [ -f "$root/out/package.json" ]
  [ -f "$root/out/AUTOLINK_DIAGNOSTICS.md" ]
  [ -f "$root/out/AUTOLINK_FACADE.mbt" ]
  grep -F '"loader_new"' "$root/out/moon.pkg.json" >/dev/null
  grep -F '"loader_load"' "$root/out/moon.pkg.json" >/dev/null
  grep -F 'import {' "$root/out/AUTOLINK_FACADE.mbt" >/dev/null
  grep -F '"demo/facade/child",' "$root/out/AUTOLINK_FACADE.mbt" >/dev/null
  grep -F 'pub fn loader_new(arg0 : @child.Item) -> Loader {' "$root/out/AUTOLINK_FACADE.mbt" >/dev/null
  grep -F 'pub fn loader_load(self : Loader) -> @child.Item {' "$root/out/AUTOLINK_FACADE.mbt" >/dev/null
  grep -F 'export function loader_new(arg0: child.Item): Loader;' "$root/out/index.d.ts" >/dev/null
  grep -F 'export function loader_load(self: Loader): child.Item;' "$root/out/index.d.ts" >/dev/null
  pnpm exec tsc -p "$root/tsconfig.json" --pretty false
}

verify_moonbit_scaffold_fixture() {
  local root="_build/scaffold_ts_to_moonbit"
  local fixture_path="$repo_root/fixtures/bridge_smoke/double-entry.d.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/double.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src -- emit-moonbit-scaffold-from-ts \
    "$fixture_path" "./runtime/double.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/double.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/scaffold_ts_to_moonbit",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated scaffold package smoke" {
  assert_eq(double(21.0), 42.0)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_moonbit_scaffold_external_package_fixture() {
  local root="_build/scaffold_ts_to_moonbit_neverthrow_like"
  local fixture_path="$repo_root/fixtures/resolver/project/types/neverthrow-like-entry.d.ts"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src -- emit-moonbit-scaffold-from-ts \
    "$fixture_path" "./runtime/neverthrow-like.js" "$root" >/dev/null

  cat > "$root/runtime/neverthrow-like.js" <<'EOF'
export function parseUser(input) {
  return {
    value: { id: input, name: `user:${input}` },
    isOk() { return true; },
  };
}

export function fetchUser(id) {
  return {
    promiseValue: { id, name: `user:${id}` },
    isOk() { return true; },
  };
}
EOF

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/scaffold_ts_to_moonbit_neverthrow_like",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated scaffold package with external package types smoke" {
  let _ = parseUser("u1")
  let _ = fetchUser("u2")
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_moonbit_scaffold_namespace_fixture() {
  local root="_build/scaffold_ts_to_moonbit_namespace"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src -- emit-moonbit-scaffold-from-ts \
    fixtures/resolver/project/types/ns-entry.d.ts \
    ./runtime/ns.js \
    "$root" >/dev/null

  cp "$repo_root/fixtures/bridge_smoke/runtime/ns.js" "$root/runtime/ns.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/scaffold_ts_to_moonbit_namespace",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated scaffold package namespace smoke" {
  let _ = get_shapes()
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_moonbit_scaffold_handles_ambiguous_surface() {
  local root="_build/scaffold_ts_to_moonbit_ambiguous"

  rm -rf "$root"
  mkdir -p "$root"

  moon run src -- emit-moonbit-scaffold-from-ts \
    fixtures/resolver/project/types/ambiguous-entry.d.ts \
    ./runtime/ambiguous.js \
    "$root" >/dev/null

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/scaffold_ts_to_moonbit_ambiguous",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  [ -f "$root/SCAFFOLD_DIAGNOSTICS.md" ]
  grep -F 'Shared (ambiguous re-export:' "$root/SCAFFOLD_DIAGNOSTICS.md" >/dev/null
  grep -F 'fixtures/resolver/project/types/ambiguous-a.d.ts' "$root/SCAFFOLD_DIAGNOSTICS.md" >/dev/null
  grep -F 'fixtures/resolver/project/types/ambiguous-b.d.ts' "$root/SCAFFOLD_DIAGNOSTICS.md" >/dev/null
  grep -F 'Unsupported export Shared: ambiguous re-export surface is widened to JSValue' "$root/bridge.mbti" >/dev/null
  grep -F 'Unsupported export Shared: ambiguous re-export surface cannot be bound safely' "$root/bridge.mbt" >/dev/null
  moon -C "$root" check --target js
}

verify_typescript_scaffold_fixture
verify_typescript_facade_scaffold_fixture
verify_moonbit_scaffold_fixture
verify_moonbit_scaffold_external_package_fixture
verify_moonbit_scaffold_namespace_fixture
verify_moonbit_scaffold_handles_ambiguous_surface

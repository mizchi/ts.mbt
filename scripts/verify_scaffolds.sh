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

verify_moonbit_scaffold_rejects_ambiguous_surface() {
  local root="_build/scaffold_ts_to_moonbit_ambiguous"
  local output

  rm -rf "$root"

  output="$(
    moon run src -- emit-moonbit-scaffold-from-ts \
      fixtures/resolver/project/types/ambiguous-entry.d.ts \
      ./runtime/ambiguous.js \
      "$root" 2>&1 || true
  )"

  printf '%s\n' "$output" | grep -F \
    "unsupported exports: Shared (ambiguous re-export:" >/dev/null
  printf '%s\n' "$output" | grep -F \
    "fixtures/resolver/project/types/ambiguous-a.d.ts" >/dev/null
  printf '%s\n' "$output" | grep -F \
    "fixtures/resolver/project/types/ambiguous-b.d.ts" >/dev/null

  if [ -e "$root" ]; then
    echo "Unsupported scaffold entry unexpectedly created output at $root" >&2
    return 1
  fi
}

verify_typescript_scaffold_fixture
verify_moonbit_scaffold_fixture
verify_moonbit_scaffold_external_package_fixture
verify_moonbit_scaffold_namespace_fixture
verify_moonbit_scaffold_rejects_ambiguous_surface

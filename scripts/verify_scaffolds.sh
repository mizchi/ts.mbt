#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

verify_typescript_scaffold_fixture() {
  local root="_build/scaffold_mbti_to_ts"
  local mbti_path="$repo_root/examples/moonbit-to-typescript/counter/pkg.generated.mbti"

  rm -rf "$root"
  mkdir -p "$root"

  moon run src -- emit-typescript-scaffold-from-mbti \
    "$mbti_path" \
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

  [ -f "$root/out/package.json" ]
  [ -f "$root/out/index.js" ]
  [ -f "$root/out/index.js.map" ]
  [ -f "$root/out/AUTOLINK_DIAGNOSTICS.md" ]
  [ ! -f "$root/out/moon.pkg.json" ]
  [ ! -f "$root/out/moon.pkg" ]
  [ ! -f "$root/out/AUTOLINK_FACADE.mbt" ]
  [ ! -f "$root/out/TSMBT_GLUE.mbt" ]
  grep -F '"name": "@examples/counter"' "$root/out/package.json" >/dev/null
  grep -F '"import": "./index.js"' "$root/out/package.json" >/dev/null
  grep -F '"./child": { "types": "./child/index.d.ts" }' "$root/out/package.json" >/dev/null
  grep -F 'Counter::label' "$root/out/AUTOLINK_DIAGNOSTICS.md" >/dev/null
  if grep -F 'counter_label' "$root/out/index.d.ts" >/dev/null; then
    echo "base scaffold should not emit facade declarations" >&2
    exit 1
  fi
  pnpm exec tsc -p "$root/tsconfig.json" --pretty false
  node --input-type=module <<'EOF'
const mod = await import("./_build/scaffold_mbti_to_ts/out/index.js");
const counter = mod.create("demo", { id: 7, name: "item" });
if (mod.summarize(counter) !== "demo:item#7") {
  throw new Error("unexpected summarize output");
}
if ("counter_label" in mod) {
  throw new Error("base scaffold unexpectedly exported counter_label");
}
EOF
}

verify_typescript_facade_scaffold_fixture() {
  local root="_build/scaffold_mbti_to_ts_facade"
  local mbti_path="$repo_root/examples/moonbit-to-typescript/counter/pkg.generated.mbti"

  rm -rf "$root"
  mkdir -p "$root"

  moon run src -- emit-typescript-facade-scaffold-from-mbti \
    "$mbti_path" \
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

  [ -f "$root/out/package.json" ]
  [ -f "$root/out/index.js" ]
  [ -f "$root/out/index.js.map" ]
  [ -f "$root/out/AUTOLINK_DIAGNOSTICS.md" ]
  [ ! -f "$root/out/moon.pkg.json" ]
  [ ! -f "$root/out/moon.pkg" ]
  [ ! -f "$root/out/AUTOLINK_FACADE.mbt" ]
  [ ! -f "$root/out/TSMBT_GLUE.mbt" ]
  grep -F '"name": "@examples/counter"' "$root/out/package.json" >/dev/null
  grep -F '"import": "./index.js"' "$root/out/package.json" >/dev/null
  grep -F 'export function counter_label(self: Counter): string;' "$root/out/index.d.ts" >/dev/null
  pnpm exec tsc -p "$root/tsconfig.json" --pretty false
  node --input-type=module <<'EOF'
const mod = await import("./_build/scaffold_mbti_to_ts_facade/out/index.js");
const counter = mod.create("demo", { id: 7, name: "item" });
if (mod.counter_label(counter) !== "demo") {
  throw new Error("unexpected counter_label output");
}
if (mod.summarize(counter) !== "demo:item#7") {
  throw new Error("unexpected summarize output");
}
EOF
}

write_js_any_stub() {
  local root="$1"

  mkdir -p "$root/_stubs/mizchi_js/core"

  cat > "$root/_stubs/mizchi_js/moon.mod.json" <<'EOF'
{
  "name": "mizchi/js",
  "version": "0.0.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/_stubs/mizchi_js/core/moon.pkg.json" <<'EOF'
{}
EOF

  cat > "$root/_stubs/mizchi_js/core/core.mbt" <<'EOF'
///|
#external
pub type Any
EOF
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

verify_moonbit_scaffold_react_like_jsx_fixture() {
  local root="_build/scaffold_ts_to_moonbit_react_like_jsx"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src -- emit-moonbit-scaffold-from-ts \
    fixtures/resolver/project/types/export-as-namespace-jsx-entry.d.ts \
    ./runtime/react-like.js \
    "$root" >/dev/null

  write_js_any_stub "$root"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/scaffold_ts_to_moonbit_react_like_jsx",
  "version": "0.1.0",
  "deps": {
    "mizchi/js": { "path": "./_stubs/mizchi_js" }
  },
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/runtime/react-like.js" <<'EOF'
export default {
  createElement(tag) {
    return { kind: tag };
  }
};
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated react-like jsx scaffold smoke" {
  let _ = createElement("badge")
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_moonbit_scaffold_react_package_fixture() {
  local root="_build/scaffold_ts_to_moonbit_react_package"

  rm -rf "$root"
  mkdir -p "$root/node_modules"

  moon run src -- emit-moonbit-scaffold-from-ts \
    fixtures/resolver/project/node_modules/react/index.d.ts \
    react \
    "$root" >/dev/null

  write_js_any_stub "$root"
  cp -R "$repo_root/fixtures/resolver/project/node_modules/react" "$root/node_modules/react"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/scaffold_ts_to_moonbit_react_package",
  "version": "0.1.0",
  "deps": {
    "mizchi/js": { "path": "./_stubs/mizchi_js" }
  },
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
extern "js" fn test_dom_attributes() -> DOMAttributes =
  #| () => ({ id: "app" })

extern "js" fn test_button_attributes() -> ButtonHTMLAttributes =
  #| () => ({ disabled: true })

extern "js" fn test_function_component() -> FunctionComponent =
  #| () => (props) => ({ type: "component", props, key: null })

extern "js" fn test_forward_ref_render() -> @js.Any =
  #| () => (props, ref) => ({ type: "forward", props, ref, key: null })

extern "js" fn test_ref() -> Ref =
  #| () => ({ current: null })

extern "js" fn test_children() -> Array[JSValue] =
  #| () => []

test "generated React package scaffold smoke" {
  let element = createElement(
    "div",
    Some(test_dom_attributes()),
    test_children(),
  )
  let _ = cloneElement(element, Some(test_dom_attributes()), test_children())
  let _ = forwardRef(test_forward_ref_render())
  let _ = memo(test_function_component(), None)
  let _ = normalizeProps(test_button_attributes())
  let _ = useComponentRef(test_ref())
  let _ = get_default()
}
EOF

  grep -F 'pub fn createElement(type_ : String, props : DOMAttributes?, children : Array[JSValue]) -> ReactElement' "$root/bridge.mbt" >/dev/null
  grep -F 'pub fn cloneElement(element : ReactElement, props : DOMAttributes?, children : Array[JSValue]) -> ReactElement' "$root/bridge.mbt" >/dev/null
  grep -F '#external' "$root/bridge.mbt" >/dev/null
  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_moonbit_scaffold_react_jsx_runtime_fixture() {
  local root="_build/scaffold_ts_to_moonbit_react_jsx_runtime"

  rm -rf "$root"
  mkdir -p "$root/node_modules"

  moon run src -- emit-moonbit-scaffold-from-ts \
    fixtures/resolver/project/node_modules/react/jsx-runtime.d.ts \
    react/jsx-runtime \
    "$root" >/dev/null

  write_js_any_stub "$root"
  cp -R "$repo_root/fixtures/resolver/project/node_modules/react" "$root/node_modules/react"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/scaffold_ts_to_moonbit_react_jsx_runtime",
  "version": "0.1.0",
  "deps": {
    "mizchi/js": { "path": "./_stubs/mizchi_js" }
  },
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
extern "js" fn test_button_attributes() -> ButtonHTMLAttributes =
  #| () => ({ disabled: true })

test "generated jsx runtime scaffold smoke" {
  let _ = jsx("button", test_button_attributes(), None)
  let _ = jsxs("button", test_button_attributes(), None)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_moonbit_scaffold_react_jsx_dev_runtime_fixture() {
  local root="_build/scaffold_ts_to_moonbit_react_jsx_dev_runtime"

  rm -rf "$root"
  mkdir -p "$root/node_modules"

  moon run src -- emit-moonbit-scaffold-from-ts \
    fixtures/resolver/project/node_modules/react/jsx-dev-runtime.d.ts \
    react/jsx-dev-runtime \
    "$root" >/dev/null

  write_js_any_stub "$root"
  cp -R "$repo_root/fixtures/resolver/project/node_modules/react" "$root/node_modules/react"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/scaffold_ts_to_moonbit_react_jsx_dev_runtime",
  "version": "0.1.0",
  "deps": {
    "mizchi/js": { "path": "./_stubs/mizchi_js" }
  },
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
extern "js" fn test_element_type() -> ElementType =
  #| () => "badge"

extern "js" fn test_key() -> Key =
  #| () => "key"

extern "js" fn test_props() -> JSValue =
  #| () => ({ label: "Badge" })

extern "js" fn test_source() -> JSXSource =
  #| () => ({ fileName: "x.tsx", lineNumber: 1 })

test "generated jsx dev runtime scaffold smoke" {
  let _ = jsxDEV(
    test_element_type(),
    test_props(),
    Some(test_key()),
    false,
    Some(test_source()),
    None,
  )
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_moonbit_scaffold_hono_jsx_fixture() {
  local root="_build/scaffold_ts_to_moonbit_hono_jsx"

  rm -rf "$root"
  mkdir -p "$root/node_modules"

  moon run src -- emit-moonbit-scaffold-from-ts \
    fixtures/resolver/project/node_modules/hono/dist/types/jsx/index.d.ts \
    hono/jsx \
    "$root" >/dev/null

  write_js_any_stub "$root"
  cp -R "$repo_root/fixtures/resolver/project/node_modules/hono" "$root/node_modules/hono"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/scaffold_ts_to_moonbit_hono_jsx",
  "version": "0.1.0",
  "deps": {
    "mizchi/js": { "path": "./_stubs/mizchi_js" }
  },
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
extern "js" fn test_button_attributes() -> ButtonAttributes =
  #| () => ({ disabled: true })

extern "js" fn test_component() -> @js.Any =
  #| () => (props) => ({ tag: "button", props })

test "generated Hono JSX scaffold smoke" {
  let _ = jsx("button", test_button_attributes())
  let _ = memo(test_component())
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_moonbit_scaffold_hono_options_fixture() {
  local root="_build/scaffold_ts_to_moonbit_hono_options"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src -- emit-moonbit-scaffold-from-ts \
    fixtures/resolver/project/types/hono-options-entry.d.ts \
    ./runtime/hono.js \
    "$root" >/dev/null

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/scaffold_ts_to_moonbit_hono_options",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/runtime/hono.js" <<'EOF'
export class Hono {
  constructor(options) {
    this.options = options;
  }
}

export function createApp(options) {
  return new Hono(options);
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
extern "js" fn test_hono_options() -> HonoOptions =
  #| () => ({ strict: true })

test "generated hono options scaffold smoke" {
  let _ = new_hono(None)
  let _ = createApp(test_hono_options())
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

  write_js_any_stub "$root"
  cp "$repo_root/fixtures/bridge_smoke/runtime/ns.js" "$root/runtime/ns.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/scaffold_ts_to_moonbit_namespace",
  "version": "0.1.0",
  "deps": {
    "mizchi/js": { "path": "./_stubs/mizchi_js" }
  },
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

  write_js_any_stub "$root"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/scaffold_ts_to_moonbit_ambiguous",
  "version": "0.1.0",
  "deps": {
    "mizchi/js": { "path": "./_stubs/mizchi_js" }
  },
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
verify_moonbit_scaffold_react_like_jsx_fixture
verify_moonbit_scaffold_react_package_fixture
verify_moonbit_scaffold_react_jsx_runtime_fixture
verify_moonbit_scaffold_react_jsx_dev_runtime_fixture
verify_moonbit_scaffold_hono_jsx_fixture
verify_moonbit_scaffold_hono_options_fixture
verify_moonbit_scaffold_namespace_fixture
verify_moonbit_scaffold_handles_ambiguous_surface

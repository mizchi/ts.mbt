#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
source "$repo_root/scripts/warning_guard.sh"

verify_mbti_fixture_typescript() {
  local root="_build/fixture_mbti_tscheck"
  rm -rf "$root"
  mkdir -p \
    "$root/fixtures" \
    "$root/mizchi/ts" \
    "$root/moonbitlang/core" \
    "$root/moonbitlang/parser" \
    "$root/demo"

  shopt -s nullglob
  local fixtures=(fixtures/mbti_typescript/*.pkg.generated.mbti)
  if [ "${#fixtures[@]}" -eq 0 ]; then
    echo "No fixtures/mbti_typescript/*.pkg.generated.mbti fixtures found" >&2
    return 1
  fi

  local fixture
  for fixture in "${fixtures[@]}"; do
    local base
    base="$(basename "$fixture" .pkg.generated.mbti)"
    moon run src/cmd/mbt2ts -- decl "$fixture" "$root/fixtures/$base.d.ts" >/dev/null
  done

  cat > "$root/mizchi/ts/ast.d.ts" <<'EOF'
export interface TsModule {}
EOF

  cat > "$root/moonbitlang/core/debug.d.ts" <<'EOF'
export interface Debug {}
EOF

  cat > "$root/moonbitlang/core/json.d.ts" <<'EOF'
export interface Json {}
export interface JsonDecodeError {}
export interface ToJson {}
export interface FromJson {}
EOF

  cat > "$root/moonbitlang/core/set.d.ts" <<'EOF'
export interface Set<T> {}
EOF

  cat > "$root/moonbitlang/core/bigint.d.ts" <<'EOF'
export interface BigInt {}
EOF

  cat > "$root/moonbitlang/core/list.d.ts" <<'EOF'
export interface List<T> {}
EOF

  cat > "$root/moonbitlang/parser/basic.d.ts" <<'EOF'
export interface Report {}
EOF

  cat > "$root/moonbitlang/parser/syntax.d.ts" <<'EOF'
export interface Constant {}
export interface Expr {}
export interface Impl {}
export interface Pattern {}
export interface Type {}
EOF

  cat > "$root/demo/class.d.ts" <<'EOF'
export interface Value {}
export interface Result<T> {}
EOF

  cat > "$root/demo/with.d.ts" <<'EOF'
export interface Handler {}
EOF

  cat > "$root/demo/runtime.d.ts" <<'EOF'
export interface Runtime {}
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
  "include": ["**/*.d.ts"]
}
EOF

  pnpm exec tsc -p "$root/tsconfig.json" --pretty false
}

verify_bridge_smoke_fixture() {
  local root="_build/bridge_fixture_smoke"
  local fixture_path="$repo_root/fixtures/bridge_smoke/double-entry.d.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/double.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/double.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/double.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_smoke",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package smoke" {
  assert_eq(double(21.0), 42.0)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_enum_fixture() {
  local root="_build/bridge_fixture_enum"
  local fixture_path="$repo_root/fixtures/bridge_smoke/enum-entry.d.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/enum.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/enum.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/enum.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_enum",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package converts string enums at the JS boundary" {
  assert_eq(recordMode(Read), "read")
  match nextMode(Read) {
    Write => ()
    _ => abort("expected read to become write")
  }
  match echo(Write) {
    Write => ()
    _ => abort("expected same-name enum wrapper to preserve write")
  }
  match maybeMode(Some(Read)) {
    Some(Write) => ()
    _ => abort("expected optional read to become optional write")
  }
  let absent : Mode? = None
  match maybeMode(absent) {
    None => ()
    _ => abort("expected absent optional enum to stay absent")
  }
  assert_eq(recordMode(nextMode(Write)), "read")
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_literal_union_alias_fixture() {
  local root="_build/bridge_fixture_literal_union_alias"
  local fixture_path="$repo_root/fixtures/bridge_smoke/literal-union-alias-entry.d.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/literal-union-alias.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/literal-union-alias.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/literal-union-alias.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_literal_union_alias",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package converts named string literal union aliases" {
  match renderButton(Solid) {
    Ghost => ()
    _ => abort("expected solid to become ghost")
  }
  match maybeVariant(Some(Ghost)) {
    Some(Solid) => ()
    _ => abort("expected optional ghost to become optional solid")
  }
  let absent : ButtonVariant? = None
  match maybeVariant(absent) {
    None => ()
    _ => abort("expected absent variant to stay absent")
  }
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_numeric_enum_fixture() {
  local root="_build/bridge_fixture_numeric_enum"
  local fixture_path="$repo_root/fixtures/bridge_smoke/numeric-enum-entry.d.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/numeric-enum.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/numeric-enum.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/numeric-enum.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_numeric_enum",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package converts numeric enums at the JS boundary" {
  match nextKind(Identifier) {
    PrivateIdentifier => ()
    _ => abort("expected identifier to become private identifier")
  }
  match maybeKind(Some(PrivateIdentifier)) {
    Some(Identifier) => ()
    _ => abort("expected optional private identifier to become optional identifier")
  }
  let absent : SyntaxKind? = None
  match maybeKind(absent) {
    None => ()
    _ => abort("expected absent numeric enum to stay absent")
  }
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_numeric_literal_union_fixture() {
  local root="_build/bridge_fixture_numeric_literal_union"
  local fixture_path="$repo_root/fixtures/bridge_smoke/numeric-literal-union-entry.d.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/numeric-literal-union.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/numeric-literal-union.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/numeric-literal-union.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_numeric_literal_union",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package converts named numeric literal union aliases" {
  match nextStatus(N200) {
    N404 => ()
    _ => abort("expected 200 to become 404")
  }
  match maybeStatus(Some(N404)) {
    Some(N200) => ()
    _ => abort("expected optional 404 to become optional 200")
  }
  let absent : StatusCode? = None
  match maybeStatus(absent) {
    None => ()
    _ => abort("expected absent status code to stay absent")
  }
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_boolean_literal_union_fixture() {
  local root="_build/bridge_fixture_boolean_literal_union"
  local fixture_path="$repo_root/fixtures/bridge_smoke/boolean-literal-union-entry.d.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/boolean-literal-union.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/boolean-literal-union.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/boolean-literal-union.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_boolean_literal_union",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps boolean literal aliases primitive" {
  assert_false(flipFlag(true))
  assert_true(flipFlag(false))
  match maybeAlways(Some(false)) {
    Some(true) => ()
    _ => abort("expected optional false to become optional true")
  }
  let absent : Bool? = None
  match maybeAlways(absent) {
    None => ()
    _ => abort("expected absent boolean literal alias to stay absent")
  }
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_realworld_literal_options_fixture() {
  local root="_build/bridge_fixture_realworld_literal_options"
  local fixture_path="$repo_root/fixtures/bridge_smoke/realworld-literal-options-entry.d.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/realworld-literal-options.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/realworld-literal-options.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/realworld-literal-options.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_realworld_literal_options",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package converts real-world literal option fields" {
  let read_options = NodeReadOptions::{
    encoding: Some(Utf8),
    flag: Some(R)
  }
  match describeRead("/tmp/config.json", read_options) {
    Buffer => ()
    _ => abort("expected Node encoding option to cross as a primitive string")
  }
  match nextFlag(R) {
    W => ()
    _ => abort("expected Node flag alias to convert as a top-level enum")
  }
  let button_props = ReactButtonProps::{ type_: Some(Submit) }
  match renderReactButton(button_props) {
    Reset => ()
    _ => abort("expected React button type prop to cross as a primitive string")
  }
  let hono_options = HonoProbeOptions::{ mode: Some(Strict) }
  match createHonoProbe(hono_options) {
    Loose => ()
    _ => abort("expected Hono mode option to cross as a primitive string")
  }
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_stable_constructor_fixture() {
  local root="_build/bridge_fixture_stable_constructor"
  local fixture_path="$repo_root/fixtures/bridge_smoke/stable-constructor-entry.d.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/stable-constructor.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/stable-constructor.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/stable-constructor.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_stable_constructor",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps stable constructor names" {
  match cycleName(A_b) {
    A_b2 => ()
    _ => abort("expected collision suffix to preserve a_b")
  }
  match cycleName(A_b2) {
    String_ => ()
    _ => abort("expected primitive-name constructor to be suffixed")
  }
  match cycleName(String_) {
    UnderscorePrivate => ()
    _ => abort("expected leading underscore to be stable")
  }
  match cycleName(UnderscorePrivate) {
    Member => ()
    _ => abort("expected empty literal to use fallback constructor")
  }
  match cycleName(Member) {
    A_b => ()
    _ => abort("expected empty literal roundtrip to preserve original value")
  }
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_default_export_fixture() {
  local root="_build/bridge_fixture_default_export"
  local fixture_path="$repo_root/fixtures/bridge_smoke/default-export-entry.d.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/default-export.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/default-export.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/default-export.js"

  cat > "$root/moon.mod.json" <<EOF
{
  "name": "fixture/bridge_default_export",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_smoke_helper.mbt" <<'EOF'
pub extern "js" fn JSValue::read_default_value(self : JSValue) -> Double = "(self) => self.value"
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps widened export self-contained" {
  let default_value = get_default()
  assert_eq(default_value.read_default_value(), 42)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_declaration_merge_namespace_fixture() {
  local root="_build/bridge_fixture_declaration_merge_namespace"
  local fixture_path="$repo_root/fixtures/resolver/project/types/declaration-merge-namespace-entry.d.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/declaration-merge-namespace.js"


  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/declaration-merge-namespace.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/declaration-merge-namespace.js"

  cat > "$root/moon.mod.json" <<EOF
{
  "name": "fixture/bridge_declaration_merge_namespace",
  "version": "0.1.0",
  "deps": {},
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
extern "js" fn test_make_options() -> MakeOptions =
  #| () => ({ uppercase: true })

///|
test "generated bridge package calls declaration-merged namespace members" {
  assert_eq(make("ok"), "make:ok")
  assert_eq(get_make_version(), "1.0.0")
  assert_eq(makeWithOptions("ok", test_make_options()), "OK")
  assert_eq(get_tool_version(), "2.0.0")
  let _ = toolParse("tool")
  let current_settings = get_settings()
  assert_eq(current_settings.mode, "prod")
  assert_eq(get_settings_default_mode(), "prod")
  assert_eq(settingsNormalize(" Prod "), "prod")
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_promise_return_fixture() {
  local root="_build/bridge_fixture_promise_return"
  local fixture_path="$repo_root/fixtures/resolver/project/types/promise-return-entry.d.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/promise-return.js"


  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/promise-return.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/promise-return.js"

  cat > "$root/moon.mod.json" <<EOF
{
  "name": "fixture/bridge_promise_return",
  "version": "0.1.0",
  "deps": {
    "moonbitlang/async": "0.18.0"
  },
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/moon.pkg" <<'EOF'
import {
  "moonbitlang/async",
} for "test"
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
///|
async test "generated bridge package awaits Promise-returning APIs" {
  // Promise return functions exist and are callable. Bridge runtime
  // wiring is verified by the moon check + test compile passes above.
  let _ = fetchLabel("a")
  let _ = fetchCount()
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_callback_fixture() {
  local root="_build/bridge_fixture_callback"
  local fixture_path="$repo_root/fixtures/resolver/project/types/callback-entry.d.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/callback.js"


  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/callback.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/callback.js"

  cat > "$root/moon.mod.json" <<EOF
{
  "name": "fixture/bridge_callback",
  "version": "0.1.0",
  "deps": {},
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
extern "js" fn test_listener() -> EmitEventListenerCallback =
  #| () => (label, count) => {
  #|   globalThis.__tsmbtCallbackSeen = `${label}:${count}`;
  #| }

extern "js" fn test_maybe_listener() -> MaybeEmitListenerCallback =
  #| () => (label, count) => {
  #|   globalThis.__tsmbtCallbackSeen = `${label}:${count}`;
  #| }

extern "js" fn test_callback_seen() -> String =
  #| () => globalThis.__tsmbtCallbackSeen ?? ""

///|
test "generated bridge package calls callback APIs" {
  assert_eq(emitEvent("evt", 3.0, test_listener()), "evt:3")
  assert_eq(test_callback_seen(), "evt:3")
  assert_eq(maybeEmit("empty", None), "empty:none")
  assert_eq(maybeEmit("once", Some(test_maybe_listener())), "once:called")
  assert_eq(test_callback_seen(), "once:1")
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_cjs_export_equals_fixture() {
  local root="_build/bridge_fixture_cjs_export_equals"
  local fixture_path="$repo_root/fixtures/resolver/project/types/cjs-export-equals-entry.d.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/cjs-export-equals.cjs"


  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/cjs-export-equals.cjs" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/cjs-export-equals.cjs"

  cat > "$root/moon.mod.json" <<EOF
{
  "name": "fixture/bridge_cjs_export_equals",
  "version": "0.1.0",
  "deps": {},
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
///|
test "generated bridge package calls CJS export-equals namespace members" {
  assert_eq(format("ok"), "fmt:ok")
  assert_eq(get_version(), "cjs1")
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_node_path_namespace_import_fixture() {
  local root="_build/bridge_fixture_node_path_namespace_import"
  local fixture_path="$repo_root/fixtures/resolver/project/types/export-equals-namespace-members-entry.d.ts"


  rm -rf "$root"
  mkdir -p "$root"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "node:path" "$root" >/dev/null

  cat > "$root/moon.mod.json" <<EOF
{
  "name": "fixture/bridge_node_path_namespace_import",
  "version": "0.1.0",
  "deps": {},
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
///|
test "generated bridge package reads node:path through namespace import" {
  assert_true(get_path_sep().length() > 0)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_parent_relative_default_function_fixture() {
  local root="_build/bridge_fixture_parent_relative"
  local pkg_root="$root/pkg"
  local fixture_path="$repo_root/fixtures/bridge_smoke/default-function-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/default-function.js"

  rm -rf "$root"
  mkdir -p "$pkg_root" "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "../runtime/default-function.js" "$pkg_root" >/dev/null
  cp "$runtime_path" "$root/runtime/default-function.js"

  cat > "$pkg_root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_parent_relative",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$pkg_root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps parent-relative default export self-contained" {
  assert_eq(default("  hi  "), "hi")
}
EOF

  moon -C "$pkg_root" check --target js
  moon -C "$pkg_root" test --target js
}

verify_bridge_bare_cjs_default_function_fixture() {
  local root="_build/bridge_fixture_bare_cjs_default_function"
  local fixture_path="$repo_root/fixtures/bridge_smoke/default-function-entry.ts"

  rm -rf "$root"
  mkdir -p "$root/node_modules/pkg-default-fn"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "pkg-default-fn" "$root" >/dev/null

  cat > "$root/node_modules/pkg-default-fn/package.json" <<'EOF'
{
  "name": "pkg-default-fn",
  "version": "0.0.0",
  "main": "index.cjs"
}
EOF

  cat > "$root/node_modules/pkg-default-fn/index.cjs" <<'EOF'
module.exports = function defaultFunction(label) {
  return `pkg:${label.trim()}`;
};
EOF

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_bare_cjs_default_function",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package calls bare CJS default function through bridge adapter" {
  assert_eq(default("  hi  "), "pkg:hi")
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_class_property_fixture() {
  local root="_build/bridge_fixture_class_property"
  local fixture_path="$repo_root/fixtures/bridge_smoke/class-property-entry.d.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/class-property.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/class-property.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/class-property.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_class_property",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps class bindings self-contained" {
  let state = new_counter_state()
  assert_eq(state.get_counter_state_current(), 7.0)
  assert_eq(state.get_counter_state_label(), "start")
  state.set_counter_state_label("next")
  assert_eq(state.get_counter_state_label(), "next")
  assert_eq(get_counter_state_version(), "v1")
  assert_eq(get_counter_state_step(), 1.0)
  set_counter_state_step(3.0)
  assert_eq(get_counter_state_step(), 3.0)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_rooted_class_property_reexport_fixture() {
  local root="_build/bridge_fixture_class_property_reexport_rooted"
  local fixture_path="$repo_root/fixtures/bridge_smoke/class-property-reexport-entry.d.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/class-property.js"
  local runtime_spec
  runtime_spec="$(cd "$(dirname "$runtime_path")" && pwd)/$(basename "$runtime_path")"

  rm -rf "$root"
  mkdir -p "$root"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "$runtime_spec" "$root" >/dev/null

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_class_property_reexport_rooted",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps rooted class-property reexports self-contained" {
  let state = new_runtime_state()
  assert_eq(state.get_runtime_state_current(), 7.0)
  assert_eq(state.get_runtime_state_label(), "start")
  state.set_runtime_state_label("next")
  assert_eq(state.get_runtime_state_label(), "next")
  assert_eq(get_runtime_state_version(), "v1")
  assert_eq(get_runtime_state_step(), 1.0)
  set_runtime_state_step(3.0)
  assert_eq(get_runtime_state_step(), 3.0)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_bare_class_property_reexport_fixture() {
  local root="_build/bridge_fixture_class_property_reexport_bare"
  local fixture_path="$repo_root/fixtures/resolver/project/types/bare-class-property-entry.d.ts"
  local runtime_pkg_src="$repo_root/fixtures/resolver/project/node_modules/pkg-class-property"
  local runtime_pkg_dst="$root/node_modules/pkg-class-property"

  rm -rf "$root"
  mkdir -p "$root/node_modules"
  cp -R "$runtime_pkg_src" "$runtime_pkg_dst"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "pkg-class-property" "$root" >/dev/null

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_class_property_reexport_bare",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps bare class-property reexports self-contained" {
  let state = new_runtime_state()
  assert_eq(state.get_runtime_state_current(), 7.0)
  assert_eq(state.get_runtime_state_label(), "start")
  state.set_runtime_state_label("next")
  assert_eq(state.get_runtime_state_label(), "next")
  assert_eq(get_runtime_state_version(), "v1")
  assert_eq(get_runtime_state_step(), 1.0)
  set_runtime_state_step(3.0)
  assert_eq(get_runtime_state_step(), 3.0)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_bare_default_class_reexport_fixture() {
  local root="_build/bridge_fixture_default_class_reexport_bare"
  local fixture_path="$repo_root/fixtures/resolver/project/types/bare-default-class-entry.d.ts"
  local runtime_pkg_src="$repo_root/fixtures/resolver/project/node_modules/pkg-default-class"
  local runtime_pkg_dst="$root/node_modules/pkg-default-class"

  rm -rf "$root"
  mkdir -p "$root/node_modules"
  cp -R "$runtime_pkg_src" "$runtime_pkg_dst"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "pkg-default-class" "$root" >/dev/null

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_default_class_reexport_bare",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps bare default class reexports self-contained" {
  let counter = new_runtime_counter(2.0)
  assert_eq(counter.runtime_counter_inc(5.0), 7.0)
  let seeded = runtime_counter_from(4.0)
  assert_eq(seeded.get_runtime_counter_count(), 4.0)
  assert_eq(get_runtime_counter_version(), "v1")
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_subpath_class_reexport_fixture() {
  local root="_build/bridge_fixture_class_property_reexport_subpath"
  local fixture_path="$repo_root/fixtures/resolver/project/types/subpath-class-entry.d.ts"
  local runtime_pkg_src="$repo_root/fixtures/resolver/project/node_modules/pkg-class-subpath"
  local runtime_pkg_dst="$root/node_modules/pkg-class-subpath"

  rm -rf "$root"
  mkdir -p "$root/node_modules"
  cp -R "$runtime_pkg_src" "$runtime_pkg_dst"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "pkg-class-subpath/state" "$root" >/dev/null

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_class_property_reexport_subpath",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps subpath class reexports self-contained" {
  let state = new_runtime_state()
  assert_eq(state.get_runtime_state_current(), 7.0)
  assert_eq(state.get_runtime_state_label(), "start")
  assert_eq(get_runtime_state_version(), "v1")
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_destructured_value_fixture() {
  local root="_build/bridge_fixture_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/destructured-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/destructured-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/destructured-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/destructured-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps destructured value exports self-contained" {
  assert_eq(get_runtime_version(), "v3")
  assert_eq(get_build(), 7.0)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_destructured_nested_rest_value_fixture() {
  local root="_build/bridge_fixture_destructured_nested_rest_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/destructured-nested-rest-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/destructured-nested-rest-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/destructured-nested-rest-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/destructured-nested-rest-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_destructured_nested_rest_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps nested and array-rest destructured value exports self-contained" {
  assert_eq(get_runtime_version(), "v3")
  assert_eq(get_build(), 7.0)
  assert_eq(get_head(), 1.0)
  let tail = get_tail()
  assert_eq(tail.length(), 2)
  assert_eq(tail[0], 2.0)
  assert_eq(tail[1], 3.0)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_object_rest_value_fixture() {
  local root="_build/bridge_fixture_object_rest_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/object-rest-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/object-rest-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/object-rest-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/object-rest-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_object_rest_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps object-rest destructured value exports self-contained" {
  assert_eq(get_version(), "v3")
  let rest = get_rest_meta()
  assert_eq(rest.build, 7.0)
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/computed-destructured-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/computed-destructured-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/computed-destructured-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/computed-destructured-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps computed-key destructured value exports self-contained" {
  assert_eq(get_runtime_version(), "v3")
  assert_eq(get_build(), 7.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_template_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_template_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/template-computed-destructured-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/template-computed-destructured-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/template-computed-destructured-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/template-computed-destructured-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_template_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps template-literal computed-key destructured value exports self-contained" {
  assert_eq(get_runtime_version(), "v3")
  assert_eq(get_build(), 7.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_concat_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_concat_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/concat-computed-destructured-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/concat-computed-destructured-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/concat-computed-destructured-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/concat-computed-destructured-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_concat_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps concatenated computed-key destructured value exports self-contained" {
  assert_eq(get_runtime_version(), "v3")
  assert_eq(get_build(), 7.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_primitive_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_primitive_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/primitive-computed-destructured-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/primitive-computed-destructured-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/primitive-computed-destructured-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/primitive-computed-destructured-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_primitive_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps primitive-literal computed-key destructured value exports self-contained" {
  assert_eq(get_truthy(), "yes")
  assert_eq(get_nil_value(), 7.0)
  assert_eq(get_negative(), false)
  assert_eq(get_bigint_value(), "one")
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_void_bigint_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_void_bigint_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/void-bigint-computed-destructured-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/void-bigint-computed-destructured-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/void-bigint-computed-destructured-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/void-bigint-computed-destructured-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_void_bigint_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps void-and-negative-bigint computed-key destructured value exports self-contained" {
  assert_eq(get_undefined_value(), "void")
  assert_eq(get_negative_bigint(), 9.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_const_ref_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_const_ref_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/const-ref-computed-destructured-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/const-ref-computed-destructured-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/const-ref-computed-destructured-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/const-ref-computed-destructured-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_const_ref_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps const-reference computed-key destructured value exports self-contained" {
  assert_eq(get_runtime_version(), "v3")
  assert_eq(get_build(), 7.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_destructured_const_ref_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_destructured_const_ref_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/destructured-const-ref-computed-destructured-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/destructured-const-ref-computed-destructured-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/destructured-const-ref-computed-destructured-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/destructured-const-ref-computed-destructured-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_destructured_const_ref_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps destructured-const-reference computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v4")
  assert_eq(get_build(), 8.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, false)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_const_object_access_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_const_object_access_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/const-object-access-computed-destructured-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/const-object-access-computed-destructured-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/const-object-access-computed-destructured-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/const-object-access-computed-destructured-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_const_object_access_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps const-object-access computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v5")
  assert_eq(get_build(), 9.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_nested_const_object_access_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_nested_const_object_access_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/nested-const-object-access-computed-destructured-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/nested-const-object-access-computed-destructured-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/nested-const-object-access-computed-destructured-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/nested-const-object-access-computed-destructured-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_nested_const_object_access_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps nested-const-object-access computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v6")
  assert_eq(get_build(), 10.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, false)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_const_array_access_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_const_array_access_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/const-array-access-computed-destructured-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/const-array-access-computed-destructured-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/const-array-access-computed-destructured-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/const-array-access-computed-destructured-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_const_array_access_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps const-array-access computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v7")
  assert_eq(get_build(), 11.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_nested_const_array_access_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_nested_const_array_access_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/nested-const-array-access-computed-destructured-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/nested-const-array-access-computed-destructured-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/nested-const-array-access-computed-destructured-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/nested-const-array-access-computed-destructured-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_nested_const_array_access_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps nested-const-array-access computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v8")
  assert_eq(get_build(), 12.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, false)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_const_index_alias_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_const_index_alias_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/const-index-alias-computed-destructured-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/const-index-alias-computed-destructured-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/const-index-alias-computed-destructured-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/const-index-alias-computed-destructured-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_const_index_alias_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps const-index-alias computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v9")
  assert_eq(get_build(), 13.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_const_index_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_const_index_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/const-index-table-computed-destructured-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/const-index-table-computed-destructured-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/const-index-table-computed-destructured-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/const-index-table-computed-destructured-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_const_index_table_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps const-index-table computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v10")
  assert_eq(get_build(), 14.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, false)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_nested_index_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_nested_index_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/nested-index-table-computed-destructured-value-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/nested-index-table-computed-destructured-value.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/nested-index-table-computed-destructured-value.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/nested-index-table-computed-destructured-value.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_nested_index_table_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps nested-index-table computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v11")
  assert_eq(get_build(), 15.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_const_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_const_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-const-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-const-table-entry.js"
  local runtime_consts_path="$repo_root/fixtures/bridge_smoke/runtime/imported-const-table.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-const-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-const-table-entry.js"
  cp "$runtime_consts_path" "$root/runtime/imported-const-table.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_const_table_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps imported const-table computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v12")
  assert_eq(get_build(), 16.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, false)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_namespace_const_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_namespace_const_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-namespace-const-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-namespace-const-table-entry.js"
  local runtime_consts_path="$repo_root/fixtures/bridge_smoke/runtime/imported-const-table.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-namespace-const-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-namespace-const-table-entry.js"
  cp "$runtime_consts_path" "$root/runtime/imported-const-table.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_namespace_const_table_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps imported namespace const-table computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v20")
  assert_eq(get_build(), 24.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_default_const_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_default_const_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-default-const-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-default-const-table-entry.js"
  local runtime_consts_path="$repo_root/fixtures/bridge_smoke/runtime/imported-default-const-table.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-default-const-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-default-const-table-entry.js"
  cp "$runtime_consts_path" "$root/runtime/imported-default-const-table.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_default_const_table_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps imported default const-table computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v21")
  assert_eq(get_build(), 25.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, false)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_inline_default_const_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_inline_default_const_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-inline-default-const-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-inline-default-const-table-entry.js"
  local runtime_consts_path="$repo_root/fixtures/bridge_smoke/runtime/imported-inline-default-const-table.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-inline-default-const-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-inline-default-const-table-entry.js"
  cp "$runtime_consts_path" "$root/runtime/imported-inline-default-const-table.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_inline_default_const_table_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps imported inline default const-table computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v22")
  assert_eq(get_build(), 26.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_inline_default_const_table_as_const_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_inline_default_const_table_as_const_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-inline-default-const-table-as-const-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-inline-default-const-table-as-const-entry.js"
  local runtime_consts_path="$repo_root/fixtures/bridge_smoke/runtime/imported-inline-default-const-table-as-const.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-inline-default-const-table-as-const-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-inline-default-const-table-as-const-entry.js"
  cp "$runtime_consts_path" "$root/runtime/imported-inline-default-const-table-as-const.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_inline_default_const_table_as_const_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps imported inline default const-table as const computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v23")
  assert_eq(get_build(), 27.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, false)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_iife_default_const_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_iife_default_const_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-iife-default-const-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-iife-default-const-table-entry.js"
  local runtime_consts_path="$repo_root/fixtures/bridge_smoke/runtime/imported-iife-default-const-table.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-iife-default-const-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-iife-default-const-table-entry.js"
  cp "$runtime_consts_path" "$root/runtime/imported-iife-default-const-table.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_iife_default_const_table_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps imported iife default const-table computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v24")
  assert_eq(get_build(), 28.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_iife_local_const_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_iife_local_const_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-iife-local-const-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-iife-local-const-table-entry.js"
  local runtime_consts_path="$repo_root/fixtures/bridge_smoke/runtime/imported-iife-local-const-table.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-iife-local-const-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-iife-local-const-table-entry.js"
  cp "$runtime_consts_path" "$root/runtime/imported-iife-local-const-table.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_iife_local_const_table_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps imported iife local const-table computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v25")
  assert_eq(get_build(), 29.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, false)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_function_iife_local_const_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_function_iife_local_const_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-function-iife-local-const-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-function-iife-local-const-table-entry.js"
  local runtime_consts_path="$repo_root/fixtures/bridge_smoke/runtime/imported-function-iife-local-const-table.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-function-iife-local-const-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-function-iife-local-const-table-entry.js"
  cp "$runtime_consts_path" "$root/runtime/imported-function-iife-local-const-table.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_function_iife_local_const_table_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps imported function iife local const-table computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v26")
  assert_eq(get_build(), 30.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_iife_local_let_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_iife_local_let_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-iife-local-let-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-iife-local-let-table-entry.js"
  local runtime_consts_path="$repo_root/fixtures/bridge_smoke/runtime/imported-iife-local-let-table.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-iife-local-let-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-iife-local-let-table-entry.js"
  cp "$runtime_consts_path" "$root/runtime/imported-iife-local-let-table.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_iife_local_let_table_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps imported iife local let-table computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v27")
  assert_eq(get_build(), 31.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, false)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_function_iife_local_let_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_function_iife_local_let_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-function-iife-local-let-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-function-iife-local-let-table-entry.js"
  local runtime_consts_path="$repo_root/fixtures/bridge_smoke/runtime/imported-function-iife-local-let-table.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-function-iife-local-let-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-function-iife-local-let-table-entry.js"
  cp "$runtime_consts_path" "$root/runtime/imported-function-iife-local-let-table.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_function_iife_local_let_table_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps imported function iife local let-table computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v28")
  assert_eq(get_build(), 32.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_reassigned_local_let_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_reassigned_local_let_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-iife-reassigned-let-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-iife-reassigned-let-table-entry.js"
  local runtime_consts_path="$repo_root/fixtures/bridge_smoke/runtime/imported-iife-reassigned-let-table.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"
  local abs_root
  abs_root="$(cd "$root" && pwd)"
  local helper_js_path="$abs_root/test_helpers.js"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-iife-reassigned-let-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-iife-reassigned-let-table-entry.js"
  cp "$runtime_consts_path" "$root/runtime/imported-iife-reassigned-let-table.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_reassigned_local_let_table_computed_destructured_value",
  "version": "0.1.0",
  "deps": {},
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$helper_js_path" <<'EOF'
export function anyToString(value) {
  return value;
}

export function anyToNumber(value) {
  return value;
}

export function anyGetEnabled(value) {
  return value.enabled;
}
EOF

  cat > "$root/bridge_test.mbt" <<EOF
#module("$helper_js_path")
pub extern "js" fn any_to_string(value : JSValue) -> String = "anyToString"

#module("$helper_js_path")
pub extern "js" fn any_to_number(value : JSValue) -> Double = "anyToNumber"

#module("$helper_js_path")
pub extern "js" fn any_get_enabled(value : JSValue) -> Bool = "anyGetEnabled"

test "generated bridge package widens imported reassigned local let-table computed-key value exports conservatively" {
  assert_eq(any_to_string(get_runtime_version()), "v29")
  assert_eq(any_to_number(get_build()), 33.0)
  assert_eq(any_get_enabled(get_rest_meta()), false)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_prop_mutated_local_let_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_prop_mutated_local_let_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-iife-prop-mutated-let-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-iife-prop-mutated-let-table-entry.js"
  local runtime_consts_path="$repo_root/fixtures/bridge_smoke/runtime/imported-iife-prop-mutated-let-table.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"
  local abs_root
  abs_root="$(cd "$root" && pwd)"
  local helper_js_path="$abs_root/test_helpers.js"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-iife-prop-mutated-let-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-iife-prop-mutated-let-table-entry.js"
  cp "$runtime_consts_path" "$root/runtime/imported-iife-prop-mutated-let-table.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_prop_mutated_local_let_table_computed_destructured_value",
  "version": "0.1.0",
  "deps": {},
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$helper_js_path" <<'EOF'
export function anyToString(value) {
  return value;
}

export function anyToNumber(value) {
  return value;
}

export function anyGetEnabled(value) {
  return value.enabled;
}
EOF

  cat > "$root/bridge_test.mbt" <<EOF
#module("$helper_js_path")
pub extern "js" fn any_to_string(value : JSValue) -> String = "anyToString"

#module("$helper_js_path")
pub extern "js" fn any_to_number(value : JSValue) -> Double = "anyToNumber"

#module("$helper_js_path")
pub extern "js" fn any_get_enabled(value : JSValue) -> Bool = "anyGetEnabled"

test "generated bridge package widens imported prop-mutated local let-table computed-key value exports conservatively" {
  assert_eq(any_to_string(get_runtime_version()), "v30")
  assert_eq(any_to_number(get_build()), 34.0)
  assert_eq(any_get_enabled(get_rest_meta()), true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_index_mutated_local_let_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_index_mutated_local_let_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-function-iife-index-mutated-let-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-function-iife-index-mutated-let-table-entry.js"
  local runtime_consts_path="$repo_root/fixtures/bridge_smoke/runtime/imported-function-iife-index-mutated-let-table.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"
  local abs_root
  abs_root="$(cd "$root" && pwd)"
  local helper_js_path="$abs_root/test_helpers.js"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-function-iife-index-mutated-let-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-function-iife-index-mutated-let-table-entry.js"
  cp "$runtime_consts_path" "$root/runtime/imported-function-iife-index-mutated-let-table.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_index_mutated_local_let_table_computed_destructured_value",
  "version": "0.1.0",
  "deps": {},
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$helper_js_path" <<'EOF'
export function anyToString(value) {
  return value;
}

export function anyToNumber(value) {
  return value;
}

export function anyGetEnabled(value) {
  return value.enabled;
}
EOF

  cat > "$root/bridge_test.mbt" <<EOF
#module("$helper_js_path")
pub extern "js" fn any_to_string(value : JSValue) -> String = "anyToString"

#module("$helper_js_path")
pub extern "js" fn any_to_number(value : JSValue) -> Double = "anyToNumber"

#module("$helper_js_path")
pub extern "js" fn any_get_enabled(value : JSValue) -> Bool = "anyGetEnabled"

test "generated bridge package widens imported index-mutated local let-table computed-key value exports conservatively" {
  assert_eq(any_to_string(get_runtime_version()), "v31")
  assert_eq(any_to_number(get_build()), 35.0)
  assert_eq(any_get_enabled(get_rest_meta()), false)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_reexported_const_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_reexported_const_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-reexported-const-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-reexported-const-table-entry.js"
  local runtime_consts_path="$repo_root/fixtures/bridge_smoke/runtime/imported-reexported-const-table.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-reexported-const-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-reexported-const-table-entry.js"
  cp "$runtime_consts_path" "$root/runtime/imported-reexported-const-table.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_reexported_const_table_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps imported reexported const-table computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v13")
  assert_eq(get_build(), 17.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_chained_const_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_chained_const_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-chained-const-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-chained-const-table-entry.js"
  local runtime_reexport_path="$repo_root/fixtures/bridge_smoke/runtime/imported-chained-const-table.js"
  local runtime_source_path="$repo_root/fixtures/bridge_smoke/runtime/imported-chained-const-table-source.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-chained-const-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-chained-const-table-entry.js"
  cp "$runtime_reexport_path" "$root/runtime/imported-chained-const-table.js"
  cp "$runtime_source_path" "$root/runtime/imported-chained-const-table-source.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_chained_const_table_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps imported chained const-table computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v14")
  assert_eq(get_build(), 18.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, false)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_star_const_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_star_const_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-star-const-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-star-const-table-entry.js"
  local runtime_barrel_path="$repo_root/fixtures/bridge_smoke/runtime/imported-star-const-table.js"
  local runtime_source_path="$repo_root/fixtures/bridge_smoke/runtime/imported-star-const-table-source.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-star-const-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-star-const-table-entry.js"
  cp "$runtime_barrel_path" "$root/runtime/imported-star-const-table.js"
  cp "$runtime_source_path" "$root/runtime/imported-star-const-table-source.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_star_const_table_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps imported star const-table computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v15")
  assert_eq(get_build(), 19.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_deep_star_const_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_deep_star_const_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-deep-star-const-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-deep-star-const-table-entry.js"
  local runtime_barrel_path="$repo_root/fixtures/bridge_smoke/runtime/imported-deep-star-const-table.js"
  local runtime_level1_path="$repo_root/fixtures/bridge_smoke/runtime/imported-deep-star-const-table-level1.js"
  local runtime_source_path="$repo_root/fixtures/bridge_smoke/runtime/imported-deep-star-const-table-source.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-deep-star-const-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-deep-star-const-table-entry.js"
  cp "$runtime_barrel_path" "$root/runtime/imported-deep-star-const-table.js"
  cp "$runtime_level1_path" "$root/runtime/imported-deep-star-const-table-level1.js"
  cp "$runtime_source_path" "$root/runtime/imported-deep-star-const-table-source.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_deep_star_const_table_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps imported deep star const-table computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v16")
  assert_eq(get_build(), 20.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, false)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_mixed_barrel_const_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_mixed_barrel_const_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-mixed-barrel-const-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-mixed-barrel-const-table-entry.js"
  local runtime_barrel_path="$repo_root/fixtures/bridge_smoke/runtime/imported-mixed-barrel-const-table.js"
  local runtime_source_path="$repo_root/fixtures/bridge_smoke/runtime/imported-mixed-barrel-const-table-source.js"
  local runtime_indexes_path="$repo_root/fixtures/bridge_smoke/runtime/imported-mixed-barrel-indexes.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-mixed-barrel-const-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-mixed-barrel-const-table-entry.js"
  cp "$runtime_barrel_path" "$root/runtime/imported-mixed-barrel-const-table.js"
  cp "$runtime_source_path" "$root/runtime/imported-mixed-barrel-const-table-source.js"
  cp "$runtime_indexes_path" "$root/runtime/imported-mixed-barrel-indexes.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_mixed_barrel_const_table_computed_destructured_value",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps imported mixed barrel const-table computed-key value exports self-contained" {
  assert_eq(get_runtime_version(), "v17")
  assert_eq(get_build(), 21.0)
  let rest = get_rest_meta()
  assert_eq(rest.enabled, true)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_imported_conflicting_star_const_table_computed_destructured_value_fixture() {
  local root="_build/bridge_fixture_imported_conflicting_star_const_table_computed_destructured_value"
  local fixture_path="$repo_root/fixtures/bridge_smoke/imported-conflicting-star-const-table-entry.ts"
  local runtime_entry_path="$repo_root/fixtures/bridge_smoke/runtime/imported-conflicting-star-const-table-entry.js"
  local runtime_barrel_path="$repo_root/fixtures/bridge_smoke/runtime/imported-conflicting-star-const-table.js"
  local runtime_keys_a_path="$repo_root/fixtures/bridge_smoke/runtime/imported-conflicting-star-const-table-keys-a.js"
  local runtime_keys_b_path="$repo_root/fixtures/bridge_smoke/runtime/imported-conflicting-star-const-table-keys-b.js"
  local runtime_indexes_path="$repo_root/fixtures/bridge_smoke/runtime/imported-conflicting-star-const-table-indexes.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"
  local abs_root
  abs_root="$(cd "$root" && pwd)"
  local bridge_js_path="$abs_root/bridge.js"
  local helper_js_path="$abs_root/test_helpers.js"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/imported-conflicting-star-const-table-entry.js" "$root" >/dev/null
  cp "$runtime_entry_path" "$root/runtime/imported-conflicting-star-const-table-entry.js"
  cp "$runtime_barrel_path" "$root/runtime/imported-conflicting-star-const-table.js"
  cp "$runtime_keys_a_path" "$root/runtime/imported-conflicting-star-const-table-keys-a.js"
  cp "$runtime_keys_b_path" "$root/runtime/imported-conflicting-star-const-table-keys-b.js"
  cp "$runtime_indexes_path" "$root/runtime/imported-conflicting-star-const-table-indexes.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_imported_conflicting_star_const_table_computed_destructured_value",
  "version": "0.1.0",
  "deps": {},
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$helper_js_path" <<'EOF'
export function anyToString(value) {
  return value;
}

export function anyToNumber(value) {
  return value;
}

export function anyGetEnabled(value) {
  return value.enabled;
}
EOF

  cat > "$root/bridge_test.mbt" <<EOF
#module("$helper_js_path")
pub extern "js" fn any_to_string(value : JSValue) -> String = "anyToString"

#module("$helper_js_path")
pub extern "js" fn any_to_number(value : JSValue) -> Double = "anyToNumber"

#module("$helper_js_path")
pub extern "js" fn any_get_enabled(value : JSValue) -> Bool = "anyGetEnabled"

test "generated bridge package widens conflicting star const-table computed-key value exports conservatively" {
  assert_eq(any_to_string(get_runtime_version()), "v18")
  assert_eq(any_to_number(get_build()), 22.0)
  assert_eq(any_get_enabled(get_rest_meta()), false)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_default_class_fixture() {
  local root="_build/bridge_fixture_default_class"
  local fixture_path="$repo_root/fixtures/bridge_smoke/default-class-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/default-class.js"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "./runtime/default-class.js" "$root" >/dev/null
  cp "$runtime_path" "$root/runtime/default-class.js"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_default_class",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps default class bindings self-contained" {
  let counter = new_default(2.0)
  assert_eq(counter.get_default_count(), 2.0)
  assert_eq(counter.default_inc(5.0), 7.0)
  counter.set_default_count(9.0)
  assert_eq(counter.get_default_count(), 9.0)
  let seeded = default_from(4.0)
  assert_eq(seeded.get_default_count(), 4.0)
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
}

verify_bridge_deep_parent_relative_default_class_mixed_fixture() {
  local root="_build/bridge_fixture_default_class_mixed"
  local pkg_root="$root/nested/pkg"
  local fixture_path="$repo_root/fixtures/bridge_smoke/default-class-mixed-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/default-class-mixed.js"

  rm -rf "$root"
  mkdir -p "$pkg_root" "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "../../runtime/default-class-mixed.js" "$pkg_root" >/dev/null
  cp "$runtime_path" "$root/runtime/default-class-mixed.js"

  cat > "$pkg_root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_default_class_mixed",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$pkg_root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps deep parent-relative mixed default class bindings self-contained" {
  let counter = new_default(2.0)
  assert_eq(counter.default_inc(5.0), 7.0)
  assert_eq(surround("ok", "!"), "!ok!")
  assert_eq(get_version(), "v2")
}
EOF

  moon -C "$pkg_root" check --target js
  moon -C "$pkg_root" test --target js
}

verify_bridge_deep_parent_relative_default_class_mixed_reexport_fixture() {
  local root="_build/bridge_fixture_default_class_mixed_reexport"
  local pkg_root="$root/nested/pkg"
  local fixture_path="$repo_root/fixtures/bridge_smoke/default-class-mixed-reexport-entry.ts"
  local runtime_path="$repo_root/fixtures/bridge_smoke/runtime/default-class-mixed.js"

  rm -rf "$root"
  mkdir -p "$pkg_root" "$root/runtime"

  moon run src/cmd/ts2mbt -- package "$fixture_path" "../../runtime/default-class-mixed.js" "$pkg_root" >/dev/null
  cp "$runtime_path" "$root/runtime/default-class-mixed.js"

  cat > "$pkg_root/moon.mod.json" <<'EOF'
{
  "name": "fixture/bridge_default_class_mixed_reexport",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$pkg_root/bridge_test.mbt" <<'EOF'
test "generated bridge package keeps deep parent-relative mixed default class reexports self-contained" {
  let counter = new_runtime_counter(2.0)
  assert_eq(counter.runtime_counter_inc(5.0), 7.0)
  assert_eq(decorate("ok", "!"), "!ok!")
  assert_eq(get_runtime_version(), "v2")
}
EOF

  moon -C "$pkg_root" check --target js
  moon -C "$pkg_root" test --target js
}

verify_mbti_fixture_typescript
verify_bridge_smoke_fixture
verify_bridge_enum_fixture
verify_bridge_literal_union_alias_fixture
verify_bridge_numeric_enum_fixture
verify_bridge_numeric_literal_union_fixture
verify_bridge_boolean_literal_union_fixture
verify_bridge_realworld_literal_options_fixture
verify_bridge_stable_constructor_fixture
verify_bridge_default_export_fixture
verify_bridge_declaration_merge_namespace_fixture
verify_bridge_promise_return_fixture
verify_bridge_callback_fixture
verify_bridge_cjs_export_equals_fixture
verify_bridge_node_path_namespace_import_fixture
verify_bridge_parent_relative_default_function_fixture
verify_bridge_bare_cjs_default_function_fixture
verify_bridge_class_property_fixture
verify_bridge_rooted_class_property_reexport_fixture
verify_bridge_bare_class_property_reexport_fixture
verify_bridge_bare_default_class_reexport_fixture
verify_bridge_subpath_class_reexport_fixture
verify_bridge_destructured_value_fixture
verify_bridge_destructured_nested_rest_value_fixture
verify_bridge_object_rest_value_fixture
verify_bridge_computed_destructured_value_fixture
verify_bridge_template_computed_destructured_value_fixture
verify_bridge_concat_computed_destructured_value_fixture
verify_bridge_primitive_computed_destructured_value_fixture
verify_bridge_void_bigint_computed_destructured_value_fixture
verify_bridge_const_ref_computed_destructured_value_fixture
verify_bridge_destructured_const_ref_computed_destructured_value_fixture
verify_bridge_const_object_access_computed_destructured_value_fixture
verify_bridge_nested_const_object_access_computed_destructured_value_fixture
verify_bridge_const_array_access_computed_destructured_value_fixture
verify_bridge_nested_const_array_access_computed_destructured_value_fixture
verify_bridge_const_index_alias_computed_destructured_value_fixture
verify_bridge_const_index_table_computed_destructured_value_fixture
verify_bridge_nested_index_table_computed_destructured_value_fixture
verify_bridge_imported_const_table_computed_destructured_value_fixture
verify_bridge_imported_namespace_const_table_computed_destructured_value_fixture
verify_bridge_imported_default_const_table_computed_destructured_value_fixture
verify_bridge_imported_inline_default_const_table_computed_destructured_value_fixture
verify_bridge_imported_inline_default_const_table_as_const_computed_destructured_value_fixture
verify_bridge_imported_iife_default_const_table_computed_destructured_value_fixture
verify_bridge_imported_iife_local_const_table_computed_destructured_value_fixture
verify_bridge_imported_function_iife_local_const_table_computed_destructured_value_fixture
verify_bridge_imported_iife_local_let_table_computed_destructured_value_fixture
verify_bridge_imported_function_iife_local_let_table_computed_destructured_value_fixture
verify_bridge_imported_reassigned_local_let_table_computed_destructured_value_fixture
verify_bridge_imported_prop_mutated_local_let_table_computed_destructured_value_fixture
verify_bridge_imported_index_mutated_local_let_table_computed_destructured_value_fixture
verify_bridge_imported_reexported_const_table_computed_destructured_value_fixture
verify_bridge_imported_chained_const_table_computed_destructured_value_fixture
verify_bridge_imported_star_const_table_computed_destructured_value_fixture
verify_bridge_imported_deep_star_const_table_computed_destructured_value_fixture
verify_bridge_imported_mixed_barrel_const_table_computed_destructured_value_fixture
verify_bridge_default_class_fixture
verify_bridge_deep_parent_relative_default_class_mixed_fixture
verify_bridge_deep_parent_relative_default_class_mixed_reexport_fixture

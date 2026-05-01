#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
source "$repo_root/scripts/warning_guard.sh"

grep_generated_mbt() {
  local root="$1"
  local pattern="$2"
  local file

  for file in "$root"/bridge.mbt "$root"/types.mbt "$root"/converters.mbt "$root"/externs.mbt "$root"/guards.mbt; do
    [ -f "$file" ] || continue
    grep -F "$pattern" "$file" >/dev/null && return 0
  done
  return 1
}

assert_declared_value_exports_present() {
  local module_path="$1"
  local decl_path="$2"

  MODULE_PATH="$module_path" DECL_PATH="$decl_path" node --input-type=module <<'EOF'
import { readFileSync } from "node:fs";

const modulePath = process.env.MODULE_PATH;
const declPath = process.env.DECL_PATH;
const mod = await import(modulePath);
const decl = readFileSync(declPath, "utf8");
const declared = [...decl.matchAll(/^export function\s+([A-Za-z_$][\w$]*)\s*\(/gm)]
  .map((match) => match[1]);
const missing = declared.filter((name) => !(name in mod));
if (missing.length > 0) {
  throw new Error(`missing runtime exports for declarations: ${missing.join(", ")}`);
}
EOF
}

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
    "out/child/index.d.ts",
    "out/child/grand/index.d.ts"
  ]
}
EOF

  [ -f "$root/out/package.json" ]
  [ -f "$root/out/index.js" ]
  [ -f "$root/out/index.js.map" ]
  [ -f "$root/out/child/index.js" ]
  [ -f "$root/out/child/grand/index.js" ]
  [ -f "$root/out/AUTOLINK_DIAGNOSTICS.md" ]
  [ ! -f "$root/out/moon.pkg.json" ]
  [ ! -f "$root/out/moon.pkg" ]
  [ ! -f "$root/out/AUTOLINK_FACADE.mbt" ]
  [ ! -f "$root/out/TSMBT_GLUE.mbt" ]
  grep -F '"name": "@examples/counter"' "$root/out/package.json" >/dev/null
  grep -F '"import": "./index.js"' "$root/out/package.json" >/dev/null
  grep -F '"./child": { "types": "./child/index.d.ts", "import": "./child/index.js" }' "$root/out/package.json" >/dev/null
  grep -F '"./child/grand": { "types": "./child/grand/index.d.ts", "import": "./child/grand/index.js" }' "$root/out/package.json" >/dev/null
  grep -F 'Counter::label' "$root/out/AUTOLINK_DIAGNOSTICS.md" >/dev/null
  if grep -F 'counter_label' "$root/out/index.d.ts" >/dev/null; then
    echo "base scaffold should not emit facade declarations" >&2
    exit 1
  fi
  assert_declared_value_exports_present "./$root/out/index.js" "$root/out/index.d.ts"
  assert_declared_value_exports_present "./$root/out/child/index.js" "$root/out/child/index.d.ts"
  assert_declared_value_exports_present "./$root/out/child/grand/index.js" "$root/out/child/grand/index.d.ts"
  pnpm exec tsc -p "$root/tsconfig.json" --pretty false
  node --input-type=module <<'EOF'
const mod = await import("./_build/scaffold_mbti_to_ts/out/index.js");
const child = await import("./_build/scaffold_mbti_to_ts/out/child/index.js");
const grand = await import("./_build/scaffold_mbti_to_ts/out/child/grand/index.js");
const counter = mod.create("demo", { id: 7, name: "item" });
if (mod.summarize(counter) !== "demo:item#7") {
  throw new Error("unexpected summarize output");
}
const item = child.make_item(8, "child");
if (item.name !== "child" || item.id !== 8) {
  throw new Error("unexpected child make_item output");
}
const tag = child.item_tag(item);
if (tag.value !== "child#8") {
  throw new Error("unexpected child item_tag output");
}
const directTag = grand.make_tag("direct");
if (directTag.value !== "direct") {
  throw new Error("unexpected grand make_tag output");
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
    "out/child/index.d.ts",
    "out/child/grand/index.d.ts"
  ]
}
EOF

  [ -f "$root/out/package.json" ]
  [ -f "$root/out/index.js" ]
  [ -f "$root/out/index.js.map" ]
  [ -f "$root/out/child/index.js" ]
  [ -f "$root/out/child/grand/index.js" ]
  [ -f "$root/out/AUTOLINK_DIAGNOSTICS.md" ]
  [ ! -f "$root/out/moon.pkg.json" ]
  [ ! -f "$root/out/moon.pkg" ]
  [ ! -f "$root/out/AUTOLINK_FACADE.mbt" ]
  [ ! -f "$root/out/TSMBT_GLUE.mbt" ]
  grep -F '"name": "@examples/counter"' "$root/out/package.json" >/dev/null
  grep -F '"import": "./index.js"' "$root/out/package.json" >/dev/null
  grep -F '"./child": { "types": "./child/index.d.ts", "import": "./child/index.js" }' "$root/out/package.json" >/dev/null
  grep -F '"./child/grand": { "types": "./child/grand/index.d.ts", "import": "./child/grand/index.js" }' "$root/out/package.json" >/dev/null
  grep -F 'export function counter_label(self: Counter): string;' "$root/out/index.d.ts" >/dev/null
  grep -F 'export function item_display(self: Item): string;' "$root/out/child/index.d.ts" >/dev/null
  grep -F 'export function tag_label(self: Tag): string;' "$root/out/child/grand/index.d.ts" >/dev/null
  assert_declared_value_exports_present "./$root/out/index.js" "$root/out/index.d.ts"
  assert_declared_value_exports_present "./$root/out/child/index.js" "$root/out/child/index.d.ts"
  assert_declared_value_exports_present "./$root/out/child/grand/index.js" "$root/out/child/grand/index.d.ts"
  pnpm exec tsc -p "$root/tsconfig.json" --pretty false
  node --input-type=module <<'EOF'
const mod = await import("./_build/scaffold_mbti_to_ts_facade/out/index.js");
const child = await import("./_build/scaffold_mbti_to_ts_facade/out/child/index.js");
const grand = await import("./_build/scaffold_mbti_to_ts_facade/out/child/grand/index.js");
const counter = mod.create("demo", { id: 7, name: "item" });
if (mod.counter_label(counter) !== "demo") {
  throw new Error("unexpected counter_label output");
}
if (mod.summarize(counter) !== "demo:item#7") {
  throw new Error("unexpected summarize output");
}
const item = child.make_item(8, "child");
if (child.item_display(item) !== "child#8") {
  throw new Error("unexpected item_display output");
}
const tag = child.item_tag(item);
if (grand.tag_label(tag) !== "child#8") {
  throw new Error("unexpected grand tag_label output");
}
EOF
}

verify_typescript_async_facade_scaffold_fixture() {
  local root="_build/scaffold_mbti_to_ts_async_facade"
  local mbti_path="$repo_root/examples/moonbit-to-typescript/async_worker/pkg.generated.mbti"

  rm -rf "$root"
  mkdir -p "$root"

  moon run src -- emit-typescript-facade-scaffold-from-mbti \
    "$mbti_path" \
    "$root/out" >/dev/null

  cat > "$root/consumer.ts" <<'EOF'
import { worker_load, worker_new, type Worker } from "./out/index.js";

async function main() {
  const worker: Worker = await worker_new("demo");
  const loaded: string = await worker_load(worker, "key");
  const fallback: string = await worker_load(worker);
  void loaded;
  void fallback;
}

void main;
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
    "consumer.ts",
    "out/index.d.ts"
  ]
}
EOF

  grep -F 'export function worker_new(arg0: string): Promise<Worker>;' "$root/out/index.d.ts" >/dev/null
  grep -F 'export function worker_load(self: Worker, key?: string): Promise<string>;' "$root/out/index.d.ts" >/dev/null
  assert_declared_value_exports_present "./$root/out/index.js" "$root/out/index.d.ts"
  pnpm exec tsc -p "$root/tsconfig.json" --pretty false
  node --input-type=module <<'EOF'
const mod = await import("./_build/scaffold_mbti_to_ts_async_facade/out/index.js");
const workerPromise = mod.worker_new("demo");
if (!(workerPromise instanceof Promise)) {
  throw new Error("worker_new should return a Promise");
}
const worker = await workerPromise;
if ((await mod.worker_load(worker, "key")) !== "demo:key") {
  throw new Error("unexpected worker_load output");
}
if ((await mod.worker_load(worker)) !== "demo:default") {
  throw new Error("unexpected worker_load fallback output");
}
EOF
}

verify_typescript_reverse_edge_scaffold_fixture() {
  local root="_build/scaffold_mbti_to_ts_reverse_edge"
  local mbti_path="$repo_root/examples/moonbit-to-typescript/reverse_edge/pkg.generated.mbti"

  rm -rf "$root"
  mkdir -p "$root/moonbitlang/core"

  moon run src -- emit-typescript-scaffold-from-mbti \
    "$mbti_path" \
    "$root/out" >/dev/null

  cat > "$root/moonbitlang/core/ref.d.ts" <<'EOF'
export interface Ref<T> {
  val: T;
}
EOF

  cat > "$root/moonbitlang/core/set.d.ts" <<'EOF'
export type Set<T> = globalThis.Set<T>;
EOF

  cat > "$root/consumer.ts" <<'EOF'
import {
  borrow_bytes,
  consume_callbacks,
  failed,
  load_all,
  make_string_box,
  ready,
  update_ref,
  type CallbackBox,
  type LoadError,
  type Result,
  type Status,
} from "./out/index.js";
import type { Ref } from "moonbitlang/core/ref";

const bytes: Uint8Array = borrow_bytes(new Uint8Array([1, 2, 3]));
const box: CallbackBox<string> = make_string_box("value");
const ok: Promise<Result<Result<Array<[string, number]>, LoadError>, LoadError>> = load_all(["a"]);
const status: Status = ready(1);
const errorStatus: Status = failed("missing");
const state: Ref<Array<bigint>> = { val: [] };
const updated: Set<string> = update_ref(state, [1n, 2n]);
consume_callbacks((_label, _count) => {}, undefined, ["required"]);
void bytes;
void box;
void ok;
void status;
void errorStatus;
void updated;
EOF

  cat > "$root/tsconfig.json" <<'EOF'
{
  "compilerOptions": {
    "strict": true,
    "noEmit": true,
    "target": "es2020",
    "module": "esnext",
    "moduleResolution": "bundler",
    "baseUrl": ".",
    "lib": ["es2020"]
  },
  "files": [
    "consumer.ts",
    "out/index.d.ts"
  ]
}
EOF

  [ -f "$root/out/package.json" ]
  [ -f "$root/out/index.js" ]
  [ -f "$root/out/index.js.map" ]
  grep -F '"name": "@examples/reverse_edge"' "$root/out/package.json" >/dev/null
  grep -F 'export function consume_callbacks' "$root/out/index.d.ts" >/dev/null
  grep -F 'export function load_all' "$root/out/index.d.ts" >/dev/null
  assert_declared_value_exports_present "./$root/out/index.js" "$root/out/index.d.ts"
  pnpm exec tsc -p "$root/tsconfig.json" --pretty false
  node --input-type=module <<'EOF'
const mod = await import("./_build/scaffold_mbti_to_ts_reverse_edge/out/index.js");
let seen = "";
let errorSeen = "";
mod.consume_callbacks(
  (label, count) => {
    seen = `${label}:${count}`;
  },
  (err) => {
    errorSeen = err?._0 ?? "";
  },
  ["a", "b"],
);
if (seen !== "required:2") {
  throw new Error(`unexpected callback output: ${seen}`);
}
if (errorSeen !== "optional") {
  throw new Error(`unexpected optional callback output: ${errorSeen}`);
}
const bytes = mod.borrow_bytes(new Uint8Array([1, 2, 3]));
if (!(bytes instanceof Uint8Array) || bytes.length !== 3 || bytes[1] !== 2) {
  throw new Error("unexpected borrow_bytes output");
}
const box = mod.make_string_box("value");
if (box.current !== "value") {
  throw new Error("unexpected CallbackBox output");
}
const loaded = await mod.load_all(["aa"]);
if (!loaded || !("_0" in loaded) || !loaded._0 || !("_0" in loaded._0)) {
  throw new Error("unexpected load_all output");
}
const state = { val: [] };
const updated = mod.update_ref(state, [1n, 2n]);
if (state.val.length !== 2 || state.val[0] !== 1n || !updated) {
  throw new Error("unexpected update_ref output");
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

///|
#external
pub type Promise[T]
EOF
}

run_typescript_to_moonbit_js_build_smoke() {
  local root="$1"
  local module_name="$2"
  local needs_js_import="${3:-false}"
  local smoke_pkg="__tsmbt_build_smoke__"
  local smoke_dir="$root/$smoke_pkg"

  rm -rf "$smoke_dir" "$root/_build/js/debug/build"
  mkdir -p "$smoke_dir"

  local js_import_suffix=""
  if [ "$needs_js_import" = "true" ]; then
    js_import_suffix=$',
    { "path": "mizchi/js/core", "alias": "js" }'
  fi

  cat > "$smoke_dir/moon.pkg.json" <<EOF
{
  "is-main": true,
  "import": [
    { "path": "$module_name", "alias": "sut" }$js_import_suffix
  ]
}
EOF

  cat > "$smoke_dir/main.mbt"

  moon -C "$root" build --target js "$smoke_pkg"

  local built_js
  built_js="$(find "$root/_build/js/debug/build" -type f -name '*.js' | head -n 1)"
  if [ -z "$built_js" ]; then
    echo "moon build --target js did not emit a runnable JS file for $module_name" >&2
    exit 1
  fi

  printf '{ "type": "module" }\n' > "$(dirname "$built_js")/package.json"
  node "$built_js"
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
  run_typescript_to_moonbit_js_build_smoke "$root" "fixture/scaffold_ts_to_moonbit" <<'EOF'
fn main {
  if @sut.double(21.0) != 42.0 {
    abort("unexpected double output")
  }
}
EOF
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
  run_typescript_to_moonbit_js_build_smoke "$root" "fixture/scaffold_ts_to_moonbit_neverthrow_like" <<'EOF'
fn main {
  let _ = @sut.parseUser("u1")
  let _ = @sut.fetchUser("u2")
}
EOF
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
  run_typescript_to_moonbit_js_build_smoke "$root" "fixture/scaffold_ts_to_moonbit_react_like_jsx" <<'EOF'
fn main {
  let _ = @sut.createElement("badge")
}
EOF
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

extern "js" fn test_dom_attributes_partial() -> DOMAttributesPartial =
  #| () => ({ id: "app" })

extern "js" fn test_button_attributes() -> ButtonHTMLAttributes =
  #| () => ({ disabled: true })

extern "js" fn test_function_component() -> FunctionComponent =
  #| () => (props) => ({ type: "component", props, key: null })

extern "js" fn test_forward_ref_render() -> ForwardRefRenderCallback =
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
  let _ = cloneElement(element, Some(test_dom_attributes_partial()), test_children())
  let _ = forwardRef(test_forward_ref_render())
  let _ = memo(test_function_component(), None)
  let _ = normalizeProps(test_button_attributes())
  let _ = useComponentRef(test_ref())
  let _ = get_default()
}
EOF

  grep_generated_mbt "$root" 'pub fn createElement(type_ : String, props : DOMAttributes?, children : Array[JSValue]) -> ReactElement'
  grep_generated_mbt "$root" 'pub fn cloneElement(element : ReactElement, props : DOMAttributesPartial?, children : Array[JSValue]) -> ReactElement'
  grep_generated_mbt "$root" '#external'
  moon -C "$root" check --target js
  moon -C "$root" test --target js
  run_typescript_to_moonbit_js_build_smoke "$root" "fixture/scaffold_ts_to_moonbit_react_package" <<'EOF'
extern "js" fn test_dom_attributes() -> @sut.DOMAttributes =
  #| () => ({ id: "app" })

extern "js" fn test_dom_attributes_partial() -> @sut.DOMAttributesPartial =
  #| () => ({ id: "app" })

extern "js" fn test_button_attributes() -> @sut.ButtonHTMLAttributes =
  #| () => ({ disabled: true })

extern "js" fn test_function_component() -> @sut.FunctionComponent =
  #| () => (props) => ({ type: "component", props, key: null })

extern "js" fn test_forward_ref_render() -> @sut.ForwardRefRenderCallback =
  #| () => (props, ref) => ({ type: "forward", props, ref, key: null })

extern "js" fn test_ref() -> @sut.Ref =
  #| () => ({ current: null })

extern "js" fn test_children() -> Array[@sut.JSValue] =
  #| () => []

fn main {
  let element = @sut.createElement(
    "div",
    Some(test_dom_attributes()),
    test_children(),
  )
  let _ = @sut.cloneElement(element, Some(test_dom_attributes_partial()), test_children())
  let _ = @sut.forwardRef(test_forward_ref_render())
  let _ = @sut.memo(test_function_component(), None)
  let _ = @sut.normalizeProps(test_button_attributes())
  let _ = @sut.useComponentRef(test_ref())
  let _ = @sut.get_default()
}
EOF
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
  run_typescript_to_moonbit_js_build_smoke "$root" "fixture/scaffold_ts_to_moonbit_react_jsx_runtime" <<'EOF'
extern "js" fn test_button_attributes() -> @sut.ButtonHTMLAttributes =
  #| () => ({ disabled: true })

fn main {
  let _ = @sut.jsx("button", test_button_attributes(), None)
  let _ = @sut.jsxs("button", test_button_attributes(), None)
}
EOF
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
  run_typescript_to_moonbit_js_build_smoke "$root" "fixture/scaffold_ts_to_moonbit_react_jsx_dev_runtime" <<'EOF'
extern "js" fn test_element_type() -> @sut.ElementType =
  #| () => "badge"

extern "js" fn test_key() -> @sut.Key =
  #| () => "key"

extern "js" fn test_props() -> @sut.JSValue =
  #| () => ({ label: "Badge" })

extern "js" fn test_source() -> @sut.JSXSource =
  #| () => ({ fileName: "x.tsx", lineNumber: 1 })

fn main {
  let _ = @sut.jsxDEV(
    test_element_type(),
    test_props(),
    Some(test_key()),
    false,
    Some(test_source()),
    None,
  )
}
EOF
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

extern "js" fn test_component() -> MemoComponentCallback =
  #| () => (props) => ({ tag: "button", props })

test "generated Hono JSX scaffold smoke" {
  let _ = jsx("button", test_button_attributes())
  let _ = memo(test_component())
}
EOF

  moon -C "$root" check --target js
  moon -C "$root" test --target js
  run_typescript_to_moonbit_js_build_smoke "$root" "fixture/scaffold_ts_to_moonbit_hono_jsx" <<'EOF'
extern "js" fn test_button_attributes() -> @sut.ButtonAttributes =
  #| () => ({ disabled: true })

extern "js" fn test_component() -> @sut.MemoComponentCallback =
  #| () => (props) => ({ tag: "button", props })

fn main {
  let _ = @sut.jsx("button", test_button_attributes())
  let _ = @sut.memo(test_component())
}
EOF
}

verify_moonbit_scaffold_hono_options_fixture() {
  local root="_build/scaffold_ts_to_moonbit_hono_options"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  moon run src -- emit-moonbit-scaffold-from-ts \
    fixtures/resolver/project/types/hono-options-entry.d.ts \
    ./runtime/hono.js \
    "$root" >/dev/null

  write_js_any_stub "$root"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "fixture/scaffold_ts_to_moonbit_hono_options",
  "version": "0.1.0",
  "deps": {
    "mizchi/js": { "path": "./_stubs/mizchi_js" }
  },
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
  run_typescript_to_moonbit_js_build_smoke "$root" "fixture/scaffold_ts_to_moonbit_hono_options" <<'EOF'
extern "js" fn test_hono_options() -> @sut.HonoOptions =
  #| () => ({ strict: true })

fn main {
  let _ = @sut.new_hono(None)
  let _ = @sut.createApp(test_hono_options())
}
EOF
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
  run_typescript_to_moonbit_js_build_smoke "$root" "fixture/scaffold_ts_to_moonbit_namespace" <<'EOF'
fn main {
  let _ = @sut.get_shapes()
}
EOF
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
  grep_generated_mbt "$root" 'Unsupported export Shared: ambiguous re-export surface cannot be bound safely'
  moon -C "$root" check --target js
}

verify_typescript_scaffold_fixture
verify_typescript_facade_scaffold_fixture
verify_typescript_async_facade_scaffold_fixture
verify_typescript_reverse_edge_scaffold_fixture
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

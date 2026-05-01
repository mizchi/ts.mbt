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
  [ -f "$root/dist/child/index.js" ]
  [ -f "$root/dist/AUTOLINK_DIAGNOSTICS.md" ]
  [ ! -f "$root/dist/moon.pkg.json" ]
  [ ! -f "$root/dist/moon.pkg" ]
  [ ! -f "$root/dist/AUTOLINK_FACADE.mbt" ]
  [ ! -f "$root/dist/TSMBT_GLUE.mbt" ]
  grep -F '"name": "@examples/counter"' "$root/dist/package.json" >/dev/null
  grep -F '"import": "./index.js"' "$root/dist/package.json" >/dev/null
  grep -F '"./child": { "types": "./child/index.d.ts", "import": "./child/index.js" }' "$root/dist/package.json" >/dev/null
  grep -F 'export function create' "$root/dist/index.d.ts" >/dev/null
  grep -F 'export function counter_label' "$root/dist/index.d.ts" >/dev/null
  grep -F 'export interface Item' "$root/dist/child/index.d.ts" >/dev/null
  grep -F 'export function item_display' "$root/dist/child/index.d.ts" >/dev/null
  pnpm exec tsc -p "$root/tsconfig.json" --pretty false
  node --input-type=module - <<'EOF'
const mod = await import("./_build/examples/moonbit-to-typescript/dist/index.js");
const child = await import("./_build/examples/moonbit-to-typescript/dist/child/index.js");
const counter = mod.create("demo", { id: 7, name: "item" });
if (mod.counter_label(counter) !== "demo") {
  throw new Error("counter_label returned an unexpected value");
}
if (mod.summarize(counter) !== "demo:item#7") {
  throw new Error("summarize returned an unexpected value");
}
const item = child.make_item(8, "child");
if (child.item_display(item) !== "child#8") {
  throw new Error("item_display returned an unexpected value");
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
  grep_generated_mbt "$out" 'pub extern "js" fn greet(name : String) -> String'
  grep_generated_mbt "$out" 'pub extern "js" fn double(value : Double) -> Double'
  moon -C "$out" check --target js
  moon -C "$out" test --target js
  run_typescript_to_moonbit_js_build_smoke "$out" "examples/typescript_to_moonbit" <<'EOF'
fn main {
  if @sut.greet("MoonBit") != "Hello, MoonBit" {
    abort("unexpected greet output")
  }
  if @sut.double(21.0) != 42.0 {
    abort("unexpected double output")
  }
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

run_typescript_ast_build_smoke() {
  local root="$1"
  local module_name="$2"
  local smoke_pkg="__tsmbt_build_smoke__"
  local smoke_dir="$root/$smoke_pkg"

  rm -rf "$smoke_dir" "$root/_build/js/debug/build"
  mkdir -p "$smoke_dir"

  cat > "$smoke_dir/moon.pkg.json" <<EOF
{
  "is-main": true,
  "import": [
    { "path": "$module_name", "alias": "sut" }
  ]
}
EOF

  cp examples/typescript-to-moonbit/typescript-ast/smoke/main.mbt "$smoke_dir/main.mbt"

  moon -C "$root" build --target js "$smoke_pkg"

  local built_js
  built_js="$(find "$root/_build/js/debug/build" -type f -name '*.js' | head -n 1)"
  if [ -z "$built_js" ]; then
    echo "moon build --target js did not emit a runnable JS file for $module_name" >&2
    exit 1
  fi

  printf '{ "type": "module" }\n' > "$(dirname "$built_js")/package.json"
  node --input-type=module - <<EOF
await import("./$built_js");
EOF
}

verify_typescript_to_moonbit_hono_example() {
  local root="_build/examples/typescript-to-moonbit-hono"
  local out="$root/dist"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  cp examples/typescript-to-moonbit/hono/runtime/hono.js "$root/runtime/hono.js"

  moon run src -- \
    --input examples/typescript-to-moonbit/hono/src/index.d.ts \
    --out "$out" \
    --direction ts-to-mbt \
    --module-spec ../runtime/hono.js >/dev/null

  write_js_any_stub "$out"

  cat > "$out/moon.mod.json" <<'EOF'
{
  "name": "examples/typescript_to_moonbit_hono",
  "version": "0.1.0",
  "deps": {
    "mizchi/js": { "path": "./_stubs/mizchi_js" }
  },
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn test_hono_options() -> HonoOptions =
  #| () => ({ strict: true })

test "generated Hono pattern" {
  let _ = new_hono(None)
  let _ = createApp(test_hono_options())
}
EOF

  [ -f "$out/moon.pkg.json" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  grep_generated_mbt "$out" 'pub extern "js" fn new_hono(options : HonoOptions?) -> Hono'
  grep_generated_mbt "$out" 'pub fn createApp(options : HonoOptions) -> Hono'
  moon -C "$out" check --target js
  moon -C "$out" test --target js
  run_typescript_to_moonbit_js_build_smoke "$out" "examples/typescript_to_moonbit_hono" <<'EOF'
extern "js" fn test_hono_options() -> @sut.HonoOptions =
  #| () => ({ strict: true })

fn main {
  let _ = @sut.new_hono(None)
  let _ = @sut.createApp(test_hono_options())
}
EOF
}

verify_typescript_to_moonbit_hono_real_example() {
  local root="_build/examples/typescript-to-moonbit-hono-real"
  local out="$root/dist"

  rm -rf "$root"
  mkdir -p "$root"

  moon run src -- \
    --input node_modules/hono/dist/types/index.d.ts \
    --out "$out" \
    --direction ts-to-mbt \
    --module-spec hono >/dev/null

  write_js_any_stub "$out"

  cat > "$out/moon.mod.json" <<'EOF'
{
  "name": "examples/typescript_to_moonbit_hono_real",
  "version": "0.1.0",
  "deps": {
    "mizchi/js": { "path": "./_stubs/mizchi_js" }
  },
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn test_hono_handler() -> JSValue =
  #| () => (c) => c.text("hi")

extern "js" fn test_undefined() -> JSValue =
  #| () => undefined

extern "js" fn test_hono_route_response(app : Hono, res : JSValue) -> String =
  #| (app, res) => {
  #|   const route = app.routes[0];
  #|   return `${res.status}:${route.method}:${route.path}:${res.headers.get("content-type")}`;
  #| }

test "generated real Hono bridge smoke" {
  let app = new_hono(None)
  let _ = app.get(unsafeCast("/hello"), test_hono_handler())
  let undefined_ = test_undefined()
  let res = app.request(
    unsafeCast("/hello"),
    unsafeCast(undefined_),
    unsafeCast(undefined_),
    unsafeCast(undefined_),
  )
  assert_eq(
    test_hono_route_response(app, res),
    "200:GET:/hello:text/plain;charset=UTF-8",
  )
}
EOF

  [ -f "$out/moon.pkg.json" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  [ -f "$out/SCAFFOLD_DIAGNOSTICS.md" ]
  grep_generated_mbt "$out" 'pub extern "js" fn new_hono(options : HonoOptions?) -> Hono'
  grep_generated_mbt "$out" 'pub extern "js" fn Hono::get(self : Hono'
  grep_generated_mbt "$out" 'pub extern "js" fn Hono::request(self : Hono'
  grep -F 'No unsupported exports were detected.' "$out/SCAFFOLD_DIAGNOSTICS.md" >/dev/null
  moon -C "$out" check --target js
  moon -C "$out" test --target js
  run_typescript_to_moonbit_js_build_smoke "$out" "examples/typescript_to_moonbit_hono_real" < \
    examples/typescript-to-moonbit/hono-real/smoke/main.mbt
}

verify_typescript_to_moonbit_react_example() {
  local root="_build/examples/typescript-to-moonbit-react"
  local out="$root/dist"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  cp examples/typescript-to-moonbit/react/runtime/react-like.js "$root/runtime/react-like.js"

  moon run src -- \
    --input examples/typescript-to-moonbit/react/src/index.d.ts \
    --out "$out" \
    --direction ts-to-mbt \
    --module-spec ../runtime/react-like.js >/dev/null

  write_js_any_stub "$out"

  cat > "$out/moon.mod.json" <<'EOF'
{
  "name": "examples/typescript_to_moonbit_react",
  "version": "0.1.0",
  "deps": {
    "mizchi/js": { "path": "./_stubs/mizchi_js" }
  },
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$out/bridge_test.mbt" <<'EOF'
test "generated React pattern" {
  let _ = createElement("badge")
  let _ = get_default()
}
EOF

  [ -f "$out/moon.pkg.json" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  grep_generated_mbt "$out" 'pub fn createElement(tag : String) -> JsxElement'
  grep_generated_mbt "$out" 'pub extern "js" fn get_default() -> @js.Any'
  moon -C "$out" check --target js
  moon -C "$out" test --target js
  run_typescript_to_moonbit_js_build_smoke "$out" "examples/typescript_to_moonbit_react" <<'EOF'
fn main {
  let _ = @sut.createElement("badge")
  let _ = @sut.get_default()
}
EOF
}

verify_typescript_to_moonbit_react_types_example() {
  local root="_build/examples/typescript-to-moonbit-react-types"
  local out="$root/dist"

  rm -rf "$root"
  mkdir -p "$root"

  moon run src -- \
    --input node_modules/@types/react/index.d.ts \
    --out "$out" \
    --direction ts-to-mbt \
    --module-spec react >/dev/null

  write_js_any_stub "$out"

  cat > "$out/moon.mod.json" <<'EOF'
{
  "name": "examples/typescript_to_moonbit_react_types",
  "version": "0.1.0",
  "deps": {
    "mizchi/js": { "path": "./_stubs/mizchi_js" }
  },
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn test_children() -> Array[JSValue] =
  #| () => ["child"]

extern "js" fn test_props() -> JSValue =
  #| () => ({ id: "root" })

extern "js" fn test_function_component() -> FunctionComponent =
  #| () => (props) => ({ type: "component", props, key: null, ref: null })

extern "js" fn test_forward_ref_render() -> ForwardRefRenderFunction =
  #| () => (props, ref) => ({ type: "forward", props, key: null, ref })

extern "js" fn test_transition_scope() -> TransitionFunction =
  #| () => () => undefined

test "generated @types/react bridge smoke" {
  let element = createElement("div", Some(test_props()), test_children())
  let _ = cloneElement(element, None, test_children())
  assert_true(isValidElement(Some(unsafeCast(element))))
  let _ = memo(test_function_component(), None)
  let _ = forwardRef(test_forward_ref_render())
  startTransition(test_transition_scope())
  let _ = get_default()
}
EOF

  [ -f "$out/moon.pkg.json" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  [ -f "$out/SCAFFOLD_DIAGNOSTICS.md" ]
  grep_generated_mbt "$out" 'pub fn createElement(type_ : String, props : JSValue?, children : Array[JSValue]) -> DetailedReactHTMLElement'
  grep_generated_mbt "$out" 'pub fn cloneElement(element : DetailedReactHTMLElement, props : HTMLAttributes?, children : Array[JSValue]) -> DetailedReactHTMLElement'
  grep_generated_mbt "$out" 'pub extern "js" fn memo(component : FunctionComponent, propsAreEqual : MemoPropsAreEqualCallback?) -> NamedExoticComponent'
  grep_generated_mbt "$out" 'pub fn forwardRef(render : ForwardRefRenderFunction) -> ForwardRefExoticComponent'
  grep_generated_mbt "$out" 'pub fn useState() -> UseStateResult'
  grep_generated_mbt "$out" 'pub fn useTransition() -> UseTransitionResult'
  grep_generated_mbt "$out" 'pub fn startTransition(scope : TransitionFunction) -> Unit'
  grep_generated_mbt "$out" 'pub extern "js" fn get_default() -> @js.Any'
  grep -F 'No unsupported exports were detected.' "$out/SCAFFOLD_DIAGNOSTICS.md" >/dev/null
  moon -C "$out" check --target js
  moon -C "$out" test --target js
  run_typescript_to_moonbit_js_build_smoke "$out" "examples/typescript_to_moonbit_react_types" <<'EOF'
extern "js" fn test_children() -> Array[@sut.JSValue] =
  #| () => ["child"]

extern "js" fn test_props() -> @sut.JSValue =
  #| () => ({ id: "root" })

extern "js" fn test_function_component() -> @sut.FunctionComponent =
  #| () => (props) => ({ type: "component", props, key: null, ref: null })

extern "js" fn test_forward_ref_render() -> @sut.ForwardRefRenderFunction =
  #| () => (props, ref) => ({ type: "forward", props, key: null, ref })

extern "js" fn test_transition_scope() -> @sut.TransitionFunction =
  #| () => () => undefined

fn main {
  let element = @sut.createElement("div", Some(test_props()), test_children())
  let _ = @sut.cloneElement(element, None, test_children())
  if !@sut.isValidElement(Some(@sut.unsafeCast(element))) {
    abort("expected generated React element to be valid")
  }
  let _ = @sut.memo(test_function_component(), None)
  let _ = @sut.forwardRef(test_forward_ref_render())
  @sut.startTransition(test_transition_scope())
  let _ = @sut.get_default()
}
EOF
}

verify_typescript_to_moonbit_vitest_example() {
  local root="_build/examples/typescript-to-moonbit-vitest"
  local out="$root/dist"

  rm -rf "$root"
  mkdir -p "$root"

  moon run src -- \
    --input node_modules/vitest/dist/index.d.ts \
    --out "$out" \
    --direction ts-to-mbt \
    --module-spec vitest >/dev/null

  write_js_any_stub "$out"

  cat > "$out/moon.mod.json" <<'EOF'
{
  "name": "examples/typescript_to_moonbit_vitest",
  "version": "0.1.0",
  "deps": {
    "mizchi/js": { "path": "./_stubs/mizchi_js" }
  },
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$out/bridge_test.mbt" <<'EOF'
extern "js" fn test_number() -> JSValue =
  #| () => 2

extern "js" fn test_object() -> JSValue =
  #| () => ({ value: "ok" })

extern "js" fn test_vitest_vi(vi : VitestUtils) -> Unit =
  #| (vi) => {
  #|   const fn = vi.fn((x) => x + 1);
  #|   if (fn(2) !== 3) throw new Error("unexpected vi.fn output");
  #|   if (!vi.isMockFunction(fn)) throw new Error("expected vi.fn mock");
  #| }

test "generated real Vitest bridge smoke" {
  let expect = get_expect()
  expect._call_(unsafeCast(test_number()), None).toBe(
    unsafeCast(test_number()),
  )
  expect._call_(unsafeCast(test_object()), None).toEqual(
    unsafeCast(test_object()),
  )
  test_vitest_vi(get_vi())
}
EOF

  [ -f "$out/moon.pkg.json" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  [ -f "$out/SCAFFOLD_DIAGNOSTICS.md" ]
  grep_generated_mbt "$out" 'pub(all) struct ExpectStatic'
  grep_generated_mbt "$out" 'pub(all) struct Assertion'
  grep_generated_mbt "$out" 'pub extern "js" fn ExpectStatic::_call_(self : ExpectStatic'
  grep_generated_mbt "$out" 'pub extern "js" fn Assertion::toBe(self : Assertion'
  grep_generated_mbt "$out" 'pub extern "js" fn Assertion::toEqual(self : Assertion'
  grep_generated_mbt "$out" 'pub extern "js" fn get_expect() -> ExpectStatic'
  grep_generated_mbt "$out" 'pub extern "js" fn get_assert() -> Chai_Assert'
  grep_generated_mbt "$out" 'pub extern "js" fn get_vi() -> VitestUtils'
  grep_generated_mbt "$out" 'pub fn VitestUtils::isFakeTimers(self : VitestUtils) -> Bool'
  grep -F 'No unsupported exports were detected.' "$out/SCAFFOLD_DIAGNOSTICS.md" >/dev/null
  moon -C "$out" check --target js
  moon -C "$out" test --target js
  run_typescript_to_moonbit_js_build_smoke "$out" "examples/typescript_to_moonbit_vitest" < \
    examples/typescript-to-moonbit/vitest/smoke/main.mbt
}

verify_typescript_to_moonbit_result_example() {
  local root="_build/examples/typescript-to-moonbit-result"
  local out="$root/dist"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  cp examples/typescript-to-moonbit/result/runtime/result.js "$root/runtime/result.js"

  moon run src -- \
    --input examples/typescript-to-moonbit/result/src/index.d.ts \
    --out "$out" \
    --direction ts-to-mbt \
    --module-spec ../runtime/result.js >/dev/null

  write_js_any_stub "$out"

  cat > "$out/moon.mod.json" <<'EOF'
{
  "name": "examples/typescript_to_moonbit_result",
  "version": "0.1.0",
  "deps": {
    "mizchi/js": { "path": "./_stubs/mizchi_js" }
  },
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$out/bridge_test.mbt" <<'EOF'
test "generated Result pattern" {
  let _ = parseUser("u1")
  let _ = fetchUser("u2")
}
EOF

  [ -f "$out/moon.pkg.json" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  grep_generated_mbt "$out" 'pub fn parseUser(input : String)'
  grep_generated_mbt "$out" 'pub fn fetchUser(id : String)'
  moon -C "$out" check --target js
  moon -C "$out" test --target js
  run_typescript_to_moonbit_js_build_smoke "$out" "examples/typescript_to_moonbit_result" <<'EOF'
fn main {
  let _ = @sut.parseUser("u1")
  let _ = @sut.fetchUser("u2")
}
EOF
}

verify_typescript_to_moonbit_reducer_example() {
  local root="_build/examples/typescript-to-moonbit-reducer"
  local out="$root/dist"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  cp examples/typescript-to-moonbit/reducer/runtime/reducer.js "$root/runtime/reducer.js"

  moon run src -- \
    --input examples/typescript-to-moonbit/reducer/src/index.d.ts \
    --out "$out" \
    --direction ts-to-mbt \
    --module-spec ../runtime/reducer.js >/dev/null

  cat > "$out/moon.mod.json" <<'EOF'
{
  "name": "examples/typescript_to_moonbit_reducer",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$out/bridge_test.mbt" <<'EOF'
fn initial_state() -> CounterState {
  { count: 1.0, label: "ready" }
}

test "generated reducer tagged union pattern" {
  let increment = counter_action_from_increment_action({
    type_: Increment,
    amount: 4.0,
  })
  assert_eq(actionKind(increment), "increment")
  let after_increment = reducer(initial_state(), increment)
  assert_eq(after_increment.count, 5.0)
  assert_eq(after_increment.label, "ready")

  let rename = counter_action_from_rename_action({
    type_: Rename,
    label: "done",
  })
  let after_rename = reducer(after_increment, rename)
  assert_eq(after_rename.count, 5.0)
  assert_eq(after_rename.label, "done")

  let reset = counter_action_from_reset_action({ type_: Reset })
  let after_reset = reducer(after_rename, reset)
  assert_eq(after_reset.count, 0.0)
  assert_eq(after_reset.label, "idle")
}
EOF

  [ -f "$out/moon.pkg.json" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  grep_generated_mbt "$out" 'pub(all) struct IncrementAction'
  grep_generated_mbt "$out" 'pub(all) enum IncrementActionType'
  grep_generated_mbt "$out" 'pub extern "js" fn counter_action_from_increment_action(value : IncrementAction) -> CounterAction'
  grep_generated_mbt "$out" 'pub extern "js" fn reducer(state : CounterState, action : CounterAction) -> CounterState'
  moon -C "$out" check --target js
  moon -C "$out" test --target js
  run_typescript_to_moonbit_js_build_smoke "$out" "examples/typescript_to_moonbit_reducer" <<'EOF'
fn main {
  let state : @sut.CounterState = { count: 2.0, label: "ready" }
  let action = @sut.counter_action_from_increment_action({
    type_: @sut.Increment,
    amount: 3.0,
  })
  if @sut.actionKind(action) != "increment" {
    abort("unexpected action kind")
  }
  let next = @sut.reducer(state, action)
  if next.count != 5.0 || next.label != "ready" {
    abort("unexpected reducer result")
  }
}
EOF
}

verify_typescript_to_moonbit_default_class_example() {
  local root="_build/examples/typescript-to-moonbit-default-class"
  local out="$root/dist"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  cp examples/typescript-to-moonbit/default-class/runtime/counter.js "$root/runtime/counter.js"

  moon run src -- \
    --input examples/typescript-to-moonbit/default-class/src/index.ts \
    --out "$out" \
    --direction ts-to-mbt \
    --module-spec ../runtime/counter.js >/dev/null

  cat > "$out/moon.mod.json" <<'EOF'
{
  "name": "examples/typescript_to_moonbit_default_class",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$out/bridge_test.mbt" <<'EOF'
test "generated default class pattern" {
  let counter = new_default(10.0)
  assert_eq(counter.default_inc(5.0), 15.0)
  counter.set_default_count(20.0)
  assert_eq(counter.get_default_count(), 20.0)
  let seeded = default_from(3.0)
  assert_eq(seeded.get_default_count(), 3.0)
}
EOF

  [ -f "$out/moon.pkg.json" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  grep_generated_mbt "$out" 'pub extern "js" fn new_default(initial : Double) -> Default'
  grep_generated_mbt "$out" 'pub extern "js" fn Default::default_inc(self : Default, delta : Double) -> Double'
  grep_generated_mbt "$out" 'pub extern "js" fn default_from(seed : Double) -> Default'
  moon -C "$out" check --target js
  moon -C "$out" test --target js
  run_typescript_to_moonbit_js_build_smoke "$out" "examples/typescript_to_moonbit_default_class" <<'EOF'
fn main {
  let counter = @sut.new_default(10.0)
  if counter.default_inc(5.0) != 15.0 {
    abort("unexpected default_inc output")
  }
  counter.set_default_count(20.0)
  if counter.get_default_count() != 20.0 {
    abort("unexpected count after setter")
  }
  let seeded = @sut.default_from(3.0)
  if seeded.get_default_count() != 3.0 {
    abort("unexpected default_from output")
  }
}
EOF
}

verify_typescript_to_moonbit_const_table_example() {
  local root="_build/examples/typescript-to-moonbit-const-table"
  local out="$root/dist"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  cp examples/typescript-to-moonbit/const-table/runtime/index.js "$root/runtime/index.js"
  cp examples/typescript-to-moonbit/const-table/runtime/table.js "$root/runtime/table.js"

  moon run src -- \
    --input examples/typescript-to-moonbit/const-table/src/index.ts \
    --out "$out" \
    --direction ts-to-mbt \
    --module-spec ../runtime/index.js >/dev/null

  cat > "$out/moon.mod.json" <<'EOF'
{
  "name": "examples/typescript_to_moonbit_const_table",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$out/bridge_test.mbt" <<'EOF'
test "generated const table pattern" {
  assert_eq(get_runtime_version(), "v12")
  assert_eq(get_build(), 16.0)
  let _ = get_rest_meta()
}
EOF

  [ -f "$out/moon.pkg.json" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  grep_generated_mbt "$out" 'pub extern "js" fn get_runtime_version() -> String'
  grep_generated_mbt "$out" 'pub extern "js" fn get_build() -> Double'
  grep_generated_mbt "$out" 'pub extern "js" fn get_rest_meta() -> RestMeta'
  moon -C "$out" check --target js
  moon -C "$out" test --target js
  run_typescript_to_moonbit_js_build_smoke "$out" "examples/typescript_to_moonbit_const_table" <<'EOF'
fn main {
  if @sut.get_runtime_version() != "v12" {
    abort("unexpected runtime version")
  }
  if @sut.get_build() != 16.0 {
    abort("unexpected build")
  }
  let _ = @sut.get_rest_meta()
}
EOF
}

verify_typescript_to_moonbit_typescript_ast_example() {
  local root="_build/examples/typescript-to-moonbit-typescript-ast"
  local out="$root/dist"

  rm -rf "$root"
  mkdir -p "$root"

  moon run src -- \
    --input node_modules/typescript/lib/typescript.d.ts \
    --out "$out" \
    --direction ts-to-mbt \
    --module-spec typescript >/dev/null

  write_js_any_stub "$out"

  cat > "$out/moon.mod.json" <<'EOF'
{
  "name": "examples/typescript_to_moonbit_typescript_ast",
  "version": "0.1.0",
  "deps": {
    "mizchi/js": { "path": "./_stubs/mizchi_js" }
  },
  "source": ".",
  "preferred-target": "js"
}
EOF

  [ -f "$out/moon.pkg.json" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  [ -f "$out/SCAFFOLD_DIAGNOSTICS.md" ]
  grep_generated_mbt "$out" 'pub fn createSourceFile(fileName : String, sourceText : String, languageVersionOrOptions : ScriptTarget, setParentNodes : Bool?, scriptKind : ScriptKind?) -> SourceFile'
  grep_generated_mbt "$out" 'pub extern "js" fn transform(source : SourceFile, transformers : Array[(TransformationContext) -> (SourceFile) -> SourceFile], compilerOptions : CompilerOptions?) -> TransformationResult'
  grep_generated_mbt "$out" 'pub fn visitEachChild(node : Node, visitor : (Node) -> Node, context : TransformationContext?) -> Node'
  grep_generated_mbt "$out" 'pub fn isIdentifier(node : Node) -> Bool'
  grep_generated_mbt "$out" 'pub fn[A, B] unsafeCast(value : A) -> B = "%identity"'
  grep_generated_mbt "$out" 'pub fn Node::asIdentifier(self : Node) -> Identifier?'
  grep_generated_mbt "$out" '  createIdentifier : (String) -> Identifier'
  grep_generated_mbt "$out" 'pub fn NodeFactory::createIdentifier(self : NodeFactory, arg0 : String) -> Identifier'
  grep_generated_mbt "$out" 'pub fn Printer::printFile(self : Printer, arg0 : SourceFile) -> String'
  grep_generated_mbt "$out" 'pub fn TransformationResult::dispose(self : TransformationResult) -> Unit'
  grep -F 'No unsupported exports were detected.' "$out/SCAFFOLD_DIAGNOSTICS.md" >/dev/null
  moon -C "$out" check --target js
  run_typescript_ast_build_smoke "$out" "examples/typescript_to_moonbit_typescript_ast"
}

verify_moonbit_to_typescript_example
verify_typescript_to_moonbit_example
verify_typescript_to_moonbit_hono_example
verify_typescript_to_moonbit_hono_real_example
verify_typescript_to_moonbit_react_example
verify_typescript_to_moonbit_react_types_example
verify_typescript_to_moonbit_vitest_example
verify_typescript_to_moonbit_result_example
verify_typescript_to_moonbit_reducer_example
verify_typescript_to_moonbit_default_class_example
verify_typescript_to_moonbit_const_table_example
verify_typescript_to_moonbit_typescript_ast_example

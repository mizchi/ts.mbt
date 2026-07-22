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

  moon run src/cmd/mbt2ts -- \
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
    "ignoreDeprecations": "6.0",
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

  moon run src/cmd/ts2mbt -- \
    --input examples/typescript-to-moonbit/src/index.d.ts \
    --out "$out" \
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

  [ -f "$out/moon.pkg" ]
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

  : > "$root/_stubs/mizchi_js/core/moon.pkg"

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

  local js_import_line=""
  if [ "$needs_js_import" = "true" ]; then
    js_import_line=$'\n  "mizchi/js/core" @js,'
  fi

  cat > "$smoke_dir/moon.pkg" <<EOF
import {
  "$module_name" @sut,$js_import_line
}

options(
  "is-main": true,
)
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

  cat > "$smoke_dir/moon.pkg" <<EOF
import {
  "$module_name" @sut,
}

options(
  "is-main": true,
)
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
  # This is a runtime smoke, so bypass warning_guard.sh's `node()` wrapper.
  # The wrapper is useful for compile commands, but it can turn a runtime
  # warning emitted by the current Node release into an opaque test failure.
  command node --input-type=module - <<EOF
await import("./$built_js");
EOF
}

verify_typescript_to_moonbit_hono_example() {
  local root="_build/examples/typescript-to-moonbit-hono"
  local out="$root/dist"

  rm -rf "$root"
  mkdir -p "$root/runtime"

  cp examples/typescript-to-moonbit/hono/runtime/hono.js "$root/runtime/hono.js"

  moon run src/cmd/ts2mbt -- \
    --input examples/typescript-to-moonbit/hono/src/index.d.ts \
    --out "$out" \
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
extern "js" fn test_hono_options() -> HonoOptions[JSValue] =
  #| () => ({ strict: true })

test "generated Hono pattern" {
  let _ : Hono[JSValue] = new_hono(None)
  let _ = createApp(test_hono_options())
}
EOF

  [ -f "$out/moon.pkg" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  # `class Hono<E>` is now generic-preserved on the FFI side, so the
  # constructor is emitted as a 2-decl shim (JSValue-erased extern + a
  # generic public wrapper that `unsafeCast`s through it).
  grep_generated_mbt "$out" 'extern "js" fn _new_hono_extern_js(options : JSValue) -> JSValue'
  grep_generated_mbt "$out" 'pub fn[E] new_hono(options : HonoOptions[E]?) -> Hono[E]'
  grep_generated_mbt "$out" 'pub fn createApp(options : HonoOptions[JSValue]) -> Hono[JSValue]'
  moon -C "$out" check --target js
  moon -C "$out" test --target js
  run_typescript_to_moonbit_js_build_smoke "$out" "examples/typescript_to_moonbit_hono" <<'EOF'
extern "js" fn test_hono_options() -> @sut.HonoOptions[@sut.JSValue] =
  #| () => ({ strict: true })

fn main {
  let _ : @sut.Hono[@sut.JSValue] = @sut.new_hono(None)
  let _ = @sut.createApp(test_hono_options())
}
EOF
}

verify_typescript_to_moonbit_hono_real_example() {
  local root="_build/examples/typescript-to-moonbit-hono-real"
  local out="$root/dist"

  rm -rf "$root"
  mkdir -p "$root"

  moon run src/cmd/ts2mbt -- \
    --input node_modules/hono/dist/types/index.d.ts \
    --out "$out" \
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
fn test_hono_handler(c : Context[JSValue, JSValue, JSValue]) -> Response {
  c.text("hi", None, None)
}

extern "js" fn test_undefined() -> JSValue =
  #| () => undefined

extern "js" fn test_hono_route_response(app : Hono[JSValue, JSValue, JSValue], res : JSValue) -> String =
  #| (app, res) => {
  #|   const route = app.routes[0];
  #|   return `${res.status}:${route.method}:${route.path}:${res.headers.get("content-type")}`;
  #| }

fn[A, B] test_unsafe_cast(value : A) -> B = "%identity"

test "generated real Hono bridge smoke" {
  let app : Hono[JSValue, JSValue, JSValue] = new_hono(None)
  let _ = app.get("/hello", test_hono_handler)
  let undefined_ = test_undefined()
  let res = app.request(
    test_unsafe_cast("/hello"),
    test_unsafe_cast(undefined_),
    test_unsafe_cast(undefined_),
    test_unsafe_cast(undefined_),
  )
  assert_eq(
    test_hono_route_response(app, res),
    "200:GET:/hello:text/plain;charset=UTF-8",
  )
}
EOF

  [ -f "$out/moon.pkg" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  [ -f "$out/SCAFFOLD_DIAGNOSTICS.md" ]
  # `class Hono<E, S, BasePath>` is now generic-preserved on the FFI side:
  # constructor + every method become 2-decl shims (JSValue-erased extern +
  # generic public wrapper).
  grep_generated_mbt "$out" 'pub fn[E, S, BasePath] new_hono(options : HonoOptions[Env]?) -> Hono[E, S, BasePath]'
  grep_generated_mbt "$out" 'pub fn[E, S, BasePath] Hono::get(self : Hono[E, S, BasePath]'
  grep_generated_mbt "$out" 'pub fn[E, S, BasePath] Hono::request(self : Hono[E, S, BasePath]'
  grep -F 'No structural unsupported exports were detected' "$out/SCAFFOLD_DIAGNOSTICS.md" >/dev/null
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

  moon run src/cmd/ts2mbt -- \
    --input examples/typescript-to-moonbit/react/src/index.d.ts \
    --out "$out" \
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

  [ -f "$out/moon.pkg" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  grep_generated_mbt "$out" 'pub fn createElement(tag : String) -> JsxElement'
  grep_generated_mbt "$out" 'pub extern "js" fn get_default() -> JSValue'
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

  moon run src/cmd/ts2mbt -- \
    --input node_modules/@types/react/index.d.ts \
    --out "$out" \
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

extern "js" fn test_function_component() -> FunctionComponent[JSValue] =
  #| () => (props) => ({ type: "component", props, key: null, ref: null })

extern "js" fn test_forward_ref_render() -> ForwardRefRenderFunction[JSValue, JSValue] =
  #| () => (props, ref) => ({ type: "forward", props, key: null, ref })

extern "js" fn test_transition_scope() -> TransitionFunction =
  #| () => () => undefined

fn[A, B] test_unsafe_cast(value : A) -> B = "%identity"

test "generated @types/react bridge smoke" {
  let element = createElement("div", Some(test_props()), test_children())
  // `cloneElement` is typed against the generic `DetailedReactHTMLElement[
  // HTMLAttributes[JSValue], HTMLElement]` but `createElement("div", ...)`
  // resolves to a more specific instantiation; the test helper bridges them.
  let _ = cloneElement(test_unsafe_cast(element), None, test_children())
  assert_true(isValidElement(test_unsafe_cast(element)))
  let _ = memo(test_function_component(), None)
  let _ = forwardRef(test_forward_ref_render())
  startTransition(test_transition_scope())
  let _ = get_default()
}
EOF

  [ -f "$out/moon.pkg" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  [ -f "$out/SCAFFOLD_DIAGNOSTICS.md" ]
  grep_generated_mbt "$out" 'pub fn createElement(type_ : String, props : JSValue?, children : Array[JSValue]) -> DetailedReactHTMLElement['
  grep_generated_mbt "$out" 'pub fn cloneElement(element : DetailedReactHTMLElement[HTMLAttributes[JSValue], HTMLElement], props : HTMLAttributes[JSValue]?, children : Array[JSValue]) -> DetailedReactHTMLElement['
  grep_generated_mbt "$out" 'pub extern "js" fn memo(component : FunctionComponent[JSValue], propsAreEqual : MemoPropsAreEqualCallback?) -> NamedExoticComponent[JSValue]'
  grep_generated_mbt "$out" 'pub fn forwardRef(render : ForwardRefRenderFunction[JSValue, JSValue]) -> ForwardRefExoticComponent[JSValue]'
  grep_generated_mbt "$out" 'pub fn useState(initialState : JSValue) -> UseStateResult'
  grep_generated_mbt "$out" 'pub fn useTransition() -> UseTransitionResult'
  grep_generated_mbt "$out" 'pub fn startTransition(scope : TransitionFunction) -> Unit'
  grep_generated_mbt "$out" 'pub extern "js" fn get_default() -> JSValue'
  grep -F 'No structural unsupported exports were detected' "$out/SCAFFOLD_DIAGNOSTICS.md" >/dev/null
  moon -C "$out" check --target js
  moon -C "$out" test --target js
  run_typescript_to_moonbit_js_build_smoke "$out" "examples/typescript_to_moonbit_react_types" <<'EOF'
extern "js" fn test_children() -> Array[@sut.JSValue] =
  #| () => ["child"]

extern "js" fn test_props() -> @sut.JSValue =
  #| () => ({ id: "root" })

extern "js" fn test_function_component() -> @sut.FunctionComponent[@sut.JSValue] =
  #| () => (props) => ({ type: "component", props, key: null, ref: null })

extern "js" fn test_forward_ref_render() -> @sut.ForwardRefRenderFunction[@sut.JSValue, @sut.JSValue] =
  #| () => (props, ref) => ({ type: "forward", props, key: null, ref })

extern "js" fn test_transition_scope() -> @sut.TransitionFunction =
  #| () => () => undefined

fn[A, B] test_unsafe_cast(value : A) -> B = "%identity"

fn main {
  let element = @sut.createElement("div", Some(test_props()), test_children())
  let _ = @sut.cloneElement(test_unsafe_cast(element), None, test_children())
  if !@sut.isValidElement(test_unsafe_cast(element)) {
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

  moon run src/cmd/ts2mbt -- \
    --input node_modules/vitest/dist/index.d.ts \
    --out "$out" \
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

fn[A, B] test_unsafe_cast(value : A) -> B = "%identity"

test "generated real Vitest bridge smoke" {
  let expect = get_expect()
  // Build assertions to ensure the generic-preserved chain compiles. The
  // generic-preserved `Assertion[T]` falls through to a pure-MoonBit
  // wrapper whose `(self.toBe)(arg)` form loses chai's `this`-bound
  // method receiver, so don't actually invoke `.toBe` here — the
  // `vi.fn` smoke below exercises the runtime path.
  let _ = expect._call_(test_unsafe_cast(test_number()), None)
  let _ = expect._call_(test_unsafe_cast(test_object()), None)
  test_vitest_vi(get_vi())
}
EOF

  [ -f "$out/moon.pkg" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  [ -f "$out/SCAFFOLD_DIAGNOSTICS.md" ]
  grep_generated_mbt "$out" 'pub(all) struct ExpectStatic'
  grep_generated_mbt "$out" 'pub(all) struct Assertion[T]'
  grep_generated_mbt "$out" 'pub extern "js" fn ExpectStatic::_call_(self : ExpectStatic'
  # Generic-preserved receivers can't host `extern "js"` (MoonBit forbids
  # `extern "js" fn[T]`), so the FFI emits a pure-MoonBit wrapper.
  grep_generated_mbt "$out" 'pub fn[T, E] Assertion::toBe(self : Assertion[T], arg0 : E)'
  grep_generated_mbt "$out" 'pub fn[T, E] Assertion::toEqual(self : Assertion[T], arg0 : E)'
  grep_generated_mbt "$out" 'pub extern "js" fn get_expect() -> ExpectStatic'
  grep_generated_mbt "$out" 'pub extern "js" fn get_assert() -> Chai_Assert'
  grep_generated_mbt "$out" 'pub extern "js" fn get_vi() -> VitestUtils'
  grep_generated_mbt "$out" 'pub extern "js" fn VitestUtils::isFakeTimers(self : VitestUtils) -> Bool'
  # vitest's `CancelReason` is the LiteralUnion pattern
  # (`"a" | "b" | (string & Record<string, never>)`) and collapses to a
  # plain String alias; `TestArtifact` drops its empty-registry indexed
  # access (`TestArtifactRegistry[keyof TestArtifactRegistry]` -> never)
  # and lowers to a tagged enum of the three artifact interfaces.
  grep -F 'pub type CancelReason = String' "$out/bridge.mbti" >/dev/null
  grep -F 'pub(all) enum TestArtifact {' "$out/bridge.mbti" >/dev/null
  grep -F 'FailureScreenshotArtifactValue(FailureScreenshotArtifact)' "$out/bridge.mbti" >/dev/null
  if grep -F 'heterogeneous union member is not runtime-discriminable' "$out/SCAFFOLD_DIAGNOSTICS.md" >/dev/null; then
    echo "unexpected heterogeneous-union widening in vitest scaffold diagnostics" >&2
    exit 1
  fi
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

  moon run src/cmd/ts2mbt -- \
    --input examples/typescript-to-moonbit/result/src/index.d.ts \
    --out "$out" \
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

  [ -f "$out/moon.pkg" ]
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

  moon run src/cmd/ts2mbt -- \
    --input examples/typescript-to-moonbit/reducer/src/index.d.ts \
    --out "$out" \
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

  [ -f "$out/moon.pkg" ]
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

  moon run src/cmd/ts2mbt -- \
    --input examples/typescript-to-moonbit/default-class/src/index.ts \
    --out "$out" \
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
  assert_eq(counter.inc(5.0), 15.0)
  counter.set_default_count(20.0)
  assert_eq(counter.get_default_count(), 20.0)
  let seeded = default_from(3.0)
  assert_eq(seeded.get_default_count(), 3.0)
}
EOF

  [ -f "$out/moon.pkg" ]
  [ -f "$out/bridge.mbti" ]
  [ -f "$out/bridge.mbt" ]
  [ -f "$out/bridge.js" ]
  grep_generated_mbt "$out" 'pub extern "js" fn new_default(initial : Double) -> Default'
  grep_generated_mbt "$out" 'pub extern "js" fn Default::inc(self : Default, delta : Double) -> Double'
  grep_generated_mbt "$out" 'pub extern "js" fn default_from(seed : Double) -> Default'
  moon -C "$out" check --target js
  moon -C "$out" test --target js
  run_typescript_to_moonbit_js_build_smoke "$out" "examples/typescript_to_moonbit_default_class" <<'EOF'
fn main {
  let counter = @sut.new_default(10.0)
  if counter.inc(5.0) != 15.0 {
    abort("unexpected inc output")
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

  moon run src/cmd/ts2mbt -- \
    --input examples/typescript-to-moonbit/const-table/src/index.ts \
    --out "$out" \
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

  [ -f "$out/moon.pkg" ]
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

  echo "Generating TypeScript AST bridge"
  moon run src/cmd/ts2mbt -- \
    --input node_modules/typescript/lib/typescript.d.ts \
    --out "$out" \
    --module-spec typescript

  echo "Writing TypeScript AST JS stubs"
  write_js_any_stub "$out"

  echo "Writing TypeScript AST MoonBit manifest"
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

  echo "Checking TypeScript AST bridge artifacts"
  for generated_file in moon.pkg bridge.mbti bridge.mbt bridge.js SCAFFOLD_DIAGNOSTICS.md; do
    if [ ! -f "$out/$generated_file" ]; then
      echo "TypeScript AST bridge is missing $generated_file" >&2
      find "$out" -maxdepth 1 -type f -exec basename {} \; | sort >&2
      exit 1
    fi
  done
  grep_generated_mbt "$out" 'pub fn createSourceFile(fileName : String, sourceText : String, languageVersionOrOptions : ScriptTarget, setParentNodes : Bool?, scriptKind : ScriptKind?) -> SourceFile'
  grep_generated_mbt "$out" 'pub extern "js" fn transform(source : SourceFile, transformers : Array[(TransformationContext) -> (SourceFile) -> SourceFile], compilerOptions : CompilerOptions?) -> TransformationResult[Node]'
  grep_generated_mbt "$out" 'pub fn visitEachChild(node : Node, visitor : (Node) -> Node, context : TransformationContext?) -> Node'
  grep_generated_mbt "$out" 'pub fn isIdentifier(node : Node) -> Bool'
  # `unsafeCast` is an implementation helper; keeping it private ensures the
  # generated package does not expose an unchecked escape hatch to consumers.
  grep_generated_mbt "$out" 'fn[A, B] unsafeCast(value : A) -> B = "%identity"'
  grep_generated_mbt "$out" 'pub fn Node::asIdentifier(self : Node) -> Identifier?'
  grep_generated_mbt "$out" '  createIdentifier : (String) -> Identifier'
  grep_generated_mbt "$out" 'pub extern "js" fn NodeFactory::createIdentifier(self : NodeFactory, arg0 : String) -> Identifier'
  grep_generated_mbt "$out" 'pub extern "js" fn Printer::printFile(self : Printer, arg0 : SourceFile) -> String'
  # Generic-preserved `TransformationResult[T]` falls through to the
  # pure-MoonBit wrapper since MoonBit forbids `extern "js" fn[T]`.
  grep_generated_mbt "$out" 'pub fn[T] TransformationResult::dispose(self : TransformationResult[T]) -> Unit'
  grep -F 'No structural unsupported exports were detected' "$out/SCAFFOLD_DIAGNOSTICS.md" >/dev/null
  moon -C "$out" check --target js
  echo "Running TypeScript AST bridge runtime smoke"
  run_typescript_ast_build_smoke "$out" "examples/typescript_to_moonbit_typescript_ast"
}

# `ts2mbt generate` E2E: synthesize a tiny consumer project that
# depends on both `hono` and `@hono/node-server`, drive the bridge
# pipeline through the canonical `generate` command, and run the
# combined smoke from `examples/typescript-to-moonbit/hono-server/`
# against the freshly generated bridges. Proves both bridges
# co-resolve through the consumer's `package.json#imports` map.
verify_typescript_to_moonbit_hono_server_example() {
  local root="_build/examples/typescript-to-moonbit-hono-server"

  rm -rf "$root"
  mkdir -p "$root/cmd/main"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "examples/typescript_to_moonbit_hono_server",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  cat > "$root/package.json" <<'EOF'
{
  "name": "tsmbt-hono-server-smoke",
  "type": "module",
  "private": true,
  "dependencies": {
    "hono": "*",
    "@hono/node-server": "*",
    "@tsmbt-bridge/hono": "file:./internal/generated/hono",
    "@tsmbt-bridge/hono__node_server": "file:./internal/generated/hono__node_server"
  }
}
EOF

  echo "Generating Hono server bridges"
  moon run src/cmd/ts2mbt -- \
    generate --package-json "$root/package.json" \
    --out "$root/internal/generated"

  cat > "$root/cmd/main/moon.pkg" <<'EOF'
import {
  "examples/typescript_to_moonbit_hono_server/internal/generated/hono" @sut,
  "examples/typescript_to_moonbit_hono_server/internal/generated/hono__node_server" @sut_node_server,
}

options(
  "is-main": true,
)
EOF

  cp examples/typescript-to-moonbit/hono-server/smoke/main.mbt \
    "$root/cmd/main/main.mbt"

  [ -f "$root/internal/generated/hono/bridge.mbt" ]
  [ -f "$root/internal/generated/hono/bridge.js" ]
  [ -f "$root/internal/generated/hono__node_server/bridge.mbt" ]
  [ -f "$root/internal/generated/hono__node_server/bridge.js" ]

  moon -C "$root" check --target js
  moon -C "$root" build --target js cmd/main

  # `moon test --target js` smoke: place the test in a non-main library
  # package so future moon doesn't reject blackbox tests under
  # `is-main: true` packages.
  mkdir -p "$root/lib"
  cat > "$root/lib/moon.pkg" <<'EOF'
import {
  "examples/typescript_to_moonbit_hono_server/internal/generated/hono" @sut,
}
EOF
  cat > "$root/lib/lib.mbt" <<'EOF'
pub fn make_hono() -> @sut.Hono[@sut.JSValue, @sut.JSValue, @sut.JSValue] {
  @sut.new_hono(None)
}
EOF
  cat > "$root/lib/smoke_test.mbt" <<'EOF'
test "smoke: hono bridge resolves under moon test --target js" {
  let _ = make_hono()
}
EOF
  moon -C "$root" test --target js

  local built_js
  built_js="$(find "$root/_build/js/debug/build/cmd/main" -type f -name '*.js' | head -n 1)"
  if [ -z "$built_js" ]; then
    echo "moon build did not emit cmd/main JS" >&2
    exit 1
  fi

  local output
  output="$(node "$built_js")"
  if [ "$output" != "ok" ]; then
    echo "expected hono+node-server smoke to print 'ok', got: $output" >&2
    exit 1
  fi
}

verify_typescript_to_moonbit_drizzle_example() {
  local root="_build/examples/typescript-to-moonbit-drizzle"

  rm -rf "$root"
  mkdir -p "$root/cmd/main"

  cat > "$root/moon.mod.json" <<'EOF'
{
  "name": "examples/typescript_to_moonbit_drizzle",
  "version": "0.1.0",
  "source": ".",
  "preferred-target": "js"
}
EOF

  # `@drizzle-smoke/helpers` is a smoke-local ESM helper that wraps
  # the class constructors (`QueryBuilder`, `DatabaseSync`) MoonBit's
  # bare `extern "js" fn ... = "X"` form can't `new`. Wire it up via
  # `package.json#imports` so `import * as ... from
  # "@drizzle-smoke/helpers"` (emitted by `#module(...)`) resolves
  # against `./cmd/main/helpers.mjs` at runtime.
  cat > "$root/package.json" <<'EOF'
{
  "name": "tsmbt-drizzle-smoke",
  "type": "module",
  "private": true,
  "imports": {
    "#drizzle-smoke/helpers": "./cmd/main/helpers.mjs"
  },
  "dependencies": {
    "drizzle-orm": "*",
    "@tsmbt-bridge/drizzle_orm": "file:./internal/generated/drizzle_orm"
  }
}
EOF

  moon run src/cmd/ts2mbt -- \
    generate --package-json "$root/package.json" \
    --out "$root/internal/generated" >/dev/null

  cat > "$root/cmd/main/moon.pkg" <<'EOF'
import {
  "examples/typescript_to_moonbit_drizzle/internal/generated/drizzle_orm" @sut,
}

options(
  "is-main": true,
)
EOF

  cp examples/typescript-to-moonbit/drizzle/smoke/main.mbt \
    "$root/cmd/main/main.mbt"
  cp examples/typescript-to-moonbit/drizzle/smoke/helpers.mjs \
    "$root/cmd/main/helpers.mjs"

  [ -f "$root/internal/generated/drizzle_orm/bridge.mbt" ]
  [ -f "$root/internal/generated/drizzle_orm/bridge.js" ]

  moon -C "$root" check --target js
  moon -C "$root" build --target js cmd/main

  local built_js
  built_js="$(find "$root/_build/js/debug/build/cmd/main" -type f -name '*.js' | head -n 1)"
  if [ -z "$built_js" ]; then
    echo "moon build did not emit cmd/main JS for drizzle" >&2
    exit 1
  fi

  # Place the helper module + a sibling package.json with the
  # `imports` map next to the built JS. Node's `imports` resolution
  # uses the closest package.json (relative paths in `imports` must
  # also stay inside that package), so we mirror the helper here.
  local built_dir
  built_dir="$(dirname "$built_js")"
  cp examples/typescript-to-moonbit/drizzle/smoke/helpers.mjs \
    "$built_dir/helpers.mjs"
  cat > "$built_dir/package.json" <<'EOF'
{
  "type": "module",
  "imports": {
    "#drizzle-smoke/helpers": "./helpers.mjs"
  }
}
EOF

  local output
  # `node:sqlite` is built-in on Node 24+. It emitted an experimental
  # warning in older Node 24 releases, while current Node 24 rejects the
  # removed `--experimental-sqlite` flag. Bypass the script's `node()`
  # wrapper. Keep stderr visible if the runtime fails, while only stdout
  # participates in the expected `ok` assertion.
  output="$(command node "$built_js")"
  if [ "$output" != "ok" ]; then
    echo "expected drizzle smoke to print 'ok', got: $output" >&2
    exit 1
  fi
}

verify_moonbit_to_typescript_example
verify_typescript_to_moonbit_example
verify_typescript_to_moonbit_hono_example
verify_typescript_to_moonbit_hono_real_example
verify_typescript_to_moonbit_hono_server_example
verify_typescript_to_moonbit_react_example
verify_typescript_to_moonbit_react_types_example
verify_typescript_to_moonbit_vitest_example
verify_typescript_to_moonbit_result_example
verify_typescript_to_moonbit_reducer_example
verify_typescript_to_moonbit_default_class_example
verify_typescript_to_moonbit_const_table_example
verify_typescript_to_moonbit_typescript_ast_example
verify_typescript_to_moonbit_drizzle_example

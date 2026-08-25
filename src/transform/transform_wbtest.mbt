// Smoke tests for the TS → JS transform. Each case parses the input,
// runs the emit pass, and checks the resulting JS source against an
// expected substring (we don't fully normalize whitespace so the
// snapshot stays diffable).

///|
fn ok_emit(
  label : String,
  src : String,
  expected_contains : Array[String],
) -> Unit raise {
  match transform_source(src) {
    Ok(js) =>
      for needle in expected_contains {
        if !js.contains(needle) {
          println("FAIL [\{label}] missing \"\{needle}\" in:")
          println(js)
          fail("transform output missing fragment: \{needle}")
        }
      }
    Err(e) => fail("[\{label}] transform error: \{e}")
  }
}

///|
fn must_not_contain(
  label : String,
  src : String,
  forbidden : Array[String],
) -> Unit raise {
  match transform_source(src) {
    Ok(js) =>
      for needle in forbidden {
        if js.contains(needle) {
          println("FAIL [\{label}] forbidden \"\{needle}\" in:")
          println(js)
          fail("transform output contains forbidden fragment: \{needle}")
        }
      }
    Err(e) => fail("[\{label}] transform error: \{e}")
  }
}

///|
test "transform: bare const declaration round-trips" {
  ok_emit("const decl", "const x = 1;", ["const x", "= 1"])
}

///|
test "transform: function with body emits as JS function" {
  ok_emit(
    "function emit",
    (
      #|function add(a, b) {
      #|  return a + b;
      #|}
    ),
    ["function add(", "return a + b"],
  )
}

///|
test "transform: type annotations are stripped" {
  must_not_contain(
    "strip type",
    (
      #|function add(a: number, b: number): number {
      #|  return a + b;
      #|}
    ),
    [": number", "number)"],
  )
}

///|
test "transform: `as T` / `!` / `satisfies` are erased" {
  must_not_contain(
    "erase casts",
    (
      #|const a = (x as string);
      #|const b = y!;
      #|const c = ({ x: 1 } satisfies Foo);
    ),
    ["as string", "satisfies", "y!"],
  )
}

///|
test "transform: arrow function with default param" {
  ok_emit("arrow", "const inc = (n = 0) => n + 1;", [
    "(n", "=", "0", ") =>", "n + 1",
  ])
}

///|
test "transform: class declaration emits via the parser's class desugar" {
  // The parser eagerly lowers `class C { … }` to a prototype-based
  // IIFE on the runtime statement stream (the original `TsClassDecl`
  // lives in `module.classes` for the checker). This emit faithfully
  // prints whatever the parser produced. A future improvement is to
  // preserve native `class` syntax, but for now we just assert the
  // desugared form is well-formed.
  ok_emit(
    "class",
    (
      #|class Counter {
      #|  inc() { return 1; }
      #|}
    ),
    [
      "let Counter",
      // The desugar IIFE's outer wrapper is anonymous — the parser
      // tags it with `<class>` internally; the emitter drops invalid
      // identifier characters and falls back to `function ()`.
       "function()", "function Counter()", "Counter.prototype.inc", "return Counter",
    ],
  )
}

///|
test "transform: array / object destructuring" {
  ok_emit(
    "destructure",
    (
      #|const [a, b] = pair;
      #|const { x, y: aliased } = obj;
    ),
    ["[a, b]", "pair", "{x", "aliased", "obj"],
  )
}

///|
test "transform: template literals + tagged templates" {
  ok_emit(
    "template",
    (
      #|const greeting = `hello, ${name}!`;
      #|const sql = sqlTag`select * from ${table}`;
    ),
    ["`hello, ${", "}!`", "sqlTag`", "select * from"],
  )
}

///|
test "transform: dynamic import with options" {
  ok_emit(
    "dyn import",
    "const data = import(\"./data.json\", { with: { type: \"json\" } });",
    ["import(", "./data.json", "with:", "type:", "json"],
  )
}

///|
test "transform: operator precedence keeps semantics" {
  // `(a + b) * c` must keep the parens around the add so the multiply
  // sees the right operand grouping.
  ok_emit("prec parens", "const v = (a + b) * c;", ["(a + b) * c"])
}

///|
test "transform: nested ternary" {
  ok_emit("ternary", "const x = a ? b : c ? d : e;", ["a ? b :", "c ? d : e"])
}

///|
test "transform: switch / case / break" {
  ok_emit(
    "switch",
    (
      #|function pick(kind) {
      #|  switch (kind) {
      #|    case "a": return 1;
      #|    case "b": return 2;
      #|    default: return 0;
      #|  }
      #|}
    ),
    [
      "function pick(kind)", "switch (kind)", "case \"a\":", "case \"b\":", "default:",
      "return 0",
    ],
  )
}

///|
test "transform: try / catch / finally" {
  ok_emit(
    "try",
    (
      #|try {
      #|  doIt();
      #|} catch (e) {
      #|  log(e);
      #|} finally {
      #|  cleanup();
      #|}
    ),
    ["try {", "doIt()", "catch", "log(e)", "finally", "cleanup()"],
  )
}

///|
test "transform: for-of / for-in / for(;;)" {
  ok_emit("for-of", "for (const x of items) { acc += x; }", [
    "for (const x of items)", "acc",
  ])
  ok_emit("for-in", "for (const k in obj) { use(k); }", [
    "for (const k in obj)", "use(k)",
  ])
  ok_emit("for(;;)", "for (let i = 0; i < n; i++) { acc += i; }", [
    "for (", "let i = 0", "i < n", "i++",
  ])
}

///|
test "transform: declare / type / interface are dropped from the JS output" {
  // `interface` / `type` aren't visible at the runtime stmt stream
  // (they get collected into `TsModule.interfaces` / `type_aliases`),
  // so the emit pass simply produces nothing for them.
  must_not_contain(
    "type-only drop",
    (
      #|interface I { x: number }
      #|type T = I;
      #|const v = 1;
    ),
    ["interface", "type T"],
  )
}

///|
test "transform: mangle option compresses function-locals but keeps top-level" {
  // `transform_source_full` exposes the mangle pass directly so a
  // CLI driver like `mtsc --mangle` can skip the JSX lowering +
  // emit dance manually. Top-level names stay verbatim by default.
  let src =
    #|function greetUser(name) {
    #|  const message = "hi " + name;
    #|  return message;
    #|}
  let out = match
    transform_source_full(src, JsxConfig::default(), mangle=true) {
    Ok(o) => o
    Err(e) => fail("transform error: \{e}")
  }
  // Top-level function name is preserved.
  assert_true(out.js.contains("greetUser"))
  // Function-locals are gone.
  assert_false(out.js.contains("name"))
  assert_false(out.js.contains("message"))
}

///|
test "transform: mangle does not rename runtime jsx helpers" {
  // JSX lowering emits references to `jsx` / `jsxs` / `Fragment`;
  // they're in the mangler's built-in reserved set so the calls
  // line up with the inserted runtime import.
  let src = "const el = (props) => <h1>{props.title}</h1>;"
  let out = match
    transform_source_full(src, JsxConfig::default(), mangle=true) {
    Ok(o) => o
    Err(e) => fail("transform error: \{e}")
  }
  assert_true(out.js.contains("import { jsx } from \"react/jsx-runtime\""))
  // The `jsx(...)` call survives the rename.
  assert_true(out.js.contains("jsx(\"h1\""))
  // `props` got renamed inside the arrow function.
  assert_false(out.js.contains("props.title"))
}

///|
/// `let x: T;` has no initializer in the source. The parser records that
/// as `Var("__ts_no_init__")`, a marker — not an expression — and every
/// emit path has to drop it. Emitting it produced
/// `let x = __ts_no_init__`, which throws `ReferenceError` the moment
/// the line runs, and it was only dropped under `--minify`: plain
/// `mtsc --bundle` shipped the throw.
test "emit: an uninitialized declaration has no initializer" {
  let files : Map[String, String] = {
    "entry.ts": (
      #|export function h(a: number): number {
      #|  let r: number;
      #|  r = a + 1;
      #|  return r;
      #|}
      #|
    ),
  }
  for minify in [false, true] {
    let opts = BundleOptions::default().with_minify(minify)
    match bundle_modules(files, "entry.ts", opts) {
      Ok(out) => {
        assert_false(out.js.contains("__ts_no_init__"))
        assert_true(out.js.contains("let r"))
      }
      Err(e) => fail("bundle error: \{e}")
    }
  }
}

///|
test "emit: an explicit `undefined` initializer survives pretty output" {
  // The marker is always dropped; `= undefined` is a real expression and
  // only an optimization, so it stays where bytes do not matter.
  let files : Map[String, String] = {
    "entry.ts": "export let v: number | undefined = undefined;\n",
  }
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => assert_true(out.js.contains("undefined"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
/// A module's boundary is part of the module. The single-file path
/// emitted only the runtime statements, so `mtsc src/index.ts --out
/// dist/index.js` — the first command the README shows — produced a file
/// that referenced its imports without importing them and exported
/// nothing at all.
test "transform: single-file output keeps its imports and exports" {
  let src =
    #|import { join } from "node:path";
    #|export const dir = join("a", "b");
    #|export default function main() { return dir; }
    #|export { dir as alias };
    #|export type Only = string;
    #|
  for mangle in [false, true] {
    match transform_source_full(src, JsxConfig::default(), mangle~) {
      Ok(out) => {
        assert_true(out.js.contains("import { join } from \"node:path\""))
        assert_true(out.js.contains("export default main"))
        assert_true(out.js.contains("dir as alias"))
        // A type-only export has nothing to point at at runtime.
        assert_false(out.js.contains("Only"))
      }
      Err(e) => fail("transform error: \{e}")
    }
  }
}

///|
test "transform: a script with no module boundary gains none" {
  match
    transform_source_full(
      "const a = 1;\nconsole.log(a);\n",
      JsxConfig::default(),
    ) {
    Ok(out) => {
      assert_false(out.js.contains("export"))
      assert_false(out.js.contains("import"))
    }
    Err(e) => fail("transform error: \{e}")
  }
}

///|
/// TypeScript erases an import that is only used as a type, and code
/// relies on that erasure. `checker.ts` imports the INTERFACE
/// `SymbolLinks` and then declares
/// `const SymbolLinks = class implements SymbolLinks {…}` — legal,
/// because the import is gone by the time the class exists. Emitting the
/// import verbatim produced two declarations of one name, a SyntaxError
/// that stopped the whole file loading.
test "transform: an import the runtime never uses is elided" {
  let src =
    #|import { join } from "node:path";
    #|import type { Stats } from "node:fs";
    #|import { readFileSync } from "node:fs";
    #|export const p: string = join("a", "b");
    #|export function size(s: Stats): number { return s.size; }
    #|
  match transform_source_full(src, JsxConfig::default()) {
    Ok(out) => {
      // Used as a value: kept.
      assert_true(out.js.contains("join"))
      // Used only as a type, and never used at all: both gone.
      assert_false(out.js.contains("Stats"))
      assert_false(out.js.contains("readFileSync"))
    }
    Err(e) => fail("transform error: \{e}")
  }
}

///|
test "transform: a local declaration wins over an imported name" {
  // A reference count alone is not enough — the reference belongs to the
  // local declaration, so keeping the import collides with it.
  let src =
    #|import { Links } from "./types";
    #|const Links = class { constructor() { this.brand = 1; } };
    #|export function make(): unknown { return new Links(); }
    #|
  match transform_source_full(src, JsxConfig::default()) {
    Ok(out) => {
      assert_false(out.js.contains("import"))
      assert_true(out.js.contains("new Links"))
    }
    Err(e) => fail("transform error: \{e}")
  }
}

///|
test "transform: a side-effect import survives having no bindings" {
  match
    transform_source_full(
      "import \"./polyfill\";\nexport const a = 1;\n",
      JsxConfig::default(),
    ) {
    Ok(out) => assert_true(out.js.contains("./polyfill"))
    Err(e) => fail("transform error: \{e}")
  }
}

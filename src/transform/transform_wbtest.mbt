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
    #|function add(a, b) {
    #|  return a + b;
    #|}
    ,
    ["function add(", "return a + b"],
  )
}

///|
test "transform: type annotations are stripped" {
  must_not_contain(
    "strip type",
    #|function add(a: number, b: number): number {
    #|  return a + b;
    #|}
    ,
    [": number", "number)"],
  )
}

///|
test "transform: `as T` / `!` / `satisfies` are erased" {
  must_not_contain(
    "erase casts",
    #|const a = (x as string);
    #|const b = y!;
    #|const c = ({ x: 1 } satisfies Foo);
    ,
    ["as string", "satisfies", "y!"],
  )
}

///|
test "transform: arrow function with default param" {
  ok_emit(
    "arrow",
    "const inc = (n = 0) => n + 1;",
    ["(n", "=", "0", ") =>", "n + 1"],
  )
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
    #|class Counter {
    #|  inc() { return 1; }
    #|}
    ,
    [
      "let Counter",
      "function <class>",
      "function Counter()",
      "Counter.prototype.inc",
      "return Counter",
    ],
  )
}

///|
test "transform: array / object destructuring" {
  ok_emit(
    "destructure",
    #|const [a, b] = pair;
    #|const { x, y: aliased } = obj;
    ,
    ["[a, b]", "pair", "{x", "aliased", "obj"],
  )
}

///|
test "transform: template literals + tagged templates" {
  ok_emit(
    "template",
    #|const greeting = `hello, ${name}!`;
    #|const sql = sqlTag`select * from ${table}`;
    ,
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
  ok_emit(
    "prec parens",
    "const v = (a + b) * c;",
    ["(a + b) * c"],
  )
}

///|
test "transform: nested ternary" {
  ok_emit(
    "ternary",
    "const x = a ? b : c ? d : e;",
    ["a ? b :", "c ? d : e"],
  )
}

///|
test "transform: switch / case / break" {
  ok_emit(
    "switch",
    #|function pick(kind) {
    #|  switch (kind) {
    #|    case "a": return 1;
    #|    case "b": return 2;
    #|    default: return 0;
    #|  }
    #|}
    ,
    [
      "function pick(kind)",
      "switch (kind)",
      "case \"a\":",
      "case \"b\":",
      "default:",
      "return 0",
    ],
  )
}

///|
test "transform: try / catch / finally" {
  ok_emit(
    "try",
    #|try {
    #|  doIt();
    #|} catch (e) {
    #|  log(e);
    #|} finally {
    #|  cleanup();
    #|}
    ,
    ["try {", "doIt()", "catch", "log(e)", "finally", "cleanup()"],
  )
}

///|
test "transform: for-of / for-in / for(;;)" {
  ok_emit(
    "for-of",
    "for (const x of items) { acc += x; }",
    ["for (const x of items)", "acc"],
  )
  ok_emit(
    "for-in",
    "for (const k in obj) { use(k); }",
    ["for (const k in obj)", "use(k)"],
  )
  ok_emit(
    "for(;;)",
    "for (let i = 0; i < n; i++) { acc += i; }",
    ["for (", "let i = 0", "i < n", "i++"],
  )
}

///|
test "transform: declare / type / interface are dropped from the JS output" {
  // `interface` / `type` aren't visible at the runtime stmt stream
  // (they get collected into `TsModule.interfaces` / `type_aliases`),
  // so the emit pass simply produces nothing for them.
  must_not_contain(
    "type-only drop",
    #|interface I { x: number }
    #|type T = I;
    #|const v = 1;
    ,
    ["interface", "type T"],
  )
}

///|
test "transform: mangle option compresses function-locals but keeps top-level" {
  // `transform_source_full` exposes the mangle pass directly so a
  // CLI driver like `mtsc --mangle` can skip the JSX lowering +
  // emit dance manually. Top-level names stay verbatim by default.
  let src =
    (
      #|function greetUser(name) {
      #|  const message = "hi " + name;
      #|  return message;
      #|}
    )
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

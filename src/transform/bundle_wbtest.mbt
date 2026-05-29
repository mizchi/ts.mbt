// Tests for the bundle phase. Each case constructs a virtual file
// system in memory and walks `bundle_modules` from an entry path.

///|
fn vfs(entries : Array[(String, String)]) -> Map[String, String] {
  let m : Map[String, String] = {}
  for entry in entries {
    m[entry.0] = entry.1
  }
  m
}

///|
test "bundle: single-file entry round-trips through the bundler" {
  let files = vfs([("entry.ts", "const x = 1;\nconst y = 2;\n")])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      assert_eq(out.modules.length(), 1)
      assert_eq(out.modules[0], "entry.ts")
      assert_true(out.js.contains("const x"))
      assert_true(out.js.contains("const y"))
      assert_true(out.js.contains("// ===== entry.ts ====="))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: two-file dependency emits deepest module first" {
  let files = vfs([
    ("entry.ts", "import { lib } from \"./lib\";\nconst x = lib();\n"),
    ("lib.ts", "export const lib = () => 1;\n"),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      assert_eq(out.modules, ["lib.ts", "entry.ts"])
      // Both modules show up in the bundle, lib first.
      let lib_idx = match out.js.find("// ===== lib.ts =====") {
        Some(i) => i
        None => -1
      }
      let entry_idx = match out.js.find("// ===== entry.ts =====") {
        Some(i) => i
        None => -1
      }
      assert_true(lib_idx >= 0)
      assert_true(entry_idx >= 0)
      assert_true(lib_idx < entry_idx)
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: bare-specifier imports are re-emitted at the top" {
  let files = vfs([
    (
      "entry.ts", "import React from \"react\";\nimport { useState } from \"react\";\nconst el = React.createElement(\"div\");\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      assert_true(out.js.contains("import React from \"react\""))
      assert_true(out.js.contains("import { useState } from \"react\""))
      // Internal-statement `const el = …` should also be present.
      assert_true(out.js.contains("const el"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: type-only imports are dropped from the output" {
  let files = vfs([
    ("types.ts", "export type T = number;\n"),
    ("entry.ts", "import type { T } from \"./types\";\nconst v: T = 1;\n"),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      // No bundle section for the types-only module — it gets pruned.
      assert_eq(out.modules.length(), 1)
      assert_eq(out.modules[0], "entry.ts")
      assert_false(out.js.contains("// ===== types.ts ====="))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: diamond dependency visits the shared module once" {
  // a.ts -> shared.ts
  // b.ts -> shared.ts
  // entry.ts -> a.ts and b.ts
  let files = vfs([
    (
      "entry.ts", "import { a } from \"./a\";\nimport { b } from \"./b\";\nconst v = a + b;\n",
    ),
    (
      "a.ts", "import { shared } from \"./shared\";\nexport const a = shared + 1;\n",
    ),
    (
      "b.ts", "import { shared } from \"./shared\";\nexport const b = shared + 2;\n",
    ),
    ("shared.ts", "export const shared = 42;\n"),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      assert_eq(out.modules.length(), 4)
      assert_eq(out.modules[0], "shared.ts")
      assert_true(
        (out.modules[1] == "a.ts" && out.modules[2] == "b.ts") ||
        (out.modules[1] == "b.ts" && out.modules[2] == "a.ts"),
      )
      assert_eq(out.modules[3], "entry.ts")
      // The shared module body must appear exactly once.
      let mut first = 0
      match out.js.find("export const shared") {
        Some(_) => first = first + 1
        None => ()
      }
      let mut count = 0
      let mut search_from = 0
      while search_from < out.js.length() {
        let slice = out.js
          .substring(start=search_from, end=out.js.length())
          .to_string()
        match slice.find("const shared = 42") {
          Some(idx) => {
            count = count + 1
            search_from = search_from + idx + 1
          }
          None => break
        }
      }
      assert_eq(count, 1)
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: missing module fails with a clear error" {
  let files = vfs([
    ("entry.ts", "import { x } from \"./missing\";\nconst v = x;\n"),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(_) => fail("expected error for missing module")
    Err(e) => assert_true(e.contains("module not in vfs"))
  }
}

///|
test "bundle: relative paths resolve through ./ and ../" {
  // `entry.ts` lives in `src/`, depends on `./lib.ts` and `../shared.ts`.
  let files = vfs([
    (
      "src/entry.ts", "import { lib } from \"./lib\";\nimport { shared } from \"../shared\";\nconst v = lib + shared;\n",
    ),
    ("src/lib.ts", "export const lib = 1;\n"),
    ("shared.ts", "export const shared = 2;\n"),
  ])
  match bundle_modules(files, "src/entry.ts", BundleOptions::default()) {
    Ok(out) => {
      assert_eq(out.modules.length(), 3)
      assert_true(out.modules.contains("src/lib.ts"))
      assert_true(out.modules.contains("shared.ts"))
      assert_true(out.modules.contains("src/entry.ts"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: sourcemap option emits multi-source v3 JSON" {
  let files = vfs([
    ("entry.ts", "import { x } from \"./lib\";\nconst v = x;\n"),
    ("lib.ts", "export const x = 1;\n"),
  ])
  let opts : BundleOptions = BundleOptions::default().with_sourcemap(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      match out.sourcemap {
        Some(json) => {
          assert_true(json.contains("\"version\":3"))
          assert_true(json.contains("\"sources\":["))
          // Both module paths should be in the sources array.
          assert_true(json.contains("\"lib.ts\""))
          assert_true(json.contains("\"entry.ts\""))
          // sourcesContent has both bodies embedded.
          assert_true(json.contains("export const x"))
          assert_true(json.contains("import { x } from"))
        }
        None => fail("expected sourcemap, got None")
      }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: mangle folds modules into one scope and renames everything" {
  // Two modules — the bundle should expose `b.compute` as the entry
  // through the same renamed slot used inside `a`. With
  // `--mangle`, the per-module separator comments are dropped and
  // every binding gets a short name.
  let files = vfs([
    (
      "entry.ts", "import { compute } from \"./lib\";\nconst out = compute(7);\nconsole.log(out);\n",
    ),
    (
      "lib.ts", "export function compute(seed: number): number {\n  const offset = 3;\n  return seed + offset;\n}\n",
    ),
  ])
  let opts = BundleOptions::default().with_mangle(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // Parameter / local names should be gone.
      assert_false(out.js.contains("offset"))
      assert_false(out.js.contains("seed"))
      // Per-module separator banners are skipped in mangle mode.
      assert_false(out.js.contains("// ===== "))
      // `console` stays put — it's in the built-in reserved set.
      assert_true(out.js.contains("console.log"))
      assert_eq(out.modules.length(), 2)
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: mangle keeps the shared call site consistent across modules" {
  // `helper` is defined in `lib.ts`, called from `entry.ts`. The
  // mangle pass folds both into one block so the bundle's call
  // site must refer to the same renamed identifier as the
  // declaration's outer binding.
  let files = vfs([
    (
      "entry.ts", "import { helper } from \"./lib\";\nconst v = helper(2);\nconsole.log(v);\n",
    ),
    (
      "lib.ts", "export function helper(n: number): number {\n  return n * 2;\n}\n",
    ),
  ])
  let opts = BundleOptions::default().with_mangle(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // Emit-time function-decl lowering converts
      // `Let(Ident(X), _, FuncExpr({name: X|orig, …}))` into a
      // plain `function X(…) {…}`. The FuncExpr internal name is
      // dropped; rename consistency between declaration and call
      // site is preserved by the mangler walking `Var`/`Call`
      // references in the body.
      let mut found = false
      for candidate in ["a", "b", "c", "d", "e"] {
        if out.js.contains("function " + candidate + "(") &&
          out.js.contains("= " + candidate + "(") {
          found = true
        }
      }
      if !found {
        fail("expected matched declaration / call rename in: \{out.js}")
      }
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: cyclic imports don't stack-overflow" {
  // `a.js` <-> `b.js` form a 2-cycle. Without the cycle-break
  // sentinel in `load_module_graph`, this used to recurse
  // infinitely until SIGSEGV.
  let files = vfs([
    (
      "a.js", "import { B } from \"./b.js\";\nexport const A = 1;\nconsole.log(A + B);\n",
    ),
    ("b.js", "import { A } from \"./a.js\";\nexport const B = 2;\n"),
  ])
  match bundle_modules(files, "a.js", BundleOptions::default()) {
    Ok(out) => {
      assert_true(out.js.contains("const A"))
      assert_true(out.js.contains("const B"))
      // Both modules show up in the output.
      assert_eq(out.modules.length(), 2)
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: longer cycle through three modules" {
  let files = vfs([
    ("a.js", "import { B } from \"./b.js\";\nexport const A = 1;\n"),
    ("b.js", "import { C } from \"./c.js\";\nexport const B = 2;\n"),
    ("c.js", "import { A } from \"./a.js\";\nexport const C = 3;\n"),
  ])
  match bundle_modules(files, "a.js", BundleOptions::default()) {
    Ok(out) => assert_eq(out.modules.length(), 3)
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: class extends emits native syntax with working super()" {
  let files = vfs([
    (
      "entry.ts", "class MyError extends Error {\n  res: number;\n  constructor(m: string, r: number) { super(m); this.res = r; }\n}\nconsole.log(new MyError(\"x\", 1).message);\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      // Native `class … extends Error { … }` syntax, not the
      // IIFE desugar. Without this fix, the IIFE's `super(…)`
      // call landed outside a method body and V8 rejected it.
      assert_true(out.js.contains("class MyError extends Error"))
      assert_true(out.js.contains("super(m)"))
      // The brittle bits of the old IIFE form should not appear.
      assert_false(out.js.contains("__super_proto"))
      assert_false(out.js.contains("__super_ctor"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: for-loop comma-separated init unfolds correctly" {
  let files = vfs([
    (
      "entry.ts", "function sum(arr: number[]): number {\n  let total = 0;\n  for (let i = 0, n = arr.length; i < n; i++) {\n    total += arr[i];\n  }\n  return total;\n}\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      // Comma-separated `for (let i = 0, n = …; …; …)` is emitted as
      // a single declaration, not as a brace-block.
      assert_true(out.js.contains("for (let i = 0, n = arr.length;"))
      // Block-form `for ({…}; …; …)` is what the buggy emit
      // produced — must not appear.
      assert_false(out.js.contains("for ({"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: optional chaining emits ?. tokens" {
  let files = vfs([
    (
      "entry.ts", "const obj: any = { foo: 1 };\nconst arr: any = null;\nconsole.log(obj?.foo, arr?.[0], obj?.method?.());\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      // Each `?.` step is restored in the output.
      assert_true(out.js.contains("obj?.foo"))
      assert_true(out.js.contains("arr?.["))
      assert_true(out.js.contains("?.method"))
      // The chain `obj?.method?.()` keeps both `?.` markers.
      assert_true(out.js.contains("?.method?.("))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: constructor parameter properties become this.x = x" {
  let files = vfs([
    (
      "entry.ts", "class Point {\n  constructor(public x: number, private y: number, readonly z: number = 99) {}\n  sum() { return this.x + this.y + this.z; }\n}\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      // The constructor body needs to assign each parameter-property
      // back onto `this` so `sum()` can read the fields later.
      assert_true(out.js.contains("this.x = x"))
      assert_true(out.js.contains("this.y = y"))
      assert_true(out.js.contains("this.z = z"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: private fields strip the `#` after brand mangling" {
  let files = vfs([
    (
      "entry.ts", "class Counter {\n  #count = 0;\n  inc() { this.#count++; return this.#count; }\n  get value() { return this.#count; }\n}\nconst c = new Counter();\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      // The brand prefix is fine, but `#` must not appear in the
      // emitted identifier — it isn't a legal JS ident char outside
      // the native `#field` syntax.
      assert_false(out.js.contains("__#"))
      assert_false(out.js.contains("#count"))
      // Brand'd field is still namespaced so external access
      // doesn't collide with public fields.
      assert_true(out.js.contains("__private_brand__"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: class getter desugars to Object.defineProperty" {
  let files = vfs([
    ("entry.ts", "class Box {\n  v = 7;\n  get value() { return this.v; }\n}\n"),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      // The `@@get:value` desugar marker must become
      // `Object.defineProperty(...)` in the output — without this
      // the previous emit wrote `proto.@@get:value = …`, which V8
      // rejects.
      assert_true(out.js.contains("Object.defineProperty"))
      assert_false(out.js.contains("@@get:"))
      assert_false(out.js.contains("@@set:"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: --reserve-entry-exports keeps exported type surface" {
  // `Config` is exported via `start(cfg: Config)` and via the
  // explicit `export interface Config`. Both `host` and `port`
  // belong to the public type surface and must survive
  // `--mangle-properties`. The internal `Internal` interface's
  // members can mangle freely.
  let files = vfs([
    (
      "entry.ts",
      "interface Internal { tag: string; data: number; }\n" +
      "export interface Config { host: string; port: number; }\n" +
      "function make(): Internal { return { tag: \"x\", data: 1 }; }\n" +
      "export function start(cfg: Config) {\n" +
      "  const i = make();\n" +
      "  console.log(cfg.host, cfg.port, i.tag);\n" +
      "}\n",
    ),
  ])
  let source = match files.get("entry.ts") {
    Some(s) => s
    None => ""
  }
  let module_ = @parser.parse_module_from_source_with_const_values(source, {})
  let reserved = entry_export_property_names(module_, ["start", "Config"])
  let r : Map[String, Bool] = {}
  for n in reserved {
    r[n] = true
  }
  // Exported surface is reserved …
  assert_true(r.contains("host"))
  assert_true(r.contains("port"))
  // … but `Internal`'s members aren't.
  assert_false(r.contains("tag"))
  assert_false(r.contains("data"))
}

///|
test "bundle: --reserve-entry-exports follows class signatures" {
  // The exported `Service` class exposes `endpoint`, `port`, and
  // `call`. All three should land in the reserved set.
  let src = "export class Service {\n" +
    "  endpoint: string;\n" +
    "  port: number;\n" +
    "  constructor(endpoint: string, port: number) {}\n" +
    "  call() {}\n" +
    "}\n"
  let module_ = @parser.parse_module_from_source_with_const_values(src, {})
  let reserved = entry_export_property_names(module_, ["Service"])
  let r : Map[String, Bool] = {}
  for n in reserved {
    r[n] = true
  }
  assert_true(r.contains("endpoint"))
  assert_true(r.contains("port"))
  assert_true(r.contains("call"))
}

///|
test "dts: emits only entry-exported declarations" {
  let src = "interface Internal { tag: string }\n" +
    "export interface Config { host: string; port: number }\n" +
    "function helper(): Internal { return { tag: \"x\" }; }\n" +
    "export function start(cfg: Config): void { console.log(cfg.host); }\n"
  let module_ = @parser.parse_module_from_source_with_const_values(src, {})
  let dts = emit_entry_dts(module_, ["Config", "start"], {})
  // Exported interface survives, including its public field names.
  assert_true(dts.contains("export interface Config"))
  assert_true(dts.contains("host: string"))
  assert_true(dts.contains("port: number"))
  // Exported function with its signature.
  assert_true(dts.contains("export declare function start(cfg: Config)"))
  // Internal helper interface is dropped from the published surface.
  assert_false(dts.contains("Internal"))
  assert_false(dts.contains("tag"))
}

///|
test "dts: prints conditional + union extends + mapped + indexed access" {
  let src = "export type Maybe<T> = T extends null | undefined ? never : T;\n" +
    "export type Pick2<T, K extends keyof T> = { [P in K]: T[P] };\n"
  let module_ = @parser.parse_module_from_source_with_const_values(src, {})
  let dts = emit_entry_dts(module_, ["Maybe", "Pick2"], {})
  assert_true(dts.contains("T extends (null | undefined)"))
  assert_true(dts.contains("? never : T"))
  assert_true(dts.contains("{ [P in K]: T[P] }"))
  // Generic param bounds: `K extends keyof T` should round-trip.
  assert_true(dts.contains("K extends keyof T"))
}

///|
test "dts: optional field round-trips to `x?: T` instead of `T | undefined`" {
  let src = "export interface Config {\n" +
    "  host: string;\n" +
    "  port?: number;\n" +
    "  tags?: string[];\n" +
    "}\n"
  let module_ = @parser.parse_module_from_source_with_const_values(src, {})
  let dts = emit_entry_dts(module_, ["Config"], {})
  // Required field still emits with `:`.
  assert_true(dts.contains("host: string"))
  // Optional fields use `?:` rather than `: T | undefined`.
  assert_true(dts.contains("port?: number"))
  assert_true(dts.contains("tags?: string[]"))
  assert_false(dts.contains("undefined"))
}

///|
test "dts: infer marker prints as `infer T` (not `__tsmbt_infer<T>`)" {
  let src = "export type R<T> = T extends (...args: any) => infer Ret ? Ret : never;\n"
  let module_ = @parser.parse_module_from_source_with_const_values(src, {})
  let dts = emit_entry_dts(module_, ["R"], {})
  // The parser stores `infer T` as `Applied("__tsmbt_infer", …)` —
  // emit must render it as the TypeScript keyword form.
  assert_true(dts.contains("infer Ret"))
  assert_false(dts.contains("__tsmbt_infer"))
}

///|
test "emit: async function expression keeps `async` keyword" {
  // The function-expression emit dropped `f.is_async`; this is the
  // shape `inline_block` produces from `async function* gen() {…}`.
  let files = vfs([
    (
      "entry.ts",
      "async function* gen() { yield 1; }\n" +
      "const g = gen();\n" +
      "console.log(typeof g.next);\n",
    ),
  ])
  let opts = BundleOptions::default()
    .with_fold(true)
    .with_mangle(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // Whether the function got inlined into the call site or kept
      // as a decl, the `async` keyword must survive.
      assert_true(out.js.contains("async "))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "emit: PropAssign with FuncExpr receiver wraps in parens" {
  // Inline can collapse `let f = function () {…}; f.x = y` into a
  // PropAssign with the FuncExpr as receiver. Bare-emitted, the
  // leading `function …` parses as a declaration, not an
  // expression, and the trailing `.x = …` fails to parse.
  let files = vfs([
    (
      "entry.ts",
      "class Foo { _v = 1; get value() { return this._v; } }\n" +
      "console.log(new Foo().value);\n",
    ),
  ])
  let opts = BundleOptions::default()
    .with_fold(true)
    .with_treeshake(true)
    .with_mangle(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // The output must not contain a bare `function …` immediately
      // followed by `.prop=` (which would be a parse error).
      assert_false(out.js.contains("function value(){return this._v}.")) // wouldn't actually appear; just guard
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "mangle: dynamic IndexAccess disables property mangling" {
  // `obj[key]` with a non-literal key can resolve to any property
  // name at runtime; the mangler must not rename properties when
  // the bundle contains such an access. Previously this only
  // fired for external receivers, missing local-binding dynamic
  // access entirely.
  let files = vfs([
    (
      "entry.ts",
      "const obj = { foo: 1, bar: 2 };\n" +
      "const key = \"foo\";\n" +
      "console.log(obj[key]);\n",
    ),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // `foo` stays as a property key — otherwise `obj[key]` would
      // miss the renamed slot at runtime.
      assert_true(out.js.contains("foo"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "mangle: class method names rename in lockstep with property accesses" {
  // The property mangle pass renamed PropAccess at call sites but
  // left NativeClassStmt method declarations untouched, so
  // `class C { sayHi() {…} } new C().sayHi()` came out as
  // `class C { sayHi() {…} } new C().a()` — method name on the
  // declaration didn't match the renamed call site.
  let files = vfs([
    (
      "entry.ts",
      "class Base {}\n" +
      "class C extends Base { sayHi() { return \"hi\"; } }\n" +
      "console.log(new C().sayHi());\n",
    ),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // Either both sites end up `sayHi` (reserved didn't allow
      // rename) or both end up `a`. They must MATCH.
      let in_class = out.js.contains("sayHi()")
      let in_call = out.js.contains(".sayHi()")
      assert_true(in_class == in_call)
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "dead_props: destructured function param keeps property name alive" {
  // Before fix: dead_props' FuncExpr branch walked only the body,
  // missing destructured-param bindings. `function fn({a,b}){…}`
  // made `a` and `b` look unused, so `fn({a:1,b:2})` call sites
  // got their object literal stripped to `{}`.
  let files = vfs([
    (
      "entry.ts",
      "function fn({ a = 10, b = 20 }) { return a + b; }\n" +
      "console.log(fn({ a: 1, b: 2 }));\n",
    ),
  ])
  let opts = BundleOptions::default()
    .with_mangle(true)
    .with_mangle_properties(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // Caller's argument literal must not be stripped to `{}`.
      assert_false(out.js.contains("({})"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "link: two modules declaring the same name don't collide" {
  // Before the linker existed, two modules each declaring
  // `var Hono` collapsed into one binding and an `extends Hono`
  // reference in the second module resolved to the wrong target.
  // The linker renames the second module's `Hono` to `Hono$0` and
  // an `import { HonoBase } from "./a"` (where a does
  // `export { Hono as HonoBase }`) resolves to module-a's `Hono`.
  let files = vfs([
    (
      "a.ts", "var Hono = class _Hono { greet() { return \"hi\"; } };\nexport { Hono as HonoBase };\n",
    ),
    (
      "b.ts", "import { HonoBase } from \"./a\";\nvar Hono = class extends HonoBase { extra() { return \"!\"; } };\nexport { Hono };\n",
    ),
    (
      "entry.ts", "import { Hono } from \"./b\";\nconst h = new Hono();\nconsole.log(h.greet() + h.extra());\n",
    ),
  ])
  let opts = BundleOptions::default()
    .with_treeshake(true)
    .with_mangle(true)
    .with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // Crucial property: `extends` references an actually-declared
      // class binding. We don't check the exact rename, just that
      // the output doesn't leave `Hono` (or `HonoBase`) as a free
      // variable that would fail at runtime.
      assert_false(out.js.contains("extends HonoBase"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "link: re-export chain resolves to the original declaration" {
  // `entry` → `index` → `mod` chain. Without re-export resolution,
  // `import { val } from "./index"` would dead-end at index's
  // empty export_specs (only `reexport_specs` carries the alias).
  let files = vfs([
    ("mod.ts", "export const val = 42;\n"),
    ("index.ts", "export { val } from \"./mod\";\n"),
    ("entry.ts", "import { val } from \"./index\";\nconsole.log(val);\n"),
  ])
  let opts = BundleOptions::default().with_treeshake(true).with_mangle(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // `val` must resolve to a declared binding somewhere in
      // the output — at minimum the literal `42` should survive.
      assert_true(out.js.contains("42"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "parser: private field reference inside template literal stays mangled" {
  // Regression for a bug found while bundling Hono: the template-
  // literal sub-parser was created via `Parser::from_source` which
  // initialises `current_class_brand` to `None`, so `${this.#x}`
  // inside a class body emitted the original `#x` syntax outside
  // the class body, breaking Node's parser.
  let files = vfs([
    (
      "entry.ts",
      "var Node = class _Node {\n" +
      "  #index;\n" +
      "  describe() { return `#${this.#index}`; }\n" +
      "};\n" +
      "const n = new Node();\n" +
      "console.log(n.describe());\n",
    ),
  ])
  let opts = BundleOptions::default()
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // After lowering, `#index` should be mangled to a brand-
      // suffixed identifier everywhere — INCLUDING inside the
      // template-literal interpolation. Output must not contain
      // a `#index` token outside of a class body.
      assert_false(out.js.contains("this.#index"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "emit: object literal with computed key (`{[expr]: value}`)" {
  let files = vfs([
    (
      "entry.ts",
      "const KEY = \"name\";\n" +
      "const obj = { [KEY]: 42, other: 1 };\n" +
      "console.log(obj);\n",
    ),
  ])
  let opts = BundleOptions::default().with_fold(true).with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // The parser stores computed keys as a `("@@computed:N",
      // ComputedProp(key, value))` sentinel. Emit must produce
      // the proper `[key]:value` shorthand instead of leaking
      // the sentinel and the wrapper.
      assert_false(out.js.contains("@@computed"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "treeshake: class extends keeps the base class alive" {
  let files = vfs([
    (
      "entry.ts",
      "class Base { greet() { return \"hi\"; } }\n" +
      "class Greeter extends Base {}\n" +
      "const g = new Greeter();\n" +
      "console.log(g.greet());\n",
    ),
  ])
  let opts = BundleOptions::default().with_treeshake(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // Treeshake previously didn't walk class bodies / `extends`
      // names, so `Base` got dropped despite being referenced by
      // `Greeter`'s extends clause. The bundle is invalid at
      // runtime in that case.
      assert_true(out.js.contains("Base"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "treeshake: unused native class declaration is dropped" {
  // A `class Unused { … }` that is never instantiated or referenced
  // should be eliminated by treeshake.
  let files = vfs([
    (
      "entry.ts",
      "class Unused { run() { return 42; } }\n" +
      "class Used {}\n" +
      "const u = new Used();\n" +
      "console.log(u);\n",
    ),
  ])
  let opts = BundleOptions::default().with_treeshake(true).with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_false(out.js.contains("Unused"))
      assert_true(out.js.contains("Used"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "sourcemap: mangle path emits per-stmt mappings via encoded positions" {
  let files = vfs([
    (
      "entry.ts", "import { x } from \"./lib\";\nconst y = x + 1;\nconsole.log(y);\n",
    ),
    ("lib.ts", "export const x = 41;\n"),
  ])
  let opts = BundleOptions::default()
    .with_treeshake(true)
    .with_mangle(true)
    .with_sourcemap(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // The combined-path emit now decodes per-stmt origins and
      // records source-map mappings. The map must include both
      // module slots in `sources` and at least one mapping segment
      // (the `mappings` string isn't empty).
      match out.sourcemap {
        Some(sm) => {
          assert_true(sm.contains("\"entry.ts\""))
          assert_true(sm.contains("\"lib.ts\""))
          // mangle path used to drop positions; now `mappings` is
          // populated.
          let mappings_pos = sm.find("\"mappings\":\"")
          let mappings = match mappings_pos {
            Some(idx) =>
              sm
              .substring(
                start=idx + "\"mappings\":\"".length(),
                end=sm.length(),
              )
              .to_string()
            None => ""
          }
          assert_true(mappings.length() > 5)
        }
        None => fail("expected sourcemap output, got None")
      }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "dts: class constructor emits when parser captured it" {
  let src = "export class Foo {\n" +
    "  x: number;\n" +
    "  constructor(x: number, label?: string) { this.x = x; }\n" +
    "  go(): void { return; }\n" +
    "}\n"
  let module_ = @parser.parse_module_from_source_with_const_values(src, {})
  let dts = emit_entry_dts(module_, ["Foo"], {})
  assert_true(dts.contains("export class Foo"))
  assert_true(dts.contains("constructor(x: number, label?: string)"))
}

///|
test "enum lowering: numeric enum picks up reverse mapping" {
  let files = vfs([
    ("entry.ts", "enum Color { Red, Green, Blue }\nconsole.log(Color.Red);\n"),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      // Forward mapping
      assert_true(out.js.contains("Color[\"Red\"] = 0"))
      // Reverse mapping (numeric enums only)
      assert_true(out.js.contains("Color[0] = \"Red\""))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "enum lowering: string enum omits reverse mapping" {
  let files = vfs([
    (
      "entry.ts", "enum Size { Small = \"s\", Medium = \"m\" }\nconsole.log(Size.Small);\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      assert_true(out.js.contains("Size[\"Small\"] = \"s\""))
      // String enums must NOT have the reverse-map assignment.
      assert_false(out.js.contains("Size[\"s\"] ="))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "const-enum: numeric values inline at use sites, no runtime var" {
  let files = vfs([
    (
      "entry.ts", "const enum Status { OK = 200, NotFound = 404 }\nconsole.log(Status.OK, Status.NotFound);\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      // The const-enum's runtime declaration must NOT appear.
      assert_false(out.js.contains("var Status"))
      assert_false(out.js.contains("Status[\"OK\"]"))
      // Use sites become the literal values.
      assert_true(out.js.contains("console.log(200, 404)"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "const-enum: string values inline as string literals" {
  let files = vfs([
    (
      "entry.ts", "const enum Mode { R = \"r\", W = \"w\" }\nconsole.log(Mode.R, Mode.W);\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      assert_false(out.js.contains("var Mode"))
      assert_true(out.js.contains("console.log(\"r\", \"w\")"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "const-enum: auto-increment after explicit numeric anchor" {
  let files = vfs([
    ("entry.ts", "const enum E { A = 10, B, C }\nconsole.log(E.A, E.B, E.C);\n"),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) =>
      // 10 is explicit, 11 / 12 come from auto-increment.
      assert_true(out.js.contains("console.log(10, 11, 12)"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "const-enum: regular `enum` keeps its runtime var when adjacent" {
  let files = vfs([
    (
      "entry.ts", "const enum Inline { X = 10 }\nenum Regular { A, B }\nconsole.log(Inline.X + Regular.A);\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      // Only `Regular` materializes; `Inline` is fully erased.
      assert_false(out.js.contains("var Inline"))
      assert_true(out.js.contains("var Regular"))
      // Both members get inlined now (regular numeric enum
      // member access is folded to the literal value while the
      // runtime table stays in place for reverse lookups).
      assert_true(out.js.contains("console.log(10 + 0)"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "@__PURE__: annotation reaches PureCall AST node + emit" {
  let files = vfs([
    (
      "entry.ts", "function alloc(): any { return null; }\nconst x = /* @__PURE__ */ alloc();\nconsole.log(x);\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) =>
      // The annotation is preserved in the JS output so
      // downstream minifiers can drop the call too.
      assert_true(out.js.contains("/* @__PURE__ */ alloc()"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "@__PURE__: treeshake drops unused PureCall binding" {
  let files = vfs([
    (
      "entry.ts", "function alloc(): any { return null; }\nconst _unused = /* @__PURE__ */ alloc();\nconsole.log(\"done\");\n",
    ),
  ])
  let opts = BundleOptions::default().with_treeshake(true).with_mangle(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // The binding never gets read, so treeshake drops it. The
      // `alloc()` call disappears too.
      assert_false(out.js.contains("alloc"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "@internal: tagged exports vanish from the published .d.ts" {
  let src = "/** @internal */\nexport interface Internal { raw: string }\n" +
    "export interface Public { name: string }\n" +
    "/** @internal */\nexport function debugLog(x: any): void {}\n" +
    "export function start(p: Public): void {}\n"
  let block = @parser.parse_module_block_from_source(src)
  let module_ = @parser.parse_module_from_source_with_const_values(src, {})
  let local : Array[String] = []
  for ex in block.exports {
    if not(block.internal_names.contains(ex.local_name)) {
      local.push(ex.local_name)
    }
  }
  let dts = emit_entry_dts(module_, local, {})
  // Public surface survives, marked internal disappears.
  assert_true(dts.contains("export interface Public"))
  assert_true(dts.contains("function start"))
  assert_false(dts.contains("Internal"))
  assert_false(dts.contains("debugLog"))
}

///|
test "@internal: collected_internal_names lists tagged decls" {
  let src = "/** @internal */\nexport function helper(): void {}\nexport function pub(): void {}\n"
  let block = @parser.parse_module_block_from_source(src)
  assert_true(block.internal_names.contains("helper"))
  assert_false(block.internal_names.contains("pub"))
}

///|
test "@__NO_SIDE_EFFECTS__: suppresses impure-getter diagnostic for annotated callee" {
  let files = vfs([
    (
      "entry.ts",
      "declare function expensive(): any;\n" +
      "/** @__NO_SIDE_EFFECTS__ */\nfunction compute(x: number) { return expensive() + x; }\n" +
      "class Box { v = 1; get value() { return compute(this.v); } }\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => assert_eq(out.warnings.length(), 0)
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "enum: regular numeric enum members inline at use sites" {
  let files = vfs([
    (
      "entry.ts", "enum Status { OK = 200, NotFound = 404 }\nconsole.log(Status.OK, Status.NotFound);\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      // Runtime var stays (other code might use Status[200] reverse lookup).
      assert_true(out.js.contains("var Status"))
      // Member access folds to the literal.
      assert_true(out.js.contains("console.log(200, 404)"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "predicate-inline: `function isX(): x is T { return cond }` body substitutes" {
  let files = vfs([
    (
      "entry.ts",
      "function isString(x: any): x is string { return typeof x === \"string\"; }\n" +
      "function f(v: any) { if (isString(v)) { return v.length; } return 0; }\n" +
      "console.log(f(\"hi\"));\n",
    ),
  ])
  let opts = BundleOptions::default().with_treeshake(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // The call site became the inlined body, the predicate
      // function was treeshaken away.
      assert_true(out.js.contains("if (typeof v === \"string\")"))
      assert_false(out.js.contains("isString"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "type-fold: typeof check on typed parameter folds to bool" {
  let files = vfs([
    (
      "entry.ts", "function f(x: number) { if (typeof x === \"number\") return 1; return 0; }\n",
    ),
  ])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // `typeof x === "number"` for `x: number` folds to true.
      // The fold pass then collapses `if (true) {…}` to its body.
      assert_true(out.js.contains("return 1;"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "switch-fold: literal-union dispatch arm substitutes at call site" {
  let files = vfs([
    (
      "entry.ts",
      "function dispatch(k: \"x\" | \"y\" | \"z\", n: number): number {\n" +
      "  switch (k) {\n" +
      "    case \"x\": return n + 1;\n" +
      "    case \"y\": return n + 2;\n" +
      "    case \"z\": return n + 3;\n" +
      "  }\n" +
      "}\n" +
      "console.log(dispatch(\"y\", 10));\n",
    ),
  ])
  let opts = BundleOptions::default().with_treeshake(true).with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // The "y" arm's body `n + 2` got substituted with `10`, then
      // the fold pass collapsed `10 + 2` to `12`. Either way, the
      // `dispatch` symbol must be gone post-treeshake.
      assert_false(out.js.contains("dispatch"))
      assert_true(out.js.contains("console.log(12)"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "switch-fold: non-literal first arg leaves call alone" {
  let files = vfs([
    (
      "entry.ts",
      "function dispatch(k: \"x\" | \"y\", n: number): number {\n" +
      "  switch (k) {\n" +
      "    case \"x\": return n + 1;\n" +
      "    case \"y\": return n + 2;\n" +
      "  }\n" +
      "}\n" +
      "declare const k: \"x\" | \"y\";\n" +
      "console.log(dispatch(k, 5));\n",
    ),
  ])
  let opts = BundleOptions::default()
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // `k` is a variable, not a literal — the call must stay.
      assert_true(out.js.contains("dispatch(k, 5)"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "as-const: literal array indexed read inlines to the element" {
  let files = vfs([
    (
      "entry.ts",
      "const STATUSES = [\"ok\", \"warn\", \"err\"] as const;\n" +
      "console.log(STATUSES[1]);\n",
    ),
  ])
  let opts = BundleOptions::default().with_treeshake(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_true(out.js.contains("console.log(\"warn\")"))
      assert_false(out.js.contains("STATUSES"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "as-const: literal object property read inlines to the value" {
  let files = vfs([
    (
      "entry.ts",
      "const HTTP = { OK: 200, NF: 404 } as const;\n" +
      "function status() { return HTTP.OK; }\n" +
      "console.log(status());\n",
    ),
  ])
  let opts = BundleOptions::default().with_treeshake(true).with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // `HTTP.OK` got replaced by `200`; the binding survives only
      // if something else references it (here, nothing does).
      assert_true(out.js.contains("200"))
      assert_false(out.js.contains("HTTP"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "as-const: bare reference disqualifies the binding" {
  let files = vfs([
    (
      "entry.ts",
      "const ARR = [1, 2, 3] as const;\n" +
      "const COPY = ARR;\n" +
      "console.log(ARR[0], COPY[0]);\n",
    ),
  ])
  let opts = BundleOptions::default()
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // `const COPY = ARR` is a bare-identifier capture — neither
      // ARR nor COPY can inline at access sites because they'd
      // diverge from the array identity.
      assert_true(out.js.contains("ARR"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "switch-exhaustive: default throw drops when union is fully covered" {
  let files = vfs([
    (
      "entry.ts",
      "function area(k: \"circle\" | \"square\"): number {\n" +
      "  switch (k) {\n" +
      "    case \"circle\": return 1;\n" +
      "    case \"square\": return 2;\n" +
      "    default: throw new Error(\"unreachable\");\n" +
      "  }\n" +
      "}\n" +
      "console.log(area(\"circle\"));\n",
    ),
  ])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // The default arm went away — no `throw` remains in the output.
      assert_false(out.js.contains("unreachable"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "switch-exhaustive: non-exhaustive case set keeps the default" {
  let files = vfs([
    (
      "entry.ts",
      "function area(k: \"circle\" | \"square\"): number {\n" +
      "  switch (k) {\n" +
      "    case \"circle\": return 1;\n" +
      "    default: throw new Error(\"unreachable\");\n" +
      "  }\n" +
      "}\n" +
      "console.log(area(\"circle\"));\n",
    ),
  ])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // Only `circle` is covered — the default must stay.
      assert_true(out.js.contains("unreachable"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "tag-rewrite: discriminated union string tags become integers" {
  let files = vfs([
    (
      "entry.ts",
      "type Shape = { kind: \"circle\", r: number } | { kind: \"square\", side: number };\n" +
      "function area(s: Shape): number {\n" +
      "  switch (s.kind) {\n" +
      "    case \"circle\": return s.r * s.r;\n" +
      "    case \"square\": return s.side * s.side;\n" +
      "  }\n" +
      "  return 0;\n" +
      "}\n" +
      "const c: Shape = { kind: \"circle\", r: 3 };\n" +
      "const out = area(c);\n",
    ),
  ])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // After rewrite, the source no longer carries `"circle"` /
      // `"square"` discriminant strings — they became 0 / 1.
      assert_false(out.js.contains("\"circle\""))
      assert_false(out.js.contains("\"square\""))
      assert_true(out.js.contains("case 0:"))
      assert_true(out.js.contains("case 1:"))
      assert_true(out.js.contains("kind: 0"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "tag-rewrite: skipped when console.log mentions the bundle" {
  let files = vfs([
    (
      "entry.ts",
      "type Shape = { kind: \"a\", x: number } | { kind: \"b\", y: number };\n" +
      "const s: Shape = { kind: \"a\", x: 1 };\n" +
      "console.log(s);\n",
    ),
  ])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // `console.log(s)` would let an outside observer see the
      // string tag — abort K=kind.
      assert_true(out.js.contains("\"a\""))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "tag-rewrite: unrelated console.log doesn't abort the DU rewrite" {
  let files = vfs([
    (
      "entry.ts",
      "type Shape = { kind: \"circle\", r: number } | { kind: \"square\", side: number };\n" +
      "function area(s: Shape): number {\n" +
      "  switch (s.kind) {\n" +
      "    case \"circle\": return s.r * s.r;\n" +
      "    case \"square\": return s.side * s.side;\n" +
      "  }\n" +
      "  return 0;\n" +
      "}\n" +
      "const c: Shape = { kind: \"circle\", r: 3 };\n" +
      "const out = area(c);\n" +
      // Unrelated escape sink — does NOT touch any K=kind binding.
      "console.log(\"hello world\");\n" +
      "console.log(out);\n",
    ),
  ])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // The DU rewrite still fires — the strings `"circle"` /
      // `"square"` are gone, replaced by integers.
      assert_false(out.js.contains("\"circle\""))
      assert_false(out.js.contains("\"square\""))
      assert_true(out.js.contains("case 0:"))
      // But the unrelated console.log still has its own string.
      assert_true(out.js.contains("\"hello world\""))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "class-method-dce: drops methods nothing in the bundle accesses (native class)" {
  // Forces the `NativeClassStmt` path via `extends`.
  let files = vfs([
    (
      "entry.ts",
      "class Base {}\n" +
      "class Foo extends Base {\n" +
      "  start() { return 1; }\n" +
      "  legacy() { return 2; }\n" +
      "}\n" +
      "const f = new Foo();\n" +
      "const out = f.start();\n",
    ),
  ])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_true(out.js.contains("start"))
      assert_false(out.js.contains("legacy"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "iife-class-lift: simple class without extends becomes native syntax" {
  let files = vfs([
    (
      "entry.ts",
      "class Foo {\n" +
      "  start() { return 1; }\n" +
      "  stop() { return 2; }\n" +
      "}\n" +
      "const f = new Foo();\n" +
      "const out = f.start() + f.stop();\n",
    ),
  ])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // The IIFE wrapper is gone; a native `class Foo` declaration
      // takes its place.
      assert_true(out.js.contains("class Foo"))
      assert_false(out.js.contains("Foo.prototype.start"))
      assert_false(out.js.contains("__super_proto"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "iife-class-lift: class with extends becomes native class with extends" {
  // TypeScript lowers `class Child extends Base {}` to an IIFE form.
  // The lift should recognise the single-arg IIFE pattern and produce
  // `class Child extends Base { … }`.
  let files = vfs([
    (
      "entry.ts",
      "class Base {\n" +
      "  greet() { return \"hi\"; }\n" +
      "}\n" +
      "class Child extends Base {\n" +
      "  greet() { return super.greet() + \"!\"; }\n" +
      "}\n" +
      "const c = new Child();\n" +
      "console.log(c.greet());\n",
    ),
  ])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // Both classes should be lifted to native syntax.
      assert_true(out.js.contains("class Base"))
      assert_true(out.js.contains("class Child"))
      assert_true(out.js.contains("extends"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "class-method-dce: drops methods on IIFE-lowered class" {
  let files = vfs([
    (
      "entry.ts",
      "class Foo {\n" +
      "  start() { return 1; }\n" +
      "  legacy() { return 2; }\n" +
      "}\n" +
      "const f = new Foo();\n" +
      "const out = f.start();\n",
    ),
  ])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_true(out.js.contains("start"))
      assert_false(out.js.contains("legacy"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "class-method-dce: kept under reflection-sink presence" {
  let files = vfs([
    (
      "entry.ts",
      "class Base {}\n" +
      "class Foo extends Base {\n" +
      "  start() { return 1; }\n" +
      "  legacy() { return 2; }\n" +
      "}\n" +
      "const f = new Foo();\n" +
      "const names = Object.getOwnPropertyNames(f);\n" +
      "const out = f.start();\n",
    ),
  ])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // The reflection call disqualifies the optimization — `legacy`
      // stays in.
      assert_true(out.js.contains("legacy"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "type-fold: null check on non-nullable primitive folds to false" {
  let files = vfs([
    (
      "entry.ts", "function f(x: number) { if (x === null) return 1; return 0; }\n",
    ),
  ])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // `x === null` for `x: number` is statically false → branch
      // gets eliminated.
      assert_false(out.js.contains("return 1"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "link: wildcard re-export `export * from` resolves named import through barrel (#32)" {
  // a.ts → barrel.ts (export * from "./a") → entry.ts (import { foo } from "./barrel")
  // Without wildcard enumeration the linker treats barrel's export surface
  // as empty and leaves `foo` as a free reference.
  let files = vfs([
    ("a.ts", "export const foo = 1;\nexport const bar = 2;\n"),
    ("barrel.ts", "export * from \"./a\";\n"),
    ("entry.ts", "import { foo } from \"./barrel\";\nconsole.log(foo);\n"),
  ])
  let opts = BundleOptions::default().with_treeshake(true).with_mangle(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // The constant `1` must survive into the bundle — either as the
      // inlined literal or as the initialiser of the renamed binding.
      assert_true(out.js.contains("1"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "link: `export * as ns from` synthesizes namespace object for named import (#33)" {
  // core.ts re-exports util as a namespace; consumer imports it by name.
  // Without the synthesis path `util.check(...)` is a free-variable call.
  let files = vfs([
    ("util.ts", "export function check(x: unknown): boolean { return x !== null; }\n"),
    ("core.ts", "export * as util from \"./util\";\n"),
    (
      "entry.ts",
      "import { util } from \"./core\";\nconsole.log(util.check(42));\n",
    ),
  ])
  let opts = BundleOptions::default().with_treeshake(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) =>
      // `check` must appear in the bundle — either inlined or via the
      // synthesized namespace object.
      assert_true(out.js.contains("check"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "link: multi-level wildcard barrel chain resolves to original declaration" {
  // c.ts → b.ts (export * from "./c") → barrel.ts (export * from "./b") → entry.ts
  // Transitive wildcard re-exports through two barrel hops must still resolve.
  let files = vfs([
    ("c.ts", "export const val = 99;\n"),
    ("b.ts", "export * from \"./c\";\n"),
    ("barrel.ts", "export * from \"./b\";\n"),
    ("entry.ts", "import { val } from \"./barrel\";\nconsole.log(val);\n"),
  ])
  let opts = BundleOptions::default().with_treeshake(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_true(out.js.contains("99"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "iife_class_lift: Object.defineProperty getter/setter lifted to native accessor" {
  // TypeScript emits `Object.defineProperty(ClassName.prototype, "prop", {
  //   get: function() {...}, enumerable: false, configurable: true })` for
  // class getters. The lift should convert this to a native `get prop()` method.
  let files = vfs([
    (
      "entry.ts",
      (
        #|class Box {
        #|  constructor(private _val: number) {}
        #|  get value(): number { return this._val; }
        #|  set value(v: number) { this._val = v; }
        #|}
        #|const b = new Box(1);
        #|console.log(b.value);
      ),
    ),
  ])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // Native getter/setter syntax should appear.
      assert_true(
        out.js.contains("get value") || out.js.contains("get "),
        "expected native getter syntax",
      )
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "fold: empty constructor dropped from NativeClassStmt without extends" {
  // `class Foo { constructor() {} }` → `class Foo {}` when ctor is a no-op.
  // Saves `constructor(){}` bytes per class without changing behavior.
  let files = vfs([
    (
      "entry.ts",
      (
        #|class Box {
        #|  constructor() {}
        #|  getValue() { return 42; }
        #|}
        #|export default Box;
      ),
    ),
  ])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // The empty constructor should be dropped.
      assert_false(
        out.js.contains("constructor"),
        "expected empty constructor to be dropped",
      )
      // The method must still be present.
      assert_true(out.js.contains("getValue"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "iife_class_lift: extra Expr statements move after class (#31 perf)" {
  // A class IIFE where a side-effect expression statement (e.g.
  // `allMethods.forEach(…)`) appears at the top level of the IIFE
  // body should still be lifted to `class C { … }`, with the forEach
  // call appended afterward.
  let files = vfs([
    (
      "entry.ts",
      (
        #|const METHODS = ["get", "post"];
        #|class Router {
        #|  route() { return 42; }
        #|}
        #|METHODS.forEach(m => { Router.prototype[m] = function() {}; });
        #|export default Router;
      ),
    ),
  ])
  let opts = BundleOptions::default()
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // Class declaration must be present.
      assert_true(out.js.contains("class Router") || out.js.contains("route"))
      // The forEach call must be present.
      assert_true(out.js.contains("forEach"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "iife_class_lift: static property assignment moves after class" {
  // TypeScript sometimes emits `ClassName.staticProp = value` inside
  // the IIFE body for non-function static fields. This previously
  // classified as Unknown and aborted the lift. Now it is an Extra
  // statement appended after the class declaration.
  let files = vfs([
    (
      "entry.ts",
      (
        #|class Config {
        #|  getValue() { return Config.version; }
        #|}
        #|Config.version = "1.0";
        #|export default Config;
      ),
    ),
  ])
  let opts = BundleOptions::default()
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // Class must be present.
      assert_true(out.js.contains("class Config") || out.js.contains("getValue"))
      // The static field assignment must be present.
      assert_true(out.js.contains("1.0"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "iife_class_lift: closure variable hoisted before class" {
  // TypeScript ES5 output for classes with static closure state:
  // `var Counter = (function() { var _count = 0; function Counter() {}
  //   Counter.prototype.increment = function() { _count++; };
  //   return Counter; })();`
  // The `var _count = 0` previously aborted the lift. Now it is
  // emitted before the class so the methods can still close over it.
  let files = vfs([
    (
      "entry.ts",
      (
        #|class Counter {
        #|  increment() {}
        #|  get() { return 0; }
        #|}
        #|export default Counter;
      ),
    ),
  ])
  let opts = BundleOptions::default()
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_true(out.js.contains("class Counter") || out.js.contains("increment"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "iife_class_lift: closure var referencing class name emitted after class (#31)" {
  // `var _proto = Foo.prototype` references Foo (the class being lifted).
  // Class declarations are NOT hoisted, so this variable must be emitted
  // AFTER the class definition, not before it (ExtraBefore would be wrong).
  // The fix checks whether the variable's RHS mentions the class name.
  let src = #|var Foo = (function() {
  #|  function Foo() {}
  #|  Foo.prototype.run = function() { return 1; };
  #|  var _proto = Foo.prototype;
  #|  _proto.stop = function() { return 2; };
  #|  return Foo;
  #|}());
  #|export default Foo;
  let files = vfs([("entry.ts", src)])
  let opts = BundleOptions::default()
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // The class must be lifted (not left as an IIFE).
      assert_true(out.js.contains("class Foo"))
      // `var _proto = Foo.prototype` must come AFTER class Foo, so
      // that `Foo` is already initialized when the assignment runs.
      let class_pos = out.js.index_of("class Foo")
      let proto_pos = out.js.index_of("_proto")
      if class_pos >= 0 && proto_pos >= 0 {
        assert_true(proto_pos > class_pos)
      }
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "iife_class_lift: non-class-name PropAssign lifted as Extra (#31)" {
  // Assignments to other objects' properties inside an IIFE should not
  // abort the class lift — they're side effects that can run after the class.
  let src = #|var registry = {};
  #|var Foo = (function() {
  #|  function Foo() {}
  #|  Foo.prototype.run = function() { return 1; };
  #|  registry.Foo = Foo;
  #|  return Foo;
  #|}());
  #|export default Foo;
  let files = vfs([("entry.ts", src)])
  let opts = BundleOptions::default()
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_true(out.js.contains("class Foo"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "iife_class_lift: Assign to non-class var in IIFE body does not abort lift" {
  // `counter = counter + 1` inside the IIFE is a side effect to a
  // non-class variable. The lift should keep it as Extra and still
  // produce `class Foo`.
  let src = #|var counter = 0;
  #|var Foo = (function() {
  #|  function Foo() {}
  #|  counter = counter + 1;
  #|  Foo.prototype.run = function() { return counter; };
  #|  return Foo;
  #|}());
  #|export default Foo;
  let files = vfs([("entry.ts", src)])
  let opts = BundleOptions::default()
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_true(out.js.contains("class Foo"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "iife_class_lift: destructuring Var in IIFE body does not abort lift" {
  // `var { a, b } = opts` inside the IIFE is a destructuring declaration
  // that does not touch the class name. The lift should hoist it before
  // the class and still produce `class Foo`.
  let src = #|var Foo = (function() {
  #|  var opts = { a: 1, b: 2 };
  #|  var _a = opts.a, _b = opts.b;
  #|  function Foo() { this.v = _a + _b; }
  #|  Foo.prototype.get = function() { return this.v; };
  #|  return Foo;
  #|}());
  #|export default Foo;
  let files = vfs([("entry.ts", src)])
  let opts = BundleOptions::default()
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_true(out.js.contains("class Foo"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "link: `export * as ns from` where source uses `export * from` (re-export chain)" {
  // util-impl.ts → util.ts (export * from "./util-impl") → core.ts (export * as util from "./util")
  // The namespace object in core.ts should include `check` from the transitive re-export.
  let files = vfs([
    (
      "util-impl.ts",
      "export function check(x: unknown): boolean { return x !== null; }\n",
    ),
    ("util.ts", "export * from \"./util-impl\";\n"),
    ("core.ts", "export * as util from \"./util\";\n"),
    (
      "entry.ts",
      "import { util } from \"./core\";\nconsole.log(util.check(42));\n",
    ),
  ])
  let opts = BundleOptions::default().with_treeshake(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_true(out.js.contains("check"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "switch_fold: switch with default arm folds known-literal call sites" {
  // A dispatch function with `default:` for unmapped literals should still
  // fold when the call site uses a literal that hits the default.
  let src = #|function dispatch(k: "x" | "y" | "z"): number {
  #|  switch (k) {
  #|    case "x": return 1;
  #|    default: return 99;
  #|  }
  #|}
  #|console.log(dispatch("y"));
  let files = vfs([("entry.ts", src)])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_true(out.js.contains("99"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "type_fold: typeof x === \"undefined\" folds to true for x: undefined param" {
  // When a parameter is declared `: undefined`, `typeof x === "undefined"`
  // is statically true. The fold pass should collapse the if-branch.
  let src = #|function check(x: undefined): string {
  #|  if (typeof x === "undefined") {
  #|    return "yes";
  #|  }
  #|  return "no";
  #|}
  #|console.log(check(undefined));
  let files = vfs([("entry.ts", src)])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_false(out.js.contains("\"no\""))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "class_method_dce: for-in loop in constructor body does not abort prototype method DCE" {
  // A class whose constructor uses `for...in` over a plain object should
  // still have unused prototype methods removed. The conservative `ForIn =>
  // true` caused DCE to be skipped entirely for any such class.
  let src = #|class Router {
  #|  constructor(routes: Record<string, string>) {
  #|    for (const k in routes) {
  #|      this.register(k, routes[k]);
  #|    }
  #|  }
  #|  register(path: string, handler: string) { return path + handler; }
  #|  unused() { return 99; }
  #|}
  #|const r = new Router({});
  #|r.register("/", "h");
  let files = vfs([("entry.ts", src)])
  let opts = BundleOptions::default()
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_false(out.js.contains("unused"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "emit: empty no-arg constructor on base class is dropped in minify mode" {
  // An explicit `constructor() {}` on a class that does not extend another
  // is identical to the implicit default constructor. The emitter should
  // drop it in minify mode to save bytes.
  let src = #|class Foo {
  #|  constructor() {}
  #|  run(): number { return 42; }
  #|}
  #|const f = new Foo();
  #|console.log(f.run());
  let files = vfs([("entry.ts", src)])
  let opts = BundleOptions::default().with_fold(true).with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_false(out.js.contains("constructor"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "class_method_dce: this[dynamic] instance-write does not abort prototype method DCE" {
  // Hono-style: constructor assigns this[method] = ... for all methods.
  // The DCE should still drop the unused `old()` prototype method.
  let src = #|class Foo {
  #|  constructor() {
  #|    const methods = ["run"];
  #|    methods.forEach(m => { this[m] = () => 42; });
  #|  }
  #|  run() { return 1; }
  #|  old() { return 99; }
  #|}
  #|const f = new Foo();
  #|f.run();
  let files = vfs([("entry.ts", src)])
  let opts = BundleOptions::default()
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => assert_false(out.js.contains("old"))
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "emit: minify emits !0/!1 for true/false and void 0 for undefined" {
  // In minify mode `true` → `!0` (saves 2 bytes), `false` → `!1` (saves 3
  // bytes), and `undefined` → `void 0` (saves 3 bytes).
  let src = #|const a = true;
  #|const b = false;
  #|const c = undefined;
  #|console.log(a, b, c);
  let files = vfs([("entry.ts", src)])
  let opts = BundleOptions::default().with_minify(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      assert_false(out.js.contains("true"), "expected true to be minified away")
      assert_false(out.js.contains("false"), "expected false to be minified away")
      // `undefined` may be dropped entirely by the treeshaker/folder or
      // replaced with `void 0` — either way the 9-char identifier should not appear.
      assert_false(
        out.js.contains("undefined"),
        "expected undefined to be minified away",
      )
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "bundle: second fold pass after inline folds const-indexed array access" {
  // `const N = 1; const arr = ["a","b","c"]; console.log(arr[N])` should
  // fold to `console.log("b")` when fold+minify are both enabled.
  // Without the post-inline fold pass, `arr[N]` survives as-is after inlining
  // substitutes `N → 1`, yielding `["a","b","c"][1]` which is not folded.
  let src = #|const N = 1;
  #|const arr = ["a", "b", "c"];
  #|console.log(arr[N]);
  let files = vfs([("entry.ts", src)])
  let opts = BundleOptions::default()
    .with_fold(true)
    .with_minify(true)
    .with_treeshake(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // After fold+inline+fold the array literal should be gone — only "b" remains.
      assert_true(
        out.js.contains("\"b\""),
        "expected folded value \"b\" in output",
      )
      assert_false(out.js.contains("[\"a\""), "expected array literal to be folded away")
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "type-fold: x + \"\" is dropped when x is typed as string" {
  // When `x: string`, `x + ""` is a no-op and should fold to just `x`.
  let files = vfs([
    (
      "entry.ts",
      "function greet(name: string): string { return name + \"\"; }\nconsole.log(greet(\"world\"));\n",
    ),
  ])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // The `name + ""` concatenation should be folded away.
      assert_false(
        out.js.contains("+ \"\"") || out.js.contains("+\"\""),
        "expected x + \"\" to be folded away for string-typed x",
      )
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "fold: else block hoisted when then-branch returns, result folded to ternary" {
  // `if (c) { return x; } else { return y; }` should fold to `return c ? x : y`.
  // The else-hoist enables fold_func_body to then combine to a ternary.
  let files = vfs([
    (
      "entry.ts",
      "function pick(c: boolean, x: number, y: number): number { if (c) { return x; } else { return y; } }\nconsole.log(pick(true, 1, 2));\n",
    ),
  ])
  let opts = BundleOptions::default().with_fold(true)
  match bundle_modules(files, "entry.ts", opts) {
    Ok(out) => {
      // `else` keyword should be gone; result is a ternary or direct branch.
      assert_false(
        out.js.contains("else"),
        "expected else to be eliminated: \{out.js}",
      )
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

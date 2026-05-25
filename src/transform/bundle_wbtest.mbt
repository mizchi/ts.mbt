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
      "entry.ts",
      "import React from \"react\";\nimport { useState } from \"react\";\nconst el = React.createElement(\"div\");\n",
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
    (
      "entry.ts",
      "import type { T } from \"./types\";\nconst v: T = 1;\n",
    ),
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
      "entry.ts",
      "import { a } from \"./a\";\nimport { b } from \"./b\";\nconst v = a + b;\n",
    ),
    ("a.ts", "import { shared } from \"./shared\";\nexport const a = shared + 1;\n"),
    ("b.ts", "import { shared } from \"./shared\";\nexport const b = shared + 2;\n"),
    ("shared.ts", "export const shared = 42;\n"),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      assert_eq(out.modules.length(), 4)
      assert_eq(out.modules[0], "shared.ts")
      assert_true(
        out.modules[1] == "a.ts" && out.modules[2] == "b.ts" ||
        out.modules[1] == "b.ts" && out.modules[2] == "a.ts",
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
      "src/entry.ts",
      "import { lib } from \"./lib\";\nimport { shared } from \"../shared\";\nconst v = lib + shared;\n",
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
      "entry.ts",
      "import { compute } from \"./lib\";\nconst out = compute(7);\nconsole.log(out);\n",
    ),
    (
      "lib.ts",
      "export function compute(seed: number): number {\n  const offset = 3;\n  return seed + offset;\n}\n",
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
      "entry.ts",
      "import { helper } from \"./lib\";\nconst v = helper(2);\nconsole.log(v);\n",
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
      "a.js",
      "import { B } from \"./b.js\";\nexport const A = 1;\nconsole.log(A + B);\n",
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
    (
      "a.js", "import { B } from \"./b.js\";\nexport const A = 1;\n",
    ),
    (
      "b.js", "import { C } from \"./c.js\";\nexport const B = 2;\n",
    ),
    (
      "c.js", "import { A } from \"./a.js\";\nexport const C = 3;\n",
    ),
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
      "entry.ts",
      "class MyError extends Error {\n  res: number;\n  constructor(m: string, r: number) { super(m); this.res = r; }\n}\nconsole.log(new MyError(\"x\", 1).message);\n",
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
      "entry.ts",
      "function sum(arr: number[]): number {\n  let total = 0;\n  for (let i = 0, n = arr.length; i < n; i++) {\n    total += arr[i];\n  }\n  return total;\n}\n",
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
      "entry.ts",
      "const obj: any = { foo: 1 };\nconst arr: any = null;\nconsole.log(obj?.foo, arr?.[0], obj?.method?.());\n",
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
      "entry.ts",
      "class Point {\n  constructor(public x: number, private y: number, readonly z: number = 99) {}\n  sum() { return this.x + this.y + this.z; }\n}\n",
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
      "entry.ts",
      "class Counter {\n  #count = 0;\n  inc() { this.#count++; return this.#count; }\n  get value() { return this.#count; }\n}\nconst c = new Counter();\n",
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
    (
      "entry.ts",
      "class Box {\n  v = 7;\n  get value() { return this.v; }\n}\n",
    ),
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
  for n in reserved { r[n] = true }
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
  for n in reserved { r[n] = true }
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
}

///|
test "enum lowering: numeric enum picks up reverse mapping" {
  let files = vfs([
    (
      "entry.ts", "enum Color { Red, Green, Blue }\nconsole.log(Color.Red);\n",
    ),
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
      "entry.ts",
      "enum Size { Small = \"s\", Medium = \"m\" }\nconsole.log(Size.Small);\n",
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
      "entry.ts",
      "const enum Status { OK = 200, NotFound = 404 }\nconsole.log(Status.OK, Status.NotFound);\n",
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
      "entry.ts",
      "const enum Mode { R = \"r\", W = \"w\" }\nconsole.log(Mode.R, Mode.W);\n",
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
    (
      "entry.ts",
      "const enum E { A = 10, B, C }\nconsole.log(E.A, E.B, E.C);\n",
    ),
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
      "entry.ts",
      "const enum Inline { X = 10 }\nenum Regular { A, B }\nconsole.log(Inline.X + Regular.A);\n",
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
      "entry.ts",
      "function alloc(): any { return null; }\nconst x = /* @__PURE__ */ alloc();\nconsole.log(x);\n",
    ),
  ])
  match bundle_modules(files, "entry.ts", BundleOptions::default()) {
    Ok(out) => {
      // The annotation is preserved in the JS output so
      // downstream minifiers can drop the call too.
      assert_true(out.js.contains("/* @__PURE__ */ alloc()"))
    }
    Err(e) => fail("bundle error: \{e}")
  }
}

///|
test "@__PURE__: treeshake drops unused PureCall binding" {
  let files = vfs([
    (
      "entry.ts",
      "function alloc(): any { return null; }\nconst _unused = /* @__PURE__ */ alloc();\nconsole.log(\"done\");\n",
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
      "entry.ts",
      "enum Status { OK = 200, NotFound = 404 }\nconsole.log(Status.OK, Status.NotFound);\n",
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
      "entry.ts",
      "function f(x: number) { if (typeof x === \"number\") return 1; return 0; }\n",
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
test "type-fold: null check on non-nullable primitive folds to false" {
  let files = vfs([
    (
      "entry.ts",
      "function f(x: number) { if (x === null) return 1; return 0; }\n",
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

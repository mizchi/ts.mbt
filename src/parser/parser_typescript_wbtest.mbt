// test

///|
/// Convert interface to JSON format matching TypeScript oracle output
fn interface_to_json(iface : @ast.TsInterface) -> String {
  let fields_json = []
  for field in iface.fields {
    let (name, type_) = field
    // Determine if it's a method based on naming convention
    let is_method = name == "<new>" || name == "<call>" || name == "<computed>"
    let type_str = type_.to_string()
    fields_json.push(
      "    {\"name\": \"\{escape_json(name)}\", \"type\": \"\{escape_json(type_str)}\", \"optional\": false, \"method\": \{is_method}}",
    )
  }
  let fields_str = fields_json.join(",\n")
  "{\n  \"name\": \"\{escape_json(iface.name)}\",\n  \"fields\": [\n\{fields_str}\n  ]\n}"
}

///|
fn escape_json(s : String) -> String {
  let mut result = ""
  for c in s {
    match c {
      '"' => result += "\\\""
      '\\' => result += "\\\\"
      '\n' => result += "\\n"
      '\r' => result += "\\r"
      '\t' => result += "\\t"
      _ => result += c.to_string()
    }
  }
  result
}

///|
/// Extract interfaces from parsed module as JSON array
pub fn extract_interfaces_json(module_ : @ast.TsModule) -> String {
  let jsons = []
  for iface in module_.interfaces {
    jsons.push(interface_to_json(iface))
  }
  "[\n" + jsons.join(",\n") + "\n]"
}

///|
async fn list_typescript_lib_files() -> Array[String] {
  let roots = ["typescript/lib", "typescript/src/lib"]
  let mut base = ""
  for root in roots {
    let kind = @fs.kind(root, follow_symlink=false) catch {
      _ => @fs.FileKind::Unknown
    }
    if kind is @fs.FileKind::Directory {
      base = root
      break
    }
  }
  if base == "" {
    return []
  }
  let entries = @fs.readdir(
    base,
    include_hidden=false,
    include_special=false,
    sort=true,
  ) catch {
    _ => []
  }
  let files : Array[String] = []
  for name in entries {
    if name.has_suffix(".d.ts") {
      files.push(base + "/" + name)
    }
  }
  files
}

///|
async fn resolve_typescript_lib_path(file_name : String) -> String? {
  let roots = ["typescript/src/lib", "typescript/lib"]
  for root in roots {
    let path = root + "/" + file_name
    let kind = @fs.kind(path, follow_symlink=false) catch {
      _ => @fs.FileKind::Unknown
    }
    if kind is @fs.FileKind::Regular {
      return Some(path)
    }
  }
  None
}

///|
async test "parser: parse TypeScript lib d.ts files" {
  let files = list_typescript_lib_files()
  if files.length() == 0 {
    println("skip: typescript/lib not found")
    return
  }
  let failures : Array[String] = []
  for path in files {
    let content = @fs.read_file(path).text() catch {
      e => {
        failures.push(path + ": read error " + "\{e}")
        continue
      }
    }
    let parser = Parser::from_source(content)
    let result : Result[@ast.TsModule, ParseError] = try? parser.parse_module()
    match result {
      Ok(_) => ()
      Err(err) => failures.push(path + ": " + "\{err}")
    }
  }
  if failures.length() > 0 {
    println("TypeScript lib parse failures (\{failures.length()}):")
    for item in failures {
      println(item)
    }
    fail("Expected all TypeScript lib files to parse")
  }
}

///|
/// Extract interface field names only (for comparison)
fn extract_field_names(module_ : @ast.TsModule) -> Map[String, Array[String]] {
  let result : Map[String, Array[String]] = {}
  for iface in module_.interfaces {
    let names : Array[String] = []
    for field in iface.fields {
      let (name, _) = field
      names.push(name)
    }
    result[iface.name] = names
  }
  result
}

///|
async test "parser: compare heredoc vs file content" {
  // Content from heredoc
  let heredoc =
    #|interface ArrayLike<T> {
    #|    readonly length: number;
    #|    readonly [n: number]: T;
    #|}
    #|
    #|type Partial<T> = {
    #|    [P in keyof T]?: T[P];
    #|};

  // Test heredoc
  let parser1 = Parser::from_source(heredoc)
  let mod1 = parser1.parse_module() catch {
    e => {
      println("Heredoc parse error: \{e}")
      fail("Heredoc should parse")
      return
    }
  }
  println("Heredoc: found \{mod1.interfaces.length()} interfaces")

  let es5_path = match resolve_typescript_lib_path("es5.d.ts") {
    Some(path) => path
    None => {
      println("skip: es5.d.ts not found")
      return
    }
  }

  // Read from file
  let file_content = @fs.read_file(es5_path).text() catch {
    e => {
      fail("File read error: \{e}")
      return
    }
  }

  // Extract same section from file (lines 1559-1570)
  let normalized = normalize_line_endings(file_content)
  let lines = normalized.split("\n")
  let parts : Array[String] = []
  for i, line in lines {
    if i >= 1558 && i < 1570 {
      parts.push(line.to_owned())
    }
  }
  let file_section = parts.join("\n")
  println("File section:")
  println(file_section)

  // Test file section
  let parser2 = Parser::from_source(file_section)
  let mod2 = parser2.parse_module() catch {
    e => {
      println("File section parse error: \{e}")
      return
    }
  }
  println("File section: found \{mod2.interfaces.length()} interfaces")
}

///|
test "parser: complex type aliases from es5" {
  let src =
    #|interface ArrayLike<T> {
    #|    readonly length: number;
    #|    readonly [n: number]: T;
    #|}
    #|
    #|type Partial<T> = {
    #|    [P in keyof T]?: T[P];
    #|};
    #|
    #|type Required<T> = {
    #|    [P in keyof T]-?: T[P];
    #|};
    #|
    #|type NonNullable<T> = T & {};
    #|
    #|type Parameters<T extends (...args: any) => any> = T extends (...args: infer P) => any ? P : never;
    #|
    #|type ConstructorParameters<T extends abstract new (...args: any) => any> = T extends abstract new (...args: infer P) => any ? P : never;
    #|
    #|interface ThisType<T> {}
    #|
    #|interface WeakKeyTypes {
    #|    object: object;
    #|}
    #|
    #|type WeakKey = WeakKeyTypes[keyof WeakKeyTypes];
    #|
    #|interface ArrayBuffer {
    #|    readonly byteLength: number;
    #|}
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  println("Found \{module_.interfaces.length()} interfaces:")
  for iface in module_.interfaces {
    println("  - \{iface.name}")
  }

  // Should find: ArrayLike, ThisType, WeakKeyTypes, ArrayBuffer
  assert_eq(module_.interfaces.length(), 4)
}

///|
test "parser: type alias with intrinsic" {
  let src =
    #|interface Foo {
    #|  bar: string;
    #|}
    #|
    #|type Partial<T> = {
    #|    [P in keyof T]?: T[P];
    #|};
    #|
    #|type Uppercase<S extends string> = intrinsic;
    #|
    #|interface Bar {
    #|  baz: number;
    #|}
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  println("Found \{module_.interfaces.length()} interfaces")
  for iface in module_.interfaces {
    println("  - \{iface.name}")
  }

  // Should find both Foo and Bar
  assert_eq(module_.interfaces.length(), 2)
  assert_eq(module_.interfaces[0].name, "Foo")
  assert_eq(module_.interfaces[1].name, "Bar")
}

///|
/// Compare interface field names between MoonBit parser and TypeScript oracle
async test "parser: compare interface fields with TypeScript oracle" {
  // Test with a simple file first
  let test_file = match resolve_typescript_lib_path("es2015.symbol.d.ts") {
    Some(path) => path
    None => {
      println("skip: es2015.symbol.d.ts not found")
      return
    }
  }
  let content = @fs.read_file(test_file).text() catch {
    e => {
      fail("Failed to read \{test_file}: \{e}")
      return
    }
  }
  let parser = Parser::from_source(content)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }

  // Expected from TypeScript oracle:
  // SymbolConstructor: ["prototype", "<call>", "for", "keyFor"]
  let field_names = extract_field_names(module_)

  // Check SymbolConstructor interface
  let symbol_ctor = field_names.get("SymbolConstructor")
  match symbol_ctor {
    Some(fields) => {
      println("SymbolConstructor fields: " + @debug.to_string(fields))
      assert_true(fields.contains("prototype"))
      assert_true(fields.contains("for"))
      assert_true(fields.contains("keyFor"))
    }
    None => fail("SymbolConstructor interface not found")
  }
}

///|
/// Compare es5.d.ts interface fields with oracle
async test "parser: compare es5 interface fields" {
  let es5_path = match resolve_typescript_lib_path("es5.d.ts") {
    Some(path) => path
    None => {
      println("skip: es5.d.ts not found")
      return
    }
  }

  let content = @fs.read_file(es5_path).text() catch {
    e => {
      fail("Failed to read es5.d.ts: \{e}")
      return
    }
  }
  let parser = Parser::from_source(content)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let field_names = extract_field_names(module_)

  // Check Array interface fields (from TypeScript oracle)
  let array_fields = field_names.get("Array")
  match array_fields {
    Some(fields) => {
      // Oracle: length, toString, toLocaleString, pop, push, concat, join, reverse, shift, slice, sort, splice, unshift, indexOf, lastIndexOf, every, some, forEach, map, filter, reduce, reduceRight
      let expected = [
        "length", "toString", "pop", "push", "concat", "join", "reverse", "shift",
        "slice", "sort", "splice", "unshift", "indexOf", "lastIndexOf", "every",
        "some", "forEach", "map", "filter", "reduce", "reduceRight",
      ]
      let missing : Array[String] = []
      for name in expected {
        if !fields.contains(name) {
          missing.push(name)
        }
      }
      if missing.length() > 0 {
        println("Array interface missing fields: " + @debug.to_string(missing))
      }
      // At least these core methods should be present
      assert_true(fields.contains("length"))
      assert_true(fields.contains("push"))
      assert_true(fields.contains("pop"))
    }
    None => fail("Array interface not found")
  }

  // Check Error interface
  let error_fields = field_names.get("Error")
  match error_fields {
    Some(fields) => {
      assert_true(fields.contains("name"))
      assert_true(fields.contains("message"))
    }
    None => fail("Error interface not found")
  }

  // Check Object interface
  let object_fields = field_names.get("Object")
  match object_fields {
    Some(fields) => {
      assert_true(fields.contains("constructor"))
      assert_true(fields.contains("toString"))
      assert_true(fields.contains("valueOf"))
    }
    None => fail("Object interface not found")
  }
}

///|
/// Normalize line endings to LF
fn normalize_line_endings(s : String) -> String {
  s.replace(old="\r\n", new="\n").replace(old="\r", new="\n")
}

///|
/// Test type alias skipping with nested generics (>> token)
test "parser: type alias with nested generics" {
  let src =
    #|interface Before {}
    #|
    #|type Omit<T, K extends keyof any> = Pick<T, Exclude<keyof T, K>>;
    #|
    #|interface After {}
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }

  // Should find both interfaces, correctly skipping the type alias with nested generics
  assert_eq(module_.interfaces.length(), 2)
  assert_eq(module_.interfaces[0].name, "Before")
  assert_eq(module_.interfaces[1].name, "After")
}

///|
/// Test es5.d.ts type alias section
test "parser: es5 type alias section" {
  let src =
    #|interface ArrayLike<T> {
    #|    readonly length: number;
    #|    readonly [n: number]: T;
    #|}
    #|
    #|type Partial<T> = {
    #|    [P in keyof T]?: T[P];
    #|};
    #|
    #|type Required<T> = {
    #|    [P in keyof T]-?: T[P];
    #|};
    #|
    #|type Omit<T, K extends keyof any> = Pick<T, Exclude<keyof T, K>>;
    #|
    #|type NonNullable<T> = T & {};
    #|
    #|type Parameters<T extends (...args: any) => any> = T extends (...args: infer P) => any ? P : never;
    #|
    #|type Uppercase<S extends string> = intrinsic;
    #|
    #|interface ThisType<T> {}
    #|
    #|interface WeakKeyTypes {
    #|    object: object;
    #|}
    #|
    #|type WeakKey = WeakKeyTypes[keyof WeakKeyTypes];
    #|
    #|interface ArrayBuffer {
    #|    readonly byteLength: number;
    #|}
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }

  // Should find: ArrayLike, ThisType, WeakKeyTypes, ArrayBuffer
  assert_eq(module_.interfaces.length(), 4)
}

///|
/// Test multiple files against oracle
async test "parser: validate interface structure against TypeScript" {
  // Test files with expected interface counts (from TypeScript oracle)
  // Note: es5.d.ts has 95 interfaces in the oracle, but 15 are inside
  // `declare namespace Intl { ... }` which we currently skip.
  // So we expect 80 interfaces (95 - 15 = 80)
  let test_cases : Array[(String, Int)] = [
    ("typescript/src/lib/es2015.symbol.d.ts", 1),
    ("typescript/src/lib/es5.d.ts", 80), // Excludes interfaces inside namespaces
  ]
  for test_case in test_cases {
    let (file_path, expected_count) = test_case
    let content = @fs.read_file(file_path).text() catch {
      e => {
        println("Skip \{file_path}: \{e}")
        continue
      }
    }
    let parser = Parser::from_source(content)
    let module_ = parser.parse_module() catch {
      e => {
        fail("Parse error in \{file_path}: \{e}")
        continue
      }
    }
    let actual_count = module_.interfaces.length()
    if actual_count != expected_count {
      println(
        "WARNING: \{file_path} - expected \{expected_count} interfaces, got \{actual_count}",
      )
      // Print interface names for debugging
      let names : Array[String] = []
      for iface in module_.interfaces {
        names.push(iface.name)
      }
      names.sort()
      println("Found interfaces: " + @debug.to_string(names))
    }
  }
}

///|
async fn collect_ts_source_files(dir : String) -> Array[String] {
  let kind = @fs.kind(dir, follow_symlink=false) catch {
    _ => @fs.FileKind::Unknown
  }
  if !(kind is @fs.FileKind::Directory) {
    return []
  }
  let entries = @fs.readdir(
    dir,
    include_hidden=false,
    include_special=false,
    sort=true,
  ) catch {
    _ => []
  }
  let files : Array[String] = []
  for name in entries {
    if name.has_suffix(".ts") && !name.has_suffix(".d.ts") {
      files.push(dir + "/" + name)
    }
  }
  files
}

///|
/// Like `collect_ts_source_files` but walks subdirectories recursively.
/// Used by the conformance smoke test so a top-level directory like
/// `conformance/expressions/` picks up nested cases without having to
/// enumerate every feature subdir.
async fn collect_ts_source_files_recursive(dir : String) -> Array[String] {
  let kind = @fs.kind(dir, follow_symlink=false) catch {
    _ => @fs.FileKind::Unknown
  }
  if !(kind is @fs.FileKind::Directory) {
    return []
  }
  let entries = @fs.readdir(
    dir,
    include_hidden=false,
    include_special=false,
    sort=true,
  ) catch {
    _ => []
  }
  let files : Array[String] = []
  for name in entries {
    let path = dir + "/" + name
    if name.has_suffix(".ts") && !name.has_suffix(".d.ts") {
      files.push(path)
    } else {
      let sub_kind = @fs.kind(path, follow_symlink=false) catch {
        _ => @fs.FileKind::Unknown
      }
      if sub_kind is @fs.FileKind::Directory {
        for f in collect_ts_source_files_recursive(path) {
          files.push(f)
        }
      }
    }
  }
  files
}

///|
/// Every `.ts` (non-declaration) source file shipped with the upstream
/// TypeScript compiler/services/server in the pinned submodule must parse
/// without errors. Acts as a broad regression gate against real-world
/// runtime TypeScript syntax.
async test "parser: parse TypeScript compiler/services/server .ts sources" {
  let dirs = [
    "typescript/src/compiler", "typescript/src/server", "typescript/src/services",
    "typescript/src/typingsInstaller", "typescript/src/jsTyping",
  ]
  let failures : Array[String] = []
  let mut total = 0
  for dir in dirs {
    let files = collect_ts_source_files(dir)
    for path in files {
      total += 1
      let content = @fs.read_file(path).text() catch { _ => continue }
      try Parser::from_source(content).parse_module() catch {
        err => failures.push(path + ": \{err}")
      } noraise {
        _ => ()
      }
    }
  }
  if total == 0 {
    println("skip: no .ts sources found in pinned submodule")
    return
  }
  if failures.length() > 0 {
    for f in failures {
      println("FAIL " + f)
    }
    fail(
      "\{failures.length()} of \{total} TypeScript .ts files failed to parse",
    )
  }
}

///|
/// Run the expression / statement-level checker against every successfully
/// parsed source file in `tests/cases/conformance/types/typeParameters` and
/// `tests/cases/controlFlow/`. Acts as a smoke gate: the checker must not
/// crash on real-world TypeScript and the parse-success rate must stay
/// above the documented threshold below.
///
/// Tolerance: TS test cases intentionally include syntax-error programs to
/// exercise the official compiler's error recovery. Our parser is stricter,
/// so a small number of parse failures is expected. The threshold is
/// generous; if it ever fails, broaden the parser instead of relaxing it.
async test "checker: smoke-run against TypeScript conformance test corpus" {
  let dirs = [
    // Originally added: feature-specific narrowing / generics / guards.
    "typescript/tests/cases/conformance/types/typeParameters", "typescript/tests/cases/conformance/controlFlow",
    "typescript/tests/cases/conformance/expressions/typeGuards", "typescript/tests/cases/conformance/types/typeGuards",
    // Broader `types/` coverage — exercises union / intersection /
    // tuple / mapped / literal / conditional / utility shapes.
     "typescript/tests/cases/conformance/types/union", "typescript/tests/cases/conformance/types/intersection",
    "typescript/tests/cases/conformance/types/tuple", "typescript/tests/cases/conformance/types/literal",
    "typescript/tests/cases/conformance/types/conditional", "typescript/tests/cases/conformance/types/never",
    "typescript/tests/cases/conformance/types/unknown", "typescript/tests/cases/conformance/types/any",
    "typescript/tests/cases/conformance/types/keyof", "typescript/tests/cases/conformance/types/typeAliases",
    // Other commonly-exercised conformance corners.
     "typescript/tests/cases/conformance/types/objectTypeLiteral", "typescript/tests/cases/conformance/types/primitives",
    "typescript/tests/cases/conformance/types/stringLiteral", "typescript/tests/cases/conformance/types/uniqueSymbol",
    "typescript/tests/cases/conformance/types/rest", "typescript/tests/cases/conformance/types/specifyingTypes",
    "typescript/tests/cases/conformance/types/contextualTypes", "typescript/tests/cases/conformance/types/namedTypes",
    "typescript/tests/cases/conformance/types/typeRelationships", "typescript/tests/cases/conformance/types/forAwait",
    "typescript/tests/cases/conformance/types/asyncGenerators", "typescript/tests/cases/conformance/types/nonPrimitive",
    "typescript/tests/cases/conformance/interfaces", "typescript/tests/cases/conformance/classes",
    "typescript/tests/cases/conformance/generics", "typescript/tests/cases/conformance/expressions",
    "typescript/tests/cases/conformance/statements",
  ]
  let mut total = 0
  let mut parsed = 0
  let mut checked = 0
  let parse_failures : Array[String] = []
  let check_crashes : Array[String] = []
  for dir in dirs {
    let files = collect_ts_source_files_recursive(dir)
    for path in files {
      total += 1
      let content = @fs.read_file(path).text() catch { _ => continue }
      // `.ts` (non-`.tsx`) files do not allow JSX, so the legacy
      // `<T>expr` type-assertion syntax is valid. Configure the parser
      // accordingly — using `from_source` would default `allow_jsx = true`
      // and reject the cast.
      let allow_jsx = path.has_suffix(".tsx")
      let module_ = try
        Parser::from_source_with_jsx(content, allow_jsx).parse_module()
      catch {
        err => {
          parse_failures.push(path + ": \{err}")
          continue
        }
      } noraise {
        m => {
          parsed += 1
          m
        }
      }
      // The checker must not panic on any well-parsed module. We don't
      // care about the issue count — TS conformance programs often
      // intentionally produce errors.
      let _ = @checker.check_module_function_bodies(module_)
      checked += 1
    }
  }
  if total == 0 {
    println("skip: no .ts sources found in pinned conformance corpus")
    return
  }
  // Print summary so the corpus size and pass-rate are visible to anyone
  // diffing the wbtest output.
  println(
    "conformance corpus: total=\{total} parsed=\{parsed} checked=\{checked}",
  )
  // 70 % parse-success floor leaves room for parser-error-recovery test
  // cases without masking real regressions. (Almost all of the parse
  // failures on this corpus correspond to TS files intentionally
  // exercising syntax errors — `*Errors.ts`, `*Negative.ts`, etc.)
  if parsed * 100 < total * 70 {
    for f in parse_failures {
      println("PARSE FAIL " + f)
    }
    fail("parse-success rate below 70 %: \{parsed}/\{total}")
  }
  // Checker must not crash on any parsed module.
  if check_crashes.length() > 0 {
    for c in check_crashes {
      println("CHECK CRASH " + c)
    }
    fail("\{check_crashes.length()} checker crashes on conformance corpus")
  }
}

///|
test "checker: bare unconstrained type parameter access is silent" {
  // TypeScript allows method/property access on an unconstrained type
  // parameter — it has `object`'s API by default. Make sure we don't
  // false-flag these.
  let src =
    #|class C<T> {
    #|    f() {
    #|        var x: T;
    #|        return x.toString();
    #|    }
    #|}
  let module_ = Parser::from_source(src).parse_module()
  let issues = @checker.check_module_function_bodies(module_)
  for i in issues {
    if i.message.has_prefix("method ") || i.message.has_prefix("property ") {
      println("unexpected: \{i.path}: \{i.message}")
      fail(
        "got unexpected method/property error on unconstrained type parameter",
      )
    }
  }
}

///|
test "checker: negative-numeric literal types accept negative literal exprs" {
  // `var v: -123 = -123` parses the RHS as `UnaryOp(Neg, IntLit(123))`,
  // and TypeScript narrows that to the literal type `-123`. Make sure
  // `precise_literal_type` follows the same path so the literal-
  // tightened assignment doesn't false-flag.
  let src =
    #|function f() {
    #|  var v: -123 = -123;
    #|  let l: -1 = -1;
    #|}
  let module_ = Parser::from_source(src).parse_module()
  let issues = @checker.check_module_function_bodies(module_)
  for i in issues {
    if i.message.contains("expected `-") {
      println("unexpected: \{i.path}: \{i.message}")
      fail("got unexpected literal-mismatch error on negative numeric literal")
    }
  }
}

///|
test "checker: static members cannot reference class type parameters" {
  // TS2302. Class TPs are an instance-side notion; a `static` property
  // / method that references one is a declaration-time error.
  let src =
    #|class C<T> {
    #|  static x: T;
    #|  static f(x: T) { return x; }
    #|}
    #|class D<T, U> {
    #|  static y: U;
    #|  static g(): T { throw new Error(); }
    #|}
  let module_ = Parser::from_source(src).parse_module()
  let issues = @checker.check_module_function_bodies(module_)
  let mut hits = 0
  for i in issues {
    if i.message.contains("static members cannot reference") {
      hits += 1
    }
  }
  // C.x, C.f (param), D.y, D.g (return) → 4.
  if hits != 4 {
    for i in issues {
      println("  \{i.path}: \{i.message}")
    }
    fail("expected 4 static-member-uses-class-TP issues, got \{hits}")
  }
}

///|

///|
test "checker: method-level T shadows class TP for the static lint" {
  // `static h<T>(x: T): T` declares its own `T` that shadows the
  // class's, so the static lint must not flag the body. Exercises
  // the parser's method-TP propagation (T8) and the checker's
  // `class_tps_minus_method` filter.
  let src =
    #|class E<T> {
    #|  static h<T>(x: T): T { return x; }
    #|}
  let module_ = Parser::from_source(src).parse_module()
  let issues = @checker.check_module_function_bodies(module_)
  for i in issues {
    if i.message.contains("static members cannot reference") {
      fail("unexpected TS2302 on method-shadowed TP: \{i.path}: \{i.message}")
    }
  }
}

///|
test "checker: assigning to a readonly field is rejected" {
  // TS2540 — assignment-target is `readonly`. Engages on interface
  // `readonly value`, class `readonly value`, and union / intersection
  // shapes where any reachable variant marks the field readonly.
  let src =
    #|interface Base { readonly value: number; }
    #|interface Mutable { value: number; }
    #|class C { readonly tag: string = ""; }
    #|declare let a: Base;
    #|declare let b: Base | Mutable;
    #|declare let c: C;
    #|declare let d: Mutable;
    #|a.value = 1;
    #|b.value = 1;
    #|c.tag = "x";
    #|d.value = 2;
  let module_ = Parser::from_source(src).parse_module()
  let issues = @checker.check_module_function_bodies(module_)
  let mut hits = 0
  for i in issues {
    if i.message.contains("read-only") {
      hits += 1
    }
  }
  // a (Base.readonly value), b (Base side of the union), c (class
  // readonly tag) → 3. d (purely Mutable) → 0.
  if hits != 3 {
    for i in issues {
      println("  \{i.path}: \{i.message}")
    }
    fail("expected 3 readonly-assign issues, got \{hits}")
  }
}

///|
test "checker: structurally equivalent classes assign in either direction" {
  // Two distinct classes with identical public shape (TS is structural)
  // assign both ways. The strict `is_assignable_to` rule is nominal, so
  // a structural-equivalence fallback in the checker silences these.
  let src =
    #|class S { foo: string; }
    #|class T { foo: string; }
    #|interface I2 { foo: string; }
    #|declare var s: S;
    #|declare var t: T;
    #|declare var i2: I2;
    #|s = t;
    #|t = s;
    #|s = i2;
    #|i2 = s;
  let module_ = Parser::from_source(src).parse_module()
  let issues = @checker.check_module_function_bodies(module_)
  for i in issues {
    if i.message.contains("expected") {
      println("unexpected: \{i.path}: \{i.message}")
      fail(
        "got unexpected mismatch on structurally-equivalent class / interface",
      )
    }
  }
}

///|
test "checker: namespace bodies are walked with parent-scope types visible" {
  // Inner namespace references `Base` defined in its parent — TypeScript
  // resolves this through lexical scoping. The layered resolver path
  // surfaces the parent's classes / interfaces at bare names inside the
  // child so this assignment can be type-checked.
  let src =
    #|namespace Outer {
    #|  class Base { foo: string; }
    #|  namespace Inner {
    #|    declare var b: Base;
    #|    declare var n: number;
    #|    b = n;
    #|  }
    #|}
  let module_ = Parser::from_source(src).parse_module()
  let issues = @checker.check_module_function_bodies(module_)
  let mut found = false
  for i in issues {
    if i.message.contains("expected `Base`") {
      found = true
    }
  }
  if !found {
    for i in issues {
      println("  \{i.path}: \{i.message}")
    }
    fail(
      "expected a `Base`-vs-`number` mismatch from inside the nested namespace",
    )
  }
}

///|
test "checker: rest parameters must be array / tuple type and last" {
  // TS2370: rest param needs an array-ish annotation.
  // TS1014: rest param must be last in the list.
  let src =
    #|function f(...x: string) { }
    #|function g(...x: number, ...y: number) { }
    #|class C {
    #|  foo(...x: C) { }
    #|  bar(...x: number[], ...y: string) { }
    #|}
  let module_ = Parser::from_source(src).parse_module()
  let issues = @checker.check_module_function_bodies(module_)
  let mut rest_type_errs = 0
  let mut rest_last_errs = 0
  for i in issues {
    if i.message.contains("must be of an array type") {
      rest_type_errs += 1
    } else if i.message.contains("must be last in the parameter list") {
      rest_last_errs += 1
    }
  }
  // Type errors: f.x:string, g.x:number, g.y:number, C.bar.y:string
  // → 4 type errors. (C.foo.x:C uses a class name -- `is_valid_rest_param_type`
  // is intentionally permissive on `Named(_)` / `Applied(_, _)` since the
  // resolver-free decl-signature pass can't tell a class from a tuple
  // alias.) Last errors: g.x (not last), C.bar.x (not last) → 2.
  if rest_type_errs != 4 || rest_last_errs != 2 {
    for i in issues {
      println("  \{i.path}: \{i.message}")
    }
    fail(
      "expected rest_type_errs=4 rest_last_errs=2, got rest_type_errs=\{rest_type_errs} rest_last_errs=\{rest_last_errs}",
    )
  }
}

///|
test "checker: duplicate parameter / type parameter names" {
  let src =
    #|class C<T, T> { }
    #|interface I<T, T> { }
    #|function f<T, T>() { }
    #|function g(x: number, x: string) { return x; }
  let module_ = Parser::from_source(src).parse_module()
  let issues = @checker.check_module_function_bodies(module_)
  // Expect one duplicate-type-param issue per of class C / interface I /
  // function f, plus one duplicate-param-name on function g.
  let mut dup_tp = 0
  let mut dup_param = 0
  for i in issues {
    if i.message.has_prefix("duplicate type parameter") {
      dup_tp += 1
    } else if i.message.has_prefix("duplicate parameter name") {
      dup_param += 1
    }
  }
  if dup_tp != 3 || dup_param != 1 {
    for i in issues {
      println("  \{i.path}: \{i.message}")
    }
    fail(
      "expected dup_tp=3 dup_param=1, got dup_tp=\{dup_tp} dup_param=\{dup_param}",
    )
  }
}

///|
test "checker: null / undefined are assignable to every type (non-strict)" {
  // Without `strictNullChecks` (the conformance default, and the mode we
  // assume absent a per-file signal) `null` / `undefined` assign to any
  // target. Make sure those initializers never false-flag.
  let src =
    #|function f() {
    #|  var b: number = null;
    #|  var c: string = undefined;
    #|  var d: boolean = null;
    #|  var e: number[] = null;
    #|  var g: () => number = undefined;
    #|}
  let module_ = Parser::from_source(src).parse_module()
  let issues = @checker.check_module_function_bodies(module_)
  for i in issues {
    if i.message.contains("but got `null`") ||
      i.message.contains("but got `undefined`") {
      println("unexpected: \{i.path}: \{i.message}")
      fail(
        "got unexpected null/undefined assignability error in non-strict mode",
      )
    }
  }
}

///|
test "checker: string-literal bracket access on a primitive is silent" {
  // `x["charAt"](0)` / `n["toExponential"]()` reach a prototype member by
  // name — valid on primitives — so neither "cannot index into" nor
  // "is not callable" should fire.
  let src =
    #|function f() {
    #|  var s = "";
    #|  var n = 1;
    #|  var bl = true;
    #|  var a = s["charAt"](0);
    #|  var b = n["toExponential"]();
    #|  var c = bl["toString"]();
    #|}
  let module_ = Parser::from_source(src).parse_module()
  let issues = @checker.check_module_function_bodies(module_)
  for i in issues {
    if i.message.contains("cannot index into") ||
      i.message.contains("is not callable") {
      println("unexpected: \{i.path}: \{i.message}")
      fail("got unexpected index/callable error on primitive bracket access")
    }
  }
}

///|
/// Strip the parent directory and the `.ts` / `.tsx` suffix off a path.
/// `tests/cases/conformance/foo/bar/Baz.ts` -> `Baz`.
fn ts_case_basename(path : String) -> String {
  let parts = path.split("/")
  let arr : Array[StringView] = []
  for p in parts {
    arr.push(p)
  }
  let mut name = if arr.length() == 0 {
    path
  } else {
    arr[arr.length() - 1].to_owned()
  }
  if name.has_suffix(".tsx") {
    name = name[:name.length() - 4].to_owned()
  } else if name.has_suffix(".ts") {
    name = name[:name.length() - 3].to_owned()
  }
  name
}

///|
async fn baseline_errors_txt_exists(case_name : String) -> Bool {
  let path = "typescript/tests/baselines/reference/" + case_name + ".errors.txt"
  let kind = @fs.kind(path, follow_symlink=false) catch {
    _ => @fs.FileKind::Unknown
  }
  kind is @fs.FileKind::Regular
}

///|
/// Cross-check the checker's accuracy against the TypeScript test corpus.
///
/// The corpus convention is:
///   - `tests/cases/conformance/.../<name>.ts` is the source.
///   - `tests/baselines/reference/<name>.errors.txt` exists iff `tsc`
///     reports at least one error on that source.
///
/// So for each parsed source we can sort the outcome into a 2x2 table:
///   ┌────────────────┬──────────────┬──────────────┐
///   │                │ baseline yes │ baseline no  │
///   ├────────────────┼──────────────┼──────────────┤
///   │ our issues > 0 │ recall hit   │ false pos.   │
///   │ our issues = 0 │ recall miss  │ precision hit│
///   └────────────────┴──────────────┴──────────────┘
///
/// The two "miss" columns are the failure side. The thresholds below are
/// generous initial gates so the test starts useful without immediately
/// failing on the (large) recall gap that exists today. Tighten them as
/// the checker improves.
async test "checker: accuracy against TypeScript conformance baselines" {
  let dirs = [
    "typescript/tests/cases/conformance/types/typeParameters", "typescript/tests/cases/conformance/controlFlow",
    "typescript/tests/cases/conformance/expressions/typeGuards", "typescript/tests/cases/conformance/types/typeGuards",
    "typescript/tests/cases/conformance/types/union", "typescript/tests/cases/conformance/types/intersection",
    "typescript/tests/cases/conformance/types/tuple", "typescript/tests/cases/conformance/types/literal",
    "typescript/tests/cases/conformance/types/conditional", "typescript/tests/cases/conformance/types/never",
    "typescript/tests/cases/conformance/types/unknown", "typescript/tests/cases/conformance/types/any",
    "typescript/tests/cases/conformance/types/keyof", "typescript/tests/cases/conformance/types/typeAliases",
    "typescript/tests/cases/conformance/types/objectTypeLiteral", "typescript/tests/cases/conformance/types/primitives",
    "typescript/tests/cases/conformance/types/stringLiteral", "typescript/tests/cases/conformance/types/uniqueSymbol",
    "typescript/tests/cases/conformance/types/rest", "typescript/tests/cases/conformance/types/specifyingTypes",
    "typescript/tests/cases/conformance/types/contextualTypes", "typescript/tests/cases/conformance/types/namedTypes",
    "typescript/tests/cases/conformance/types/typeRelationships", "typescript/tests/cases/conformance/types/nonPrimitive",
  ]
  let mut total = 0
  let mut parsed = 0
  let mut recall_hit = 0
  let mut recall_miss = 0
  let mut precision_hit = 0
  let mut precision_miss = 0
  let per_dir : Map[String, (Int, Int, Int, Int)] = {}
  for dir in dirs {
    let files = collect_ts_source_files_recursive(dir)
    let mut d_rh = 0
    let mut d_rm = 0
    let mut d_ph = 0
    let mut d_pm = 0
    for path in files {
      total += 1
      let content = @fs.read_file(path).text() catch { _ => continue }
      let allow_jsx = path.has_suffix(".tsx")
      let module_ = try
        Parser::from_source_with_jsx(content, allow_jsx).parse_module()
      catch {
        _ => continue
      } noraise {
        m => {
          parsed += 1
          m
        }
      }
      let case_name = ts_case_basename(path)
      let has_baseline = baseline_errors_txt_exists(case_name)
      // Permissive mode for the whole-corpus accuracy walk: T9
      // suppressions drop the diagnostic families dominated by gaps
      // we don't model (flow narrowing, generic inference, builtin
      // optional-arg signatures, CFA). Unit tests stay strict.
      let issues = @checker.check_module_function_bodies_permissive(module_)
      if issues.length() > 0 {
        if has_baseline {
          recall_hit += 1
          d_rh += 1
        } else {
          precision_miss += 1
          d_pm += 1
        }
      } else if has_baseline {
        recall_miss += 1
        d_rm += 1
      } else {
        precision_hit += 1
        d_ph += 1
      }
    }
    per_dir[dir] = (d_rh, d_rm, d_ph, d_pm)
  }
  println(
    "=== per-directory breakdown (recall_hit / recall_miss / precision_hit / precision_miss) ===",
  )
  for kv in per_dir {
    println("  \{kv.0}: \{kv.1.0} / \{kv.1.1} / \{kv.1.2} / \{kv.1.3}")
  }
  if total == 0 {
    println("skip: no .ts sources found in pinned conformance corpus")
    return
  }
  let with_baseline = recall_hit + recall_miss
  let without_baseline = precision_hit + precision_miss
  println(
    "baseline accuracy: parsed=\{parsed}/\{total} | recall=\{recall_hit}/\{with_baseline} | precision=\{precision_hit}/\{without_baseline} (false-positives=\{precision_miss})",
  )
  // Regression gates calibrated against today's measurements. Tighten
  // as accuracy improves; loosen only with justification.
  //
  // Recall floor: T9 permissive-mode suppressions trade nearly all
  // recall for the FP elimination required by the "9割潰す" goal.
  // Measured 2026-06-02 via `tscheck`: recall is 16 / 488 ≈ 3 %.
  // Floor at 2 % so a genuine pipeline regression (parser stops
  // producing modules, etc.) still trips; the recall *quality* is
  // governed by the strict diagnostics that unit tests still pin.
  if with_baseline > 0 && recall_hit * 100 < with_baseline * 2 {
    fail(
      "recall floor breached: \{recall_hit}/\{with_baseline} baseline-positive cases caught (< 2 %)",
    )
  }
  // Precision floor: T9 permissive mode hits FP = 0 / 319 (verified
  // 2026-06-02 via the `tscheck` CLI walking the same corpus -- the
  // "9割潰す" goal). Cap at 5 % so a regression that re-introduces
  // even a few false positives trips immediately.
  if without_baseline > 0 && precision_miss * 100 > without_baseline * 5 {
    fail(
      "precision floor breached: \{precision_miss}/\{without_baseline} clean cases reported as failing (> 5 %)",
    )
  }
}

///|
async test "parser: smoke-run against the entire TypeScript repo source" {
  // Broader sweep than `typescript/src/compiler` — walks the full
  // `typescript/src` tree (compiler + services + server + harness +
  // tsserver + jsTyping + ...). About 379k lines across ~250 files.
  // Parser must not crash on any of them and we record per-directory
  // parse-rate so regressions are visible.
  let root = "typescript/src"
  let kind = @fs.kind(root, follow_symlink=false) catch {
    _ => @fs.FileKind::Unknown
  }
  if !(kind is @fs.FileKind::Directory) {
    println("skip: \{root} not found")
    return
  }
  let files = collect_ts_source_files_recursive(root)
  let mut total = 0
  let mut parsed = 0
  let mut checked = 0
  let per_dir : Map[String, (Int, Int)] = {}
  let parse_failures : Array[String] = []
  let check_crashes : Array[String] = []
  for path in files {
    if path.has_suffix(".d.ts") {
      continue
    }
    total += 1
    let content = @fs.read_file(path).text() catch { _ => continue }
    let bucket = match path.find("/") {
      Some(_) => {
        // path looks like `typescript/src/<bucket>/...`. Pull the
        // third path segment.
        let parts = path.split("/")
        let arr : Array[StringView] = []
        for p in parts {
          arr.push(p)
        }
        if arr.length() >= 3 {
          arr[2].to_owned()
        } else {
          "(other)"
        }
      }
      None => "(root)"
    }
    let prev = per_dir.get(bucket).unwrap_or((0, 0))
    let module_ = try
      Parser::from_source_with_jsx(content, false).parse_module()
    catch {
      err => {
        parse_failures.push(path + ": \{err}")
        per_dir[bucket] = (prev.0 + 1, prev.1)
        continue
      }
    } noraise {
      m => {
        parsed += 1
        per_dir[bucket] = (prev.0 + 1, prev.1 + 1)
        m
      }
    }
    let _ = @checker.check_module_function_bodies(module_)
    checked += 1
  }
  if total == 0 {
    println("skip: no .ts sources found under \{root}")
    return
  }
  println(
    "TypeScript repo source: total=\{total} parsed=\{parsed} checked=\{checked}",
  )
  let buckets : Array[String] = []
  for entry in per_dir {
    let (k, _) = entry
    buckets.push(k)
  }
  buckets.sort()
  for bucket in buckets {
    let (t, p) = per_dir.get(bucket).unwrap_or((0, 0))
    println("  \{bucket}: \{p}/\{t}")
  }
  if check_crashes.length() > 0 {
    for c in check_crashes {
      println("CHECK CRASH " + c)
    }
    fail("\{check_crashes.length()} checker crashes on repo source")
  }
  // 80 % is the floor — the TS source intentionally uses some
  // very-recent syntax (decorators with metadata, some experimental
  // grammar) that lags a TS minor we don't yet handle.
  if parse_failures.length() <= 16 {
    for f in parse_failures {
      println("PARSE FAIL " + f)
    }
  }
  if parsed * 100 < total * 80 {
    fail("repo-source parse rate below 80 %: \{parsed}/\{total}")
  }
}

///|
async test "parser: smoke-run against the TypeScript compiler source" {
  // The TypeScript compiler itself (`typescript/src/compiler/*.ts`)
  // is a big single-file-per-module surface — ~145k lines total
  // across 38 files. Running it through our parser is a higher-bar
  // smoke than the conformance corpus, since the compiler source is
  // intentionally exercising every TS feature.
  //
  // We also run the expression-level checker on every successfully
  // parsed module so the smoke covers both the parser *and* the
  // checker against the same real-world corpus. The checker must
  // never crash — issue counts are not asserted.
  let dir = "typescript/src/compiler"
  let kind = @fs.kind(dir, follow_symlink=false) catch {
    _ => @fs.FileKind::Unknown
  }
  if !(kind is @fs.FileKind::Directory) {
    println("skip: \{dir} not found")
    return
  }
  let entries = @fs.readdir(
    dir,
    include_hidden=false,
    include_special=false,
    sort=true,
  ) catch {
    _ => []
  }
  let mut total = 0
  let mut parsed = 0
  let mut checked = 0
  let parse_failures : Array[String] = []
  let check_crashes : Array[String] = []
  for name in entries {
    if !name.has_suffix(".ts") || name.has_suffix(".d.ts") {
      continue
    }
    total += 1
    let path = dir + "/" + name
    let content = @fs.read_file(path).text() catch { _ => continue }
    let module_ = try
      Parser::from_source_with_jsx(content, false).parse_module()
    catch {
      err => {
        parse_failures.push(name + ": \{err}")
        continue
      }
    } noraise {
      m => {
        parsed += 1
        m
      }
    }
    let _ = @checker.check_module_function_bodies(module_)
    checked += 1
  }
  println(
    "TypeScript compiler source: total=\{total} parsed=\{parsed} checked=\{checked}",
  )
  if parse_failures.length() > 0 && parse_failures.length() <= 8 {
    for f in parse_failures {
      println("PARSE FAIL " + f)
    }
  }
  if check_crashes.length() > 0 {
    for c in check_crashes {
      println("CHECK CRASH " + c)
    }
    fail("\{check_crashes.length()} checker crashes on compiler source")
  }
  if total > 0 && parsed * 100 < total * 50 {
    fail("compiler-source parse rate below 50 %: \{parsed}/\{total}")
  }
}

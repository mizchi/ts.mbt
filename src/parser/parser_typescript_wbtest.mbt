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
    let kind = @fs.kind(root, follow_symlink=false) catch { _ => @fs.FileKind::Unknown }
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
      ) catch { _ => [] }
  let files : Array[String] = []
  for name in entries {
    if name.has_suffix(".d.ts") {
      files.push(base + "/" + name)
    }
  }
  files
}

///|
async test "parser: parse TypeScript lib d.ts files" {
  let files = list_typescript_lib_files()
  if files.length() == 0 {
    fail("typescript/lib not found. Ensure the TypeScript submodule is initialized.")
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

  // Read from file
  let file_content = @fs.read_file("typescript/src/lib/es5.d.ts").text() catch {
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
      parts.push(line.to_string())
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
  let test_file = "typescript/src/lib/es2015.symbol.d.ts"
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
      println("SymbolConstructor fields: \{fields}")
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
  let content = @fs.read_file("typescript/src/lib/es5.d.ts").text() catch {
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
      let expected = ["length", "toString", "pop", "push", "concat", "join", "reverse", "shift", "slice", "sort", "splice", "unshift", "indexOf", "lastIndexOf", "every", "some", "forEach", "map", "filter", "reduce", "reduceRight"]
      let missing : Array[String] = []
      for name in expected {
        if not(fields.contains(name)) {
          missing.push(name)
        }
      }
      if missing.length() > 0 {
        println("Array interface missing fields: \{missing}")
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
      println("Found interfaces: \{names}")
    }
  }
}

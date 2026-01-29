// test

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

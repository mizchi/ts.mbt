// Smoke tests that exercise the `mizchi/ts/checker` API on real parsed
// fixtures. These run after the parser, so any false positive here would
// reflect a real gap in the checker's resolution logic.

///|
test "checker: bridge_smoke double-entry has no unresolved type references" {
  let src = "export declare function double(input: number): number;"
  let module_ = @parser.parse_module_from_source_with_const_values(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let unresolved = @checker.unresolved_type_references(module_)
  if unresolved.length() != 0 {
    fail("Unexpected unresolved references: \{unresolved}")
  }
}

///|
test "checker: enum decl shadows references to its own name" {
  let src =
    #|export declare enum Mode {
    #|  Read = "read",
    #|  Write = "write",
    #|}
    #|export declare function recordMode(mode: Mode): string;
    #|export declare function nextMode(mode: Mode): Mode;
  let module_ = @parser.parse_module_from_source_with_const_values(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let unresolved = @checker.unresolved_type_references(module_)
  if unresolved.length() != 0 {
    fail("Unexpected unresolved references: \{unresolved}")
  }
}

///|
test "checker: detects truly missing type references" {
  let src =
    #|export declare function take(box: Inner): void;
  let module_ = @parser.parse_module_from_source_with_const_values(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let unresolved = @checker.unresolved_type_references(module_)
  // Either Inner is reported, or the parser preemptively widens it to
  // something well-known. Whichever happens, the test surfaces it.
  if unresolved.length() != 1 {
    fail("Expected exactly one unresolved name, got: \{unresolved}")
  }
  if unresolved[0] != "Inner" {
    fail("Expected unresolved name to be Inner, got: \{unresolved[0]}")
  }
}

///|
test "checker: nested generic params in interfaces are recognised in scope" {
  let src =
    #|export interface Box<T> {
    #|  value: T;
    #|  inner: Wrap<T>;
    #|}
    #|export interface Wrap<U> {
    #|  raw: U;
    #|}
  let module_ = @parser.parse_module_from_source_with_const_values(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let unresolved = @checker.unresolved_type_references(module_)
  if unresolved.length() != 0 {
    fail("Unexpected unresolved references: \{unresolved}")
  }
}

///|
test "checker: assignability roundtrips on parsed type aliases" {
  // Parse a couple of aliases, build a resolver from them, and check
  // assignability across the chain.
  let src =
    #|export type ID = string;
    #|export type UserId = ID;
  let module_ = @parser.parse_module_from_source_with_const_values(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let table : Map[String, @ast.TsType] = {}
  for ta in module_.type_aliases {
    table[ta.name] = ta.type_
  }
  let resolve = fn(name) { table.get(name) }
  // UserId should be assignable to string after resolver expansion.
  if !@checker.is_assignable_to_with(Named("UserId"), String_, resolve) {
    fail("UserId should resolve to string")
  }
  if @checker.is_assignable_to_with(Named("UserId"), Number, resolve) {
    fail("UserId is string, not number")
  }
}

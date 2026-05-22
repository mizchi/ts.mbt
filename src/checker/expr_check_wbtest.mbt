// Tests for the new expression / statement-level checker. The structural
// checks in `check_module.mbt` are validated separately — these tests focus
// strictly on what the new layer adds on top.

///|
fn parse_function_named(src : String, name : String) -> @ast.TsFunc? {
  match (try? @parser.parse_module_from_source_with_const_values(src, {})) {
    Ok(module_) => {
      for f in module_.funcs {
        if f.name == name {
          return Some(f)
        }
      }
      None
    }
    Err(_) => None
  }
}

///|
test "expr_check: const initializer assignable to declared type" {
  let src =
    #|function f(): void {
    #|  const x: number = 1;
    #|  const y: string = "ok";
    #|}
  match parse_function_named(src, "f") {
    Some(f) => {
      let issues = check_function_body(f)
      assert_eq(issues.length(), 0)
    }
    None => fail("function f not found")
  }
}

///|
test "expr_check: const initializer with wrong primitive type" {
  let src =
    #|function f(): void {
    #|  const x: number = "oops";
    #|}
  match parse_function_named(src, "f") {
    Some(f) => {
      let issues = check_function_body(f)
      assert_eq(issues.length(), 1)
      let issue = issues[0]
      assert_true(issue.path.contains("function f"))
      assert_true(issue.path.contains("binding `x`"))
      assert_true(issue.message.contains("number"))
      assert_true(issue.message.contains("string"))
    }
    None => fail("function f not found")
  }
}

///|
test "expr_check: missing return value for non-void return type" {
  let src =
    #|function f(): number {
    #|  return;
    #|}
  match parse_function_named(src, "f") {
    Some(f) => {
      let issues = check_function_body(f)
      assert_eq(issues.length(), 1)
      assert_true(issues[0].path.contains("return"))
    }
    None => fail("function f not found")
  }
}

///|
test "expr_check: return value with wrong type" {
  let src =
    #|function f(): number {
    #|  return "oops";
    #|}
  match parse_function_named(src, "f") {
    Some(f) => {
      let issues = check_function_body(f)
      assert_eq(issues.length(), 1)
      assert_true(issues[0].message.contains("number"))
      assert_true(issues[0].message.contains("string"))
    }
    None => fail("function f not found")
  }
}

///|
test "expr_check: return value matching declared type passes" {
  let src =
    #|function add(a: number, b: number): number {
    #|  return a + b;
    #|}
  match parse_function_named(src, "add") {
    Some(f) => {
      let issues = check_function_body(f)
      assert_eq(issues.length(), 0)
    }
    None => fail("function add not found")
  }
}

///|
test "expr_check: void return tolerates bare return" {
  let src =
    #|function log(msg: string): void {
    #|  return;
    #|}
  match parse_function_named(src, "log") {
    Some(f) => {
      let issues = check_function_body(f)
      assert_eq(issues.length(), 0)
    }
    None => fail("function log not found")
  }
}

///|
test "expr_check: silently accepts unknown identifier as any" {
  // Real-world `.ts` files rely on untyped globals; we must not flag them.
  let src =
    #|function f(): void {
    #|  const x: number = globalCounter;
    #|  return;
    #|}
  match parse_function_named(src, "f") {
    Some(f) => {
      let issues = check_function_body(f)
      assert_eq(issues.length(), 0)
    }
    None => fail("function f not found")
  }
}

///|
test "expr_check: unannotated function return skips return-type checks" {
  // No return type annotation → checker treats it as `Any` and accepts any
  // returned value without flagging it.
  let src =
    #|function f(a: number) {
    #|  return "anything-goes";
    #|}
  match parse_function_named(src, "f") {
    Some(f) => {
      let issues = check_function_body(f)
      assert_eq(issues.length(), 0)
    }
    None => fail("function f not found")
  }
}

///|
test "expr_check: parameter binding seeds the env" {
  let src =
    #|function takesStr(s: string): number {
    #|  return s;
    #|}
  match parse_function_named(src, "takesStr") {
    Some(f) => {
      let issues = check_function_body(f)
      assert_eq(issues.length(), 1)
      assert_true(issues[0].message.contains("number"))
      assert_true(issues[0].message.contains("string"))
    }
    None => fail("function takesStr not found")
  }
}

///|
test "expr_check: nested block scope strips inner bindings on exit" {
  // After the inner block ends, `inner` should no longer be in scope, so
  // the second `inner` reference falls back to `any` and the assignment to
  // a `number` succeeds (no issue raised).
  let src =
    #|function f(): number {
    #|  {
    #|    const inner: string = "hello";
    #|  }
    #|  const x: number = inner;
    #|  return x;
    #|}
  match parse_function_named(src, "f") {
    Some(f) => {
      let issues = check_function_body(f)
      assert_eq(issues.length(), 0)
    }
    None => fail("function f not found")
  }
}

///|
test "expr_check: typeof expression infers as string" {
  let src =
    #|function f(x: number): string {
    #|  return typeof x;
    #|}
  match parse_function_named(src, "f") {
    Some(f) => {
      let issues = check_function_body(f)
      assert_eq(issues.length(), 0)
    }
    None => fail("function f not found")
  }
}

///|
test "expr_check: numeric binop result is number" {
  let src =
    #|function f(a: number, b: number): string {
    #|  return a + b;
    #|}
  match parse_function_named(src, "f") {
    Some(f) => {
      let issues = check_function_body(f)
      assert_eq(issues.length(), 1)
      assert_true(issues[0].message.contains("string"))
    }
    None => fail("function f not found")
  }
}

///|
test "expr_check: string `+` operand is string" {
  let src =
    #|function f(a: number): string {
    #|  return a + "abc";
    #|}
  match parse_function_named(src, "f") {
    Some(f) => {
      let issues = check_function_body(f)
      assert_eq(issues.length(), 0)
    }
    None => fail("function f not found")
  }
}

///|
test "expr_check: check_module_function_bodies walks all top-level funcs" {
  let src =
    #|function a(): number { return "x"; }
    #|function b(): string { return 1; }
    #|function c(): number { return 1; }
  let module_ = match (try?
      @parser.parse_module_from_source_with_const_values(src, {})) {
    Ok(m) => m
    Err(e) => {
      fail("parse failed: \{e}")
      return
    }
  }
  let issues = check_module_function_bodies(module_)
  assert_eq(issues.length(), 2)
  let mut saw_a = false
  let mut saw_b = false
  for i in issues {
    if i.path.contains("function a") {
      saw_a = true
    }
    if i.path.contains("function b") {
      saw_b = true
    }
  }
  assert_true(saw_a)
  assert_true(saw_b)
}

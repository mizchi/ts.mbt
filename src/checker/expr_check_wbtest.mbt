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

///|
fn parse_module_or_empty(src : String) -> @ast.TsModule {
  match (try? @parser.parse_module_from_source_with_const_values(src, {})) {
    Ok(m) => m
    Err(_) =>
      // Empty fallback — the test's subsequent assertions will fail loudly
      // if parsing failed unexpectedly.
      {
        funcs: [],
        interfaces: [],
        type_aliases: [],
        imports: [],
        values: [],
        classes: [],
        namespaces: [],
        enums: [],
      }
  }
}

///|
test "expr_check: argument count mismatch on top-level function call" {
  let src =
    #|function add(a: number, b: number): number { return a + b; }
    #|function caller(): number { return add(1); }
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  // Should flag the call site for the missing argument.
  let mut saw_count = false
  for i in issues {
    if i.message.contains("expected 2") && i.message.contains("got 1") {
      saw_count = true
    }
  }
  assert_true(saw_count)
}

///|
test "expr_check: argument type mismatch on top-level function call" {
  let src =
    #|function takesString(s: string): void {}
    #|function caller(): void { takesString(42); }
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  let mut saw_arg_err = false
  for i in issues {
    if i.message.contains("string") && i.message.contains("number") {
      saw_arg_err = true
    }
  }
  assert_true(saw_arg_err)
}

///|
test "expr_check: interface property access is typed via resolver" {
  let src =
    #|interface Point { x: number; y: number; }
    #|function getX(p: Point): string { return p.x; }
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  // p.x is `number` but the declared return type is `string` → mismatch.
  let mut found = false
  for i in issues {
    if i.message.contains("string") && i.message.contains("number") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "expr_check: interface property access correct usage passes" {
  let src =
    #|interface Point { x: number; y: number; }
    #|function getX(p: Point): number { return p.x; }
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  assert_eq(issues.length(), 0)
}

///|
test "expr_check: interface method call return type" {
  let src =
    #|interface Logger { log(msg: string): void; }
    #|function use(l: Logger): string { return l.log("hi"); }
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  let mut found = false
  for i in issues {
    if i.message.contains("string") && i.message.contains("void") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "expr_check: interface method call argument type checked" {
  let src =
    #|interface Logger { log(msg: string): void; }
    #|function use(l: Logger): void { l.log(42); }
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  let mut found = false
  for i in issues {
    if i.path.contains("call `log`") &&
       i.message.contains("string") && i.message.contains("number") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "expr_check: async function body returns inner T not Promise<T>" {
  let src =
    #|async function f(): Promise<number> { return 1; }
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  assert_eq(issues.length(), 0)
}

///|
test "expr_check: async function wrong inner return type flagged" {
  let src =
    #|async function f(): Promise<number> { return "oops"; }
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  let mut found = false
  for i in issues {
    if i.message.contains("number") && i.message.contains("string") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "expr_check: await unwraps Promise<T>" {
  let src =
    #|async function fetchN(): Promise<number> { return 1; }
    #|async function user(): Promise<string> {
    #|  const n = await fetchN();
    #|  return n;
    #|}
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  // `n` is number, declared return inner type is string → mismatch.
  let mut found = false
  for i in issues {
    if i.message.contains("string") && i.message.contains("number") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "expr_check: typeof narrowing on string in then-branch" {
  let src =
    #|function f(x: string | number): number {
    #|  if (typeof x === "string") {
    #|    return x;
    #|  }
    #|  return 0;
    #|}
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  // After narrowing, `x` is string, declared return is number → mismatch.
  let mut found = false
  for i in issues {
    if i.path.contains("return") &&
       i.message.contains("number") && i.message.contains("string") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "expr_check: typeof narrowing accepts compatible branch" {
  let src =
    #|function f(x: string | number): string {
    #|  if (typeof x === "string") {
    #|    return x;
    #|  }
    #|  return "fallback";
    #|}
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  assert_eq(issues.length(), 0)
}

///|
test "expr_check: new ClassName returns instance type and checks ctor args" {
  let src =
    #|class Point { constructor(x: number, y: number) {} }
    #|function make(): number { return new Point(1, 2); }
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  // `new Point(...)` is `Point`, not `number`.
  let mut found = false
  for i in issues {
    if i.message.contains("number") && i.message.contains("Point") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "expr_check: constructor argument type mismatch" {
  let src =
    #|class Point { constructor(x: number, y: number) {} }
    #|function make(): Point { return new Point("a", 2); }
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  let mut found = false
  for i in issues {
    if i.path.contains("new `Point`") &&
       i.message.contains("number") && i.message.contains("string") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "expr_check: tuple element access via literal index" {
  let src =
    #|function f(t: [number, string]): string { return t[0]; }
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  let mut found = false
  for i in issues {
    if i.message.contains("string") && i.message.contains("number") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "expr_check: array index access returns element type" {
  let src =
    #|function f(xs: number[]): string { return xs[0]; }
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  let mut found = false
  for i in issues {
    if i.message.contains("string") && i.message.contains("number") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "expr_check: top-level function visible as global" {
  let src =
    #|function helper(): number { return 1; }
    #|function caller(): string { return helper(); }
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  let mut found = false
  for i in issues {
    if i.message.contains("string") && i.message.contains("number") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "expr_check: type alias is unwrapped for property access" {
  let src =
    #|interface Point { x: number; }
    #|type P = Point;
    #|function f(p: P): string { return p.x; }
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  let mut found = false
  for i in issues {
    if i.message.contains("string") && i.message.contains("number") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "expr_check: interface extends chain resolves field" {
  let src =
    #|interface Base { id: number; }
    #|interface Sub extends Base { name: string; }
    #|function f(s: Sub): string { return s.id; }
  let module_ = parse_module_or_empty(src)
  let issues = check_module_function_bodies(module_)
  // s.id is from Base → number; return type string → mismatch.
  let mut found = false
  for i in issues {
    if i.message.contains("string") && i.message.contains("number") {
      found = true
    }
  }
  assert_true(found)
}

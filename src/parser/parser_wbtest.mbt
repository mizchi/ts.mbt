// test

///|
fn parse_expr_from(src : String) -> @ast.TsExpr {
  try! Parser::from_source(src).parse_expr()
}

///|
fn parse_stmt_from(src : String) -> @ast.TsStmt {
  try! Parser::from_source(src).parse_stmt()
}

///|
fn parse_binding_from(src : String) -> @ast.TsBinding {
  try! Parser::from_source(src).parse_binding_pattern()
}

///|
fn parse_assign_binding_from(src : String) -> @ast.TsBinding {
  try! Parser::from_source(src).parse_assignment_binding_pattern()
}

///|
test "lexer: tokenize simple" {
  let lexer = Lexer::new("let x: number = 42;")
  let tokens = lexer.tokenize()
  assert_eq(tokens[0].kind, Let)
  assert_eq(tokens[1].kind, Ident("x"))
  assert_eq(tokens[2].kind, Colon)
  assert_eq(tokens[3].kind, NumberType)
  assert_eq(tokens[4].kind, Eq)
  assert_eq(tokens[5].kind, Int(42))
  assert_eq(tokens[6].kind, Semicolon)
  assert_eq(tokens[7].kind, Eof)
}

///|
test "lexer: tokenize operators" {
  let lexer = Lexer::new("a + b * c === d")
  let tokens = lexer.tokenize()
  assert_eq(tokens[0].kind, Ident("a"))
  assert_eq(tokens[1].kind, Plus)
  assert_eq(tokens[2].kind, Ident("b"))
  assert_eq(tokens[3].kind, Star)
  assert_eq(tokens[4].kind, Ident("c"))
  assert_eq(tokens[5].kind, EqEqEq)
  assert_eq(tokens[6].kind, Ident("d"))
}

///|
test "lexer: tokenize function" {
  let lexer = Lexer::new(
    "function add(a: number, b: number): number { return a + b; }",
  )
  let tokens = lexer.tokenize()
  assert_eq(tokens[0].kind, Function)
  assert_eq(tokens[1].kind, Ident("add"))
  assert_eq(tokens[2].kind, LParen)
}

///|
test "parser: parse simple expr" {
  let parser = Parser::from_source("1 + 2")
  let expr = parser.parse_expr()
  match expr {
    BinOp(Add, IntLit(1), IntLit(2)) => ()
    _ => fail("unexpected result")
  }
}

///|
test "parser: parse complex expr" {
  let parser = Parser::from_source("1 + 2 * 3")
  let expr = parser.parse_expr()
  // 1 + (2 * 3)
  match expr {
    BinOp(Add, IntLit(1), BinOp(Mul, IntLit(2), IntLit(3))) => ()
    _ => fail("unexpected result: \{expr}")
  }
}

///|
test "parser: parse comparison" {
  let parser = Parser::from_source("a <= b")
  let expr = parser.parse_expr()
  match expr {
    BinOp(BinLe, Var("a"), Var("b")) => ()
    _ => fail("unexpected result: \{expr}")
  }
}

///|
test "parser: parse call" {
  let parser = Parser::from_source("add(1, 2)")
  let expr = parser.parse_expr()
  match expr {
    Call("add", args) => assert_eq(args.length(), 2)
    _ => fail("unexpected result: \{expr}")
  }
}

///|
test "parser: parse let stmt" {
  let parser = Parser::from_source("let x: number = 42;")
  let stmt = parser.parse_stmt()
  match stmt {
    Let(@ast.TsBinding::Ident("x"), Number, IntLit(42)) => ()
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse return stmt" {
  let parser = Parser::from_source("return a + b;")
  parser.in_function = true // Set function context for return
  let stmt = parser.parse_stmt()
  match stmt {
    Return(Some(BinOp(Add, Var("a"), Var("b")))) => ()
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse if stmt" {
  let parser = Parser::from_source(
    "if (x > 0) { return 1; } else { return 0; }",
  )
  parser.in_function = true // Set function context for return
  let stmt = parser.parse_stmt()
  match stmt {
    If(_, then_block, Some(else_block)) => {
      assert_eq(then_block.stmts.length(), 1)
      assert_eq(else_block.stmts.length(), 1)
    }
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse while stmt" {
  let parser = Parser::from_source("while (i < n) { i = i + 1; }")
  let stmt = parser.parse_stmt()
  match stmt {
    While(BinOp(BinLt, Var("i"), Var("n")), body) =>
      assert_eq(body.stmts.length(), 1)
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse for stmt" {
  let parser = Parser::from_source(
    "for (let i = 0; i < 10; i = i + 1) { i = i + 1; }",
  )
  let stmt = parser.parse_stmt()
  match stmt {
    For(
      Some(Let(@ast.TsBinding::Ident("i"), Any, IntLit(0))),
      Some(BinOp(BinLt, Var("i"), IntLit(10))),
      update,
      body
    ) => {
      match update {
        Some(Assign("i", BinOp(Add, Var("i"), IntLit(1))))
        | Some(Expr(AssignExpr("i", BinOp(Add, Var("i"), IntLit(1))))) => ()
        _ => fail("unexpected update: \{update}")
      }
      assert_eq(body.stmts.length(), 1)
    }
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse for stmt with uninitialized let" {
  let parser = Parser::from_source(
    "for (let i; i < 10; i = i + 1) { i = i + 1; }",
  )
  let stmt = parser.parse_stmt()
  match stmt {
    For(
      Some(Let(@ast.TsBinding::Ident("i"), Any, Var("undefined"))),
      Some(BinOp(BinLt, Var("i"), IntLit(10))),
      _,
      body
    ) => assert_eq(body.stmts.length(), 1)
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse for stmt with multi-let" {
  let parser = Parser::from_source(
    "for (let i = 0, j; i < 10; i = i + 1) { i = i + 1; }",
  )
  let stmt = parser.parse_stmt()
  match stmt {
    For(Some(Block(init_block)), Some(BinOp(BinLt, Var("i"), IntLit(10))), _, _) => {
      assert_eq(init_block.stmts.length(), 2)
      match init_block.stmts[0] {
        Let(@ast.TsBinding::Ident("i"), Any, IntLit(0)) => ()
        _ => fail("unexpected init[0]: \{init_block.stmts[0]}")
      }
      match init_block.stmts[1] {
        Let(@ast.TsBinding::Ident("j"), Any, Var("undefined")) => ()
        _ => fail("unexpected init[1]: \{init_block.stmts[1]}")
      }
    }
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse let with multiple declarators" {
  let parser = Parser::from_source("let a, b = 1;")
  let stmt = parser.parse_stmt()
  match stmt {
    Block(block) => {
      assert_eq(block.stmts.length(), 2)
      match block.stmts[0] {
        Let(@ast.TsBinding::Ident("a"), Any, Var("undefined")) => ()
        _ => fail("unexpected decl[0]: \{block.stmts[0]}")
      }
      match block.stmts[1] {
        Let(@ast.TsBinding::Ident("b"), Any, IntLit(1)) => ()
        _ => fail("unexpected decl[1]: \{block.stmts[1]}")
      }
    }
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse for-of stmt" {
  let parser = Parser::from_source("for (let x of arr) { x; }")
  let stmt = parser.parse_stmt()
  match stmt {
    ForOf(
      @ast.TsForOfKind::Let,
      @ast.TsBinding::Ident("x"),
      Number,
      Var("arr"),
      body
    ) => assert_eq(body.stmts.length(), 1)
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse for-await-of stmt" {
  let parser = Parser::from_source("for await (var x of []) { x; }")
  let stmt = parser.parse_stmt()
  match stmt {
    ForOf(
      @ast.TsForOfKind::Var,
      @ast.TsBinding::Ident("x"),
      Number,
      ArrayLit(_),
      body
    ) => assert_eq(body.stmts.length(), 1)
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: let destructuring requires initializer" {
  let ok = try {
    let parser = Parser::from_source("let { a };")
    let _ = parser.parse_stmt()
    true
  } catch {
    _ => false
  }
  assert_eq(ok, false)
}

///|
test "parser: parse let expr statement with newline" {
  let parser = Parser::from_source("let\nx = 1;")
  let stmt = parser.parse_stmt()
  match stmt {
    Expr(Var("let")) => ()
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse for-in stmt" {
  let parser = Parser::from_source("for (let k in obj) { k; }")
  let stmt = parser.parse_stmt()
  match stmt {
    ForIn(
      @ast.TsForOfKind::Let,
      @ast.TsBinding::Ident("k"),
      Number,
      Var("obj"),
      body
    ) => assert_eq(body.stmts.length(), 1)
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse for-in let identifier" {
  let parser = Parser::from_source("for (let in obj) { }")
  let stmt = parser.parse_stmt()
  match stmt {
    ForIn(
      @ast.TsForOfKind::Assign,
      @ast.TsBinding::Ident("let"),
      Number,
      Var("obj"),
      body
    ) => assert_eq(body.stmts.length(), 0)
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse do-while stmt" {
  let parser = Parser::from_source("do { i = i + 1; } while (i < n);")
  let stmt = parser.parse_stmt()
  match stmt {
    DoWhile(BinOp(BinLt, Var("i"), Var("n")), body) =>
      assert_eq(body.stmts.length(), 1)
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse switch stmt" {
  let parser = Parser::from_source(
    "switch (x) { case 1: break; default: break; }",
  )
  let stmt = parser.parse_stmt()
  match stmt {
    Switch(Var("x"), cases) => {
      assert_eq(cases.length(), 2)
      match cases[0].test_expr {
        Some(IntLit(1)) => ()
        _ => fail("unexpected case[0]: \{cases[0]}")
      }
      match cases[1].test_expr {
        None => ()
        _ => fail("unexpected case[1]: \{cases[1]}")
      }
    }
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse try/catch/finally stmt" {
  let parser = Parser::from_source(
    "try { x = 1; } catch (e) { x = 2; } finally { x = 3; }",
  )
  let stmt = parser.parse_stmt()
  match stmt {
    Try(
      try_block,
      Some(@ast.TsBinding::Ident("e")),
      Some(catch_block),
      Some(finally_block)
    ) => {
      assert_eq(try_block.stmts.length(), 1)
      assert_eq(catch_block.stmts.length(), 1)
      assert_eq(finally_block.stmts.length(), 1)
    }
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse try/catch with destructuring" {
  let parser = Parser::from_source("try { x = 1; } catch ({ e }) { x = e; }")
  let stmt = parser.parse_stmt()
  match stmt {
    Try(_, Some(@ast.TsBinding::Object(obj)), Some(_), None) => {
      assert_eq(obj.props.length(), 1)
      assert_eq(obj.props[0].key, "e")
    }
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse break/continue with label" {
  let parser = Parser::from_source("loop: while (true) { break loop; }")
  let stmt = parser.parse_stmt()
  match stmt {
    Label("loop", While(BoolLit(true), body)) =>
      match body.stmts[0] {
        Break(Some("loop")) => ()
        _ => fail("unexpected body: \{body}")
      }
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse debugger stmt" {
  let parser = Parser::from_source("debugger;")
  let stmt = parser.parse_stmt()
  match stmt {
    Debugger => ()
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse throw stmt" {
  let parser = Parser::from_source("throw err;")
  let stmt = parser.parse_stmt()
  match stmt {
    Throw(Var("err")) => ()
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: disallow let in single-statement if" {
  let ok = try {
    let parser = Parser::from_source("if (true) let x = 1;")
    let _ = parser.parse_stmt()
    true
  } catch {
    _ => false
  }
  assert_eq(ok, false)
}

///|
test "parser: parse function" {
  let src =
    #|function add(a: number, b: number): number {
    #|  return a + b;
    #|}
  let parser = Parser::from_source(src)
  let f = parser.parse_function()
  assert_eq(f.name, "add")
  assert_eq(f.params.length(), 2)
  assert_eq(f.params[0].name, "a")
  assert_eq(f.params[0].type_, Number)
  assert_eq(f.params[1].name, "b")
  assert_eq(f.return_type, Number)
  assert_eq(f.body.stmts.length(), 1)
}

///|
test "parser: parse factorial function" {
  let src =
    #|function factorial(n: number): number {
    #|  if (n <= 1) {
    #|    return 1;
    #|  }
    #|  return n * factorial(n - 1);
    #|}
  let parser = Parser::from_source(src)
  let f = parser.parse_function()
  assert_eq(f.name, "factorial")
  assert_eq(f.params.length(), 1)
  assert_eq(f.params[0].name, "n")
  assert_eq(f.body.stmts.length(), 2) // if + return
}

///|
test "parser: parse module" {
  let src =
    #|function add(a: number, b: number): number {
    #|  return a + b;
    #|}
    #|function mul(a: number, b: number): number {
    #|  return a * b;
    #|}
  let parser = Parser::from_source(src)
  let m = parser.parse_module()
  assert_eq(m.funcs.length(), 2)
  assert_eq(m.funcs[0].name, "add")
  assert_eq(m.funcs[1].name, "mul")
}

///|
test "parser: parse array type" {
  let parser = Parser::from_source("number[]")
  let t = parser.parse_type()
  match t {
    Array(Number) => ()
    _ => fail("expected Array(Number), got \{t}")
  }
}

///|
test "parser: parse array literal" {
  let parser = Parser::from_source("[1, 2, 3]")
  let expr = parser.parse_expr()
  match expr {
    ArrayLit(elements) => assert_eq(elements.length(), 3)
    _ => fail("expected ArrayLit, got \{expr}")
  }
}

///|
test "parser: parse index access" {
  let parser = Parser::from_source("arr[i]")
  let expr = parser.parse_expr()
  match expr {
    IndexAccess(Var("arr"), Var("i")) => ()
    _ => fail("expected IndexAccess, got \{expr}")
  }
}

///|
test "parser: parse property access" {
  let parser = Parser::from_source("arr.length")
  let expr = parser.parse_expr()
  match expr {
    PropAccess(Var("arr"), "length") => ()
    _ => fail("expected PropAccess, got \{expr}")
  }
}

///|
test "parser: parse new array" {
  let parser = Parser::from_source("new Array<number>(10)")
  let expr = parser.parse_expr()
  match expr {
    New("Array", args) => assert_eq(args.length(), 1)
    _ => fail("expected New, got \{expr}")
  }
}

///|
test "parser: parse interface" {
  let src =
    #|interface Point {
    #|  x: number;
    #|  y: number;
    #|}
  let parser = Parser::from_source(src)
  let iface = parser.parse_interface()
  assert_eq(iface.name, "Point")
  assert_eq(iface.fields.length(), 2)
  let (name0, type0) = iface.fields[0]
  assert_eq(name0, "x")
  assert_eq(type0, Number)
  let (name1, type1) = iface.fields[1]
  assert_eq(name1, "y")
  assert_eq(type1, Number)
}

///|
test "parser: parse default parameters" {
  let src =
    #|function greet(name: int, times: int = 1): int {
    #|  return name * times;
    #|}
  let parser = Parser::from_source(src)
  let f = parser.parse_function()
  assert_eq(f.name, "greet")
  assert_eq(f.params.length(), 2)
  assert_eq(f.params[0].name, "name")
  match f.params[0].default {
    None => ()
    Some(_) => fail("name should not have default")
  }
  assert_eq(f.params[1].name, "times")
  match f.params[1].default {
    Some(IntLit(1)) => ()
    _ => fail("times should have default 1")
  }
}

///|
test "parser: parse module with interface" {
  let src =
    #|interface Point {
    #|  x: number;
    #|  y: number;
    #|}
    #|function getX(p: Point): number {
    #|  return p.x;
    #|}
  let parser = Parser::from_source(src)
  let m = parser.parse_module()
  assert_eq(m.interfaces.length(), 1)
  assert_eq(m.funcs.length(), 1)
  assert_eq(m.interfaces[0].name, "Point")
  assert_eq(m.funcs[0].name, "getX")
}

///|
test "lexer: tokenize string literal" {
  let lexer = Lexer::new("\"hello world\"")
  let tokens = lexer.tokenize()
  assert_eq(tokens[0].kind, Str("hello world"))
  assert_eq(tokens[1].kind, Eof)
}

///|
test "lexer: tokenize string with escape" {
  let lexer = Lexer::new("\"hello\\nworld\"")
  let tokens = lexer.tokenize()
  assert_eq(tokens[0].kind, Str("hello\nworld"))
}

///|
test "lexer: tokenize single quoted string" {
  let lexer = Lexer::new("'test'")
  let tokens = lexer.tokenize()
  assert_eq(tokens[0].kind, Str("test"))
}

///|
test "parser: parse string literal" {
  let parser = Parser::from_source("\"hello\"")
  let expr = parser.parse_expr()
  match expr {
    StringLit("hello") => ()
    _ => fail("expected StringLit, got \{expr}")
  }
}

///|
test "parser: parse string type" {
  let parser = Parser::from_source("string")
  let t = parser.parse_type()
  match t {
    String_ => ()
    _ => fail("expected String_, got \{t}")
  }
}

///|
test "parser: parse let with string" {
  let parser = Parser::from_source("let s: string = \"hello\";")
  let stmt = parser.parse_stmt()
  match stmt {
    Let(@ast.TsBinding::Ident("s"), String_, StringLit("hello")) => ()
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse method call" {
  let parser = Parser::from_source("s.charAt(0)")
  let expr = parser.parse_expr()
  match expr {
    MethodCall(Var("s"), "charAt", args) => assert_eq(args.length(), 1)
    _ => fail("expected MethodCall, got \{expr}")
  }
}

///|
test "parser: parse chained method call" {
  let parser = Parser::from_source("s.substring(0, 5).concat(t)")
  let expr = parser.parse_expr()
  match expr {
    MethodCall(MethodCall(Var("s"), "substring", _), "concat", _) => ()
    _ => fail("expected chained MethodCall, got \{expr}")
  }
}

///|
test "parser: parse declare function" {
  let src =
    #|declare function console_log(msg: string): void;
  let parser = Parser::from_source(src)
  let _ = parser.expect(Declare)
  let _ = parser.expect(Function)
  let imp = parser.parse_declare_function()
  assert_eq(imp.name, "console_log")
  assert_eq(imp.module_, "env")
  assert_eq(imp.params.length(), 1)
  let (param_name, param_type) = imp.params[0]
  assert_eq(param_name, "msg")
  assert_eq(param_type, String_)
  assert_eq(imp.return_type, Void)
}

///|
test "parser: parse module with imports" {
  let src =
    #|declare function log(msg: string): void;
    #|declare function alert(msg: string): void;
    #|function main(): void {
    #|  log("hello");
    #|}
  let parser = Parser::from_source(src)
  let m = parser.parse_module()
  assert_eq(m.imports.length(), 2)
  assert_eq(m.imports[0].name, "log")
  assert_eq(m.imports[1].name, "alert")
  assert_eq(m.funcs.length(), 1)
  assert_eq(m.funcs[0].name, "main")
}

///|
test "parser: parse module with import/export" {
  let src =
    #|import { a as b } from "mod";
    #|export { b as c };
    #|export function foo(): void {
    #|}
  let parser = Parser::from_source(src)
  let m = parser.parse_module()
  assert_eq(m.funcs.length(), 1)
  assert_eq(m.funcs[0].name, "foo")
}

///|
test "parser: parse export default function expr" {
  let src =
    #|export default function() {
    #|}
  let parser = Parser::from_source(src)
  let m = parser.parse_module()
  assert_eq(m.funcs.length(), 0)
}

///|
test "parser: parse javascript without type annotations" {
  // type JavaScript
  let src =
    #|function add(a, b) {
    #|  return a + b;
    #|}
  let parser = Parser::from_source(src)
  let f = parser.parse_function()
  assert_eq(f.name, "add")
  assert_eq(f.params.length(), 2)
  assert_eq(f.params[0].name, "a")
  assert_eq(f.params[0].type_, Any) // type Any
  assert_eq(f.params[1].name, "b")
  assert_eq(f.params[1].type_, Any)
  assert_eq(f.return_type, Any) // return valuetype Any
}

///|
test "parser: parse let without type annotation" {
  let parser = Parser::from_source("let x = 42;")
  let stmt = parser.parse_stmt()
  match stmt {
    Let(@ast.TsBinding::Ident("x"), Any, IntLit(42)) => ()
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse mixed typed and untyped" {
  // typed
  let src =
    #|function mixed(a: number, b) {
    #|  let x = 1;
    #|  let y: int = 2;
    #|  return a + b;
    #|}
  let parser = Parser::from_source(src)
  let f = parser.parse_function()
  assert_eq(f.params[0].type_, Number) // type
  assert_eq(f.params[1].type_, Any) // type
  assert_eq(f.return_type, Any) // return valuetype
}

///|
test "parser: ast patterns expr literals" {
  match parse_expr_from("1") {
    IntLit(1) => ()
    _ => fail("expected IntLit(1)")
  }
  match parse_expr_from("1.5") {
    NumberLit(_) => ()
    _ => fail("expected NumberLit")
  }
  match parse_expr_from("true") {
    BoolLit(true) => ()
    _ => fail("expected BoolLit(true)")
  }
  match parse_expr_from("\"a\"") {
    StringLit("a") => ()
    _ => fail("expected StringLit(\"a\")")
  }
  match parse_expr_from("null") {
    NullLit => ()
    _ => fail("expected NullLit")
  }
  match parse_expr_from("[, 1]") {
    ArrayLit(elements) => {
      assert_eq(elements.length(), 2)
      match elements[0] {
        ArrayHole => ()
        _ => fail("expected ArrayHole")
      }
      match elements[1] {
        IntLit(1) => ()
        _ => fail("expected IntLit(1)")
      }
    }
    _ => fail("expected ArrayLit")
  }
  match parse_expr_from("/ab+/i") {
    New("RegExp", args) => assert_eq(args.length(), 2)
    _ => fail("expected RegExp constructor")
  }
}

///|
test "parser: ast patterns expr operators" {
  match parse_expr_from("1 + 2") {
    BinOp(Add, IntLit(1), IntLit(2)) => ()
    _ => fail("expected BinOp(Add)")
  }
  match parse_expr_from("a && b") {
    BinOp(And, Var("a"), Var("b")) => ()
    _ => fail("expected BinOp(And)")
  }
  match parse_expr_from("a ? b : c") {
    Cond(Var("a"), Var("b"), Var("c")) => ()
    _ => fail("expected Cond")
  }
  match parse_expr_from("a, b") {
    Seq(Var("a"), Var("b")) => ()
    _ => fail("expected Seq")
  }
  match parse_expr_from("-x") {
    UnaryOp(Neg, Var("x")) => ()
    _ => fail("expected UnaryOp(Neg)")
  }
  match parse_expr_from("!x") {
    UnaryOp(Not, Var("x")) => ()
    _ => fail("expected UnaryOp(Not)")
  }
  match parse_expr_from("typeof x") {
    UnaryOp(Typeof, Var("x")) => ()
    _ => fail("expected UnaryOp(Typeof)")
  }
  match parse_expr_from("void x") {
    UnaryOp(Void, Var("x")) => ()
    _ => fail("expected UnaryOp(Void)")
  }
  match parse_expr_from("++x") {
    UnaryOp(PreInc, Var("x")) => ()
    _ => fail("expected UnaryOp(PreInc)")
  }
  match parse_expr_from("x--") {
    UnaryOp(PostDec, Var("x")) => ()
    _ => fail("expected UnaryOp(PostDec)")
  }
}

///|
test "parser: ast patterns expr calls and access" {
  match parse_expr_from("foo(1)") {
    Call("foo", args) => assert_eq(args.length(), 1)
    _ => fail("expected Call")
  }
  match parse_expr_from("(a ? b : c)(1)") {
    CallExpr(Cond(_, _, _), args) => assert_eq(args.length(), 1)
    _ => fail("expected CallExpr")
  }
  match parse_expr_from("obj.m(1)") {
    MethodCall(Var("obj"), "m", args) => assert_eq(args.length(), 1)
    _ => fail("expected MethodCall")
  }
  match parse_expr_from("arr[0]") {
    IndexAccess(Var("arr"), IntLit(0)) => ()
    _ => fail("expected IndexAccess")
  }
  match parse_expr_from("obj.prop") {
    PropAccess(Var("obj"), "prop") => ()
    _ => fail("expected PropAccess")
  }
  match parse_expr_from("new Foo(1)") {
    New("Foo", args) => assert_eq(args.length(), 1)
    _ => fail("expected New")
  }
  match parse_expr_from("new foo.bar(1)") {
    NewExpr(PropAccess(Var("foo"), "bar"), args) => assert_eq(args.length(), 1)
    _ => fail("expected NewExpr")
  }
}

///|
test "parser: ast patterns expr composites" {
  match parse_expr_from("[1, 2]") {
    ArrayLit(elements) => assert_eq(elements.length(), 2)
    _ => fail("expected ArrayLit")
  }
  match parse_expr_from("{ a: 1, b }") {
    ObjectLit(fields) => {
      assert_eq(fields.length(), 2)
      match fields[0] {
        ("a", IntLit(1)) => ()
        _ => fail("expected field a: 1")
      }
      match fields[1] {
        ("b", Var("b")) => ()
        _ => fail("expected field b")
      }
    }
    _ => fail("expected ObjectLit")
  }
}

///|
test "parser: ast patterns expr assignments" {
  match parse_expr_from("x = 1") {
    AssignExpr("x", IntLit(1)) => ()
    _ => fail("expected AssignExpr")
  }
  match parse_expr_from("x += 1") {
    CompoundAssignExpr(Var("x"), AddAssign, IntLit(1)) => ()
    _ => fail("expected CompoundAssignExpr")
  }
  match parse_expr_from("obj.x = 1") {
    PropAssignExpr(Var("obj"), "x", IntLit(1)) => ()
    _ => fail("expected PropAssignExpr")
  }
  match parse_expr_from("arr[0] = 1") {
    IndexAssignExpr(Var("arr"), IntLit(0), IntLit(1)) => ()
    _ => fail("expected IndexAssignExpr")
  }
  match parse_expr_from("[a] = arr") {
    AssignPattern(binding, Var("arr")) =>
      match binding {
        @ast.TsBinding::Array(_) => ()
        _ => fail("expected array binding")
      }
    _ => fail("expected AssignPattern")
  }
}

///|
test "parser: ast patterns expr functions" {
  match parse_expr_from("x => x + 1") {
    ArrowFunc(params, ArrowExpr(BinOp(Add, Var("x"), IntLit(1))), _) =>
      assert_eq(params.length(), 1)
    _ => fail("expected ArrowFunc (expr)")
  }
  match parse_expr_from("(x) => { return x; }") {
    ArrowFunc(_, ArrowBlock(block), _) => assert_eq(block.stmts.length(), 1)
    _ => fail("expected ArrowFunc (block)")
  }
  match parse_expr_from("function foo(x) { return x; }") {
    FuncExpr(func) => {
      assert_eq(func.name, "foo")
      assert_eq(func.params.length(), 1)
      assert_eq(func.body.stmts.length(), 1)
    }
    _ => fail("expected FuncExpr")
  }
  let src =
    #|function* gen() {
    #|  yield 1;
    #|  yield* xs;
    #|}
  let gen = try! Parser::from_source(src).parse_function()
  match gen.body.stmts[0] {
    Expr(Yield(Some(IntLit(1)))) => ()
    _ => fail("expected yield")
  }
  match gen.body.stmts[1] {
    Expr(YieldStar(Var("xs"))) => ()
    _ => fail("expected yield*")
  }
}

///|
test "parser: ast patterns stmt basics" {
  match parse_stmt_from("const x = 1;") {
    Const(@ast.TsBinding::Ident("x"), Any, IntLit(1)) => ()
    _ => fail("expected Const")
  }
  match parse_stmt_from("x = 1;") {
    Expr(AssignExpr("x", IntLit(1))) => ()
    _ => fail("expected AssignExpr statement")
  }
  match parse_stmt_from("x += 1;") {
    Expr(CompoundAssignExpr(Var("x"), AddAssign, IntLit(1))) => ()
    _ => fail("expected CompoundAssignExpr statement")
  }
  match parse_stmt_from("obj.x = 1;") {
    Expr(PropAssignExpr(Var("obj"), "x", IntLit(1))) => ()
    _ => fail("expected PropAssignExpr statement")
  }
  match parse_stmt_from("arr[0] = 1;") {
    Expr(IndexAssignExpr(Var("arr"), IntLit(0), IntLit(1))) => ()
    _ => fail("expected IndexAssignExpr statement")
  }
  match parse_stmt_from("x + 1;") {
    Expr(BinOp(Add, Var("x"), IntLit(1))) => ()
    _ => fail("expected Expr")
  }
  match parse_stmt_from(";") {
    Empty => ()
    _ => fail("expected Empty")
  }
  match parse_stmt_from("{ x = 1; }") {
    Block(block) => assert_eq(block.stmts.length(), 1)
    _ => fail("expected Block")
  }
}

///|
test "parser: ast patterns binding" {
  match parse_binding_from("x") {
    @ast.TsBinding::Ident("x") => ()
    _ => fail("expected binding ident")
  }
  match parse_binding_from("[a, , b, ...rest]") {
    @ast.TsBinding::Array(arr) => {
      assert_eq(arr.items.length(), 3)
      match arr.items[0] {
        Some(elem) =>
          match elem.binding {
            @ast.TsBinding::Ident("a") => ()
            _ => fail("expected binding a")
          }
        None => fail("expected binding a")
      }
      match arr.items[1] {
        None => ()
        _ => fail("expected hole")
      }
      match arr.items[2] {
        Some(elem) =>
          match elem.binding {
            @ast.TsBinding::Ident("b") => ()
            _ => fail("expected binding b")
          }
        None => fail("expected binding b")
      }
      match arr.rest {
        Some(@ast.TsBinding::Ident("rest")) => ()
        _ => fail("expected rest")
      }
    }
    _ => fail("expected array binding")
  }
  match parse_binding_from("{ a, b: c, ...rest }") {
    @ast.TsBinding::Object(obj) => {
      assert_eq(obj.props.length(), 2)
      match obj.props[0] {
        { key: "a", binding: @ast.TsBinding::Ident("a"), .. } => ()
        _ => fail("expected prop a")
      }
      match obj.props[1] {
        { key: "b", binding: @ast.TsBinding::Ident("c"), .. } => ()
        _ => fail("expected prop b: c")
      }
      match obj.rest {
        Some("rest") => ()
        _ => fail("expected rest")
      }
    }
    _ => fail("expected object binding")
  }
  match parse_assign_binding_from("obj.x") {
    @ast.TsBinding::Target(PropAccess(Var("obj"), "x")) => ()
    _ => fail("expected target binding")
  }
}

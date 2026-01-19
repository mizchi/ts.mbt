// パーサーのテスト

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
  // 1 + (2 * 3) になるはず
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
    Let("x", Number, IntLit(42)) => ()
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse return stmt" {
  let parser = Parser::from_source("return a + b;")
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
    Let("s", String_, StringLit("hello")) => ()
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
  let imp = parser.parse_import()
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
test "parser: parse javascript without type annotations" {
  // 型注釈なしの JavaScript スタイル
  let src =
    #|function add(a, b) {
    #|  return a + b;
    #|}
  let parser = Parser::from_source(src)
  let f = parser.parse_function()
  assert_eq(f.name, "add")
  assert_eq(f.params.length(), 2)
  assert_eq(f.params[0].name, "a")
  assert_eq(f.params[0].type_, Any) // 型注釈なしは Any
  assert_eq(f.params[1].name, "b")
  assert_eq(f.params[1].type_, Any)
  assert_eq(f.return_type, Any) // 戻り値型も Any
}

///|
test "parser: parse let without type annotation" {
  let parser = Parser::from_source("let x = 42;")
  let stmt = parser.parse_stmt()
  match stmt {
    Let("x", Any, IntLit(42)) => ()
    _ => fail("unexpected result: \{stmt}")
  }
}

///|
test "parser: parse mixed typed and untyped" {
  // 一部だけ型付き
  let src =
    #|function mixed(a: number, b) {
    #|  let x = 1;
    #|  let y: int = 2;
    #|  return a + b;
    #|}
  let parser = Parser::from_source(src)
  let f = parser.parse_function()
  assert_eq(f.params[0].type_, Number) // 型あり
  assert_eq(f.params[1].type_, Any) // 型なし
  assert_eq(f.return_type, Any) // 戻り値型なし
}

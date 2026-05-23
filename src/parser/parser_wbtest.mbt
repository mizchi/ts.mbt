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
fn count_occurrences_in_parser_output(
  haystack : String,
  needle : String,
) -> Int {
  let mut count = 0
  for _ in haystack.split(needle) {
    count += 1
  }
  count - 1
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
test "lexer: tokenize slash after type keyword assertion as division" {
  let lexer = Lexer::new("length as any as number / factor")
  let tokens = lexer.tokenize()
  assert_eq(tokens[0].kind, Ident("length"))
  assert_eq(tokens[1].kind, As)
  assert_eq(tokens[2].kind, Ident("any"))
  assert_eq(tokens[3].kind, As)
  assert_eq(tokens[4].kind, NumberType)
  assert_eq(tokens[5].kind, Slash)
  assert_eq(tokens[6].kind, Ident("factor"))
}

///|
test "lexer: tokenize slash after non-null assertion as division" {
  let lexer = Lexer::new("state.width! / 2")
  let tokens = lexer.tokenize()
  assert_eq(tokens[0].kind, Ident("state"))
  assert_eq(tokens[1].kind, Dot)
  assert_eq(tokens[2].kind, Ident("width"))
  assert_eq(tokens[3].kind, Bang)
  assert_eq(tokens[4].kind, Slash)
  assert_eq(tokens[5].kind, Int(2))
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
      Any,
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
    ForAwaitOf(
      @ast.TsForOfKind::Var,
      @ast.TsBinding::Ident("x"),
      Any,
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
      Any,
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
      Any,
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
test "parser: parse union type" {
  let parser = Parser::from_source("string | number")
  let t = parser.parse_type()
  assert_eq(t, Union([String_, Number]))
}

///|
test "parser: parse intersection type" {
  let parser = Parser::from_source("BadgeProps & RefAttributes<Element>")
  let t = parser.parse_type()
  assert_eq(
    t,
    Intersection([
      Named("BadgeProps"),
      Applied("RefAttributes", [Named("Element")]),
    ]),
  )
}

///|
test "parser: parse keyof preserves operand as Keyof(...)" {
  // keyof previously dropped its operand and returned `String_`; it now
  // keeps the operand so the simplifier can resolve it once the base
  // becomes a concrete struct.
  let parser = Parser::from_source("keyof JSX.IntrinsicElements")
  let t = parser.parse_type()
  assert_eq(t, Keyof(Named("JSX.IntrinsicElements")))
}

///|
test "parser: keyof of inline object literal" {
  let parser = Parser::from_source("keyof { a: string; b: number }")
  let t = parser.parse_type()
  assert_eq(t, Keyof(Object([(Literal("a"), String_), (Literal("b"), Number)])))
}

///|
test "parser: lowers statically decidable conditional types" {
  let true_parser = Parser::from_source(
    "string extends string ? number : boolean",
  )
  assert_eq(true_parser.parse_type(), Number)
  let false_parser = Parser::from_source(
    "number extends string ? number : boolean",
  )
  assert_eq(false_parser.parse_type(), Boolean)
}

///|
test "parser: resolves concrete infer conditional types" {
  let parser = Parser::from_source(
    "Promise<string> extends Promise<infer Name> ? Name : never",
  )
  assert_eq(parser.parse_type(), String_)
}

///|
test "parser: preserves generic infer conditional type aliases" {
  let module_ = Parser::from_source(
    "export type UnwrapPromise<T> = T extends Promise<infer Value> ? Value : never;",
  ).parse_module() catch {
    e => fail("expected generic infer conditional alias to parse: \{e}")
  }
  assert_eq(module_.type_aliases.length(), 1)
  assert_eq(module_.type_aliases[0].name, "UnwrapPromise")
  assert_eq(module_.type_aliases[0].type_params, ["T"])
  assert_eq(
    module_.type_aliases[0].type_,
    Conditional(
      Named("T"),
      Applied("Promise", [Applied("__tsmbt_infer", [Named("Value")])]),
      Named("Value"),
      Never,
    ),
  )
}

///|
test "parser: preserves infer extends bound when conditional cannot resolve eagerly" {
  // `T[]` doesn't structurally match `Promise<...>` so the conditional
  // stays in the AST and the inner `infer X extends Date` marker reaches
  // downstream consumers with its bound attached.
  let module_ = Parser::from_source(
    "export type Inner<T> = T[] extends Promise<infer X extends Date>[] ? X : never;",
  ).parse_module() catch {
    e => fail("expected infer-with-bound alias to parse: \{e}")
  }
  assert_eq(module_.type_aliases.length(), 1)
  match module_.type_aliases[0].type_ {
    Conditional(_, target, _, _) =>
      // Walk the target until we find the infer marker.
      match target {
        Array(Applied("Promise", [Applied("__tsmbt_infer", marker_args)])) =>
          assert_eq(marker_args.length(), 2)
        _ =>
          fail("expected target to wrap an infer marker with a bound argument")
      }
    _ => fail("expected conditional alias")
  }
}

///|
test "parser: preserves non-string literal type kinds" {
  let module_ = Parser::from_source(
    "export type LiteralCases = 1 | \"1\" | true | 0n;",
  ).parse_module() catch {
    e => fail("expected literal type alias to parse: \{e}")
  }
  assert_eq(module_.type_aliases.length(), 1)
  assert_eq(module_.type_aliases[0].name, "LiteralCases")
  assert_eq(
    module_.type_aliases[0].type_,
    Union([
      NumberLiteral("1"),
      Literal("1"),
      BooleanLiteral(true),
      BigIntLiteral("0"),
    ]),
  )
}

///|
test "parser: parse literal-key mapped object type as fields" {
  let parser = Parser::from_source("{ [K in \"id\" | \"name\"]?: string }")
  assert_eq(
    parser.parse_type(),
    Object([
      (Literal("id"), Union([String_, Undefined])),
      (Literal("name"), Union([String_, Undefined])),
    ]),
  )
}

///|
test "parser: parse constructor type `new (...) => T`" {
  let parser = Parser::from_source("new (x: string) => Foo")
  assert_eq(
    parser.parse_type(),
    Constructor([String_], Named("Foo"), false),
  )
}

///|
test "parser: parse abstract constructor type" {
  let parser = Parser::from_source("abstract new (x: string) => Foo")
  assert_eq(
    parser.parse_type(),
    Constructor([String_], Named("Foo"), true),
  )
}

///|
test "parser: parse variadic tuple type with rest element" {
  let parser = Parser::from_source("[string, ...number[]]")
  assert_eq(
    parser.parse_type(),
    Tuple([String_, Rest(Array(Number))]),
  )
}

///|
test "parser: parse leading rest variadic tuple" {
  let parser = Parser::from_source("[...string[], number]")
  assert_eq(
    parser.parse_type(),
    Tuple([Rest(Array(String_)), Number]),
  )
}

///|
test "parser: parse labeled tuple drops labels, keeps shape" {
  // Labels are TS-only structural metadata. `[name: string, age: number]`
  // is structurally identical to `[string, number]`.
  let parser = Parser::from_source("[name: string, age: number]")
  assert_eq(parser.parse_type(), Tuple([String_, Number]))
}

///|
test "parser: parse labeled tuple with optional label" {
  let parser = Parser::from_source("[name: string, age?: number]")
  assert_eq(parser.parse_type(), Tuple([String_, Union([Number, Undefined])]))
}

///|
test "parser: parse labeled rest tuple element" {
  let parser = Parser::from_source("[name: string, ...rest: number[]]")
  assert_eq(parser.parse_type(), Tuple([String_, Rest(Array(Number))]))
}

///|
test "parser: parse mapped type with `as` key remap" {
  // Literal-source mapped type with a template-literal remap. After parse
  // we don't simplify, so the variant must survive intact for the checker
  // pass to materialize.
  let parser = Parser::from_source(
    "{ [K in \"a\" | \"b\" as `get${Capitalize<K>}`]: number }",
  )
  let parsed = parser.parse_type()
  match parsed {
    MappedTypeRemap(
      "K",
      Union([Literal("a"), Literal("b")]),
      TemplateLiteralType(_, _),
      Number,
      false
    ) => ()
    other => fail("expected MappedTypeRemap, got \{other}")
  }
}

///|
test "parser: parse mapped type with `as` filtering via never" {
  let parser = Parser::from_source(
    "{ [K in \"a\" | \"b\" | \"c\" as K extends \"b\" ? never : K]: number }",
  )
  let parsed = parser.parse_type()
  match parsed {
    MappedTypeRemap(
      "K",
      Union(_),
      Conditional(_, _, Never, Named("K")),
      Number,
      false
    ) => ()
    other =>
      fail("expected MappedTypeRemap with conditional remap, got \{other}")
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
test "parser: parse interface type parameters" {
  let src =
    #|interface Box<T, U extends string = string> {
    #|  value: T;
    #|  label: U;
    #|}
  let parser = Parser::from_source(src)
  let iface = parser.parse_interface()
  assert_eq(iface.name, "Box")
  assert_eq(iface.type_params, ["T", "U"])
  assert_eq(iface.fields.length(), 2)
  assert_eq(iface.fields[0], ("value", @ast.TsType::Named("T")))
  assert_eq(iface.fields[1], ("label", @ast.TsType::String_))
}

///|
test "parser: substitute generic interface bounds in fields" {
  let src =
    #|interface TransformationResult<T extends Node> {
    #|  transformed: T[];
    #|}
  let parser = Parser::from_source(src)
  let iface = parser.parse_interface()
  assert_eq(iface.name, "TransformationResult")
  assert_eq(iface.type_params, ["T"])
  assert_eq(
    iface.fields[0],
    ("transformed", @ast.TsType::Array(@ast.TsType::Named("Node"))),
  )
}

///|
test "parser: substitute declare function generic bounds in signature" {
  let src = "visitEachChild<T extends Node>(node: T, visitor: Visitor): T;"
  let parser = Parser::from_source(src)
  let import_ = parser.parse_declare_function()
  assert_eq(import_.name, "visitEachChild")
  assert_eq(import_.params[0], ("node", @ast.TsType::Named("Node")))
  assert_eq(import_.return_type, @ast.TsType::Named("Node"))
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
test "parser: parse template literal type" {
  let parser = Parser::from_source("`section-${string}`")
  let t = parser.parse_type()
  match t {
    @ast.TsType::TemplateLiteralType(parts, args) => {
      assert_eq(parts, ["section-", ""])
      assert_eq(args, [@ast.TsType::String_])
    }
    _ => fail("expected TemplateLiteralType, got \{t}")
  }
}

///|
test "parser: parse interface method with template literal return type" {
  let src =
    #|interface Crypto {
    #|  randomUUID(): `${string}-${string}-${string}-${string}-${string}`;
    #|}
  let parser = Parser::from_source(src)
  let iface = parser.parse_interface()
  assert_eq(iface.name, "Crypto")
  assert_eq(iface.fields.length(), 1)
  let (name, type_) = iface.fields[0]
  assert_eq(name, "randomUUID")
  match type_ {
    @ast.TsType::Func(params, @ast.TsType::TemplateLiteralType(_, _)) =>
      assert_eq(params.length(), 0)
    _ => fail("expected Func returning template literal, got \{type_}")
  }
}

///|
test "parser: parse interface method signature as function field" {
  let src =
    #|interface Printer {
    #|  printFile(sourceFile: SourceFile): string;
    #|  printNode(hint: EmitHint, node: Node, sourceFile?: SourceFile): string;
    #|}
  let iface = Parser::from_source(src).parse_interface() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(iface.name, "Printer")
  assert_eq(iface.fields.length(), 2)
  assert_eq(
    iface.fields[0],
    (
      "printFile",
      @ast.TsType::Func([@ast.TsType::Named("SourceFile")], String_),
    ),
  )
  assert_eq(
    iface.fields[1],
    (
      "printNode",
      @ast.TsType::Func(
        [
          @ast.TsType::Named("EmitHint"),
          @ast.TsType::Named("Node"),
          @ast.TsType::Union([
            @ast.TsType::Named("SourceFile"),
            @ast.TsType::Undefined,
          ]),
        ],
        String_,
      ),
    ),
  )
}

///|
test "parser: emit MoonBit declarations caps function field method helpers" {
  let mut src = "export interface LargeApi {\n"
  for i in 0..<(moonbit_function_field_method_wrapper_limit + 1) {
    src += "  call\{i}(): void;\n"
  }
  src += "}"
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected LargeApi interface to parse: \{e}")
  }
  let actual = emit_moonbit_decl(module_)
  assert_true(
    actual.contains(
      "/// call\{moonbit_function_field_method_wrapper_limit} : () -> Unit",
    ),
  )
  assert_eq(
    count_occurrences_in_parser_output(actual, "declare pub fn LargeApi::call"),
    moonbit_function_field_method_wrapper_limit,
  )
  assert_false(
    actual.contains(
      "declare pub fn LargeApi::call\{moonbit_function_field_method_wrapper_limit}(",
    ),
  )
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
test "parser: parse export declare function in module" {
  let parser = Parser::from_source(
    "export declare function draw(point: number): void;",
  )
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.imports.length(), 1)
  assert_eq(module_.imports[0].name, "draw")
  assert_eq(module_.imports[0].params.length(), 1)
}

///|
test "parser: parse declare const in module" {
  let parser = Parser::from_source(
    "declare const version: string; declare let count: number;",
  )
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 2)
  assert_eq(module_.values[0].name, "version")
  assert_eq(module_.values[0].type_, String_)
  assert_eq(module_.values[1].name, "count")
  assert_eq(module_.values[1].type_, Number)
}

///|
test "parser: parse module block export metadata for interface and declare function" {
  let src =
    #|export interface Point {
    #|  x: number;
    #|}
    #|
    #|export declare function draw(point: Point): void;
  let module_ = parse_module_block_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.exports.length(), 2)
  assert_eq(module_.exports[0].local_name, "Point")
  assert_eq(module_.exports[0].export_name, "Point")
  assert_eq(module_.exports[1].local_name, "draw")
  assert_eq(module_.exports[1].export_name, "draw")
}

///|
test "parser: parse module block export metadata for declare const" {
  let src =
    #|declare const localVersion: string;
    #|export { localVersion as version };
    #|export declare const buildNumber: number;
  let module_ = parse_module_block_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.exports.length(), 2)
  assert_eq(module_.exports[0].local_name, "localVersion")
  assert_eq(module_.exports[0].export_name, "version")
  assert_eq(module_.exports[1].local_name, "buildNumber")
  assert_eq(module_.exports[1].export_name, "buildNumber")
}

///|
test "parser: parse import equals require in module block" {
  let src = "import semver = require(\"pkg-types\");"
  let module_ = parse_module_block_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.imports.length(), 1)
  assert_eq(module_.imports[0].module_spec, "pkg-types")
  assert_eq(module_.imports[0].namespace_binding, Some("semver"))
}

///|
test "parser: parse export assignment in module block" {
  let src = "declare namespace semver { const version: string; } export = semver;"
  let module_ = parse_module_block_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.exports.length(), 1)
  assert_eq(module_.exports[0].local_name, "semver")
  assert_eq(module_.exports[0].export_name, "default")
}

///|
test "parser: parse export as namespace in module block" {
  let src = "declare namespace ReactLike { function createContext<T>(defaultValue: T): Context<T>; interface Context<T> { value: T; } } export = ReactLike; export as namespace ReactLike;"
  let module_ = parse_module_block_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.exports.length(), 1)
  assert_eq(module_.exports[0].local_name, "ReactLike")
  assert_eq(module_.exports[0].export_name, "default")
}

///|
test "parser: parse export type star in module block" {
  let src = "export type * from \"./types\";"
  let module_ = parse_module_block_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.exports.length(), 0)
  assert_eq(module_.reexports.length(), 1)
  assert_eq(module_.reexports[0].module_spec, "./types")
  match module_.reexports[0].kind {
    All => ()
    _ => fail("expected type star re-export metadata")
  }
}

///|
test "parser: parse namespace members in module" {
  let src = "declare namespace ReactLike { function createContext<T>(defaultValue: T): Context<T>; interface Context<T> { value: T; } } export = ReactLike; export as namespace ReactLike;"
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.namespaces.length(), 1)
  let namespace_ = module_.namespaces[0]
  assert_eq(namespace_.name, "ReactLike")
  assert_eq(namespace_.module_.funcs.length(), 1)
  assert_eq(namespace_.module_.funcs[0].name, "createContext")
  assert_eq(namespace_.module_.interfaces.length(), 1)
  assert_eq(namespace_.module_.interfaces[0].name, "Context")
}

///|
test "parser: parse ambient const and class inside namespace members in module" {
  let src =
    #|declare namespace ReactLike {
    #|  const version: string;
    #|  interface Context<T> { value: T; }
    #|  class Component<P, S> {
    #|    props: P;
    #|    state: S;
    #|  }
    #|  function useContext<T>(context: Context<T>): T;
    #|}
    #|export = ReactLike;
    #|export as namespace ReactLike;
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.namespaces.length(), 1)
  let namespace_ = module_.namespaces[0]
  assert_eq(namespace_.module_.values.length(), 1)
  assert_eq(namespace_.module_.values[0].name, "version")
  assert_eq(namespace_.module_.classes.length(), 1)
  assert_eq(namespace_.module_.classes[0].name, "Component")
  assert_eq(namespace_.module_.funcs.length(), 1)
  assert_eq(namespace_.module_.funcs[0].name, "useContext")
}

///|
test "parser: parse JSX constructor signatures with trailing comma inside namespace members in module" {
  let src =
    #|declare namespace ReactLike {
    #|  type JSXElementConstructor<P> =
    #|    | ((
    #|        props: P,
    #|      ) => ReactNode | Promise<ReactNode>)
    #|    | (new(props: P, context: any) => Component<any, any>);
    #|}
    #|export = ReactLike;
    #|export as namespace ReactLike;
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.namespaces.length(), 1)
  assert_eq(module_.namespaces[0].name, "ReactLike")
}

///|
test "parser: parse conditional utility signatures inside namespace members in module" {
  let src =
    #|declare namespace ReactLike {
    #|  type ComponentRef<T extends ElementType> =
    #|    ComponentPropsWithRef<T> extends RefAttributes<infer Method> ? Method
    #|    : never;
    #|
    #|  type LibraryManagedAttributes<C, P> = C extends
    #|    ReactLike.MemoExoticComponent<infer T> | ReactLike.LazyExoticComponent<
    #|      infer T
    #|    >
    #|      ? T extends
    #|          ReactLike.MemoExoticComponent<infer U> | ReactLike.LazyExoticComponent<
    #|            infer U
    #|          >
    #|          ? ReactManagedAttributes<U, P>
    #|          : ReactManagedAttributes<T, P>
    #|      : ReactManagedAttributes<C, P>;
    #|}
    #|export = ReactLike;
    #|export as namespace ReactLike;
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.namespaces.length(), 1)
  assert_eq(module_.namespaces[0].name, "ReactLike")
}

///|
test "parser: parse tuple return hook signatures inside namespace members in module" {
  let src =
    #|declare namespace ReactLike {
    #|  type Dispatch<A> = (value: A) => void;
    #|  type ActionDispatch<A> = (action: A) => void;
    #|  type TransitionFunction = () => void;
    #|  function useState<S>(initialState: S): [S, Dispatch<S>];
    #|  function useReducer<S, A>(
    #|    reducer: (prevState: S, action: A) => S,
    #|    initialState: S
    #|  ): [S, ActionDispatch<A>];
    #|  function useTransition(): [boolean, TransitionFunction];
    #|  function useOptimistic<State>(
    #|    passthrough: State
    #|  ): [State, (action: State) => void];
    #|  function useActionState<State>(
    #|    action: (state: State) => State | Promise<State>,
    #|    initialState: State,
    #|    permalink?: string
    #|  ): [State, () => void, boolean];
    #|}
    #|export = ReactLike;
    #|export as namespace ReactLike;
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.namespaces.length(), 1)
  let namespace_ = module_.namespaces[0]
  assert_eq(namespace_.module_.funcs.length(), 5)
  assert_eq(namespace_.module_.funcs[0].name, "useState")
  assert_eq(
    namespace_.module_.funcs[0].return_type,
    @ast.TsType::Tuple([
      @ast.TsType::Named("S"),
      @ast.TsType::Applied("Dispatch", [@ast.TsType::Named("S")]),
    ]),
  )
  assert_eq(namespace_.module_.funcs[1].name, "useReducer")
  assert_eq(
    namespace_.module_.funcs[1].return_type,
    @ast.TsType::Tuple([
      @ast.TsType::Named("S"),
      @ast.TsType::Applied("ActionDispatch", [@ast.TsType::Named("A")]),
    ]),
  )
  assert_eq(namespace_.module_.funcs[2].name, "useTransition")
  assert_eq(
    namespace_.module_.funcs[2].return_type,
    @ast.TsType::Tuple([
      @ast.TsType::Boolean,
      @ast.TsType::Named("TransitionFunction"),
    ]),
  )
  assert_eq(namespace_.module_.funcs[3].name, "useOptimistic")
  assert_eq(
    namespace_.module_.funcs[3].return_type,
    @ast.TsType::Tuple([
      @ast.TsType::Named("State"),
      @ast.TsType::Func([@ast.TsType::Named("State")], @ast.TsType::Void),
    ]),
  )
  assert_eq(namespace_.module_.funcs[4].name, "useActionState")
  assert_eq(
    namespace_.module_.funcs[4].return_type,
    @ast.TsType::Tuple([
      @ast.TsType::Named("State"),
      @ast.TsType::Func([], @ast.TsType::Void),
      @ast.TsType::Boolean,
    ]),
  )
}

///|
test "parser: parse nested namespace members inside export-as-namespace module" {
  let src =
    #|declare namespace ReactLike {
    #|  namespace JSX {
    #|    interface Element { kind: string; }
    #|    interface IntrinsicElements { badge: BadgeProps; }
    #|  }
    #|  interface BadgeProps { label: string; }
    #|  function createElement(tag: keyof JSX.IntrinsicElements): JSX.Element;
    #|}
    #|export = ReactLike;
    #|export as namespace ReactLike;
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.namespaces.length(), 1)
  let namespace_ = module_.namespaces[0]
  assert_eq(namespace_.module_.namespaces.length(), 1)
  let jsx_namespace = namespace_.module_.namespaces[0]
  assert_eq(jsx_namespace.name, "JSX")
  assert_eq(jsx_namespace.module_.interfaces.length(), 2)
  assert_eq(jsx_namespace.module_.interfaces[0].name, "Element")
  assert_eq(jsx_namespace.module_.interfaces[1].name, "IntrinsicElements")
  assert_eq(namespace_.module_.funcs.length(), 1)
  assert_eq(
    namespace_.module_.funcs[0].return_type,
    @ast.TsType::Named("JSX.Element"),
  )
}

///|
test "parser: parse generic type application inside export-as-namespace module" {
  let src =
    #|declare namespace ReactLike {
    #|  type ReactNode = string | number;
    #|  type PropsWithChildren<P> = P & { children?: ReactNode | undefined };
    #|  interface BadgeProps { label: string; }
    #|  function createBadge(
    #|    props: PropsWithChildren<BadgeProps>
    #|  ): PropsWithChildren<BadgeProps>;
    #|}
    #|export = ReactLike;
    #|export as namespace ReactLike;
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.namespaces.length(), 1)
  let namespace_ = module_.namespaces[0]
  assert_eq(namespace_.module_.funcs.length(), 1)
  assert_eq(
    namespace_.module_.funcs[0].params[0].type_,
    @ast.TsType::Applied("PropsWithChildren", [@ast.TsType::Named("BadgeProps")]),
  )
  assert_eq(
    namespace_.module_.funcs[0].return_type,
    @ast.TsType::Applied("PropsWithChildren", [@ast.TsType::Named("BadgeProps")]),
  )
}

///|
test "parser: parse ComponentProps literal application inside export-as-namespace module" {
  let src =
    #|declare namespace ReactLike {
    #|  namespace JSX {
    #|    interface IntrinsicElements {
    #|      badge: BadgeProps;
    #|    }
    #|  }
    #|  interface BadgeProps { label: string; }
    #|  type ComponentProps<T extends keyof JSX.IntrinsicElements> =
    #|    JSX.IntrinsicElements[T];
    #|  function createBadge(
    #|    props: ComponentProps<"badge">
    #|  ): ComponentProps<"badge">;
    #|}
    #|export = ReactLike;
    #|export as namespace ReactLike;
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.namespaces.length(), 1)
  let namespace_ = module_.namespaces[0]
  assert_eq(
    namespace_.module_.funcs[0].params[0].type_,
    @ast.TsType::Applied("ComponentProps", [@ast.TsType::Literal("badge")]),
  )
  assert_eq(
    namespace_.module_.funcs[0].return_type,
    @ast.TsType::Applied("ComponentProps", [@ast.TsType::Literal("badge")]),
  )
}

///|
test "parser: parse ComponentPropsWithoutRef literal application inside export-as-namespace module" {
  let src =
    #|declare namespace ReactLike {
    #|  namespace JSX {
    #|    interface IntrinsicElements {
    #|      badge: BadgeProps;
    #|    }
    #|  }
    #|  interface BadgeProps { label: string; }
    #|  type ComponentPropsWithoutRef<T extends keyof JSX.IntrinsicElements> =
    #|    JSX.IntrinsicElements[T];
    #|  function createBadge(
    #|    props: ComponentPropsWithoutRef<"badge">
    #|  ): ComponentPropsWithoutRef<"badge">;
    #|}
    #|export = ReactLike;
    #|export as namespace ReactLike;
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.namespaces.length(), 1)
  let namespace_ = module_.namespaces[0]
  assert_eq(
    namespace_.module_.funcs[0].params[0].type_,
    @ast.TsType::Applied("ComponentPropsWithoutRef", [
      @ast.TsType::Literal("badge"),
    ]),
  )
  assert_eq(
    namespace_.module_.funcs[0].return_type,
    @ast.TsType::Applied("ComponentPropsWithoutRef", [
      @ast.TsType::Literal("badge"),
    ]),
  )
}

///|
test "parser: parse ComponentPropsWithRef literal application inside export-as-namespace module" {
  let src =
    #|declare namespace ReactLike {
    #|  namespace JSX {
    #|    interface IntrinsicElements {
    #|      badge: BadgeProps;
    #|    }
    #|  }
    #|  interface BadgeProps { label: string; }
    #|  interface Ref<T> { current: T; }
    #|  interface RefAttributes<T> { ref: Ref<T>; }
    #|  type ComponentPropsWithRef<T extends keyof JSX.IntrinsicElements> =
    #|    JSX.IntrinsicElements[T] & RefAttributes<BadgeProps>;
    #|  function createBadge(
    #|    props: ComponentPropsWithRef<"badge">
    #|  ): ComponentPropsWithRef<"badge">;
    #|}
    #|export = ReactLike;
    #|export as namespace ReactLike;
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.namespaces.length(), 1)
  let namespace_ = module_.namespaces[0]
  assert_eq(
    namespace_.module_.funcs[0].params[0].type_,
    @ast.TsType::Applied("ComponentPropsWithRef", [
      @ast.TsType::Literal("badge"),
    ]),
  )
  assert_eq(
    namespace_.module_.funcs[0].return_type,
    @ast.TsType::Applied("ComponentPropsWithRef", [
      @ast.TsType::Literal("badge"),
    ]),
  )
}

///|
test "parser: parse nested PropsWithChildren application inside export-as-namespace module" {
  let src =
    #|declare namespace ReactLike {
    #|  namespace JSX {
    #|    interface IntrinsicElements {
    #|      badge: BadgeProps;
    #|    }
    #|  }
    #|  type ReactNode = string | number;
    #|  interface BadgeProps { label: string; }
    #|  type ComponentPropsWithoutRef<T extends keyof JSX.IntrinsicElements> =
    #|    JSX.IntrinsicElements[T];
    #|  type PropsWithChildren<P> = P & { children?: ReactNode | undefined };
    #|  function createBadge(
    #|    props: PropsWithChildren<ComponentPropsWithoutRef<"badge">>
    #|  ): PropsWithChildren<ComponentPropsWithoutRef<"badge">>;
    #|}
    #|export = ReactLike;
    #|export as namespace ReactLike;
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.namespaces.length(), 1)
  let namespace_ = module_.namespaces[0]
  let expected = @ast.TsType::Applied("PropsWithChildren", [
    @ast.TsType::Applied("ComponentPropsWithoutRef", [
      @ast.TsType::Literal("badge"),
    ]),
  ])
  assert_eq(namespace_.module_.funcs[0].params[0].type_, expected)
  assert_eq(namespace_.module_.funcs[0].return_type, expected)
}

///|
test "parser: parse PropsWithoutRef and PropsWithRef applications inside export-as-namespace module" {
  let src =
    #|declare namespace ReactLike {
    #|  type ReactNode = string | number;
    #|  interface BadgeProps { label: string; }
    #|  type PropsWithChildren<P> = P & { children?: ReactNode | undefined };
    #|  type PropsWithoutRef<Props> = Props;
    #|  type PropsWithRef<Props> = Props;
    #|  function stripRef(
    #|    props: PropsWithoutRef<BadgeProps>
    #|  ): PropsWithoutRef<BadgeProps>;
    #|  function keepRef(
    #|    props: PropsWithRef<BadgeProps>
    #|  ): PropsWithRef<BadgeProps>;
    #|  function nested(
    #|    props: PropsWithoutRef<PropsWithChildren<BadgeProps>>
    #|  ): PropsWithoutRef<PropsWithChildren<BadgeProps>>;
    #|}
    #|export = ReactLike;
    #|export as namespace ReactLike;
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let namespace_ = module_.namespaces[0]
  assert_eq(
    namespace_.module_.funcs[0].params[0].type_,
    @ast.TsType::Applied("PropsWithoutRef", [@ast.TsType::Named("BadgeProps")]),
  )
  assert_eq(
    namespace_.module_.funcs[1].params[0].type_,
    @ast.TsType::Applied("PropsWithRef", [@ast.TsType::Named("BadgeProps")]),
  )
  assert_eq(
    namespace_.module_.funcs[2].params[0].type_,
    @ast.TsType::Applied("PropsWithoutRef", [
      @ast.TsType::Applied("PropsWithChildren", [
        @ast.TsType::Named("BadgeProps"),
      ]),
    ]),
  )
}

///|
test "parser: parse inline object PropsWithChildren application inside export-as-namespace module" {
  let src =
    #|declare namespace ReactLike {
    #|  type ReactNode = string | number;
    #|  type PropsWithChildren<P> = P & { children?: ReactNode | undefined };
    #|  function createBadge(
    #|    props: PropsWithChildren<{ label: string; count: number }>
    #|  ): PropsWithChildren<{ label: string; count: number }>;
    #|}
    #|export = ReactLike;
    #|export as namespace ReactLike;
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.namespaces.length(), 1)
  let namespace_ = module_.namespaces[0]
  let inline_props = @ast.TsType::Object([
    (@ast.TsType::Literal("label"), @ast.TsType::String_),
    (@ast.TsType::Literal("count"), @ast.TsType::Number),
  ])
  assert_eq(
    namespace_.module_.funcs[0].params[0].type_,
    @ast.TsType::Applied("PropsWithChildren", [inline_props]),
  )
  assert_eq(
    namespace_.module_.funcs[0].return_type,
    @ast.TsType::Applied("PropsWithChildren", [inline_props]),
  )
}

///|
test "parser: parse semicolonless export type reexport without swallowing following exports" {
  let src =
    #|import { RuntimeImported } from "./runtime-import-reexport-class-source.ts"
    #|
    #|export type { RuntimeImportedOptions } from "./runtime-import-reexport-class-source.ts"
    #|export { RuntimeImported }
  let module_ = parse_module_block_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.exports.length(), 1)
  assert_eq(module_.exports[0].local_name, "RuntimeImported")
  assert_eq(module_.exports[0].export_name, "RuntimeImported")
}

///|
test "parser: parse semicolonless export type alias without swallowing following exports" {
  let src =
    #|export type Name = string
    #|export function greet(name: Name): Name {
    #|  return name
    #|}
  let module_ = parse_module_block_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.exports.length(), 2)
  assert_eq(module_.exports[0].local_name, "Name")
  assert_eq(module_.exports[0].export_name, "Name")
  assert_eq(module_.exports[1].local_name, "greet")
  assert_eq(module_.exports[1].export_name, "greet")
}

///|
test "parser: parse semicolonless export type alias in full module" {
  let src =
    #|export type Name = string
    #|export function greet(name: Name): Name {
    #|  return name
    #|}
  let module_ = parse_module_from_source_with_const_values(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.funcs.length(), 1)
  assert_eq(module_.funcs[0].name, "greet")
}

///|
test "parser: parse declare class in module" {
  let src =
    #|declare class Counter {
    #|  constructor(initial: number);
    #|  inc(delta: number): number;
    #|  value(): number;
    #|  static from(seed: number): Counter;
    #|}
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.classes.length(), 1)
  let class_ = module_.classes[0]
  assert_eq(class_.name, "Counter")
  assert_false(class_.is_abstract)
  match class_.constructor_params {
    Some(params) => assert_eq(params.length(), 1)
    None => fail("expected constructor params")
  }
  assert_eq(class_.methods.length(), 3)
  assert_eq(class_.methods[0].name, "inc")
  assert_false(class_.methods[0].is_static)
  assert_eq(class_.methods[1].name, "value")
  assert_eq(class_.methods[2].name, "from")
  assert_true(class_.methods[2].is_static)
}

///|
test "parser: substitute declare class method generic bounds" {
  let src =
    #|interface Events {
    #|  close: [];
    #|}
    #|declare class Stream {
    #|  on<E extends keyof Events>(eventName: E): void;
    #|}
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.classes.length(), 1)
  let method_ = module_.classes[0].methods[0]
  // `E extends keyof Events` substitutes `E` with the bound; the simplifier
  // (run later, with module-level resolution) reduces it to a literal-key
  // union once `Events` is known.
  assert_eq(method_.params[0].1, Keyof(Named("Events")))
}

///|
test "parser: parse declare namespace in module as value declaration" {
  let parser = Parser::from_source(
    "declare namespace semver { const version: string; } export = semver;",
  )
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 1)
  assert_eq(module_.values[0].name, "semver")
  assert_eq(module_.values[0].type_, Any)
}

///|
test "parser: parse module block export metadata for declare class" {
  let src =
    #|export declare class Counter {
    #|  constructor(initial: number);
    #|  inc(delta: number): number;
    #|}
  let module_ = parse_module_block_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.exports.length(), 1)
  assert_eq(module_.exports[0].local_name, "Counter")
  assert_eq(module_.exports[0].export_name, "Counter")
}

///|
test "parser: parse export type alias metadata in module block" {
  let src =
    #|export type Status = "ok" | "err";
    #|export interface User {
    #|  name: string;
    #|}
  let module_ = parse_module_block_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.exports.length(), 2)
  assert_eq(module_.exports[0].local_name, "Status")
  assert_eq(module_.exports[0].export_name, "Status")
  assert_eq(module_.exports[1].local_name, "User")
  assert_eq(module_.exports[1].export_name, "User")
}

///|
test "parser: parse export object type alias in module block as interface" {
  let src =
    #|export type HonoOptions<E> = {
    #|  strict?: boolean | undefined
    #|  bindings?: E | undefined
    #|}
    #|export class Hono<E> {
    #|  constructor(options?: HonoOptions<E>);
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_true(
    module_.interfaces.iter().any(fn(iface) { iface.name == "HonoOptions" }),
  )
  let mut found = false
  for iface in module_.interfaces {
    if iface.name == "HonoOptions" {
      found = true
      assert_eq(iface.fields.length(), 2)
      assert_eq(iface.fields[0].0, "strict")
      assert_eq(iface.fields[1].0, "bindings")
      break
    }
  }
  assert_true(found)
}

///|
test "parser: parse abstract declare class in module" {
  let src =
    #|declare abstract class Shape {
    #|  area(): number;
    #|}
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.classes.length(), 1)
  let class_ = module_.classes[0]
  assert_true(class_.is_abstract)
  assert_false(class_.is_constructible)
}

///|
test "parser: parse declare class properties in module" {
  let src =
    #|declare class CounterState {
    #|  readonly current: number;
    #|  label: string;
    #|  static readonly version: string;
    #|  static step: number;
    #|}
  let parser = Parser::from_source(src)
  let module_ = parser.parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.classes.length(), 1)
  let class_ = module_.classes[0]
  assert_eq(class_.properties.length(), 4)
  assert_eq(class_.properties[0].name, "current")
  assert_true(class_.properties[0].is_readonly)
  assert_false(class_.properties[0].is_static)
  assert_eq(class_.properties[1].name, "label")
  assert_false(class_.properties[1].is_readonly)
  assert_eq(class_.properties[2].name, "version")
  assert_true(class_.properties[2].is_static)
  assert_true(class_.properties[2].is_readonly)
  assert_eq(class_.properties[3].name, "step")
  assert_true(class_.properties[3].is_static)
  assert_false(class_.properties[3].is_readonly)
}

///|
test "parser: parse qualified ambient type references in module" {
  let src =
    #|export interface RuntimeConfig {
    #|  env: NodeJS.ProcessEnv;
    #|  cwd: string;
    #|}
    #|export declare class NodeRunner {
    #|  readonly env: NodeJS.ProcessEnv;
    #|  cwd: string;
    #|  constructor(env: NodeJS.ProcessEnv);
    #|}
    #|export declare function hasEnv(env: NodeJS.ProcessEnv, key: string): boolean;
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.interfaces.length(), 1)
  assert_eq(module_.interfaces[0].fields[0].1, Named("NodeJS.ProcessEnv"))
  assert_eq(module_.classes.length(), 1)
  assert_eq(module_.classes[0].properties[0].type_, Named("NodeJS.ProcessEnv"))
  match module_.classes[0].constructor_params {
    Some(params) => assert_eq(params[0].1, Named("NodeJS.ProcessEnv"))
    None => fail("expected constructor params")
  }
  assert_eq(module_.imports.length(), 1)
  assert_eq(module_.imports[0].params[0].1, Named("NodeJS.ProcessEnv"))
}

///|
test "parser: parse named imports with inline type modifier" {
  let src =
    #|import { ResultAsync, type Result } from "neverthrow";
    #|export declare function parseUser(input: string): Result<string, Error>;
  let module_ = parse_module_block_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.imports.length(), 1)
  let import_decl = module_.imports[0]
  assert_eq(import_decl.module_spec, "neverthrow")
  assert_eq(import_decl.named_bindings.length(), 2)
  assert_eq(import_decl.named_bindings[0], ("ResultAsync", "ResultAsync"))
  assert_eq(import_decl.named_bindings[1], ("Result", "Result"))
}

///|
test "parser: parse local interface declaration inside function block" {
  let src =
    #|function analyze(): number {
    #|  interface PackageResult {
    #|    file: string;
    #|  }
    #|  return 1;
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.funcs.length(), 1)
  let body = module_.funcs[0].body
  assert_eq(body.stmts.length(), 2)
}

///|
test "parser: interface field name can be a fractional number" {
  // `interface I { 1.0: T; }` — the lexer emits `Number(1.0)` for the key.
  // Previously only `Int(n)` was accepted, raising "Expected field name".
  let src = "interface I { 1.0: number; 2: string; }"
  match (try? Parser::from_source(src).parse_module()) {
    Ok(_) => ()
    Err(e) => fail("parse error: \{e}")
  }
}

///|
test "parser: class can `extends null`" {
  let src = "class C extends null { x = 1; }"
  match (try? Parser::from_source(src).parse_module()) {
    Ok(_) => ()
    Err(e) => fail("parse error: \{e}")
  }
}

///|
test "parser: `using` declaration parses as a let binding" {
  // ES2023 `using x = expr;` — auto-disposal binding. Treated as `let`
  // for parser / checker purposes; the runtime semantics don't change
  // the type-level shape.
  let src =
    #|function f() {
    #|  using d1 = { [Symbol.dispose]() {} };
    #|  using d2 = null;
    #|}
  match (try? Parser::from_source(src).parse_module()) {
    Ok(_) => ()
    Err(e) => fail("parse error: \{e}")
  }
}

///|
test "parser: `await using` declaration parses as a let binding" {
  let src =
    #|async function f() {
    #|  await using d1 = { [Symbol.asyncDispose]() {} };
    #|}
  match (try? Parser::from_source(src).parse_module()) {
    Ok(_) => ()
    Err(e) => fail("parse error: \{e}")
  }
}

///|
test "parser: `for (using x of arr)` parses as a for-of loop" {
  let src =
    #|function f() {
    #|  for (using d of [null, undefined]) { /* body */ }
    #|}
  match (try? Parser::from_source(src).parse_module()) {
    Ok(_) => ()
    Err(e) => fail("parse error: \{e}")
  }
}

///|
test "parser: nested anonymous class expression as base" {
  // `let C = class extends class extends class { a = 1 } { b = 2 } { c = 3 };`
  let src = "let C = class extends class extends class { a = 1 } { b = 2 } { c = 3 };"
  match (try? Parser::from_source(src).parse_module()) {
    Ok(_) => ()
    Err(e) => fail("parse error: \{e}")
  }
}

///|
test "parser: class extends with optional chain in base name" {
  // `class C extends A?.B { ... }` — the heritage clause uses optional
  // chaining; `parse_class_base_name` falls through to the expression-
  // based parser when it sees `?.`.
  let src =
    #|namespace A { export class B {} }
    #|class C extends A?.B {}
  match (try? Parser::from_source(src).parse_module()) {
    Ok(_) => ()
    Err(e) => fail("parse error: \{e}")
  }
}

///|
test "parser: super assignment / super.method() inside static initializer" {
  let src =
    #|class B {
    #|  static a: any;
    #|}
    #|class C extends B {
    #|  static y1 = this.x;
    #|  static z1 = super.a;
    #|  static z3 = super.f();
    #|  static z5 = super.a = 0;
    #|  static z6 = super.a += 1;
    #|}
  match (try? Parser::from_source(src).parse_module()) {
    Ok(_) => ()
    Err(e) => fail("parse error: \{e}")
  }
}

///|
test "parser: `using` followed by newline is still a reference" {
  // ES2023 ASI rule: a line terminator between `using` and the binding
  // makes this NOT a using declaration — `using` is a free reference.
  let src =
    #|function f() {
    #|  using
    #|  x;
    #|}
  match (try? Parser::from_source(src).parse_module()) {
    Ok(_) => ()
    Err(e) => fail("parse error: \{e}")
  }
}

///|
test "parser: object literal as destructuring-assignment LHS in static field" {
  // `{ ...super.a } = { x: 0 }` — the LHS is an object literal that's
  // re-interpreted as a destructuring assignment target. Our binding
  // pattern parser doesn't accept complex spread targets, so the
  // assignment falls through to a generic `AssignPattern` with a
  // `Target(...)` binding.
  let src =
    #|class B { static a: any; }
    #|class C extends B {
    #|    static z13 = { ...super.a } = { x: 0 };
    #|}
  match (try? Parser::from_source(src).parse_module()) {
    Ok(_) => ()
    Err(e) => fail("parse error: \{e}")
  }
}

///|
test "parser: array literal as destructuring-assignment LHS" {
  // `[a, b] = arr` outside of a destructuring-friendly slot — falls
  // through to the same generic `AssignPattern(Target(...))` path.
  let src =
    #|function f(): void {
    #|  let z;
    #|  z = [super.a] = [0];
    #|}
  // We don't care about super in a function context; parse only checks
  // the structural shape.
  match (try? Parser::from_source(src).parse_module()) {
    Ok(_) => ()
    Err(e) => fail("parse error: \{e}")
  }
}

///|
test "parser: parse interface call-signature with type predicate return" {
  let src = "interface I1 { (p1: A): p1 is C; }"
  match (try? Parser::from_source(src).parse_module()) {
    Ok(_) => ()
    Err(e) => fail("parse error: \{e}")
  }
}

///|
test "parser: declare function tolerates missing return type" {
  // `declare function f();` — TS treats the missing return type as
  // implicit `void`; we parse it as `Any` so the checker can fall
  // through gracefully.
  let src = "declare function acceptingBoolean(a: boolean);"
  match (try? Parser::from_source(src).parse_module()) {
    Ok(_) => ()
    Err(e) => fail("parse error: \{e}")
  }
}

///|
test "parser: arrow function type with untyped parameter" {
  // `(item) => item is A` — function-type parameter without annotation.
  // The parser previously chose the parenthesized-type fallback, leaving
  // the trailing `=>` dangling. Now it treats the missing colon as `Any`.
  let src = "declare function f(g: (item) => item is A);"
  match (try? Parser::from_source(src).parse_module()) {
    Ok(_) => ()
    Err(e) => fail("parse error: \{e}")
  }
}

///|
test "parser: ASI before `else` keyword" {
  // `if (cond) return -1\nelse ...` — `else` isn't a statement-starting
  // token, but the line terminator after `-1` should still trigger ASI.
  let src =
    #|function g(): number {
    #|  if (!true)
    #|    return -1
    #|  else
    #|    return 0
    #|}
  match (try? Parser::from_source(src).parse_module()) {
    Ok(_) => ()
    Err(e) => fail("parse error: \{e}")
  }
}

///|
test "parser: parse class type predicate methods as type predicates" {
  let src =
    #|declare class Ok<T, E> {
    #|  isOk(): this is Ok<T, E>;
    #|  isErr(): this is Err<T, E>;
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.classes.length(), 1)
  let class_ = module_.classes[0]
  assert_eq(class_.methods.length(), 2)
  // Type predicates `this is T` survive into `TypePredicate("this", T)`.
  match class_.methods[0].return_type {
    TypePredicate("this", Applied("Ok", _)) => ()
    other => fail("expected isOk to return `this is Ok<T, E>`, got \{other}")
  }
  match class_.methods[1].return_type {
    TypePredicate("this", Applied("Err", _)) => ()
    other => fail("expected isErr to return `this is Err<T, E>`, got \{other}")
  }
}

///|
test "parser: parse asserts predicate functions" {
  let src =
    #|export declare function assertString(value: unknown): asserts value is string;
    #|export declare function assertOk(value: unknown): asserts value;
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.imports.length(), 2)
  // `asserts value is string` — typed assertion.
  match module_.imports[0].return_type {
    AssertsPredicate("value", Some(String_)) => ()
    other =>
      fail("expected `asserts value is string`, got \{other}")
  }
  // `asserts value` — truthy assertion, no type payload.
  match module_.imports[1].return_type {
    AssertsPredicate("value", None) => ()
    other => fail("expected `asserts value`, got \{other}")
  }
}

///|
test "parser: retain class-level decorators in TsClassDecl" {
  let src =
    #|@Injectable()
    #|@deco.factory(arg)
    #|export declare class UserService {
    #|  find(id: number): string;
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.classes.length(), 1)
  let cls = module_.classes[0]
  assert_eq(cls.name, "UserService")
  assert_eq(cls.decorators.length(), 2)
  match cls.decorators[0] {
    CallExpr(Var("Injectable"), _) => ()
    other => fail("expected `@Injectable()`, got \{other}")
  }
  match cls.decorators[1] {
    CallExpr(PropAccess(Var("deco"), "factory"), args) =>
      assert_eq(args.length(), 1)
    other => fail("expected `@deco.factory(arg)`, got \{other}")
  }
}

///|
test "parser: parse dynamic import with options retains the second arg" {
  // `import("./data.json", { with: { type: "json" } })` should parse
  // with both arguments captured.
  let parser = Parser::from_source(
    #|import("./data.json", { with: { type: "json" } })
    ,
  )
  let expr = parser.parse_expr()
  match expr {
    DynamicImport(StringLit("./data.json"), Some(_)) => ()
    other => fail("expected dynamic import with options, got \{other}")
  }
}

///|
test "parser: parse dynamic import without options keeps slot empty" {
  let parser = Parser::from_source("import(\"./mod\")")
  let expr = parser.parse_expr()
  match expr {
    DynamicImport(StringLit("./mod"), None) => ()
    other => fail("expected bare dynamic import, got \{other}")
  }
}

///|
test "parser: parse import attributes (`with { type: \"json\" }`)" {
  let src =
    #|import data from "./data.json" with { type: "json" };
  let parser = Parser::from_source(src)
  let block = parser.parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(block.imports.length(), 1)
  let imp = block.imports[0]
  assert_eq(imp.module_spec, "./data.json")
  assert_eq(imp.attributes, [("type", "json")])
}

///|
test "parser: parse per-specifier type modifier on named imports" {
  let src =
    #|import { type Foo, Bar, type Baz } from "./mod";
  let parser = Parser::from_source(src)
  let block = parser.parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(block.imports.length(), 1)
  let imp = block.imports[0]
  assert_eq(imp.named_bindings, [("Foo", "Foo"), ("Bar", "Bar"), ("Baz", "Baz")])
  assert_eq(imp.named_type_only, [true, false, true])
  assert_false(imp.type_only)
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
test "parser: parse generic function declaration in ts module" {
  let src =
    #|function withResolver<T>(value?: T): Promise<T> {
    #|  return promise;
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.funcs.length(), 1)
  assert_eq(module_.funcs[0].name, "withResolver")
}

///|
test "parser: parse function with const-modifier type parameter" {
  // TypeScript 5.0 introduced `<const T>` to opt the inferred type
  // parameter into a more literal-preserving inference. The const
  // modifier has no effect on the erased generic shape we keep.
  let src =
    #|function asConst<const T>(value: T): T {
    #|  return value;
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.funcs.length(), 1)
  assert_eq(module_.funcs[0].name, "asConst")
}

///|
test "parser: parse interface method with const-modifier type parameter" {
  let src =
    #|interface Asserts {
    #|  assertReadonly<const T>(value: T): T;
    #|}
  let parser = Parser::from_source(src)
  let iface = parser.parse_interface()
  assert_eq(iface.name, "Asserts")
  assert_eq(iface.fields.length(), 1)
  let (name, _) = iface.fields[0]
  assert_eq(name, "assertReadonly")
}

///|
test "parser: parse const enum declaration in ts module block" {
  let src =
    #|export const enum ReactiveFlags {
    #|  None = 0,
    #|  Watching = 2,
    #|}
    #|export function current(): number {
    #|  return ReactiveFlags.None;
    #|}
  let module_ = parse_module_block_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.enums.length(), 1)
  assert_eq(module_.enums[0].name, "ReactiveFlags")
  assert_true(module_.enums[0].is_const)
  assert_false(module_.enums[0].is_declare)
  assert_eq(module_.enums[0].members.length(), 2)
  assert_eq(
    module_.enums[0].members[0].value,
    Some(@ast.TsEnumMemberValue::Number("0")),
  )
  assert_eq(
    module_.enums[0].members[1].value,
    Some(@ast.TsEnumMemberValue::Number("2")),
  )
  assert_eq(module_.exports.length(), 2)
  assert_eq(module_.exports[0].export_name, "ReactiveFlags")
  assert_eq(module_.exports[1].export_name, "current")
}

///|
test "parser: parse declare string enum in ts module" {
  let src =
    #|declare enum Mode {
    #|  Read = "read",
    #|  Write = "write",
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.enums.length(), 1)
  assert_eq(module_.enums[0].name, "Mode")
  assert_false(module_.enums[0].is_const)
  assert_true(module_.enums[0].is_declare)
  assert_eq(module_.enums[0].members.length(), 2)
  assert_eq(module_.enums[0].members[0].name, "Read")
  assert_eq(
    module_.enums[0].members[0].value,
    Some(@ast.TsEnumMemberValue::String("read")),
  )
  assert_eq(module_.enums[0].members[1].name, "Write")
  assert_eq(
    module_.enums[0].members[1].value,
    Some(@ast.TsEnumMemberValue::String("write")),
  )
}

///|
test "parser: parse export const numeric enum in ts module" {
  let src =
    #|export const enum SyntaxKind {
    #|  Unknown = 0,
    #|  Identifier = 80,
    #|  StringLiteral,
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.enums.length(), 1)
  assert_eq(module_.enums[0].name, "SyntaxKind")
  assert_true(module_.enums[0].is_const)
  assert_false(module_.enums[0].is_declare)
  assert_eq(module_.enums[0].members.length(), 3)
  assert_eq(module_.enums[0].members[0].name, "Unknown")
  assert_eq(
    module_.enums[0].members[0].value,
    Some(@ast.TsEnumMemberValue::Number("0")),
  )
  assert_eq(module_.enums[0].members[1].name, "Identifier")
  assert_eq(
    module_.enums[0].members[1].value,
    Some(@ast.TsEnumMemberValue::Number("80")),
  )
  assert_eq(module_.enums[0].members[2].name, "StringLiteral")
  assert_eq(module_.enums[0].members[2].value, None)
  assert_false(module_.enums[0].members[2].is_computed)
}

///|
test "parser: marks non-literal enum initializers as computed" {
  let src =
    #|export declare enum ComputedKind {
    #|  Dynamic = getKind(),
    #|  Static = 1,
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.enums.length(), 1)
  assert_eq(module_.enums[0].members.length(), 2)
  assert_eq(module_.enums[0].members[0].name, "Dynamic")
  assert_eq(module_.enums[0].members[0].value, None)
  assert_true(module_.enums[0].members[0].is_computed)
  assert_eq(
    module_.enums[0].members[1].value,
    Some(@ast.TsEnumMemberValue::Number("1")),
  )
  assert_false(module_.enums[0].members[1].is_computed)
}

///|
test "parser: parse enum inside declared namespace" {
  let src =
    #|declare namespace ts {
    #|  enum ScriptTarget {
    #|    ES5 = 1,
    #|  }
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.namespaces.length(), 1)
  assert_eq(module_.namespaces[0].name, "ts")
  assert_eq(module_.namespaces[0].module_.enums.length(), 1)
  let enum_ = module_.namespaces[0].module_.enums[0]
  assert_eq(enum_.name, "ScriptTarget")
  assert_false(enum_.is_const)
  assert_true(enum_.is_declare)
  assert_eq(enum_.members.length(), 1)
  assert_eq(enum_.members[0].name, "ES5")
  assert_eq(enum_.members[0].value, Some(@ast.TsEnumMemberValue::Number("1")))
}

///|
test "parser: parse function overload signature in ts module" {
  let src =
    #|export function signal<T>(): {
    #|  (): T | undefined;
    #|  (value: T | undefined): void;
    #|};
    #|export function signal<T>(initialValue?: T): {
    #|  (): T | undefined;
    #|  (value: T | undefined): void;
    #|} {
    #|  return signalOper;
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.funcs.length(), 2)
  assert_eq(module_.funcs[0].name, "signal")
  assert_eq(module_.funcs[1].name, "signal")
}

///|
test "parser: substitute ambient namespace function generic bounds" {
  let src =
    #|declare namespace ts {
    #|  function visitEachChild<T extends Node>(node: T, visitor: Visitor): T;
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.namespaces.length(), 1)
  let inner = module_.namespaces[0].module_
  assert_eq(inner.funcs.length(), 1)
  assert_eq(inner.funcs[0].name, "visitEachChild")
  assert_eq(inner.funcs[0].params[0].type_, @ast.TsType::Named("Node"))
  assert_eq(inner.funcs[0].return_type, @ast.TsType::Named("Node"))
}

///|
test "parser: parse semicolon-less ambient declarations in dts module" {
  let src =
    #|declare const coreMap: Record<string, Uint8Array>
    #|declare const corePkgs: string[]
    #|declare function getLoadPkgsParams(
    #|  target?: "wasm-gc" | "wasm" | "js",
    #|): [importPath: string, mi: Uint8Array][]
    #|
    #|export { coreMap, getLoadPkgsParams }
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 2)
  assert_eq(module_.imports.length(), 1)
}

///|
test "parser: parse typeof import type annotation" {
  let src =
    #|function isObjectOrNullableUnion(
    #|  ts: typeof import("typescript"),
    #|): boolean {
    #|  return true;
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.funcs.length(), 1)
}

///|
test "parser: parse typeof import qualified type annotation" {
  let src =
    #|let registerPreActionHooks: typeof import("./preaction.js").registerPreActionHooks;
  let stmt = parse_stmt_from(src)
  match stmt {
    Let(@ast.TsBinding::Ident("registerPreActionHooks"), _, _) => ()
    _ => fail("expected let declaration with typeof import qualified type")
  }
}

///|
test "parser: preserve type-position typeof queries in type aliases" {
  let src =
    #|type Middleware = typeof middleware;
    #|type Imported = typeof import("./dispatch.js").dispatch;
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.type_aliases.length(), 2)
  assert_eq(module_.type_aliases[0].type_, @ast.TsType::TypeOf("middleware"))
  assert_eq(
    module_.type_aliases[1].type_,
    @ast.TsType::TypeOf("import(\"./dispatch.js\").dispatch"),
  )
}

///|
test "parser: parse generic function type parameter annotation" {
  let src =
    #|async function buildDispatchInboundContextCapture(
    #|  importOriginal: <T extends Record<string, unknown>>() => Promise<T>,
    #|) {
    #|  return await importOriginal<typeof import("./dispatch.js")>();
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse arrow with function return type annotation" {
  let src =
    #|const createShouldEmitToolResult = (params: VerboseGateParams): (() => boolean) => {
    #|  return createVerboseGate(params, (level) => level !== "off");
    #|};
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("createShouldEmitToolResult"), _, _) => ()
    _ => fail("expected const declaration with function return type annotation")
  }
}

///|
test "parser: parse module export const declaration without initializer" {
  let src =
    #|export const runNodeWatchedPaths: string[];
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 1)
  assert_eq(module_.values[0].name, "runNodeWatchedPaths")
}

///|
test "parser: parse module export const declaration with initializer into values" {
  let src =
    #|export const version: string = "v2";
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 1)
  assert_eq(module_.values[0].name, "version")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
}

///|
test "parser: parse module export const destructuring declaration into values" {
  let src =
    #|export const { version: runtimeVersion, build } = { version: "v3", build: 7.0 };
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 2)
  assert_eq(module_.values[0].name, "runtimeVersion")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "build")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
}

///|
test "parser: parse module export nested const destructuring declaration into values" {
  let src =
    #|export const { meta: { version: runtimeVersion, build } } = {
    #|  meta: { version: "v3", build: 7.0 },
    #|};
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 2)
  assert_eq(module_.values[0].name, "runtimeVersion")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "build")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
}

///|
test "parser: parse module export array rest destructuring declaration into values" {
  let src =
    #|export const [head, ...tail] = [1.0, 2.0, 3.0];
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 2)
  assert_eq(module_.values[0].name, "head")
  assert_eq(module_.values[0].type_, @ast.TsType::Number)
  assert_eq(module_.values[1].name, "tail")
  assert_eq(module_.values[1].type_, @ast.TsType::Array(@ast.TsType::Number))
}

///|
test "parser: parse module export object rest destructuring declaration into values" {
  let src =
    #|export const { version, ...restMeta } = {
    #|  version: "v3",
    #|  build: 7.0,
    #|  enabled: true,
    #|};
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 2)
  assert_eq(module_.values[0].name, "version")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "restMeta")
  assert_eq(
    module_.values[1].type_,
    @ast.TsType::Struct("RestMeta", [
      ("build", @ast.TsType::Number),
      ("enabled", @ast.TsType::Boolean),
    ]),
  )
}

///|
test "parser: parse module export computed-key destructuring declaration into values" {
  let src =
    #|export const { ["version"]: runtimeVersion, ["build"]: build, ...restMeta } = {
    #|  version: "v3",
    #|  build: 7.0,
    #|  enabled: true,
    #|};
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].name, "runtimeVersion")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "build")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(module_.values[2].name, "restMeta")
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse module export template-literal computed-key destructuring declaration into values" {
  let src =
    #|export const { [`version`]: runtimeVersion, [`build`]: build, ...restMeta } = {
    #|  version: "v3",
    #|  build: 7.0,
    #|  enabled: true,
    #|};
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].name, "runtimeVersion")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "build")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(module_.values[2].name, "restMeta")
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse module export concatenated computed-key destructuring declaration into values" {
  let src =
    #|export const { ["ver" + "sion"]: runtimeVersion, ["bu" + "ild"]: build, ...restMeta } = {
    #|  version: "v3",
    #|  build: 7.0,
    #|  enabled: true,
    #|};
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].name, "runtimeVersion")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "build")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(module_.values[2].name, "restMeta")
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse module export primitive-literal computed-key destructuring declaration into values" {
  let src =
    #|export const { [true]: truthy, [null]: nilValue, [-1]: negative, [1n]: bigintValue, ...restMeta } = {
    #|  "true": "yes",
    #|  "null": 7.0,
    #|  "-1": false,
    #|  "1": "one",
    #|  enabled: true,
    #|};
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 5)
  assert_eq(module_.values[0].name, "truthy")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "nilValue")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(module_.values[2].name, "negative")
  assert_eq(module_.values[2].type_, @ast.TsType::Boolean)
  assert_eq(module_.values[3].name, "bigintValue")
  assert_eq(module_.values[3].type_, @ast.TsType::String_)
  assert_eq(module_.values[4].name, "restMeta")
  assert_eq(
    module_.values[4].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse module export void-and-negative-bigint computed-key destructuring declaration into values" {
  let src =
    #|export const { [void 0]: undefinedValue, [-1n]: negativeBigint, ...restMeta } = {
    #|  "undefined": "void",
    #|  "-1": 9.0,
    #|  enabled: true,
    #|};
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].name, "undefinedValue")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "negativeBigint")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(module_.values[2].name, "restMeta")
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse module export const-reference computed-key destructuring declaration into values" {
  let src =
    #|const VERSION_KEY = "version";
    #|const BUILD_KEY = "build";
    #|export const { [VERSION_KEY]: runtimeVersion, [BUILD_KEY]: build, ...restMeta } = {
    #|  version: "v3",
    #|  build: 7.0,
    #|  enabled: true,
    #|};
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].name, "runtimeVersion")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "build")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(module_.values[2].name, "restMeta")
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse module export destructured-const-reference computed-key declaration into values" {
  let src =
    #|const { version: VERSION_KEY, build: BUILD_KEY } = {
    #|  version: "version",
    #|  build: "build",
    #|};
    #|export const { [VERSION_KEY]: runtimeVersion, [BUILD_KEY]: build, ...restMeta } = {
    #|  version: "v4",
    #|  build: 8.0,
    #|  enabled: false,
    #|};
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].name, "runtimeVersion")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "build")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(module_.values[2].name, "restMeta")
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse module export const-object-access computed-key declaration into values" {
  let src =
    #|const KEYS = {
    #|  version: "version",
    #|  build: "build",
    #|};
    #|export const {
    #|  [KEYS.version]: runtimeVersion,
    #|  [KEYS["build"]]: build,
    #|  ...restMeta,
    #|} = {
    #|  version: "v5",
    #|  build: 9.0,
    #|  enabled: true,
    #|};
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].name, "runtimeVersion")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "build")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(module_.values[2].name, "restMeta")
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse module export nested-const-object-access computed-key declaration into values" {
  let src =
    #|const KEYS = {
    #|  nested: {
    #|    version: "version",
    #|    build: "build",
    #|  },
    #|};
    #|export const {
    #|  [KEYS.nested.version]: runtimeVersion,
    #|  [KEYS.nested["build"]]: build,
    #|  ...restMeta,
    #|} = {
    #|  version: "v6",
    #|  build: 10.0,
    #|  enabled: false,
    #|};
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].name, "runtimeVersion")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "build")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(module_.values[2].name, "restMeta")
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse module export const-array-access computed-key declaration into values" {
  let src =
    #|const KEYS = ["version", "build"];
    #|export const {
    #|  [KEYS[0]]: runtimeVersion,
    #|  [KEYS[1]]: build,
    #|  ...restMeta,
    #|} = {
    #|  version: "v7",
    #|  build: 11.0,
    #|  enabled: true,
    #|};
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].name, "runtimeVersion")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "build")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(module_.values[2].name, "restMeta")
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse module export nested-const-array-access computed-key declaration into values" {
  let src =
    #|const KEYS = {
    #|  nested: ["version", "build"],
    #|};
    #|export const {
    #|  [KEYS.nested[0]]: runtimeVersion,
    #|  [KEYS.nested[1]]: build,
    #|  ...restMeta,
    #|} = {
    #|  version: "v8",
    #|  build: 12.0,
    #|  enabled: false,
    #|};
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].name, "runtimeVersion")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "build")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(module_.values[2].name, "restMeta")
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse module export const-index-alias computed-key declaration into values" {
  let src =
    #|const INDEX = 0;
    #|const NEXT_INDEX = 1;
    #|const KEYS = {
    #|  nested: ["version", "build"],
    #|};
    #|export const {
    #|  [KEYS.nested[INDEX]]: runtimeVersion,
    #|  [KEYS.nested[NEXT_INDEX]]: build,
    #|  ...restMeta,
    #|} = {
    #|  version: "v9",
    #|  build: 13.0,
    #|  enabled: true,
    #|};
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].name, "runtimeVersion")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "build")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(module_.values[2].name, "restMeta")
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse module export const-index-table computed-key declaration into values" {
  let src =
    #|const INDEXES = [0, 1];
    #|const KEYS = {
    #|  nested: ["version", "build"],
    #|};
    #|export const {
    #|  [KEYS.nested[INDEXES[0]]]: runtimeVersion,
    #|  [KEYS.nested[INDEXES[1]]]: build,
    #|  ...restMeta,
    #|} = {
    #|  version: "v10",
    #|  build: 14.0,
    #|  enabled: false,
    #|};
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].name, "runtimeVersion")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "build")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(module_.values[2].name, "restMeta")
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse module export nested-index-table computed-key declaration into values" {
  let src =
    #|const MATRIX = [[0, 1]];
    #|const KEYS = {
    #|  nested: ["version", "build"],
    #|};
    #|export const {
    #|  [KEYS.nested[MATRIX[0][0]]]: runtimeVersion,
    #|  [KEYS.nested[MATRIX[0][1]]]: build,
    #|  ...restMeta,
    #|} = {
    #|  version: "v11",
    #|  build: 15.0,
    #|  enabled: true,
    #|};
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].name, "runtimeVersion")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "build")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(module_.values[2].name, "restMeta")
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse module with seeded imported const values into exports" {
  let src =
    #|export const {
    #|  [KEYS.nested[INDEXES[0]]]: runtimeVersion,
    #|  [KEYS.nested[INDEXES[1]]]: build,
    #|  ...restMeta,
    #|} = {
    #|  version: "v12",
    #|  build: 16.0,
    #|  enabled: false,
    #|};
  let seeded_const_values : Map[String, @ast.TsExpr] = {
    "INDEXES": @ast.TsExpr::ArrayLit([
      @ast.TsExpr::IntLit(0),
      @ast.TsExpr::IntLit(1),
    ]),
    "KEYS": @ast.TsExpr::ObjectLit([
      (
        "nested",
        @ast.TsExpr::ArrayLit([
          @ast.TsExpr::StringLit("version"),
          @ast.TsExpr::StringLit("build"),
        ]),
      ),
    ]),
  }
  let module_ = parse_module_from_source_with_const_values(
    src, seeded_const_values,
  ) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].name, "runtimeVersion")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "build")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(module_.values[2].name, "restMeta")
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: collect exported const values from source" {
  let src =
    #|const INDEXES = [0, 1];
    #|const KEYS = {
    #|  nested: ["version", "build"],
    #|};
    #|export { INDEXES, KEYS };
  let exported_const_values = collect_exported_const_values_from_source(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  match exported_const_values.get("INDEXES") {
    Some(@ast.TsExpr::ArrayLit(items)) => assert_eq(items.length(), 2)
    _ => fail("expected INDEXES array literal")
  }
  match exported_const_values.get("KEYS") {
    Some(@ast.TsExpr::ObjectLit(props)) => assert_eq(props.length(), 1)
    _ => fail("expected KEYS object literal")
  }
}

///|
test "parser: collect default exported const value from source" {
  let src =
    #|const TABLES = {
    #|  INDEXES: [0, 1],
    #|  KEYS: {
    #|    nested: ["version", "build"],
    #|  },
    #|};
    #|export default TABLES;
  let exported_const_values = collect_exported_const_values_from_source(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  match exported_const_values.get("default") {
    Some(@ast.TsExpr::ObjectLit(props)) => assert_eq(props.length(), 2)
    _ => fail("expected default object literal")
  }
}

///|
test "parser: collect inline default exported const value from source" {
  let src =
    #|export default {
    #|  INDEXES: [0, 1],
    #|  KEYS: {
    #|    nested: ["version", "build"],
    #|  },
    #|};
  let exported_const_values = collect_exported_const_values_from_source(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  match exported_const_values.get("default") {
    Some(@ast.TsExpr::ObjectLit(props)) => assert_eq(props.length(), 2)
    _ => fail("expected inline default object literal")
  }
}

///|
test "parser: collect inline default exported const value with as const from source" {
  let src =
    #|export default {
    #|  INDEXES: [0, 1],
    #|  KEYS: {
    #|    nested: ["version", "build"],
    #|  },
    #|} as const;
  let exported_const_values = collect_exported_const_values_from_source(src, {}) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  match exported_const_values.get("default") {
    Some(@ast.TsExpr::ObjectLit(props)) => assert_eq(props.length(), 2)
    _ => fail("expected inline default as const object literal")
  }
}

///|
test "parser: parse computed-key destructuring with zero-arg iife const seed into values" {
  let src =
    #|export const {
    #|  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
    #|  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
    #|  ...restMeta
    #|} = {
    #|  version: "v24",
    #|  build: 28.0,
    #|  enabled: true,
    #|};
  let seeded_const_values = {
    "tables": parse_expr_from(
      "(() => ({ INDEXES: [0, 1], KEYS: { nested: [\"version\", \"build\"] } }))()",
    ),
  }
  let module_ = parse_module_from_source_with_const_values(
    src, seeded_const_values,
  ) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].name, "runtimeVersion")
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].name, "build")
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(module_.values[2].name, "restMeta")
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse computed-key destructuring with block iife local const seed into values" {
  let src =
    #|export const {
    #|  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
    #|  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
    #|  ...restMeta
    #|} = {
    #|  version: "v25",
    #|  build: 29.0,
    #|  enabled: false,
    #|};
  let seeded_const_values = {
    "tables": parse_expr_from(
      "(() => { const INDEXES = [0, 1]; const KEYS = { nested: [\"version\", \"build\"] }; const TABLES = { INDEXES, KEYS }; return TABLES; })()",
    ),
  }
  let module_ = parse_module_from_source_with_const_values(
    src, seeded_const_values,
  ) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse computed-key destructuring with function iife local const seed into values" {
  let src =
    #|export const {
    #|  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
    #|  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
    #|  ...restMeta
    #|} = {
    #|  version: "v26",
    #|  build: 30.0,
    #|  enabled: true,
    #|};
  let seeded_const_values = {
    "tables": parse_expr_from(
      "(function() { const INDEXES = [0, 1]; const KEYS = { nested: [\"version\", \"build\"] }; const TABLES = { INDEXES, KEYS }; return TABLES; })()",
    ),
  }
  let module_ = parse_module_from_source_with_const_values(
    src, seeded_const_values,
  ) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse computed-key destructuring with block iife local let seed into values" {
  let src =
    #|export const {
    #|  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
    #|  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
    #|  ...restMeta
    #|} = {
    #|  version: "v27",
    #|  build: 31.0,
    #|  enabled: false,
    #|};
  let seeded_const_values = {
    "tables": parse_expr_from(
      "(() => { let INDEXES = [0, 1]; let KEYS = { nested: [\"version\", \"build\"] }; let TABLES = { INDEXES, KEYS }; return TABLES; })()",
    ),
  }
  let module_ = parse_module_from_source_with_const_values(
    src, seeded_const_values,
  ) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: parse computed-key destructuring with function iife local let seed into values" {
  let src =
    #|export const {
    #|  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
    #|  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
    #|  ...restMeta
    #|} = {
    #|  version: "v28",
    #|  build: 32.0,
    #|  enabled: true,
    #|};
  let seeded_const_values = {
    "tables": parse_expr_from(
      "(function() { let INDEXES = [0, 1]; let KEYS = { nested: [\"version\", \"build\"] }; let TABLES = { INDEXES, KEYS }; return TABLES; })()",
    ),
  }
  let module_ = parse_module_from_source_with_const_values(
    src, seeded_const_values,
  ) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].type_, @ast.TsType::String_)
  assert_eq(module_.values[1].type_, @ast.TsType::Number)
  assert_eq(
    module_.values[2].type_,
    @ast.TsType::Struct("RestMeta", [("enabled", @ast.TsType::Boolean)]),
  )
}

///|
test "parser: keep computed-key destructuring with reassigned local let seed conservative" {
  let src =
    #|export const {
    #|  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
    #|  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
    #|  ...restMeta
    #|} = {
    #|  version: "v29",
    #|  build: 33.0,
    #|  enabled: false,
    #|};
  let seeded_const_values = {
    "tables": parse_expr_from(
      "(() => { let INDEXES = [0, 1]; let KEYS = { nested: [\"version\", \"build\"] }; KEYS = { nested: [\"version\", \"build\"] }; let TABLES = { INDEXES, KEYS }; return TABLES; })()",
    ),
  }
  let module_ = parse_module_from_source_with_const_values(
    src, seeded_const_values,
  ) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].type_, @ast.TsType::Any)
  assert_eq(module_.values[1].type_, @ast.TsType::Any)
  assert_eq(module_.values[2].type_, @ast.TsType::Any)
}

///|
test "parser: keep computed-key destructuring with prop-mutated local let seed conservative" {
  let src =
    #|export const {
    #|  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
    #|  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
    #|  ...restMeta
    #|} = {
    #|  version: "v30",
    #|  build: 34.0,
    #|  enabled: true,
    #|};
  let seeded_const_values = {
    "tables": parse_expr_from(
      "(() => { let INDEXES = [0, 1]; let KEYS = { nested: [\"version\", \"build\"] }; KEYS.nested = [\"version\", \"build\"]; let TABLES = { INDEXES, KEYS }; return TABLES; })()",
    ),
  }
  let module_ = parse_module_from_source_with_const_values(
    src, seeded_const_values,
  ) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].type_, @ast.TsType::Any)
  assert_eq(module_.values[1].type_, @ast.TsType::Any)
  assert_eq(module_.values[2].type_, @ast.TsType::Any)
}

///|
test "parser: keep computed-key destructuring with index-mutated local let seed conservative" {
  let src =
    #|export const {
    #|  [tables.KEYS.nested[tables.INDEXES[0]]]: runtimeVersion,
    #|  [tables.KEYS.nested[tables.INDEXES[1]]]: build,
    #|  ...restMeta
    #|} = {
    #|  version: "v31",
    #|  build: 35.0,
    #|  enabled: false,
    #|};
  let seeded_const_values = {
    "tables": parse_expr_from(
      "(function() { let INDEXES = [0, 1]; let KEYS = { nested: [\"version\", \"build\"] }; INDEXES[0] = 0; let TABLES = { INDEXES, KEYS }; return TABLES; })()",
    ),
  }
  let module_ = parse_module_from_source_with_const_values(
    src, seeded_const_values,
  ) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.values.length(), 3)
  assert_eq(module_.values[0].type_, @ast.TsType::Any)
  assert_eq(module_.values[1].type_, @ast.TsType::Any)
  assert_eq(module_.values[2].type_, @ast.TsType::Any)
}

///|
test "parser: parse module block export const declaration without initializer" {
  let src =
    #|export const runNodeWatchedPaths: string[];
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.exports.length(), 1)
  assert_eq(module_.exports[0].export_name, "runNodeWatchedPaths")
}

///|
test "parser: parse bare import type annotation" {
  let src =
    #|function resolveSections(
    #|  sections: import("./resource-resolver.js").PieceSections,
    #|): void {
    #|  return;
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.funcs.length(), 1)
}

///|
test "parser: parse new expression with multiple generic type args" {
  match parse_expr_from("new Map<string, string>()") {
    New("Map", args) => assert_eq(args.length(), 0)
    _ => fail("expected generic New(Map), got different expression")
  }
}

///|
test "parser: parse new expression with private constructor property and type args" {
  match parse_expr_from("new this.#mapCtor<string, DataValue>()") {
    NewExpr(_, args) => assert_eq(args.length(), 0)
    _ => fail("expected NewExpr with private constructor property")
  }
}

///|
test "parser: parse module block type re-export metadata" {
  let src =
    #|export type { ExpectStatic, Assertion as TestAssertion } from "@vitest/expect";
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.exports.length(), 0)
  assert_eq(module_.reexports.length(), 1)
  assert_eq(module_.reexports[0].module_spec, "@vitest/expect")
  match module_.reexports[0].kind {
    Named(items) => {
      assert_eq(items.length(), 2)
      assert_eq(items[0], ("ExpectStatic", "ExpectStatic"))
      assert_eq(items[1], ("Assertion", "TestAssertion"))
    }
    _ => fail("expected named type re-export")
  }
}

///|
test "parser: parse generic call with array type arg" {
  match parse_expr_from("signal<number[]>([])") {
    Call("signal", args) => assert_eq(args.length(), 1)
    _ => fail("expected generic call expression")
  }
}

///|
test "parser: parse as const assertion" {
  let stmt = parse_stmt_from("const pair = [promise, resolve!] as const;")
  match stmt {
    Const(@ast.TsBinding::Ident("pair"), _, _) => ()
    _ => fail("expected const declaration with as const assertion")
  }
}

///|
test "parser: parse as type assertion in expression" {
  let stmt = parse_stmt_from(
    "const link = (moonPkg.link as Record<string, unknown>) || {};",
  )
  match stmt {
    Const(@ast.TsBinding::Ident("link"), _, _) => ()
    _ => fail("expected const declaration with as-cast expression")
  }
}

///|
test "parser: parse as assertion before logical or" {
  let src =
    #|const displayName: string | undefined = (step as Record<string, unknown>).persona_name as string
    #|  || undefined;
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("displayName"), _, _) => ()
    _ => fail("expected const declaration with as assertion before logical or")
  }
}

///|
test "parser: parse leading pipe union in as assertion" {
  let src =
    #|const snapshot = props.hello?.snapshot as
    #|  | {
    #|      uptimeMs?: number;
    #|      policy?: { tickIntervalMs?: number };
    #|      authMode?: "none" | "token" | "password" | "trusted-proxy";
    #|    }
    #|  | undefined;
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("snapshot"), _, _) => ()
    _ => fail("expected const declaration with leading-pipe union assertion")
  }
}

///|
test "parser: parse as cast inside callback call argument" {
  let src =
    #|if ([...normalizedTypes].every((v) => ["string", "number", "boolean"].includes(v as string))) {
    #|  const ok = true;
    #|}
  let stmt = Parser::from_source(src).parse_stmt()
  match stmt {
    If(_, _, _) => ()
    _ => fail("expected if statement with as-cast in callback argument")
  }
}

///|
test "parser: parse typed catch binding" {
  let stmt = parse_stmt_from(
    "try { risky(); } catch (error: unknown) { console.error(error); }",
  )
  match stmt {
    Try(_, Some(@ast.TsBinding::Ident("error")), Some(catch_block), None) =>
      assert_eq(catch_block.stmts.length(), 1)
    _ => fail("expected try/catch with typed binding")
  }
}

///|
test "parser: parse non-null assertion postfix" {
  let src =
    #|const name = moduleName.split("/").pop()!;
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("name"), _, _) => ()
    _ => fail("expected const declaration with postfix non-null assertion")
  }
}

///|
test "parser: parse non-null assertion before property access" {
  let stmt = parse_stmt_from("link = stack!.value;")
  match stmt {
    Expr(
      AssignExpr(
        "link",
        PropAccess(@ast.TsExpr::NonNull(Var("stack")), "value")
      )
    ) => ()
    _ => fail("expected property access after non-null assertion")
  }
}

///|
test "parser: parse non-null assertion after call before compound assign" {
  let stmt = parse_stmt_from(
    "getActiveSub()!.flags &= ~ReactiveFlags.RecursedCheck;",
  )
  match stmt {
    Expr(
      CompoundAssignExpr(
        PropAccess(@ast.TsExpr::NonNull(Call("getActiveSub", _)), "flags"),
        BitAndAssign,
        _
      )
    ) => ()
    _ => fail("expected compound assign on call()!.prop")
  }
}

///|
test "parser: parse arrow function with type predicate return annotation" {
  let src =
    #|const types = ast.sigs.filter((sig): sig is Foo => sig.ok);
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("types"), _, _) => ()
    _ => fail("expected const declaration with typed arrow predicate")
  }
}

///|
test "parser: parse real-world chain with destructuring and typed filter predicate" {
  let src =
    #|function getTypes(ast: Mbti): TypeSig[] {
    #|  return ast.sigs
    #|    .map(([sig]) => sig)
    #|    .filter((sig): sig is { $tag: "Type"; 0: TypeSig } => sig.$tag === "Type")
    #|    .map((sig) => sig[0]);
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.funcs.length(), 1)
}

///|
test "parser: parse real-world object literal with arrow properties" {
  let src =
    #|function createCompilerHost(filename: string): void {
    #|  const compilerHost: ts.CompilerHost = {
    #|    getSourceFile: (name) =>
    #|      name === filename ? sourceFile : undefined,
    #|    getDefaultLibFileName: () => "lib.d.ts",
    #|    writeFile: () => {},
    #|  };
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.funcs.length(), 1)
}

///|
test "parser: parse object literal async method shorthand" {
  let src =
    #|const factory = {
    #|  async create() {
    #|    return moon;
    #|  },
    #|};
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("factory"), _, _) => ()
    _ => fail("expected object literal with async method shorthand")
  }
}

///|
test "parser: parse object literal async method with typed signature" {
  let src =
    #|const fs = {
    #|  async readFile(uri: URI): Promise<Uint8Array> {
    #|    return Deno.readFileSync(uri.path);
    #|  },
    #|};
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("fs"), _, _) => ()
    _ => fail("expected object literal with typed async method")
  }
}

///|
test "parser: parse satisfies expression" {
  let src =
    #|const params = {
    #|  capabilities: {},
    #|} satisfies lsp.InitializeParams;
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("params"), _, _) => ()
    _ => fail("expected const declaration with satisfies expression")
  }
}

///|
test "parser: parse object literal shorthand with keyword-like property name" {
  let stmt = parse_stmt_from("const blob = new Blob([], { type });")
  match stmt {
    Const(@ast.TsBinding::Ident("blob"), _, _) => ()
    _ => fail("expected object literal shorthand with keyword-like key")
  }
}

///|
test "parser: import named binding named type" {
  let src =
    #|import { type } from "./type.js";
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.imports.length(), 1)
}

///|
test "parser: parse exported namespace declaration" {
  let src =
    #|export namespace JSX {
    #|  export type A = string;
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.exports.length(), 1)
  assert_eq(module_.exports[0].local_name, "JSX")
  assert_eq(module_.exports[0].export_name, "JSX")
}

///|
test "parser: parse export import alias declaration" {
  let src =
    #|export import flakySuite = testUtils.flakySuite;
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.exports.length(), 1)
}

///|
async test "parser: parse export-as-namespace sanitize fixture in module block" {
  let src = @fs.read_file(
    "fixtures/resolver/project/types/export-as-namespace-sanitize-entry.d.ts",
  ).text()
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.exports.length(), 1)
  assert_eq(module_.exports[0].export_name, "default")
}

///|
test "parser: skip plain namespace declaration in module block" {
  let src =
    #|namespace Samples {
    #|  export class EventCounter {
    #|    count = 0;
    #|  }
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 0)
}

///|
test "parser: parse interface extends nested generic object type" {
  let src =
    #|export interface Context<T> extends FC<PropsWithChildren<{ value: T }>> {
    #|  Provider: FC<PropsWithChildren<{ value: T }>>
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.interfaces.length(), 1)
  assert_eq(module_.interfaces[0].extends_names, ["FC"])
}

///|
test "parser: parse generic function property type" {
  let src =
    #|export interface Assertion<T> {
    #|  toBe: <E>(expected: E) => void;
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.interfaces.length(), 1)
  assert_eq(module_.interfaces[0].fields.length(), 1)
  match module_.interfaces[0].fields[0].1 {
    Func(params, Void) => assert_eq(params.length(), 1)
    _ => fail("expected generic function property to lower to Func")
  }
}

///|
test "parser: parse object literal method with generic type params" {
  let src =
    #|const testContext = {
    #|  add<T extends IDisposable>(o: T): T {
    #|    return store.add(o);
    #|  }
    #|};
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("testContext"), _, _) => ()
    _ => fail("expected const declaration with generic object method")
  }
}

///|
test "parser: parse async generator computed object method" {
  let src =
    #|const asyncIterable = {
    #|  async *[Symbol.asyncIterator]() {
    #|    yield "a";
    #|  }
    #|};
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("asyncIterable"), _, _) => ()
    _ => fail("expected const declaration with async generator computed method")
  }
}

///|
test "parser: parse anonymous class expression with implements clause" {
  let src =
    #|const deserializer = new class implements IViewDeserializer<ISerializableView> {
    #|  fromJSON(): ISerializableView {
    #|    return view;
    #|  }
    #|};
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("deserializer"), _, _) => ()
    _ =>
      fail("expected const declaration with anonymous class implements clause")
  }
}

///|
test "parser: parse object literal arrow value with type keyword param name" {
  let src =
    #|const result = transform(source, { data: string => string + string }, strings => strings.join());
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("result"), _, _) => ()
    _ => fail("expected const declaration with type-keyword arrow parameter")
  }
}

///|
test "parser: parse angle bracket type assertion when jsx disabled" {
  let src =
    #|function check(str: unknown) {
    #|  return strings.containsUppercaseCharacter(<string>str);
    #|}
  let module_ = Parser::from_source_with_jsx(src, false).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse decorated class method" {
  let src =
    #|class Foo {
    #|  @memoize
    #|  answer() {
    #|    return 42;
    #|  }
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse decorated export class" {
  let src =
    #|@customElement("x-app")
    #|export class App extends LitElement {}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
  assert_eq(module_.exports.length(), 1)
}

///|
test "parser: parse class field definite assignment assertion" {
  let src =
    #|class QueueProtocol {
    #|  other!: QueueProtocol;
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse declared class field" {
  let src =
    #|class EventDeliveryQueuePrivate {
    #|  declare _isEventDeliveryQueue: true;
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse constructor parameter property named type" {
  let src =
    #|class ProtocolMessage {
    #|  constructor(public readonly type: ProtocolMessageType) {}
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse parameter named of" {
  let src =
    #|class Color {
    #|  static getLighterColor(of: Color, relative: Color): Color {
    #|    return of;
    #|  }
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse class extends parenthesized expression base" {
  let src =
    #|class Root extends (SignalWatcher(LitElement) as typeof LitElement) {}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse jsx self closing element expression" {
  let src =
    #|function renderView() {
    #|  return <Style />;
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse jsx fragment with nested children" {
  let src =
    #|function App() {
    #|  return (
    #|    <>
    #|      <div>{state}</div>
    #|      <Style nonce="1234" />
    #|    </>
    #|  );
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse jsx text with apostrophe" {
  let src =
    #|function App() {
    #|  return (
    #|    <TreeItemLayout> Test doesn't have run info. Rename ↵ </TreeItemLayout>
    #|  );
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse tsx callback prop with destructured second parameter" {
  let src =
    #|export const CurrentRunPicker = () => {
    #|  return (
    #|    <Dialog
    #|      open={isRenameDialogOpen}
    #|      onOpenChange={(_, { open }) => setIsRenameDialogOpen(open)}
    #|    >
    #|      <DialogSurface />
    #|    </Dialog>
    #|  );
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
  assert_eq(module_.exports.length(), 1)
}

///|
test "parser: parse tsx conditional fragment branch with mapped children" {
  let src =
    #|function TestView() {
    #|  return (
    #|    <Tree>
    #|      {
    #|        items === undefined
    #|          ? (
    #|              <TreeItem itemType='leaf'>
    #|                <TreeItemLayout>Missing</TreeItemLayout>
    #|              </TreeItem>
    #|            )
    #|          : <>
    #|              {items.map((run, idx) => {
    #|                const key = `${idx}`;
    #|                return (
    #|                  <div key={key} ref={el => refs.current[idx] = el!}>
    #|                    <TreeItem
    #|                      itemType='branch'
    #|                      open={open[idx]}
    #|                      onOpenChange={() => updateNth(idx, !open[idx])}
    #|                    >
    #|                      <TreeItemLayout
    #|                        iconBefore={run.score === undefined ? undefined : <Badge>{run.score}</Badge>}
    #|                      >
    #|                        Test Run # {idx + 1}
    #|                      </TreeItemLayout>
    #|                    </TreeItem>
    #|                  </div>
    #|                );
    #|              })}
    #|            </>
    #|      }
    #|    </Tree>
    #|  );
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse real-world exported tsx observer with mapped option children" {
  let src =
    #|type Props = {
    #|  simulationRunsProvider: SimulationRunsProvider;
    #|  outputFolderName: string;
    #|  onChange: (selected: string | undefined) => void;
    #|  disabled?: boolean;
    #|};
    #|
    #|export const CurrentRunPicker = mobxlite.observer(({ simulationRunsProvider, onChange, disabled, outputFolderName }: Props) => {
    #|  const [isRenameDialogOpen, setIsRenameDialogOpen] = React.useState(false);
    #|  const [newName, setNewName] = React.useState('');
    #|  const [runToRename, setRunToRename] = React.useState<string>('');
    #|
    #|  const handleRenameClick = (runName: string) => {
    #|    setRunToRename(runName);
    #|    setNewName(runName);
    #|    setIsRenameDialogOpen(true);
    #|  };
    #|
    #|  return (
    #|    <div className={styles.root}>
    #|      <Dropdown
    #|        selectedOptions={[outputFolderName]}
    #|        onOptionSelect={(_e: SelectionEvents, { optionValue }: OptionOnSelectData) => onChange(optionValue)}
    #|      >
    #|        {simulationRunsProvider.runs.map((run) => (
    #|          <Option key={run.name} value={run.name} text={run.friendlyName}>
    #|            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', width: '100%' }}>
    #|              <span>{run.friendlyName}</span>
    #|              <Button
    #|                icon={<Edit16Regular />}
    #|                onClick={(e) => {
    #|                  e.stopPropagation();
    #|                  handleRenameClick(run.name);
    #|                }}
    #|              >Rename ↵</Button>
    #|            </div>
    #|          </Option>
    #|        ))}
    #|      </Dropdown>
    #|      <Dialog open={isRenameDialogOpen} onOpenChange={(_, { open }) => setIsRenameDialogOpen(open)}>
    #|        <DialogSurface />
    #|      </Dialog>
    #|    </div>
    #|  );
    #|});
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
  assert_eq(module_.exports.length(), 1)
}

///|
test "parser: parse real-world exported tsx tree view with ternary fragment branch" {
  let src =
    #|type Props = {
    #|  test: ISimulationTest;
    #|  runner: SimulationRunner;
    #|  runnerOptions: RunnerOptions;
    #|  nesExternalOptions: NesExternalOptions;
    #|  testSource: TestSourceValue;
    #|  displayOptions: DisplayOptions;
    #|};
    #|
    #|export const TestView = mobxlite.observer(({ test, runner, runnerOptions, nesExternalOptions, testSource, displayOptions }: Props) => {
    #|  const [isTestRunOpen, setIsTestRunOpen] = React.useState(new Array(test.runnerStatus?.runs.length).fill(test.runnerStatus?.runs.length === 1 ? true : false));
    #|  const testItemRefs = React.useRef<HTMLDivElement[]>([]);
    #|
    #|  const updateNth = (n: number, value: boolean) => {
    #|    const copy = Array.from(isTestRunOpen);
    #|    copy[n] = value;
    #|    setIsTestRunOpen(copy);
    #|  };
    #|
    #|  return (
    #|    <TreeItem itemType={'branch'} className='test-runs-container'>
    #|      <TreeItemLayout
    #|        iconBefore={<StatusIcon runner={runner} runnerOptions={runnerOptions} nesExternalOptions={nesExternalOptions} testSource={testSource} test={test} />}
    #|        iconAfter={test.runnerStatus && <RunsSummaryBadge runs={test.runnerStatus.runs} />}
    #|      >
    #|        <Text>{test.suiteName ? test.name.replace(test.suiteName, '') : test.name}</Text>
    #|      </TreeItemLayout>
    #|      <Tree>
    #|        {
    #|          test.runnerStatus === undefined
    #|            ? (
    #|                <TreeItem itemType='leaf'>
    #|                  <TreeItemLayout> Test doesn't have run info. </TreeItemLayout>
    #|                </TreeItem>
    #|              )
    #|            : <>
    #|                {test.runnerStatus.runs.map((run, idx) => {
    #|                  const key = `${test.name}-${idx}`;
    #|                  return (
    #|                    <div key={key} ref={el => testItemRefs.current[idx] = el!}>
    #|                      <TreeItem
    #|                        itemType='branch'
    #|                        open={isTestRunOpen[idx]}
    #|                        onOpenChange={() => updateNth(idx, !isTestRunOpen[idx])}
    #|                      >
    #|                        <TreeItemLayout
    #|                          iconBefore={run.explicitScore === undefined ? undefined : <Badge>{run.explicitScore}</Badge>}
    #|                          iconAfter={<RunSummaryBadge run={run} baseline={test.baseline?.runs[idx]} />}
    #|                        >
    #|                          Test Run # {idx + 1}
    #|                        </TreeItemLayout>
    #|                      </TreeItem>
    #|                    </div>
    #|                  );
    #|                })}
    #|              </>
    #|        }
    #|      </Tree>
    #|    </TreeItem>
    #|  );
    #|});
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
  assert_eq(module_.exports.length(), 1)
}

///|
test "parser: parse tsx tag with nested self-closing reference and jsx arrow child" {
  let src =
    #|function renderMatch() {
    #|  return <Tag name='match' attrs={{
    #|    path: this.promptPathRepresentationService.getFilePath(uri),
    #|    line: rangeInDocument.start.line + 1,
    #|  }}>
    #|    <references value={[new PromptReference(new Location(this.props.uri, rangeInDocument), undefined, { isFromTool: true })]} />
    #|    {toPreviewLines.map((line, i) =>
    #|      <TextChunk priority={FIND_FILES_START_PRIORITY - Math.abs(i - center)}>
    #|        {line}
    #|      </TextChunk>
    #|    )}
    #|  </Tag>;
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse tsx conditional fragments with markdown-like text and br tags" {
  let src =
    #|function renderMemoryPrompt() {
    #|  return <Tag name='memoryInstructions'>
    #|    As you work, consult your memory files to build on previous experience. When you encounter a mistake that seems like it could be common, check your memory for relevant notes — and if nothing is written yet, record what you learned.<br />
    #|    <br />
    #|    <Tag name='memoryScopes'>
    #|      Memory is organized into the scopes defined below:<br />
    #|      {enableMemoryTool && <>- **User memory** (`/memories/`): Persistent notes that survive across all workspaces and conversations.<br /></>}
    #|      {enableCopilotMemory && <>- **Repository memory** (`/memories/repo/`): Repository-scoped facts stored via Copilot.<br /></>}
    #|    </Tag>
    #|  </Tag>;
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse tsx expression with comment apostrophe inside braces" {
  let src =
    #|function render() {
    #|  return <>
    #|    {items.flatMap(result => {
    #|      // don't lose brace sync inside jsx source scanner
    #|      return result.ranges.map(rangeInfo => <FindMatch uri={result.uri} />);
    #|    })}
    #|  </>;
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse tsx conditional fragment with apostrophe text" {
  let src =
    #|function render() {
    #|  return <Tag>
    #|    {enabled && <>If you're here, use `/memories/repo/`.<br /></>}
    #|  </Tag>;
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: allow ASI before delete statement" {
  let src =
    #|function f() {
    #|  expect(aborted).toBeTruthy()
    #|  delete global.Bun
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: skip block-local type alias without semicolon" {
  let src =
    #|function f() {
    #|  type Expected = MiddlewareHandler<any, string, {}, Response>
    #|  type _verify = Expect<Equal<Expected, typeof middleware>>
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: skip callback-local type alias without semicolon" {
  let src =
    #|it('x', async () => {
    #|  const middleware = createMiddleware(async (c, next) => {
    #|    await next()
    #|  })
    #|  type Expected = MiddlewareHandler<any, string, {}, Response>
    #|  type _verify = Expect<Equal<Expected, typeof middleware>>
    #|})
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse nested template literal inside template expression" {
  let src =
    #|function shellQuote(value: string): string {
    #|  return `'${value.replace(/'/g, `"'"`)}'`;
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.funcs.length(), 1)
}

///|
test "parser: skip plain enum declaration in statement position" {
  let src =
    #|enum FileType {
    #|  Unknown = 0,
    #|}
  let stmt = parse_stmt_from(src)
  match stmt {
    Empty => ()
    _ => fail("expected enum declaration to be skipped")
  }
}

///|
test "parser: parse plain enum declaration in ts module block" {
  let src =
    #|enum FileType {
    #|  Unknown = 0,
    #|  File = 1,
    #|}
    #|const value = 1;
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.enums.length(), 1)
  assert_eq(module_.enums[0].name, "FileType")
  assert_false(module_.enums[0].is_const)
  assert_false(module_.enums[0].is_declare)
  assert_eq(module_.enums[0].members.length(), 2)
  assert_eq(
    module_.enums[0].members[1].value,
    Some(@ast.TsEnumMemberValue::Number("1")),
  )
  assert_eq(module_.block.stmts.length(), 0)
}

///|
test "parser: parse declare enum declaration in ts module block" {
  let src =
    #|declare enum Mode {
    #|  Read = "read",
    #|  Write = "write",
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.enums.length(), 1)
  assert_eq(module_.enums[0].name, "Mode")
  assert_false(module_.enums[0].is_const)
  assert_true(module_.enums[0].is_declare)
  assert_eq(module_.enums[0].members.length(), 2)
  assert_eq(
    module_.enums[0].members[0].value,
    Some(@ast.TsEnumMemberValue::String("read")),
  )
}

///|
test "parser: parse export declare enum declaration in ts module block" {
  let src =
    #|export declare enum Mode {
    #|  Read = "read",
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.enums.length(), 1)
  assert_eq(module_.enums[0].name, "Mode")
  assert_true(module_.enums[0].is_declare)
  assert_eq(module_.exports.length(), 1)
  assert_eq(module_.exports[0].export_name, "Mode")
}

///|
test "parser: parse class implements clause" {
  let src =
    #|class MFS implements RemoteFileSystem {
    #|  constructor() {}
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse constructor parameter properties" {
  let src =
    #|class Runner {
    #|  constructor(
    #|    private readonly deps: RunnerDeps,
    #|    protected name?: string,
    #|  ) {}
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse interface field named number" {
  let src =
    #|export interface GitHubIssue {
    #|  number: number;
    #|  title: string;
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.exports.length(), 1)
}

///|
test "parser: parse export async function in module block" {
  let src =
    #|export async function detect(): Promise<void> {
    #|  return;
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
  assert_eq(module_.exports.length(), 1)
}

///|
test "parser: parse class optional field and generic method" {
  let src =
    #|class Store {
    #|  private currentSessionId?: string;
    #|  private withLock<T>(fn: () => T): T {
    #|    return fn();
    #|  }
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
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
test "parser: parse tagged template with nested html property binding" {
  let src =
    #|const view = html`${options.map((value) => {
    #|  const checked = selectedSet.has(normalizeQueryText(value));
    #|  return html`
    #|    <label class="usage-filter-option">
    #|      <input .checked=${checked} />
    #|      <span>${value}</span>
    #|    </label>
    #|  `;
    #|})}`;
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("view"), _, _) => ()
    _ => fail("expected const declaration with nested html property binding")
  }
}

///|
test "parser: parse tagged template with iife and nested html" {
  let src =
    #|const chart = html`${(() => {
    #|  const total = segments.reduce((sum, seg) => sum + seg.value, 0) || 1;
    #|  return segments.map(
    #|    (seg) => html`<div style="height: ${(seg.value / total) * 100}%"></div>`,
    #|  );
    #|})()}`;
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("chart"), _, _) => ()
    _ => fail("expected const declaration with template-expression iife")
  }
}

///|
test "parser: parse ternary branch with parenthesized as cast" {
  let src =
    #|const obj =
    #|  fallback && typeof fallback === "object" && !Array.isArray(fallback)
    #|    ? (fallback as Record<string, unknown>)
    #|    : {};
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("obj"), _, _) => ()
    _ => fail("expected const declaration with ternary as-cast branch")
  }
}

///|
test "parser: parse tagged template event callback with checked cast" {
  let src =
    #|const view = html`
    #|  <input
    #|    @change=${(e: Event) => onPatch(path, (e.target as HTMLInputElement).checked)}
    #|  />
    #|`;
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("view"), _, _) => ()
    _ => fail("expected const declaration with checked cast callback")
  }
}

///|
test "parser: parse tagged template event callback with union literal cast" {
  let src =
    #|const view = html`
    #|  <select
    #|    @change=${(e: Event) =>
    #|      props.onTimeZoneChange((e.target as HTMLSelectElement).value as "local" | "utc")}
    #|  ></select>
    #|`;
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("view"), _, _) => ()
    _ => fail("expected const declaration with union-literal cast callback")
  }
}

///|
test "parser: parse chained filter with type predicate and call body" {
  let src =
    #|const recentEntries = recentSessions
    #|  .map((key) => sessionMap.get(key))
    #|  .filter((entry): entry is UsageSessionEntry => Boolean(entry));
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("recentEntries"), _, _) => ()
    _ => fail("expected const declaration with chained type-predicate filter")
  }
}

///|
test "parser: parse ternary parenthesized optional chain before later arrow" {
  let src =
    #|const valA = isTokenMode ? (a.usage?.totalTokens ?? 0) : (a.usage?.totalCost ?? 0);
    #|const later = props.items.map((item) => item);
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("valA"), _, _) => ()
    _ => fail("expected const declaration with ternary optional-chain branch")
  }
}

///|
test "parser: parse ternary parenthesized as cast before later arrow" {
  let src =
    #|const obj =
    #|  cond
    #|    ? (fallback as Record<string, unknown>)
    #|    : {};
    #|const later = entries.map((entry) => entry);
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("obj"), _, _) => ()
    _ =>
      fail(
        "expected const declaration with ternary as-cast branch before later arrow",
      )
  }
}

///|
test "parser: parse ternary parenthesized call before later arrow" {
  let src =
    #|const label =
    #|  stats.durationCount > 0
    #|    ? (formatDurationCompact(stats.avgDurationMs, { spaced: true }) ?? "—")
    #|    : "—";
    #|const later = values.map((value) => value);
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("label"), _, _) => ()
    _ =>
      fail(
        "expected const declaration with ternary call branch before later arrow",
      )
  }
}

///|
test "parser: parse import with json attributes" {
  let src =
    #|import rawConfig from "./tool-display.json" with { type: "json" };
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.imports.length(), 1)
}

///|
test "parser: parse generic arrow function const initializer" {
  let src =
    #|const filterSessionsByQuery = <TSession extends UsageSessionQueryTarget>(
    #|  sessions: TSession[],
    #|  query: string,
    #|): UsageQueryResult<TSession> => {
    #|  return { sessions, warnings: [] };
    #|};
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("filterSessionsByQuery"), _, _) => ()
    _ => fail("expected const declaration with generic arrow initializer")
  }
}

///|
test "parser: parse definite assignment assertion in let declaration" {
  let src = "let onClosed!: () => void;"
  let stmt = parse_stmt_from(src)
  match stmt {
    Let(@ast.TsBinding::Ident("onClosed"), _, _) => ()
    _ => fail("expected let declaration with definite assignment assertion")
  }
}

///|
test "parser: parse method chain starting on next line" {
  let src =
    #|program
    #|  .command("message")
    #|  .command("send")
    #|  .action(async () => {});
  let stmt = parse_stmt_from(src)
  match stmt {
    Expr(_) => ()
    _ => fail("expected expression statement with multiline method chain")
  }
}

///|
test "parser: parse contextual keyword variable reference from" {
  let src =
    #|const from = "user";
    #|const payload = { from };
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("from"), _, _) => ()
    _ => fail("expected const declaration using contextual keyword identifier")
  }
}

///|
test "parser: parse generic class declaration" {
  let src =
    #|class DirectoryCache<T> {
    #|  private readonly cache = new Map<string, T>();
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse class extends generic base" {
  let src =
    #|class ExecApprovalActionRow extends Row<Button> {
    #|  constructor() {}
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse class extends qualified base" {
  let src =
    #|class MockModelRegistry extends actual.ModelRegistry {
    #|  constructor() {}
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse async generic arrow function initializer" {
  let src =
    #|const withTimeout = async <T>(
    #|  work: Promise<T>,
    #|  fallback: T,
    #|): Promise<T> => {
    #|  return fallback;
    #|};
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("withTimeout"), _, _) => ()
    _ => fail("expected const declaration with async generic arrow initializer")
  }
}

///|
test "parser: parse multiline type predicate with union after is" {
  let src =
    #|const cred = profiles.find(
    #|  (
    #|    profile,
    #|  ): profile is
    #|    | { type: "api_key"; provider: string; key: string }
    #|    | { type: "token"; provider: string; token: string } =>
    #|    profile?.type === "api_key" || profile?.type === "token",
    #|);
  let stmt = parse_stmt_from(src)
  match stmt {
    Const(@ast.TsBinding::Ident("cred"), _, _) => ()
    _ => fail("expected const declaration with multiline union type predicate")
  }
}

///|
test "parser: parse abstract class modifiers and abstract method signatures" {
  let src =
    #|abstract class MemoryManagerSyncOps {
    #|  protected abstract readonly cfg: OpenClawConfig;
    #|  protected abstract sync(params?: {
    #|    reason?: string;
    #|    force?: boolean;
    #|  }): Promise<void>;
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse parameter named override and optional override" {
  let src =
    #|function mergeRecord<T>(
    #|  base?: Record<string, T>,
    #|  override?: Record<string, T>,
    #|): Record<string, T> | undefined {
    #|  return override;
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse for loop with parenthesized bitwise condition" {
  let src =
    #|for (let expMask = 0x4000; (sample & expMask) === 0 && exponent > 0; exponent--) {
    #|  expMask >>= 1;
    #|}
  let stmt = parse_stmt_from(src)
  match stmt {
    For(Some(_), Some(_), Some(_), _) => ()
    _ => fail("expected for statement with bounded condition parsing")
  }
}

///|
test "parser: parse nested shift expression after for loop" {
  let src =
    #|function linearToMulaw(sample: number): number {
    #|  for (let i = 0; i < 1; i++) {
    #|  }
    #|  const mantissa = (sample >> (1 + 3));
    #|  return mantissa;
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse generator iife return call" {
  let src =
    #|function chunkAudio(audio: Buffer, chunkSize = 160): Generator<Buffer, void, unknown> {
    #|  return (function* () {
    #|    for (let i = 0; i < audio.length; i += chunkSize) {
    #|      yield audio.subarray(i, Math.min(i + chunkSize, audio.length));
    #|    }
    #|  })();
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: while statement does not consume following complex if" {
  let src =
    #|while (index < input.length && (input[index] === " " || input[index] === "\t")) {
    #|  index += 1;
    #|}
    #|if (input.slice(index, index + 9).toLowerCase() === "arguments") {
    #|  index += 9;
    #|}
    #|const lastOpen = openMatches[openMatches.length - 1];
    #|const lastClose = closeMatches[closeMatches.length - 1];
    #|if (lastClose && lastClose.index > (lastOpen.index ?? -1)) {
    #|  return closed;
    #|}
  let parser = Parser::from_source(src)
  parser.in_function = true
  parser.in_iteration = true
  let stmt = parser.parse_stmt() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  match stmt {
    While(_, _) => ()
    _ => fail("expected while statement")
  }
  assert_eq(parser.peek().kind, If)
}

///|
test "parser: block does not consume following complex if" {
  let src =
    #|{
    #|  index += 1;
    #|}
    #|if (lastClose && lastClose.index > (lastOpen.index ?? -1)) {
    #|  return closed;
    #|}
  let parser = Parser::from_source(src)
  parser.in_function = true
  let block = parser.parse_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(block.stmts.length(), 1)
  assert_eq(parser.peek().kind, If)
}

///|
test "parser: iteration block does not consume following complex if" {
  let src =
    #|{
    #|  index += 1;
    #|}
    #|if (input.slice(index, index + 9).toLowerCase() === "arguments") {
    #|  index += 9;
    #|}
    #|const lastOpen = openMatches[openMatches.length - 1];
    #|const lastClose = closeMatches[closeMatches.length - 1];
    #|if (lastClose && lastClose.index > (lastOpen.index ?? -1)) {
    #|  return closed;
    #|}
  let parser = Parser::from_source(src)
  parser.in_function = true
  parser.in_iteration = true
  let block = parser.parse_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(block.stmts.length(), 1)
  assert_eq(parser.peek().kind, If)
}

///|
test "parser: parse openclaw thinking helpers module block" {
  let src =
    #|export function formatReasoningMessage(text: string): string {
    #|  const trimmed = text.trim();
    #|  if (!trimmed) {
    #|    return "";
    #|  }
    #|  const italicLines = trimmed
    #|    .split("\n")
    #|    .map((line) => (line ? `_${line}_` : line))
    #|    .join("\n");
    #|  return `Reasoning:\n${italicLines}`;
    #|}
    #|
    #|type ThinkTaggedSplitBlock =
    #|  | { type: "thinking"; thinking: string }
    #|  | { type: "text"; text: string };
    #|
    #|export function splitThinkingTaggedText(text: string): ThinkTaggedSplitBlock[] | null {
    #|  const trimmedStart = text.trimStart();
    #|  if (!trimmedStart.startsWith("<")) {
    #|    return null;
    #|  }
    #|  const openRe = /<\s*(?:think(?:ing)?|thought|antthinking)\s*>/i;
    #|  const closeRe = /<\s*\/\s*(?:think(?:ing)?|thought|antthinking)\s*>/i;
    #|  if (!openRe.test(trimmedStart)) {
    #|    return null;
    #|  }
    #|  if (!closeRe.test(text)) {
    #|    return null;
    #|  }
    #|
    #|  const scanRe = /<\s*(\/?)\s*(?:think(?:ing)?|thought|antthinking)\s*>/gi;
    #|  let inThinking = false;
    #|  let cursor = 0;
    #|  let thinkingStart = 0;
    #|  const blocks: ThinkTaggedSplitBlock[] = [];
    #|
    #|  const pushText = (value: string) => {
    #|    if (!value) {
    #|      return;
    #|    }
    #|    blocks.push({ type: "text", text: value });
    #|  };
    #|  const pushThinking = (value: string) => {
    #|    const cleaned = value.trim();
    #|    if (!cleaned) {
    #|      return;
    #|    }
    #|    blocks.push({ type: "thinking", thinking: cleaned });
    #|  };
    #|
    #|  for (const match of text.matchAll(scanRe)) {
    #|    const index = match.index ?? 0;
    #|    const isClose = Boolean(match[1]?.includes("/"));
    #|
    #|    if (!inThinking && !isClose) {
    #|      pushText(text.slice(cursor, index));
    #|      thinkingStart = index + match[0].length;
    #|      inThinking = true;
    #|      continue;
    #|    }
    #|
    #|    if (inThinking && isClose) {
    #|      pushThinking(text.slice(thinkingStart, index));
    #|      cursor = index + match[0].length;
    #|      inThinking = false;
    #|    }
    #|  }
    #|
    #|  if (inThinking) {
    #|    return null;
    #|  }
    #|  pushText(text.slice(cursor));
    #|
    #|  const hasThinking = blocks.some((b) => b.type === "thinking");
    #|  if (!hasThinking) {
    #|    return null;
    #|  }
    #|  return blocks;
    #|}
    #|
    #|export function extractThinkingFromTaggedStream(text: string): string {
    #|  if (!text) {
    #|    return "";
    #|  }
    #|  const openRe = /<\s*(?:think(?:ing)?|thought|antthinking)\s*>/gi;
    #|  const closeRe = /<\s*\/\s*(?:think(?:ing)?|thought|antthinking)\s*>/gi;
    #|  const openMatches = [...text.matchAll(openRe)];
    #|  if (openMatches.length === 0) {
    #|    return "";
    #|  }
    #|  const closeMatches = [...text.matchAll(closeRe)];
    #|  const lastOpen = openMatches[openMatches.length - 1];
    #|  const lastClose = closeMatches[closeMatches.length - 1];
    #|  if (lastClose && (lastClose.index ?? -1) > (lastOpen.index ?? -1)) {
    #|    return "";
    #|  }
    #|  const start = (lastOpen.index ?? 0) + lastOpen[0].length;
    #|  return text.slice(start).trim();
    #|}
    #|
    #|export function inferToolMetaFromArgs(toolName: string, args: unknown): string | undefined {
    #|  return toolName ? "" : undefined;
    #|}
  let module_ = Parser::from_source(src).parse_module_block() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.block.stmts.length(), 4)
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
    ArrowFunc(params, _, ArrowExpr(BinOp(Add, Var("x"), IntLit(1))), _) =>
      assert_eq(params.length(), 1)
    _ => fail("expected ArrowFunc (expr)")
  }
  match parse_expr_from("(x) => { return x; }") {
    ArrowFunc(_, _, ArrowBlock(block), _) => assert_eq(block.stmts.length(), 1)
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

///|
test "parser: parse nested generic angle bracket type assertion when jsx disabled" {
  let src = "const value = <CancelablePromise<T>>new class { cancel() {} };"
  let stmt = Parser::from_source_with_jsx(src, false).parse_stmt() catch {
    e => fail("expected nested generic type assertion to parse: \{e}")
  }
  match stmt {
    Const(@ast.TsBinding::Ident("value"), _, _) => ()
    _ => fail("expected const statement")
  }
}

///|
test "parser: parse tuple angle bracket type assertion inside parens when jsx disabled" {
  let src = "const arr = (<[K, V][]>values).slice(0);"
  let stmt = Parser::from_source_with_jsx(src, false).parse_stmt() catch {
    e => fail("expected tuple type assertion to parse: \{e}")
  }
  match stmt {
    Const(@ast.TsBinding::Ident("arr"), _, _) => ()
    _ => fail("expected const statement")
  }
}

///|
test "parser: parse asserted equality expression" {
  // `x as T === y` — the `as` survives as an `As(...)` wrapper on the LHS
  // of the equality.
  match parse_expr_from("this._state as AutorunState === AutorunState.stale") {
    BinOp(
      BinEq,
      @ast.TsExpr::As(PropAccess(Var("this"), "_state"), _),
      PropAccess(Var("AutorunState"), "stale")
    ) => ()
    expr => fail("expected asserted equality, got \{expr}")
  }
}

///|
test "parser: parse declare class method with destructured parameter" {
  let src = "declare class Renderer { code({ text, lang, escaped }: Tokens.Code): string; }"
  let module_ = Parser::from_source(src).parse_module() catch {
    e =>
      fail("expected declare class with destructured parameter to parse: \{e}")
  }
  assert_eq(module_.classes.length(), 1)
  let class_ = module_.classes[0]
  assert_eq(class_.methods.length(), 1)
  let method_ = class_.methods[0]
  assert_eq(method_.name, "code")
  assert_eq(method_.params.length(), 1)
}

///|
test "parser: parse function type with destructured parameter" {
  let src =
    #|export declare const escape: (s: string, { windowsPathsNoEscape, magicalBraces, }?: Pick<MinimatchOptions, "windowsPathsNoEscape" | "magicalBraces">) => string;
  let module_ = Parser::from_source(src).parse_module() catch {
    e =>
      fail("expected function type with destructured parameter to parse: \{e}")
  }
  assert_eq(module_.values.length(), 1)
  assert_eq(module_.values[0].name, "escape")
  match module_.values[0].type_ {
    @ast.TsType::Func(params, @ast.TsType::String_) =>
      assert_eq(params.length(), 2)
    other => fail("expected function type, got \{other}")
  }
}

///|
test "parser: parse interface call signature with typed parameters" {
  let src =
    #|export interface GenericGetKeyFunction<IProtectedHeader, IToken, ReturnKeyTypes> {
    #|  (protectedHeader: IProtectedHeader, token: IToken): Promise<ReturnKeyTypes> | ReturnKeyTypes
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected interface call signature to parse: \{e}")
  }
  assert_eq(module_.interfaces.length(), 1)
  assert_eq(module_.interfaces[0].fields.length(), 1)
  assert_eq(module_.interfaces[0].fields[0].0, "<call>")
}

///|
test "parser: parse array field followed by index signature on next line" {
  let src =
    #|export interface HeaderParameters {
    #|  crit?: string[]
    #|  [propName: string]: unknown
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected array field followed by index signature to parse: \{e}")
  }
  assert_eq(module_.interfaces.length(), 1)
  // Index signatures (`[propName: string]: unknown`) are now retained on the
  // dedicated `index_signatures` channel with their key/value types preserved,
  // so bridge passes can lower them to `op_get` / `op_set` accessors without
  // contaminating the regular named-field walk.
  assert_eq(module_.interfaces[0].fields.length(), 1)
  assert_eq(module_.interfaces[0].fields[0].0, "crit")
  assert_eq(module_.interfaces[0].index_signatures.length(), 1)
  assert_eq(module_.interfaces[0].index_signatures[0].0, @ast.TsType::String_)
  assert_eq(module_.interfaces[0].index_signatures[0].1, @ast.TsType::Any)
}

///|
test "parser: parse constructor parameter decorator" {
  let src = "class App { constructor(@IInstantiationService private readonly service: IInstantiationService) {} }"
  let stmt = Parser::from_source(src).parse_stmt() catch {
    e => fail("expected constructor parameter decorator to parse: \{e}")
  }
  match stmt {
    Let(@ast.TsBinding::Ident("App"), _, _) => ()
    _ => fail("expected class declaration lowering")
  }
}

///|
test "parser: parse anonymous class extending generic call expression" {
  let src = "const vm = new class extends mock<IViewModel>() { override onDidChange() {} };"
  let stmt = Parser::from_source_with_jsx(src, false).parse_stmt() catch {
    e => fail("expected class extends generic call expression to parse: \{e}")
  }
  match stmt {
    Const(@ast.TsBinding::Ident("vm"), _, _) => ()
    _ => fail("expected const statement")
  }
}

///|
test "parser: parse class generic method named get" {
  let src = "class Options { public get<T extends EditorOption>(id: T): T { return id; } }"
  let stmt = Parser::from_source(src).parse_stmt() catch {
    e => fail("expected generic class method named get to parse: \{e}")
  }
  match stmt {
    Let(@ast.TsBinding::Ident("Options"), _, _) => ()
    _ => fail("expected class declaration lowering")
  }
}

///|
test "parser: parse property access with true identifier" {
  let expr = Parser::from_source("ContextKeyExpr.true()").parse_expr() catch {
    e => fail("expected property access with true identifier to parse: \{e}")
  }
  match expr {
    MethodCall(Var("ContextKeyExpr"), "true", args) =>
      assert_eq(args.length(), 0)
    expr => fail("expected method call on .true, got \{expr}")
  }
}

///|
test "parser: parse function declaration named boolean" {
  let func = Parser::from_source(
    "function boolean(value: unknown, defaultValue: boolean): boolean { return Boolean(value); }",
  ).parse_function() catch {
    e => fail("expected function named boolean to parse: \{e}")
  }
  assert_eq(func.name, "boolean")
  assert_eq(func.params.length(), 2)
}

///|
test "parser: parse class static method named string" {
  let src = "class EditorStringOption { public static string(value: unknown, defaultValue: string): string { return value as string; } }"
  let stmt = Parser::from_source(src).parse_stmt() catch {
    e => fail("expected class static method named string to parse: \{e}")
  }
  match stmt {
    Let(@ast.TsBinding::Ident("EditorStringOption"), _, _) => ()
    _ => fail("expected class declaration lowering")
  }
}

///|
test "parser: parse class getter without parens" {
  let src = "class TestProvider { override get capabilities(): FileSystemProviderCapabilities { return caps; } }"
  let stmt = Parser::from_source(src).parse_stmt() catch {
    e => fail("expected class getter without parens to parse: \{e}")
  }
  match stmt {
    Let(@ast.TsBinding::Ident("TestProvider"), _, _) => ()
    _ => fail("expected class declaration lowering")
  }
}

///|
test "parser: parse parameter type with union member intersection" {
  let func = Parser::from_source(
    "function toFileStat(stat: IStat | { type: FileType } & Partial<IStat>): void {}",
  ).parse_function() catch {
    e =>
      fail("expected union member intersection parameter type to parse: \{e}")
  }
  assert_eq(func.name, "toFileStat")
  assert_eq(func.params.length(), 1)
}

///|
test "parser: parse class field named readonly" {
  let src = "class TestProvider { private readonly: boolean = false; }"
  let stmt = Parser::from_source(src).parse_stmt() catch {
    e => fail("expected class field named readonly to parse: \{e}")
  }
  match stmt {
    Let(@ast.TsBinding::Ident("TestProvider"), _, _) => ()
    _ => fail("expected class declaration lowering")
  }
}

///|
test "parser: parse class static method named false" {
  let src = "class ContextKeyExpr { public static false(): ContextKeyExpression { return value; } }"
  let stmt = Parser::from_source(src).parse_stmt() catch {
    e => fail("expected class static method named false to parse: \{e}")
  }
  match stmt {
    Let(@ast.TsBinding::Ident("ContextKeyExpr"), _, _) => ()
    _ => fail("expected class declaration lowering")
  }
}

///|
test "parser: parse instantiation expression as call argument" {
  let src = "const widget = createInstance(PostEditWidget<T>, editor, range);"
  let stmt = Parser::from_source_with_jsx(src, false).parse_stmt() catch {
    e => fail("expected instantiation expression argument to parse: \{e}")
  }
  match stmt {
    Const(@ast.TsBinding::Ident("widget"), _, _) => ()
    _ => fail("expected const statement")
  }
}

///|
test "parser: parse nested instantiation expression with multiple type args" {
  let src = "const tree = createInstance(WorkbenchObjectTree<IQuickPickElement, void>, container);"
  let stmt = Parser::from_source_with_jsx(src, false).parse_stmt() catch {
    e =>
      fail(
        "expected nested instantiation expression with multiple type args to parse: \{e}",
      )
  }
  match stmt {
    Const(@ast.TsBinding::Ident("tree"), _, _) => ()
    _ => fail("expected const statement")
  }
}

///|
test "parser: parse asserted logical or chain" {
  match
    parse_expr_from(
      "node.name?.value as string || node.value?.value as string || ''",
    ) {
    BinOp(Or, _, _) => ()
    expr => fail("expected logical-or chain after assertions, got \{expr}")
  }
}

///|
test "parser: parse object literal generic set method" {
  let stmt = Parser::from_source_with_jsx(
    "const rpc = { set<T, R extends T>(identifier: ProxyIdentifier<T>, value: R): R { return value; } };",
    false,
  ).parse_stmt() catch {
    e => fail("expected object literal generic set method to parse: \{e}")
  }
  match stmt {
    Const(@ast.TsBinding::Ident("rpc"), _, _) => ()
    _ => fail("expected const statement")
  }
}

///|
test "parser: parse object literal async delete method" {
  let stmt = Parser::from_source_with_jsx(
    "const fs = { async delete(uri: Uri): Promise<void> { return value; } };", false,
  ).parse_stmt() catch {
    e => fail("expected object literal async delete method to parse: \{e}")
  }
  match stmt {
    Const(@ast.TsBinding::Ident("fs"), _, _) => ()
    _ => fail("expected const statement")
  }
}

///|
test "parser: parse class static method named of" {
  let stmt = Parser::from_source(
    "class Range { static of(obj: Range): Range { return obj; } }",
  ).parse_stmt() catch {
    e => fail("expected class static method named of to parse: \{e}")
  }
  match stmt {
    Let(@ast.TsBinding::Ident("Range"), _, _) => ()
    _ => fail("expected class declaration lowering")
  }
}

///|
test "parser: parse object literal property named null" {
  let stmt = Parser::from_source_with_jsx(
    "const variables = { null: null, empty: '' };", false,
  ).parse_stmt() catch {
    e => fail("expected object literal property named null to parse: \{e}")
  }
  match stmt {
    Const(@ast.TsBinding::Ident("variables"), _, _) => ()
    _ => fail("expected const statement")
  }
}

///|
test "parser: parse object literal generic getProxy method" {
  let stmt = Parser::from_source_with_jsx(
    "const rpc = { getProxy<T>(): T { return thing; } };", false,
  ).parse_stmt() catch {
    e => fail("expected object literal generic getProxy method to parse: \{e}")
  }
  match stmt {
    Const(@ast.TsBinding::Ident("rpc"), _, _) => ()
    _ => fail("expected const statement")
  }
}

///|
test "parser: parse class readonly set function type field" {
  let stmt = Parser::from_source(
    "class Rpc { readonly set: <T, R extends T>(identifier: ProxyIdentifier<T>, instance: R) => R; }",
  ).parse_stmt() catch {
    e => fail("expected readonly set function type field to parse: \{e}")
  }
  match stmt {
    Let(@ast.TsBinding::Ident("Rpc"), _, _) => ()
    _ => fail("expected class declaration lowering")
  }
}

///|
test "parser: parse object literal async arrow with keyword param" {
  let stmt = Parser::from_source_with_jsx(
    "const service = { getDiscoveryInfo: async type => emptyDiscoveryInfo(type) };",
    false,
  ).parse_stmt() catch {
    e => fail("expected async arrow with keyword param to parse: \{e}")
  }
  match stmt {
    Const(@ast.TsBinding::Ident("service"), _, _) => ()
    _ => fail("expected const statement")
  }
}

///|
test "parser: parse type predicate with keyword identifier" {
  let func = Parser::from_source(
    "function isValidPromptType(type: string): type is PromptsType { return true; }",
  ).parse_function() catch {
    e => fail("expected type predicate with keyword identifier to parse: \{e}")
  }
  assert_eq(func.name, "isValidPromptType")
}

///|
test "parser: parse optional chaining generic call" {
  let expr = Parser::from_source_with_jsx(
    "(e.target as HTMLElement)?.closest?.<HTMLElement>(selector)", false,
  ).parse_expr() catch {
    e => fail("expected optional chaining generic call to parse: \{e}")
  }
  // The whole chain is wrapped in `OptionalChain(...)` since at least one
  // `?.` link was present; the inner shape is the conventional
  // `CallExpr` / `MethodCall`.
  match expr {
    @ast.TsExpr::OptionalChain(CallExpr(_, _))
    | @ast.TsExpr::OptionalChain(MethodCall(_, _, _)) => ()
    expr => fail("expected optional chaining generic call, got \{expr}")
  }
}

///|
test "parser: parse interface field named debugger" {
  let module_ = Parser::from_source(
    "export interface IGuessedDebugger { debugger: IDebugger; }",
  ).parse_module() catch {
    e => fail("expected interface field named debugger to parse: \{e}")
  }
  assert_eq(module_.interfaces.length(), 1)
}

///|
test "parser: parse vscode single proxy rpc object literal" {
  let stmt = Parser::from_source_with_jsx(
    "const rpc = { _serviceBrand: undefined, remoteAuthority: null!, getProxy<T>(): T { return thing; }, set<T, R extends T>(identifier: ProxyIdentifier<T>, value: R): R { return value; }, dispose: undefined! };",
    false,
  ).parse_stmt() catch {
    e => fail("expected vscode rpc object literal to parse: \{e}")
  }
  match stmt {
    Const(@ast.TsBinding::Ident("rpc"), _, _) => ()
    _ => fail("expected const statement")
  }
}

///|
test "parser: parse method call with object literal argument" {
  let parser = Parser::from_source_with_jsx(
    "module = module.with({ path: ensureSuffix(module.path, '.js') });", false,
  )
  let stmt = parser.parse_stmt() catch {
    e =>
      fail("expected method call with object literal argument to parse: \{e}")
  }
  if parser.peek().kind != Eof {
    fail("expected EOF, got stmt=\{stmt} next=\{parser.peek().kind}")
  }
}

///|
test "parser: parse interface optional readonly field name" {
  let module_ = Parser::from_source(
    "export interface IDetachedXTermOptions { readonly?: boolean; }",
  ).parse_module() catch {
    e => fail("expected readonly field name in interface to parse: \{e}")
  }
  assert_eq(module_.interfaces.length(), 1)
  assert_eq(module_.interfaces[0].fields[0].0, "readonly")
  assert_eq(module_.interfaces[0].readonly_fields.length(), 0)
}

///|
test "parser: preserves readonly interface field modifiers" {
  let module_ = Parser::from_source(
    "export interface User { readonly id: string; name: string; }",
  ).parse_module() catch {
    e => fail("expected readonly interface field modifier to parse: \{e}")
  }
  assert_eq(module_.interfaces.length(), 1)
  assert_eq(module_.interfaces[0].readonly_fields, ["id"])
}

///|
test "parser: parse const declaration with function type annotation" {
  let module_ = Parser::from_source(
    "export const scaleArrowPoint: (point: RuntimeArrowPoint, factor: number) => RuntimeArrowPoint = (point, factor) => point;",
  ).parse_module_block() catch {
    e => fail("expected const declaration with function type annotation: \{e}")
  }
  assert_eq(module_.exports.length(), 1)
  assert_eq(module_.block.stmts.length(), 1)
}

///|
test "parser: parse angle bracket assertion before empty array literal" {
  let expr = Parser::from_source_with_jsx(
    "<Array<MenuItemAction | SubmenuItemAction | string>>[]", false,
  ).parse_expr() catch {
    e =>
      fail(
        "expected angle bracket assertion before array literal to parse: \{e}",
      )
  }
  match expr {
    ArrayLit(_) => ()
    _ => ()
  }
}

///|
test "parser: parse vscode async generic class method" {
  let src =
    #|class ExtHostExtensionService {
    #|  protected async _loadCommonJSModule<T extends object | undefined>(extension: IExtensionDescription | null, module: URI, activationTimesBuilder: ExtensionActivationTimesBuilder): Promise<T> {
    #|    module = module.with({ path: ensureSuffix(module.path, '.js') });
    #|    const extensionId = extension?.identifier.value;
    #|    const browserUri = URI.revive(await this._mainThreadExtensionsProxy.$asBrowserUri(module));
    #|    const response = await fetch(browserUri.toString(true));
    #|  }
    #|}
  let stmt = Parser::from_source_with_jsx(src, false).parse_stmt() catch {
    e => fail("expected vscode async generic class method to parse: \{e}")
  }
  match stmt {
    Let(@ast.TsBinding::Ident("ExtHostExtensionService"), _, _) => ()
    _ => fail("expected class declaration lowering")
  }
}

///|
test "parser: parse module tolerates top-level implementation classes" {
  let src =
    #|interface ResourceMapKeyFn {
    #|  (resource: URI): string;
    #|}
    #|
    #|class ResourceMapEntry<T> {
    #|  constructor(readonly uri: URI, readonly value: T) { }
    #|}
    #|
    #|abstract class Cache<K, V> {
    #|  abstract trim(newSize: number): void;
    #|}
    #|
    #|export interface PublicStyle {
    #|  id: string;
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected module with top-level classes to parse: \{e}")
  }
  assert_eq(module_.interfaces.length(), 2)
}

///|
test "parser: parse runtime default exported classes into module classes" {
  let src =
    #|export default class Counter {
    #|  count: number
    #|
    #|  constructor(initial: number) {
    #|    this.count = initial
    #|  }
    #|
    #|  inc(delta: number): number {
    #|    return this.count + delta
    #|  }
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e =>
      fail("expected runtime default class to parse into module classes: \{e}")
  }
  assert_eq(module_.classes.length(), 1)
  assert_eq(module_.classes[0].name, "Counter")
  assert_eq(module_.classes[0].methods.length(), 1)
}

///|
test "parser: parse top-level runtime classes for default reexports" {
  let src =
    #|class RuntimeGreeter {
    #|  constructor(label: string) {
    #|    this.label = label
    #|  }
    #|
    #|  greet(name: string): string {
    #|    return `${this.label}, ${name}`
    #|  }
    #|}
    #|
    #|export default RuntimeGreeter
  let module_ = Parser::from_source(src).parse_module() catch {
    e =>
      fail(
        "expected top-level runtime class to be kept for default reexport: \{e}",
      )
  }
  assert_eq(module_.classes.length(), 1)
  assert_eq(module_.classes[0].name, "RuntimeGreeter")
}

///|
test "parser: parse generic tuple item followed by array postfix" {
  let src = "declare function flatten(issues: [BaseIssue<unknown>, ...BaseIssue<unknown>[]]): FlatErrors<undefined>;"
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected generic tuple array postfix to parse: \{e}")
  }
  assert_eq(module_.imports.length(), 1)
}

///|
test "parser: parse ambient class index signature" {
  let src =
    #|export class AxiosHeaders {
    #|  [key: string]: any;
    #|  set(headerName?: string): AxiosHeaders;
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected class index signature to parse: \{e}")
  }
  assert_eq(module_.classes.length(), 1)
}

///|
test "parser: parse named reexport containing declare binding name" {
  let src =
    #|export { ark, declare, define, type, type Ark } from "./keywords/keywords.ts";
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected declare binding name in export list to parse: \{e}")
  }
  assert_eq(module_.funcs.length(), 0)
}

///|
test "parser: parse declare function whose name is a type keyword" {
  let src = "declare function string(): StringSchema<undefined>;"
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected type keyword function name to parse: \{e}")
  }
  assert_eq(module_.imports.length(), 1)
  assert_eq(module_.imports[0].name, "string")
}

///|
test "parser: parse declare function whose name is int keyword" {
  let src = "export declare function int(params?: string): ZodInt;"
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected int keyword function name to parse: \{e}")
  }
  assert_eq(module_.imports.length(), 1)
  assert_eq(module_.imports[0].name, "int")
}

///|
test "parser: parse interface field whose name is int keyword" {
  let src =
    #|export interface NumericFlags {
    #|  int: boolean
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected int keyword field name to parse: \{e}")
  }
  assert_eq(module_.interfaces.length(), 1)
  assert_eq(module_.interfaces[0].fields[0].0, "int")
}

///|
test "parser: parse multiline union before field named is" {
  let src =
    #|export interface HTMLAttributes {
    #|  inputmode?:
    #|    | 'none'
    #|    | 'text'
    #|    | undefined
    #|  is?: string | undefined
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected multiline union before is field to parse: \{e}")
  }
  assert_eq(module_.interfaces.length(), 1)
  assert_eq(module_.interfaces[0].fields.length(), 2)
  assert_eq(module_.interfaces[0].fields[1].0, "is")
}

///|
test "parser: parse exported JSX namespace followed by extending interface" {
  let src =
    #|export namespace JSX {
    #|  export interface IntrinsicElements {
    #|    div: HTMLAttributes
    #|  }
    #|}
    #|
    #|export interface IntrinsicElements extends JSX.IntrinsicElements {}
  let module_block = Parser::from_source(src).parse_module_block() catch {
    e =>
      fail(
        "expected exported JSX namespace and interface extends to parse: \{e}",
      )
  }
  let module_ = Parser::from_source(src).parse_module() catch {
    e =>
      fail(
        "expected exported JSX namespace and interface extends to parse: \{e}",
      )
  }
  assert_eq(module_block.exports.length(), 2)
  assert_eq(module_.interfaces[0].extends_names, ["JSX.IntrinsicElements"])
}

///|
test "parser: preserve declare class extends base names" {
  let src =
    #|import { BaseApp } from "./base"
    #|export declare class App extends BaseApp<Env> {
    #|  constructor()
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected declare class extends to parse: \{e}")
  }
  assert_eq(module_.classes.length(), 1)
  assert_eq(module_.classes[0].base_names, ["BaseApp"])
}

///|
test "parser: parse named export alias to keyword name" {
  let src = "export { function_ as function, null_ as null };"
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected keyword aliases in export list to parse: \{e}")
  }
  assert_eq(module_.funcs.length(), 0)
}

///|
test "parser: parse named export alias to interface keyword" {
  let src = "export { type as interface };"
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected interface keyword alias in export list to parse: \{e}")
  }
  assert_eq(module_.funcs.length(), 0)
}

///|
test "parser: parse qualified type name starting with type keyword" {
  let src = "export type Validator<a> = type.validate<a>;"
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected type-qualified generic name to parse: \{e}")
  }
  assert_eq(module_.interfaces.length(), 0)
}

///|
test "parser: parse declare const with initializer" {
  let src = "declare const extendsToken = \"extends \";"
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected declare const initializer to parse: \{e}")
  }
  assert_eq(module_.values.length(), 1)
  assert_eq(module_.values[0].name, "extendsToken")
}

///|
test "parser: parse declare class member named declare" {
  let src =
    #|export declare class InternalScope {
    #|  declare: () => { type: InternalTypeParser };
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected declare-named class member to parse: \{e}")
  }
  assert_eq(module_.classes.length(), 1)
}

///|
test "parser: parse type alias reference named from" {
  let src =
    #|declare namespace ctx {
    #|  type from<ctx extends MatchParserContext> = ctx;
    #|  type init = from<{ cases: [] }>;
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected from-named type alias reference to parse: \{e}")
  }
  assert_eq(module_.namespaces.length(), 1)
}

///|
test "parser: parse primitive keyword qualified type names" {
  let src =
    #|export declare namespace Ark {
    #|  interface wrapped extends arkPrototypes.wrapped {
    #|    string: string.submodule;
    #|    number: number.submodule;
    #|    object: object.submodule;
    #|    unknown: unknown.submodule;
    #|  }
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected primitive keyword qualified names to parse: \{e}")
  }
  assert_eq(module_.funcs.length(), 0)
}

///|
test "parser: parse namespace named type" {
  let src =
    #|export declare namespace type {
    #|  type infer<def> = inferDefinition<def>;
    #|}
    #|export type type<t = unknown> = Type<t>;
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected namespace named type to parse: \{e}")
  }
  assert_eq(module_.funcs.length(), 0)
}

///|
test "parser: parse optional tuple elements after variadic tuple rest" {
  let src = "export declare function merge<A extends readonly unknown[]>(...sourcesAndConcurrency: [...ObservableInputTuple<A>, number?]): Observable<A[number]>;"
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected optional tuple element after rest to parse: \{e}")
  }
  assert_eq(module_.imports.length(), 1)
}

///|
test "parser: parse generic function type property in interface" {
  let src =
    #|export interface Apply<F> extends Functor<F> {
    #|  readonly ap: <A, B>(fab: HKT<F, (a: A) => B>, fa: HKT<F, A>) => HKT<F, B>
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected generic function type property to parse: \{e}")
  }
  assert_eq(module_.interfaces.length(), 1)
  assert_eq(module_.interfaces[0].fields[0].0, "ap")
}

///|
test "parser: parse semicolonless ambient export const followed by export list" {
  let src =
    #|declare namespace fastify {
    #|  export const errorCodes: FastifyErrorCodes
    #|  export type {
    #|    FastifyErrorCodes
    #|  }
    #|  export const fastify: Fastify
    #|  export { fastify as default }
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected ambient namespace export const to parse: \{e}")
  }
  assert_eq(module_.namespaces.length(), 1)
  assert_eq(module_.namespaces[0].module_.values.length(), 2)
}

///|
test "parser: emit MoonBit declarations uppercases lowercase type names" {
  let src =
    #|export type p = string;
    #|export declare function isMatching(pattern: p): unknown;
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected lowercase type alias surface to parse: \{e}")
  }
  let actual = emit_moonbit_decl(module_)
  assert_true(actual.contains("pub type P = String"))
  assert_true(actual.contains("pattern : P"))
  assert_false(actual.contains("pub type p ="))
  assert_false(actual.contains("pattern : p"))
}

///|
test "parser: emit MoonBit declarations suffixes reserved parameter names" {
  let src =
    #|export interface Is {}
    #|export declare class Type {
    #|  constructor(is: Is)
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected reserved constructor parameter to parse: \{e}")
  }
  let actual = emit_moonbit_decl(module_)
  assert_true(actual.contains("declare pub fn new_type_(is_ : Is) -> Type"))
  assert_false(actual.contains("new_type_(is : Is)"))
}

///|
test "parser: parse bigint literal union types" {
  let src = "export type Falsy = null | undefined | false | 0 | -0 | 0n | '';"
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected bigint literal union type to parse: \{e}")
  }
  assert_eq(module_.funcs.length(), 0)
}

///|
test "parser: parse bigint primitive type" {
  let src = "export type UserId = bigint;"
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected bigint primitive type to parse: \{e}")
  }
  assert_eq(module_.type_aliases.length(), 1)
  assert_eq(module_.type_aliases[0].type_, @ast.TsType::BigInt)
}

///|
test "parser: parse generic curried function return type" {
  let src =
    #|export declare function ap<F extends URIS2, G extends URIS>(
    #|  F: Apply2<F>,
    #|  G: Apply1<G>
    #|): <FE, A>(
    #|  fa: Kind2<F, FE, Kind<G, A>>
    #|) => <B>(fab: Kind2<F, FE, Kind<G, (a: A) => B>>) => Kind2<F, FE, Kind<G, B>>
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected curried generic function return type to parse: \{e}")
  }
  assert_eq(module_.imports.length(), 1)
}

///|
test "parser: parse semicolonless conditional type before export" {
  let src =
    #|type EnforceNonEmptyRecord<R> = keyof R extends never ? never : R
    #|export declare function sequenceS<F extends URIS4>(
    #|  F: Apply4<F>
    #|): <S, R, E, NER extends Record<string, Kind4<F, S, R, E, any>>>(
    #|  r: EnforceNonEmptyRecord<NER> & Record<string, Kind4<F, S, R, E, any>>
    #|) => Kind4<
    #|  F,
    #|  S,
    #|  R,
    #|  E,
    #|  {
    #|    [K in keyof NER]: [NER[K]] extends [Kind4<F, any, any, any, infer A>] ? A : never
    #|  }
    #|>
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected conditional type alias before export to parse: \{e}")
  }
  assert_eq(module_.imports.length(), 1)
}

///|
test "parser: parse declare class method with this parameter" {
  let src =
    #|export declare class Type<A, O = A, I = unknown> {
    #|  readonly name: string
    #|  readonly encode: Encode<A, O>
    #|  pipe<B, IB, A2 extends IB, OB extends A2>(this: Type<A2, O, I>, ab: Type<B, OB, IB>, name?: string): Type<B, O, I>
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected this parameter in declare class method to parse: \{e}")
  }
  assert_eq(module_.classes.length(), 1)
}

///|
test "parser: parse declare class heritage with object type argument" {
  let src =
    #|export declare class AnyDictionaryType extends Type<{
    #|  [key: string]: unknown
    #|}> {
    #|  readonly _tag: 'AnyDictionaryType'
    #|  constructor()
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected object type in declare class heritage to parse: \{e}")
  }
  assert_eq(module_.classes.length(), 1)
}

///|
test "parser: parse exported dts function declarations without declare keyword" {
  let src =
    #|export function nanoid<Type extends string>(size?: number): Type
    #|export const urlAlphabet: string
    #|export function random(bytes: number): Uint8Array
  let module_ = Parser::from_source(src).parse_module() catch {
    e => fail("expected ambient export function declarations to parse: \{e}")
  }
  assert_eq(module_.funcs.length(), 2)
  assert_eq(module_.values.length(), 1)
}

///|
test "parser: literal-union and template-literal aliases land in type_aliases" {
  // Confirms the parser keeps the underlying alias node so bridge passes
  // can re-evaluate the body, even when the alias itself looks like an
  // enum candidate (`type Channel = "info" | "warn"`).
  let src =
    #|export type Channel = "info" | "warn";
    #|export type Banner = `${Channel}-x`;
  let m = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(m.type_aliases.length(), 2)
  assert_eq(m.type_aliases[0].name, "Channel")
  assert_eq(m.type_aliases[0].type_, Union([Literal("info"), Literal("warn")]))
  assert_eq(m.type_aliases[1].name, "Banner")
  assert_eq(
    m.type_aliases[1].type_,
    TemplateLiteralType(["", "-x"], [Named("Channel")]),
  )
}

///|
test "parser: parse top-level async function declaration" {
  let src =
    #|async function fetchData() {
    #|  const r = await fetch("/api");
    #|  return r;
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.funcs.length(), 1)
  assert_eq(module_.funcs[0].name, "fetchData")
  assert_true(module_.funcs[0].is_async)
}

///|
test "parser: parse top-level decorator on class declaration" {
  let src =
    #|@logged
    #|class Service {
    #|  greet() { return "hi"; }
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.classes.length(), 1)
  assert_eq(module_.classes[0].name, "Service")
}

///|
test "parser: parse top-level decorator with call args on exported class" {
  // Single-line: decorator must not swallow the following declaration.
  let src = "@inject('logger') export class App { constructor() {} }"
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.classes.length(), 1)
  assert_eq(module_.classes[0].name, "App")
}

///|
test "parser: parse member-access decorator on class method" {
  let src =
    #|class C {
    #|  @ns.deco
    #|  foo() {}
    #|  @ns.deco()
    #|  bar() {}
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.classes.length(), 1)
}

///|
test "parser: export abstract class with definite-assignment field" {
  let src =
    #|export abstract class T implements I {
    #|    protected installer!: P;
    #|    private projectService!: S;
    #|    private isReady = false;
    #|    foo(): number { return 1; }
    #|}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.classes.length(), 1)
  assert_eq(module_.classes[0].name, "T")
}

///|
test "parser: top-level if/expression/assignment/block statements" {
  let cases = [
    "if (cond()) { setup(); }", "setObjectAllocator(getDefault());", "container.field = computeValue();",
    "{ type X<T> = T; }",
  ]
  for src in cases {
    let _ = Parser::from_source(src).parse_module() catch {
      e => {
        fail("Expected to parse top-level statement, got: \{e} for \{src}")
        return
      }
    }
  }
}

///|
test "parser: export namespace with runtime class body" {
  let src =
    #|export namespace ScriptSnapshot {
    #|    class StringScriptSnapshot {
    #|        constructor(private text: string) {}
    #|        public getText(start: number, end: number): string {
    #|            return start === 0 && end === this.text.length
    #|                ? this.text
    #|                : this.text.substring(start, end);
    #|        }
    #|    }
    #|    export function fromString(text: string): StringScriptSnapshot {
    #|        return new StringScriptSnapshot(text);
    #|    }
    #|}
    #|export interface PreProcessed {}
  let module_ = Parser::from_source(src).parse_module() catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_eq(module_.namespaces.length(), 1)
  assert_eq(module_.namespaces[0].name, "ScriptSnapshot")
  assert_eq(module_.interfaces.length(), 1)
  assert_eq(module_.interfaces[0].name, "PreProcessed")
}

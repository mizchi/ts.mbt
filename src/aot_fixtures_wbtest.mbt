// Tests for AOT fixtures

///|
test "fixtures/aot/simple.ts is AOT compilable" {
  let src =
    #|function add(a: number, b: number): number {
    #|  return a + b;
    #|}
    #|
    #|function factorial(n: number): number {
    #|  let result = 1;
    #|  for (let i = 1; i <= n; i = i + 1) {
    #|    result = result * i;
    #|  }
    #|  return result;
    #|}
    #|
    #|function fibonacci(n: number): number {
    #|  if (n <= 1) {
    #|    return n;
    #|  }
    #|  let a = 0;
    #|  let b = 1;
    #|  for (let i = 2; i <= n; i = i + 1) {
    #|    let tmp = a + b;
    #|    a = b;
    #|    b = tmp;
    #|  }
    #|  return b;
    #|}
    #|
    #|function max(a: number, b: number): number {
    #|  return a > b ? a : b;
    #|}
    #|
    #|function abs(x: number): number {
    #|  return x < 0 ? -x : x;
    #|}
  let result = @analysis.check_aot_compilable_source(src)
  println(result.debug_string())
  assert_true(result.compilable)
  assert_eq(result.incompatible_funcs.length(), 0)
}

///|
test "fixtures/aot/closure_readonly.ts is AOT compilable" {
  let src =
    #|function makeAdder(x: number) {
    #|  const add = (y: number) => x + y;
    #|  return add(10);
    #|}
    #|
    #|function applyTwice(x: number) {
    #|  const double = () => x * 2;
    #|  return double() + double();
    #|}
    #|
    #|function nested(a: number, b: number) {
    #|  const sum = () => a + b;
    #|  const diff = () => a - b;
    #|  return sum() * diff();
    #|}
  let result = @analysis.check_aot_compilable_source(src)
  println(result.debug_string())
  assert_true(result.compilable)
}

///|
test "fixtures/aot/closure_mutable.ts is AOT compilable" {
  let src =
    #|function counter() {
    #|  let count = 0;
    #|  const inc = () => { count = count + 1; };
    #|  inc();
    #|  inc();
    #|  inc();
    #|  return count;
    #|}
    #|
    #|function accumulator(initial: number) {
    #|  let sum = initial;
    #|  const add = (x: number) => { sum = sum + x; };
    #|  add(10);
    #|  add(20);
    #|  add(30);
    #|  return sum;
    #|}
    #|
    #|function multipleClosures() {
    #|  let x = 0;
    #|  const inc = () => { x = x + 1; };
    #|  const dec = () => { x = x - 1; };
    #|  const get = () => x;
    #|  inc();
    #|  inc();
    #|  dec();
    #|  return get();
    #|}
  let result = @analysis.check_aot_compilable_source(src)
  println(result.debug_string())
  assert_true(result.compilable)
}

///|
test "fixtures/aot/generator.ts simple generators are AOT compilable" {
  let src =
    #|function* range(start: number, end: number) {
    #|  for (let i = start; i < end; i = i + 1) {
    #|    yield i;
    #|  }
    #|}
    #|
    #|function* countdown(n: number) {
    #|  while (n > 0) {
    #|    yield n;
    #|    n = n - 1;
    #|  }
    #|}
    #|
    #|function* simpleYield() {
    #|  yield 1;
    #|  yield 2;
    #|  yield 3;
    #|}
    #|
    #|function* conditionalYield(n: number) {
    #|  if (n > 0) {
    #|    yield n;
    #|    yield n * 2;
    #|  } else {
    #|    yield 0;
    #|  }
    #|}
  let result = @analysis.check_aot_compilable_source(src)
  println(result.debug_string())
  // Generators should have AOT groups
  assert_true(result.groups.length() > 0)
}

///|
test "fixtures/aot/not_aot_compatible.ts - eval not supported" {
  let src =
    #|function withEval(code: string) {
    #|  return eval(code);
    #|}
  let result = @analysis.check_aot_compilable_source(src)
  println(result.debug_string())
  assert_false(result.compilable)
  assert_true(result.incompatible_funcs.length() > 0)
  assert_eq(result.incompatible_funcs[0].reason, "'eval' is not supported")
}

///|
test "fixtures/aot/not_aot_compatible.ts - with statement not supported" {
  let src =
    #|function withWith(obj: any) {
    #|  with (obj) {
    #|    return x;
    #|  }
    #|}
  let result = @analysis.check_aot_compilable_source(src)
  println(result.debug_string())
  assert_false(result.compilable)
  assert_true(result.incompatible_funcs.length() > 0)
}

///|
test "closure codegen for fixtures/aot/closure_readonly.ts" {
  // Test that we can generate code for read-only closures
  // (y) => x + y
  let body = @ast.TsArrowBody::ArrowExpr(
    @ast.TsExpr::BinOp(@ast.TsBinOp::Add, @ast.TsExpr::Var("x"), @ast.TsExpr::Var("y")),
  )
  let arrow_params : Array[@ast.TsParam] = [
    { name: "y", type_: @ast.TsType::Number, binding: None, is_rest: false, default: None },
  ]
  let outer_scope : Array[String] = ["x"]
  let ctx = @codegen.ClosureCodegenCtx::new(0U)

  match @codegen.compile_arrow_func(arrow_params, body, outer_scope, ctx) {
    Some(code) => {
      assert_true(code.env_struct_type is Some(_))
      assert_eq(code.capture_names.length(), 1)
      assert_eq(code.capture_names[0], "x")
      println("Generated closure code: \{code.func_code.body.instrs.length()} instructions")
    }
    None => fail("Should compile read-only closure")
  }
}

///|
test "closure codegen for fixtures/aot/closure_mutable.ts" {
  // Test counter function pattern
  let block : @ast.TsBlock = {
    stmts: [
      @ast.TsStmt::Let(@ast.TsBinding::Ident("count"), @ast.TsType::Number, @ast.TsExpr::IntLit(0)),
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident("inc"),
        @ast.TsType::Any,
        @ast.TsExpr::ArrowFunc(
          [],
          @ast.TsArrowBody::ArrowBlock({
            stmts: [
              @ast.TsStmt::Assign(
                "count",
                @ast.TsExpr::BinOp(@ast.TsBinOp::Add, @ast.TsExpr::Var("count"), @ast.TsExpr::IntLit(1)),
              ),
            ],
          }),
          false,
        ),
      ),
      @ast.TsStmt::Return(Some(@ast.TsExpr::Var("count"))),
    ],
  }
  let params : Array[@ast.TsParam] = []
  let lifted_info = @codegen.analyze_lifted_vars(block, [])

  // count should be lifted with mutable flag
  assert_eq(lifted_info.lifted_vars.length(), 1)
  assert_true(lifted_info.lifted_vars.contains("count"))
  assert_eq(lifted_info.is_mutated.get("count"), Some(true))

  // Generate code with environment sharing
  let result = @codegen.compile_func_body_with_env(block, params, lifted_info, 0U)
  assert_true(result.env_struct_type is Some(_))
  assert_true(result.env_local_idx is Some(_))
  println("Generated counter with env sharing: \{result.func_code.body.instrs.length()} instructions")
}

///|
test "generator codegen for fixtures/aot/generator.ts - range" {
  let src =
    #|function* range(start: number, end: number) {
    #|  for (let i = start; i < end; i = i + 1) {
    #|    yield i;
    #|  }
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let func = ts_module.funcs[0]

  // Analyze generator
  let analysis = @analysis.analyze_generator(func)
  assert_true(analysis.compilable)
  println("Generator yield points: \{analysis.yield_points.length()}")

  // Compile generator
  match @codegen.compile_generator_func(func, 0U) {
    Some(code) => {
      println("Generated range() next function: \{code.next_func_code.body.instrs.length()} instructions")
    }
    None => fail("Should compile range generator")
  }
}

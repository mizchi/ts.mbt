// Tests for AOT compilation.

///|
test "compile_module_aot: simple pure function" {
  let src =
    #|export function add(a: number, b: number): number {
    #|  return a + b;
    #|}
  let parser = @parser.Parser::from_source(src)
  let mod = parser.parse_module()
  let result = compile_module_aot(mod)
  // Should compile successfully
  assert_eq(result.compiled_functions.length(), 1)
  assert_eq(result.uncompiled_functions.length(), 0)
  let compiled = result.compiled_functions[0]
  assert_eq(compiled.name, "add")
  assert_true(compiled.wasm_bytes.length() > 0)
}

///|
test "compile_module_aot: multiple functions" {
  let src =
    #|export function add(a: number, b: number): number {
    #|  return a + b;
    #|}
    #|export function mul(a: number, b: number): number {
    #|  return a * b;
    #|}
  let parser = @parser.Parser::from_source(src)
  let mod = parser.parse_module()
  let result = compile_module_aot(mod)
  // Both should compile
  assert_eq(result.compiled_functions.length(), 2)
  assert_eq(result.uncompiled_functions.length(), 0)
}

///|
test "get_compilation_info" {
  let src =
    #|export function pure(x: number): number {
    #|  return x * 2;
    #|}
  let parser = @parser.Parser::from_source(src)
  let mod = parser.parse_module()
  let (compilable_count, not_compilable_count, compilable, not_compilable) = get_compilation_info(
    mod,
  )
  assert_eq(compilable_count, 1)
  assert_eq(not_compilable_count, 0)
  assert_eq(compilable[0], "pure")
  assert_eq(not_compilable.length(), 0)
}

///|
test "is_function_compilable" {
  // Create a simple pure function
  let pure_func : @ast.TsFunc = {
    name: "test",
    params: [],
    return_type: @ast.TsType::Number,
    body: { stmts: [@ast.TsStmt::Return(Some(@ast.TsExpr::IntLit(42)))] },
    is_generator: false,
    is_async: false,
  }
  assert_true(is_function_compilable(pure_func))
  // Create an async function
  let async_func : @ast.TsFunc = {
    name: "async_test",
    params: [],
    return_type: @ast.TsType::Any,
    body: { stmts: [] },
    is_generator: false,
    is_async: true,
  }
  assert_false(is_function_compilable(async_func))
}

///|
test "compile_module_to_wasm" {
  let src =
    #|export function add(a: number, b: number): number {
    #|  return a + b;
    #|}
  let parser = @parser.Parser::from_source(src)
  let mod = parser.parse_module()
  let compiled = compile_module_to_wasm(mod)
  assert_eq(compiled.functions.length(), 1)
  assert_true(compiled.wasm_bytes.length() > 0)
}

///|
test "AOTRuntime::call simple function" {
  let src =
    #|export function double(x: number): number {
    #|  return x * 2;
    #|}
  let parser = @parser.Parser::from_source(src)
  let mod = parser.parse_module()
  let runtime = create_aot_runtime(mod)
  assert_true(runtime.has_function("double"))
  // Call the compiled function
  let result = runtime.call("double", [21.0])
  assert_eq(result, 42.0)
}

///|
test "AOTRuntime::call add function" {
  let src =
    #|export function add(a: number, b: number): number {
    #|  return a + b;
    #|}
  let parser = @parser.Parser::from_source(src)
  let mod = parser.parse_module()
  let runtime = create_aot_runtime(mod)
  let result = runtime.call("add", [10.0, 32.0])
  assert_eq(result, 42.0)
}

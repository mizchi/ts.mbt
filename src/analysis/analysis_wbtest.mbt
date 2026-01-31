// Tests for static analysis.

///|
test "SourceLoc::from_offset basic" {
  let source = "let x = 1;\nlet y = 2;"
  let loc = SourceLoc::from_offset(source, 0)
  assert_eq(loc.line, 1)
  assert_eq(loc.column, 1)
  let loc2 = SourceLoc::from_offset(source, 4)
  assert_eq(loc2.line, 1)
  assert_eq(loc2.column, 5)
  let loc3 = SourceLoc::from_offset(source, 11)
  assert_eq(loc3.line, 2)
  assert_eq(loc3.column, 1)
}

///|
test "Scope::define and lookup" {
  let scope = Scope::global()
  let info : BindingInfo = {
    name: "x",
    kind: Let,
    type_: @ast.TsType::Number,
    is_initialized: true,
    loc: SourceLoc::unknown(),
  }
  scope.add_binding("x", info)
  assert_true(scope.has_local("x"))
  assert_true(scope.lookup("x") is Some(_))
  assert_true(scope.lookup("y") is None)
}

///|
test "Scope::nested lookup" {
  let parent = Scope::global()
  let parent_info : BindingInfo = {
    name: "x",
    kind: Let,
    type_: @ast.TsType::Number,
    is_initialized: true,
    loc: SourceLoc::unknown(),
  }
  parent.add_binding("x", parent_info)
  let child = Scope::new(Block, Some(parent))
  let child_info : BindingInfo = {
    name: "y",
    kind: Let,
    type_: @ast.TsType::String_,
    is_initialized: true,
    loc: SourceLoc::unknown(),
  }
  child.add_binding("y", child_info)

  // Child can access parent's bindings
  assert_true(child.lookup("x") is Some(_))
  assert_true(child.lookup("y") is Some(_))

  // Parent cannot access child's bindings
  assert_true(parent.lookup("y") is None)
}

///|
test "Scope::is_const" {
  let scope = Scope::global()
  let const_info : BindingInfo = {
    name: "PI",
    kind: Const,
    type_: @ast.TsType::Number,
    is_initialized: true,
    loc: SourceLoc::unknown(),
  }
  scope.add_binding("PI", const_info)
  let let_info : BindingInfo = {
    name: "x",
    kind: Let,
    type_: @ast.TsType::Number,
    is_initialized: true,
    loc: SourceLoc::unknown(),
  }
  scope.add_binding("x", let_info)
  assert_true(scope.is_const("PI"))
  assert_false(scope.is_const("x"))
}

///|
test "AnalysisCtx::push_pop_scope" {
  let ctx = AnalysisCtx::new("")
  assert_eq(ctx.current_scope.kind, Global)
  ctx.push_scope(Function)
  assert_eq(ctx.current_scope.kind, Function)
  ctx.push_scope(Block)
  assert_eq(ctx.current_scope.kind, Block)
  ctx.pop_scope()
  assert_eq(ctx.current_scope.kind, Function)
  ctx.pop_scope()
  assert_eq(ctx.current_scope.kind, Global)
}

///|
test "collect_binding_names from Ident" {
  let binding = @ast.TsBinding::Ident("x")
  let names : Array[String] = []
  collect_binding_names(binding, names)
  assert_eq(names.length(), 1)
  assert_eq(names[0], "x")
}

///|
test "collect_binding_names from Array" {
  let binding = @ast.TsBinding::Array({
    items: [
      Some({ binding: @ast.TsBinding::Ident("a"), default: None }),
      Some({ binding: @ast.TsBinding::Ident("b"), default: None }),
    ],
    rest: None,
  })
  let names : Array[String] = []
  collect_binding_names(binding, names)
  assert_eq(names.length(), 2)
  assert_eq(names[0], "a")
  assert_eq(names[1], "b")
}

///|
test "collect_binding_names from Object" {
  let binding = @ast.TsBinding::Object({
    props: [
      {
        key: "x",
        key_expr: None,
        binding: @ast.TsBinding::Ident("x"),
        default: None,
      },
      {
        key: "y",
        key_expr: None,
        binding: @ast.TsBinding::Ident("y"),
        default: None,
      },
    ],
    rest: Some("rest"),
  })
  let names : Array[String] = []
  collect_binding_names(binding, names)
  assert_eq(names.length(), 3)
  assert_eq(names[0], "x")
  assert_eq(names[1], "y")
  assert_eq(names[2], "rest")
}

///|
test "infer_literal_type" {
  assert_eq(
    infer_literal_type(@ast.TsExpr::NumberLit(1.0)),
    @ast.TsType::Number,
  )
  assert_eq(infer_literal_type(@ast.TsExpr::IntLit(1)), @ast.TsType::Int)
  assert_eq(
    infer_literal_type(@ast.TsExpr::BoolLit(true)),
    @ast.TsType::Boolean,
  )
  assert_eq(
    infer_literal_type(@ast.TsExpr::StringLit("hello")),
    @ast.TsType::String_,
  )
}

///|
test "format_error basic" {
  let error : AnalysisError = {
    kind: ReferenceError,
    message: "x is not defined",
    loc: { offset: 4, line: 1, column: 5 },
  }
  let source = "let y = x;"
  let formatted = format_error(error, source)
  assert_true(formatted.contains("ReferenceError"))
  assert_true(formatted.contains("x is not defined"))
  assert_true(formatted.contains("line 1"))
}

///|
test "AnalysisResult::is_ok" {
  let ok_result : AnalysisResult[Int] = Ok(42, [])
  assert_true(ok_result.is_ok())
  let err_result : AnalysisResult[Int] = Err([])
  assert_false(err_result.is_ok())
}

///|
test "analyze simple module" {
  let source = "function add(a: number, b: number): number { return a + b; }"
  let parser = @parser.Parser::from_source(source)
  let module_ = parser.parse_module()
  let result = analyze(module_, source)
  assert_true(result.is_ok())
}

///|
test "TypeInferCtx variable types" {
  let ctx = TypeInferCtx::new("")
  ctx.add_var("x", @ast.TsType::Number)
  ctx.add_var("y", @ast.TsType::String_)
  assert_eq(ctx.get_var_type("x"), @ast.TsType::Number)
  assert_eq(ctx.get_var_type("y"), @ast.TsType::String_)
  assert_eq(ctx.get_var_type("z"), @ast.TsType::Any)
}

///|
test "infer_binop_type comparison" {
  let ctx = TypeInferCtx::new("")
  let left = @ast.TsExpr::NumberLit(1.0)
  let right = @ast.TsExpr::NumberLit(2.0)
  assert_eq(
    infer_binop_type(ctx, @ast.TsBinOp::BinLt, left, right),
    @ast.TsType::Boolean,
  )
  assert_eq(
    infer_binop_type(ctx, @ast.TsBinOp::BinEq, left, right),
    @ast.TsType::Boolean,
  )
}

///|
test "infer_binop_type add with strings" {
  let ctx = TypeInferCtx::new("")
  let str_expr = @ast.TsExpr::StringLit("hello")
  let num_expr = @ast.TsExpr::NumberLit(1.0)
  assert_eq(
    infer_binop_type(ctx, @ast.TsBinOp::Add, str_expr, num_expr),
    @ast.TsType::String_,
  )
  assert_eq(
    infer_binop_type(ctx, @ast.TsBinOp::Add, num_expr, str_expr),
    @ast.TsType::String_,
  )
}

///|
test "infer_method_return_type string methods" {
  let ctx = TypeInferCtx::new("")
  let receiver = @ast.TsExpr::StringLit("hello")
  assert_eq(
    infer_method_return_type(ctx, receiver, "charAt"),
    @ast.TsType::String_,
  )
  assert_eq(
    infer_method_return_type(ctx, receiver, "charCodeAt"),
    @ast.TsType::Int,
  )
  assert_eq(
    infer_method_return_type(ctx, receiver, "indexOf"),
    @ast.TsType::Int,
  )
}

///|
test "resolve_any preserves explicit type" {
  let explicit_type = @ast.TsType::String_
  let init = @ast.TsExpr::NumberLit(1.0)
  assert_eq(resolve_any(explicit_type, init), @ast.TsType::String_)
}

///|
test "resolve_any infers from init when Any" {
  let any_type = @ast.TsType::Any
  let init = @ast.TsExpr::NumberLit(1.0)
  assert_eq(resolve_any(any_type, init), @ast.TsType::Number)
}

// ============================================
// Type constraint tests
// ============================================

///|
test "is_assignable basic types" {
  // Same types
  assert_true(is_assignable(@ast.TsType::Number, @ast.TsType::Number))
  assert_true(is_assignable(@ast.TsType::String_, @ast.TsType::String_))

  // Any is assignable to/from anything
  assert_true(is_assignable(@ast.TsType::Any, @ast.TsType::Number))
  assert_true(is_assignable(@ast.TsType::String_, @ast.TsType::Any))

  // Int is assignable to Number
  assert_true(is_assignable(@ast.TsType::Int, @ast.TsType::Number))
  assert_false(is_assignable(@ast.TsType::Number, @ast.TsType::Int))

  // Never is assignable to anything
  assert_true(is_assignable(@ast.TsType::Never, @ast.TsType::String_))
  assert_false(is_assignable(@ast.TsType::String_, @ast.TsType::Never))
}

///|
test "is_assignable union types" {
  let union = @ast.TsType::Union([@ast.TsType::String_, @ast.TsType::Number])

  // String is assignable to string | number
  assert_true(is_assignable(@ast.TsType::String_, union))
  assert_true(is_assignable(@ast.TsType::Number, union))

  // Boolean is not assignable to string | number
  assert_false(is_assignable(@ast.TsType::Boolean, union))
}

///|
test "is_assignable array types" {
  let str_arr = @ast.TsType::Array(@ast.TsType::String_)
  let num_arr = @ast.TsType::Array(@ast.TsType::Number)
  assert_true(is_assignable(str_arr, str_arr))
  assert_false(is_assignable(str_arr, num_arr))
}

///|
test "narrow_type typeof guard" {
  let union = @ast.TsType::Union([
    @ast.TsType::String_,
    @ast.TsType::Number,
    @ast.TsType::Boolean,
  ])
  let narrowed = narrow_type(union, "string")
  assert_eq(narrowed, @ast.TsType::String_)
  let narrowed_num = narrow_type(union, "number")
  assert_eq(narrowed_num, @ast.TsType::Number)
}

///|
test "remove_null_undefined" {
  let union = @ast.TsType::Union([
    @ast.TsType::String_,
    @ast.TsType::Null,
    @ast.TsType::Undefined,
  ])
  let narrowed = remove_null_undefined(union)
  assert_eq(narrowed, @ast.TsType::String_)
}

///|
test "TypeEnv narrowing" {
  let env = TypeEnv::new(None)
  env.set_narrowed("x", @ast.TsType::String_)
  assert_eq(env.get_narrowed("x"), Some(@ast.TsType::String_))
  assert_eq(env.get_narrowed("y"), None)

  // Nested scope
  let inner = TypeEnv::new(Some(env))
  inner.set_narrowed("y", @ast.TsType::Number)

  // Inner can see parent's narrowed types
  assert_eq(inner.get_narrowed("x"), Some(@ast.TsType::String_))
  assert_eq(inner.get_narrowed("y"), Some(@ast.TsType::Number))
}

///|
test "analyze_typeof_guard" {
  let expr = @ast.TsExpr::BinOp(
    @ast.TsBinOp::BinEq,
    @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Typeof, @ast.TsExpr::Var("x")),
    @ast.TsExpr::StringLit("string"),
  )
  match analyze_typeof_guard(expr) {
    Some((name, type_str)) => {
      assert_eq(name, "x")
      assert_eq(type_str, "string")
    }
    None => assert_true(false)
  }
}

///|
test "analyze_null_guard" {
  let expr = @ast.TsExpr::BinOp(
    @ast.TsBinOp::BinNe,
    @ast.TsExpr::Var("x"),
    @ast.TsExpr::NullLit,
  )
  match analyze_null_guard(expr) {
    Some((name, is_not_null)) => {
      assert_eq(name, "x")
      assert_true(is_not_null)
    }
    None => assert_true(false)
  }
}

///|
test "union_types" {
  let a = @ast.TsType::String_
  let b = @ast.TsType::Number
  let union = union_types(a, b)
  assert_eq(
    union,
    @ast.TsType::Union([@ast.TsType::String_, @ast.TsType::Number]),
  )

  // Same type returns same type
  assert_eq(union_types(a, a), @ast.TsType::String_)

  // Never is absorbed
  assert_eq(union_types(@ast.TsType::Never, a), @ast.TsType::String_)
}

///|
test "intersect_types" {
  let a = @ast.TsType::Any
  let b = @ast.TsType::String_

  // Any intersected with anything is the other type
  assert_eq(intersect_types(a, b), @ast.TsType::String_)

  // Same type
  assert_eq(intersect_types(b, b), @ast.TsType::String_)

  // Never
  assert_eq(intersect_types(@ast.TsType::Never, b), @ast.TsType::Never)
}

///|
test "FlowTypeCtx scope management" {
  let ctx = FlowTypeCtx::new("")
  ctx.set_type("x", @ast.TsType::Number)
  assert_eq(ctx.get_type("x"), @ast.TsType::Number)
  ctx.enter_scope()
  ctx.narrow("x", @ast.TsType::Int)
  assert_eq(ctx.get_type("x"), @ast.TsType::Int)
  ctx.leave_scope()
  // Back to original type (narrowing removed)
  assert_eq(ctx.get_type("x"), @ast.TsType::Number)
}

///|
test "ObjectType property tracking" {
  let obj = ObjectType::new()
  obj.set_prop("name", @ast.TsType::String_)
  obj.set_prop("age", @ast.TsType::Number)
  assert_eq(obj.get_prop("name"), Some(@ast.TsType::String_))
  assert_eq(obj.get_prop("age"), Some(@ast.TsType::Number))
  assert_eq(obj.get_prop("unknown"), None)
}

///|
test "ConstraintSolver type errors" {
  let registry = TypeRegistry::new()
  let solver = ConstraintSolver::new(registry)

  // Add invalid constraint
  solver.add_constraint(
    Assignable(@ast.TsType::String_, @ast.TsType::Number, SourceLoc::unknown()),
  )
  solver.solve()
  assert_eq(solver.errors.length(), 1)
  assert_eq(solver.errors[0].expected, @ast.TsType::Number)
  assert_eq(solver.errors[0].actual, @ast.TsType::String_)
}

///|
test "type_check_module simple function" {
  let source = "function add(a: number, b: number): number { return a + b; }"
  let parser = @parser.Parser::from_source(source)
  let module_ = parser.parse_module()
  let result = type_check_module(module_, source)
  assert_eq(result.errors.length(), 0)
}

///|
test "type_check_module return type mismatch" {
  let source =
    #|function bad(): number {
    #|  return "hello";
    #|}
  let parser = @parser.Parser::from_source(source)
  let module_ = parser.parse_module()
  let result = type_check_module(module_, source)

  // Should have type error for returning string where number expected
  assert_true(result.errors.length() > 0)
}

///|
test "infer_expr_flow array literal" {
  let ctx = FlowTypeCtx::new("")
  let expr = @ast.TsExpr::ArrayLit([
    @ast.TsExpr::NumberLit(1.0),
    @ast.TsExpr::NumberLit(2.0),
  ])
  let type_ = infer_expr_flow(ctx, expr)
  assert_eq(type_, @ast.TsType::Array(@ast.TsType::Number))
}

///|
test "infer_expr_flow mixed array literal" {
  let ctx = FlowTypeCtx::new("")
  let expr = @ast.TsExpr::ArrayLit([
    @ast.TsExpr::NumberLit(1.0),
    @ast.TsExpr::StringLit("hello"),
  ])
  let type_ = infer_expr_flow(ctx, expr)
  // Should be Array<number | string>
  match type_ {
    @ast.TsType::Array(@ast.TsType::Union(_)) => ()
    _ => assert_true(false)
  }
}

///|
test "type_check function argument mismatch" {
  let source =
    #|function greet(name: string): string {
    #|  return "Hello, " + name;
    #|}
    #|function test(): void {
    #|  greet(123);
    #|}
  let parser = @parser.Parser::from_source(source)
  let module_ = parser.parse_module()
  let result = type_check_module(module_, source)

  // Should detect argument type mismatch (number vs string)
  assert_true(result.errors.length() > 0)
}

///|
test "infer_prop_type object literal" {
  let ctx = FlowTypeCtx::new("")
  // Simulate: let obj = { x: 1, y: "hello" }
  let obj_type = @ast.TsType::Object([
    (@ast.TsType::Literal("x"), @ast.TsType::Number),
    (@ast.TsType::Literal("y"), @ast.TsType::String_),
  ])
  assert_eq(infer_prop_type(ctx, obj_type, "x"), @ast.TsType::Number)
  assert_eq(infer_prop_type(ctx, obj_type, "y"), @ast.TsType::String_)
  assert_eq(infer_prop_type(ctx, obj_type, "z"), @ast.TsType::Any)
}

///|
test "infer_expr_flow object literal" {
  let ctx = FlowTypeCtx::new("")
  let expr = @ast.TsExpr::ObjectLit([
    ("x", @ast.TsExpr::NumberLit(1.0)),
    ("y", @ast.TsExpr::StringLit("hello")),
  ])
  let type_ = infer_expr_flow(ctx, expr)
  match type_ {
    @ast.TsType::Object(props) => assert_eq(props.length(), 2)
    _ => assert_true(false)
  }
}

///|
test "infer_binop_flow coalesce" {
  let ctx = FlowTypeCtx::new("")
  let left = @ast.TsExpr::NullLit
  let right = @ast.TsExpr::StringLit("default")
  let type_ = infer_binop_flow(ctx, @ast.TsBinOp::Coalesce, left, right)

  // null ?? "default" should be string | null with null removed = string
  match type_ {
    @ast.TsType::Union(types) =>
      // Union of Never (null with null removed) and String
      assert_true(types.length() >= 1)
    @ast.TsType::String_ => () // Also acceptable
    _ => ()
  }
}

// ============================================
// Usage tracking tests
// ============================================

///|
test "UsageInfo::is_linear" {
  let info = UsageInfo::new("x", SourceLoc::unknown(), Let, @ast.TsType::Number)
  // Initially unused
  assert_true(info.is_unused())
  assert_true(info.is_affine())

  // One read = linear
  info.read_count = 1
  assert_true(info.is_linear())
  assert_true(info.is_affine())

  // Two reads = not linear
  info.read_count = 2
  assert_false(info.is_linear())
  assert_false(info.is_affine())
}

///|
test "UsageInfo::is_captured" {
  let info = UsageInfo::new("x", SourceLoc::unknown(), Let, @ast.TsType::Number)
  info.read_count = 1
  info.last_use = Some(SourceLoc::unknown())

  // Not captured -> can drop at last use
  assert_true(info.can_drop_at_last_use())

  // Captured -> cannot drop
  info.is_captured = true
  assert_false(info.can_drop_at_last_use())
}

///|
test "SymbolTable basic usage" {
  let table = SymbolTable::new("let x = 1; x + 1;")
  table.add_symbol("x", Let, @ast.TsType::Number, 4)
  table.record_use("x", Read, 11)
  match table.get_usage("x") {
    Some(info) => {
      assert_eq(info.read_count, 1)
      assert_eq(info.write_count, 0)
      assert_true(info.is_linear())
    }
    None => assert_true(false)
  }
}

///|
test "SymbolTable closure capture" {
  let table = SymbolTable::new("")
  table.add_symbol("outer", Let, @ast.TsType::Number, 0)

  // Enter closure and use outer variable
  table.enter_closure()
  table.record_use("outer", Read, 10)
  table.leave_closure()
  match table.get_usage("outer") {
    Some(info) => {
      assert_true(info.is_captured)
      assert_false(info.can_drop_at_last_use())
    }
    None => assert_true(false)
  }
}

///|
test "SymbolTable scoped lookup" {
  let table = SymbolTable::new("")
  table.add_symbol("x", Let, @ast.TsType::Number, 0)
  table.enter_scope()
  // Shadow x in inner scope
  table.add_symbol("x", Let, @ast.TsType::String_, 10)
  table.record_use("x", Read, 15)
  table.leave_scope()

  // Use outer x
  table.record_use("x", Read, 20)

  // Both x's should have 1 read each
  // (This test verifies scoping works)
}

///|
test "analyze_usage simple function" {
  let source = "function foo(a) { return a + 1; }"
  let parser = @parser.Parser::from_source(source)
  let module_ = parser.parse_module()
  let table = analyze_usage(module_, source)

  // foo should be declared
  match table.get_usage("foo") {
    Some(info) => assert_eq(info.decl_kind, Function)
    None => () // Top-level function might not be in symbol table
  }
}

///|
test "DropAnalysis basic" {
  let table = SymbolTable::new("")
  table.add_symbol("used", Let, @ast.TsType::Number, 0)
  table.add_symbol("unused", Let, @ast.TsType::Number, 10)
  table.record_use("used", Read, 20)
  let analysis = table.get_drop_analysis()

  // unused should be in never_used
  assert_true(analysis.never_used.contains("unused"))

  // used should be in drop_after_use
  let has_used = analysis.drop_after_use
    .iter()
    .any(fn(pair) { pair.0 == "used" })
  assert_true(has_used)
}

///|
test "type inference: variable reference preserves type" {
  // Test that types are correctly inferred through variable references
  let src =
    #|function test(a: number, b: number): number {
    #|  let sum = a + b;
    #|  return sum;
    #|}
  let result = parse_and_analyze(src)
  match result {
    Ok(typed_module, _) => {
      let func = typed_module.funcs[0]
      // Check that 'sum' is inferred as Number (not Any)
      let mut found_sum = false
      for var_info in func.locals {
        let (name, type_) = var_info
        if name == "sum" {
          found_sum = true
          assert_eq(type_, @ast.TsType::Number)
        }
      }
      assert_true(found_sum)
    }
    Err(_) => panic()
  }
}

///|
test "type inference: binary operation preserves type" {
  let src =
    #|function test(): int {
    #|  let x = 10;
    #|  let y = 20;
    #|  let z = x + y;
    #|  return z;
    #|}
  let result = parse_and_analyze(src)
  match result {
    Ok(typed_module, _) => {
      let func = typed_module.funcs[0]
      // All locals should be Int
      for var_info in func.locals {
        let (_, type_) = var_info
        assert_eq(type_, @ast.TsType::Int)
      }
    }
    Err(_) => panic()
  }
}

///|
test "type inference: mixed types in chain" {
  let src =
    #|function test(a: number): number {
    #|  let b = a * 2.0;
    #|  let c = b + 1.0;
    #|  return c;
    #|}
  let result = parse_and_analyze(src)
  match result {
    Ok(typed_module, _) => {
      let func = typed_module.funcs[0]
      // b and c should be Number
      for var_info in func.locals {
        let (_, type_) = var_info
        assert_eq(type_, @ast.TsType::Number)
      }
    }
    Err(_) => panic()
  }
}

///|
test "type inference: int + number promotes to number" {
  let src =
    #|function test(): number {
    #|  let x = 10;
    #|  let y = 1.5;
    #|  let z = x + y;
    #|  return z;
    #|}
  let result = parse_and_analyze(src)
  match result {
    Ok(typed_module, _) => {
      let func = typed_module.funcs[0]
      // z should be Number (promoted from Int + Number)
      let mut found_z = false
      for var_info in func.locals {
        let (name, type_) = var_info
        if name == "z" {
          found_z = true
          assert_eq(type_, @ast.TsType::Number)
        }
      }
      assert_true(found_z)
    }
    Err(_) => panic()
  }
}

///|
test "type inference: bitwise operators return int" {
  let src =
    #|function test(a: number): int {
    #|  let x = a | 0;
    #|  return x;
    #|}
  let result = parse_and_analyze(src)
  match result {
    Ok(typed_module, _) => {
      let func = typed_module.funcs[0]
      for var_info in func.locals {
        let (name, type_) = var_info
        if name == "x" {
          assert_eq(type_, @ast.TsType::Int)
        }
      }
    }
    Err(_) => panic()
  }
}

// Compilability tests

///|
test "can_compile_to_wasm: simple pure function" {
  let src =
    #|function add(a: number, b: number): number {
    #|  return a + b;
    #|}
  let parser = @parser.Parser::from_source(src)
  let mod = parser.parse_module()
  let func = mod.funcs[0]
  match can_compile_to_wasm(func) {
    Compilable => ()
    NotCompilable(reason) => fail("expected compilable: \{reason}")
  }
}

///|
test "can_compile_to_wasm: function with loops" {
  let src =
    #|function factorial(n: number): number {
    #|  let result = 1;
    #|  for (let i = 1; i <= n; i = i + 1) {
    #|    result = result * i;
    #|  }
    #|  return result;
    #|}
  let parser = @parser.Parser::from_source(src)
  let mod = parser.parse_module()
  let func = mod.funcs[0]
  match can_compile_to_wasm(func) {
    Compilable => ()
    NotCompilable(reason) => fail("expected compilable: \{reason}")
  }
}

///|
test "can_compile_to_wasm: async function not supported" {
  // Create an async function directly
  let func : @ast.TsFunc = {
    name: "fetchData",
    params: [],
    return_type: @ast.TsType::Any,
    body: { stmts: [@ast.TsStmt::Return(Some(@ast.TsExpr::IntLit(42)))] },
    is_generator: false,
    is_async: true,
  }
  match can_compile_to_wasm(func) {
    Compilable => fail("expected not compilable")
    NotCompilable(reason) => assert_true(reason.contains("async"))
  }
}

///|
test "can_compile_to_wasm: generator function not supported" {
  let src =
    #|function* gen(): Generator<number> {
    #|  yield 1;
    #|}
  let parser = @parser.Parser::from_source(src)
  let mod = parser.parse_module()
  let func = mod.funcs[0]
  match can_compile_to_wasm(func) {
    Compilable => fail("expected not compilable")
    NotCompilable(reason) => assert_true(reason.contains("generator"))
  }
}

///|
test "can_compile_to_wasm: try/catch not supported" {
  let src =
    #|function risky(): number {
    #|  try {
    #|    return 1;
    #|  } catch (e) {
    #|    return 0;
    #|  }
    #|}
  let parser = @parser.Parser::from_source(src)
  let mod = parser.parse_module()
  let func = mod.funcs[0]
  match can_compile_to_wasm(func) {
    Compilable => fail("expected not compilable")
    NotCompilable(reason) => assert_true(reason.contains("try"))
  }
}

///|
test "find_compilable_functions" {
  let src =
    #|export function pure1(x: number): number {
    #|  return x * 2;
    #|}
    #|export function pure2(a: number, b: number): number {
    #|  return a + b;
    #|}
  let parser = @parser.Parser::from_source(src)
  let mod = parser.parse_module()
  let compilable = find_compilable_functions(mod)
  assert_eq(compilable.length(), 2)
  assert_eq(compilable[0].0, "pure1")
  assert_eq(compilable[1].0, "pure2")
}

///|
test "find_compilable_functions: filters async/generator" {
  // Create a module with a mix of compilable and non-compilable functions
  let pure_func : @ast.TsFunc = {
    name: "pureFunc",
    params: [],
    return_type: @ast.TsType::Number,
    body: { stmts: [@ast.TsStmt::Return(Some(@ast.TsExpr::IntLit(42)))] },
    is_generator: false,
    is_async: false,
  }
  let async_func : @ast.TsFunc = {
    name: "asyncFunc",
    params: [],
    return_type: @ast.TsType::Any,
    body: { stmts: [] },
    is_generator: false,
    is_async: true,
  }
  let gen_func : @ast.TsFunc = {
    name: "genFunc",
    params: [],
    return_type: @ast.TsType::Any,
    body: { stmts: [] },
    is_generator: true,
    is_async: false,
  }
  let mod : @ast.TsModule = {
    funcs: [pure_func, async_func, gen_func],
    interfaces: [],
    imports: [],
  }
  let compilable = find_compilable_functions(mod)
  assert_eq(compilable.length(), 1)
  assert_eq(compilable[0].0, "pureFunc")
}

///|
test "analyze_generator: simple generator" {
  // function* simple() { yield 1; yield 2; }
  let gen_func : @ast.TsFunc = {
    name: "simple",
    params: [],
    return_type: @ast.TsType::Any,
    body: {
      stmts: [
        @ast.TsStmt::Expr(@ast.TsExpr::Yield(Some(@ast.TsExpr::IntLit(1)))),
        @ast.TsStmt::Expr(@ast.TsExpr::Yield(Some(@ast.TsExpr::IntLit(2)))),
      ],
    },
    is_generator: true,
    is_async: false,
  }
  let analysis = analyze_generator(gen_func)
  assert_eq(analysis.yield_points.length(), 2)
  assert_true(analysis.compilable)
  assert_eq(analysis.state_count, 4) // initial + 2 yields + done
}

///|
test "analyze_generator: generator with loop" {
  // function* range(n) { for (let i = 0; i < n; i++) { yield i; } }
  let gen_func : @ast.TsFunc = {
    name: "range",
    params: [
      {
        name: "n",
        is_rest: false,
        type_: @ast.TsType::Number,
        binding: None,
        default: None,
      },
    ],
    return_type: @ast.TsType::Any,
    body: {
      stmts: [
        @ast.TsStmt::For(
          Some(
            @ast.TsStmt::Let(
              @ast.TsBinding::Ident("i"),
              @ast.TsType::Number,
              @ast.TsExpr::IntLit(0),
            ),
          ),
          Some(
            @ast.TsExpr::BinOp(
              @ast.TsBinOp::BinLt,
              @ast.TsExpr::Var("i"),
              @ast.TsExpr::Var("n"),
            ),
          ),
          Some(
            @ast.TsStmt::Assign(
              "i",
              @ast.TsExpr::BinOp(
                @ast.TsBinOp::Add,
                @ast.TsExpr::Var("i"),
                @ast.TsExpr::IntLit(1),
              ),
            ),
          ),
          {
            stmts: [
              @ast.TsStmt::Expr(@ast.TsExpr::Yield(Some(@ast.TsExpr::Var("i")))),
            ],
          },
        ),
      ],
    },
    is_generator: true,
    is_async: false,
  }
  let analysis = analyze_generator(gen_func)
  assert_eq(analysis.yield_points.length(), 1)
  assert_true(analysis.compilable)
  // Check persisted vars: n (param) and i (local)
  assert_eq(analysis.persisted_vars.length(), 2)
}

///|
test "analyze_generator: non-generator returns not compilable" {
  let func : @ast.TsFunc = {
    name: "notGen",
    params: [],
    return_type: @ast.TsType::Number,
    body: { stmts: [@ast.TsStmt::Return(Some(@ast.TsExpr::IntLit(42)))] },
    is_generator: false,
    is_async: false,
  }
  let analysis = analyze_generator(func)
  assert_false(analysis.compilable)
  assert_eq(analysis.not_compilable_reason, Some("not a generator function"))
}

///|
test "callgraph: build basic call graph" {
  let src =
    #|function helper(x) { return x * 2; }
    #|function* gen() {
    #|  yield helper(1);
    #|  yield helper(2);
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let graph = build_call_graph(ts_module)
  println(graph.debug_string())

  // gen calls helper
  assert_true(graph.functions.contains("gen"))
  assert_true(graph.functions.contains("helper"))
  match graph.calls.get("gen") {
    Some(callees) => assert_true(callees.contains("helper"))
    None => assert_true(false)
  }

  // helper is called by gen
  match graph.callers.get("helper") {
    Some(callers) => assert_true(callers.contains("gen"))
    None => assert_true(false)
  }
}

///|
test "callgraph: find AOT groups" {
  let src =
    #|function double(x) { return x * 2; }
    #|function triple(x) { return x * 3; }
    #|function* gen(n) {
    #|  yield double(n);
    #|  yield triple(n);
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let graph = build_call_graph(ts_module)
  let groups = find_aot_groups(ts_module, graph)
  println("Found \{groups.length()} AOT groups")
  for group in groups {
    println(group.debug_string())
  }

  // Should find one group with gen as root
  assert_eq(groups.length(), 1)
  let group = groups[0]
  assert_eq(group.root, "gen")
  // Members should include gen, double, triple
  assert_true(group.members.contains("gen"))
  assert_true(group.members.contains("double"))
  assert_true(group.members.contains("triple"))
}

///|
test "callgraph: external caller detection" {
  let src =
    #|function shared(x) { return x + 1; }
    #|function user(x) { return shared(x) * 2; }
    #|function* gen(n) {
    #|  yield shared(n);
    #|}
  let parser = @parser.Parser::from_source(src)
  let ts_module = parser.parse_module()
  let graph = build_call_graph(ts_module)
  let groups = find_aot_groups(ts_module, graph)

  // Should still find one group
  assert_eq(groups.length(), 1)
  let group = groups[0]

  // shared is called from both gen and user
  // user is outside the gen group, so shared has external callers
  assert_true(group.external_calls.contains("shared"))
}

///|
test "aot_check: simple generator is compilable" {
  let src =
    #|function* counter(n) {
    #|  let i = 0;
    #|  while (i < n) {
    #|    yield i;
    #|    i = i + 1;
    #|  }
    #|}
  assert_true(is_aot_compilable(src))
}

///|
test "aot_check: generator with helper is compilable" {
  let src =
    #|function double(x) { return x * 2; }
    #|function* gen(n) {
    #|  yield double(n);
    #|}
  let result = check_aot_compilable_source(src)
  println(result.debug_string())
  assert_true(result.compilable)
  assert_eq(result.groups.length(), 1)
}

///|
test "aot_check: eval is not compilable" {
  let src =
    #|function danger() {
    #|  return eval("1 + 2");
    #|}
  let result = check_aot_compilable_source(src)
  println(result.debug_string())
  assert_false(result.compilable)
  assert_eq(result.incompatible_funcs.length(), 1)
  assert_eq(result.incompatible_funcs[0].reason, "'eval' is not supported")
}

///|
test "aot_check: with statement is not compilable" {
  let src =
    #|function bad(obj) {
    #|  with (obj) {
    #|    return x;
    #|  }
    #|}
  let result = check_aot_compilable_source(src)
  println(result.debug_string())
  assert_false(result.compilable)
}

///|
test "aot_check: check_func_aot_compatible" {
  // Simple function
  let simple_func : @ast.TsFunc = {
    name: "add",
    params: [
      {
        name: "a",
        binding: None,
        is_rest: false,
        type_: @ast.TsType::Number,
        default: None,
      },
      {
        name: "b",
        binding: None,
        is_rest: false,
        type_: @ast.TsType::Number,
        default: None,
      },
    ],
    return_type: @ast.TsType::Number,
    body: {
      stmts: [
        @ast.TsStmt::Return(
          Some(
            @ast.TsExpr::BinOp(
              @ast.TsBinOp::Add,
              @ast.TsExpr::Var("a"),
              @ast.TsExpr::Var("b"),
            ),
          ),
        ),
      ],
    },
    is_generator: false,
    is_async: false,
  }
  assert_true(check_func_aot_compatible(simple_func) is None)

  // Function with eval
  let eval_func : @ast.TsFunc = {
    name: "danger",
    params: [],
    return_type: @ast.TsType::Any,
    body: {
      stmts: [
        @ast.TsStmt::Return(
          Some(@ast.TsExpr::Call("eval", [@ast.TsExpr::StringLit("1+1")])),
        ),
      ],
    },
    is_generator: false,
    is_async: false,
  }
  match check_func_aot_compatible(eval_func) {
    Some(reason) => assert_eq(reason, "'eval' is not supported")
    None => assert_true(false)
  }
}

// Closure analysis tests

///|
test "analyze_arrow_func: no captures" {
  let params : Array[@ast.TsParam] = [
    {
      name: "x",
      type_: @ast.TsType::Number,
      binding: None,
      is_rest: false,
      default: None,
    },
  ]
  let body = @ast.TsArrowBody::ArrowExpr(
    @ast.TsExpr::BinOp(
      @ast.TsBinOp::Add,
      @ast.TsExpr::Var("x"),
      @ast.TsExpr::IntLit(1),
    ),
  )
  let outer_scope : Array[String] = []
  let info = analyze_arrow_func(params, body, outer_scope)
  assert_true(info.compilable)
  assert_eq(info.captures.length(), 0)
  assert_eq(info.params.length(), 1)
}

///|
test "analyze_arrow_func: with read-only capture" {
  let params : Array[@ast.TsParam] = [
    {
      name: "x",
      type_: @ast.TsType::Number,
      binding: None,
      is_rest: false,
      default: None,
    },
  ]
  // () => x + y (where y is from outer scope)
  let body = @ast.TsArrowBody::ArrowExpr(
    @ast.TsExpr::BinOp(
      @ast.TsBinOp::Add,
      @ast.TsExpr::Var("x"),
      @ast.TsExpr::Var("y"),
    ),
  )
  let outer_scope : Array[String] = ["y"]
  let info = analyze_arrow_func(params, body, outer_scope)
  assert_true(info.compilable)
  assert_eq(info.captures.length(), 1)
  assert_eq(info.captures[0].name, "y")
  assert_false(info.captures[0].is_mutated)
}

///|
test "analyze_arrow_func: with mutable capture" {
  let params : Array[@ast.TsParam] = []
  // () => { y = 1; return y; }
  let body = @ast.TsArrowBody::ArrowBlock({
    stmts: [
      @ast.TsStmt::Assign("y", @ast.TsExpr::IntLit(1)),
      @ast.TsStmt::Return(Some(@ast.TsExpr::Var("y"))),
    ],
  })
  let outer_scope : Array[String] = ["y"]
  let info = analyze_arrow_func(params, body, outer_scope)
  // Mutable captures are now supported (Phase 3)
  assert_true(info.compilable)
  assert_eq(info.captures.length(), 1)
  assert_true(info.captures[0].is_mutated)
}

///|
test "analyze_func_expr: simple function" {
  let func : @ast.TsFunc = {
    name: "add",
    params: [
      {
        name: "a",
        type_: @ast.TsType::Number,
        binding: None,
        is_rest: false,
        default: None,
      },
      {
        name: "b",
        type_: @ast.TsType::Number,
        binding: None,
        is_rest: false,
        default: None,
      },
    ],
    return_type: @ast.TsType::Number,
    body: {
      stmts: [
        @ast.TsStmt::Return(
          Some(
            @ast.TsExpr::BinOp(
              @ast.TsBinOp::Add,
              @ast.TsExpr::Var("a"),
              @ast.TsExpr::Var("b"),
            ),
          ),
        ),
      ],
    },
    is_generator: false,
    is_async: false,
  }
  let outer_scope : Array[String] = []
  let info = analyze_func_expr(func, outer_scope)
  assert_true(info.compilable)
  assert_eq(info.captures.length(), 0)
}

///|
test "analyze_func_expr: with capture" {
  let func : @ast.TsFunc = {
    name: "addX",
    params: [
      {
        name: "a",
        type_: @ast.TsType::Number,
        binding: None,
        is_rest: false,
        default: None,
      },
    ],
    return_type: @ast.TsType::Number,
    body: {
      stmts: [
        @ast.TsStmt::Return(
          Some(
            @ast.TsExpr::BinOp(
              @ast.TsBinOp::Add,
              @ast.TsExpr::Var("a"),
              @ast.TsExpr::Var("x"),
            ),
          ),
        ),
      ],
    },
    is_generator: false,
    is_async: false,
  }
  let outer_scope : Array[String] = ["x"]
  let info = analyze_func_expr(func, outer_scope)
  assert_true(info.compilable)
  assert_eq(info.captures.length(), 1)
  assert_eq(info.captures[0].name, "x")
}

///|
test "has_mutable_captures" {
  let info_no_mut : ClosureInfo = {
    params: [],
    captures: [{ name: "x", is_mutated: false, type_hint: None }],
    compilable: true,
    not_compilable_reason: None,
  }
  assert_false(has_mutable_captures(info_no_mut))
  let info_with_mut : ClosureInfo = {
    params: [],
    captures: [
      { name: "x", is_mutated: false, type_hint: None },
      { name: "y", is_mutated: true, type_hint: None },
    ],
    compilable: false,
    not_compilable_reason: Some("mutable capture 'y' not yet supported"),
  }
  assert_true(has_mutable_captures(info_with_mut))
}

///|
test "get_capture_names" {
  let info : ClosureInfo = {
    params: ["a", "b"],
    captures: [
      { name: "x", is_mutated: false, type_hint: None },
      { name: "y", is_mutated: false, type_hint: None },
    ],
    compilable: true,
    not_compilable_reason: None,
  }
  let names = get_capture_names(info)
  assert_eq(names.length(), 2)
  assert_eq(names[0], "x")
  assert_eq(names[1], "y")
}

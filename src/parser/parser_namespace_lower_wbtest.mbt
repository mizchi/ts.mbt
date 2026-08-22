// Tests for the runtime-namespace lowering.

///|
fn ns_block_of(source : String) -> @ast.TsBlock {
  let parsed = Parser::from_source(source).parse_module_block() catch {
    e => abort("parse error: \{e}")
  }
  parsed.block
}

///|
/// Names a lowered namespace assigns onto its namespace object, in
/// source order.
fn ns_assigned_members(block : @ast.TsBlock, name : String) -> Array[String] {
  let out : Array[String] = []
  fn walk(b : @ast.TsBlock) -> Unit {
    for stmt in b.stmts {
      match stmt {
        @ast.TsStmt::PropAssign(@ast.TsExpr::Var(n), prop, _) =>
          if n == name {
            out.push(prop)
          }
        @ast.TsStmt::Block(inner) => walk(inner)
        @ast.TsStmt::Expr(
          @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(f), _)
        ) => walk(f.body)
        @ast.TsStmt::Expr(
          @ast.TsExpr::MethodCall(
            @ast.TsExpr::Var("Object"),
            "defineProperty",
            args
          )
        ) =>
          if args.length() >= 2 {
            match (args[0], args[1]) {
              (@ast.TsExpr::Var(n), @ast.TsExpr::StringLit(prop)) =>
                if n == name {
                  out.push(prop)
                }
              _ => ()
            }
          }
        _ => ()
      }
    }
  }

  walk(block)
  out
}

///|
/// True when the block declares `name` as a `var` (the namespace object
/// binding, which has to be a `var` for declaration merging).
fn ns_declares_var(block : @ast.TsBlock, name : String) -> Bool {
  fn walk(b : @ast.TsBlock) -> Bool {
    for stmt in b.stmts {
      match stmt {
        @ast.TsStmt::Var(@ast.TsBinding::Ident(n), _, _) =>
          if n == name {
            return true
          }
        @ast.TsStmt::Block(inner) => if walk(inner) { return true }
        _ => ()
      }
    }
    false
  }

  walk(block)
}

///|
test "namespace lowering: exported members are assigned onto the object" {
  let block = ns_block_of(
    #|namespace N {
    #|  const secret = 1;
    #|  export function f() { return secret; }
    #|  export const label = "x";
    #|}
    ,
  )
  assert_true(ns_declares_var(block, "N"))
  let members = ns_assigned_members(block, "N")
  assert_true(members.contains("f"))
  assert_true(members.contains("label"))
  // A non-exported local stays private to the closure.
  assert_false(members.contains("secret"))
}

///|
test "namespace lowering: `export let` is published as a live getter" {
  // A snapshot assignment would go stale the first time the namespace
  // mutates the binding, so the lowering routes mutable exports through
  // `Object.defineProperty`.
  let block = ns_block_of(
    #|namespace C {
    #|  export let count = 0;
    #|  export function inc() { count = count + 1; }
    #|}
    ,
  )
  let members = ns_assigned_members(block, "C")
  assert_true(members.contains("count"))
  assert_true(members.contains("inc"))
  let mut has_define_property = false
  fn walk(b : @ast.TsBlock) -> Unit {
    for stmt in b.stmts {
      match stmt {
        @ast.TsStmt::Block(inner) => walk(inner)
        @ast.TsStmt::Expr(
          @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(f), _)
        ) => walk(f.body)
        @ast.TsStmt::Expr(
          @ast.TsExpr::MethodCall(@ast.TsExpr::Var("Object"), "defineProperty", _)
        ) => has_define_property = true
        _ => ()
      }
    }
  }

  walk(block)
  assert_true(has_define_property)
}

///|
test "namespace lowering: a type-only member gets no runtime assignment" {
  let block = ns_block_of(
    #|namespace T {
    #|  export type Shape = { v: number };
    #|  export interface Other { w: number }
    #|  export const value = 1;
    #|}
    ,
  )
  let members = ns_assigned_members(block, "T")
  assert_true(members.contains("value"))
  assert_false(members.contains("Shape"))
  assert_false(members.contains("Other"))
}

///|
test "namespace lowering: `export namespace` lowers and stays exported" {
  let parsed = Parser::from_source(
      #|export namespace P {
      #|  export function hello() { return "hi"; }
      #|}
    ).parse_module_block()
    catch {
      e => abort("parse error: \{e}")
    }
  assert_true(ns_declares_var(parsed.block, "P"))
  assert_true(ns_assigned_members(parsed.block, "P").contains("hello"))
  let mut exported = false
  for spec in parsed.exports {
    if spec.export_name == "P" {
      exported = true
    }
  }
  assert_true(exported)
}

///|
test "namespace lowering: a nested namespace lowers too" {
  let block = ns_block_of(
    #|namespace Outer {
    #|  export namespace Inner {
    #|    export const v = 1;
    #|  }
    #|}
    ,
  )
  assert_true(ns_declares_var(block, "Outer"))
  assert_true(ns_assigned_members(block, "Outer").contains("Inner"))
  assert_true(ns_assigned_members(block, "Inner").contains("v"))
}

///|
test "namespace lowering: an empty namespace still declares the object" {
  let block = ns_block_of("namespace E {}\n")
  assert_true(ns_declares_var(block, "E"))
}

///|
test "namespace lowering: a dotted path is left alone" {
  // `namespace A.B { … }` isn't modelled; it must not be half-lowered.
  let block = ns_block_of(
    #|namespace A.B {
    #|  export const v = 1;
    #|}
    ,
  )
  assert_false(ns_declares_var(block, "A"))
}

///|
test "value declarations: a numeric literal is `number`, not `int`" {
  // TypeScript has one numeric type. `Int` is the MoonBit bridge's
  // marker; recording it for a TS `const` made the binding
  // unassignable to a `number` slot and to itself after arithmetic.
  let module_ = Parser::from_source("const v = 1;\n").parse_module() catch {
    e => abort("parse error: \{e}")
  }
  let mut found = false
  for value in module_.values {
    if value.name == "v" {
      found = true
      assert_true(value.type_ is @ast.TsType::Number)
    }
  }
  assert_true(found)
}

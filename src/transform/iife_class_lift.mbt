// Lift IIFE-lowered classes back to native `class Name { … }` syntax.
//
// The parser's class-desugar produces IIFE-shaped runtime code for
// classes that don't `extends` another class:
//
//   let Foo = function () {
//     "use strict";
//     let __super_proto = Function.prototype;
//     function Foo() { … }                       // constructor
//     Foo.__super_proto = Object.prototype;      // metadata
//     Foo.prototype.start = function start() {}; // method
//     Foo.prototype.start.__super_proto = ...;   // metadata
//     return Foo;
//   }();
//
// This shape is byte-heavy. When the body matches the simple
// constructor + methods + metadata pattern (no static blocks,
// decorators, computed keys, or private fields), it's safe to
// rewrite back into a native ES2015 class:
//
//   class Foo {
//     constructor() { … }
//     start() {}
//   }
//
// Constraints (anything outside aborts the lift for that class):
//   - The IIFE body contains: an optional `"use strict"` directive,
//     an optional `let __super_proto = …`, the constructor
//     `function Foo() { … }`, zero or more method-assignments
//     `Foo.prototype.METHOD = function METHOD() { … }`, each
//     optionally followed by `Foo.prototype.METHOD.<meta> = …`,
//     other `Foo.<meta> = …` lines, and a final `return Foo;`.
//   - The constructor function's name matches the outer binding.
//   - Every method assignment uses a `FuncExpr` literal (not an
//     arrow function — `this` semantics differ).
//   - Nothing else: no static-field assigns, no decorator
//     applications, no `Object.defineProperty` calls.

///|
pub fn iife_class_lift_block(block : @ast.TsBlock) -> @ast.TsBlock {
  let new_stmts : Array[@ast.TsStmt] = []
  let new_positions : Array[Int] = []
  let has_positions = block.stmt_positions.length() == block.stmts.length()
  for i, s in block.stmts {
    let lifted = try_lift_iife_class(s)
    new_stmts.push(lifted)
    if has_positions {
      new_positions.push(block.stmt_positions[i])
    }
  }
  { stmts: new_stmts, stmt_positions: new_positions }
}

///|
fn try_lift_iife_class(stmt : @ast.TsStmt) -> @ast.TsStmt {
  // Match the outer shape: `Var|Let|Const(Ident(name), _,
  // CallExpr(FuncExpr(f), []))`.
  match stmt {
    Var(b, t, e) =>
      match try_lift_iife_value(b, e) {
        Some(s) => s
        None => Var(b, t, e)
      }
    Let(b, t, e) =>
      match try_lift_iife_value(b, e) {
        Some(s) => s
        None => Let(b, t, e)
      }
    Const(b, t, e) =>
      match try_lift_iife_value(b, e) {
        Some(s) => s
        None => Const(b, t, e)
      }
    _ => stmt
  }
}

///|
fn try_lift_iife_value(
  b : @ast.TsBinding,
  e : @ast.TsExpr,
) -> @ast.TsStmt? {
  let name = match b {
    @ast.TsBinding::Ident(n) => n
    _ => return None
  }
  let body = match e {
    CallExpr(@ast.TsExpr::FuncExpr(f), args) =>
      if args.length() == 0 && f.params.length() == 0 {
        f.body
      } else {
        return None
      }
    _ => return None
  }
  // Walk the IIFE body, classifying each statement.
  let mut ctor_func : @ast.TsFunc? = None
  let methods : Array[@ast.TsClassMethodDecl] = []
  let static_methods : Array[@ast.TsClassMethodDecl] = []
  let mut saw_return = false
  for s in body.stmts {
    if saw_return {
      // Anything after the `return ClassName;` would be dead, but
      // the presence of dead code itself is suspicious. Abort.
      return None
    }
    match classify_iife_body_stmt(s, name) {
      Skipped => ()
      Ctor(f) =>
        match ctor_func {
          Some(_) => return None // Two constructors? Bail.
          None => ctor_func = Some(f)
        }
      Method(decl) => methods.push(decl)
      StaticMethod(decl) => static_methods.push(decl)
      ReturnsClassName => saw_return = true
      Unknown => return None
    }
  }
  if not(saw_return) {
    return None
  }
  // Merge instance + static methods (preserves order: instance
  // first, then static — emit doesn't care about order).
  let all_methods : Array[@ast.TsClassMethodDecl] = []
  for m in methods {
    all_methods.push(m)
  }
  for m in static_methods {
    all_methods.push(m)
  }
  let decl : @ast.TsClassDecl = {
    name,
    type_params: [],
    base_names: [],
    base_expr: None,
    static_field_inits: [],
    constructor_params: None,
    properties: [],
    methods: all_methods,
    is_abstract: false,
    is_constructible: true,
    index_signatures: [],
    decorators: [],
  }
  Some(NativeClassStmt(decl, ctor_func))
}

///|
priv enum IifeBodyClassification {
  Skipped
  Ctor(@ast.TsFunc)
  Method(@ast.TsClassMethodDecl)
  StaticMethod(@ast.TsClassMethodDecl)
  ReturnsClassName
  Unknown
}

///|
fn classify_iife_body_stmt(
  stmt : @ast.TsStmt,
  class_name : String,
) -> IifeBodyClassification {
  match stmt {
    // `"use strict";` directive.
    Expr(@ast.TsExpr::StringLit("use strict")) => Skipped
    // `let __super_proto = ...;` — metadata; skip.
    Let(@ast.TsBinding::Ident("__super_proto"), _, _)
    | Const(@ast.TsBinding::Ident("__super_proto"), _, _)
    | Var(@ast.TsBinding::Ident("__super_proto"), _, _) => Skipped
    // `function ClassName() {…}` — the constructor.
    Let(@ast.TsBinding::Ident(n), _, @ast.TsExpr::FuncExpr(f))
    | Const(@ast.TsBinding::Ident(n), _, @ast.TsExpr::FuncExpr(f))
    | Var(@ast.TsBinding::Ident(n), _, @ast.TsExpr::FuncExpr(f)) =>
      if n == class_name {
        // Promote the function expression to a constructor candidate.
        // Rename to "constructor" so emit produces the correct keyword.
        Ctor({
          ..f,
          name: "constructor",
        })
      } else {
        Unknown
      }
    // `ClassName.prototype.METHOD = function METHOD() {…};` —
    // instance method.
    PropAssign(
      @ast.TsExpr::PropAccess(@ast.TsExpr::Var(n), "prototype"),
      method_name,
      @ast.TsExpr::FuncExpr(f),
    ) =>
      if n == class_name {
        Method(method_decl_from_func(method_name, f, false))
      } else {
        Unknown
      }
    // `ClassName.METHOD = function METHOD() {…};` — static method.
    // Filtered to exclude metadata keys (`__super_proto`,
    // `__brand__`, etc.).
    PropAssign(
      @ast.TsExpr::Var(n),
      prop_name,
      @ast.TsExpr::FuncExpr(f),
    ) =>
      if n == class_name && not(is_class_metadata_key(prop_name)) {
        StaticMethod(method_decl_from_func(prop_name, f, true))
      } else if n == class_name {
        Skipped
      } else {
        Unknown
      }
    // `ClassName.prototype.METHOD.<meta> = …;` — chained metadata.
    PropAssign(
      @ast.TsExpr::PropAccess(
        @ast.TsExpr::PropAccess(@ast.TsExpr::Var(n), "prototype"),
        _,
      ),
      _,
      _,
    ) => if n == class_name { Skipped } else { Unknown }
    // `ClassName.METHOD.<meta> = …;` (chained static metadata).
    PropAssign(
      @ast.TsExpr::PropAccess(@ast.TsExpr::Var(n), _),
      _,
      _,
    ) => if n == class_name { Skipped } else { Unknown }
    // `ClassName.<meta> = …;` — top-level class metadata that isn't
    // a static method (e.g. `__super_proto`).
    PropAssign(@ast.TsExpr::Var(n), prop_name, _) =>
      if n == class_name && is_class_metadata_key(prop_name) {
        Skipped
      } else {
        Unknown
      }
    // `return ClassName;` — the IIFE's value.
    Return(Some(@ast.TsExpr::Var(n))) =>
      if n == class_name {
        ReturnsClassName
      } else {
        Unknown
      }
    _ => Unknown
  }
}

///|
fn is_class_metadata_key(name : String) -> Bool {
  name == "__super_proto" ||
  name == "__brand__" ||
  name.has_prefix("__private_brand__")
}

///|
fn method_decl_from_func(
  name : String,
  f : @ast.TsFunc,
  is_static : Bool,
) -> @ast.TsClassMethodDecl {
  // Map TsParam list back into the class-method shape
  // (Array[(String, TsType)]).
  let params : Array[(String, @ast.TsType)] = []
  for p in f.params {
    params.push((p.name, p.type_))
  }
  {
    name,
    type_params: f.type_params,
    type_param_bounds: [],
    params,
    return_type: f.return_type,
    is_static,
    body: Some(f.body),
    accessor: "",
  }
}

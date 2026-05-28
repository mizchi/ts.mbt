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
    let lifted : Array[@ast.TsStmt] = []
    try_lift_iife_class_into(s, lifted)
    for ls in lifted {
      new_stmts.push(ls)
      if has_positions {
        new_positions.push(block.stmt_positions[i])
      }
    }
  }
  { stmts: new_stmts, stmt_positions: new_positions }
}

///|
fn try_lift_iife_class_into(stmt : @ast.TsStmt, out : Array[@ast.TsStmt]) -> Unit {
  // Match the outer shape: `Var|Let|Const(Ident(name), _,
  // CallExpr(FuncExpr(f), []))`.
  match stmt {
    Var(b, t, e) =>
      if not(try_lift_iife_value(b, e, out)) {
        out.push(Var(b, t, e))
      }
    Let(b, t, e) =>
      if not(try_lift_iife_value(b, e, out)) {
        out.push(Let(b, t, e))
      }
    Const(b, t, e) =>
      if not(try_lift_iife_value(b, e, out)) {
        out.push(Const(b, t, e))
      }
    _ => out.push(stmt)
  }
}

///|
// Returns `true` when the lift succeeded (output pushed into `out`),
// `false` when the shape didn't match and the original statement
// should be kept verbatim.
fn try_lift_iife_value(
  b : @ast.TsBinding,
  e : @ast.TsExpr,
  out : Array[@ast.TsStmt],
) -> Bool {
  let name = match b {
    @ast.TsBinding::Ident(n) => n
    _ => return false
  }
  // Accept both `(function() { … })()` (no extends) and
  // `(function(_Super) { … })(Base)` (single-arg extends pattern).
  let (body, super_param, super_arg) : (@ast.TsBlock, String?, @ast.TsExpr?) = match e {
    CallExpr(@ast.TsExpr::FuncExpr(f), args) =>
      if args.length() == 0 && f.params.length() == 0 {
        (f.body, None, None)
      } else if args.length() == 1 && f.params.length() == 1 {
        (f.body, Some(f.params[0].name), Some(args[0]))
      } else {
        return false
      }
    _ => return false
  }
  // Walk the IIFE body, classifying each statement.
  let mut ctor_func : @ast.TsFunc? = None
  let methods : Array[@ast.TsClassMethodDecl] = []
  let static_methods : Array[@ast.TsClassMethodDecl] = []
  // Extra statements to emit AFTER the class declaration.
  let extra_stmts : Array[@ast.TsStmt] = []
  let mut saw_return = false
  for s in body.stmts {
    if saw_return {
      // Anything after the `return ClassName;` would be dead, but
      // the presence of dead code itself is suspicious. Abort.
      return false
    }
    match classify_iife_body_stmt(s, name, super_param) {
      Skipped => ()
      Ctor(f) =>
        match ctor_func {
          Some(_) => return false // Two constructors? Bail.
          None => ctor_func = Some(f)
        }
      Method(decl) => methods.push(decl)
      Methods(decls) => for d in decls { methods.push(d) }
      StaticMethod(decl) => static_methods.push(decl)
      ReturnsClassName => saw_return = true
      Extra(extra) => extra_stmts.push(extra)
      Unknown => return false
    }
  }
  if not(saw_return) {
    return false
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
  let (base_names, base_expr) : (Array[String], @ast.TsExpr?) = match super_arg {
    Some(arg) => (["<expr-base>"], Some(arg))
    None => ([], None)
  }
  // When the class extends a super, rewrite `_Super.call(this, a, b)`
  // in the constructor body to `super(a, b)` so the lifted native
  // class emits valid ES6.
  let ctor_func = match (ctor_func, super_param) {
    (Some(f), Some(sp)) => Some({ ..f, body: rewrite_super_calls(f.body, sp) })
    _ => ctor_func
  }
  let decl : @ast.TsClassDecl = {
    name,
    type_params: [],
    base_names,
    base_expr,
    static_field_inits: [],
    constructor_params: None,
    properties: [],
    methods: all_methods,
    is_abstract: false,
    is_constructible: true,
    index_signatures: [],
    decorators: [],
  }
  out.push(NativeClassStmt(decl, ctor_func))
  // Append the extra side-effect statements after the class.
  for s in extra_stmts {
    out.push(s)
  }
  true
}

///|
priv enum IifeBodyClassification {
  Skipped
  Ctor(@ast.TsFunc)
  Method(@ast.TsClassMethodDecl)
  // Multiple methods from one statement (e.g. Object.defineProperty with
  // both get and set accessor entries).
  Methods(Array[@ast.TsClassMethodDecl])
  StaticMethod(@ast.TsClassMethodDecl)
  ReturnsClassName
  // A statement that isn't a class shape but is safe to move after
  // the class declaration. This allows `allMethods.forEach(…)` style
  // dynamic-method-registration calls to live in the IIFE body
  // without aborting the lift — they're appended as regular
  // statements following the `class` declaration.
  Extra(@ast.TsStmt)
  Unknown
}

///|
fn classify_iife_body_stmt(
  stmt : @ast.TsStmt,
  class_name : String,
  super_param : String?,
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
        Ctor({ ..f, name: "constructor" })
      } else {
        Unknown
      }
    // `ClassName.prototype.METHOD = function METHOD() {…};` —
    // instance method.
    PropAssign(
      @ast.TsExpr::PropAccess(@ast.TsExpr::Var(n), "prototype"),
      method_name,
      @ast.TsExpr::FuncExpr(f)
    ) =>
      if n == class_name {
        Method(method_decl_from_func(method_name, f, false))
      } else {
        Unknown
      }
    // `ClassName.METHOD = function METHOD() {…};` — static method.
    // Filtered to exclude metadata keys (`__super_proto`,
    // `__brand__`, etc.).
    PropAssign(@ast.TsExpr::Var(n), prop_name, @ast.TsExpr::FuncExpr(f)) =>
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
        _
      ),
      _,
      _
    ) => if n == class_name { Skipped } else { Unknown }
    // `ClassName.METHOD.<meta> = …;` (chained static metadata).
    PropAssign(@ast.TsExpr::PropAccess(@ast.TsExpr::Var(n), _), _, _) =>
      if n == class_name {
        Skipped
      } else {
        Unknown
      }
    // `ClassName.<meta> = …;` — top-level class metadata that isn't
    // a static method (e.g. `__super_proto`).
    PropAssign(@ast.TsExpr::Var(n), prop_name, _) =>
      if n == class_name && is_class_metadata_key(prop_name) {
        Skipped
      } else {
        Unknown
      }
    // Prototype-chain setup for `extends` — skip all of these forms:
    // `ClassName.prototype.__proto__ = _Super.prototype`
    // `ClassName.__proto__ = _Super`
    PropAssign(
      @ast.TsExpr::PropAccess(@ast.TsExpr::Var(n), "prototype"),
      "__proto__",
      _
    )
    | PropAssign(@ast.TsExpr::Var(n), "__proto__", _) =>
      if n == class_name { Skipped } else { Unknown }
    // `_inheritsLoose(ClassName, _Super)` / `_inherits(ClassName, _Super)` /
    // `__extends(ClassName, _Super)` (TypeScript emitted helper)
    Expr(@ast.TsExpr::CallExpr(@ast.TsExpr::Var(fn_name), args)) =>
      if (fn_name.has_prefix("_inherit") || fn_name == "__extends") &&
         args.length() >= 1 {
        match args[0] {
          @ast.TsExpr::Var(n) => if n == class_name { Skipped } else { Unknown }
          _ => Unknown
        }
      } else {
        Unknown
      }
    // `Object.setPrototypeOf(ClassName.prototype, _Super.prototype)`
    Expr(
      @ast.TsExpr::MethodCall(
        @ast.TsExpr::Var("Object"),
        "setPrototypeOf",
        _
      )
    ) =>
      match super_param {
        Some(_) => Skipped
        None => Unknown
      }
    // `Object.defineProperty(ClassName.prototype, "prop", { get: fn, set: fn, … })`
    // TypeScript emits this for class getters/setters. Convert to native class
    // accessor method declarations.
    Expr(
      @ast.TsExpr::MethodCall(
        @ast.TsExpr::Var("Object"),
        "defineProperty",
        [
          @ast.TsExpr::PropAccess(@ast.TsExpr::Var(recv_name), "prototype"),
          @ast.TsExpr::StringLit(prop_name),
          @ast.TsExpr::ObjectLit(descriptor),
        ]
      )
    ) =>
      if recv_name == class_name {
        let accessors : Array[@ast.TsClassMethodDecl] = []
        let mut all_ok = true
        for entry in descriptor {
          match (entry.0, entry.1) {
            ("get", @ast.TsExpr::FuncExpr(f)) =>
              accessors.push(method_decl_from_func_accessor(prop_name, f, "get"))
            ("set", @ast.TsExpr::FuncExpr(f)) =>
              accessors.push(method_decl_from_func_accessor(prop_name, f, "set"))
            ("enumerable", _) | ("configurable", _) | ("writable", _) => ()
            _ => { all_ok = false; break }
          }
        }
        if all_ok && accessors.length() > 0 {
          Methods(accessors)
        } else {
          Unknown
        }
      } else {
        Unknown
      }
    // Any other top-level expression statement (e.g. `allMethods.forEach(…)`)
    // is a side-effect call. These are safe to move AFTER the class
    // declaration — they can still reference the class by name (the name
    // is in scope) and don't alter the class shape. Classify as `Extra`
    // so the lift can succeed while keeping the call.
    Expr(e) => Extra(Expr(e))
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
  let param_defaults : Array[@ast.TsExpr?] = []
  for p in f.params {
    params.push((p.name, p.type_))
    param_defaults.push(p.default)
  }
  {
    name,
    type_params: f.type_params,
    type_param_bounds: [],
    params,
    param_defaults,
    return_type: f.return_type,
    is_static,
    body: Some(f.body),
    accessor: "",
    key_expr: None,
    is_async: f.is_async,
    is_generator: f.is_generator,
  }
}

///|
/// Like `method_decl_from_func` but sets the `accessor` field to `"get"` or
/// `"set"` for native-class getter/setter syntax.
fn method_decl_from_func_accessor(
  name : String,
  f : @ast.TsFunc,
  accessor : String,
) -> @ast.TsClassMethodDecl {
  let params : Array[(String, @ast.TsType)] = []
  let param_defaults : Array[@ast.TsExpr?] = []
  for p in f.params {
    params.push((p.name, p.type_))
    param_defaults.push(p.default)
  }
  {
    name,
    type_params: f.type_params,
    type_param_bounds: [],
    params,
    param_defaults,
    return_type: f.return_type,
    is_static: false,
    body: Some(f.body),
    accessor,
    key_expr: None,
    is_async: f.is_async,
    is_generator: f.is_generator,
  }
}

///|
/// Rewrite `super_param.call(this, a, b)` → `super(a, b)` in the
/// constructor body. This makes the lifted native `class` valid ES6
/// when the IIFE pattern uses `_Super.call(this, ...)` for the super
/// constructor call.
fn rewrite_super_calls(block : @ast.TsBlock, super_param : String) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(rewrite_super_stmt(s, super_param))
  }
  { ..block, stmts }
}

///|
fn rewrite_super_stmt(stmt : @ast.TsStmt, sp : String) -> @ast.TsStmt {
  match stmt {
    Expr(e) => Expr(rewrite_super_expr(e, sp))
    Return(Some(e)) => Return(Some(rewrite_super_expr(e, sp)))
    If(c, t, el) =>
      If(
        rewrite_super_expr(c, sp),
        rewrite_super_block(t, sp),
        match el {
          Some(b) => Some(rewrite_super_block(b, sp))
          None => None
        },
      )
    Block(b) => Block(rewrite_super_block(b, sp))
    _ => stmt
  }
}

///|
fn rewrite_super_block(block : @ast.TsBlock, sp : String) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(rewrite_super_stmt(s, sp))
  }
  { ..block, stmts }
}

///|
fn rewrite_super_expr(expr : @ast.TsExpr, sp : String) -> @ast.TsExpr {
  match expr {
    // `_Super.call(this, a, b)` → `super(a, b)`
    MethodCall(@ast.TsExpr::Var(recv), "call", args) =>
      if recv == sp &&
         args.length() >= 1 &&
         (match args[0] {
           @ast.TsExpr::Var("this") => true
           _ => false
         }) {
        // Drop the leading `this` arg; the rest are the super() args.
        let super_args : Array[@ast.TsExpr] = []
        for i, a in args {
          if i > 0 {
            super_args.push(a)
          }
        }
        Call("super", super_args)
      } else {
        expr
      }
    // `_Super.apply(this, arguments)` → `super(...arguments)`
    // TypeScript emits this pattern for the default constructor in
    // derived classes: `_super.apply(this, arguments)`.
    MethodCall(@ast.TsExpr::Var(recv), "apply", args) =>
      if recv == sp &&
         args.length() >= 1 &&
         (match args[0] {
           @ast.TsExpr::Var("this") => true
           _ => false
         }) {
        let super_args : Array[@ast.TsExpr] = []
        for i, a in args {
          if i > 0 {
            super_args.push(Spread(a))
          }
        }
        Call("super", super_args)
      } else {
        expr
      }
    // `_Super !== null && _Super.apply(this, arguments) || this`
    // TypeScript 4+ default-constructor pattern. Map to `super(...arguments)`.
    BinOp(
      @ast.TsBinOp::Or,
      @ast.TsExpr::BinOp(@ast.TsBinOp::And, _, inner_apply),
      @ast.TsExpr::Var("this")
    ) => {
      let rewritten = rewrite_super_expr(inner_apply, sp)
      match rewritten {
        Call("super", _) => rewritten
        _ => expr
      }
    }
    _ => expr
  }
}

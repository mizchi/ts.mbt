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
fn try_lift_iife_class_into(
  stmt : @ast.TsStmt,
  out : Array[@ast.TsStmt],
) -> Unit {
  // Match the outer shape: `Var|Let|Const(Ident(name), _,
  // CallExpr(FuncExpr(f), []))`.
  match stmt {
    Var(b, t, e) =>
      if !try_lift_iife_value(b, e, out) {
        out.push(Var(b, t, e))
      }
    Let(b, t, e) =>
      if !try_lift_iife_value(b, e, out) {
        out.push(Let(b, t, e))
      }
    Const(b, t, e) =>
      if !try_lift_iife_value(b, e, out) {
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
  // Also handle `/* @__PURE__ */ (function() { … })()` (PureCall wrapper).
  let inner_e = match e {
    PureCall(inner) => inner
    _ => e
  }
  let (body, super_param, super_arg) : (@ast.TsBlock, String?, @ast.TsExpr?) = match
    inner_e {
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
  // If the inner function/class name differs from the outer variable name
  // (e.g. anonymous class expressions use `_anon` internally but the outer
  // binding may be `Context`, `HonoBase`, etc.), detect the inner name by
  // finding `return innerName` at the end of the body. Use `innerName` as
  // the effective class name so prototype assignments like
  // `_anon.prototype.method = …` and `return _anon` resolve correctly.
  let inner_name : String = {
    let mut found : String = name
    for s in body.stmts {
      match s {
        Return(Some(@ast.TsExpr::Var(ret_n))) => found = ret_n
        _ => ()
      }
    }
    found
  }
  // Pre-scan: collect `__get_NAME` / `__set_NAME` function definitions
  // that the parser emits for named getter/setter methods. These are
  // referenced by `PropAssign(proto, "@@get:NAME", Var("__get_NAME"))`.
  let accessor_funcs : Map[String, @ast.TsFunc] = {}
  for s in body.stmts {
    match s {
      Let(@ast.TsBinding::Ident(n), _, @ast.TsExpr::FuncExpr(f))
      | Const(@ast.TsBinding::Ident(n), _, @ast.TsExpr::FuncExpr(f))
      | Var(@ast.TsBinding::Ident(n), _, @ast.TsExpr::FuncExpr(f)) =>
        if n.has_prefix("__get_") || n.has_prefix("__set_") {
          accessor_funcs[n] = f
        }
      _ => ()
    }
  }
  // Walk the IIFE body, classifying each statement.
  let mut ctor_func : @ast.TsFunc? = None
  let methods : Array[@ast.TsClassMethodDecl] = []
  let static_methods : Array[@ast.TsClassMethodDecl] = []
  // Extra statements to emit AFTER the class declaration.
  let extra_stmts : Array[@ast.TsStmt] = []
  // Closure-variable statements to emit BEFORE the class so the class
  // body can still reference them.
  let pre_stmts : Array[@ast.TsStmt] = []
  let mut saw_return = false
  for s in body.stmts {
    if saw_return {
      // Dead code after `return ClassName;` — just skip it.
      continue
    }
    // Flatten Block stmts from multi-declarator `var a=1, b=2;`.
    let flat_stmts : Array[@ast.TsStmt] = match s {
      Block(inner) => inner.stmts
      _ => [s]
    }
    for fs in flat_stmts {
      match
        classify_iife_body_stmt(fs, inner_name, super_param, accessor_funcs) {
        Skipped => ()
        Ctor(f) =>
          match ctor_func {
            Some(_) => return false // Two constructors? Bail.
            None => ctor_func = Some(f)
          }
        Method(decl) => methods.push(decl)
        Methods(decls) =>
          for d in decls {
            methods.push(d)
          }
        StaticMethod(decl) => static_methods.push(decl)
        ReturnsClassName => saw_return = true
        Extra(extra) => extra_stmts.push(extra)
        ExtraBefore(pre) => pre_stmts.push(pre)
        Unknown => return false
      }
    }
  }
  if !saw_return {
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
  let (base_names, base_expr) : (Array[String], @ast.TsExpr?) = match
    super_arg {
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
  // Promote `ClassName.key = val` Extra stmts to static_field_inits so
  // downstream passes (fold, treeshake, inline) see them as part of the
  // class rather than stand-alone statements. Any Extra stmt that
  // doesn't match that shape stays as a post-class side-effect.
  let static_field_inits : Array[(String, @ast.TsExpr)] = []
  let side_effect_stmts : Array[@ast.TsStmt] = []
  for s in extra_stmts {
    match s {
      @ast.TsStmt::PropAssign(@ast.TsExpr::Var(n), key, val) if n == name ||
        n == inner_name => static_field_inits.push((key, val))
      _ => side_effect_stmts.push(s)
    }
  }
  let decl : @ast.TsClassDecl = {
    name,
    type_params: [],
    base_names,
    base_expr,
    static_field_inits,
    static_blocks: [],
    instance_field_inits: [],
    constructor_params: None,
    constructor_param_is_rest: [],
    constructor_param_defaults: [],
    constructor_body: None,
    properties: [],
    methods: all_methods,
    is_abstract: false,
    is_constructible: true,
    index_signatures: [],
    decorators: [],
    is_declare: false,
    private_members: [],
    protected_members: [],
    duplicate_member_names: [],
  }
  // Emit closure-variable declarations before the class so the class
  // body can still close over them.
  for s in pre_stmts {
    out.push(s)
  }
  // When the inner name differs from the outer name (anonymous class
  // expression pattern), rename all `inner_name` references to `name`
  // in method bodies, the constructor, and extra/pre stmts.
  let (final_decl, final_ctor) = if inner_name != name {
    let renamed_methods = all_methods.map(fn(m) {
      let new_body = match m.body {
        Some(b) => Some(rename_var_in_block(b, inner_name, name))
        None => None
      }
      { ..m, body: new_body }
    })
    let renamed_ctor = match ctor_func {
      Some(f) =>
        Some({ ..f, body: rename_var_in_block(f.body, inner_name, name) })
      None => None
    }
    ({ ..decl, methods: renamed_methods }, renamed_ctor)
  } else {
    (decl, ctor_func)
  }
  out.push(NativeClassStmt(final_decl, final_ctor))
  // Append remaining side-effect statements after the class.
  for s in side_effect_stmts {
    let s2 = if inner_name != name {
      rename_var_in_stmt(s, inner_name, name)
    } else {
      s
    }
    out.push(s2)
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
  // A statement that must be emitted BEFORE the class declaration
  // (e.g. a closure variable that the class methods capture). Hoisting
  // these before the class keeps them in scope for the class body.
  ExtraBefore(@ast.TsStmt)
  Unknown
}

///|
fn classify_iife_body_stmt(
  stmt : @ast.TsStmt,
  class_name : String,
  super_param : String?,
  accessor_funcs : Map[String, @ast.TsFunc],
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
      } else if n.has_prefix("__get_") || n.has_prefix("__set_") {
        // Accessor helper functions emitted by the parser for `get`/`set`
        // methods. These are consumed by the `@@get:` / `@@set:` PropAssign
        // handler below and should not be hoisted separately.
        Skipped
      } else {
        // A named function that isn't the class — likely a helper used
        // by the class body. Hoist it before the class so it's in scope.
        ExtraBefore(stmt)
      }
    // Non-function let/const/var — a closure variable captured by the
    // class methods (e.g. `var _count = 0`). Emit before the class
    // when the RHS does not reference the class name itself. If the
    // RHS references the class (e.g. `var _proto = ClassName.prototype`)
    // we must emit it AFTER the class definition instead, since class
    // declarations are not hoisted the way function declarations are.
    Let(@ast.TsBinding::Ident(n), _, rhs)
    | Const(@ast.TsBinding::Ident(n), _, rhs)
    | Var(@ast.TsBinding::Ident(n), _, rhs) =>
      if n == class_name {
        Unknown // non-function assignment to the class name — bail
      } else if expr_refs_class_name(rhs, class_name) {
        Extra(stmt) // rhs uses class — must come after the class decl
      } else {
        ExtraBefore(stmt)
      }
    // Destructuring bindings (`const [a, b] = arr`, `var {x} = obj`).
    // The binding pattern can never be the class name, so always safe.
    // Use ExtraBefore unless the RHS references the class.
    Let(_, _, rhs) | Const(_, _, rhs) | Var(_, _, rhs) =>
      if expr_refs_class_name(rhs, class_name) {
        Extra(stmt)
      } else {
        ExtraBefore(stmt)
      }
    // Empty statement — no-op.
    Empty => Skipped
    // `ClassName.prototype["@@get:VALUE"] = __get_VALUE;` —
    // Named getter/setter from the parser's `@@get:`/`@@set:` desugar.
    // The function body is stored in `accessor_funcs` under `__get_VALUE`.
    PropAssign(
      @ast.TsExpr::PropAccess(@ast.TsExpr::Var(n), "prototype"),
      marker_key,
      @ast.TsExpr::Var(accessor_tmp)
    ) if n == class_name &&
      (marker_key.has_prefix("@@get:") || marker_key.has_prefix("@@set:")) => {
      let (kind, prop_name) = if marker_key.has_prefix("@@get:") {
        ("get", marker_key[6:].to_owned())
      } else {
        ("set", marker_key[6:].to_owned())
      }
      match accessor_funcs.get(accessor_tmp) {
        Some(f) => Method(method_decl_from_func_accessor(prop_name, f, kind))
        None => Extra(stmt) // function definition not found — keep as-is
      }
    }
    // Also skip the __super_proto metadata on accessor temp vars.
    PropAssign(@ast.TsExpr::Var(n), "__super_proto", _) if accessor_funcs.contains(
        n,
      ) => Skipped
    // `ClassName.prototype.METHOD = function METHOD() {…};` —
    // instance method. For non-class-name receivers this is a side
    // effect (prototype augmentation of another class) that is safe
    // to emit after the class declaration.
    PropAssign(
      @ast.TsExpr::PropAccess(@ast.TsExpr::Var(n), "prototype"),
      method_name,
      @ast.TsExpr::FuncExpr(f)
    ) =>
      if n == class_name {
        Method(method_decl_from_func(method_name, f, false))
      } else {
        Extra(stmt)
      }
    // `ClassName.METHOD = function METHOD() {…};` — static method.
    // Filtered to exclude metadata keys (`__super_proto`,
    // `__brand__`, etc.). For non-class-name receivers this is a
    // side effect (function assigned to another object's property)
    // that is safe to emit after the class declaration.
    PropAssign(@ast.TsExpr::Var(n), prop_name, @ast.TsExpr::FuncExpr(f)) =>
      if n == class_name && !is_class_metadata_key(prop_name) {
        StaticMethod(method_decl_from_func(prop_name, f, true))
      } else if n == class_name {
        Skipped
      } else {
        Extra(stmt)
      }
    // `ClassName.prototype.METHOD.<meta> = …;` — chained metadata.
    // For non-class-name targets this is chained metadata on another
    // class — safe to emit after the class as a side effect.
    PropAssign(
      @ast.TsExpr::PropAccess(
        @ast.TsExpr::PropAccess(@ast.TsExpr::Var(n), "prototype"),
        _
      ),
      _,
      _
    ) => if n == class_name { Skipped } else { Extra(stmt) }
    // `ClassName.METHOD.<meta> = …;` (chained static metadata).
    // When `n` is some other variable, the chained prop-assign is a
    // side-effect statement that doesn't affect the class shape.
    PropAssign(@ast.TsExpr::PropAccess(@ast.TsExpr::Var(n), _), _, _) =>
      if n == class_name {
        Skipped
      } else {
        Extra(stmt)
      }
    // `ClassName.<meta> = …;` — top-level class metadata or static
    // field initializer. Metadata keys are silently dropped; non-function
    // static field assignments (`ClassName.version = "1.0"`) are moved
    // AFTER the class declaration as `Extra` so the lift still succeeds.
    // Assignments to other variables' properties are also side effects
    // that don't affect the class shape — emit them after the class.
    PropAssign(@ast.TsExpr::Var(n), prop_name, _) =>
      if n == class_name && is_class_metadata_key(prop_name) {
        Skipped
      } else if n == class_name {
        Extra(stmt)
      } else {
        // Assignment to some other object — safe as a side effect after
        // the class. Any ordering with respect to other Extra stmts is
        // preserved since all Extra stmts are emitted in source order.
        Extra(stmt)
      }
    // Prototype-chain setup for `extends` — skip all of these forms:
    // `ClassName.prototype.__proto__ = _Super.prototype`
    // `ClassName.__proto__ = _Super`
    // `_inheritsLoose(ClassName, _Super)` / `_inherits(ClassName, _Super)` /
    // `__extends(ClassName, _Super)` (TypeScript emitted helper)
    Expr(@ast.TsExpr::CallExpr(@ast.TsExpr::Var(fn_name), args)) =>
      if (fn_name.has_prefix("_inherit") || fn_name == "__extends") &&
        args.length() >= 1 {
        match args[0] {
          @ast.TsExpr::Var(n) =>
            if n == class_name {
              Skipped
            } else {
              // Inheritance setup for another class — safe as a side
              // effect after our class (the other class is not our target).
              Extra(stmt)
            }
          _ => Extra(stmt)
        }
      } else {
        // Any other bare-function call is a side-effect expression.
        // Fall through to the generic `Extra` path below.
        Extra(stmt)
      }
    // `Object.setPrototypeOf(ClassName.prototype, _Super.prototype)`
    Expr(
      @ast.TsExpr::MethodCall(@ast.TsExpr::Var("Object"), "setPrototypeOf", _)
    ) =>
      match super_param {
        Some(_) => Skipped
        // Not in an extends context but still a side-effect expr —
        // emit after the class rather than aborting the lift.
        None => Extra(stmt)
      }
    // `Object.defineProperty(ClassName.prototype, "prop", { get: fn, set: fn, … })`
    // TypeScript emits this for class getters/setters. Convert to native class
    // accessor method declarations.
    // Handles both MethodCall(Var("Object"), "defineProperty", [...]) and
    // Expr(CallExpr(PropAccess(Var("Object"), "defineProperty"), [...])) forms.
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
      | @ast.TsExpr::CallExpr(
        @ast.TsExpr::PropAccess(@ast.TsExpr::Var("Object"), "defineProperty"),
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
              accessors.push(
                method_decl_from_func_accessor(prop_name, f, "get"),
              )
            ("set", @ast.TsExpr::FuncExpr(f)) =>
              accessors.push(
                method_decl_from_func_accessor(prop_name, f, "set"),
              )
            ("enumerable", _) | ("configurable", _) | ("writable", _) => ()
            _ => {
              all_ok = false
              break
            }
          }
        }
        if all_ok && accessors.length() > 0 {
          Methods(accessors)
        } else {
          // Descriptor has unrecognised keys — keep as a side-effect
          // expression appended after the class rather than aborting.
          Extra(stmt)
        }
      } else {
        // defineProperty on a different object — keep as Extra.
        Extra(stmt)
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
    // `name = expr;` — plain assignment to a variable (not prop).
    // If the variable is the class name itself, bail (the IIFE is
    // reassigning the class, e.g. decorator wrapping). Otherwise
    // treat as a side-effect emitted AFTER the class. We don't hoist
    // assignments before the class even when the RHS is independent —
    // the original IIFE ran them after the constructor definition.
    Assign(n, _) => if n == class_name { Unknown } else { Extra(stmt) }
    // `name op= expr;` — compound assignment. Same ordering logic as
    // plain Assign: abort if it touches the class binding, otherwise
    // emit as a side effect (after, since the RHS might implicitly use
    // the current value of `name` which could reference the class).
    CompoundAssign(n, _, _) =>
      if n == class_name {
        Unknown
      } else {
        Extra(stmt)
      }
    // `recv[idx] = val;` — dynamic index assignment. Always emit after
    // the class (Extra) since the receiver may be a class instance or
    // prototype reference, and we want to avoid any forward-ref issues.
    IndexAssign(_, _, _) => Extra(stmt)
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
/// Returns `true` when `expr` contains a `Var(name)` reference at any
/// depth. Used to detect closure-variable declarations whose RHS reads
/// the class being lifted (e.g. `var _proto = ClassName.prototype`),
/// which must be emitted AFTER the class declaration rather than
/// before it.
fn expr_refs_class_name(expr : @ast.TsExpr, name : String) -> Bool {
  match expr {
    @ast.TsExpr::Var(n) => n == name
    @ast.TsExpr::PropAccess(recv, _) => expr_refs_class_name(recv, name)
    @ast.TsExpr::IndexAccess(recv, idx) =>
      expr_refs_class_name(recv, name) || expr_refs_class_name(idx, name)
    @ast.TsExpr::Call(n, args) => {
      if n == name {
        return true
      }
      for a in args {
        if expr_refs_class_name(a, name) {
          return true
        }
      }
      false
    }
    @ast.TsExpr::CallExpr(callee, args) => {
      if expr_refs_class_name(callee, name) {
        return true
      }
      for a in args {
        if expr_refs_class_name(a, name) {
          return true
        }
      }
      false
    }
    @ast.TsExpr::New(n, args) => {
      if n == name {
        return true
      }
      for a in args {
        if expr_refs_class_name(a, name) {
          return true
        }
      }
      false
    }
    @ast.TsExpr::NewExpr(callee, args) => {
      if expr_refs_class_name(callee, name) {
        return true
      }
      for a in args {
        if expr_refs_class_name(a, name) {
          return true
        }
      }
      false
    }
    @ast.TsExpr::MethodCall(recv, _, args) => {
      if expr_refs_class_name(recv, name) {
        return true
      }
      for a in args {
        if expr_refs_class_name(a, name) {
          return true
        }
      }
      false
    }
    @ast.TsExpr::BinOp(_, l, r) =>
      expr_refs_class_name(l, name) || expr_refs_class_name(r, name)
    @ast.TsExpr::UnaryOp(_, inner) => expr_refs_class_name(inner, name)
    @ast.TsExpr::Cond(c, t, e) =>
      expr_refs_class_name(c, name) ||
      expr_refs_class_name(t, name) ||
      expr_refs_class_name(e, name)
    @ast.TsExpr::ArrayLit(items) => {
      for item in items {
        if expr_refs_class_name(item, name) {
          return true
        }
      }
      false
    }
    @ast.TsExpr::ObjectLit(entries) => {
      for ent in entries {
        if expr_refs_class_name(ent.1, name) {
          return true
        }
      }
      false
    }
    @ast.TsExpr::AssignExpr(_, rhs) => expr_refs_class_name(rhs, name)
    @ast.TsExpr::Spread(inner) => expr_refs_class_name(inner, name)
    _ => false
  }
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
  let param_is_rest : Array[Bool] = []
  for p in f.params {
    params.push((p.name, p.type_))
    param_defaults.push(p.default)
    param_is_rest.push(p.is_rest)
  }
  {
    name,
    type_params: f.type_params,
    type_param_bounds: [],
    params,
    param_defaults,
    param_is_rest,
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
  let param_is_rest : Array[Bool] = []
  for p in f.params {
    params.push((p.name, p.type_))
    param_defaults.push(p.default)
    param_is_rest.push(p.is_rest)
  }
  {
    name,
    type_params: f.type_params,
    type_param_bounds: [],
    params,
    param_defaults,
    param_is_rest,
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
fn rewrite_super_calls(
  block : @ast.TsBlock,
  super_param : String,
) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(rewrite_super_stmt(s, super_param))
  }
  { ..block, stmts, }
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
  { ..block, stmts, }
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

///|
// Rename all `Var(from)` / `New(from, …)` references in an expression.
// Used to replace the inner class name with the outer class name after
// an IIFE whose inner constructor name differs from the outer binding.
fn rename_var_in_expr(
  expr : @ast.TsExpr,
  from : String,
  to : String,
) -> @ast.TsExpr {
  let re = fn(e) { rename_var_in_expr(e, from, to) }
  match expr {
    Var(n) => if n == from { Var(to) } else { expr }
    New(n, args) => New(if n == from { to } else { n }, args.map(re))
    NewExpr(callee, args) => NewExpr(re(callee), args.map(re))
    PropAccess(recv, p) => PropAccess(re(recv), p)
    IndexAccess(recv, idx) => IndexAccess(re(recv), re(idx))
    MethodCall(recv, m, args) => MethodCall(re(recv), m, args.map(re))
    CallExpr(callee, args) => CallExpr(re(callee), args.map(re))
    Call(n, args) => Call(n, args.map(re))
    BinOp(op, l, r) => BinOp(op, re(l), re(r))
    UnaryOp(op, operand) => UnaryOp(op, re(operand))
    Cond(c, t, e) => Cond(re(c), re(t), re(e))
    Seq(l, r) => Seq(re(l), re(r))
    Await(e) => Await(re(e))
    ArrayLit(items) => ArrayLit(items.map(re))
    Spread(e) => Spread(re(e))
    ObjectLit(pairs) => ObjectLit(pairs.map(p => (p.0, re(p.1))))
    AssignExpr(n, v) => AssignExpr(n, re(v))
    PropAssignExpr(recv, p, val) => PropAssignExpr(re(recv), p, re(val))
    CompoundAssignExpr(target, op, val) =>
      CompoundAssignExpr(re(target), op, re(val))
    IndexAssignExpr(recv, idx, val) =>
      IndexAssignExpr(re(recv), re(idx), re(val))
    _ => expr
  }
}

///|
fn rename_var_in_block(
  block : @ast.TsBlock,
  from : String,
  to : String,
) -> @ast.TsBlock {
  { ..block, stmts: block.stmts.map(s => rename_var_in_stmt(s, from, to)) }
}

///|
fn rename_var_in_stmt(
  stmt : @ast.TsStmt,
  from : String,
  to : String,
) -> @ast.TsStmt {
  let re = fn(e) { rename_var_in_expr(e, from, to) }
  let rb = fn(b) { rename_var_in_block(b, from, to) }
  match stmt {
    @ast.TsStmt::Expr(e) => Expr(re(e))
    @ast.TsStmt::Return(Some(e)) => Return(Some(re(e)))
    @ast.TsStmt::Let(b, t, e) => Let(b, t, re(e))
    @ast.TsStmt::Const(b, t, e) => Const(b, t, re(e))
    @ast.TsStmt::Var(b, t, e) => Var(b, t, re(e))
    @ast.TsStmt::Assign(n, e) => Assign(n, re(e))
    @ast.TsStmt::PropAssign(recv, p, val) => PropAssign(re(recv), p, re(val))
    @ast.TsStmt::IndexAssign(arr, idx, val) =>
      IndexAssign(re(arr), re(idx), re(val))
    @ast.TsStmt::If(c, t, e) => If(re(c), rb(t), e.map(rb))
    @ast.TsStmt::While(c, body) => While(re(c), rb(body))
    @ast.TsStmt::For(init, cond, update, body) =>
      For(
        init.map(s => rename_var_in_stmt(s, from, to)),
        cond.map(re),
        update.map(s => rename_var_in_stmt(s, from, to)),
        rb(body),
      )
    @ast.TsStmt::Block(b) => Block(rb(b))
    @ast.TsStmt::Throw(e) => Throw(re(e))
    @ast.TsStmt::CompoundAssign(n, op, e) => CompoundAssign(n, op, re(e))
    _ => stmt
  }
}

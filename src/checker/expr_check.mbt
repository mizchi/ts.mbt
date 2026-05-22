// Expression and statement-level type inference / type checking, layered on
// top of the structural checker. Aimed at validating runtime `function` /
// arrow bodies against their declared parameter and return-type annotations
// — not (yet) at full TypeScript narrowing, generic inference, this-typing,
// async/await semantics, JSX, or destructuring.
//
// Behavior is intentionally conservative: when a sub-expression cannot be
// typed concretely (unknown identifier, property access against an opaque
// receiver, etc.) the inferred type is `Any`, and `Any` is assignable to /
// from anything via the structural assignability checker. That keeps false
// positives low against real-world `.ts` files that pull in untyped DOM /
// Node globals and class state we do not model yet.

///|
pub(all) struct ExprIssue {
  // Dotted breadcrumb describing where in the function the issue was found,
  // e.g. `function foo > param init`, `function foo > return`.
  path : String
  message : String
} derive(Eq, Debug)

///|
/// Local typing environment: a flat name → type map. Function-scope semantics
/// are good enough for the MVP since most TypeScript code does not shadow
/// across blocks; nested block scopes can be added later by wrapping this in
/// a snapshot/restore helper.
priv struct ExprEnv {
  vars : Map[String, @ast.TsType]
}

///|
fn ExprEnv::new() -> ExprEnv {
  { vars: {} }
}

///|
fn ExprEnv::bind(self : ExprEnv, name : String, ty : @ast.TsType) -> Unit {
  self.vars[name] = ty
}

///|
fn ExprEnv::lookup(self : ExprEnv, name : String) -> @ast.TsType? {
  self.vars.get(name)
}

///|
fn ExprEnv::snapshot(self : ExprEnv) -> Array[String] {
  let names : Array[String] = []
  for entry in self.vars {
    names.push(entry.0)
  }
  names
}

///|
fn ExprEnv::restore_added(
  self : ExprEnv,
  pre_existing : Array[String],
) -> Unit {
  let kept : Map[String, Bool] = {}
  for n in pre_existing {
    kept[n] = true
  }
  let to_remove : Array[String] = []
  for entry in self.vars {
    if !kept.contains(entry.0) {
      to_remove.push(entry.0)
    }
  }
  for n in to_remove {
    let _ = self.vars.remove(n)
  }
}

///|
priv struct CheckCtx {
  // Display prefix for issue paths, e.g. `function foo`.
  path_prefix : String
  // Declared return type for the enclosing function. `Any` means the
  // function's return type was unannotated, in which case we skip
  // return-type checks entirely.
  return_type : @ast.TsType
  issues : Array[ExprIssue]
}

///|
fn record(ctx : CheckCtx, sub_path : String, message : String) -> Unit {
  let path = if sub_path == "" {
    ctx.path_prefix
  } else if ctx.path_prefix == "" {
    sub_path
  } else {
    ctx.path_prefix + " > " + sub_path
  }
  ctx.issues.push({ path, message })
}

///|
/// A type is "concrete enough to check" when both its source and target form
/// are not `Any` (and not the structurally-equivalent `unknown` we model as
/// `Any` here). The checker silently accepts anything involving `Any`.
fn is_checkable(ty : @ast.TsType) -> Bool {
  match ty {
    Any => false
    _ => true
  }
}

///|
/// Infer the static type of a value expression. Returns `Any` for any form
/// the MVP does not yet model so the caller can use the assignability
/// checker without false positives.
fn infer_expr(env : ExprEnv, expr : @ast.TsExpr) -> @ast.TsType {
  match expr {
    NumberLit(_) | IntLit(_) => @ast.TsType::Number
    BigIntLit(_) => @ast.TsType::BigInt
    BoolLit(_) => @ast.TsType::Boolean
    StringLit(_) => @ast.TsType::String_
    NullLit => @ast.TsType::Null
    ArrayHole => @ast.TsType::Undefined
    Var(name) =>
      match env.lookup(name) {
        Some(ty) => ty
        None => @ast.TsType::Any
      }
    BinOp(op, l, r) => {
      let lt = infer_expr(env, l)
      let rt = infer_expr(env, r)
      infer_binop(op, lt, rt)
    }
    UnaryOp(op, inner) => infer_unary(op, infer_expr(env, inner))
    Cond(_, then_, else_) =>
      narrow_union(infer_expr(env, then_), infer_expr(env, else_))
    ArrayLit(items) => {
      // Best-effort: empty array → Array(Any); homogeneous element type
      // → Array(T); heterogeneous → Array(Any).
      let mut elem : @ast.TsType = Any
      let mut first = true
      for item in items {
        let t = match item {
          Spread(_) => @ast.TsType::Any
          _ => infer_expr(env, item)
        }
        if first {
          elem = t
          first = false
        } else if !equivalent(elem, t) {
          elem = Any
        }
      }
      @ast.TsType::Array(elem)
    }
    Call(name, args) =>
      match env.lookup(name) {
        Some(Func(_, ret)) => {
          for a in args {
            let _ = infer_expr(env, a)
          }
          ret
        }
        _ => {
          for a in args {
            let _ = infer_expr(env, a)
          }
          @ast.TsType::Any
        }
      }
    CallExpr(callee, args) => {
      let callee_ty = infer_expr(env, callee)
      for a in args {
        let _ = infer_expr(env, a)
      }
      match callee_ty {
        Func(_, ret) => ret
        _ => @ast.TsType::Any
      }
    }
    New(_, args) | NewExpr(_, args) => {
      for a in args {
        let _ = infer_expr(env, a)
      }
      @ast.TsType::Any
    }
    MethodCall(receiver, _, args) => {
      let _ = infer_expr(env, receiver)
      for a in args {
        let _ = infer_expr(env, a)
      }
      @ast.TsType::Any
    }
    AssignExpr(_, value) | AssignPattern(_, value) => infer_expr(env, value)
    CompoundAssignExpr(_, _, value) => infer_expr(env, value)
    PropAssignExpr(_, _, value) | IndexAssignExpr(_, _, value) =>
      infer_expr(env, value)
    Seq(_, second) => infer_expr(env, second)
    Spread(inner) => infer_expr(env, inner)
    Await(inner) => {
      // Best-effort: peel `Promise<T>` if present, otherwise return Any.
      match infer_expr(env, inner) {
        Applied("Promise", args) if args.length() == 1 => args[0]
        _ => @ast.TsType::Any
      }
    }
    Yield(_) | YieldStar(_) => @ast.TsType::Any
    DynamicImport(_) | ImportMeta => @ast.TsType::Any
    PropAccess(_, _) | IndexAccess(_, _) => @ast.TsType::Any
    ObjectLit(_) | ComputedProp(_, _) => @ast.TsType::Any
    ArrowFunc(params, body, _) => {
      let param_types : Array[@ast.TsType] = []
      for p in params {
        param_types.push(p.type_)
      }
      let ret = match body {
        ArrowExpr(e) => infer_expr(env, e)
        ArrowBlock(_) => @ast.TsType::Any
      }
      @ast.TsType::Func(param_types, ret)
    }
    FuncExpr(f) => {
      let param_types : Array[@ast.TsType] = []
      for p in f.params {
        param_types.push(p.type_)
      }
      @ast.TsType::Func(param_types, f.return_type)
    }
    TaggedTemplate(_, _, _, _) | TemplateLiteral(_, _) => @ast.TsType::String_
  }
}

///|
fn infer_binop(
  op : @ast.TsBinOp,
  l : @ast.TsType,
  r : @ast.TsType,
) -> @ast.TsType {
  match op {
    Add => {
      // `+` is a string concat if either side is `string`, otherwise number.
      // When either side is `Any` we conservatively widen to `Any`.
      match (l, r) {
        (String_, _) | (_, String_) => @ast.TsType::String_
        (Number, Number) | (Number, Int) | (Int, Number) | (Int, Int) =>
          @ast.TsType::Number
        (Any, _) | (_, Any) => @ast.TsType::Any
        _ => @ast.TsType::Number
      }
    }
    Sub | Mul | Div | Mod | Pow | Shl | Shr | UShr | BitAnd | BitOr | BitXor =>
      @ast.TsType::Number
    BinEq | BinNe | AbstractEq | AbstractNe | BinLt | BinLe | BinGt | BinGe | In | Instanceof =>
      @ast.TsType::Boolean
    And | Or => narrow_union(l, r)
    Coalesce => narrow_union(l, r)
  }
}

///|
fn infer_unary(op : @ast.TsUnaryOp, _inner : @ast.TsType) -> @ast.TsType {
  match op {
    Neg | Plus | BitwiseNot | PreInc | PreDec | PostInc | PostDec =>
      @ast.TsType::Number
    Not => @ast.TsType::Boolean
    Typeof => @ast.TsType::String_
    Void => @ast.TsType::Undefined
    Delete => @ast.TsType::Boolean
  }
}

///|
/// Combine two branch types into the smallest equivalent union (or the
/// single shared type when both branches agree).
fn narrow_union(a : @ast.TsType, b : @ast.TsType) -> @ast.TsType {
  if equivalent(a, b) {
    return a
  }
  @ast.TsType::Union([a, b])
}

///|
/// Check `expr`'s inferred type against `expected`. Reports an issue if both
/// types are concrete and the inferred type cannot be assigned to the
/// expected one.
fn check_expr_against(
  env : ExprEnv,
  expr : @ast.TsExpr,
  expected : @ast.TsType,
  ctx : CheckCtx,
  sub_path : String,
) -> Unit {
  if !is_checkable(expected) {
    let _ = infer_expr(env, expr)
    return
  }
  let inferred = infer_expr(env, expr)
  if !is_checkable(inferred) {
    return
  }
  if !is_assignable_to(inferred, expected) {
    let detail = "expected `\{type_display(expected)}` but got `\{type_display(inferred)}`"
    record(ctx, sub_path, detail)
  }
}

///|
fn type_display(ty : @ast.TsType) -> String {
  match ty {
    Number => "number"
    Int => "int"
    Boolean => "boolean"
    String_ => "string"
    BigInt => "bigint"
    Symbol => "symbol"
    Void => "void"
    Null => "null"
    Undefined => "undefined"
    Any => "any"
    Never => "never"
    Literal(s) => "\"\{s}\""
    NumberLiteral(s) => s
    BigIntLiteral(s) => s + "n"
    BooleanLiteral(b) => if b { "true" } else { "false" }
    Array(inner) => type_display(inner) + "[]"
    Named(n) => n
    Applied(n, args) => {
      let parts : Array[String] = []
      for a in args {
        parts.push(type_display(a))
      }
      n + "<" + parts.join(", ") + ">"
    }
    Union(items) => {
      let parts : Array[String] = []
      for a in items {
        parts.push(type_display(a))
      }
      parts.join(" | ")
    }
    Intersection(items) => {
      let parts : Array[String] = []
      for a in items {
        parts.push(type_display(a))
      }
      parts.join(" & ")
    }
    Func(_, _) => "function"
    Tuple(items) => {
      let parts : Array[String] = []
      for a in items {
        parts.push(type_display(a))
      }
      "[" + parts.join(", ") + "]"
    }
    _ => "type"
  }
}

///|
fn check_block(
  env : ExprEnv,
  block : @ast.TsBlock,
  ctx : CheckCtx,
) -> Unit {
  let pre = env.snapshot()
  for stmt in block.stmts {
    check_stmt(env, stmt, ctx)
  }
  env.restore_added(pre)
}

///|
fn check_stmt(
  env : ExprEnv,
  stmt : @ast.TsStmt,
  ctx : CheckCtx,
) -> Unit {
  match stmt {
    Var(@ast.TsBinding::Ident(name), declared, init)
    | Let(@ast.TsBinding::Ident(name), declared, init)
    | Const(@ast.TsBinding::Ident(name), declared, init) => {
      let bound_type = if is_checkable(declared) { declared } else {
        infer_expr(env, init)
      }
      env.bind(name, bound_type)
      check_expr_against(env, init, declared, ctx, "binding `\{name}` init")
    }
    Var(_, _, init) | Let(_, _, init) | Const(_, _, init) => {
      // Destructuring binding pattern — out of MVP scope.
      let _ = infer_expr(env, init)
    }
    Expr(e)
    | Assign(_, e)
    | CompoundAssign(_, _, e)
    | IndexAssign(_, _, e)
    | PropAssign(_, _, e) => {
      let _ = infer_expr(env, e)
    }
    Return(opt) => {
      match opt {
        Some(e) => check_expr_against(env, e, ctx.return_type, ctx, "return")
        None =>
          if is_checkable(ctx.return_type) {
            if !is_assignable_to(@ast.TsType::Undefined, ctx.return_type) &&
              !is_assignable_to(@ast.TsType::Void, ctx.return_type) {
              record(
                ctx,
                "return",
                "expected `\{type_display(ctx.return_type)}` but no value returned",
              )
            }
          }
      }
    }
    Throw(e) => {
      let _ = infer_expr(env, e)
    }
    If(cond, then_block, else_block) => {
      let _ = infer_expr(env, cond)
      check_block(env, then_block, ctx)
      match else_block {
        Some(b) => check_block(env, b, ctx)
        None => ()
      }
    }
    While(cond, body) | DoWhile(cond, body) => {
      let _ = infer_expr(env, cond)
      check_block(env, body, ctx)
    }
    For(init, cond, update, body) => {
      let pre = env.snapshot()
      match init {
        Some(s) => check_stmt(env, s, ctx)
        None => ()
      }
      match cond {
        Some(e) => {
          let _ = infer_expr(env, e)
        }
        None => ()
      }
      match update {
        Some(s) => check_stmt(env, s, ctx)
        None => ()
      }
      check_block(env, body, ctx)
      env.restore_added(pre)
    }
    ForOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body) => {
      let _ = infer_expr(env, iter)
      check_block(env, body, ctx)
    }
    Switch(scrutinee, cases) => {
      let _ = infer_expr(env, scrutinee)
      for case_ in cases {
        match case_.test_expr {
          Some(e) => {
            let _ = infer_expr(env, e)
          }
          None => ()
        }
        check_block(env, case_.body, ctx)
      }
    }
    With(_, body) => check_block(env, body, ctx)
    Try(try_block, catch_binding, catch_block, finally_block) => {
      check_block(env, try_block, ctx)
      match catch_block {
        Some(cb) => {
          let pre = env.snapshot()
          match catch_binding {
            Some(@ast.TsBinding::Ident(name)) => env.bind(name, @ast.TsType::Any)
            _ => ()
          }
          check_block(env, cb, ctx)
          env.restore_added(pre)
        }
        None => ()
      }
      match finally_block {
        Some(fb) => check_block(env, fb, ctx)
        None => ()
      }
    }
    Block(b) => check_block(env, b, ctx)
    Label(_, inner) => check_stmt(env, inner, ctx)
    Empty | Break(_) | Continue(_) | Debugger => ()
  }
}

///|
/// Check the body of a function against its declared parameter and return
/// types. Returns an empty array when the body is consistent with the
/// signature (or when the MVP cannot tell either way).
pub fn check_function_body(func : @ast.TsFunc) -> Array[ExprIssue] {
  let issues : Array[ExprIssue] = []
  if func.body.stmts.length() == 0 {
    return issues
  }
  let env = ExprEnv::new()
  for p in func.params {
    env.bind(p.name, p.type_)
  }
  let ctx : CheckCtx = {
    path_prefix: "function " + func.name,
    return_type: func.return_type,
    issues,
  }
  for stmt in func.body.stmts {
    check_stmt(env, stmt, ctx)
  }
  issues
}

///|
/// Check every top-level function in `module_`. Class methods and namespace
/// members are not walked yet — add them in a follow-up.
pub fn check_module_function_bodies(
  module_ : @ast.TsModule,
) -> Array[ExprIssue] {
  let all : Array[ExprIssue] = []
  for func in module_.funcs {
    for issue in check_function_body(func) {
      all.push(issue)
    }
  }
  all
}

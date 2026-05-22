// Expression and statement-level type inference / type checking, layered on
// top of the structural checker. Aimed at validating runtime `function` /
// arrow bodies against their declared parameter and return-type annotations.
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

// ---------------------------------------------------------------------------
// Resolver — maps `Named(N)` to interface / class / type-alias definitions and
// looks up fields, methods, constructors. Built once per module check.
// ---------------------------------------------------------------------------

///|
priv struct Resolver {
  interfaces : Map[String, @ast.TsInterface]
  classes : Map[String, @ast.TsClassDecl]
  type_aliases : Map[String, @ast.TsTypeAlias]
  // Module-level identifier types: top-level functions, ambient values,
  // imports. Looked up when an identifier is unbound in the local env.
  globals : Map[String, @ast.TsType]
}

///|
fn Resolver::empty() -> Resolver {
  { interfaces: {}, classes: {}, type_aliases: {}, globals: {} }
}

///|
fn Resolver::from_module(module_ : @ast.TsModule) -> Resolver {
  let r = Resolver::empty()
  for i in module_.interfaces {
    r.interfaces[i.name] = i
  }
  for c in module_.classes {
    r.classes[c.name] = c
  }
  for ta in module_.type_aliases {
    r.type_aliases[ta.name] = ta
  }
  for v in module_.values {
    r.globals[v.name] = v.type_
  }
  for imp in module_.imports {
    let param_types : Array[@ast.TsType] = []
    for p in imp.params {
      param_types.push(p.1)
    }
    r.globals[imp.name] = @ast.TsType::Func(param_types, imp.return_type)
  }
  for f in module_.funcs {
    let param_types : Array[@ast.TsType] = []
    for p in f.params {
      param_types.push(p.type_)
    }
    // Async functions expose `Promise<R>` to callers even when the body's
    // declared `return_type` is the un-wrapped `R`.
    let ret = wrap_async_return(f.is_async, f.return_type)
    r.globals[f.name] = @ast.TsType::Func(param_types, ret)
  }
  r
}

///|
/// Resolve a type to its "shape" — unwrap `Named(N)` through type aliases
/// (one hop, with simple cycle protection) so callers can pattern-match on
/// the structural form (Object, Tuple, Array, Func, ...).
fn Resolver::unwrap(self : Resolver, ty : @ast.TsType) -> @ast.TsType {
  let seen : Map[String, Bool] = {}
  let mut cur = ty
  let mut keep_going = true
  while keep_going {
    match cur {
      Named(n) =>
        if seen.contains(n) {
          keep_going = false
        } else {
          match self.type_aliases.get(n) {
            Some(alias) => {
              seen[n] = true
              cur = alias.type_
            }
            None => keep_going = false
          }
        }
      _ => keep_going = false
    }
  }
  cur
}

///|
/// Look up a property on a value of type `recv` named `field`. Walks
/// interfaces / classes / objects / arrays. Returns `None` when the property
/// cannot be resolved structurally; callers fall back to `Any`.
fn Resolver::lookup_field(
  self : Resolver,
  recv : @ast.TsType,
  field : String,
) -> @ast.TsType? {
  let unwrapped = self.unwrap(recv)
  match unwrapped {
    Named(n) => {
      match self.interfaces.get(n) {
        Some(iface) => {
          for f in iface.fields {
            if f.0 == field {
              return Some(f.1)
            }
          }
          // Walk `extends` chain one level (no cycle protection — the
          // checker's `check_module` already validates these).
          for base in iface.extends_names {
            match self.lookup_field(@ast.TsType::Named(base), field) {
              Some(t) => return Some(t)
              None => ()
            }
          }
          None
        }
        None =>
          match self.classes.get(n) {
            Some(cls) => self.lookup_class_field(cls, field)
            None => None
          }
      }
    }
    Object(entries) => {
      for entry in entries {
        match entry.0 {
          Literal(name) if name == field => return Some(entry.1)
          _ => ()
        }
      }
      None
    }
    Struct(_, fields) => {
      for f in fields {
        if f.0 == field {
          return Some(f.1)
        }
      }
      None
    }
    Array(elem) =>
      match field {
        "length" => Some(@ast.TsType::Number)
        "0" | "1" | "2" | "3" => Some(elem)
        _ => None
      }
    Tuple(items) =>
      // Numeric field on a tuple → that element type.
      match (try? @strconv.parse_int(field)) {
        Ok(idx) if idx >= 0 && idx < items.length() => Some(items[idx])
        _ =>
          match field {
            "length" => Some(@ast.TsType::Number)
            _ => None
          }
      }
    String_ | Literal(_) =>
      match field {
        "length" => Some(@ast.TsType::Number)
        _ => None
      }
    _ => None
  }
}

///|
fn Resolver::lookup_class_field(
  self : Resolver,
  cls : @ast.TsClassDecl,
  field : String,
) -> @ast.TsType? {
  for p in cls.properties {
    if p.name == field && !p.is_static {
      return Some(p.type_)
    }
  }
  for m in cls.methods {
    if m.name == field && !m.is_static {
      let param_types : Array[@ast.TsType] = []
      for p in m.params {
        param_types.push(p.1)
      }
      return Some(@ast.TsType::Func(param_types, m.return_type))
    }
  }
  for base in cls.base_names {
    match self.lookup_field(@ast.TsType::Named(base), field) {
      Some(t) => return Some(t)
      None => ()
    }
  }
  None
}

///|
/// Look up a method's `(params, return)` signature. Returns `None` when the
/// receiver shape is opaque.
fn Resolver::lookup_method_sig(
  self : Resolver,
  recv : @ast.TsType,
  method : String,
) -> (Array[@ast.TsType], @ast.TsType)? {
  match self.lookup_field(recv, method) {
    Some(Func(ps, ret)) => Some((ps, ret))
    _ => None
  }
}

///|
/// Look up the constructor parameter types for a class. Returns `None` when
/// the class is unknown or has no declared constructor (the latter falls back
/// to a zero-arg signature, mirroring TS semantics).
fn Resolver::lookup_constructor(
  self : Resolver,
  class_name : String,
) -> Array[@ast.TsType]? {
  match self.classes.get(class_name) {
    Some(cls) =>
      match cls.constructor_params {
        Some(params) => {
          let types : Array[@ast.TsType] = []
          for p in params {
            types.push(p.1)
          }
          Some(types)
        }
        None => Some([])
      }
    None => None
  }
}

// ---------------------------------------------------------------------------
// Environment — flat name -> type map with snapshot/restore for block scope
// and narrowing.
// ---------------------------------------------------------------------------

///|
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
/// Capture a snapshot of `(name, type)` pairs currently in the env so we can
/// fully restore — including overwritten bindings — when a block exits. Used
/// for both lexical scope and narrowing.
fn ExprEnv::full_snapshot(
  self : ExprEnv,
) -> Array[(String, @ast.TsType)] {
  let entries : Array[(String, @ast.TsType)] = []
  for entry in self.vars {
    entries.push((entry.0, entry.1))
  }
  entries
}

///|
fn ExprEnv::restore_from(
  self : ExprEnv,
  snap : Array[(String, @ast.TsType)],
) -> Unit {
  let kept : Map[String, @ast.TsType] = {}
  for entry in snap {
    kept[entry.0] = entry.1
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
  for entry in snap {
    self.vars[entry.0] = entry.1
  }
}

// ---------------------------------------------------------------------------
// Context — issues accumulator + return type + async flag + resolver.
// ---------------------------------------------------------------------------

///|
priv struct CheckCtx {
  path_prefix : String
  // Effective return type used by `return` checks: for async functions this
  // is the inner `T` of `Promise<T>` (since `return x` inside `async`
  // returns a `T`, not the wrapping promise).
  return_type : @ast.TsType
  resolver : Resolver
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
/// A type is "concrete enough to check" when it is not `Any` (modelling
/// `unknown` the same way). The checker silently accepts anything involving
/// `Any`.
fn is_checkable(ty : @ast.TsType) -> Bool {
  match ty {
    Any => false
    _ => true
  }
}

///|
fn wrap_async_return(is_async : Bool, ret : @ast.TsType) -> @ast.TsType {
  if !is_async {
    return ret
  }
  // If the declared return is already `Promise<...>`, leave it alone.
  match ret {
    Applied("Promise", _) => ret
    _ => @ast.TsType::Applied("Promise", [ret])
  }
}

///|
fn unwrap_async_return(is_async : Bool, ret : @ast.TsType) -> @ast.TsType {
  if !is_async {
    return ret
  }
  match ret {
    Applied("Promise", args) if args.length() == 1 => args[0]
    _ => ret
  }
}

// ---------------------------------------------------------------------------
// Expression inference.
// ---------------------------------------------------------------------------

///|
fn infer_expr(
  env : ExprEnv,
  resolver : Resolver,
  expr : @ast.TsExpr,
) -> @ast.TsType {
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
        None =>
          match resolver.globals.get(name) {
            Some(ty) => ty
            None => @ast.TsType::Any
          }
      }
    BinOp(op, l, r) => {
      let lt = infer_expr(env, resolver, l)
      let rt = infer_expr(env, resolver, r)
      infer_binop(op, lt, rt)
    }
    UnaryOp(op, inner) => {
      let _ = infer_expr(env, resolver, inner)
      infer_unary(op)
    }
    Cond(_, then_, else_) =>
      narrow_union(
        infer_expr(env, resolver, then_),
        infer_expr(env, resolver, else_),
      )
    ArrayLit(items) => {
      let mut elem : @ast.TsType = Any
      let mut first = true
      for item in items {
        let t = match item {
          Spread(_) => @ast.TsType::Any
          _ => infer_expr(env, resolver, item)
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
    Call(name, args) => {
      let callee_ty = match env.lookup(name) {
        Some(t) => t
        None =>
          match resolver.globals.get(name) {
            Some(t) => t
            None => @ast.TsType::Any
          }
      }
      infer_call(env, resolver, callee_ty, args)
    }
    CallExpr(callee, args) => {
      let callee_ty = infer_expr(env, resolver, callee)
      infer_call(env, resolver, callee_ty, args)
    }
    New(class_name, args) =>
      match resolver.lookup_constructor(class_name) {
        Some(_) => {
          // Validate args at the call site via `check_arguments`; here we
          // just return the instance type.
          for a in args {
            let _ = infer_expr(env, resolver, a)
          }
          @ast.TsType::Named(class_name)
        }
        None => {
          for a in args {
            let _ = infer_expr(env, resolver, a)
          }
          @ast.TsType::Any
        }
      }
    NewExpr(callee, args) => {
      let _ = infer_expr(env, resolver, callee)
      for a in args {
        let _ = infer_expr(env, resolver, a)
      }
      @ast.TsType::Any
    }
    MethodCall(receiver, method, args) => {
      let recv_ty = infer_expr(env, resolver, receiver)
      match resolver.lookup_method_sig(recv_ty, method) {
        Some((_params, ret)) => {
          for a in args {
            let _ = infer_expr(env, resolver, a)
          }
          ret
        }
        None => {
          for a in args {
            let _ = infer_expr(env, resolver, a)
          }
          @ast.TsType::Any
        }
      }
    }
    AssignExpr(_, value) | AssignPattern(_, value) =>
      infer_expr(env, resolver, value)
    CompoundAssignExpr(_, _, value) => infer_expr(env, resolver, value)
    PropAssignExpr(_, _, value) | IndexAssignExpr(_, _, value) =>
      infer_expr(env, resolver, value)
    Seq(_, second) => infer_expr(env, resolver, second)
    Spread(inner) => infer_expr(env, resolver, inner)
    Await(inner) =>
      match infer_expr(env, resolver, inner) {
        Applied("Promise", args) if args.length() == 1 => args[0]
        other => other
      }
    Yield(_) | YieldStar(_) => @ast.TsType::Any
    DynamicImport(_) | ImportMeta => @ast.TsType::Any
    PropAccess(receiver, name) => {
      let recv_ty = infer_expr(env, resolver, receiver)
      match resolver.lookup_field(recv_ty, name) {
        Some(t) => t
        None => @ast.TsType::Any
      }
    }
    IndexAccess(receiver, index_expr) => {
      let recv_ty = infer_expr(env, resolver, receiver)
      let idx_ty = infer_expr(env, resolver, index_expr)
      infer_index(resolver, recv_ty, idx_ty, index_expr)
    }
    ObjectLit(entries) => {
      let fields : Array[(@ast.TsType, @ast.TsType)] = []
      for entry in entries {
        let val_ty = infer_expr(env, resolver, entry.1)
        fields.push((@ast.TsType::Literal(entry.0), val_ty))
      }
      @ast.TsType::Object(fields)
    }
    ComputedProp(_, _) => @ast.TsType::Any
    ArrowFunc(params, body, is_async) => {
      let param_types : Array[@ast.TsType] = []
      for p in params {
        param_types.push(p.type_)
      }
      let ret = match body {
        ArrowExpr(e) => infer_expr(env, resolver, e)
        ArrowBlock(_) => @ast.TsType::Any
      }
      @ast.TsType::Func(param_types, wrap_async_return(is_async, ret))
    }
    FuncExpr(f) => {
      let param_types : Array[@ast.TsType] = []
      for p in f.params {
        param_types.push(p.type_)
      }
      @ast.TsType::Func(
        param_types,
        wrap_async_return(f.is_async, f.return_type),
      )
    }
    TaggedTemplate(_, _, _, _) | TemplateLiteral(_, _) => @ast.TsType::String_
  }
}

///|
fn infer_call(
  env : ExprEnv,
  resolver : Resolver,
  callee : @ast.TsType,
  args : Array[@ast.TsExpr],
) -> @ast.TsType {
  for a in args {
    let _ = infer_expr(env, resolver, a)
  }
  match callee {
    Func(_, ret) => ret
    _ => @ast.TsType::Any
  }
}

///|
fn infer_index(
  _resolver : Resolver,
  recv : @ast.TsType,
  idx : @ast.TsType,
  idx_expr : @ast.TsExpr,
) -> @ast.TsType {
  match recv {
    Array(elem) => elem
    Tuple(items) =>
      match idx_expr {
        IntLit(i) if i >= 0 && i < items.length() => items[i]
        NumberLit(d) => {
          let i = d.to_int()
          if i >= 0 && i < items.length() {
            items[i]
          } else {
            @ast.TsType::Any
          }
        }
        _ => {
          // Union of all element types when the index is non-literal.
          if items.length() == 0 {
            return @ast.TsType::Undefined
          }
          let mut acc = items[0]
          let mut i = 1
          while i < items.length() {
            acc = narrow_union(acc, items[i])
            i = i + 1
          }
          acc
        }
      }
    String_ | Literal(_) =>
      match idx {
        Number | Int | NumberLiteral(_) => @ast.TsType::String_
        _ => @ast.TsType::Any
      }
    _ => @ast.TsType::Any
  }
}

///|
fn infer_binop(
  op : @ast.TsBinOp,
  l : @ast.TsType,
  r : @ast.TsType,
) -> @ast.TsType {
  match op {
    Add =>
      match (l, r) {
        (String_, _) | (_, String_) => @ast.TsType::String_
        (Number, Number) | (Number, Int) | (Int, Number) | (Int, Int) =>
          @ast.TsType::Number
        (Any, _) | (_, Any) => @ast.TsType::Any
        _ => @ast.TsType::Number
      }
    Sub | Mul | Div | Mod | Pow | Shl | Shr | UShr | BitAnd | BitOr | BitXor =>
      @ast.TsType::Number
    BinEq | BinNe | AbstractEq | AbstractNe | BinLt | BinLe | BinGt | BinGe | In | Instanceof =>
      @ast.TsType::Boolean
    And | Or | Coalesce => narrow_union(l, r)
  }
}

///|
fn infer_unary(op : @ast.TsUnaryOp) -> @ast.TsType {
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
fn narrow_union(a : @ast.TsType, b : @ast.TsType) -> @ast.TsType {
  if equivalent(a, b) {
    return a
  }
  @ast.TsType::Union([a, b])
}

// ---------------------------------------------------------------------------
// Assignability + argument checking.
// ---------------------------------------------------------------------------

///|
fn check_expr_against(
  env : ExprEnv,
  expr : @ast.TsExpr,
  expected : @ast.TsType,
  ctx : CheckCtx,
  sub_path : String,
) -> Unit {
  // Always walk for nested call-site argument errors, even when the outer
  // expected type is `Any` (e.g. an unannotated return where we still want
  // bad calls inside the returned expression to be flagged).
  check_call_args_in_expr(env, expr, ctx)
  if !is_checkable(expected) {
    return
  }
  let inferred = infer_expr(env, ctx.resolver, expr)
  if !is_checkable(inferred) {
    return
  }
  if !is_assignable_to(inferred, expected) {
    let detail = "expected `\{type_display(expected)}` but got `\{type_display(inferred)}`"
    record(ctx, sub_path, detail)
  }
}

///|
/// Check call-site arguments against declared parameter types. Emits issues
/// for both argument-count mismatch (when we are confident there is no rest
/// param) and per-argument assignability errors.
fn check_arguments(
  env : ExprEnv,
  params : Array[@ast.TsType],
  args : Array[@ast.TsExpr],
  ctx : CheckCtx,
  call_path : String,
) -> Unit {
  // Spread arguments make positional matching unreliable — just type-check
  // each argument and skip count enforcement.
  let mut has_spread = false
  for a in args {
    match a {
      Spread(_) => has_spread = true
      _ => ()
    }
  }
  if !has_spread && args.length() != params.length() {
    let msg = "expected \{params.length()} argument(s), got \{args.length()}"
    record(ctx, call_path, msg)
  }
  let n = if args.length() < params.length() {
    args.length()
  } else {
    params.length()
  }
  let mut i = 0
  while i < n {
    let sub_path = "\{call_path} arg[\{i}]"
    check_expr_against(env, args[i], params[i], ctx, sub_path)
    i = i + 1
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

// ---------------------------------------------------------------------------
// Narrowing — currently handles `typeof x === "string"` (and variants) in
// `if` conditions. The narrowed type is bound for the duration of the
// then/else block and restored on exit.
// ---------------------------------------------------------------------------

///|
priv struct NarrowEffect {
  // Variables to overwrite when entering the then-branch.
  then_binds : Array[(String, @ast.TsType)]
  // Variables to overwrite when entering the else-branch.
  else_binds : Array[(String, @ast.TsType)]
}

///|
fn typeof_string_to_type(s : String) -> @ast.TsType? {
  match s {
    "string" => Some(@ast.TsType::String_)
    "number" => Some(@ast.TsType::Number)
    "boolean" => Some(@ast.TsType::Boolean)
    "bigint" => Some(@ast.TsType::BigInt)
    "symbol" => Some(@ast.TsType::Symbol)
    "undefined" => Some(@ast.TsType::Undefined)
    "function" => Some(@ast.TsType::Func([], @ast.TsType::Any))
    "object" => Some(@ast.TsType::Any)
    _ => None
  }
}

///|
fn analyze_narrowing(cond : @ast.TsExpr) -> NarrowEffect {
  let then_binds : Array[(String, @ast.TsType)] = []
  let else_binds : Array[(String, @ast.TsType)] = []
  match cond {
    BinOp(op, left, right) => {
      let (var_name, type_string, equal_sense) = extract_typeof_eq(
        op, left, right,
      )
      match (var_name, type_string) {
        (Some(name), Some(ts)) =>
          match typeof_string_to_type(ts) {
            Some(narrowed) =>
              if equal_sense {
                then_binds.push((name, narrowed))
              } else {
                else_binds.push((name, narrowed))
              }
            None => ()
          }
        _ => ()
      }
    }
    _ => ()
  }
  { then_binds, else_binds }
}

///|
/// Match a `typeof <var> === "<tag>"` (or variant) and return
/// `(var_name, type_string, is_equal)`. Order-independent across operands.
fn extract_typeof_eq(
  op : @ast.TsBinOp,
  left : @ast.TsExpr,
  right : @ast.TsExpr,
) -> (String?, String?, Bool) {
  let equal_sense = match op {
    BinEq | AbstractEq => true
    BinNe | AbstractNe => false
    _ => return (None, None, true)
  }
  // Case 1: `typeof x === "string"`
  match (left, right) {
    (UnaryOp(Typeof, Var(name)), StringLit(s)) =>
      return (Some(name), Some(s), equal_sense)
    (StringLit(s), UnaryOp(Typeof, Var(name))) =>
      return (Some(name), Some(s), equal_sense)
    _ => ()
  }
  (None, None, equal_sense)
}

// ---------------------------------------------------------------------------
// Statement checking.
// ---------------------------------------------------------------------------

///|
fn check_block(env : ExprEnv, block : @ast.TsBlock, ctx : CheckCtx) -> Unit {
  let pre = env.full_snapshot()
  for stmt in block.stmts {
    check_stmt(env, stmt, ctx)
  }
  env.restore_from(pre)
}

///|
fn check_block_with_narrowing(
  env : ExprEnv,
  block : @ast.TsBlock,
  ctx : CheckCtx,
  binds : Array[(String, @ast.TsType)],
) -> Unit {
  let pre = env.full_snapshot()
  for b in binds {
    env.bind(b.0, b.1)
  }
  for stmt in block.stmts {
    check_stmt(env, stmt, ctx)
  }
  env.restore_from(pre)
}

///|
fn check_stmt(env : ExprEnv, stmt : @ast.TsStmt, ctx : CheckCtx) -> Unit {
  match stmt {
    Var(@ast.TsBinding::Ident(name), declared, init)
    | Let(@ast.TsBinding::Ident(name), declared, init)
    | Const(@ast.TsBinding::Ident(name), declared, init) => {
      let bound_type = if is_checkable(declared) {
        declared
      } else {
        infer_expr(env, ctx.resolver, init)
      }
      env.bind(name, bound_type)
      check_expr_against(env, init, declared, ctx, "binding `\{name}` init")
    }
    Var(_, _, init) | Let(_, _, init) | Const(_, _, init) => {
      let _ = infer_expr(env, ctx.resolver, init)
    }
    Expr(e) =>
      check_call_args_in_expr(env, e, ctx)
    Assign(_, e)
    | CompoundAssign(_, _, e)
    | IndexAssign(_, _, e)
    | PropAssign(_, _, e) => {
      check_call_args_in_expr(env, e, ctx)
    }
    Return(opt) =>
      match opt {
        Some(e) => check_expr_against(env, e, ctx.return_type, ctx, "return")
        None =>
          if is_checkable(ctx.return_type) &&
            !is_assignable_to(@ast.TsType::Undefined, ctx.return_type) &&
            !is_assignable_to(@ast.TsType::Void, ctx.return_type) {
            record(
              ctx,
              "return",
              "expected `\{type_display(ctx.return_type)}` but no value returned",
            )
          }
      }
    Throw(e) => check_call_args_in_expr(env, e, ctx)
    If(cond, then_block, else_block) => {
      check_call_args_in_expr(env, cond, ctx)
      let effect = analyze_narrowing(cond)
      check_block_with_narrowing(env, then_block, ctx, effect.then_binds)
      match else_block {
        Some(b) => check_block_with_narrowing(env, b, ctx, effect.else_binds)
        None => ()
      }
    }
    While(cond, body) | DoWhile(cond, body) => {
      check_call_args_in_expr(env, cond, ctx)
      check_block(env, body, ctx)
    }
    For(init, cond, update, body) => {
      let pre = env.full_snapshot()
      match init {
        Some(s) => check_stmt(env, s, ctx)
        None => ()
      }
      match cond {
        Some(e) => check_call_args_in_expr(env, e, ctx)
        None => ()
      }
      match update {
        Some(s) => check_stmt(env, s, ctx)
        None => ()
      }
      check_block(env, body, ctx)
      env.restore_from(pre)
    }
    ForOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body) => {
      check_call_args_in_expr(env, iter, ctx)
      check_block(env, body, ctx)
    }
    Switch(scrutinee, cases) => {
      check_call_args_in_expr(env, scrutinee, ctx)
      for case_ in cases {
        match case_.test_expr {
          Some(e) => check_call_args_in_expr(env, e, ctx)
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
          let pre = env.full_snapshot()
          match catch_binding {
            Some(@ast.TsBinding::Ident(name)) => env.bind(name, @ast.TsType::Any)
            _ => ()
          }
          check_block(env, cb, ctx)
          env.restore_from(pre)
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
/// Walk `expr` for call sites and validate their arguments against the
/// callee's declared parameter types. Pure inference is also run to populate
/// inferred subtypes / surface compound issues.
fn check_call_args_in_expr(
  env : ExprEnv,
  expr : @ast.TsExpr,
  ctx : CheckCtx,
) -> Unit {
  match expr {
    Call(name, args) => {
      let callee_ty = match env.lookup(name) {
        Some(t) => t
        None =>
          match ctx.resolver.globals.get(name) {
            Some(t) => t
            None => @ast.TsType::Any
          }
      }
      match callee_ty {
        Func(params, _) =>
          check_arguments(env, params, args, ctx, "call `\{name}`")
        _ => ()
      }
      for a in args {
        check_call_args_in_expr(env, a, ctx)
      }
    }
    CallExpr(callee, args) => {
      let callee_ty = infer_expr(env, ctx.resolver, callee)
      match callee_ty {
        Func(params, _) =>
          check_arguments(env, params, args, ctx, "call")
        _ => ()
      }
      check_call_args_in_expr(env, callee, ctx)
      for a in args {
        check_call_args_in_expr(env, a, ctx)
      }
    }
    MethodCall(receiver, method, args) => {
      let recv_ty = infer_expr(env, ctx.resolver, receiver)
      match ctx.resolver.lookup_method_sig(recv_ty, method) {
        Some((params, _)) =>
          check_arguments(env, params, args, ctx, "call `\{method}`")
        None => ()
      }
      check_call_args_in_expr(env, receiver, ctx)
      for a in args {
        check_call_args_in_expr(env, a, ctx)
      }
    }
    New(class_name, args) =>
      match ctx.resolver.lookup_constructor(class_name) {
        Some(params) => {
          check_arguments(env, params, args, ctx, "new `\{class_name}`")
          for a in args {
            check_call_args_in_expr(env, a, ctx)
          }
        }
        None =>
          for a in args {
            check_call_args_in_expr(env, a, ctx)
          }
      }
    NewExpr(callee, args) => {
      check_call_args_in_expr(env, callee, ctx)
      for a in args {
        check_call_args_in_expr(env, a, ctx)
      }
    }
    BinOp(_, l, r) => {
      check_call_args_in_expr(env, l, ctx)
      check_call_args_in_expr(env, r, ctx)
    }
    UnaryOp(_, inner) => check_call_args_in_expr(env, inner, ctx)
    Cond(c, t, e) => {
      check_call_args_in_expr(env, c, ctx)
      check_call_args_in_expr(env, t, ctx)
      check_call_args_in_expr(env, e, ctx)
    }
    ArrayLit(items) =>
      for it in items {
        check_call_args_in_expr(env, it, ctx)
      }
    ObjectLit(entries) =>
      for ent in entries {
        check_call_args_in_expr(env, ent.1, ctx)
      }
    PropAccess(recv, _) => check_call_args_in_expr(env, recv, ctx)
    IndexAccess(recv, idx) => {
      check_call_args_in_expr(env, recv, ctx)
      check_call_args_in_expr(env, idx, ctx)
    }
    AssignExpr(_, v)
    | CompoundAssignExpr(_, _, v)
    | AssignPattern(_, v)
    | Spread(v)
    | Await(v) => check_call_args_in_expr(env, v, ctx)
    PropAssignExpr(recv, _, v) => {
      check_call_args_in_expr(env, recv, ctx)
      check_call_args_in_expr(env, v, ctx)
    }
    IndexAssignExpr(recv, idx, v) => {
      check_call_args_in_expr(env, recv, ctx)
      check_call_args_in_expr(env, idx, ctx)
      check_call_args_in_expr(env, v, ctx)
    }
    Seq(a, b) => {
      check_call_args_in_expr(env, a, ctx)
      check_call_args_in_expr(env, b, ctx)
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        check_call_args_in_expr(env, e, ctx)
      }
    TaggedTemplate(tag, _, _, exprs) => {
      check_call_args_in_expr(env, tag, ctx)
      for e in exprs {
        check_call_args_in_expr(env, e, ctx)
      }
    }
    _ => ()
  }
}

// ---------------------------------------------------------------------------
// Public entry points.
// ---------------------------------------------------------------------------

///|
/// Check a single function body against its signature using a resolver built
/// from the surrounding module (or an empty resolver when called in
/// isolation).
pub fn check_function_body(func : @ast.TsFunc) -> Array[ExprIssue] {
  check_function_body_with(func, Resolver::empty())
}

///|
fn check_function_body_with(
  func : @ast.TsFunc,
  resolver : Resolver,
) -> Array[ExprIssue] {
  let issues : Array[ExprIssue] = []
  if func.body.stmts.length() == 0 {
    return issues
  }
  let env = ExprEnv::new()
  for p in func.params {
    env.bind(p.name, p.type_)
  }
  // Inside an async function body, `return x` returns the inner type — the
  // wrapping `Promise<T>` is what the *caller* sees. So we unwrap once for
  // the body-level return check.
  let body_return = unwrap_async_return(func.is_async, func.return_type)
  let ctx : CheckCtx = {
    path_prefix: "function " + func.name,
    return_type: body_return,
    resolver,
    issues,
  }
  for stmt in func.body.stmts {
    check_stmt(env, stmt, ctx)
  }
  issues
}

///|
/// Check every top-level function in `module_` using a resolver built from
/// the same module. Class methods do not carry bodies in this AST, so they
/// are not walked — class shapes still inform property / method / `new`
/// typing for expressions that *call into* them.
pub fn check_module_function_bodies(
  module_ : @ast.TsModule,
) -> Array[ExprIssue] {
  let resolver = Resolver::from_module(module_)
  let all : Array[ExprIssue] = []
  for func in module_.funcs {
    for issue in check_function_body_with(func, resolver) {
      all.push(issue)
    }
  }
  all
}

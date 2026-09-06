///|
priv enum ClassKey {
  Name(String)
  Computed(@ast.TsExpr)
}

///|
/// TS2394 ("This overload signature is not compatible with its
/// implementation signature") — the ARITY half, which needs no
/// assignability and so is decidable in the parser.
///
/// The rule is one-directional, and the message text does not say which
/// direction. Probed against the real compiler, cell by cell:
///
///   m(); m(a) {}                  TS2394   impl needs an argument the
///                                          signature can never supply
///   m(a); m() {}                  legal    a shorter implementation is
///   m(a, b); m(a) {}              legal    assignable to a longer signature
///   m(); m(a?) {}                 legal
///   m(); m(a = 1) {}              legal
///   m(); m(...a: any[]) {}        legal
///   m(a, b); m(a, b?) {}          legal
///   m(a: string); m(a: number) {} TS2394   (a TYPE mismatch — abstained
///                                          on here, so a MISS)
///
/// So the only decidable error is `signature_max_args < impl_required_arity`.
/// Reading the message as "the two must agree" would flag four of those
/// legal rows.
///
/// The largest number of arguments a bodiless overload SIGNATURE can
/// supply, or `-1` for unbounded (it has a rest parameter, so no
/// implementation arity can be out of its reach). A `this` parameter is a
/// type annotation, not an argument, and is excluded from both counts —
/// `m(this: C): void; m(this: C, a: number) {}` is TS2394 for the `a`.
fn signature_max_args(params : Array[@ast.TsParam]) -> Int {
  let mut n = 0
  for p in params {
    if p.is_rest {
      return -1
    }
    if p.name == "this" {
      continue
    }
    n = n + 1
  }
  n
}

///|
/// The number of arguments an IMPLEMENTATION cannot do without: the
/// leading parameters that are neither optional (`x?`), defaulted
/// (`x = e`) nor rest. A required parameter cannot legally follow an
/// optional one (TS1016), so stopping at the first omittable one is
/// equivalent to counting them all and is the conservative reading if
/// that rule is ever violated — a LOWER required count only ever silences
/// the check. A parameter property (`constructor(private a: number)`) is
/// an ordinary required parameter and is counted.
fn impl_required_arity(params : Array[@ast.TsParam]) -> Int {
  let mut n = 0
  for p in params {
    if p.is_rest {
      break
    }
    if p.name == "this" {
      continue
    }
    if p.is_optional || p.default is Some(_) {
      break
    }
    n = n + 1
  }
  n
}

///|
priv enum ClassElement {
  Method(Bool, ClassKey, String?, @ast.TsFunc)
  // `Field(is_static, key, type, init, is_readonly, has_definite_assertion)`
  // — the `readonly` modifier (`class C { readonly x: T }`) is captured
  // so downstream structural checks can flag `c.x = …` as TS2540; the
  // `has_definite_assertion` flag (`class C { x!: T }`) feeds the
  // strict-property-initialization check (TS2564) in the checker.
  Field(Bool, ClassKey, @ast.TsType, @ast.TsExpr?, Bool, Bool)
  StaticBlock(@ast.TsBlock)
  // Marker for `[k: KeyType]: ValueType` index signatures, carrying the
  // captured key / value types and whether the signature was declared
  // `static` (a static signature constrains the *static* member side and
  // never participates in instance resolution). The presence of any index
  // signature opts the class out of strict-property-initialization (TS2564)
  // because every concrete field is implicitly covered by the indexer; the
  // captured value type also feeds the TS2411 index-constraint check (named
  // properties must be assignable to the index value type). When the
  // signature shape can't be parsed precisely the key/value default to `Any`
  // (no constraint).
  IndexSig(@ast.TsType, @ast.TsType, Bool)
}

///|
fn class_key_name(key : ClassKey) -> String {
  match key {
    Name(name) => name
    // A WELL-KNOWN-symbol key (`[Symbol.iterator]`) is statically
    // resolvable, so keep a stable member name — assignability and
    // member lookups can then treat it like any named member
    // (symbolProperty9/10/12). Other computed keys stay opaque.
    Computed(PropAccess(Var("Symbol"), sym)) => "@@" + sym
    // A constant literal key (`["get1"]`, `[""]`, `[1 << 6]`) names the
    // member statically, exactly as tsc resolves it — the TS2411
    // index-constraint checks need the real name
    // (computedPropertyNames36-45_ES6).
    Computed(e) =>
      match computed_key_const_name(e) {
        Some(n) => n
        None => "<computed>"
      }
  }
}

///|
/// Statically evaluate a computed member key: string literals, integer
/// literals, and the small constant integer expressions tsc folds
/// (`[1 << 6]` is the property name "64"). Anything else is `None`.
fn computed_key_const_name(e : @ast.TsExpr) -> String? {
  match e {
    StringLit(s) => Some(s)
    _ =>
      match computed_key_const_int(e) {
        Some(i) => Some(i.to_string())
        None => None
      }
  }
}

///|
fn computed_key_const_int(e : @ast.TsExpr) -> Int? {
  match e {
    IntLit(i) => Some(i)
    BinOp(op, a, b) => {
      guard computed_key_const_int(a) is Some(x) else { return None }
      guard computed_key_const_int(b) is Some(y) else { return None }
      match op {
        Add => Some(x + y)
        Sub => Some(x - y)
        Mul => Some(x * y)
        Shl => Some(x << y)
        Shr => Some(x >> y)
        BitAnd => Some(x & y)
        BitOr => Some(x | y)
        BitXor => Some(x ^ y)
        _ => None
      }
    }
    _ => None
  }
}

///|
fn is_public_runtime_class_member_name(name : String) -> Bool {
  !name.has_prefix("#") && !name.contains("__#") && name != "<computed>"
}

///|
/// Class-method parameters for the DECLARATION side, with any
/// destructuring pattern moved into the body.
///
/// `TsClassMethodDecl.params` is `Array[(String, TsType)]` — a name and
/// a type, with no slot for a binding pattern — so `m({ a: x })` kept
/// the first bound name (`x`) with the WHOLE parameter's type, and the
/// checker then read `x * 2` as multiplying an object. The runtime side
/// had the same hole with a worse outcome (see `lifted_method_params` in
/// `src/transform/iife_class_lift.mbt`, where the pattern was dropped
/// from the emitted code entirely).
///
/// Same remedy on both sides: desugar at the boundary where the pattern
/// would otherwise be lost.
///
///   m({ a, b }, c) { … }   ->   m(__pat0, c) { const { a, b } = __pat0; … }
///
/// The `const` carries the parameter's declared type, so the checker
/// narrows each bound name through ordinary destructuring rules instead
/// of seeing one name typed as the whole object.
fn runtime_class_method_params(
  func : @ast.TsFunc,
) -> (
  Array[(String, @ast.TsType)],
  Array[@ast.TsExpr?],
  Array[Bool],
  @ast.TsBlock,
) {
  let params : Array[(String, @ast.TsType)] = []
  let param_defaults : Array[@ast.TsExpr?] = []
  let param_is_rest : Array[Bool] = []
  let prologue : Array[@ast.TsStmt] = []
  for index, param in func.params {
    let is_pattern = match param.binding {
      Some(@ast.TsBinding::Object(_)) | Some(@ast.TsBinding::Array(_)) => true
      _ => false
    }
    if is_pattern {
      let synth = "__pat" + index.to_string()
      params.push((synth, param.type_))
      match param.binding {
        Some(b) =>
          prologue.push(
            @ast.TsStmt::Const(b, param.type_, @ast.TsExpr::Var(synth)),
          )
        None => ()
      }
    } else {
      params.push((runtime_class_param_name(param, index), param.type_))
    }
    param_defaults.push(param.default)
    param_is_rest.push(param.is_rest)
  }
  if prologue.length() == 0 {
    return (params, param_defaults, param_is_rest, func.body)
  }
  let stmts : Array[@ast.TsStmt] = []
  for st in prologue {
    stmts.push(st)
  }
  for st in func.body.stmts {
    stmts.push(st)
  }
  let positions : Array[Int] = []
  if func.body.stmt_positions.length() == func.body.stmts.length() &&
    func.body.stmt_positions.length() > 0 {
    for _ in prologue {
      positions.push(func.body.stmt_positions[0])
    }
    for pos in func.body.stmt_positions {
      positions.push(pos)
    }
  }
  (params, param_defaults, param_is_rest, { stmts, stmt_positions: positions })
}

///|
fn runtime_class_param_name(param : @ast.TsParam, index : Int) -> String {
  if param.name != "" {
    return param.name
  }
  match param.binding {
    Some(@ast.TsBinding::Ident(name)) => name
    _ => "arg" + index.to_string()
  }
}

///|

///|
/// Every identifier a binding pattern declares (helper for the static-block
/// TDZ scan).
fn sb_binding_names(binding : @ast.TsBinding, out : Array[String]) -> Unit {
  match binding {
    Ident(n) => out.push(n)
    Array(ab) => {
      for item in ab.items {
        match item {
          Some(e) => sb_binding_names(e.binding, out)
          None => ()
        }
      }
      match ab.rest {
        Some(r) => sb_binding_names(r, out)
        None => ()
      }
    }
    Object(ob) => {
      for p in ob.props {
        sb_binding_names(p.binding, out)
      }
      match ob.rest {
        Some(r) => out.push(r)
        None => ()
      }
    }
    Target(_) => ()
  }
}

///|
/// Free identifier reads / writes of a static block's *immediate* execution
/// (function bodies are deferred and skipped): `Var` reads in any operand
/// position and assignment-statement target names. Block-local declarations
/// are collected into `locals` and excluded by the caller.
fn sb_reads_expr(e : @ast.TsExpr, out : Array[String]) -> Unit {
  match e {
    Var(n) => out.push(n)
    PropAccess(recv, _) => sb_reads_expr(recv, out)
    PropAssignExpr(recv, _, v) => {
      sb_reads_expr(recv, out)
      sb_reads_expr(v, out)
    }
    MethodCall(recv, _, args) => {
      sb_reads_expr(recv, out)
      for a in args {
        sb_reads_expr(a, out)
      }
    }
    BinOp(_, a, b) | Seq(a, b) | IndexAccess(a, b) | ComputedProp(a, b) => {
      sb_reads_expr(a, out)
      sb_reads_expr(b, out)
    }
    IndexAssignExpr(a, b, c) | Cond(a, b, c) => {
      sb_reads_expr(a, out)
      sb_reads_expr(b, out)
      sb_reads_expr(c, out)
    }
    UnaryOp(_, x)
    | Spread(x)
    | Await(x)
    | YieldStar(x)
    | PureCall(x)
    | TypeArgs(_, x) => sb_reads_expr(x, out)
    AssignExpr(n, v) => {
      out.push(n)
      sb_reads_expr(v, out)
    }
    CompoundAssignExpr(a, _, b) => {
      sb_reads_expr(a, out)
      sb_reads_expr(b, out)
    }
    Yield(opt) =>
      match opt {
        Some(x) => sb_reads_expr(x, out)
        None => ()
      }
    Call(n, args) => {
      out.push(n)
      for a in args {
        sb_reads_expr(a, out)
      }
    }
    New(_, args) =>
      for a in args {
        sb_reads_expr(a, out)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      sb_reads_expr(callee, out)
      for a in args {
        sb_reads_expr(a, out)
      }
    }
    ArrayLit(items) =>
      for it in items {
        sb_reads_expr(it, out)
      }
    ObjectLit(entries) =>
      for ent in entries {
        sb_reads_expr(ent.1, out)
      }
    TemplateLiteral(_, exprs) =>
      for x in exprs {
        sb_reads_expr(x, out)
      }
    TaggedTemplate(tag, _, _, exprs) => {
      sb_reads_expr(tag, out)
      for x in exprs {
        sb_reads_expr(x, out)
      }
    }
    _ => ()
  }
}

///|
fn sb_reads_stmt(
  stmt : @ast.TsStmt,
  locals : Array[String],
  out : Array[String],
) -> Unit {
  fn walk_block(b : @ast.TsBlock) -> Unit {
    for s in b.stmts {
      sb_reads_stmt(s, locals, out)
    }
  }

  match stmt {
    Var(b, _, e) | Let(b, _, e) | Const(b, _, e) => {
      sb_binding_names(b, locals)
      sb_reads_expr(e, out)
    }
    Assign(n, e) => {
      out.push(n)
      sb_reads_expr(e, out)
    }
    CompoundAssign(n, _, e) => {
      out.push(n)
      sb_reads_expr(e, out)
    }
    Expr(e) | Throw(e) | Return(Some(e)) => sb_reads_expr(e, out)
    PropAssign(recv, _, v) => {
      sb_reads_expr(recv, out)
      sb_reads_expr(v, out)
    }
    IndexAssign(a, b, c) => {
      sb_reads_expr(a, out)
      sb_reads_expr(b, out)
      sb_reads_expr(c, out)
    }
    If(c, t, e) => {
      sb_reads_expr(c, out)
      walk_block(t)
      match e {
        Some(x) => walk_block(x)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) | With(c, b) => {
      sb_reads_expr(c, out)
      walk_block(b)
    }
    For(init, cond, upd, body) => {
      match init {
        Some(s) => sb_reads_stmt(s, locals, out)
        None => ()
      }
      match cond {
        Some(e) => sb_reads_expr(e, out)
        None => ()
      }
      match upd {
        Some(s) => sb_reads_stmt(s, locals, out)
        None => ()
      }
      walk_block(body)
    }
    ForOf(_, b, _, e, body)
    | ForAwaitOf(_, b, _, e, body)
    | ForIn(_, b, _, e, body) => {
      sb_binding_names(b, locals)
      sb_reads_expr(e, out)
      walk_block(body)
    }
    Switch(e, cases) => {
      sb_reads_expr(e, out)
      for case in cases {
        match case.test_expr {
          Some(t) => sb_reads_expr(t, out)
          None => ()
        }
        walk_block(case.body)
      }
    }
    Try(b, cb_binding, cb, fb) => {
      walk_block(b)
      match cb_binding {
        Some(bind) => sb_binding_names(bind, locals)
        None => ()
      }
      match cb {
        Some(x) => walk_block(x)
        None => ()
      }
      match fb {
        Some(x) => walk_block(x)
        None => ()
      }
    }
    Label(_, s) => sb_reads_stmt(s, locals, out)
    Block(b) => walk_block(b)
    _ => ()
  }
}

///|
/// True when `binding` declares an identifier equal to `name`.
fn sb_binding_binds(binding : @ast.TsBinding, name : String) -> Bool {
  match binding {
    Ident(n) => n == name
    Array(ab) => {
      for item in ab.items {
        match item {
          Some(elem) => if sb_binding_binds(elem.binding, name) { return true }
          None => ()
        }
      }
      match ab.rest {
        Some(rest) => sb_binding_binds(rest, name)
        None => false
      }
    }
    Object(ob) => {
      for prop in ob.props {
        if sb_binding_binds(prop.binding, name) {
          return true
        }
      }
      ob.rest is Some(r) && r == name
    }
    Target(_) => false
  }
}

///|
/// Expression walk for the TS2729 static-block check: record a hit when the
/// expression reads or writes `this.<f>` / `<ClassName>.<f>` for a field
/// name in `later`. Function-valued expressions (arrow / function / class
/// expressions) are NOT entered -- their bodies run later, after every
/// static field has initialized.
fn sb_walk_expr(
  expr : @ast.TsExpr,
  cname : String,
  later : Map[String, Bool],
  hits : Array[String],
) -> Unit {
  let check_recv = fn(recv : @ast.TsExpr, f : String) -> Unit {
    match recv {
      Var(n) =>
        if (n == "this" || n == cname) && later.get(f) is Some(_) {
          hits.push(f)
        }
      _ => ()
    }
  }
  match expr {
    PropAccess(recv, f) => {
      check_recv(recv, f)
      sb_walk_expr(recv, cname, later, hits)
    }
    PropAssignExpr(recv, f, v) => {
      check_recv(recv, f)
      sb_walk_expr(recv, cname, later, hits)
      sb_walk_expr(v, cname, later, hits)
    }
    MethodCall(recv, m, args) => {
      check_recv(recv, m)
      sb_walk_expr(recv, cname, later, hits)
      for a in args {
        sb_walk_expr(a, cname, later, hits)
      }
    }
    BinOp(_, a, b) | Seq(a, b) | IndexAccess(a, b) | ComputedProp(a, b) => {
      sb_walk_expr(a, cname, later, hits)
      sb_walk_expr(b, cname, later, hits)
    }
    IndexAssignExpr(a, b, c) | Cond(a, b, c) => {
      sb_walk_expr(a, cname, later, hits)
      sb_walk_expr(b, cname, later, hits)
      sb_walk_expr(c, cname, later, hits)
    }
    UnaryOp(_, x)
    | Spread(x)
    | Await(x)
    | YieldStar(x)
    | PureCall(x)
    | TypeArgs(_, x)
    | AssignExpr(_, x)
    | AssignPattern(_, x) => sb_walk_expr(x, cname, later, hits)
    CompoundAssignExpr(a, _, b) => {
      sb_walk_expr(a, cname, later, hits)
      sb_walk_expr(b, cname, later, hits)
    }
    Yield(opt) =>
      match opt {
        Some(x) => sb_walk_expr(x, cname, later, hits)
        None => ()
      }
    Call(_, args) | New(_, args) =>
      for a in args {
        sb_walk_expr(a, cname, later, hits)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      sb_walk_expr(callee, cname, later, hits)
      for a in args {
        sb_walk_expr(a, cname, later, hits)
      }
    }
    ArrayLit(items) =>
      for it in items {
        sb_walk_expr(it, cname, later, hits)
      }
    ObjectLit(entries) =>
      for ent in entries {
        sb_walk_expr(ent.1, cname, later, hits)
      }
    TaggedTemplate(tag, _, _, exprs) => {
      sb_walk_expr(tag, cname, later, hits)
      for e in exprs {
        sb_walk_expr(e, cname, later, hits)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        sb_walk_expr(e, cname, later, hits)
      }
    DynamicImport(a, b) => {
      sb_walk_expr(a, cname, later, hits)
      match b {
        Some(x) => sb_walk_expr(x, cname, later, hits)
        None => ()
      }
    }
    _ => ()
  }
}

///|
fn sb_walk_block(
  block : @ast.TsBlock,
  cname : String,
  later : Map[String, Bool],
  hits : Array[String],
) -> Unit {
  for s in block.stmts {
    sb_walk_stmt(s, cname, later, hits)
  }
}

///|
fn sb_walk_stmt(
  stmt : @ast.TsStmt,
  cname : String,
  later : Map[String, Bool],
  hits : Array[String],
) -> Unit {
  match stmt {
    Var(_, _, e)
    | Let(_, _, e)
    | Const(_, _, e)
    | Assign(_, e)
    | CompoundAssign(_, _, e)
    | Expr(e)
    | Throw(e)
    | Return(Some(e)) => sb_walk_expr(e, cname, later, hits)
    PropAssign(recv, prop, value) => {
      match recv {
        Var(n) =>
          if (n == "this" || n == cname) && later.get(prop) is Some(_) {
            hits.push(prop)
          }
        _ => ()
      }
      sb_walk_expr(recv, cname, later, hits)
      sb_walk_expr(value, cname, later, hits)
    }
    IndexAssign(a, b, c) => {
      sb_walk_expr(a, cname, later, hits)
      sb_walk_expr(b, cname, later, hits)
      sb_walk_expr(c, cname, later, hits)
    }
    Try(b, _, cb, fb) => {
      sb_walk_block(b, cname, later, hits)
      match cb {
        Some(x) => sb_walk_block(x, cname, later, hits)
        None => ()
      }
      match fb {
        Some(x) => sb_walk_block(x, cname, later, hits)
        None => ()
      }
    }
    If(c, t, e) => {
      sb_walk_expr(c, cname, later, hits)
      sb_walk_block(t, cname, later, hits)
      match e {
        Some(x) => sb_walk_block(x, cname, later, hits)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) | With(c, b) => {
      sb_walk_expr(c, cname, later, hits)
      sb_walk_block(b, cname, later, hits)
    }
    For(init, cond, upd, body) => {
      match init {
        Some(s) => sb_walk_stmt(s, cname, later, hits)
        None => ()
      }
      match cond {
        Some(e) => sb_walk_expr(e, cname, later, hits)
        None => ()
      }
      match upd {
        Some(s) => sb_walk_stmt(s, cname, later, hits)
        None => ()
      }
      sb_walk_block(body, cname, later, hits)
    }
    ForOf(_, _, _, e, b) | ForAwaitOf(_, _, _, e, b) | ForIn(_, _, _, e, b) => {
      sb_walk_expr(e, cname, later, hits)
      sb_walk_block(b, cname, later, hits)
    }
    Switch(e, cases) => {
      sb_walk_expr(e, cname, later, hits)
      for case in cases {
        match case.test_expr {
          Some(t) => sb_walk_expr(t, cname, later, hits)
          None => ()
        }
        sb_walk_block(case.body, cname, later, hits)
      }
    }
    Label(_, s) => sb_walk_stmt(s, cname, later, hits)
    Block(b) => sb_walk_block(b, cname, later, hits)
    _ => ()
  }
}

///|
/// TS2729 for `static { … }` blocks: a read or write of `this.<f>` /
/// `<ClassName>.<f>` inside a static block, where the static *field* `f`
/// is first declared after that block, runs before the field initializes.
/// Static methods and accessors are installed before blocks execute, so
/// only data fields participate. A block whose top level rebinds the class
/// name is skipped, and nested function bodies are never entered.
fn static_block_use_before_def(
  class_name : String,
  elements : Array[ClassElement],
) -> Array[String] {
  let hits : Array[String] = []
  if class_name == "" || class_name.has_prefix("<") {
    return hits
  }
  // First declaration index of every public static field.
  let first_decl : Map[String, Int] = {}
  for i, element in elements {
    match element {
      Field(true, Name(n), _, _, _, _) =>
        if is_public_runtime_class_member_name(n) && !first_decl.contains(n) {
          first_decl[n] = i
        }
      _ => ()
    }
  }
  if first_decl.length() == 0 {
    return hits
  }
  for i, element in elements {
    match element {
      StaticBlock(block) => {
        let later : Map[String, Bool] = {}
        for n, di in first_decl {
          if di > i {
            later[n] = true
          }
        }
        if later.length() == 0 {
          continue
        }
        let mut rebinds = false
        for s in block.stmts {
          match s {
            @ast.TsStmt::Var(b, _, _)
            | @ast.TsStmt::Let(b, _, _)
            | @ast.TsStmt::Const(b, _, _) =>
              if sb_binding_binds(b, class_name) {
                rebinds = true
              }
            _ => ()
          }
        }
        if rebinds {
          continue
        }
        sb_walk_block(block, class_name, later, hits)
      }
      _ => ()
    }
  }
  hits
}

///|
fn build_runtime_class_decl(
  name : String,
  type_params : Array[String],
  type_param_bounds : Array[(String, @ast.TsType)],
  ctor_opt : @ast.TsFunc?,
  elements : Array[ClassElement],
  is_abstract : Bool,
  private_members : Array[String],
  protected_members : Array[String],
  abstract_members : Array[String],
  implements_names : Array[String],
) -> @ast.TsClassDecl {
  let properties : Array[@ast.TsClassPropertyDecl] = []
  let methods : Array[@ast.TsClassMethodDecl] = []
  let instance_field_inits : Array[(String, @ast.TsExpr)] = []
  let static_field_inits : Array[(String, @ast.TsExpr)] = []
  let computed_field_keys : Array[@ast.TsExpr] = []
  let constructor_param_is_rest : Array[Bool] = []
  let constructor_param_defaults : Array[@ast.TsExpr?] = []
  let constructor_params = match ctor_opt {
    Some(ctor) => {
      let params : Array[(String, @ast.TsType)] = []
      for index, param in ctor.params {
        params.push((runtime_class_param_name(param, index), param.type_))
        constructor_param_is_rest.push(param.is_rest)
        constructor_param_defaults.push(param.default)
      }
      Some(params)
    }
    None => None
  }
  // Retain the constructor body (when it has one) so the checker can walk
  // its statements with `this` bound to the instance type. An overload
  // signature carries an empty body, which is harmless.
  let constructor_body : @ast.TsBlock? = match ctor_opt {
    Some(ctor) => Some(ctor.body)
    None => None
  }
  for element in elements {
    match element {
      Field(
        is_static,
        Name(field_name),
        field_type,
        init,
        is_readonly,
        has_definite_assertion
      ) =>
        if is_public_runtime_class_member_name(field_name) {
          // An unannotated field initialized by an arrow whose return type
          // is a type predicate (`isElite = (): this is T => {...}`) is a
          // callable guard. Synthesize its `Func` type so method-predicate
          // narrowing can see the `this is T` return (arrow-field guards
          // narrow the receiver the same way method guards do).
          let effective_type = match (field_type, init) {
            (@ast.TsType::Any, Some(@ast.TsExpr::ArrowFunc(aparams, aret, _, _))
            ) =>
              match aret {
                @ast.TsType::TypePredicate(_, _) => {
                  let pts : Array[@ast.TsType] = []
                  for p in aparams {
                    pts.push(p.type_)
                  }
                  @ast.TsType::Func(pts, aret)
                }
                _ => field_type
              }
            _ => field_type
          }
          upsert_class_property(properties, {
            name: field_name,
            type_: effective_type,
            is_static,
            is_readonly,
            is_accessor: false,
            has_initializer: init is Some(_),
            has_definite_assertion,
          })
          match init {
            Some(expr) =>
              if is_static {
                static_field_inits.push((field_name, expr))
              } else {
                instance_field_inits.push((field_name, expr))
              }
            None => ()
          }
        }
      Method(is_static, Name(method_name), accessor_kind, func) =>
        if is_public_runtime_class_member_name(method_name) {
          // Always record the method (so getters/setters keep their
          // bodies for emit); the `accessor` tag tells the emitter
          // whether to restore `get foo()` / `set foo(v)` syntax.
          let (params, param_defaults, param_is_rest, method_body) = runtime_class_method_params(
            func,
          )
          let accessor_tag = match accessor_kind {
            Some("get") => "get"
            Some("set") => "set"
            _ => ""
          }
          methods.push({
            name: method_name,
            type_params: func.type_params,
            type_param_bounds: [],
            params,
            param_defaults,
            param_is_rest,
            return_type: func.return_type,
            is_static,
            body: if method_body.stmts.length() == 0 {
              None
            } else {
              Some(method_body)
            },
            accessor: accessor_tag,
            key_expr: None,
            is_async: func.is_async,
            is_generator: func.is_generator,
          })
          match accessor_kind {
            Some("get") =>
              upsert_class_property(properties, {
                name: method_name,
                type_: func.return_type,
                is_static,
                is_readonly: true,
                is_accessor: false,
                has_initializer: false,
                has_definite_assertion: false,
              })
            Some("set") => {
              let setter_type = if func.params.length() > 0 {
                func.params[0].type_
              } else {
                @ast.TsType::Any
              }
              upsert_class_property(properties, {
                name: method_name,
                type_: setter_type,
                is_static,
                is_readonly: false,
                is_accessor: false,
                has_initializer: false,
                has_definite_assertion: false,
              })
            }
            _ => ()
          }
        }
      // Computed-key method (`class X { [Sym.iterator]() {…} }` /
      // `[OpCodes.OP_ON_SUCCESS](op) {…}`). Record it on the
      // `methods` list with the sentinel name `<computed>` and the
      // parsed key expression on `key_expr` so emit can restore
      // `[<expr>](…)` inside the class body. Effect's FiberRuntime
      // dispatches `this[cur._op](cur)` on these; dropping them
      // (which the previous code did) made `_op === "OnSuccess"`
      // resolve to `undefined` and runLoop ran forever.
      Method(is_static, Computed(key_expr), accessor_kind, func) => {
        let (params, param_defaults, param_is_rest, method_body) = runtime_class_method_params(
          func,
        )
        let accessor_tag = match accessor_kind {
          Some("get") => "get"
          Some("set") => "set"
          _ => ""
        }
        methods.push({
          name: class_key_name(Computed(key_expr)),
          type_params: func.type_params,
          type_param_bounds: [],
          params,
          param_defaults,
          param_is_rest,
          return_type: func.return_type,
          is_static,
          body: if method_body.stmts.length() == 0 {
            None
          } else {
            Some(method_body)
          },
          accessor: accessor_tag,
          key_expr: Some(key_expr),
          is_async: func.is_async,
          is_generator: func.is_generator,
        })
      }
      // A computed-key field (`class C { [e] = 1 }`). The property itself is
      // recorded under the `<computed>` sentinel by the value-name passes;
      // retain the key expression so the checker can flag an undefined name
      // in it (TS2304).
      Field(
        is_static_c,
        Computed(key_expr),
        field_type,
        init,
        is_readonly_c,
        has_definite_assertion_c
      ) => {
        computed_field_keys.push(key_expr)
        // Also surface the field's annotated/initialized shape under the
        // `<computed>` sentinel name so strict-property-initialization
        // (TS2564: `[Symbol.toPrimitive]: number;` with no initializer)
        // can see it. Pushed, not upserted -- computed names may repeat,
        // and name-keyed member checks skip the sentinel.
        properties.push({
          name: class_key_name(Computed(key_expr)),
          type_: field_type,
          is_static: is_static_c,
          is_readonly: is_readonly_c,
          is_accessor: false,
          has_initializer: init is Some(_),
          has_definite_assertion: has_definite_assertion_c,
        })
      }
      _ => ()
    }
  }
  // Track index-signature presence so the TS2564 check can opt-out
  // (an indexer implicitly types every concrete field), and carry the
  // captured key/value types so the TS2411 index-constraint check can
  // verify named properties are assignable to the index value type.
  let index_signatures : Array[(@ast.TsType, @ast.TsType)] = []
  let static_index_signatures : Array[(@ast.TsType, @ast.TsType)] = []
  let static_blocks : Array[@ast.TsBlock] = []
  for element in elements {
    match element {
      IndexSig(key, value, is_static) =>
        if is_static {
          static_index_signatures.push((key, value))
        } else {
          index_signatures.push((key, value))
        }
      StaticBlock(block) => static_blocks.push(block)
      _ => ()
    }
  }
  // TS2300: a class member declared in two incompatible ways within one
  // class body is a duplicate identifier. Per member name (keyed by
  // `name|static` so an instance and a static member of the same name stay
  // legal) we count how it was declared -- data field, getter, setter, or
  // regular (non-accessor) method -- and flag the combinations TypeScript
  // rejects. All are decided from declaration shape alone, so the check is
  // false-positive-free:
  //   - a data field together with *any* other declaration of the name;
  //   - two or more getters, or two or more setters;
  //   - a getter / setter together with a regular method.
  // Legal and left silent: a single field, method *overloads* (several
  // non-accessor methods -- a separate diagnostic family), and a get/set
  // pair.
  let counts : Map[String, Array[Int]] = {} // key -> [field, get, set, method]
  let key_name : Map[String, String] = {}
  // Private names (`#foo`) share a *single* namespace across the static and
  // instance halves of a class (a static `#foo` and an instance `#foo`
  // collide, TS2804), unlike public members. Accumulate them separately keyed
  // by the bare name with no `|s` / `|i` split.
  let priv_counts : Map[String, Array[Int]] = {}
  for element in elements {
    let (name, is_static, slot) = match element {
      Field(s, Name(n), _, _, _, _) => (n, s, 0)
      Method(s, Name(n), Some("get"), _) => (n, s, 1)
      Method(s, Name(n), Some("set"), _) => (n, s, 2)
      Method(s, Name(n), _, _) => (n, s, 3)
      _ => continue
    }
    if !is_public_runtime_class_member_name(name) {
      // Only `#name` private identifiers participate; `<computed>` and other
      // non-public synthetic names are skipped (we can't reason about them).
      if name.has_prefix("#") {
        let c = match priv_counts.get(name) {
          Some(existing) => existing
          None => {
            let fresh = [0, 0, 0, 0]
            priv_counts[name] = fresh
            fresh
          }
        }
        c[slot] += 1
      }
      continue
    }
    let key = if is_static { name + "|s" } else { name + "|i" }
    let c = match counts.get(key) {
      Some(existing) => existing
      None => {
        let fresh = [0, 0, 0, 0]
        counts[key] = fresh
        key_name[key] = name
        fresh
      }
    }
    c[slot] += 1
  }
  let duplicate_member_names : Array[String] = []
  let dup_seen : Map[String, Unit] = {}
  for key, c in counts {
    let nf = c[0]
    let ng = c[1]
    let ns = c[2]
    let nm = c[3]
    let is_dup = (nf >= 1 && nf + ng + ns + nm > nf) ||
      ng >= 2 ||
      ns >= 2 ||
      ((ng >= 1 || ns >= 1) && nm >= 1)
    if is_dup && !(dup_seen.get(key) is Some(_)) {
      dup_seen[key] = ()
      duplicate_member_names.push(key_name.get(key).unwrap())
    }
  }
  // Private-name duplicates (TS2300 / TS2804). The only legal repeat of a
  // private name is a getter + setter pair (ng=ns=1, nf=nm=0 — none of the
  // clauses fire). Pure method multiplicity is left silent to match the public
  // rule and avoid any overload-shape false positive.
  for name, c in priv_counts {
    let nf = c[0]
    let ng = c[1]
    let ns = c[2]
    let nm = c[3]
    // Two data fields of the same private name is also always a duplicate
    // (`nf >= 2`); the only legal repeat is a getter + setter pair.
    let is_dup = nf >= 2 ||
      (nf >= 1 && nf + ng + ns + nm > nf) ||
      ng >= 2 ||
      ns >= 2 ||
      ((ng >= 1 || ns >= 1) && nm >= 1)
    if is_dup && !(dup_seen.get(name) is Some(_)) {
      dup_seen[name] = ()
      duplicate_member_names.push(name)
    }
  }
  // TS2729: `this.<f>` / `<Name>.<f>` inside a static block before the
  // static field `f` is declared. Routed through the per-class channel as
  // a marker; the checker turns it into the diagnostic.
  for f in static_block_use_before_def(name, elements) {
    duplicate_member_names.push("<static-use-before-def:" + f + ">")
  }
  {
    name,
    type_params,
    type_param_bounds,
    computed_field_keys,
    base_names: [],
    implements_names,
    base_expr: None,
    static_field_inits,
    static_blocks,
    instance_field_inits,
    constructor_params,
    constructor_param_is_rest,
    constructor_param_defaults,
    constructor_body,
    properties,
    methods,
    index_signatures,
    static_index_signatures,
    is_abstract,
    is_constructible: !is_abstract,
    is_local: false,
    // Decorators on runtime classes are attached by the caller via
    // `Parser::take_pending_decorators` after build returns; the
    // builder is parser-agnostic so it leaves the slot empty.
    decorators: [],
    is_declare: false,
    private_members,
    protected_members,
    abstract_members,
    duplicate_member_names,
  }
}

///|

///|
/// Record the runtime class declaration just parsed. Sets
/// `last_runtime_class_decl` (which the module path takes) and also
/// accumulates the class's field annotations into
/// `collected_class_fields`, because the lowering does not keep them:
/// a field with an initializer becomes a constructor assignment, so a
/// whole-program pass looking at the emitted class sees no types at
/// all.
fn Parser::record_runtime_class_decl(
  self : Parser,
  decl : @ast.TsClassDecl,
) -> Unit {
  self.last_runtime_class_decl = Some(decl)
  for p in decl.properties {
    self.collected_class_fields.push((p.name, p.type_))
  }
}

///|
fn Parser::take_last_runtime_class_decl(self : Parser) -> @ast.TsClassDecl? {
  let result = self.last_runtime_class_decl
  self.last_runtime_class_decl = None
  result
}

///|
/// Collect the class just parsed as a LOCAL one — declared in a function
/// body, a block or an `if` branch rather than at module top level.
///
/// The module-level dispatcher takes `last_runtime_class_decl` right after
/// parsing, and nothing else did, so a class one scope in was recorded
/// nowhere a checker rule could read: TS2420 ("class does not implement
/// interface"), TS2415 / TS2417 (accessibility and static-side
/// compatibility) and TS2564 (definite assignment) all fire at module top
/// level and none of them fired inside a function. Batch DN's TS2394 does,
/// because it lives in the parser and never needed the list.
///
/// Taking the stash here also clears it, which is a small fix of its own:
/// it used to be left dirty after a nested class, where only the next
/// module-level class parse happened to overwrite it.
fn Parser::record_local_class(self : Parser) -> Unit {
  match self.take_last_runtime_class_decl() {
    Some(decl) => self.collected_local_classes.push({ ..decl, is_local: true })
    None => ()
  }
}

///|
/// Collect a class EXPRESSION (`const C = class { … }`) as a local class.
///
/// A class expression is never a top-level declaration — the binding
/// belongs to the surrounding `const C = …`, not to the class — so this is
/// unconditionally local and needs nothing from the six callers of
/// `parse_class_stub`. Without it the class-shape rules were blind to the
/// expression form: measured, TS2420 (implements), TS2415 (extends
/// accessibility) and TS2564 (definite assignment) all fire on a class
/// DECLARATION, on `declare class` and on a namespace-scoped class, and
/// on `const C = class …` not one of them did.
///
/// Called from BOTH of `parse_class_stub`'s exits, which is the point:
/// the native path is taken only when there is an `extends` clause, and a
/// base-less class expression falls through to the desugar below it.
/// Recording at the first exit alone bought exactly the one rule that
/// needs a base — TS2415 fired and the other two stayed silent, which is
/// how the split was found.
///
/// An anonymous class expression gets a synthetic, per-occurrence name
/// (the base-less path already calls it `<class>`). Per-occurrence rather
/// than one shared spelling on purpose: the checker's merge skips a
/// repeated name, so a shared one would check only the FIRST anonymous
/// class in a file, and a file with several is the normal case (mixins).
/// Angle brackets are not identifier characters, so a synthetic name can
/// never collide with a declared one.
fn Parser::record_local_class_expr(
  self : Parser,
  decl : @ast.TsClassDecl,
) -> Unit {
  let name = if decl.name == "" || decl.name == "<class>" {
    "<class expression \{self.collected_local_classes.length() + 1}>"
  } else {
    decl.name
  }
  self.collected_local_classes.push({ ..decl, name, is_local: true })
}

///|
/// True when `t` mentions any of the type-parameter names held in `bounds`
/// (the `(name, bound)` pairs pushed for the enclosing scope). Used to detect a
/// static index signature whose value type references a class type parameter
/// (TS2302). Conservative: variants it does not descend simply return `false`,
/// so a missed reference never produces a false positive.
fn type_references_type_param_name(
  t : @ast.TsType,
  names : Array[String],
) -> Bool {
  fn mentions(name : String) -> Bool {
    for n in names {
      if n == name {
        return true
      }
    }
    false
  }

  fn walk(ty : @ast.TsType) -> Bool {
    match ty {
      Named(n) => mentions(n)
      Applied(n, args) => {
        if mentions(n) {
          return true
        }
        for a in args {
          if walk(a) {
            return true
          }
        }
        false
      }
      Array(inner) | Rest(inner) | Keyof(inner) => walk(inner)
      Union(members) | Intersection(members) | Tuple(members) => {
        for m in members {
          if walk(m) {
            return true
          }
        }
        false
      }
      Func(params, ret) => {
        for p in params {
          if walk(p) {
            return true
          }
        }
        walk(ret)
      }
      IndexedAccess(base, idx) => walk(base) || walk(idx)
      Object(fields) => {
        for f in fields {
          if walk(f.1) {
            return true
          }
        }
        false
      }
      _ => false
    }
  }

  walk(t)
}

///|
fn has_static_private_elements(elements : Array[ClassElement]) -> Bool {
  for element in elements {
    match element {
      Field(is_static, Name(name), _, _, _, _)
      | Method(is_static, Name(name), _, _) =>
        // Check for static private members
        if is_static && (name.has_prefix("#") || name.contains("__#")) {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
fn has_instance_private_elements(elements : Array[ClassElement]) -> Bool {
  for element in elements {
    match element {
      Field(is_static, Name(name), _, _, _, _)
      | Method(is_static, Name(name), _, _) =>
        // Check for instance (non-static) private members
        if !is_static && (name.has_prefix("#") || name.contains("__#")) {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
fn mangle_private_name(name : String, brand : String) -> String {
  if name.has_prefix("#") {
    // Strip the `#` — keeping it produces an invalid JS
    // identifier (`__brand__#field`). The brand prefix already
    // gives uniqueness for access control; the `#` was only
    // meaningful in the source-level private-field syntax.
    brand + "__" + name[1:].to_owned()
  } else {
    name
  }
}

///|
fn class_key_expr(key : ClassKey) -> @ast.TsExpr {
  match key {
    Name(name) => @ast.TsExpr::StringLit(name)
    Computed(expr) => expr
  }
}

///|
// Parse the comma-separated type references of an `implements` clause,
// returning each head name (qualified names joined with `.`, type arguments
// skipped). The leading `implements` keyword must already be consumed.
fn Parser::parse_implements_names(self : Parser) -> Array[String] {
  let names : Array[String] = []
  // TS1097: `class C extends A implements { }` — the list cannot be empty.
  // Tested as "the class body opens immediately" rather than as
  // "`names` came back empty", because an empty result is also what this
  // collector returns for a legal form it cannot spell (an `import("m").T`
  // reference, say), and blaming the author for a gap in the collector
  // would be a false positive. Recorded here, not at the two call sites,
  // so the rule cannot hold for a class declaration and not a class
  // expression.
  if self.check(LBrace) {
    self.record_suppressible_grammar_misuse(
      "an `implements` list cannot be empty",
    )
  }
  // Always consume up to the class body `{` (matching the previous
  // skip-to-`{` behaviour), collecting the head reference of each
  // comma-separated entry. `expect_name` is true at the start of an entry
  // (right after `implements` or a top-level comma); angle-bracket depth
  // tracking skips type arguments so a `,` inside `Foo<A, B>` isn't read as
  // an entry separator. Any unexpected token (e.g. the `?.` of an invalid
  // `implements A?.B`) is simply skipped, so parsing always resyncs on `{`.
  let mut expect_name = true
  let mut angle = 0
  while !self.check(LBrace) && !self.check(Eof) {
    // TS2500 ("A class can only implement an identifier/qualified-name
    // with optional type arguments"): `implements A?.B` is not a
    // qualified name. The collector's own comment above already named
    // this shape as the thing it skips — the diagnostic was simply never
    // written. Note the asymmetry, which is why this belongs here and
    // not at the `extends` clause: `class C1 extends A?.B {}` is LEGAL
    // (an `extends` clause takes an EXPRESSION), and
    // `classExtendingOptionalChain` says so by accepting the first half
    // of the same file.
    if self.peek().kind is Question && angle == 0 && self.peek_at(1).kind is Dot {
      self.grammar_misuses.push(
        "a class can only implement an identifier / qualified-name with optional type arguments",
      )
    }
    match self.peek().kind {
      Lt => {
        angle += 1
        self.advance() |> ignore
      }
      Gt => {
        if angle > 0 {
          angle -= 1
        }
        self.advance() |> ignore
      }
      Comma if angle == 0 => {
        expect_name = true
        self.advance() |> ignore
      }
      Ident(n) if angle == 0 && expect_name => {
        let parts = [n]
        self.advance() |> ignore
        while self.check(Dot) {
          self.advance() |> ignore
          match self.peek().kind {
            Ident(m) => {
              parts.push(m)
              self.advance() |> ignore
            }
            _ => break
          }
        }
        names.push(parts.join("."))
        expect_name = false
      }
      _ => self.advance() |> ignore
    }
  }
  names
}

///|
fn Parser::parse_class_base_name(self : Parser) -> String raise ParseError {
  let start = self.pos
  self.pending_class_base_expr = None
  if self.check(LParen) {
    let expr = self.parse_expr()
    self.pending_class_base_expr = Some(expr)
    return "<expr-base>"
  }
  // `class C extends null { ... }` is valid TS — it creates a constructor
  // with `null` as its prototype, used as a no-prototype class.
  if self.check(Null) {
    let _ = self.advance()
    let _ = start
    self.pending_class_base_expr = Some(@ast.TsExpr::Var("null"))
    return "<expr-base>"
  }
  // `class C extends class { ... } { ... }` — anonymous class expression as
  // the base. Delegate to the general expression parser; whatever it
  // produces collapses to the `<expr-base>` marker since we only need the
  // structural signal that an expression-shaped base was consumed.
  if self.check(Class) {
    let expr = self.parse_expr()
    self.pending_class_base_expr = Some(expr)
    let _ = start
    return "<expr-base>"
  }
  // Some contextual keywords (`declare`, `type`, `from`, `as`, `of`,
  // `in`) double as valid identifier names — `class X extends
  // declare(args) {}` in effect's Schema.js is the standard case.
  // Accept them at the heritage clause's leading name slot.
  let lead = match contextual_ident_token_name(self.peek().kind) {
    Some(n) => {
      let _ = self.advance()
      n
    }
    None =>
      match self.advance().kind {
        Ident(n) => n
        k => raise ParseError("Expected base class name, got \{k}")
      }
  }
  let mut full_name = lead
  while self.check(Dot) {
    let _ = self.advance()
    // After `.`, JS allows ANY reserved word as the property name
    // (post-ES5). `class X extends ns.default {…}` / `extends
    // obj.case {…}` is valid. Accept the reserved-word tokens
    // that the method-key parser already recognises.
    match member_access_token_name(self.peek().kind) {
      Some(n) => {
        let _ = self.advance()
        full_name = full_name + "." + n
      }
      None =>
        match self.advance().kind {
          Ident(n) => full_name = full_name + "." + n
          k => raise ParseError("Expected base class name, got \{k}")
        }
    }
  }
  // `class C extends A?.B { ... }` — optional-chain in the heritage clause.
  // Fall through to expression-based parsing.
  let has_optional_chain = self.check(Question) && self.peek_at(1).kind == Dot
  let mut is_expr_base = self.check(LParen) ||
    self.check(LBracket) ||
    has_optional_chain
  if !is_expr_base && self.check(Lt) {
    let saved = self.pos
    self.skip_type_args()
    is_expr_base = self.check(LParen) ||
      self.check(LBracket) ||
      (self.check(Question) && self.peek_at(1).kind == Dot)
    self.pos = saved
  }
  if is_expr_base {
    self.pos = start
    let expr = self.parse_expr()
    self.pending_class_base_expr = Some(expr)
    return "<expr-base>"
  }
  full_name
}

///|
/// the lexer's keyword classification needs to defer to the surface
/// identifier name.
fn contextual_ident_token_name(kind : TokenKind) -> String? {
  match kind {
    Declare => Some("declare")
    Type => Some("type")
    From => Some("from")
    As => Some("as")
    Of => Some("of")
    In => Some("in")
    _ => None
  }
}

///|
/// Token names allowed in member-access position (`obj.<name>`).
/// JS lets any IdentifierName — including reserved words — sit
/// after `.`. Prettier ships `class X extends reader_1.default {…}`
/// as the canonical case. Mirrors the broader keyword set already
/// accepted in `parse_class_method_key`.
fn member_access_token_name(kind : TokenKind) -> String? {
  match kind {
    Declare => Some("declare")
    Type => Some("type")
    From => Some("from")
    As => Some("as")
    Of => Some("of")
    In => Some("in")
    Default => Some("default")
    Return => Some("return")
    If => Some("if")
    Else => Some("else")
    For => Some("for")
    While => Some("while")
    Do => Some("do")
    Break => Some("break")
    Continue => Some("continue")
    Function => Some("function")
    Try => Some("try")
    Catch => Some("catch")
    Finally => Some("finally")
    Throw => Some("throw")
    Yield => Some("yield")
    Let => Some("let")
    Const => Some("const")
    Var => Some("var")
    Class => Some("class")
    New => Some("new")
    Case => Some("case")
    VoidType => Some("void")
    With => Some("with")
    Switch => Some("switch")
    Typeof => Some("typeof")
    Delete => Some("delete")
    Export => Some("export")
    Import => Some("import")
    Debugger => Some("debugger")
    Interface => Some("interface")
    Instanceof => Some("instanceof")
    Extends => Some("extends")
    NumberType => Some("number")
    BooleanType => Some("boolean")
    StringType => Some("string")
    IntType => Some("int")
    Bool(true) => Some("true")
    Bool(false) => Some("false")
    Null => Some("null")
    _ => None
  }
}

///|
fn Parser::parse_class_method_key(self : Parser) -> ClassKey raise ParseError {
  if self.match_(LBracket) {
    let key_expr = self.parse_assignment()
    let _ = self.expect(RBracket)
    return Computed(key_expr)
  }
  let name = match self.advance().kind {
    Ident(n) => n
    PrivateIdent(n) => self.resolve_private_name(n)
    Str(s) => {
      // Quotedness is erased from the returned key; record it so
      // strict-property-initialization can exempt literal-named fields
      // (`class C { 'a': {} }` is not TS2564-checked by tsc).
      self.quoted_member_names.push(s)
      s
    }
    Number(n) => "\{n}"
    Int(n) => "\{n}"
    // Reserved words can be used as method names in ES6+
    Return => "return"
    If => "if"
    Else => "else"
    For => "for"
    While => "while"
    Break => "break"
    Continue => "continue"
    Function => "function"
    Try => "try"
    Catch => "catch"
    Finally => "finally"
    Throw => "throw"
    Yield => "yield"
    Type => "type"
    Let => "let"
    Const => "const"
    Var => "var"
    Class => "class"
    New => "new"
    // Additional reserved words allowed as method names
    Default => "default"
    Do => "do"
    In => "in"
    Of => "of"
    Case => "case"
    VoidType => "void"
    With => "with"
    Switch => "switch"
    Typeof => "typeof"
    Delete => "delete"
    Export => "export"
    Import => "import"
    Debugger => "debugger"
    Interface => "interface"
    Instanceof => "instanceof"
    Extends => "extends"
    From => "from"
    As => "as"
    NumberType => "number"
    BooleanType => "boolean"
    StringType => "string"
    IntType => "int"
    Bool(true) => "true"
    Bool(false) => "false"
    Null => "null"
    // Note: static, this, super, true, false, null, get, set, of, async, await
    // are handled as Ident tokens with special names, not separate TokenKind
    k => raise ParseError("Expected method name, got \{k}")
  }
  Name(name)
}

///|
fn Parser::can_consume_class_modifier(self : Parser) -> Bool {
  match self.peek_at(1).kind {
    Colon | LParen | Lt | Eq | Semicolon | RBrace | Question | Bang => false
    _ => true
  }
}

///|
fn Parser::try_skip_class_index_signature(self : Parser) -> Bool {
  if !self.check(LBracket) {
    return false
  }
  let saved_pos = self.pos
  let _ = self.advance()
  let mut depth = 1
  let mut has_index_type_separator = false
  while depth > 0 && !self.check(Eof) {
    match self.peek().kind {
      Colon if depth == 1 => {
        has_index_type_separator = true
        let _ = self.advance()
      }
      LBracket => {
        depth += 1
        let _ = self.advance()
      }
      RBracket => {
        depth -= 1
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
  if !has_index_type_separator {
    self.pos = saved_pos
    return false
  }
  if self.match_(Colon) {
    try {
      let _ = self.parse_type()
    } catch {
      _ => self.skip_until_semicolon()
    }
  }
  if self.check(Semicolon) || self.check(Comma) {
    let _ = self.advance()
  }
  true
}

///|
fn Parser::is_super_call_stmt(_self : Parser, stmt : @ast.TsStmt) -> Bool {
  match stmt {
    Expr(Call("super", _)) => true
    Expr(CallExpr(@ast.TsExpr::Var("super"), _)) => true
    _ => false
  }
}

///|
// Returns true if the block contains a `super(...)` call anywhere (recursively).
fn block_has_super_call(block : @ast.TsBlock) -> Bool {
  block.stmts.iter().any(stmt_has_super_call)
}

///|
fn stmt_has_super_call(stmt : @ast.TsStmt) -> Bool {
  match stmt {
    Expr(e) => expr_has_super_call(e)
    If(_, then_b, else_b) =>
      block_has_super_call(then_b) ||
      (match else_b {
        Some(eb) => block_has_super_call(eb)
        None => false
      })
    Try(b, _, cb, fb) =>
      block_has_super_call(b) ||
      (match cb {
        Some(cb2) => block_has_super_call(cb2)
        None => false
      }) ||
      (match fb {
        Some(fb2) => block_has_super_call(fb2)
        None => false
      })
    Block(b) => block_has_super_call(b)
    Label(_, s) => stmt_has_super_call(s)
    _ => false
  }
}

///|
fn expr_has_super_call(expr : @ast.TsExpr) -> Bool {
  match expr {
    Call("super", _) | CallExpr(@ast.TsExpr::Var("super"), _) => true
    Seq(a, b) => expr_has_super_call(a) || expr_has_super_call(b)
    Cond(c, t, e) =>
      expr_has_super_call(c) || expr_has_super_call(t) || expr_has_super_call(e)
    BinOp(_, a, b) => expr_has_super_call(a) || expr_has_super_call(b)
    _ => false
  }
}

///|
// Inject `assigns` after every `super(...)` call in a block, recursively.
fn inject_assigns_after_super_in_block(
  block : @ast.TsBlock,
  assigns : Array[@ast.TsStmt],
) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    let expanded = inject_assigns_after_super_in_stmt(s, assigns)
    for es in expanded {
      stmts.push(es)
    }
  }
  { stmts, stmt_positions: [] }
}

///|
// Returns a list of statements that replace `stmt`, with `assigns` injected
// after any `super(...)` call (top-level or nested in if/try/block).
fn inject_assigns_after_super_in_stmt(
  stmt : @ast.TsStmt,
  assigns : Array[@ast.TsStmt],
) -> Array[@ast.TsStmt] {
  match stmt {
    Expr(e) if expr_has_super_call(e) => {
      let out = [stmt]
      for a in assigns {
        out.push(a)
      }
      out
    }
    If(cond, then_b, else_b) if stmt_has_super_call(stmt) => {
      let new_then = if block_has_super_call(then_b) {
        inject_assigns_after_super_in_block(then_b, assigns)
      } else {
        then_b
      }
      let new_else = match else_b {
        Some(eb) if block_has_super_call(eb) =>
          Some(inject_assigns_after_super_in_block(eb, assigns))
        x => x
      }
      [If(cond, new_then, new_else)]
    }
    Try(b, handler, cb, fb) if stmt_has_super_call(stmt) => {
      let new_b = if block_has_super_call(b) {
        inject_assigns_after_super_in_block(b, assigns)
      } else {
        b
      }
      let new_cb = match cb {
        Some(cb2) if block_has_super_call(cb2) =>
          Some(inject_assigns_after_super_in_block(cb2, assigns))
        x => x
      }
      let new_fb = match fb {
        Some(fb2) if block_has_super_call(fb2) =>
          Some(inject_assigns_after_super_in_block(fb2, assigns))
        x => x
      }
      [Try(new_b, handler, new_cb, new_fb)]
    }
    Block(b) if block_has_super_call(b) =>
      [Block(inject_assigns_after_super_in_block(b, assigns))]
    Label(lbl, s) if stmt_has_super_call(s) => {
      let expanded = inject_assigns_after_super_in_stmt(s, assigns)
      match expanded {
        [single] => [Label(lbl, single)]
        _ => {
          let out = []
          for es in expanded {
            out.push(es)
          }
          out
        }
      }
    }
    _ => [stmt]
  }
}

///|
// Skip a decorator (`@expr` or `@expr(args)`) precisely, matching only the
// decorator expression itself and not anything that follows it on the same
// line. The grammar we accept:
//   Decorator ::= '@' DecoratorMemberExpression Arguments?
//   DecoratorMemberExpression ::= '(' Expression ')'
//                              | IdentifierReference ('.' IdentifierName)*
fn Parser::skip_decorator(self : Parser) -> Unit {
  try self.parse_decorator_expr() catch {
    _ => ()
  } noraise {
    Some(expr) => self.pending_decorators.push(expr)
    None => ()
  }
}

///|
/// Parse a single `@expr` decorator and return its expression form so
/// the caller can attach it to the next declaration. Mirrors the
/// shape of `skip_decorator` but builds a `TsExpr` instead of
/// discarding tokens. Returns `None` when the `@` isn't followed by a
/// recognized decorator head — keeps the existing permissive
/// recovery.
fn Parser::parse_decorator_expr(self : Parser) -> @ast.TsExpr? raise ParseError {
  let _ = self.match_(At)
  let head : @ast.TsExpr = match self.peek().kind {
    LParen => {
      // `@(expr)` form. Use the standard parenthesized-expression parser
      // so the captured expression is faithful; shapes it can't model
      // (instantiation expressions like `@(g<number>)` —
      // esDecorators-decoratorExpression.2) fall back to a balanced skip
      // with a placeholder head.
      let _ = self.advance()
      let saved = self.pos
      let inner_opt : @ast.TsExpr? = try self.parse_assignment() catch {
        _ => None
      } noraise {
        e => Some(e)
      }
      match inner_opt {
        Some(inner) if self.check(RParen) => {
          let _ = self.advance()
          inner
        }
        _ => {
          self.pos = saved
          let mut depth = 1
          while depth > 0 && !self.check(Eof) {
            match self.peek().kind {
              LParen => depth += 1
              RParen => depth -= 1
              _ => ()
            }
            let _ = self.advance()
          }
          Var("<decorator>")
        }
      }
    }
    Ident(_) => {
      let name = self.parse_binding_ident()
      let mut expr : @ast.TsExpr = Var(name)
      // Member / assertion chain: `@a.b.c`, `@x!`, `@x!.y`
      // (esDecorators-decoratorExpression.2).
      while true {
        if self.check(Dot) {
          let _ = self.advance()
          match self.peek().kind {
            Ident(prop) => {
              let _ = self.advance()
              expr = PropAccess(expr, prop)
            }
            _ => break
          }
        } else if self.check(Bang) {
          let _ = self.advance()
          expr = NonNull(expr)
        } else {
          break
        }
      }
      // Explicit type arguments before the call form (`@g<number>()`).
      if self.check(Lt) {
        let saved = self.pos
        match self.try_parse_simple_type_args() {
          Some(_) => if !self.check(LParen) { self.pos = saved }
          None => self.pos = saved
        }
      }
      expr
    }
    _ => return None
  }
  // Optional call form `@a(b, c)`.
  if self.check(LParen) {
    let _ = self.advance()
    let args : Array[@ast.TsExpr] = []
    if !self.check(RParen) {
      args.push(self.parse_assignment())
      while self.match_(Comma) {
        if self.check(RParen) {
          break
        }
        args.push(self.parse_assignment())
      }
    }
    let _ = self.expect(RParen)
    return Some(CallExpr(head, args))
  }
  Some(head)
}

///|
/// True when a decorator expression mentions `super` (which this parser
/// spells `Var("super")`).
///
/// TS2660: a decorator expression is evaluated where the CLASS is
/// defined, not inside a member body, so `super` has no meaning there
/// even when the class does extend something --
/// `class C extends S { @(super.m) method() {} }` is an error
/// (decoratorOnClassMethod12).
///
/// The arms are the shapes a decorator expression can take. Anything
/// else returns false, which costs a MISS rather than a finding: the
/// checker's `expr_mentions_super` is the complete walker and it cannot
/// be used here, because member decorator expressions never reach the
/// AST.
fn decorator_mentions_super(d : @ast.TsExpr) -> Bool {
  match d {
    Var("super") => true
    PropAccess(recv, _) => decorator_mentions_super(recv)
    IndexAccess(recv, idx) =>
      decorator_mentions_super(recv) || decorator_mentions_super(idx)
    MethodCall(recv, _, args) => {
      if decorator_mentions_super(recv) {
        return true
      }
      for a in args {
        if decorator_mentions_super(a) {
          return true
        }
      }
      false
    }
    Call(n, args) => {
      if n == "super" {
        return true
      }
      for a in args {
        if decorator_mentions_super(a) {
          return true
        }
      }
      false
    }
    CallExpr(callee, args) => {
      if decorator_mentions_super(callee) {
        return true
      }
      for a in args {
        if decorator_mentions_super(a) {
          return true
        }
      }
      false
    }
    TypeArgs(_, inner) | PureCall(inner) => decorator_mentions_super(inner)
    _ => false
  }
}

///|
/// The head NAME of a decorator expression, plus whether it was written
/// as a call. `@dec` -> `("bare", "dec")`, `@dec(1)` -> `("called",
/// "dec")`. `None` for every other shape (an inline arrow, a member
/// access, a parenthesized expression), which is what keeps the arity
/// check to the two forms whose signature the checker can look up by
/// name.
fn decorator_head_name(d : @ast.TsExpr) -> (String, String)? {
  match d {
    Var(n) => if n.has_prefix("<") { None } else { Some(("bare", n)) }
    Call(n, _) => if n.has_prefix("<") { None } else { Some(("called", n)) }
    CallExpr(Var(n), _) =>
      if n.has_prefix("<") {
        None
      } else {
        Some(("called", n))
      }
    _ => None
  }
}

///|
/// Drain any decorators accumulated via `skip_decorator` since the
/// last drain. Class parsers call this just before constructing the
/// `TsClassDecl` so the decorators end up on the right declaration.
fn Parser::take_pending_decorators(self : Parser) -> Array[@ast.TsExpr] {
  let out : Array[@ast.TsExpr] = []
  for d in self.pending_decorators {
    out.push(d)
  }
  self.pending_decorators.clear()
  out
}

///|
fn Parser::inject_instance_field_assigns(
  self : Parser,
  func : @ast.TsFunc,
  assigns : Array[@ast.TsStmt],
  base : String?,
) -> @ast.TsFunc {
  if assigns.length() == 0 {
    return func
  }
  let mut new_stmts : Array[@ast.TsStmt] = []
  let mut inserted = false
  if base is Some(_) {
    for stmt in func.body.stmts {
      new_stmts.push(stmt)
      if !inserted && self.is_super_call_stmt(stmt) {
        for assign in assigns {
          new_stmts.push(assign)
        }
        inserted = true
      }
    }
    if !inserted {
      // No top-level super() found. Try deep injection (super inside if/try).
      // Only fall back to prepending if no super call exists anywhere.
      if block_has_super_call(func.body) {
        new_stmts = inject_assigns_after_super_in_block(func.body, assigns).stmts
      } else {
        let combined : Array[@ast.TsStmt] = []
        for assign in assigns {
          combined.push(assign)
        }
        for stmt in func.body.stmts {
          combined.push(stmt)
        }
        new_stmts = combined
      }
    }
  } else {
    for assign in assigns {
      new_stmts.push(assign)
    }
    for stmt in func.body.stmts {
      new_stmts.push(stmt)
    }
  }
  {
    name: func.name,
    type_params: func.type_params,
    params: func.params,
    return_type: func.return_type,
    body: { stmts: new_stmts, stmt_positions: [] },
    const_type_params: [],
    type_param_bounds: func.type_param_bounds,
    is_generator: func.is_generator,
    is_async: func.is_async,
  }
}

///|
/// TS6133 ("'#unused' is declared but its value is never read") for a
/// `#private` class member, under `@noUnusedLocals`.
///
/// Decided by COUNTING, which is what makes it sound in the one
/// direction that matters. A private name is class-scoped, so every read
/// of it must spell `#name` — therefore the number of `PrivateIdent`
/// tokens carrying that name is an exact upper bound on
/// declarations + reads, and when it does not EXCEED the declaration
/// count the class parsers recorded, nothing reads it. A read this
/// misses is impossible; an extra occurrence (a second class declaring
/// the same name) only makes it quieter. That fail direction is the
/// whole reason this is not the reference-recording walk an earlier note
/// deferred: a missed read there makes a used member look unused, which
/// is a false positive.
///
/// File-level rather than per-class, deliberately. `privateNameUnused`
/// declares `#unused` FOUR times across three classes (a field, a
/// method, and a get/set pair, which is two declarations of one member)
/// and reads it never — 4 occurrences against 4 declarations. Its
/// `#used` has the same four declarations plus three reads, so 7 against
/// 4 and silent. A `#x in v` brand check IS a read to tsc and is one
/// more occurrence, which is exactly why
/// `privateNameInInExpressionUnused` reports its `#unused` and not its
/// `#brand`.
fn Parser::record_unused_private_members(self : Parser, head : String) -> Unit {
  if not(detect_no_unused_locals(head)) {
    return
  }
  if self.private_decl_counts.size() == 0 {
    return
  }
  let occurrences : Map[String, Int] = {}
  for tok in self.tokens {
    if tok.kind is PrivateIdent(n) {
      occurrences[n] = occurrences.get(n).unwrap_or(0) + 1
    }
  }
  for entry in self.private_decl_counts {
    let (name, decls) = entry
    if occurrences.get(name).unwrap_or(0) <= decls {
      self.grammar_misuses.push(
        "`#\{name}` is declared but its value is never read",
      )
    }
  }
}

///|
/// TS2803 ("Cannot assign to private method") and TS2806 ("Private
/// accessor was defined without a getter"), decided over the class
/// body's TOKEN range — for a class EXPRESSION only.
///
/// Both diagnostics ALREADY EXIST in the checker, and probing them is
/// what showed why the two corpus files were still MISSes: those checks
/// read `module_.classes`, so they cannot see `const C = class { … }`,
/// which is the shape BOTH files use. So this is not a second copy of a
/// rule — `self.in_class_expr_body` restricts it to the case the
/// existing ones structurally cannot reach, and a class DECLARATION is
/// left entirely to them rather than reported twice.
///
/// A token scan rather than an AST walk, deliberately: a member body is
/// an arbitrary expression tree, and every access to `#x` must spell
/// `#x`, so scanning tokens is complete by construction where a walker
/// missing one arm would lose findings silently.
///
/// A `PrivateIdent` counts as an ACCESS only when a `.` precedes it,
/// which excludes both spellings that are not accesses: the member's own
/// declaration (`#x = 1`) and the brand check (`#x in v`). What follows
/// then decides the direction — a plain `=` is a write, a compound
/// assignment is both (it reads the old value, which is what makes
/// `this.#x += 2` a READ of a setter-only accessor), and `++` / `--`
/// likewise. Anything else is a read.
///
/// Both boundaries were probed. Writing to a set-only accessor is legal
/// and stays silent; writing to a GET-only one is TS2540, a different
/// code, not raised here; and writing to a plain private FIELD is of
/// course fine.
fn Parser::record_private_member_misuse(
  self : Parser,
  body_start : Int,
  methods : Array[String],
  getters : Array[String],
  setters : Array[String],
  implicit_any : Array[(String, String)],
) -> Unit {
  // TS7008's other half. A member with no annotation and no initializer
  // gets its type from an assignment in the CONSTRUCTOR (instance side)
  // or a STATIC BLOCK (static side) — probed, and a method-body
  // assignment does NOT count. Telling those regions apart from a flat
  // token scan would need brace tracking, so any `.name =` in the body
  // withdraws the report: that loses `class B { q; m() { this.q = 1 } }`
  // (a MISS) and keeps `classStaticBlockUseBeforeDef1`, which shipped as
  // a false positive on the first draft, silent.
  let written : Map[String, Unit] = {}
  for i in body_start..<self.pos {
    let name = match self.tokens[i].kind {
      Ident(n) => n
      PrivateIdent(n) => "#" + n
      _ => continue
    }
    if i == 0 || not(self.tokens[i - 1].kind is Dot) {
      continue
    }
    if i + 1 < self.tokens.length() && self.tokens[i + 1].kind is Eq {
      written[name] = ()
    }
  }
  for entry in implicit_any {
    let (shown, _) = entry
    if not(written.contains(shown)) {
      self.grammar_misuses.push(
        "member `\{shown}` implicitly has an `any` type",
      )
    }
  }
  if not(self.in_class_expr_body) {
    return
  }
  if methods.length() == 0 && setters.length() == 0 {
    return
  }
  for i in body_start..<self.pos {
    guard self.tokens[i].kind is PrivateIdent(name) else { continue }
    if i == 0 || not(self.tokens[i - 1].kind is Dot) {
      continue
    }
    let next = if i + 1 < self.tokens.length() {
      self.tokens[i + 1].kind
    } else {
      Eof
    }
    let is_plain_write = next is Eq
    let is_read_write = match next {
      PlusEq
      | MinusEq
      | StarEq
      | SlashEq
      | PercentEq
      | AmpEq
      | PipeEq
      | CaretEq
      | LtLtEq
      | GtGtEq
      | GtGtGtEq
      | StarStarEq
      | AmpAmpEq
      | PipePipeEq
      | QuestionQuestionEq
      | PlusPlus
      | MinusMinus => true
      _ => false
    }
    let reads = not(is_plain_write)
    if (is_plain_write || is_read_write) && methods.contains(name) {
      self.grammar_misuses.push(
        "cannot assign to private method `#\{name}` — private methods are not writable",
      )
    }
    if reads && setters.contains(name) && not(getters.contains(name)) {
      self.grammar_misuses.push(
        "private accessor `#\{name}` was defined without a getter",
      )
    }
  }
}

///|
fn Parser::parse_class_body(
  self : Parser,
  class_type_params : Array[String],
) -> (
  @ast.TsFunc?,
  Array[ClassElement],
  Array[String],
  Array[String],
  Array[String],
  Int,
  Int,
  Bool,
  Bool,
  Bool,
  Bool,
  Bool,
  Bool,
  Bool,
  Bool,
  Array[(Bool, String)],
) raise ParseError {
  let _ = self.expect(LBrace)
  // First token INSIDE the body. TS2803 / TS2806 are decided from this
  // token range rather than from an AST walk: a member's body is an
  // arbitrary expression tree, and a walker that misses one arm loses a
  // finding silently, while a token scan is complete by construction —
  // every access to `#x` spells `#x`.
  let body_token_start = self.pos
  // Class body is implicitly strict mode
  let prev_strict = self.in_strict
  self.in_strict = true
  // TS2803 / TS2806: which `#private` names this class declares as a
  // METHOD, and which as a SET-only accessor. Raw names (no brand), to
  // match the `PrivateIdent` tokens the scan below reads.
  let private_method_names : Array[String] = []
  let private_getters : Array[String] = []
  let private_setters : Array[String] = []
  // TS7008 candidates: (spelling to report, key as the token scan sees
  // it). Held until the body has been scanned, because an assignment in
  // the class body can supply the type.
  let implicit_any_candidates : Array[(String, String)] = []
  // TS1207: which get/set accessors carried a decorator, keyed
  // `<static>:<kind>:<name>`. Decorating BOTH halves of a get/set pair is
  // an error — one descriptor covers both, so two decorators would be
  // applied to the same thing. Accumulated per class BODY (this function
  // is the one place a class's members are parsed, so there is no second
  // site to forget) and decided at the end.
  let decorated_accessors : Array[String] = []
  // TS2393 support: the keys of methods that carried a real `{ … }` body
  // in THIS class body. Keyed by staticness + accessor kind + name,
  // because an instance and a static member of one name are different
  // members and a `get`/`set` pair is two of them.
  //
  // Recorded here rather than derived from `cls.methods` afterwards
  // because `TsClassMethodDecl.body` is `None` for an EMPTY body as
  // well as for a bodiless overload signature -- so `m() {}` and `m();`
  // are indistinguishable downstream, which is the class-shaped face of
  // the `TsFunc.body` blocker this repo records for TS2393 / TS2394.
  // The parser has `has_body_block` and does not need to guess.
  let bodied_method_keys : Map[String, Bool] = {}
  // TS2394 support: for each member key, the largest argument count each
  // BODILESS overload signature of it can supply (`-1` = unbounded, i.e.
  // the signature has a rest parameter). Compared against the
  // IMPLEMENTATION's required arity when that arrives — see
  // `signature_max_args` / `impl_required_arity` for why only that one
  // direction is an error.
  let sig_max_args : Map[String, Array[Int]] = {}
  // TS2386 support: the `?`-ness of the first declaration of each member
  // key in this class body. Unlike the interface / object-type sites, the
  // IMPLEMENTATION participates — a bodied method can never be optional,
  // so probing `m?(x); m?(s); m(v) { }` reports on BOTH signatures, and
  // recording only the bodiless ones would accept it.
  let method_sig_optional : Map[String, (Bool, Bool)] = {}
  let mut ctor : @ast.TsFunc? = None
  // Count constructor *implementations* (a `constructor(...) { ... }` with a
  // real body). Two or more is TS2392 ("Multiple constructor implementations
  // are not allowed").
  let mut ctor_impl_count = 0
  // Constructor OVERLOAD SIGNATURES — bodiless `constructor(...)`
  // declarations. Paired with `ctor_impl_count` for TS2390 below.
  let mut ctor_sig_count = 0
  // Set when an accessibility modifier (`public` / `private` / `protected`)
  // was written on an index signature -- always TS1071.
  let mut index_sig_modifier_misuse = false
  // Instance index signatures whose declared value type was a naked bounded
  // type parameter (`[x: number]: T` under `T extends Base`), as
  // `(is_numeric_key, param_name)`. See `try_parse_class_index_signature`.
  let index_naked_params : Array[(Bool, String)] = []
  // Set when an `abstract` method / accessor was given a real body -- always
  // TS1245 ("Method cannot have an implementation because it is marked
  // abstract").
  let mut abstract_member_with_body = false
  // Bodyless overload-signature method names by static-ness. A name appearing
  // as both a static and an instance overload signature is TS2387/2388. Uses
  // `has_body_block` (not the AST body, which can't tell an empty `{}` from a
  // signature) so an ordinary static+instance method *pair with bodies* is not
  // flagged.
  let ov_static : Map[String, Unit] = {}
  let ov_instance : Map[String, Unit] = {}
  // Body-bearing (implementation) methods by name, per static-ness. A name
  // with both a static and an instance *implementation* is two distinct
  // overload sets (e.g. `foo(){}` and `static foo(){}`), which is legal even
  // when each side also has bodyless overload signatures.
  let impl_static : Map[String, Unit] = {}
  let impl_instance : Map[String, Unit] = {}
  let elements : Array[ClassElement] = []
  // Names declared `private` / `protected`, collected so the class decl
  // can expose member visibility to the checker (TS2341 / TS2445).
  let private_members : Array[String] = []
  let protected_members : Array[String] = []
  let abstract_members : Array[String] = []
  // Accessibility of each constructor signature / implementation seen, in
  // order. Used for TS2385 ("overload signatures must all be public, private
  // or protected"): if a class declares 2+ constructor signatures whose
  // accessibilities differ, it's an error.
  let ctor_visibilities : Array[String] = []
  // Set when a member wrote `async` before `static` (`async static foo()`) --
  // always TS1029 ("'static' modifier must precede 'async' modifier").
  let mut modifier_order_misuse = false
  // Set when a class body contains a *statement* rather than a member
  // declaration -- `var x = 1` / `function foo() {}` at member position
  // (TS1128 "Declaration or statement expected"). Distinguished from a member
  // literally named `var` / `function` by requiring an identifier to follow
  // (the statement form), so `{ var: T }` / `{ var() {} }` stay valid members.
  let mut class_body_statement_misuse = false
  // Set when a *static* index signature's value type references one of the
  // enclosing class's type parameters (`class C<T> { static [k: string]: T }`)
  // -- always TS2302 ("Static members cannot reference class type
  // parameters"). The class type parameters are in scope via
  // `self.local_type_param_bounds` at the point the body is parsed. Only static
  // index signatures qualify; instance ones may reference `T` freely, so the
  // check is gated on `is_static` and never produces a false positive.
  let mut static_index_type_param_ref = false
  while !self.check(RBrace) && !self.check(Eof) {
    // `var x` / `function foo` etc. at member position is a statement, not a
    // member (TS1128) -- but only when the identifier is on the SAME line. A
    // line break makes ASI split the keyword into a standalone member named
    // `var` / `function` (`class C { var \n public }`), which TS accepts.
    if !self.peek_at(1).has_newline_before {
      match (self.peek().kind, self.peek_at(1).kind) {
        (Var, Ident(_))
        | (Let, Ident(_))
        | (Const, Ident(_))
        | (Function, Ident(_)) => class_body_statement_misuse = true
        _ => ()
      }
    }
    let deco_before = self.pending_decorators.length()
    while self.check(At) {
      self.skip_decorator()
    }
    let member_decorated = self.pending_decorators.length() > deco_before
    if self.match_(Semicolon) {
      continue
    }
    let mut is_static = false
    let mut is_async_method = false
    let mut is_readonly_field = false
    let mut has_modifier = true
    let mut parsed_static_block = false
    let mut has_declare = false
    // The stage-3 `accessor` field modifier. A decorator on one is
    // invoked with a DESCRIPTOR like a method's, not with the two
    // arguments a plain field's gets (decoratorOnClassProperty13 --
    // TS7-ACCEPTED with a 3-parameter decorator), so the arity record
    // below has to classify it as a method.
    let mut is_auto_accessor = false
    let mut visibility = "public"
    // Whether an explicit accessibility modifier (`public` / `private` /
    // `protected`) was written on this member. Used to flag TS1071 -- such a
    // modifier on an index signature is always an error -- where the default
    // "public" can't be distinguished from an explicitly written one.
    let mut saw_visibility_modifier = false
    let mut is_abstract_member = false
    let mut saw_override_modifier = false
    while has_modifier {
      has_modifier = false
      match self.peek().kind {
        // TS1031: `export` / `import` never modify class elements
        // (`class C { export constructor() {} }` —
        // parserConstructorDeclaration3/4, parserMemberFunction/
        // VariableDeclaration4). Consume it so the member still parses.
        Export =>
          // Only a MODIFIER position consumes it — `class C { export; }`
          // declares a field NAMED `export`
          // (propertyNamesOfReservedWords).
          if self.can_consume_class_modifier() {
            let _ = self.advance()
            self.grammar_misuses.push(
              "`export` modifier cannot appear on a class element",
            )
            has_modifier = true
          }
        Ident(n) if n == "static" =>
          if self.can_consume_class_modifier() {
            let _ = self.advance()
            // TS1029: `static` must precede `async` / `override` / `readonly`.
            // If any of those was already consumed for this member, the
            // source order was reversed.
            if is_async_method || saw_override_modifier || is_readonly_field {
              modifier_order_misuse = true
            }
            // TS1434 ("Unexpected keyword or identifier"): a SECOND
            // `static` on one member — `static static Foo() {}`,
            // `static static Foo;`, `static static [x: string]: string`
            // (parserMemberFunctionDeclaration2, parserMemberVariable
            // Declaration2, parserIndexMemberDeclaration10). tsc reports
            // this as a stray identifier rather than a duplicate modifier,
            // but the condition is exactly "already seen", the same shape
            // as the TS1028 accessibility check twenty lines below.
            if is_static {
              self.grammar_misuses.push("unexpected keyword or identifier")
            }
            is_static = true
            has_modifier = true
            // Check for static initialization block: static { ... }
            if self.check(LBrace) {
              // TS1206: "Decorators are not valid here." A static
              // initialization block is not a class ELEMENT a decorator can
              // apply to, in either decorator mode (classStaticBlock19).
              // Probed against the whole TS7-accepted corpus: not one file
              // TypeScript 7 accepts decorates a static block, so this needs
              // no mode gate.
              if member_decorated {
                self.invalid_decorator_uses.push("static block")
              }
              let prev_static_block = self.in_static_block
              self.in_static_block = true
              // TS1107 ("Jump target cannot cross function boundary"): a
              // static block IS a function boundary, so a label declared
              // outside it is not a jump target inside it. Fourteen sites
              // in three files already save / clear / restore
              // `self.labels` around a function body and this fifteenth
              // one did not, so `label: while (v) { class C { static {
              // break label } } }` found the outer label and stayed
              // silent (classStaticBlock8). Labels declared INSIDE the
              // block still resolve, which is what that file's second
              // class checks.
              let saved_labels : Array[String] = []
              while self.labels.length() > 0 {
                saved_labels.push(self.labels.pop().unwrap())
              }
              let block = self.parse_block()
              while saved_labels.length() > 0 {
                self.labels.push(saved_labels.pop().unwrap())
              }
              self.in_static_block = prev_static_block
              elements.push(StaticBlock(block))
              // TS2448: a top-level class's static block executes at class
              // definition time, so its immediate reads / writes of a
              // block-scoped variable declared LATER at top level hit the
              // TDZ. Record the free identifiers in parse order; the
              // checker pairs them with `<letconst-decl:…>` markers.
              if !self.in_function {
                let locals : Array[String] = []
                let reads : Array[String] = []
                for s in block.stmts {
                  sb_reads_stmt(s, locals, reads)
                }
                for r in reads {
                  if !locals.contains(r) {
                    self.grammar_misuses.push("<sb-read:" + r + ">")
                  }
                }
              }
              parsed_static_block = true
              break // Exit inner loop, then continue outer loop
            }
          }
        Ident(n) if n == "async" =>
          if self.can_consume_class_modifier() {
            let _ = self.advance()
            is_async_method = true
            has_modifier = true
          }
        Ident(n) if n == "readonly" =>
          if self.can_consume_class_modifier() {
            let _ = self.advance()
            is_readonly_field = true
            has_modifier = true
          }
        Ident(n) if n == "public" ||
          n == "private" ||
          n == "protected" ||
          n == "abstract" ||
          n == "override" ||
          n == "declare" ||
          n == "accessor" =>
          if self.can_consume_class_modifier() {
            let _ = self.advance()
            has_modifier = true
            if n == "accessor" {
              is_auto_accessor = true
            }
            if n == "public" || n == "private" || n == "protected" {
              // TS1028: a second accessibility modifier on one member
              // (`public public Foo()`, `private protected x`).
              if saw_visibility_modifier {
                self.grammar_misuses.push("accessibility modifier already seen")
              }
              saw_visibility_modifier = true
              // TS1029 / TS1028: an accessibility modifier must precede
              // `static` / `async` / `readonly` / `override` / `abstract`
              // (`static public x` is reversed).
              if is_static ||
                is_async_method ||
                is_readonly_field ||
                is_abstract_member ||
                saw_override_modifier {
                modifier_order_misuse = true
              }
            }
            if n == "override" {
              saw_override_modifier = true
              // TS1029: `override` must precede `readonly`.
              if is_readonly_field {
                modifier_order_misuse = true
              }
            }
            if n == "private" || n == "protected" {
              visibility = n
            }
            if n == "declare" {
              has_declare = true
            }
            if n == "abstract" {
              is_abstract_member = true
            }
          }
        Declare => {
          let _ = self.advance()
          has_modifier = true
          has_declare = true
        }
        _ => ()
      }
    }
    if parsed_static_block {
      continue // Continue to next class element
    }
    // Prefer the type-capturing index-signature parser so the value type
    // is available for the TS2411 index-constraint check. Fall back to the
    // permissive skip path (recording an `Any`/`Any` placeholder) for
    // shapes the precise parser declines, e.g. computed key expressions.
    if self.check(LBracket) && self.is_index_signature_shape_after_lbracket() {
      match self.try_parse_class_index_signature() {
        Some((key, value, naked_param)) => {
          if saw_visibility_modifier {
            index_sig_modifier_misuse = true
          }
          if is_static &&
            class_type_params.length() > 0 &&
            type_references_type_param_name(value, class_type_params) {
            static_index_type_param_ref = true
          }
          if !is_static {
            match naked_param {
              Some(np) => {
                let is_num = match key {
                  Number | Int => true
                  _ => false
                }
                index_naked_params.push((is_num, np))
              }
              None => ()
            }
          }
          elements.push(IndexSig(key, value, is_static))
          continue
        }
        None => ()
      }
    }
    if self.try_skip_class_index_signature() {
      if saw_visibility_modifier {
        index_sig_modifier_misuse = true
      }
      elements.push(IndexSig(@ast.TsType::Any, @ast.TsType::Any, is_static))
      continue
    }
    let mut accessor_kind : String? = None
    match self.peek().kind {
      Ident(n) if (n == "get" || n == "set") &&
        self.peek_at(1).kind != LParen &&
        self.peek_at(1).kind != Lt &&
        self.peek_at(1).kind != Colon &&
        // `class C { get; }` declares an uninitialized field named
        // `get`, not a get-accessor. Same for `set;`, `get = …;`,
        // `set, …`. The accessor form REQUIRES a method body, so
        // anything that looks like a field-decl terminator means
        // we should treat `get` / `set` as an identifier.
        self.peek_at(1).kind != Semicolon &&
        self.peek_at(1).kind != Eq &&
        self.peek_at(1).kind != Comma &&
        self.peek_at(1).kind != RBrace &&
        // `get!: T` (definite assignment) and `get?: T` (optional) are
        // fields too — the `!` / `?` binds to the field NAME, so a
        // getter can never be spelled that way. Hono declares its
        // route methods exactly like this (`get!: HandlerInterface<…>`,
        // `post!`, `delete!`), and without these two the whole
        // package failed to parse.
        self.peek_at(1).kind != Bang &&
        self.peek_at(1).kind != Question => {
        let _ = self.advance()
        accessor_kind = Some(n)
        // TS1042: `async` cannot modify an accessor (`async get foo()`).
        if is_async_method {
          self.grammar_misuses.push("`async` modifier cannot be used here")
        }
      }
      _ => ()
    }
    let is_generator = self.match_(Star)
    // Whether the member name is a `#private` one. Read before the key is
    // parsed, because `parse_class_method_key` mangles it to a brand and
    // the `#` is gone by the time the decorator check below runs.
    let key_is_private_name = self.peek().kind is PrivateIdent(_)
    // The RAW `#private` name, captured before the key parse mangles it
    // to a brand. Empty when the member is not a private one.
    let raw_private_name = match self.peek().kind {
      PrivateIdent(n) => n
      _ => ""
    }
    let key = self.parse_class_method_key()
    let method_name = class_key_name(key)
    // TS1436 ("Decorators must precede the name and all keywords of
    // property declarations"): an `@` immediately after the member NAME,
    // on the same line (`private prop @decorator` --
    // decoratorOnClassMethod17).
    //
    // The same-line test is the whole rule. With a line terminator
    // between them, ASI ends the property and the `@` opens the NEXT
    // member's decorator list, which is the ordinary legal spelling and
    // is what tsc accepts. And the check sits here, right after the key,
    // because at this point a method still has `(` ahead and a property
    // `:` / `=` / `;` -- an `@` in that slot is a misplaced decorator
    // under every reading.
    if self.check(At) && not(self.has_line_terminator_before()) {
      self.grammar_misuses.push(
        "decorators must precede the name and all keywords of property declarations",
      )
    }
    // TS1206: decorators are not valid on a constructor
    // (decoratorOnClassConstructor1), nor on `abstract` or ambient
    // (`declare`) members (esDecorators-classDeclaration-*-nonStatic
    // Abstract / -Ambient) — in both decorator modes.
    if member_decorated {
      // Legacy (`experimentalDecorators`) mode ACCEPTS decorators on
      // `declare` / `abstract` members (decoratorInAmbientContext);
      // only standard ES decorators reject them. Constructor
      // decoration is invalid in both modes.
      if (is_abstract_member || has_declare) && !self.experimental_decorators {
        self.invalid_decorator_uses.push("class member")
      } else if method_name == "constructor" &&
        (self.check(LParen) || self.check(Lt)) {
        self.invalid_decorator_uses.push("constructor")
      } else if self.experimental_decorators && key_is_private_name {
        // TS1206, and the mirror image of the `abstract` / `declare` case
        // above: a `#private` member is something only LEGACY decorators
        // reject, so the gate points the other way here
        // (privateNamesAndDecorators, and the two private members of
        // autoAccessorExperimentalDecorators).
        //
        // `accessor` was in this condition and was WRONG — two corpus
        // false positives said so. `@dec accessor prop` under
        // experimentalDecorators is accepted by TS7
        // (decoratorOnClassProperty13, and `static accessor y = 1` in
        // legacyDecorators-contextualTypes). The file that suggested the
        // rule, autoAccessorExperimentalDecorators, combines TWO features
        // and its baseline errors only on lines 12 and 15 — `accessor #a`
        // and `static accessor #b`. The private name was doing all the
        // work and the auto-accessor none of it: attributing the error to
        // the wrong half of a two-feature file is the same mistake this
        // repo records for `computed_props` and the decorator bucket.
        self.invalid_decorator_uses.push("class member")
      }
    }
    if member_decorated {
      match accessor_kind {
        Some(kind) =>
          decorated_accessors.push(
            (if is_static { "s:" } else { "i:" }) + kind + ":" + method_name,
          )
        None => ()
      }
    }
    // TS1240 / TS1241 / TS1329 support: record each of THIS member's
    // decorators as a `<sig:...>` entry so the checker can compare the
    // decorator's declared arity against the arity the runtime invokes it
    // with. The runtime arity differs by member kind (a property
    // decorator gets 2 arguments, a method or accessor decorator 3), which
    // is why the kind is captured here rather than at the `@`: this is the
    // first point where the key has been parsed, so `LParen` / `Lt` tells
    // a method from a property.
    //
    // Rides in `invalid_decorator_uses` because that channel is already
    // plumbed through every `TsModule` construction site; the `<sig:`
    // prefix is skipped by the TS1206 consumer, which otherwise turns
    // every entry into a diagnostic verbatim.
    if member_decorated {
      let kind = if accessor_kind is Some(_) ||
        is_auto_accessor ||
        self.check(LParen) ||
        self.check(Lt) {
        "method"
      } else {
        "property"
      }
      let mut di = deco_before
      while di < self.pending_decorators.length() {
        // TS2660: `super` in a decorator expression. Gated on NOT being
        // inside a function, because a class nested in a member body of
        // a derived class is a different question -- there the decorator
        // expression really does evaluate where `super` is bound, and
        // tsc accepts it (probed). `decoratorOnClassMethod12`'s class is
        // at namespace level, so `in_function` is false for it.
        if not(self.in_function) &&
          decorator_mentions_super(self.pending_decorators[di]) {
          self.grammar_misuses.push(
            "`super` can only be referenced in members of derived classes or object literal expressions",
          )
        }
        match decorator_head_name(self.pending_decorators[di]) {
          Some((called, dname)) =>
            self.invalid_decorator_uses.push(
              "<sig:" + kind + ":" + called + ":" + dname + ">",
            )
          None => ()
        }
        di += 1
      }
    }
    // TS2803 / TS2806 support: classify this member if it is a private
    // one. A private METHOD is not writable; a private accessor with a
    // setter and no getter is not readable.
    if key_is_private_name && raw_private_name != "" {
      // TS6133 support: one entry per private member DECLARATION. A
      // get/set pair is two declarations of one member, which is what
      // makes the count comparison in `record_unused_private_members`
      // come out right.
      self.private_decl_counts[raw_private_name] = self.private_decl_counts
        .get(raw_private_name)
        .unwrap_or(0) +
        1
      match accessor_kind {
        Some("get") => private_getters.push(raw_private_name)
        Some("set") => private_setters.push(raw_private_name)
        Some(_) => ()
        None =>
          // A method, not a field: a field's key is followed by `:`, `=`,
          // `?`, `!` or a terminator, never by a call signature.
          if self.check(LParen) || self.check(Lt) {
            private_method_names.push(raw_private_name)
          }
      }
    }
    // TS1031: `declare` may modify a class FIELD and nothing else, so any
    // member whose name is followed by a call signature is an error. The
    // rule was written for the constructor alone
    // (`parserConstructorDeclaration4`) and stopped there, leaving
    // `class C { declare Foo() { } }` silent
    // (`parserMemberFunctionDeclaration5`).
    //
    // A field is unreachable from here: at this point the cursor sits
    // immediately after the member name, so `declare x: (a: number) =>
    // void` reads `Colon` and only a method reads `LParen` / `Lt`.
    if has_declare && (self.check(LParen) || self.check(Lt)) {
      self.grammar_misuses.push(
        if method_name == "constructor" {
          "`declare` modifier cannot appear on a constructor"
        } else {
          "`declare` modifier cannot appear on a class method"
        },
      )
    }
    if method_name != "<computed>" {
      if visibility == "private" {
        private_members.push(method_name)
      } else if visibility == "protected" {
        protected_members.push(method_name)
      }
      if is_abstract_member {
        abstract_members.push(method_name)
      }
    }
    // TS4112/4113/4114 support: which members carried an `override`
    // modifier (checked against the base chain, and -- under
    // noImplicitOverride -- required on genuine overrides). Marker
    // format matches other per-class sentinels; instance and static
    // sides are distinguished.
    //
    // OUTSIDE the `!= "<computed>"` guard above, deliberately. That guard
    // is right for the three lists it wraps — accessibility and
    // abstractness are looked up BY NAME, and an opaque key has none —
    // and it was inherited by this recording, which asks a different
    // question: did a member carry `override` at all. So
    // `class B extends A { override [foo]() {} }` recorded nothing and
    // TS4113 could not fire. The checker decides what a `<computed>`
    // entry may conclude; it is deliberately narrow, because
    // `override [prop]()` IS legal when the base declares the key that
    // `prop` resolves to (`overrideLateBindableName1`).
    if saw_override_modifier {
      self.override_member_names.push(
        (if is_static { "s:" } else { "i:" }) + method_name,
      )
    }
    if has_declare {
      self.override_member_names.push(
        "<decl>" + (if is_static { "s:" } else { "i:" }) + method_name,
      )
    }
    let is_optional = self.match_(Question)
    let has_definite_assertion = self.match_(Bang)
    let mut local_type_param_bound_len = self.local_type_param_bounds.length()
    let mut method_type_param_names : Array[String] = []
    let mut method_type_param_bounds : Array[(String, @ast.TsType)] = []
    // Whether a type-parameter LIST was written, as opposed to whether it
    // produced any names: `constructor<>()` parses to zero names and is
    // still TS1092 (plus TS1098 for the empty list), so the count cannot
    // answer the question. Read by the constructor grammar checks below.
    let had_type_param_list = self.check(Lt)
    if self.check(Lt) {
      let (names, type_param_bounds) = self.parse_type_param_names_and_bounds()
      method_type_param_names = names
      method_type_param_bounds = type_param_bounds
      local_type_param_bound_len = self.push_local_type_param_bounds(
        type_param_bounds,
      )
    }
    let is_getter_without_parens = match accessor_kind {
      Some(kind) => kind == "get" && !self.check(LParen)
      None => false
    }
    if self.check(LParen) || is_getter_without_parens {
      // Push a fresh "parameter property" scope when parsing a
      // constructor — `parse_param` records `public x` / `private y`
      // names there so we can synthesize `this.x = x` afterwards.
      // Non-constructor methods leave the stack untouched (any
      // accidental modifier on a non-ctor param would be a TS
      // error the checker reports later).
      let is_constructor_method = key is Name("constructor")
      if is_constructor_method {
        self.param_property_scopes.push([])
        // TS2385: record this constructor signature's accessibility so we can
        // flag an overload set whose members don't all share one (`visibility`
        // defaults to "public" and captures private / protected modifiers).
        ctor_visibilities.push(visibility)
      }
      let params = if self.check(LParen) {
        let _ = self.expect(LParen)
        // noImplicitAny: method parameters of a heritage-free class
        // declaration have no contextual-typing source (see
        // `class_decl_no_heritage`). Accessors are exempt: a setter's
        // parameter type is inferred from the paired getter's return type
        // (`get [k]() { return "" } set [k](x) {}` types `x` as string).
        let prev_record_nia = self.record_implicit_any_params
        self.record_implicit_any_params = self.class_decl_no_heritage &&
          accessor_kind is None &&
          !(is_constructor_method && self.in_class_expr_body)
        let params = self.parse_params()
        self.record_implicit_any_params = prev_record_nia
        let _ = self.expect(RParen)
        // TS1054 / TS1049: accessors have fixed arities — a getter takes
        // no parameters, a setter exactly one (parserAccessors8/9,
        // parserMemberAccessorDeclaration13/14).
        match accessor_kind {
          Some("get") =>
            if params.length() != 0 {
              self.grammar_misuses.push(
                "a `get` accessor cannot have parameters",
              )
            }
          Some("set") =>
            if params.length() != 1 {
              self.grammar_misuses.push(
                "a `set` accessor must have exactly one parameter",
              )
            }
          _ => ()
        }
        params
      } else {
        []
      }
      let param_props : Array[(String, Bool, String)] = if is_constructor_method {
        let last = self.param_property_scopes.length() - 1
        let collected = self.param_property_scopes[last]
        let _ = self.param_property_scopes.pop()
        collected
      } else {
        []
      }
      let had_return_annotation = self.check(Colon)
      let return_type = if had_return_annotation {
        let _ = self.advance()
        self.parse_type()
      } else {
        Any
      }
      // Grammar rules that are always errors on a CONSTRUCTOR, whatever the
      // surrounding types say — decided from declaration shape alone, so
      // they carry no false-positive risk on resolvable input. Each was
      // probed against tsc rather than assumed:
      //
      //   static / async / override constructor()  TS1089
      //   constructor<T>() / constructor<>()       TS1092 (+TS1098)
      //   constructor(): T                         TS1093, for every T
      //                                            including `void`
      //
      // Accessibility modifiers are deliberately NOT in the list: tsc
      // accepts `private constructor()` (the singleton idiom),
      // `protected` and `public`. `abstract` and `readonly` are errors too
      // but under their own codes (TS1242 / TS1024) and are left alone
      // here — a check that reports the wrong rule is worse than no check.
      if is_constructor_method {
        if is_static {
          self.record_suppressible_grammar_misuse(
            "`static` modifier cannot appear on a constructor declaration",
          )
        }
        if is_async_method {
          self.record_suppressible_grammar_misuse(
            "`async` modifier cannot appear on a constructor declaration",
          )
        }
        // TS1368: "Class constructor may not be a generator."
        // `*constructor() {}` (constructorNameInGenerator). The `*` sits in
        // the same modifier position as `async`, which is already rejected
        // one line above; this is the fourth member of that list rather
        // than a new rule.
        if is_generator {
          self.record_suppressible_grammar_misuse(
            "class constructor may not be a generator",
          )
        }
        if saw_override_modifier {
          self.record_suppressible_grammar_misuse(
            "`override` modifier cannot appear on a constructor declaration",
          )
        }
        if had_type_param_list {
          self.record_suppressible_grammar_misuse(
            "type parameters cannot appear on a constructor declaration",
          )
        }
        if had_return_annotation {
          self.record_suppressible_grammar_misuse(
            "a type annotation cannot appear on a constructor declaration",
          )
        }
      }
      // TS1064 for an `async` METHOD, the second of the two spellings an
      // async callable has (`parse_function` covers the first). Recorded
      // through the same helper rather than a second copy of the denylist.
      self.record_async_return_type_misuse(
        is_async_method, is_generator, had_return_annotation, return_type,
      )
      // Accessor grammar rules, same shape of argument as the constructor
      // block above: decided from the declaration alone, each probed
      // against tsc, and each with its legal neighbour probed too so the
      // check is known not to fire on it.
      //
      //   set F(a = 1)      TS1052   vs.  set F(v)          legal
      //   set F(a?)         TS1051   vs.  set F(v: number)  legal
      //   set F(...a)       TS1053   vs.  set F(v,)         legal
      //   set F(v): number  TS1095   vs.  get F(): number   legal
      //   get/set F<T>()    TS1094
      //
      // TS1094 applies to BOTH accessor kinds; the other four are `set`
      // only, because a getter takes no parameters and its return
      // annotation is the normal way to type it.
      match accessor_kind {
        Some(kind) => {
          if had_type_param_list {
            self.record_suppressible_grammar_misuse(
              "an accessor cannot have type parameters",
            )
          }
          if kind == "set" {
            if had_return_annotation {
              self.record_suppressible_grammar_misuse(
                "a `set` accessor cannot have a return type annotation",
              )
            }
            for p in params {
              if not(p.default is None) {
                self.record_suppressible_grammar_misuse(
                  "a `set` accessor parameter cannot have an initializer",
                )
              }
              if p.is_optional {
                self.record_suppressible_grammar_misuse(
                  "a `set` accessor cannot have an optional parameter",
                )
              }
              if p.is_rest {
                self.record_suppressible_grammar_misuse(
                  "a `set` accessor cannot have a rest parameter",
                )
              }
            }
          }
        }
        None => ()
      }
      let consumed_semi = self.match_(Semicolon)
      // A real `{ ... }` body marks an *implementation* (vs. a bodyless
      // overload signature). Used below to count constructor implementations
      // for TS2392.
      let has_body_block = not(consumed_semi) && self.check(LBrace)
      // TS2371: a parameter initializer belongs to an IMPLEMENTATION, so a
      // bodiless class member cannot carry one — an overload signature
      // (`foo(a = 4);`), an `abstract` member, and a `declare class`
      // member are all the same error, which is why the test is
      // `has_body_block` and not the modifiers. The rule already existed
      // for bodiless FUNCTION declarations and for interface members and
      // had nothing here, so `class C { foo(a = 4); foo(a, b) {} }` parsed
      // clean; `record_bodiless_param_initializers` is now the one
      // recorder for both.
      if not(has_body_block) {
        self.record_bodiless_param_initializers(params)
      }
      // TS2393 ("Duplicate function implementation"): two methods of one
      // name in one class body, both with a body
      // (parserMemberFunctionDeclarationAmbiguities1, whose `public()`
      // and `public public()` are the same member spelled twice).
      // Overloads legally repeat a name, which is exactly why the test is
      // on the BODY rather than the name.
      if method_name != "<computed>" {
        let mkey = (if is_static { "s:" } else { "i:" }) +
          (match accessor_kind {
            Some(k) => k
            None => "m"
          }) +
          ":" +
          method_name
        // TS2386: "Overload signatures must all be optional or required."
        // An accessor and a `constructor` cannot carry `?` at all, so only
        // plain methods participate. Unlike the interface / object-type
        // sites, a bodied IMPLEMENTATION is recorded too, as REQUIRED —
        // that is what makes `m?(x); m?(s); m(v) { }` the error tsc
        // reports on both of its signatures.
        if accessor_kind is None && method_name != "constructor" {
          self.record_overload_optionality(
            method_sig_optional,
            mkey,
            method_name,
            is_optional && not(has_body_block),
          )
        }
        if has_body_block {
          // TS2393 ("Duplicate function implementation").
          if bodied_method_keys.get(mkey) is Some(_) {
            self.grammar_misuses.push(
              "duplicate function implementation: `" + method_name + "`",
            )
          } else {
            bodied_method_keys[mkey] = true
          }
          // TS2394: an overload signature that cannot reach its own
          // implementation. Signatures precede the implementation in
          // every legal spelling, so by the time the body arrives every
          // signature of this member has been recorded; an
          // implementation written FIRST records nothing and costs a
          // MISS rather than a wrong answer.
          if sig_max_args.get(mkey) is Some(maxes) {
            let need = impl_required_arity(params)
            for m in maxes {
              if m >= 0 && m < need {
                self.grammar_misuses.push(
                  "this overload signature is not compatible with its implementation signature: `" +
                  method_name +
                  "`",
                )
                break
              }
            }
          }
        } else {
          let m = signature_max_args(params)
          match sig_max_args.get(mkey) {
            Some(arr) => arr.push(m)
            None => sig_max_args[mkey] = [m]
          }
        }
      }
      // TS1249: a decorator can only decorate a method IMPLEMENTATION,
      // not an overload signature. A bodiless method in an ambient
      // (`declare class`) or abstract position is not an overload — it is
      // the whole declaration — and legacy decorators accept those
      // (decoratorInAmbientContext), so both are excluded. `constructor`
      // is excluded because a decorated constructor is TS1206, a
      // different rule that already fires above.
      if member_decorated &&
        not(has_body_block) &&
        not(is_abstract_member) &&
        not(has_declare) &&
        not(self.in_ambient_module) &&
        method_name != "constructor" {
        self.grammar_misuses.push(
          "a decorator can only decorate a method implementation, not an overload",
        )
      }
      // TS7010 (`noImplicitAny`): a BODILESS class member with no
      // return-type annotation implicitly returns `any` — an overload
      // signature, an `abstract` member and a `declare class` member
      // alike. The IMPLEMENTATION is exempt because it infers from its
      // body, which is the whole content of the test.
      //
      // The comment that used to sit here abstained and gave a reason
      // that is the inverse of the truth: it said "tsc does not flag an
      // overload signature whose implementation carries the return
      // annotation", and probed, `m(); m(x: number); m(x?: number): void
      // { }` reports on BOTH signatures while
      // `m(): void; m(x: number): void; m(x?: number) { }` — annotated
      // signatures, unannotated implementation — is ACCEPTED. The
      // exemption belongs to the body, not to the set.
      //
      // Accessors are excluded (a getter with no annotation is TS7033, a
      // different rule) and so is `constructor`, which has no return
      // type to annotate.
      if not(has_body_block) &&
        accessor_kind is None &&
        method_name != "constructor" {
        self.record_implicit_any_member_return(
          method_name, had_return_annotation,
        )
      }
      // TS1221 / overload-signature rule: a bodiless `*method()` is
      // always an error — generators are not allowed in ambient
      // contexts, and an overload signature cannot be a generator.
      if is_generator && !has_body_block {
        self.grammar_misuses.push(
          "a generator requires a body: `*\{method_name}` cannot be an ambient declaration or overload signature",
        )
      }
      let body = if consumed_semi {
        @ast.TsBlock::{ stmts: [], stmt_positions: [] }
      } else if !self.check(LBrace) {
        // Overload signature with no body and no trailing `;` (relying on
        // ASI) — e.g. `constructor(y: any)` followed on the next line by the
        // implementation `constructor(x: number) {}`. Treat it as a bodyless
        // signature; we don't enforce overload/implementation pairing.
        @ast.TsBlock::{ stmts: [], stmt_positions: [] }
      } else {
        // Save and set function context for method body. Assign (not
        // just set-when-true): a non-generator method of a class declared
        // inside a generator function must NOT inherit the outer
        // generator context — `yield <operand>` in its body is TS1163.
        let prev_generator = self.in_generator
        let prev_function = self.in_function
        self.in_generator = is_generator
        self.in_function = true
        let body = self.parse_block()
        self.in_generator = prev_generator
        self.in_function = prev_function
        body
      }
      self.restore_local_type_param_bounds(local_type_param_bound_len)
      // Inject `this.name = name` assigns for every parameter
      // property at the TOP of the constructor body — after `super(…)`
      // when there is one. Vanilla TS semantics. The `using` lowering
      // wraps the statements after a `using` declaration in
      // `try { … } finally { dispose }`, which can bury the `super(…)`
      // call one or more `Try` levels deep — recurse into try bodies so
      // the assigns still land right after the call instead of being
      // prepended before it (usingDeclarations.11's C4/C5).
      fn insert_after_super_in(
        p : Parser,
        stmts : Array[@ast.TsStmt],
      ) -> Array[@ast.TsStmt]? {
        let out : Array[@ast.TsStmt] = []
        let mut inserted = false
        for s in stmts {
          if inserted {
            out.push(s)
            continue
          }
          match s {
            Try(tb, cb, cbody, fb) if !p.is_super_call_stmt(s) =>
              match insert_after_super_in(p, tb.stmts) {
                Some(new_inner) => {
                  out.push(
                    Try({ stmts: new_inner, stmt_positions: [] }, cb, cbody, fb),
                  )
                  inserted = true
                }
                None => out.push(s)
              }
            _ => {
              out.push(s)
              if p.is_super_call_stmt(s) {
                for pp in param_props {
                  out.push(
                    PropAssign(
                      @ast.TsExpr::Var("this"),
                      pp.0,
                      @ast.TsExpr::Var(pp.0),
                    ),
                  )
                }
                inserted = true
              }
            }
          }
        }
        if inserted {
          Some(out)
        } else {
          None
        }
      }

      let body = if param_props.length() > 0 {
        let mut super_inserted = false
        let new_stmts : Array[@ast.TsStmt] = match
          insert_after_super_in(self, body.stmts) {
          Some(ns) => {
            super_inserted = true
            ns
          }
          None => body.stmts
        }
        if !super_inserted {
          let prepended : Array[@ast.TsStmt] = []
          for pp in param_props {
            prepended.push(
              PropAssign(@ast.TsExpr::Var("this"), pp.0, @ast.TsExpr::Var(pp.0)),
            )
          }
          for s in new_stmts {
            prepended.push(s)
          }
          @ast.TsBlock::{ stmts: prepended, stmt_positions: [] }
        } else {
          @ast.TsBlock::{ stmts: new_stmts, stmt_positions: [] }
        }
      } else {
        body
      }
      let func : @ast.TsFunc = {
        name: method_name,
        type_params: method_type_param_names,
        const_type_params: [],
        type_param_bounds: method_type_param_bounds,
        params,
        return_type,
        body,
        is_generator,
        is_async: is_async_method,
      }
      if accessor_kind is None && key is Name("constructor") && !is_static {
        if has_body_block {
          ctor_impl_count += 1
        } else {
          // TS2390 support: a BODILESS constructor is an overload
          // signature (or an ambient declaration). This counter existed
          // only for implementations, and only the `>= 2` case was ever
          // read — so `class C { constructor(); }`, a signature set with
          // no implementation at all, was silent while its mirror image
          // (two implementations, TS2392) was reported.
          ctor_sig_count += 1
        }
        ctor = Some(func)
        // Materialize TS "parameter properties" (`constructor(readonly x:
        // T)`) as real instance fields so the checker can see them — this
        // makes `new C(...).x` resolve and lets the readonly assignment
        // check (TS2540) fire. The field carries the `readonly` modifier
        // captured during param parsing; `init` is `None` since the value
        // flows in through the synthesized `this.x = x` assign (the class
        // has a constructor, so TS2564 already skips it).
        for pp in param_props {
          let (pp_name, pp_readonly, pp_visibility) = pp
          let mut pp_type : @ast.TsType = Any
          for p in func.params {
            if p.name == pp_name {
              pp_type = p.type_
              break
            }
          }
          elements.push(
            Field(false, Name(pp_name), pp_type, None, pp_readonly, false),
          )
          // A `private` / `protected` parameter property contributes the
          // same accessibility as a normal member declaration.
          if pp_visibility == "private" {
            private_members.push(pp_name)
          } else if pp_visibility == "protected" {
            protected_members.push(pp_name)
          }
        }
      } else {
        // TS1245: an `abstract` method / accessor cannot carry a body. A
        // bodyless `abstract foo();` is the valid form; a real `{ ... }` body
        // is always an error.
        if is_abstract_member && has_body_block {
          abstract_member_with_body = true
        }
        // Track bodyless overload signatures (non-accessor, non-abstract) for
        // the TS2387/2388 static/instance-mix check.
        // Optional methods (`foo?()`) may omit their body, so they are neither
        // overload signatures nor missing implementations -- skip them.
        if accessor_kind is None &&
          not(is_abstract_member) &&
          not(is_optional) &&
          method_name != "<computed>" {
          if has_body_block {
            if is_static {
              impl_static[method_name] = ()
            } else {
              impl_instance[method_name] = ()
            }
          } else if is_static {
            ov_static[method_name] = ()
          } else {
            ov_instance[method_name] = ()
          }
        }
        elements.push(Method(is_static, key, accessor_kind, func))
      }
    } else {
      self.restore_local_type_param_bounds(local_type_param_bound_len)
      let had_annotation = self.check(Colon)
      let field_type = if self.match_(Colon) {
        self.parse_type()
      } else {
        @ast.TsType::Any
      }
      let field_type = if is_optional {
        wrap_optional_ts_type(field_type)
      } else {
        field_type
      }
      let init : @ast.TsExpr? = if self.match_(Eq) {
        // A field initializer is its own function-like context: `yield
        // <operand>` inside one is TS1163 even when the class sits in a
        // generator body (class DECORATORS and computed KEYS, by
        // contrast, evaluate in the enclosing scope and stay legal).
        let prev_generator = self.in_generator
        self.in_generator = false
        let e = self.parse_assignment()
        self.in_generator = prev_generator
        Some(e)
      } else {
        None
      }
      let _ = self.match_(Semicolon)
      // TS7008 evidence: a field with NEITHER a type annotation NOR an
      // initializer has no source of a type, so under `noImplicitAny` it
      // is an implicit `any` member. Recorded here rather than decided in
      // the checker because the annotation is what distinguishes it and
      // the AST cannot: a missing annotation and an explicit `: any` are
      // both `Any`.
      //
      // Every neighbour probed: `q = 1` (an initializer infers the type)
      // and `r: number` are clean — `r` is TS2564, a different rule —
      // while a `#private` name and the STATIC side both error like a
      // plain one. An ambient class is exempt and needs no gate here,
      // because `declare class` is parsed by `parse_declare_class` and
      // never reaches this function.
      if self.no_implicit_any &&
        not(self.in_ambient_module) &&
        not(had_annotation) &&
        init is None &&
        not(has_declare) {
        // The SOURCE spelling, not the brand: `class_key_name` returns
        // the mangled `__private_brand__N__u` for a private member, and
        // a diagnostic naming that is a diagnostic nobody can act on.
        let shown = if key_is_private_name && raw_private_name != "" {
          "#" + raw_private_name
        } else {
          class_key_name(key)
        }
        // Deferred, not reported here: an assignment elsewhere in the
        // class body can supply the type, and the body has not been read
        // yet. `record_private_member_misuse` decides, after its scan.
        implicit_any_candidates.push((shown, class_key_name(key)))
      }
      // A `declare` field (`class C { declare x: T }`) is ambiently
      // typed and emits no runtime code, so TS never applies strict
      // property initialization (TS2564) to it. Fold it into the
      // definite-assignment flag, which suppresses that check.
      elements.push(
        Field(
          is_static,
          key,
          field_type,
          init,
          is_readonly_field,
          has_definite_assertion || has_declare,
        ),
      )
    }
  }
  let _ = self.expect(RBrace)
  self.record_private_member_misuse(
    body_token_start, private_method_names, private_getters, private_setters, implicit_any_candidates,
  )
  // TS1207: a name whose GETTER and SETTER are both decorated. Checked
  // here, where the whole body has been seen, and keyed on static-ness
  // because the static and instance sides are separate members.
  //
  // Two gates, and the second is a limitation rather than a rule.
  //
  // LEGACY decorators only: under STANDARD ES decorators each accessor
  // gets its own decorator application, so decorating both halves is
  // legal. Seven corpus false positives in `esDecorators/` said so, and
  // every probe written for this rule had carried
  // `@experimentalDecorators: true`, so none of them could see it — the
  // same gate direction as TS1206 for a `#private` member.
  //
  // And class DECLARATIONS only. Inside a class EXPRESSION body the
  // decorator-mode flag is not reliable: `(class E { @dec get x() {…}
  // @dec set x(v) {…} })` with NO directive fires while the identical
  // class declaration stays silent, so some parser on that path carries
  // the `true` default instead of the header-derived value. That is a
  // pre-existing inconsistency affecting every decorator-mode-gated
  // rule, not something this one should paper over, so the class
  // expression is skipped and the inconsistency is recorded in TODO.md.
  // It costs nothing here — `decoratorOnClassAccessor7` is six class
  // declarations.
  let ts1207_applies = self.experimental_decorators &&
    not(self.in_class_expr_body)
  for entry in (if ts1207_applies { decorated_accessors } else { [] }) {
    if entry.contains(":get:") {
      let counterpart = entry.replace(old=":get:", new=":set:")
      if decorated_accessors.contains(counterpart) {
        self.grammar_misuses.push(
          "decorators cannot be applied to multiple get / set accessors of the same name",
        )
      }
    }
  }
  self.in_strict = prev_strict
  let mut overload_static_mix = false
  for name in ov_instance.keys() {
    // Bodyless signatures on both sides, but NOT a full instance+static
    // implementation pair (which would be two distinct, legal overload sets).
    if ov_static.contains(name) &&
      not(impl_static.contains(name) && impl_instance.contains(name)) {
      overload_static_mix = true
      break
    }
  }
  // TS2391: a bodyless overload signature with no implementation *of any
  // kind*. Conservative (a name with any-side impl is left to the more precise
  // diagnostics), so it is false-positive-free on well-formed runtime classes.
  let mut overload_missing_impl = false
  fn check_missing(names : Map[String, Unit]) -> Bool {
    for name in names.keys() {
      if not(impl_static.contains(name)) && not(impl_instance.contains(name)) {
        return true
      }
    }
    false
  }

  if check_missing(ov_instance) || check_missing(ov_static) {
    overload_missing_impl = true
  }
  // TS2385: a constructor overload set (2+ signatures) whose members don't all
  // share one accessibility. Conservative — fires only when the visibilities
  // genuinely differ, which is never valid TS, so it is false-positive-free.
  let mut overload_accessibility_mix = false
  if ctor_visibilities.length() >= 2 {
    let first = ctor_visibilities[0]
    for v in ctor_visibilities {
      if v != first {
        overload_accessibility_mix = true
        break
      }
    }
  }
  (
    ctor, elements, private_members, protected_members, abstract_members, ctor_impl_count,
    ctor_sig_count, index_sig_modifier_misuse, abstract_member_with_body, overload_static_mix,
    overload_missing_impl, overload_accessibility_mix, modifier_order_misuse, class_body_statement_misuse,
    static_index_type_param_ref, index_naked_params,
  )
}

///|
fn Parser::parse_class_stub(self : Parser) -> @ast.TsExpr raise ParseError {
  self.last_runtime_class_decl = None
  // Same pre-capture as `parse_class_decl_with_abstract`: only decorators
  // pending BEFORE the body parse are class decorators; member decorators
  // pushed during the body parse are erased.
  let class_decorators = self.take_pending_decorators()
  let _ = self.expect(Class)
  let mut class_name = ""
  let _ = match self.peek().kind {
    Ident(n) if n != "implements" => {
      class_name = n
      self.advance()
    }
    _ => { kind: Eof, pos: 0, has_newline_before: false }
  }
  let mut class_type_params : Array[String] = []
  let mut class_type_param_bounds : Array[(String, @ast.TsType)] = []
  let mut class_type_param_bound_len = self.local_type_param_bounds.length()
  if self.check(Lt) {
    let (names, type_param_bounds) = self.parse_type_param_names_and_bounds()
    class_type_params = names
    class_type_param_bounds = type_param_bounds
    // TS2314: a named generic class expression with no defaulted type
    // parameter requires all of its type arguments on a bare reference.
    if class_name != "" &&
      names.length() > 0 &&
      not(self.last_type_params_had_default) {
      self.interface_member_modifier_misuses.push(
        "<generic-noarg-required>\{class_name}",
      )
    }
    if class_name != "" && names.length() > 0 {
      self.interface_member_modifier_misuses.push(
        "<generic-min-arity>\{class_name}=\{self.last_type_params_min_required}",
      )
    }
    class_type_param_bound_len = self.push_local_type_param_bounds(
      type_param_bounds,
    )
  }
  let mut base : String? = None
  if self.match_(Extends) {
    base = Some(self.parse_class_base_name())
    if self.check(Lt) {
      // Capture `extends B<...>` type arguments for the checker's
      // generic-base compatibility checks; fall back to the permissive
      // skip when they don't parse as simple types. Bound inlining is
      // suppressed so `extends A<T>` records the raw `T`, not its
      // constraint.
      self.no_bound_inline = true
      match self.try_parse_simple_type_args() {
        Some(targs) =>
          match base {
            Some(bname) =>
              self.class_base_type_args.push((class_name, bname, targs))
            None => ()
          }
        None => self.skip_type_args()
      }
      self.no_bound_inline = false
    }
  }
  let implements_names = if self.match_ident("implements") {
    self.parse_implements_names()
  } else {
    []
  }
  // Class-expression member typing follows tsc's split: METHOD
  // declarations are never contextually typed (a matching member on the
  // assignment target does not reach them —
  // contextuallyTypedClassExpressionMethodDeclaration01/02), so a
  // heritage-free class expression arms the same noImplicitAny recording
  // as a heritage-free declaration. FIELD initializers and constructor
  // parameters CAN be contextually typed and stay exempt (fields don't
  // run the method-param gate; constructors are excluded via
  // `in_class_expr_body`). A base class re-disarms everything — an
  // inherited member can supply the parameter types.
  let prev_no_heritage_expr = self.class_decl_no_heritage
  self.class_decl_no_heritage = base is None && implements_names.length() == 0
  let prev_in_class_expr = self.in_class_expr_body
  self.in_class_expr_body = true
  // Generate unique brand ID for private fields
  let brand_id = self.class_id
  self.class_id += 1
  let brand = "__private_brand__" + brand_id.to_string()
  let prev_brand = self.current_class_brand
  self.current_class_brand = Some(brand)
  let quoted_names_start = self.quoted_member_names.length()
  let override_names_start = self.override_member_names.length()
  let (
    ctor_opt,
    elements,
    private_members,
    protected_members,
    abstract_members,
    ctor_impl_count,
    ctor_sig_count,
    index_sig_modifier_misuse,
    abstract_member_with_body,
    overload_static_mix,
    overload_missing_impl,
    overload_accessibility_mix,
    modifier_order_misuse,
    class_body_statement_misuse,
    static_index_type_param_ref,
    index_naked_params,
  ) = self.parse_class_body(class_type_params)
  self.class_decl_no_heritage = prev_no_heritage_expr
  self.in_class_expr_body = prev_in_class_expr
  self.current_class_brand = prev_brand
  self.restore_local_type_param_bounds(class_type_param_bound_len)
  // Class *expressions* (`const C = class { … }`) build their result through
  // several branches below, none of which record the class-body structural
  // diagnostics that the declaration path surfaces via
  // `build_runtime_class_decl`'s caller. Record the flag-derived sentinels up
  // front through the shared `collected_class_dups` channel the checker reads,
  // so these always-an-error conditions (TS2392 / TS1071 / TS1245 / TS2387-8 /
  // TS2391 / TS2385 / TS1029) are flagged on class expressions too.
  let expr_class_sentinels : Array[String] = []
  // Drain this class's quoted member names (see `parse_class_method_key`).
  let quoted_names : Array[String] = []
  while self.quoted_member_names.length() > quoted_names_start {
    match self.quoted_member_names.pop() {
      Some(n) => quoted_names.push(n)
      None => ()
    }
  }
  for qn in quoted_names {
    expr_class_sentinels.push("<quoted-member:" + qn + ">")
  }
  while self.override_member_names.length() > override_names_start {
    match self.override_member_names.pop() {
      Some(n) =>
        if n.has_prefix("<decl>") {
          expr_class_sentinels.push(
            "<declare-member:" + n["<decl>".length():].to_string() + ">",
          )
        } else {
          expr_class_sentinels.push("<override-member:" + n + ">")
        }
      None => ()
    }
  }
  if ctor_impl_count >= 2 {
    expr_class_sentinels.push("<multiple-ctor-impl>")
  }
  // TS2390: constructor signatures with no implementation. An AMBIENT
  // class needs none (`declare class A { constructor(); }` is legal), but
  // an ABSTRACT one does — probed, and the opposite of what "abstract
  // members have no bodies" suggests.
  if ctor_sig_count > 0 && ctor_impl_count == 0 {
    expr_class_sentinels.push("<ctor-no-impl>")
  }
  if index_sig_modifier_misuse {
    expr_class_sentinels.push("<index-sig-modifier>")
  }
  if abstract_member_with_body {
    expr_class_sentinels.push("<abstract-impl>")
  }
  if overload_static_mix {
    expr_class_sentinels.push("<overload-static-mix>")
  }
  if overload_missing_impl {
    expr_class_sentinels.push("<overload-no-impl>")
  }
  if overload_accessibility_mix {
    expr_class_sentinels.push("<overload-accessibility-mix>")
  }
  if modifier_order_misuse {
    expr_class_sentinels.push("<modifier-order>")
  }
  if class_body_statement_misuse {
    expr_class_sentinels.push("<class-body-statement>")
  }
  if static_index_type_param_ref {
    expr_class_sentinels.push("<static-type-param-ref>")
  }
  // Not an error by itself: records that an instance index signature's
  // declared value type was a naked bounded type parameter (widened to its
  // bound in the AST), so derived-class indexer compatibility can still
  // reason about the generic slot.
  for np in index_naked_params {
    let kind = if np.0 { "num" } else { "str" }
    expr_class_sentinels.push("<index-naked-param:\{kind}:\{np.1}>")
  }
  // Marker only: every private (`#name`) member this class declares, keyed
  // by its brand id, so the checker can detect shadowed private accesses
  // (TS18014) even for classes lowered out of `module_.classes`.
  let brand_member_prefix = brand + "__"
  for element in elements {
    match element {
      Field(_, Name(n), _, _, _, _) | Method(_, Name(n), _, _) =>
        if n.has_prefix(brand_member_prefix) {
          let base = n[brand_member_prefix.length():].to_string()
          expr_class_sentinels.push("<private-decl:\{brand_id}:\{base}>")
        }
      _ => ()
    }
  }
  if expr_class_sentinels.length() > 0 {
    self.collected_class_dups.push((class_name, expr_class_sentinels))
  }
  // Self-extending classes (`class C extends C {}`) intentionally
  // throw at evaluation time per ES spec; preserve that with a
  // tiny IIFE.
  match base {
    Some(base_name) =>
      if class_name.length() > 0 && base_name == class_name {
        let throw_expr = @ast.TsExpr::Call("ReferenceError", [])
        let throw_body : @ast.TsBlock = {
          stmts: [Throw(throw_expr)],
          stmt_positions: [],
        }
        return CallExpr(
          @ast.TsExpr::FuncExpr(@ast.TsFunc::{
            type_params: [],
            type_param_bounds: [],
            name: "<class>",
            params: [],
            return_type: @ast.TsType::Any,
            body: throw_body,
            const_type_params: [],
            is_generator: false,
            is_async: false,
          }),
          [],
        )
      }
    None => ()
  }
  // Class expression with `extends Base` — produce a native
  // `class … extends … { … }` rather than the IIFE desugar (whose
  // `super(…)` calls would land outside a real class body).
  match base {
    Some(base_name) => {
      let runtime_decl = build_runtime_class_decl(
        class_name, class_type_params, class_type_param_bounds, ctor_opt, elements,
        false, private_members, protected_members, abstract_members, implements_names,
      )
      let pending_base_expr = self.pending_class_base_expr
      self.pending_class_base_expr = None
      let _ = self.take_pending_decorators()
      let decorated : @ast.TsClassDecl = {
        ..runtime_decl,
        base_names: [base_name],
        base_expr: pending_base_expr,
        decorators: class_decorators,
        is_declare: false,
      }
      self.record_runtime_class_decl(decorated)
      // Add field initializers to the constructor body so `class
      // … extends X { y = 2; constructor() {…} }` doesn't lose
      // its non-static field defaults.
      let field_assigns : Array[@ast.TsStmt] = []
      for element in elements {
        match element {
          Field(is_static, Name(field_name), _, Some(init), _, _) =>
            if !is_static {
              field_assigns.push(
                PropAssign(@ast.TsExpr::Var("this"), field_name, init),
              )
            }
          _ => ()
        }
      }
      let ctor_func : @ast.TsFunc? = match ctor_opt {
        Some(func) =>
          if field_assigns.length() > 0 {
            Some(
              self.inject_instance_field_assigns(
                func,
                field_assigns,
                Some(base_name),
              ),
            )
          } else {
            Some(func)
          }
        None =>
          if field_assigns.length() > 0 {
            let rest_name = "__super_args__"
            let body_stmts : Array[@ast.TsStmt] = [
              Expr(
                Call("super", [@ast.TsExpr::Spread(@ast.TsExpr::Var(rest_name))]),
              ),
            ]
            for a in field_assigns {
              body_stmts.push(a)
            }
            Some(@ast.TsFunc::{
              name: "constructor",
              type_params: [],
              type_param_bounds: [],
              params: [
                {
                  name: rest_name,
                  binding: Some(@ast.TsBinding::Ident(rest_name)),
                  is_rest: true,
                  is_optional: false,
                  type_: @ast.TsType::Any,
                  default: None,
                },
              ],
              return_type: @ast.TsType::Any,
              body: { stmts: body_stmts, stmt_positions: [] },
              const_type_params: [],
              is_generator: false,
              is_async: false,
            })
          } else {
            None
          }
      }
      // Static field initializers: stash them on the AST so emit
      // restores them as `static foo = init;` inside the class body
      // (ES2022 native form). Avoids wrapping the class expression
      // in an IIFE or the surrounding stmt in a `Block` — both of
      // which previously broke scope: the IIFE's `this` isn't the
      // class, and the Block trapped the class declaration itself.
      let static_field_inits : Array[(String, @ast.TsExpr)] = []
      let instance_field_inits : Array[(String, @ast.TsExpr)] = []
      for element in elements {
        match element {
          Field(true, Name(static_name), _, Some(init), _, _) =>
            static_field_inits.push((static_name, init))
          Field(false, Name(field_name), _, Some(init), _, _) =>
            if is_public_runtime_class_member_name(field_name) {
              instance_field_inits.push((field_name, init))
            }
          _ => ()
        }
      }
      let decorated_with_statics : @ast.TsClassDecl = {
        ..decorated,
        static_field_inits,
        instance_field_inits,
      }
      self.record_local_class_expr(decorated_with_statics)
      return NativeClassExpr(decorated_with_statics, ctor_func)
    }
    None => ()
  }
  // (unused) Legacy synthetic-name + IIFE path retained for context — see
  // commit history; the active path above stashes static fields on the
  // AST and lets emit restore them in-body.
  // `<anon>` was the historical sentinel for "this class expression
  // has no source-level name". The angle brackets aren't valid JS
  // identifier syntax, so the emitter rejects them and writes
  // `let <anon> = …` literally, producing invalid output. Use a
  // legal-but-reserved-looking name instead; the class-desugar IIFE
  // only references it internally, so a stable token is enough.
  let tmp_name = if class_name == "" { "_anon" } else { class_name }
  let runtime_decl = build_runtime_class_decl(
    if class_name == "" {
      "<class>"
    } else {
      class_name
    },
    class_type_params,
    class_type_param_bounds,
    ctor_opt,
    elements,
    false,
    private_members,
    protected_members,
    abstract_members,
    implements_names,
  )
  // Attach any decorators accumulated via `skip_decorator` before this
  // class statement.
  let decorated : @ast.TsClassDecl = {
    name: runtime_decl.name,
    type_params: runtime_decl.type_params,
    type_param_bounds: runtime_decl.type_param_bounds,
    computed_field_keys: runtime_decl.computed_field_keys,
    base_names: runtime_decl.base_names,
    implements_names: runtime_decl.implements_names,
    base_expr: runtime_decl.base_expr,
    static_field_inits: runtime_decl.static_field_inits,
    static_blocks: runtime_decl.static_blocks,
    instance_field_inits: runtime_decl.instance_field_inits,
    constructor_params: runtime_decl.constructor_params,
    constructor_param_is_rest: runtime_decl.constructor_param_is_rest,
    constructor_param_defaults: runtime_decl.constructor_param_defaults,
    constructor_body: runtime_decl.constructor_body,
    properties: runtime_decl.properties,
    methods: runtime_decl.methods,
    index_signatures: runtime_decl.index_signatures,
    static_index_signatures: runtime_decl.static_index_signatures,
    is_abstract: runtime_decl.is_abstract,
    is_constructible: runtime_decl.is_constructible,
    is_local: false,
    decorators: {
      let _ = self.take_pending_decorators()
      class_decorators
    },
    is_declare: false,
    private_members: runtime_decl.private_members,
    protected_members: runtime_decl.protected_members,
    abstract_members: runtime_decl.abstract_members,
    duplicate_member_names: runtime_decl.duplicate_member_names,
  }
  self.record_runtime_class_decl(decorated)
  self.record_local_class_expr(decorated)
  let instance_assigns : Array[@ast.TsStmt] = []
  let has_instance_private = has_instance_private_elements(elements)
  let has_static_private = has_static_private_elements(elements)
  // Add brand marking for instance private field access control
  if has_instance_private {
    instance_assigns.push(
      PropAssign(@ast.TsExpr::Var("this"), brand, @ast.TsExpr::BoolLit(true)),
    )
  }
  let key_temps : Array[String?] = [] // Temp var names for ALL elements' computed keys
  let key_init_stmts : Array[@ast.TsStmt] = [] // Initialization statements for computed keys
  // First pass: collect all computed keys and generate temp variables
  for element in elements {
    match element {
      Field(_, key, _, _, _, _) | Method(_, key, _, _) =>
        match key {
          Name(_) => key_temps.push(None)
          Computed(key_expr) => {
            let temp_name = "__class_key_" + self.class_key_counter.to_string()
            self.class_key_counter += 1
            key_temps.push(Some(temp_name))
            // Generate: let __class_key_N = key_expr;
            key_init_stmts.push(
              Let(@ast.TsBinding::Ident(temp_name), Any, key_expr),
            )
          }
        }
      StaticBlock(_) => key_temps.push(None) // Placeholder to keep indices aligned
      IndexSig(_, _, _) => key_temps.push(None)
    }
  }

  // Second pass: generate instance field assignments (for non-static fields)
  for idx, element in elements {
    match element {
      Field(is_static, key, _, init_opt, _, _) =>
        if !is_static {
          let init = match init_opt {
            Some(expr) => expr
            None => @ast.TsExpr::Var("undefined")
          }
          match key {
            Name(field_name) => {
              // Mangle private field names with brand for access control
              let actual_name = mangle_private_name(field_name, brand)
              instance_assigns.push(
                PropAssign(@ast.TsExpr::Var("this"), actual_name, init),
              )
            }
            Computed(_) =>
              match key_temps[idx] {
                Some(temp_name) =>
                  instance_assigns.push(
                    IndexAssign(
                      @ast.TsExpr::Var("this"),
                      @ast.TsExpr::Var(temp_name),
                      init,
                    ),
                  )
                None => ()
              }
          }
        }
      _ => ()
    }
  }
  let stmts : Array[@ast.TsStmt] = []
  // Class body is implicitly strict mode
  stmts.push(Expr(@ast.TsExpr::StringLit("use strict")))
  // Define __super_proto early for static field arrow functions to capture
  let super_proto_expr = match base {
    Some(base_name) => @ast.TsExpr::Var(base_name)
    None => @ast.TsExpr::PropAccess(@ast.TsExpr::Var("Function"), "prototype")
  }
  stmts.push(Let(@ast.TsBinding::Ident("__super_proto"), Any, super_proto_expr))
  // Add computed key initializations first (in order of appearance)
  for stmt in key_init_stmts {
    stmts.push(stmt)
  }
  let ctor_func = match ctor_opt {
    Some(func) => func
    None =>
      match base {
        Some(_) => {
          let rest_name = "__super_args__"
          let rest_param : @ast.TsParam = {
            name: rest_name,
            binding: Some(@ast.TsBinding::Ident(rest_name)),
            is_rest: true,
            is_optional: false,
            type_: Any,
            default: None,
          }
          let empty_body : @ast.TsBlock = {
            stmts: [Expr(Call("super", [@ast.TsExpr::Var(rest_name)]))],
            stmt_positions: [],
          }
          {
            name: tmp_name,
            type_params: [],
            type_param_bounds: [],
            params: [rest_param],
            return_type: Any,
            body: empty_body,
            const_type_params: [],
            is_generator: false,
            is_async: false,
          }
        }
        None => {
          let empty_body : @ast.TsBlock = { stmts: [], stmt_positions: [] }
          {
            name: tmp_name,
            type_params: [],
            type_param_bounds: [],
            params: [],
            return_type: Any,
            body: empty_body,
            const_type_params: [],
            is_generator: false,
            is_async: false,
          }
        }
      }
  }
  let ctor_func = self.inject_instance_field_assigns(
    ctor_func, instance_assigns, base,
  )
  stmts.push(
    Let(@ast.TsBinding::Ident(tmp_name), Any, @ast.TsExpr::FuncExpr(ctor_func)),
  )
  // Add brand to class constructor for static private members
  if has_static_private {
    stmts.push(
      PropAssign(@ast.TsExpr::Var(tmp_name), brand, @ast.TsExpr::BoolLit(true)),
    )
  }
  let proto_expr = @ast.TsExpr::PropAccess(
    @ast.TsExpr::Var(tmp_name),
    "prototype",
  )
  match base {
    Some(base_name) => {
      let base_proto = @ast.TsExpr::PropAccess(
        @ast.TsExpr::Var(base_name),
        "prototype",
      )
      stmts.push(
        PropAssign(
          @ast.TsExpr::Var(tmp_name),
          "__super_ctor",
          @ast.TsExpr::Var(base_name),
        ),
      )
      stmts.push(
        PropAssign(@ast.TsExpr::Var(tmp_name), "__super_proto", base_proto),
      )
      stmts.push(
        PropAssign(
          @ast.TsExpr::Var(tmp_name),
          "__proto__",
          @ast.TsExpr::Var(base_name),
        ),
      )
      stmts.push(PropAssign(proto_expr, "__proto__", base_proto))
    }
    None => {
      // Even without extends, super.xxx in constructor refers to Object.prototype
      let object_proto = @ast.TsExpr::PropAccess(
        @ast.TsExpr::Var("Object"),
        "prototype",
      )
      stmts.push(
        PropAssign(@ast.TsExpr::Var(tmp_name), "__super_proto", object_proto),
      )
    }
  }
  for idx, element in elements {
    match element {
      Method(is_static, key, accessor_kind, func) => {
        let target = if is_static {
          @ast.TsExpr::Var(tmp_name)
        } else {
          proto_expr
        }
        let func_expr = @ast.TsExpr::FuncExpr(func)
        match key {
          Name(method_name) =>
            match accessor_kind {
              Some(kind) => {
                let prop_key = if kind == "get" {
                  "@@get:" + method_name
                } else {
                  "@@set:" + method_name
                }
                // For getter/setter with super, set __super_proto on the function
                let super_proto = if is_static {
                  // Static: super refers to parent class (or Function.prototype)
                  match base {
                    Some(base_name) => @ast.TsExpr::Var(base_name)
                    None =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var("Function"),
                        "prototype",
                      )
                  }
                } else {
                  // Instance: super refers to parent.prototype (or Object.prototype)
                  match base {
                    Some(base_name) =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var(base_name),
                        "prototype",
                      )
                    None =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var("Object"),
                        "prototype",
                      )
                  }
                }
                let accessor_tmp = "__" + kind + "_" + method_name
                stmts.push(
                  Let(@ast.TsBinding::Ident(accessor_tmp), Any, func_expr),
                )
                stmts.push(
                  PropAssign(
                    @ast.TsExpr::Var(accessor_tmp),
                    "__super_proto",
                    super_proto,
                  ),
                )
                stmts.push(
                  PropAssign(target, prop_key, @ast.TsExpr::Var(accessor_tmp)),
                )
              }
              None => {
                // The `@@define:` prefix the desugar used to attach
                // here was unused downstream — neither the checker
                // nor any transform actually inspects it, and the
                // emit-time stripper was a no-op once mangling
                // renamed the prefixed name. Use the raw method
                // name so property-mangling treats it like every
                // other prop and stays consistent across the
                // `prototype.method = …` assignment and any later
                // `prototype.method.something = …` chain.
                let prop_key = method_name
                // Set __super_proto for both instance and static methods
                let super_proto = if is_static {
                  // Static: super refers to parent class (or Function.prototype)
                  match base {
                    Some(base_name) => @ast.TsExpr::Var(base_name)
                    None =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var("Function"),
                        "prototype",
                      )
                  }
                } else {
                  // Instance: super refers to parent.prototype (or Object.prototype)
                  match base {
                    Some(base_name) =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var(base_name),
                        "prototype",
                      )
                    None =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var("Object"),
                        "prototype",
                      )
                  }
                }
                // For private methods, use temp var pattern to avoid brand check issues
                if method_name.contains("__#") {
                  let method_tmp = "__method_" + method_name
                  stmts.push(
                    Let(@ast.TsBinding::Ident(method_tmp), Any, func_expr),
                  )
                  stmts.push(
                    PropAssign(
                      @ast.TsExpr::Var(method_tmp),
                      "__super_proto",
                      super_proto,
                    ),
                  )
                  stmts.push(
                    PropAssign(target, prop_key, @ast.TsExpr::Var(method_tmp)),
                  )
                } else {
                  stmts.push(PropAssign(target, prop_key, func_expr))
                  let method_ref = @ast.TsExpr::PropAccess(target, method_name)
                  stmts.push(
                    PropAssign(method_ref, "__super_proto", super_proto),
                  )
                }
              }
            }
          Computed(_) => {
            // Use the pre-evaluated temp variable for the computed key
            let key_expr = match key_temps[idx] {
              Some(temp_name) => @ast.TsExpr::Var(temp_name)
              None => class_key_expr(key) // Fallback
            }
            let desc = match accessor_kind {
              Some(kind) => {
                let prop_key = if kind == "get" { "get" } else { "set" }
                @ast.TsExpr::ObjectLit([
                  (prop_key, func_expr),
                  ("enumerable", @ast.TsExpr::BoolLit(false)),
                  ("configurable", @ast.TsExpr::BoolLit(true)),
                ])
              }
              None =>
                @ast.TsExpr::ObjectLit([
                  ("value", func_expr),
                  ("writable", @ast.TsExpr::BoolLit(true)),
                  ("enumerable", @ast.TsExpr::BoolLit(false)),
                  ("configurable", @ast.TsExpr::BoolLit(true)),
                ])
            }
            let define_call = @ast.TsExpr::CallExpr(
              @ast.TsExpr::PropAccess(
                @ast.TsExpr::Var("Object"),
                "defineProperty",
              ),
              [target, key_expr, desc],
            )
            stmts.push(Expr(define_call))
          }
        }
      }
      Field(is_static, key, _, init_opt, _, _) => {
        let init = match init_opt {
          Some(expr) => expr
          None => @ast.TsExpr::Var("undefined")
        }
        if is_static {
          match key {
            Name(field_name) =>
              stmts.push(
                PropAssign(@ast.TsExpr::Var(tmp_name), field_name, init),
              )
            Computed(_) => {
              // Use the pre-evaluated temp variable for the computed key
              let key_expr = match key_temps[idx] {
                Some(temp_name) => @ast.TsExpr::Var(temp_name)
                None => class_key_expr(key) // Fallback
              }
              let desc = @ast.TsExpr::ObjectLit([
                ("value", init),
                ("writable", @ast.TsExpr::BoolLit(true)),
                ("enumerable", @ast.TsExpr::BoolLit(true)),
                ("configurable", @ast.TsExpr::BoolLit(true)),
              ])
              let define_call = @ast.TsExpr::CallExpr(
                @ast.TsExpr::PropAccess(
                  @ast.TsExpr::Var("Object"),
                  "defineProperty",
                ),
                [@ast.TsExpr::Var(tmp_name), key_expr, desc],
              )
              stmts.push(Expr(define_call))
            }
          }
        }
        // Note: non-static computed field keys are already handled in instance_assigns
      }
      StaticBlock(block) => {
        // Static initialization blocks run during class definition with `this` bound to the class
        // Generate: (function() { ...block... }).call(ClassName)
        let static_block_func = @ast.TsExpr::FuncExpr(@ast.TsFunc::{
          type_params: [],
          type_param_bounds: [],
          name: "",
          params: [],
          return_type: @ast.TsType::Any,
          body: block,
          const_type_params: [],
          is_generator: false,
          is_async: false,
        })
        let call_method = @ast.TsExpr::PropAccess(static_block_func, "call")
        let call_expr = @ast.TsExpr::CallExpr(call_method, [
          @ast.TsExpr::Var(tmp_name),
        ])
        stmts.push(Expr(call_expr))
      }
      IndexSig(_, _, _) => ()
    }
  }
  stmts.push(Return(Some(@ast.TsExpr::Var(tmp_name))))
  CallExpr(
    @ast.TsExpr::FuncExpr(@ast.TsFunc::{
      type_params: [],
      type_param_bounds: [],
      name: "<class>",
      params: [],
      return_type: @ast.TsType::Any,
      body: @ast.TsBlock::{ stmts, stmt_positions: [] },
      const_type_params: [],
      is_generator: false,
      is_async: false,
    }),
    [],
  )
}

///|
fn Parser::parse_class_decl_with_abstract(
  self : Parser,
  is_abstract : Bool,
) -> @ast.TsStmt raise ParseError {
  self.last_runtime_class_decl = None
  // Capture CLASS-declaration decorators before the body parse: member
  // decorators accumulate into the same `pending_decorators` (they're
  // erased, not modeled) and must not masquerade as class decorators
  // (decoratorOnClassAccessor1 — an accessor decorator's 3-parameter
  // signature is legal, a class decorator's is not).
  let class_decorators = self.take_pending_decorators()
  let _ = self.expect(Class)
  // A class named with a predefined-type keyword (`class void {}`,
  // `class string {}`, …) is always a TS error (TS1005 / TS2414). These
  // keywords tokenize as dedicated `*Type` kinds rather than `Ident`, so
  // capture their spelling here — otherwise the name is lost to the
  // `<class>` recovery fallback and the reserved-name check can't see it.
  let name = match self.advance().kind {
    Ident(n) => n
    VoidType => "void"
    StringType => "string"
    NumberType => "number"
    BooleanType => "boolean"
    _ => "<class>"
  }
  let mut class_type_params : Array[String] = []
  let mut class_type_param_bounds : Array[(String, @ast.TsType)] = []
  let mut class_type_param_bound_len = self.local_type_param_bounds.length()
  if self.check(Lt) {
    let (names, type_param_bounds) = self.parse_type_param_names_and_bounds()
    class_type_params = names
    class_type_param_bounds = type_param_bounds
    // TS2314: a generic class with no defaulted type parameter requires all of
    // its type arguments; a bare `C` reference is an error. Read the flag now,
    // before the base / body parse clobbers it via a nested generic.
    if name != "" &&
      name != "<class>" &&
      names.length() > 0 &&
      not(self.last_type_params_had_default) {
      self.interface_member_modifier_misuses.push(
        "<generic-noarg-required>\{name}",
      )
    }
    if name != "" && name != "<class>" && names.length() > 0 {
      self.interface_member_modifier_misuses.push(
        "<generic-min-arity>\{name}=\{self.last_type_params_min_required}",
      )
    }
    class_type_param_bound_len = self.push_local_type_param_bounds(
      type_param_bounds,
    )
  }
  let mut base : String? = None
  if self.match_(Extends) {
    base = Some(self.parse_class_base_name())
    if self.check(Lt) {
      // Capture `extends B<...>` type arguments for the checker's
      // generic-base compatibility checks; fall back to the permissive
      // skip when they don't parse as simple types. Bound inlining is
      // suppressed so `extends A<T>` records the raw `T`, not its
      // constraint.
      self.no_bound_inline = true
      match self.try_parse_simple_type_args() {
        Some(targs) =>
          match base {
            Some(bname) => self.class_base_type_args.push((name, bname, targs))
            None => ()
          }
        None => self.skip_type_args()
      }
      self.no_bound_inline = false
    }
  }
  let implements_names = if self.match_ident("implements") {
    self.parse_implements_names()
  } else {
    []
  }
  // Arm noImplicitAny member recording only for a heritage-free class
  // *declaration*: no `extends` / `implements` means no contextual-typing
  // source for method parameters or bodiless returns.
  let prev_no_heritage = self.class_decl_no_heritage
  self.class_decl_no_heritage = base is None && implements_names.length() == 0
  // Generate unique brand ID for private fields
  let brand_id = self.class_id
  self.class_id += 1
  let brand = "__private_brand__" + brand_id.to_string()
  let prev_brand = self.current_class_brand
  self.current_class_brand = Some(brand)
  let quoted_names_start = self.quoted_member_names.length()
  let override_names_start = self.override_member_names.length()
  let (
    ctor_opt,
    elements,
    private_members,
    protected_members,
    abstract_members,
    ctor_impl_count,
    ctor_sig_count,
    index_sig_modifier_misuse,
    abstract_member_with_body,
    overload_static_mix,
    overload_missing_impl,
    overload_accessibility_mix,
    modifier_order_misuse,
    class_body_statement_misuse,
    static_index_type_param_ref,
    index_naked_params,
  ) = self.parse_class_body(class_type_params)
  self.class_decl_no_heritage = prev_no_heritage
  self.current_class_brand = prev_brand
  self.restore_local_type_param_bounds(class_type_param_bound_len)
  let runtime_decl = build_runtime_class_decl(
    name, class_type_params, class_type_param_bounds, ctor_opt, elements, is_abstract,
    private_members, protected_members, abstract_members, implements_names,
  )
  // TS2392: two or more constructor implementations. Recorded via the class's
  // duplicate-member channel with a sentinel name so the checker can surface
  // the dedicated diagnostic. A single implementation (with any number of
  // bodyless overload signatures) is legal and leaves the count at 1.
  while self.quoted_member_names.length() > quoted_names_start {
    match self.quoted_member_names.pop() {
      Some(n) =>
        runtime_decl.duplicate_member_names.push("<quoted-member:" + n + ">")
      None => ()
    }
  }
  while self.override_member_names.length() > override_names_start {
    match self.override_member_names.pop() {
      Some(n) =>
        if n.has_prefix("<decl>") {
          runtime_decl.duplicate_member_names.push(
            "<declare-member:" + n["<decl>".length():].to_string() + ">",
          )
        } else {
          runtime_decl.duplicate_member_names.push(
            "<override-member:" + n + ">",
          )
        }
      None => ()
    }
  }
  if ctor_sig_count > 0 && ctor_impl_count == 0 {
    runtime_decl.duplicate_member_names.push("<ctor-no-impl>")
  }
  if ctor_impl_count >= 2 {
    runtime_decl.duplicate_member_names.push("<multiple-ctor-impl>")
  }
  // TS1071: an accessibility modifier on an index signature. Same sentinel
  // channel; always an error, so false-positive-free.
  if index_sig_modifier_misuse {
    runtime_decl.duplicate_member_names.push("<index-sig-modifier>")
  }
  // TS1245: an `abstract` method with a body. Same sentinel channel.
  if abstract_member_with_body {
    runtime_decl.duplicate_member_names.push("<abstract-impl>")
  }
  // TS2387/2388: bodyless overload signatures mixing static and instance.
  if overload_static_mix {
    runtime_decl.duplicate_member_names.push("<overload-static-mix>")
  }
  // TS2391: a bodyless overload signature with no implementation.
  if overload_missing_impl {
    runtime_decl.duplicate_member_names.push("<overload-no-impl>")
  }
  // TS2385: constructor overload signatures with inconsistent accessibility.
  if overload_accessibility_mix {
    runtime_decl.duplicate_member_names.push("<overload-accessibility-mix>")
  }
  // TS1029: a member wrote `async` before `static`.
  if modifier_order_misuse {
    runtime_decl.duplicate_member_names.push("<modifier-order>")
  }
  // TS1128: a statement (`var x = 1` / `function foo() {}`) in a class body.
  if class_body_statement_misuse {
    runtime_decl.duplicate_member_names.push("<class-body-statement>")
  }
  // TS2302: a static index signature references a class type parameter.
  if static_index_type_param_ref {
    runtime_decl.duplicate_member_names.push("<static-type-param-ref>")
  }
  // Marker only (see the expression-class path above).
  for np in index_naked_params {
    let kind = if np.0 { "num" } else { "str" }
    runtime_decl.duplicate_member_names.push(
      "<index-naked-param:\{kind}:\{np.1}>",
    )
  }
  let brand_member_prefix = brand + "__"
  for element in elements {
    match element {
      Field(_, Name(n), _, _, _, _) | Method(_, Name(n), _, _) =>
        if n.has_prefix(brand_member_prefix) {
          let base = n[brand_member_prefix.length():].to_string()
          runtime_decl.duplicate_member_names.push(
            "<private-decl:\{brand_id}:\{base}>",
          )
        }
      _ => ()
    }
  }
  // Surface the class's structural diagnostics for *every* class, including
  // ones nested in function bodies that the IIFE lowering removes from
  // `module_.classes`. The top-level collector also records these, so the
  // checker dedups by (class, name) to avoid a double report.
  if runtime_decl.duplicate_member_names.length() > 0 {
    self.collected_class_dups.push(
      (runtime_decl.name, runtime_decl.duplicate_member_names),
    )
  }
  // Attach the class-declaration decorators captured before the body
  // parse (the checker's TS1238 decorator-signature rules read
  // `decl.decorators`), and drain any MEMBER decorators the body parse
  // pushed so they don't leak onto the next declaration.
  let _ = self.take_pending_decorators()
  let runtime_decl : @ast.TsClassDecl = {
    ..runtime_decl,
    decorators: class_decorators,
  }
  self.record_runtime_class_decl(runtime_decl)
  // When the class extends another class, the IIFE desugar below
  // produces a `super(…)` call outside a real class body — V8
  // rejects that as a SyntaxError. Bypass the desugar and emit
  // native `class … extends … { … }` instead. Modern engines
  // (Node 12+, ES2015 spec) handle the syntax directly; the IIFE
  // path is only retained for non-extending classes that still
  // round-trip through the original lowering.
  match base {
    Some(base_name) => {
      // Build per-field `this.x = init` assigns for non-static
      // fields with default values; this mirrors what the IIFE
      // path does via `instance_assigns`, but we splice them into
      // the constructor body directly so the class body looks
      // like idiomatic ES2022 syntax.
      let field_assigns : Array[@ast.TsStmt] = []
      for element in elements {
        match element {
          Field(is_static, Name(field_name), _, Some(init), _, _) =>
            if !is_static {
              field_assigns.push(
                PropAssign(@ast.TsExpr::Var("this"), field_name, init),
              )
            }
          _ => ()
        }
      }
      // Inject field assigns AFTER the super() call (or at the
      // start when there's no constructor). `inject_instance_field_assigns`
      // already handles the super-call-aware ordering.
      let merged_ctor = match ctor_opt {
        Some(func) =>
          if field_assigns.length() > 0 {
            self.inject_instance_field_assigns(
              func,
              field_assigns,
              Some(base_name),
            )
          } else {
            func
          }
        None =>
          if field_assigns.length() > 0 {
            // Synthesize a constructor body that forwards `...args`
            // to `super(...)` and then runs the field assigns.
            let rest_name = "__super_args__"
            let body_stmts : Array[@ast.TsStmt] = [
              Expr(
                Call("super", [@ast.TsExpr::Spread(@ast.TsExpr::Var(rest_name))]),
              ),
            ]
            for a in field_assigns {
              body_stmts.push(a)
            }
            @ast.TsFunc::{
              name: "constructor",
              type_params: [],
              type_param_bounds: [],
              params: [
                {
                  name: rest_name,
                  binding: Some(@ast.TsBinding::Ident(rest_name)),
                  is_rest: true,
                  is_optional: false,
                  type_: @ast.TsType::Any,
                  default: None,
                },
              ],
              return_type: @ast.TsType::Any,
              body: { stmts: body_stmts, stmt_positions: [] },
              const_type_params: [],
              is_generator: false,
              is_async: false,
            }
          } else {
            // No fields and no constructor — emit class with no
            // constructor; the default does the right thing
            // (`constructor(...args) { super(...args); }`).
            @ast.TsFunc::{
              name: "",
              type_params: [],
              type_param_bounds: [],
              params: [],
              return_type: @ast.TsType::Any,
              body: { stmts: [], stmt_positions: [] },
              const_type_params: [],
              is_generator: false,
              is_async: false,
            }
          }
      }
      let ctor_func : @ast.TsFunc? = if ctor_opt is None &&
        field_assigns.length() == 0 {
        None
      } else {
        Some(merged_ctor)
      }
      let pending_base_expr2 = self.pending_class_base_expr
      self.pending_class_base_expr = None
      let decorated : @ast.TsClassDecl = {
        ..runtime_decl,
        base_names: [base_name],
        base_expr: pending_base_expr2,
        is_declare: false,
      }
      // Static field initializers: stash them on the AST so the
      // emit pass restores them as `static foo = init;` inside the
      // class body. ES2022 classes accept the native form directly,
      // which keeps the class declaration at top-level (a wrapping
      // `Block` would trap the binding in block scope and break
      // forward references from sibling top-level code).
      let static_field_inits : Array[(String, @ast.TsExpr)] = []
      let instance_field_inits : Array[(String, @ast.TsExpr)] = []
      for element in elements {
        match element {
          Field(true, Name(static_name), _, Some(init), _, _) =>
            static_field_inits.push((static_name, init))
          Field(false, Name(field_name), _, Some(init), _, _) =>
            if is_public_runtime_class_member_name(field_name) {
              instance_field_inits.push((field_name, init))
            }
          _ => ()
        }
      }
      let decorated_with_statics : @ast.TsClassDecl = {
        ..decorated,
        static_field_inits,
        instance_field_inits,
      }
      // Re-publish the fully-built decl (with `base_names` / `base_expr` /
      // statics) so `take_last_runtime_class_decl` — used by the module
      // collector — sees the heritage clause. The earlier assignment at the
      // top of this function recorded only the base-less `runtime_decl`.
      self.record_runtime_class_decl(decorated_with_statics)
      return NativeClassStmt(decorated_with_statics, ctor_func)
    }
    None => ()
  }
  let instance_assigns : Array[@ast.TsStmt] = []
  let has_instance_private = has_instance_private_elements(elements)
  let has_static_private = has_static_private_elements(elements)
  // Add brand marking for instance private field access control
  if has_instance_private {
    instance_assigns.push(
      PropAssign(@ast.TsExpr::Var("this"), brand, @ast.TsExpr::BoolLit(true)),
    )
  }
  let key_temps : Array[String?] = [] // Temp var names for ALL elements' computed keys
  let key_init_stmts : Array[@ast.TsStmt] = [] // Initialization statements for computed keys
  // First pass: collect all computed keys and generate temp variables
  for element in elements {
    match element {
      Field(_, key, _, _, _, _) | Method(_, key, _, _) =>
        match key {
          Name(_) => key_temps.push(None)
          Computed(key_expr) => {
            let temp_name = "__class_key_" + self.class_key_counter.to_string()
            self.class_key_counter += 1
            key_temps.push(Some(temp_name))
            // Generate: let __class_key_N = key_expr;
            key_init_stmts.push(
              Let(@ast.TsBinding::Ident(temp_name), Any, key_expr),
            )
          }
        }
      StaticBlock(_) => key_temps.push(None) // Placeholder to keep indices aligned
      IndexSig(_, _, _) => key_temps.push(None)
    }
  }

  // Second pass: generate instance field assignments (for non-static fields)
  for idx, element in elements {
    match element {
      Field(is_static, key, _, init_opt, _, _) =>
        if !is_static {
          let init = match init_opt {
            Some(expr) => expr
            None => @ast.TsExpr::Var("undefined")
          }
          match key {
            Name(field_name) => {
              // Mangle private field names with brand for access control
              let actual_name = mangle_private_name(field_name, brand)
              instance_assigns.push(
                PropAssign(@ast.TsExpr::Var("this"), actual_name, init),
              )
            }
            Computed(_) =>
              match key_temps[idx] {
                Some(temp_name) =>
                  instance_assigns.push(
                    IndexAssign(
                      @ast.TsExpr::Var("this"),
                      @ast.TsExpr::Var(temp_name),
                      init,
                    ),
                  )
                None => ()
              }
          }
        }
      _ => ()
    }
  }
  let stmts : Array[@ast.TsStmt] = []
  // Class body is implicitly strict mode
  stmts.push(Expr(@ast.TsExpr::StringLit("use strict")))
  // Define __super_proto early for static field arrow functions to capture
  let super_proto_expr = match base {
    Some(base_name) => @ast.TsExpr::Var(base_name)
    None => @ast.TsExpr::PropAccess(@ast.TsExpr::Var("Function"), "prototype")
  }
  stmts.push(Let(@ast.TsBinding::Ident("__super_proto"), Any, super_proto_expr))
  // Add computed key initializations first (in order of appearance)
  for stmt in key_init_stmts {
    stmts.push(stmt)
  }
  match base {
    Some(base_name) =>
      if base_name == name {
        return Throw(@ast.TsExpr::Call("ReferenceError", []))
      }
    None => ()
  }
  let ctor_func = match ctor_opt {
    Some(func) => func
    None =>
      match base {
        Some(_) => {
          let rest_name = "__super_args__"
          let rest_param : @ast.TsParam = {
            name: rest_name,
            binding: Some(@ast.TsBinding::Ident(rest_name)),
            is_rest: true,
            is_optional: false,
            type_: Any,
            default: None,
          }
          let empty_body : @ast.TsBlock = {
            stmts: [Expr(Call("super", [@ast.TsExpr::Var(rest_name)]))],
            stmt_positions: [],
          }
          {
            name,
            type_params: [],
            type_param_bounds: [],
            params: [rest_param],
            return_type: Any,
            body: empty_body,
            const_type_params: [],
            is_generator: false,
            is_async: false,
          }
        }
        None => {
          let empty_body : @ast.TsBlock = { stmts: [], stmt_positions: [] }
          {
            name,
            type_params: [],
            type_param_bounds: [],
            params: [],
            return_type: Any,
            body: empty_body,
            const_type_params: [],
            is_generator: false,
            is_async: false,
          }
        }
      }
  }
  let ctor_func = self.inject_instance_field_assigns(
    ctor_func, instance_assigns, base,
  )
  stmts.push(
    Let(@ast.TsBinding::Ident(name), Any, @ast.TsExpr::FuncExpr(ctor_func)),
  )
  // Add brand to class constructor for static private members
  if has_static_private {
    stmts.push(
      PropAssign(@ast.TsExpr::Var(name), brand, @ast.TsExpr::BoolLit(true)),
    )
  }
  let proto_expr = @ast.TsExpr::PropAccess(@ast.TsExpr::Var(name), "prototype")
  match base {
    Some(base_name) => {
      let base_proto = @ast.TsExpr::PropAccess(
        @ast.TsExpr::Var(base_name),
        "prototype",
      )
      stmts.push(
        PropAssign(
          @ast.TsExpr::Var(name),
          "__super_ctor",
          @ast.TsExpr::Var(base_name),
        ),
      )
      stmts.push(
        PropAssign(@ast.TsExpr::Var(name), "__super_proto", base_proto),
      )
      stmts.push(
        PropAssign(
          @ast.TsExpr::Var(name),
          "__proto__",
          @ast.TsExpr::Var(base_name),
        ),
      )
      stmts.push(PropAssign(proto_expr, "__proto__", base_proto))
    }
    None => {
      // Even without extends, super.xxx in constructor refers to Object.prototype
      let object_proto = @ast.TsExpr::PropAccess(
        @ast.TsExpr::Var("Object"),
        "prototype",
      )
      stmts.push(
        PropAssign(@ast.TsExpr::Var(name), "__super_proto", object_proto),
      )
    }
  }
  for idx, element in elements {
    match element {
      Method(is_static, key, accessor_kind, func) => {
        let target = if is_static { @ast.TsExpr::Var(name) } else { proto_expr }
        let func_expr = @ast.TsExpr::FuncExpr(func)
        match key {
          Name(method_name) =>
            match accessor_kind {
              Some(kind) => {
                let prop_key = if kind == "get" {
                  "@@get:" + method_name
                } else {
                  "@@set:" + method_name
                }
                // For getter/setter with super, set __super_proto on the function
                let super_proto = if is_static {
                  // Static: super refers to parent class (or Function.prototype)
                  match base {
                    Some(base_name) => @ast.TsExpr::Var(base_name)
                    None =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var("Function"),
                        "prototype",
                      )
                  }
                } else {
                  // Instance: super refers to parent.prototype (or Object.prototype)
                  match base {
                    Some(base_name) =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var(base_name),
                        "prototype",
                      )
                    None =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var("Object"),
                        "prototype",
                      )
                  }
                }
                let accessor_tmp = "__" + kind + "_" + method_name
                stmts.push(
                  Let(@ast.TsBinding::Ident(accessor_tmp), Any, func_expr),
                )
                stmts.push(
                  PropAssign(
                    @ast.TsExpr::Var(accessor_tmp),
                    "__super_proto",
                    super_proto,
                  ),
                )
                stmts.push(
                  PropAssign(target, prop_key, @ast.TsExpr::Var(accessor_tmp)),
                )
              }
              None => {
                // The `@@define:` prefix the desugar used to attach
                // here was unused downstream — neither the checker
                // nor any transform actually inspects it, and the
                // emit-time stripper was a no-op once mangling
                // renamed the prefixed name. Use the raw method
                // name so property-mangling treats it like every
                // other prop and stays consistent across the
                // `prototype.method = …` assignment and any later
                // `prototype.method.something = …` chain.
                let prop_key = method_name
                // Set __super_proto for both instance and static methods
                let super_proto = if is_static {
                  // Static: super refers to parent class (or Function.prototype)
                  match base {
                    Some(base_name) => @ast.TsExpr::Var(base_name)
                    None =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var("Function"),
                        "prototype",
                      )
                  }
                } else {
                  // Instance: super refers to parent.prototype (or Object.prototype)
                  match base {
                    Some(base_name) =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var(base_name),
                        "prototype",
                      )
                    None =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var("Object"),
                        "prototype",
                      )
                  }
                }
                // For private methods, use temp var pattern to avoid brand check issues
                if method_name.contains("__#") {
                  let method_tmp = "__method_" + method_name
                  stmts.push(
                    Let(@ast.TsBinding::Ident(method_tmp), Any, func_expr),
                  )
                  stmts.push(
                    PropAssign(
                      @ast.TsExpr::Var(method_tmp),
                      "__super_proto",
                      super_proto,
                    ),
                  )
                  stmts.push(
                    PropAssign(target, prop_key, @ast.TsExpr::Var(method_tmp)),
                  )
                } else {
                  stmts.push(PropAssign(target, prop_key, func_expr))
                  let method_ref = @ast.TsExpr::PropAccess(target, method_name)
                  stmts.push(
                    PropAssign(method_ref, "__super_proto", super_proto),
                  )
                }
              }
            }
          Computed(_) => {
            // Use the pre-evaluated temp variable for the computed key
            let key_expr = match key_temps[idx] {
              Some(temp_name) => @ast.TsExpr::Var(temp_name)
              None => class_key_expr(key) // Fallback
            }
            let desc = match accessor_kind {
              Some(kind) => {
                let prop_key = if kind == "get" { "get" } else { "set" }
                @ast.TsExpr::ObjectLit([
                  (prop_key, func_expr),
                  ("enumerable", @ast.TsExpr::BoolLit(false)),
                  ("configurable", @ast.TsExpr::BoolLit(true)),
                ])
              }
              None =>
                @ast.TsExpr::ObjectLit([
                  ("value", func_expr),
                  ("writable", @ast.TsExpr::BoolLit(true)),
                  ("enumerable", @ast.TsExpr::BoolLit(false)),
                  ("configurable", @ast.TsExpr::BoolLit(true)),
                ])
            }
            let define_call = @ast.TsExpr::CallExpr(
              @ast.TsExpr::PropAccess(
                @ast.TsExpr::Var("Object"),
                "defineProperty",
              ),
              [target, key_expr, desc],
            )
            stmts.push(Expr(define_call))
          }
        }
      }
      Field(is_static, key, _, init_opt, _, _) => {
        let init = match init_opt {
          Some(expr) => expr
          None => @ast.TsExpr::Var("undefined")
        }
        if is_static {
          match key {
            Name(field_name) =>
              stmts.push(PropAssign(@ast.TsExpr::Var(name), field_name, init))
            Computed(_) => {
              // Use the pre-evaluated temp variable for the computed key
              let key_expr = match key_temps[idx] {
                Some(temp_name) => @ast.TsExpr::Var(temp_name)
                None => class_key_expr(key) // Fallback
              }
              let desc = @ast.TsExpr::ObjectLit([
                ("value", init),
                ("writable", @ast.TsExpr::BoolLit(true)),
                ("enumerable", @ast.TsExpr::BoolLit(true)),
                ("configurable", @ast.TsExpr::BoolLit(true)),
              ])
              let define_call = @ast.TsExpr::CallExpr(
                @ast.TsExpr::PropAccess(
                  @ast.TsExpr::Var("Object"),
                  "defineProperty",
                ),
                [@ast.TsExpr::Var(name), key_expr, desc],
              )
              stmts.push(Expr(define_call))
            }
          }
        }
        // Note: non-static computed field keys are already handled in instance_assigns
      }
      StaticBlock(block) => {
        // Static initialization blocks run during class definition with `this` bound to the class
        // Generate: (function() { ...block... }).call(ClassName)
        let static_block_func = @ast.TsExpr::FuncExpr(@ast.TsFunc::{
          type_params: [],
          type_param_bounds: [],
          name: "",
          params: [],
          return_type: @ast.TsType::Any,
          body: block,
          const_type_params: [],
          is_generator: false,
          is_async: false,
        })
        let call_method = @ast.TsExpr::PropAccess(static_block_func, "call")
        let call_expr = @ast.TsExpr::CallExpr(call_method, [
          @ast.TsExpr::Var(name),
        ])
        stmts.push(Expr(call_expr))
      }
      IndexSig(_, _, _) => ()
    }
  }
  if stmts.length() == 1 {
    stmts[0]
  } else {
    // Use IIFE pattern to avoid scope issues with let
    // The first statement is always Let(name, ...) which we convert to internal temp
    // Then wrap everything in an IIFE that returns the class
    let internal_stmts : Array[@ast.TsStmt] = []
    for stmt in stmts {
      internal_stmts.push(stmt)
    }
    internal_stmts.push(Return(Some(@ast.TsExpr::Var(name))))
    let iife = @ast.TsExpr::CallExpr(
      @ast.TsExpr::FuncExpr(@ast.TsFunc::{
        type_params: [],
        type_param_bounds: [],
        name: "<class>",
        params: [],
        return_type: @ast.TsType::Any,
        body: @ast.TsBlock::{ stmts: internal_stmts, stmt_positions: [] },
        const_type_params: [],
        is_generator: false,
        is_async: false,
      }),
      [],
    )
    Let(@ast.TsBinding::Ident(name), Any, iife)
  }
}

///|
fn Parser::parse_class_decl(self : Parser) -> @ast.TsStmt raise ParseError {
  self.parse_class_decl_with_abstract(false)
}

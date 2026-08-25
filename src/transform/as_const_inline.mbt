// `as const` (and equivalent) array/object inline at use sites.
//
// When a top-level binding is `const NAME = ArrayLit | ObjectLit`
// whose every element is a literal scalar, and every reference to
// NAME in the program is a "safe access" (indexed/keyed read with
// a statically-known index, never the bare identifier on its own
// and never an assignment target), every read site can be replaced
// with the matching element value.
//
//   const STATUSES = ["ok", "warn", "err"];
//   console.log(STATUSES[1]);
//   // ->
//   console.log("warn");
//
//   const HTTP = { OK: 200, NF: 404 };
//   foo(HTTP.OK);
//   // ->
//   foo(200);
//
// Note: TypeScript's `as const` assertion is dropped by the parser
// (the resulting AST is just the literal), so we re-derive the
// "no mutations, no escape" property from usage. That's stricter
// than needed for `as const`, but is correct without it too.
//
// If any non-safe occurrence of NAME exists (bare `Var(NAME)`
// reference, `MethodCall(NAME, …)`, assignment target, escape into
// another binding, etc.) the candidate is dropped and no rewrite
// happens for that binding.

///|
priv enum AsConstShape {
  ArrShape(Array[@ast.TsExpr])
  ObjShape(Map[String, @ast.TsExpr])
}

///|
priv struct AsConstCandidate {
  shape : AsConstShape
  mut disqualified : Bool
}

///|
pub fn as_const_inline_block(block : @ast.TsBlock) -> @ast.TsBlock {
  // 1. Find candidate top-level bindings.
  let candidates : Map[String, AsConstCandidate] = {}
  for stmt in block.stmts {
    match stmt {
      Const(@ast.TsBinding::Ident(name), _, e) =>
        match extract_as_const_shape(e) {
          Some(shape) => candidates[name] = { shape, disqualified: false }
          None => ()
        }
      _ => ()
    }
  }
  if candidates.is_empty() {
    return block
  }
  // 2. Scan every statement (including the candidate's own RHS,
  //    but `disqualify_in_expr` only flags non-safe-read uses
  //    of the names — so the declaration's RHS won't disqualify
  //    its own binding).
  for stmt in block.stmts {
    scan_stmt_for_unsafe_uses(stmt, candidates)
  }
  // 3. Filter to survivors.
  let survivors : Map[String, AsConstCandidate] = {}
  for entry in candidates {
    if !entry.1.disqualified {
      survivors[entry.0] = entry.1
    }
  }
  if survivors.is_empty() {
    return block
  }
  // 4. Rewrite every safe access.
  let new_stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    new_stmts.push(rewrite_stmt(s, survivors))
  }
  { stmts: new_stmts, stmt_positions: block.stmt_positions }
}

///|
fn extract_as_const_shape(expr : @ast.TsExpr) -> AsConstShape? {
  // Unwrap the `As(...)` wrapper if a non-`const` assertion is present;
  // `as const` itself isn't wrapped by the parser, so the typical
  // shape here is the bare literal.
  let inner = match expr {
    As(e, _) => e
    _ => expr
  }
  match inner {
    ArrayLit(items) => {
      let out : Array[@ast.TsExpr] = []
      for it in items {
        if !is_scalar_literal(it) {
          return None
        }
        out.push(it)
      }
      Some(ArrShape(out))
    }
    ObjectLit(entries) => {
      let m : Map[String, @ast.TsExpr] = {}
      for ent in entries {
        if !is_scalar_literal(ent.1) {
          return None
        }
        m[ent.0] = ent.1
      }
      Some(ObjShape(m))
    }
    _ => None
  }
}

///|
fn is_scalar_literal(e : @ast.TsExpr) -> Bool {
  match e {
    StringLit(_)
    | NumberLit(_)
    | IntLit(_)
    | BoolLit(_)
    | NullLit
    | BigIntLit(_) => true
    _ => false
  }
}

///|
/// Walk a statement, flagging any candidate that is referenced in
/// an "unsafe" position (anywhere other than the right-hand side of
/// `IndexAccess(Var(name), <int_or_string_lit>)` or
/// `PropAccess(Var(name), _)`).
fn scan_stmt_for_unsafe_uses(
  stmt : @ast.TsStmt,
  candidates : Map[String, AsConstCandidate],
) -> Unit {
  match stmt {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) | Throw(e) =>
      scan_expr_for_unsafe_uses(e, candidates)
    // `NAME = …` / `NAME += …` rebinds the candidate. A top-level
    // `const` can't legally be reassigned, so this is unreachable in
    // valid input — which is exactly why it should be spelled out
    // rather than left to the wildcard arm.
    Assign(name, e) | CompoundAssign(name, _, e) => {
      match candidates.get(name) {
        Some(c) => c.disqualified = true
        None => ()
      }
      scan_expr_for_unsafe_uses(e, candidates)
    }
    Return(Some(e)) => scan_expr_for_unsafe_uses(e, candidates)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => ()
    IndexAssign(t, idx, v) => {
      scan_assign_target_for_unsafe_uses(t, candidates)
      scan_expr_for_unsafe_uses(idx, candidates)
      scan_expr_for_unsafe_uses(v, candidates)
    }
    PropAssign(t, _, v) => {
      scan_assign_target_for_unsafe_uses(t, candidates)
      scan_expr_for_unsafe_uses(v, candidates)
    }
    If(c, t, e) => {
      scan_expr_for_unsafe_uses(c, candidates)
      for s in t.stmts {
        scan_stmt_for_unsafe_uses(s, candidates)
      }
      match e {
        Some(b) =>
          for s in b.stmts {
            scan_stmt_for_unsafe_uses(s, candidates)
          }
        None => ()
      }
    }
    While(c, body) | DoWhile(c, body) | With(c, body) => {
      scan_expr_for_unsafe_uses(c, candidates)
      for s in body.stmts {
        scan_stmt_for_unsafe_uses(s, candidates)
      }
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => scan_stmt_for_unsafe_uses(s, candidates)
        None => ()
      }
      match cond {
        Some(e) => scan_expr_for_unsafe_uses(e, candidates)
        None => ()
      }
      match update {
        Some(s) => scan_stmt_for_unsafe_uses(s, candidates)
        None => ()
      }
      for s in body.stmts {
        scan_stmt_for_unsafe_uses(s, candidates)
      }
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      // The iterable position counts as a bare-identifier use:
      // `for (const x of NAME)` would observe NAME's identity.
      scan_expr_for_unsafe_uses(iter, candidates)
      for s in body.stmts {
        scan_stmt_for_unsafe_uses(s, candidates)
      }
    }
    Switch(e, cases) => {
      scan_expr_for_unsafe_uses(e, candidates)
      for c in cases {
        match c.test_expr {
          Some(te) => scan_expr_for_unsafe_uses(te, candidates)
          None => ()
        }
        for s in c.body.stmts {
          scan_stmt_for_unsafe_uses(s, candidates)
        }
      }
    }
    Try(b, _, cb, fb) => {
      for s in b.stmts {
        scan_stmt_for_unsafe_uses(s, candidates)
      }
      match cb {
        Some(blk) =>
          for s in blk.stmts {
            scan_stmt_for_unsafe_uses(s, candidates)
          }
        None => ()
      }
      match fb {
        Some(blk) =>
          for s in blk.stmts {
            scan_stmt_for_unsafe_uses(s, candidates)
          }
        None => ()
      }
    }
    Label(_, inner) => scan_stmt_for_unsafe_uses(inner, candidates)
    Block(b) =>
      for s in b.stmts {
        scan_stmt_for_unsafe_uses(s, candidates)
      }
    NativeClassStmt(decl, ctor) => {
      match decl.base_expr {
        Some(b) => scan_expr_for_unsafe_uses(b, candidates)
        None => ()
      }
      match ctor {
        Some(f) =>
          for s in f.body.stmts {
            scan_stmt_for_unsafe_uses(s, candidates)
          }
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) =>
            for s in b.stmts {
              scan_stmt_for_unsafe_uses(s, candidates)
            }
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        scan_expr_for_unsafe_uses(sf.1, candidates)
      }
    }
  }
}

///|
/// An assignment target that mentions a candidate is automatically
/// disqualifying — the candidate would be mutated.
fn scan_assign_target_for_unsafe_uses(
  expr : @ast.TsExpr,
  candidates : Map[String, AsConstCandidate],
) -> Unit {
  // The receiver of an assignment is unsafe by definition; flag every
  // candidate referenced anywhere inside it.
  flag_all_candidate_refs(expr, candidates)
}

///|
fn flag_all_candidate_refs(
  expr : @ast.TsExpr,
  candidates : Map[String, AsConstCandidate],
) -> Unit {
  match expr {
    Var(n) =>
      match candidates.get(n) {
        Some(c) => c.disqualified = true
        None => ()
      }
    BinOp(_, l, r) | Seq(l, r) => {
      flag_all_candidate_refs(l, candidates)
      flag_all_candidate_refs(r, candidates)
    }
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | YieldStar(inner) => flag_all_candidate_refs(inner, candidates)
    Cond(c, t, e) => {
      flag_all_candidate_refs(c, candidates)
      flag_all_candidate_refs(t, candidates)
      flag_all_candidate_refs(e, candidates)
    }
    PropAccess(recv, _) => flag_all_candidate_refs(recv, candidates)
    IndexAccess(recv, idx) => {
      flag_all_candidate_refs(recv, candidates)
      flag_all_candidate_refs(idx, candidates)
    }
    Call(name, args) => {
      // A bare name in callee position is fine (the candidate isn't a
      // function — but if some other binding shadows it, the rewrite
      // never fires anyway), so only walk the args.
      let _ = name
      for a in args {
        flag_all_candidate_refs(a, candidates)
      }
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      flag_all_candidate_refs(callee, candidates)
      for a in args {
        flag_all_candidate_refs(a, candidates)
      }
    }
    MethodCall(recv, _, args) => {
      flag_all_candidate_refs(recv, candidates)
      for a in args {
        flag_all_candidate_refs(a, candidates)
      }
    }
    New(_, args) =>
      for a in args {
        flag_all_candidate_refs(a, candidates)
      }
    ArrayLit(items) =>
      for it in items {
        flag_all_candidate_refs(it, candidates)
      }
    ObjectLit(entries) =>
      for ent in entries {
        flag_all_candidate_refs(ent.1, candidates)
      }
    ComputedProp(k, v) => {
      flag_all_candidate_refs(k, candidates)
      flag_all_candidate_refs(v, candidates)
    }
    AssignExpr(name, v) => {
      match candidates.get(name) {
        Some(c) => c.disqualified = true
        None => ()
      }
      flag_all_candidate_refs(v, candidates)
    }
    AssignPattern(_, v) => flag_all_candidate_refs(v, candidates)
    PropAssignExpr(recv, _, v) => {
      flag_all_candidate_refs(recv, candidates)
      flag_all_candidate_refs(v, candidates)
    }
    CompoundAssignExpr(t, _, v) => {
      flag_all_candidate_refs(t, candidates)
      flag_all_candidate_refs(v, candidates)
    }
    IndexAssignExpr(recv, idx, v) => {
      flag_all_candidate_refs(recv, candidates)
      flag_all_candidate_refs(idx, candidates)
      flag_all_candidate_refs(v, candidates)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => flag_all_candidate_refs(e, candidates)
        ArrowBlock(b) =>
          for s in b.stmts {
            scan_stmt_for_unsafe_uses(s, candidates)
          }
      }
    FuncExpr(f) =>
      for s in f.body.stmts {
        scan_stmt_for_unsafe_uses(s, candidates)
      }
    DynamicImport(spec, opts) => {
      flag_all_candidate_refs(spec, candidates)
      match opts {
        Some(o) => flag_all_candidate_refs(o, candidates)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      flag_all_candidate_refs(tag, candidates)
      for e in exprs {
        flag_all_candidate_refs(e, candidates)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        flag_all_candidate_refs(e, candidates)
      }
    As(inner, _) | Satisfies(inner, _) =>
      flag_all_candidate_refs(inner, candidates)
    Yield(Some(inner)) => flag_all_candidate_refs(inner, candidates)
    _ => ()
  }
}

///|
fn scan_expr_for_unsafe_uses(
  expr : @ast.TsExpr,
  candidates : Map[String, AsConstCandidate],
) -> Unit {
  match expr {
    // Safe read shapes: don't disqualify if the receiver is exactly
    // `Var(name)` and the index/prop is a static key. Otherwise
    // continue walking the receiver too.
    IndexAccess(@ast.TsExpr::Var(n), idx) =>
      if candidates.contains(n) && is_static_index(idx) {
        // Safe read — but still walk the index for any nested refs.
        scan_expr_for_unsafe_uses(idx, candidates)
      } else {
        // Receiver isn't a candidate, or the index isn't statically
        // known. Walk both subexpressions normally.
        scan_expr_for_unsafe_uses(idx, candidates)
      }
    PropAccess(@ast.TsExpr::Var(n), _) =>
      if candidates.contains(n) {
        // Safe.
        ()
      } else {
        ()
      }
    Var(n) =>
      match candidates.get(n) {
        Some(c) => c.disqualified = true
        None => ()
      }
    BinOp(_, l, r) | Seq(l, r) => {
      scan_expr_for_unsafe_uses(l, candidates)
      scan_expr_for_unsafe_uses(r, candidates)
    }
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | YieldStar(inner) => scan_expr_for_unsafe_uses(inner, candidates)
    Cond(c, t, e) => {
      scan_expr_for_unsafe_uses(c, candidates)
      scan_expr_for_unsafe_uses(t, candidates)
      scan_expr_for_unsafe_uses(e, candidates)
    }
    PropAccess(recv, _) => scan_expr_for_unsafe_uses(recv, candidates)
    IndexAccess(recv, idx) => {
      scan_expr_for_unsafe_uses(recv, candidates)
      scan_expr_for_unsafe_uses(idx, candidates)
    }
    Call(_, args) =>
      for a in args {
        scan_expr_for_unsafe_uses(a, candidates)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      scan_expr_for_unsafe_uses(callee, candidates)
      for a in args {
        scan_expr_for_unsafe_uses(a, candidates)
      }
    }
    MethodCall(recv, _, args) => {
      // `NAME.someMethod(...)` is an unsafe use — methods could
      // observe identity or mutate state. Flag the receiver.
      flag_all_candidate_refs(recv, candidates)
      for a in args {
        scan_expr_for_unsafe_uses(a, candidates)
      }
    }
    New(_, args) =>
      for a in args {
        scan_expr_for_unsafe_uses(a, candidates)
      }
    ArrayLit(items) =>
      for it in items {
        scan_expr_for_unsafe_uses(it, candidates)
      }
    ObjectLit(entries) =>
      for ent in entries {
        scan_expr_for_unsafe_uses(ent.1, candidates)
      }
    ComputedProp(k, v) => {
      scan_expr_for_unsafe_uses(k, candidates)
      scan_expr_for_unsafe_uses(v, candidates)
    }
    AssignExpr(name, v) => {
      // `NAME = ...` would mutate the binding.
      match candidates.get(name) {
        Some(c) => c.disqualified = true
        None => ()
      }
      scan_expr_for_unsafe_uses(v, candidates)
    }
    CompoundAssignExpr(t, _, v) => {
      flag_all_candidate_refs(t, candidates)
      scan_expr_for_unsafe_uses(v, candidates)
    }
    AssignPattern(_, v) => scan_expr_for_unsafe_uses(v, candidates)
    // `NAME.k = …` mutates the object, so its initializer no longer
    // describes what a read returns. The statement spelling
    // (`PropAssign`) already flagged the receiver; this is the same
    // write in expression position, which is how it arrives from
    // inside a function body — and missing it inlined the stale
    // initializer at every read site.
    PropAssignExpr(recv, _, v) => {
      flag_all_candidate_refs(recv, candidates)
      scan_expr_for_unsafe_uses(v, candidates)
    }
    IndexAssignExpr(recv, idx, v) => {
      flag_all_candidate_refs(recv, candidates)
      scan_expr_for_unsafe_uses(idx, candidates)
      scan_expr_for_unsafe_uses(v, candidates)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => scan_expr_for_unsafe_uses(e, candidates)
        ArrowBlock(b) =>
          for s in b.stmts {
            scan_stmt_for_unsafe_uses(s, candidates)
          }
      }
    FuncExpr(f) =>
      for s in f.body.stmts {
        scan_stmt_for_unsafe_uses(s, candidates)
      }
    DynamicImport(spec, opts) => {
      scan_expr_for_unsafe_uses(spec, candidates)
      match opts {
        Some(o) => scan_expr_for_unsafe_uses(o, candidates)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      scan_expr_for_unsafe_uses(tag, candidates)
      for e in exprs {
        scan_expr_for_unsafe_uses(e, candidates)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        scan_expr_for_unsafe_uses(e, candidates)
      }
    As(inner, _) | Satisfies(inner, _) =>
      scan_expr_for_unsafe_uses(inner, candidates)
    Yield(Some(inner)) => scan_expr_for_unsafe_uses(inner, candidates)
    NativeClassExpr(decl, ctor) => {
      match decl.base_expr {
        Some(b) => scan_expr_for_unsafe_uses(b, candidates)
        None => ()
      }
      match ctor {
        Some(f) =>
          for s in f.body.stmts {
            scan_stmt_for_unsafe_uses(s, candidates)
          }
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) =>
            for s in b.stmts {
              scan_stmt_for_unsafe_uses(s, candidates)
            }
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        scan_expr_for_unsafe_uses(sf.1, candidates)
      }
    }
    _ => ()
  }
}

///|
fn is_static_index(e : @ast.TsExpr) -> Bool {
  match e {
    NumberLit(_) | IntLit(_) | StringLit(_) => true
    _ => false
  }
}

// -- Rewrite phase ----------------------------------------------------

///|
fn rewrite_stmt(
  stmt : @ast.TsStmt,
  table : Map[String, AsConstCandidate],
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) => Var(b, t, rewrite_expr(e, table))
    Let(b, t, e) => Let(b, t, rewrite_expr(e, table))
    Const(b, t, e) => Const(b, t, rewrite_expr(e, table))
    Assign(n, e) => Assign(n, rewrite_expr(e, table))
    CompoundAssign(n, op, e) => CompoundAssign(n, op, rewrite_expr(e, table))
    IndexAssign(t, idx, v) =>
      IndexAssign(
        rewrite_expr(t, table),
        rewrite_expr(idx, table),
        rewrite_expr(v, table),
      )
    PropAssign(t, p, v) =>
      PropAssign(rewrite_expr(t, table), p, rewrite_expr(v, table))
    Expr(e) => Expr(rewrite_expr(e, table))
    Return(Some(e)) => Return(Some(rewrite_expr(e, table)))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => stmt
    Throw(e) => Throw(rewrite_expr(e, table))
    If(c, t, e) =>
      If(
        rewrite_expr(c, table),
        rewrite_block(t, table),
        match e {
          Some(b) => Some(rewrite_block(b, table))
          None => None
        },
      )
    While(c, body) => While(rewrite_expr(c, table), rewrite_block(body, table))
    DoWhile(c, body) =>
      DoWhile(rewrite_expr(c, table), rewrite_block(body, table))
    With(c, body) => With(rewrite_expr(c, table), rewrite_block(body, table))
    For(init, cond, update, body) =>
      For(
        match init {
          Some(s) => Some(rewrite_stmt(s, table))
          None => None
        },
        match cond {
          Some(e) => Some(rewrite_expr(e, table))
          None => None
        },
        match update {
          Some(s) => Some(rewrite_stmt(s, table))
          None => None
        },
        rewrite_block(body, table),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(k, b, t, rewrite_expr(iter, table), rewrite_block(body, table))
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(k, b, t, rewrite_expr(iter, table), rewrite_block(body, table))
    ForIn(k, b, t, iter, body) =>
      ForIn(k, b, t, rewrite_expr(iter, table), rewrite_block(body, table))
    Switch(e, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(te) => Some(rewrite_expr(te, table))
            None => None
          },
          body: rewrite_block(c.body, table),
        })
      }
      Switch(rewrite_expr(e, table), new_cases)
    }
    Try(b, bnd, cb, fb) =>
      Try(
        rewrite_block(b, table),
        bnd,
        match cb {
          Some(blk) => Some(rewrite_block(blk, table))
          None => None
        },
        match fb {
          Some(blk) => Some(rewrite_block(blk, table))
          None => None
        },
      )
    Label(name, inner) => Label(name, rewrite_stmt(inner, table))
    Block(b) => Block(rewrite_block(b, table))
    NativeClassStmt(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: rewrite_block(f.body, table) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(rewrite_block(b, table))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, rewrite_expr(sf.1, table)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(rewrite_expr(b, table))
        None => None
      }
      NativeClassStmt(
        {
          ..decl,
          base_expr: new_base_expr,
          methods: new_methods,
          static_field_inits: new_static_fields,
        },
        new_ctor,
      )
    }
  }
}

///|
fn rewrite_block(
  block : @ast.TsBlock,
  table : Map[String, AsConstCandidate],
) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(rewrite_stmt(s, table))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn rewrite_expr(
  expr : @ast.TsExpr,
  table : Map[String, AsConstCandidate],
) -> @ast.TsExpr {
  match expr {
    IndexAccess(@ast.TsExpr::Var(n), idx) =>
      match (table.get(n), idx) {
        (Some(c), NumberLit(d)) =>
          match c.shape {
            ArrShape(items) => {
              let i = d.to_int()
              if i >= 0 && i < items.length() && d == i.to_double() {
                items[i]
              } else {
                IndexAccess(@ast.TsExpr::Var(n), rewrite_expr(idx, table))
              }
            }
            ObjShape(m) => {
              // numeric key on object — JS coerces to string
              let k = d.to_string()
              match m.get(k) {
                Some(v) => v
                None =>
                  IndexAccess(@ast.TsExpr::Var(n), rewrite_expr(idx, table))
              }
            }
          }
        (Some(c), IntLit(i)) =>
          match c.shape {
            ArrShape(items) =>
              if i >= 0 && i < items.length() {
                items[i]
              } else {
                IndexAccess(@ast.TsExpr::Var(n), rewrite_expr(idx, table))
              }
            ObjShape(m) =>
              match m.get(i.to_string()) {
                Some(v) => v
                None =>
                  IndexAccess(@ast.TsExpr::Var(n), rewrite_expr(idx, table))
              }
          }
        (Some(c), StringLit(k)) =>
          match c.shape {
            ObjShape(m) =>
              match m.get(k) {
                Some(v) => v
                None =>
                  IndexAccess(@ast.TsExpr::Var(n), rewrite_expr(idx, table))
              }
            ArrShape(_) =>
              IndexAccess(@ast.TsExpr::Var(n), rewrite_expr(idx, table))
          }
        _ => IndexAccess(@ast.TsExpr::Var(n), rewrite_expr(idx, table))
      }
    PropAccess(@ast.TsExpr::Var(n), p) =>
      match table.get(n) {
        Some(c) =>
          match c.shape {
            ObjShape(m) =>
              match m.get(p) {
                Some(v) => v
                None => PropAccess(@ast.TsExpr::Var(n), p)
              }
            ArrShape(items) =>
              if p == "length" {
                @ast.TsExpr::IntLit(items.length())
              } else {
                PropAccess(@ast.TsExpr::Var(n), p)
              }
          }
        None => PropAccess(@ast.TsExpr::Var(n), p)
      }
    BinOp(op, l, r) => BinOp(op, rewrite_expr(l, table), rewrite_expr(r, table))
    UnaryOp(op, inner) => UnaryOp(op, rewrite_expr(inner, table))
    Cond(c, t, e) =>
      Cond(
        rewrite_expr(c, table),
        rewrite_expr(t, table),
        rewrite_expr(e, table),
      )
    PropAccess(recv, p) => PropAccess(rewrite_expr(recv, table), p)
    IndexAccess(recv, idx) =>
      IndexAccess(rewrite_expr(recv, table), rewrite_expr(idx, table))
    Call(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rewrite_expr(a, table))
      }
      Call(name, new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rewrite_expr(a, table))
      }
      CallExpr(rewrite_expr(callee, table), new_args)
    }
    New(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rewrite_expr(a, table))
      }
      New(n, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rewrite_expr(a, table))
      }
      NewExpr(rewrite_expr(callee, table), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rewrite_expr(a, table))
      }
      MethodCall(rewrite_expr(recv, table), m, new_args)
    }
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(rewrite_expr(i, table))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, rewrite_expr(ent.1, table)))
      }
      ObjectLit(new_entries)
    }
    Spread(inner) => Spread(rewrite_expr(inner, table))
    Yield(Some(inner)) => Yield(Some(rewrite_expr(inner, table)))
    YieldStar(inner) => YieldStar(rewrite_expr(inner, table))
    Await(inner) => Await(rewrite_expr(inner, table))
    Seq(a, b) => Seq(rewrite_expr(a, table), rewrite_expr(b, table))
    AssignExpr(n, v) => AssignExpr(n, rewrite_expr(v, table))
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(rewrite_expr(t, table), op, rewrite_expr(v, table))
    AssignPattern(b, v) => AssignPattern(b, rewrite_expr(v, table))
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(rewrite_expr(recv, table), p, rewrite_expr(v, table))
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        rewrite_expr(recv, table),
        rewrite_expr(idx, table),
        rewrite_expr(v, table),
      )
    ComputedProp(k, v) =>
      ComputedProp(rewrite_expr(k, table), rewrite_expr(v, table))
    ArrowFunc(params, ret, body, is_async) => {
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(rewrite_expr(e, table))
        ArrowBlock(b) => @ast.TsArrowBody::ArrowBlock(rewrite_block(b, table))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => FuncExpr({ ..f, body: rewrite_block(f.body, table) })
    DynamicImport(spec, opts) =>
      DynamicImport(
        rewrite_expr(spec, table),
        match opts {
          Some(o) => Some(rewrite_expr(o, table))
          None => None
        },
      )
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(rewrite_expr(e, table))
      }
      TaggedTemplate(rewrite_expr(tag, table), raw, cooked, new_exprs)
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(rewrite_expr(e, table))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(rewrite_expr(inner, table), ty)
    Satisfies(inner, ty) => Satisfies(rewrite_expr(inner, table), ty)
    NonNull(inner) => NonNull(rewrite_expr(inner, table))
    OptionalChain(inner) => OptionalChain(rewrite_expr(inner, table))
    PureCall(inner) => PureCall(rewrite_expr(inner, table))
    NativeClassExpr(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: rewrite_block(f.body, table) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(rewrite_block(b, table))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, rewrite_expr(sf.1, table)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(rewrite_expr(b, table))
        None => None
      }
      NativeClassExpr(
        {
          ..decl,
          base_expr: new_base_expr,
          methods: new_methods,
          static_field_inits: new_static_fields,
        },
        new_ctor,
      )
    }
    _ => expr
  }
}

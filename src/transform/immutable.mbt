// Immutability analysis + inline expansion.
//
// `analyze_immutable_consts(blocks)` finds top-level `const X = …`
// bindings whose value is an object or array literal AND whose name
// `X` is referenced *only* as the receiver of a property / index
// read in the whole bundle — never reassigned, never passed as an
// argument, never the target of `Object.assign` / `delete` / etc.
// Under those conditions every `X.foo` (object) or `X[i]` (array)
// read is provably equivalent to the literal value the object was
// constructed with.
//
// Array literals naturally cover the `[1, 2, 3] as const` pattern:
// the parser strips the `as const` annotation, so a `const TAGS =
// [...] as const` decl lands here as a plain `Const(_, _,
// ArrayLit(...))`. For arrays the report exposes one entry per
// index (`"0"`, `"1"`, …) plus a synthetic `"length"` so the inline
// pass can resolve `TAGS[0]` and `TAGS.length`.
//
// `inline_immutable_property_reads(blocks, report)` uses the report
// to substitute `PropAccess(Var(X), foo)` with the property's
// literal value (only when the value is a simple primitive — number,
// string, bool, null). Other value shapes (nested objects, function
// expressions) are left alone since inlining them would change
// sharing semantics or duplicate code.
//
// Wiring: when run before tree-shake-pass-2 inside the bundler, the
// inlined `X` typically loses every reference and the const decl
// itself becomes a dead binding — tree shaking cleans it up. The
// net effect is `const cfg = { mode: "prod" }; if (cfg.mode === "dev")
// …` becoming `if ("prod" === "dev") …`, which a follow-up
// constant-folding pass can then simplify to dead code.

///|
/// The result of an immutability scan. Keys are top-level binding
/// names; values map property name → the primitive literal value
/// from the original object literal. Properties whose value is
/// not a simple literal (object / array / function) are omitted —
/// inlining those would change sharing semantics or duplicate
/// non-trivial expressions.
pub(all) struct ImmutabilityReport {
  immutable_objects : Map[String, Map[String, @ast.TsExpr]]
}

///|
pub fn ImmutabilityReport::is_immutable(
  self : ImmutabilityReport,
  binding : String,
) -> Bool {
  self.immutable_objects.contains(binding)
}

///|
/// Look up the inlined value for `binding.prop`. Returns `None` when
/// the binding isn't on the immutable list, OR the property isn't a
/// simple-literal value, OR the property doesn't exist on the
/// original object.
pub fn ImmutabilityReport::lookup(
  self : ImmutabilityReport,
  binding : String,
  prop : String,
) -> @ast.TsExpr? {
  match self.immutable_objects.get(binding) {
    Some(m) => m.get(prop)
    None => None
  }
}

// ---------------------------------------------------------------------------
// Analysis
// ---------------------------------------------------------------------------

///|
/// Scan every block for top-level `const X = { … }` decls whose name
/// `X` is only ever read via property access in the *entire* set of
/// blocks. The bundle layer passes every module's block so the
/// analysis covers cross-module reads — that's the same scope the
/// mangler / DCE pass uses.
pub fn analyze_immutable_consts(
  blocks : Array[@ast.TsBlock],
) -> ImmutabilityReport {
  // Pass 1: find every top-level `const X = ObjectLit(…)` or
  // `const X = ArrayLit(…)` candidate. Arrays land here because
  // the parser strips the `as const` annotation; both shapes
  // contribute the same disqualifier checks.
  let candidates : Map[String, Array[(String, @ast.TsExpr)]] = {}
  for b in blocks {
    for s in b.stmts {
      match s {
        Const(@ast.TsBinding::Ident(name), _, ObjectLit(entries)) =>
          if !candidates.contains(name) {
            candidates[name] = entries
          } else {
            let _ = candidates.remove(name)
          }
        Const(@ast.TsBinding::Ident(name), _, ArrayLit(items)) =>
          if !candidates.contains(name) {
            // Synthesize ObjectLit-shaped entries: each index becomes
            // a string key (`"0"`, `"1"`, …) plus a `"length"` slot
            // so the inline pass can fold `X.length` too.
            let entries : Array[(String, @ast.TsExpr)] = []
            for i, it in items {
              entries.push((i.to_string(), it))
            }
            entries.push(("length", IntLit(items.length())))
            candidates[name] = entries
          } else {
            let _ = candidates.remove(name)
          }
        _ => ()
      }
    }
  }
  // Pass 2: walk every expression in every block and disqualify any
  // candidate whose `Var(name)` appears in a context that could
  // observe / cause mutation.
  let disqualified : Map[String, Bool] = {}
  for b in blocks {
    for s in b.stmts {
      visit_stmt_for_disqualification(s, candidates, disqualified)
    }
  }
  // Survivors: build the per-property literal table.
  let immutable_objects : Map[String, Map[String, @ast.TsExpr]] = {}
  for kv in candidates {
    let (name, entries) = kv
    if disqualified.contains(name) {
      continue
    }
    let props : Map[String, @ast.TsExpr] = {}
    for ent in entries {
      let (key, value) = ent
      if key == "..." {
        // Spread inside the literal — can't statically know which
        // properties end up on the object, so don't expose any.
        continue
      }
      if is_simple_literal(value) {
        props[key] = value
      }
    }
    if props.size() > 0 {
      immutable_objects[name] = props
    }
  }
  { immutable_objects, }
}

///|
fn is_simple_literal(expr : @ast.TsExpr) -> Bool {
  match expr {
    NumberLit(_) | IntLit(_) | BigIntLit(_) | BoolLit(_) | StringLit(_)
    | NullLit => true
    _ => false
  }
}

///|
/// Walk a stmt and call `disqualify[name] = true` for every
/// candidate name whose `Var(name)` shows up in a "non-pure-read"
/// context. After this pass, anything still in `candidates` minus
/// `disqualified` is safe to treat as immutable.
fn visit_stmt_for_disqualification(
  stmt : @ast.TsStmt,
  candidates : Map[String, Array[(String, @ast.TsExpr)]],
  disqualified : Map[String, Bool],
) -> Unit {
  match stmt {
    // Reassignment of `X` itself — the value can change.
    Assign(name, e) | CompoundAssign(name, _, e) => {
      if candidates.contains(name) {
        disqualified[name] = true
      }
      visit_expr_for_disqualification(e, candidates, disqualified)
    }
    // `X.foo = …` and `X[expr] = …` mutate the receiver.
    PropAssign(recv, _, value) => {
      match recv {
        Var(n) =>
          if candidates.contains(n) {
            disqualified[n] = true
          }
        _ => visit_expr_for_disqualification(recv, candidates, disqualified)
      }
      visit_expr_for_disqualification(value, candidates, disqualified)
    }
    IndexAssign(recv, idx, value) => {
      match recv {
        Var(n) =>
          if candidates.contains(n) {
            disqualified[n] = true
          }
        _ => visit_expr_for_disqualification(recv, candidates, disqualified)
      }
      visit_expr_for_disqualification(idx, candidates, disqualified)
      visit_expr_for_disqualification(value, candidates, disqualified)
    }
    // The initialization of the candidate itself doesn't disqualify
    // (we already captured its literal); but visit the RHS in case
    // a *different* candidate is referenced inside it.
    Const(@ast.TsBinding::Ident(n), _, _) if candidates.contains(n) =>
      // The candidate `n`'s initializer is its own ObjectLit — its
      // entries are values, not references to `n`. Skip walking.
      ()
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) | Throw(e) =>
      visit_expr_for_disqualification(e, candidates, disqualified)
    Return(opt) =>
      match opt {
        Some(e) => visit_expr_for_disqualification(e, candidates, disqualified)
        None => ()
      }
    If(c, t, e_opt) => {
      visit_expr_for_disqualification(c, candidates, disqualified)
      visit_block_for_disqualification(t, candidates, disqualified)
      match e_opt {
        Some(b) => visit_block_for_disqualification(b, candidates, disqualified)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) => {
      visit_expr_for_disqualification(c, candidates, disqualified)
      visit_block_for_disqualification(b, candidates, disqualified)
    }
    For(init_opt, cond_opt, update_opt, body) => {
      match init_opt {
        Some(s) =>
          visit_stmt_for_disqualification(s, candidates, disqualified)
        None => ()
      }
      match cond_opt {
        Some(c) =>
          visit_expr_for_disqualification(c, candidates, disqualified)
        None => ()
      }
      match update_opt {
        Some(s) =>
          visit_stmt_for_disqualification(s, candidates, disqualified)
        None => ()
      }
      visit_block_for_disqualification(body, candidates, disqualified)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      visit_expr_for_disqualification(iter, candidates, disqualified)
      visit_block_for_disqualification(body, candidates, disqualified)
    }
    Switch(scrut, cases) => {
      visit_expr_for_disqualification(scrut, candidates, disqualified)
      for c in cases {
        match c.test_expr {
          Some(t) =>
            visit_expr_for_disqualification(t, candidates, disqualified)
          None => ()
        }
        visit_block_for_disqualification(c.body, candidates, disqualified)
      }
    }
    Try(t, _, c, f) => {
      visit_block_for_disqualification(t, candidates, disqualified)
      match c {
        Some(b) => visit_block_for_disqualification(b, candidates, disqualified)
        None => ()
      }
      match f {
        Some(b) => visit_block_for_disqualification(b, candidates, disqualified)
        None => ()
      }
    }
    Block(b) => visit_block_for_disqualification(b, candidates, disqualified)
    Label(_, inner) =>
      visit_stmt_for_disqualification(inner, candidates, disqualified)
    With(target, body) => {
      visit_expr_for_disqualification(target, candidates, disqualified)
      visit_block_for_disqualification(body, candidates, disqualified)
    }
    Break(_) | Continue(_) | Empty | Debugger => ()
  }
}

///|
fn visit_block_for_disqualification(
  block : @ast.TsBlock,
  candidates : Map[String, Array[(String, @ast.TsExpr)]],
  disqualified : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    visit_stmt_for_disqualification(s, candidates, disqualified)
  }
}

///|
/// Walk an expression looking for any `Var(name)` reference outside
/// the safe-read pattern `PropAccess(Var(name), _)` /
/// `IndexAccess(Var(name), _)`. Any other appearance is conservative
/// disqualification — the binding might be passed somewhere it
/// can be mutated or have a property observed via reflection.
fn visit_expr_for_disqualification(
  expr : @ast.TsExpr,
  candidates : Map[String, Array[(String, @ast.TsExpr)]],
  disqualified : Map[String, Bool],
) -> Unit {
  match expr {
    Var(name) =>
      if candidates.contains(name) {
        disqualified[name] = true
      }
    // Safe-read pattern: `Var(name)` as the receiver of a property
    // read isn't a use of the binding itself, it's a read of one of
    // its properties. Don't descend into the `Var(name)` directly.
    PropAccess(recv, _) =>
      match recv {
        Var(_) => ()
        _ => visit_expr_for_disqualification(recv, candidates, disqualified)
      }
    IndexAccess(recv, idx) => {
      match recv {
        Var(_) => ()
        _ => visit_expr_for_disqualification(recv, candidates, disqualified)
      }
      visit_expr_for_disqualification(idx, candidates, disqualified)
    }
    MethodCall(recv, _, args) => {
      // `obj.method(…)` reads then calls — the call could mutate
      // the receiver. Disqualify if `recv` is one of ours.
      match recv {
        Var(n) =>
          if candidates.contains(n) {
            disqualified[n] = true
          }
        _ => visit_expr_for_disqualification(recv, candidates, disqualified)
      }
      for a in args {
        visit_expr_for_disqualification(a, candidates, disqualified)
      }
    }
    Call(_, args) | New(_, args) =>
      for a in args {
        visit_expr_for_disqualification(a, candidates, disqualified)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      visit_expr_for_disqualification(callee, candidates, disqualified)
      for a in args {
        visit_expr_for_disqualification(a, candidates, disqualified)
      }
    }
    ObjectLit(entries) =>
      for ent in entries {
        visit_expr_for_disqualification(ent.1, candidates, disqualified)
      }
    ArrayLit(items) =>
      for it in items {
        visit_expr_for_disqualification(it, candidates, disqualified)
      }
    ComputedProp(k, v) => {
      visit_expr_for_disqualification(k, candidates, disqualified)
      visit_expr_for_disqualification(v, candidates, disqualified)
    }
    Spread(e) | Await(e) | YieldStar(e) | NonNull(e) | UnaryOp(_, e) =>
      visit_expr_for_disqualification(e, candidates, disqualified)
    OptionalChain(e) => visit_expr_for_disqualification(e, candidates, disqualified)
    Yield(opt) =>
      match opt {
        Some(e) => visit_expr_for_disqualification(e, candidates, disqualified)
        None => ()
      }
    BinOp(_, l, r) | Seq(l, r) => {
      visit_expr_for_disqualification(l, candidates, disqualified)
      visit_expr_for_disqualification(r, candidates, disqualified)
    }
    Cond(c, t, f) => {
      visit_expr_for_disqualification(c, candidates, disqualified)
      visit_expr_for_disqualification(t, candidates, disqualified)
      visit_expr_for_disqualification(f, candidates, disqualified)
    }
    AssignExpr(name, e) => {
      if candidates.contains(name) {
        disqualified[name] = true
      }
      visit_expr_for_disqualification(e, candidates, disqualified)
    }
    AssignPattern(_, e) =>
      visit_expr_for_disqualification(e, candidates, disqualified)
    CompoundAssignExpr(target, _, e) => {
      visit_expr_for_disqualification(target, candidates, disqualified)
      visit_expr_for_disqualification(e, candidates, disqualified)
    }
    PropAssignExpr(recv, _, value) => {
      match recv {
        Var(n) =>
          if candidates.contains(n) {
            disqualified[n] = true
          }
        _ => visit_expr_for_disqualification(recv, candidates, disqualified)
      }
      visit_expr_for_disqualification(value, candidates, disqualified)
    }
    IndexAssignExpr(recv, idx, value) => {
      match recv {
        Var(n) =>
          if candidates.contains(n) {
            disqualified[n] = true
          }
        _ => visit_expr_for_disqualification(recv, candidates, disqualified)
      }
      visit_expr_for_disqualification(idx, candidates, disqualified)
      visit_expr_for_disqualification(value, candidates, disqualified)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) =>
          visit_expr_for_disqualification(e, candidates, disqualified)
        ArrowBlock(b) =>
          visit_block_for_disqualification(b, candidates, disqualified)
      }
    FuncExpr(f) =>
      visit_block_for_disqualification(f.body, candidates, disqualified)
    TaggedTemplate(tag, _, _, exprs) => {
      visit_expr_for_disqualification(tag, candidates, disqualified)
      for e in exprs {
        visit_expr_for_disqualification(e, candidates, disqualified)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        visit_expr_for_disqualification(e, candidates, disqualified)
      }
    As(e, _) | Satisfies(e, _) =>
      visit_expr_for_disqualification(e, candidates, disqualified)
    DynamicImport(spec, opt) => {
      visit_expr_for_disqualification(spec, candidates, disqualified)
      match opt {
        Some(o) => visit_expr_for_disqualification(o, candidates, disqualified)
        None => ()
      }
    }
    _ => ()
  }
}

// ---------------------------------------------------------------------------
// Inline expansion
// ---------------------------------------------------------------------------

///|
/// Walk every block and replace every `PropAccess(Var(name), prop)`
/// / `IndexAccess(Var(name), StringLit(prop))` with the literal
/// value the immutability scan recorded for `name.prop`. Leaves
/// every other expression shape unchanged.
pub fn inline_immutable_property_reads(
  blocks : Array[@ast.TsBlock],
  report : ImmutabilityReport,
) -> Array[@ast.TsBlock] {
  if report.immutable_objects.size() == 0 {
    return blocks
  }
  let out : Array[@ast.TsBlock] = []
  for b in blocks {
    out.push(inline_block(b, report))
  }
  out
}

///|
/// Walk every block and drop top-level `const X = ObjectLit(…)`
/// decls when `X` was identified as immutable AND no `Var(X)`
/// reference remains anywhere in the bundle. This is the natural
/// follow-up to `inline_immutable_property_reads`: once every
/// `X.foo` has been substituted, the source const usually has
/// zero live references and the decl itself is dead weight.
///
/// Limited to immutable candidates so we don't accidentally drop
/// a const the user wanted to keep for side-effecting access via
/// some pattern the analysis can't see.
pub fn drop_orphan_immutable_decls(
  blocks : Array[@ast.TsBlock],
  report : ImmutabilityReport,
) -> Array[@ast.TsBlock] {
  if report.immutable_objects.size() == 0 {
    return blocks
  }
  // Collect every `Var(name)` reference in the bundle, ignoring
  // the binding occurrences inside the candidates' own decls.
  let referenced : Map[String, Bool] = {}
  for b in blocks {
    for s in b.stmts {
      // The binding name on the LHS of a `Const` decl isn't a
      // reference, so collecting refs across the whole stmt is
      // safe: our reference walker only flags `Var(name)` /
      // `Call(name, …)`, neither of which appears in the LHS
      // binding position.
      let refs : Map[String, Bool] = {}
      collect_refs_in_stmt(s, refs)
      for r in refs {
        referenced[r.0] = true
      }
    }
  }
  // Filter: drop any top-level `Const(Ident, _, ObjectLit(_))`
  // whose name is on the immutable list AND is no longer referenced.
  let out : Array[@ast.TsBlock] = []
  for b in blocks {
    let new_stmts : Array[@ast.TsStmt] = []
    let new_positions : Array[Int] = []
    let has_positions = b.stmt_positions.length() == b.stmts.length()
    for i, s in b.stmts {
      let drop = match s {
        Const(@ast.TsBinding::Ident(name), _, ObjectLit(_))
        | Const(@ast.TsBinding::Ident(name), _, ArrayLit(_)) =>
          report.is_immutable(name) && !referenced.contains(name)
        _ => false
      }
      if !drop {
        new_stmts.push(s)
        if has_positions {
          new_positions.push(b.stmt_positions[i])
        }
      }
    }
    out.push({ stmts: new_stmts, stmt_positions: new_positions })
  }
  out
}

///|
fn inline_block(
  block : @ast.TsBlock,
  report : ImmutabilityReport,
) -> @ast.TsBlock {
  let new_stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    new_stmts.push(inline_stmt(s, report))
  }
  { stmts: new_stmts, stmt_positions: block.stmt_positions }
}

///|
fn inline_stmt(
  stmt : @ast.TsStmt,
  report : ImmutabilityReport,
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) => Var(b, t, inline_expr(e, report))
    Let(b, t, e) => Let(b, t, inline_expr(e, report))
    Const(b, t, e) => Const(b, t, inline_expr(e, report))
    Expr(e) => Expr(inline_expr(e, report))
    Return(opt) =>
      match opt {
        Some(e) => Return(Some(inline_expr(e, report)))
        None => stmt
      }
    Throw(e) => Throw(inline_expr(e, report))
    Assign(name, e) => Assign(name, inline_expr(e, report))
    CompoundAssign(name, op, e) =>
      CompoundAssign(name, op, inline_expr(e, report))
    PropAssign(recv, prop, value) =>
      PropAssign(inline_expr(recv, report), prop, inline_expr(value, report))
    IndexAssign(recv, idx, value) =>
      IndexAssign(
        inline_expr(recv, report),
        inline_expr(idx, report),
        inline_expr(value, report),
      )
    If(c, t, e_opt) =>
      If(
        inline_expr(c, report),
        inline_block(t, report),
        match e_opt {
          Some(b) => Some(inline_block(b, report))
          None => None
        },
      )
    While(c, b) => While(inline_expr(c, report), inline_block(b, report))
    DoWhile(c, b) => DoWhile(inline_expr(c, report), inline_block(b, report))
    For(init_opt, cond_opt, update_opt, body) =>
      For(
        match init_opt {
          Some(s) => Some(inline_stmt(s, report))
          None => None
        },
        match cond_opt {
          Some(c) => Some(inline_expr(c, report))
          None => None
        },
        match update_opt {
          Some(s) => Some(inline_stmt(s, report))
          None => None
        },
        inline_block(body, report),
      )
    ForOf(kind, b, t, iter, body) =>
      ForOf(kind, b, t, inline_expr(iter, report), inline_block(body, report))
    ForAwaitOf(kind, b, t, iter, body) =>
      ForAwaitOf(
        kind,
        b,
        t,
        inline_expr(iter, report),
        inline_block(body, report),
      )
    ForIn(kind, b, t, iter, body) =>
      ForIn(kind, b, t, inline_expr(iter, report), inline_block(body, report))
    Switch(scrut, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(t) => Some(inline_expr(t, report))
            None => None
          },
          body: inline_block(c.body, report),
        })
      }
      Switch(inline_expr(scrut, report), new_cases)
    }
    Try(t, b, c, f) =>
      Try(
        inline_block(t, report),
        b,
        match c {
          Some(blk) => Some(inline_block(blk, report))
          None => None
        },
        match f {
          Some(blk) => Some(inline_block(blk, report))
          None => None
        },
      )
    Block(b) => Block(inline_block(b, report))
    Label(name, inner) => Label(name, inline_stmt(inner, report))
    With(target, body) =>
      With(inline_expr(target, report), inline_block(body, report))
    Break(_) | Continue(_) | Empty | Debugger => stmt
  }
}

///|
fn inline_expr(
  expr : @ast.TsExpr,
  report : ImmutabilityReport,
) -> @ast.TsExpr {
  match expr {
    PropAccess(Var(name), prop) =>
      match report.lookup(name, prop) {
        Some(value) => value
        None => expr
      }
    IndexAccess(Var(name), StringLit(prop)) =>
      match report.lookup(name, prop) {
        Some(value) => value
        None => expr
      }
    // Numeric index into an immutable array — synthesized keys
    // `"0"` / `"1"` / … on the report side. `IntLit(n)` is the
    // common case, `NumberLit` shows up for floats which we just
    // don't fold.
    IndexAccess(Var(name), IntLit(n)) =>
      match report.lookup(name, n.to_string()) {
        Some(value) => value
        None => expr
      }
    PropAccess(recv, prop) => PropAccess(inline_expr(recv, report), prop)
    IndexAccess(recv, idx) =>
      IndexAccess(inline_expr(recv, report), inline_expr(idx, report))
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_expr(a, report))
      }
      MethodCall(inline_expr(recv, report), m, new_args)
    }
    Call(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_expr(a, report))
      }
      Call(name, new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_expr(a, report))
      }
      CallExpr(inline_expr(callee, report), new_args)
    }
    New(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_expr(a, report))
      }
      New(name, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_expr(a, report))
      }
      NewExpr(inline_expr(callee, report), new_args)
    }
    BinOp(op, l, r) =>
      BinOp(op, inline_expr(l, report), inline_expr(r, report))
    UnaryOp(op, e) => UnaryOp(op, inline_expr(e, report))
    Cond(c, t, f) =>
      Cond(inline_expr(c, report), inline_expr(t, report), inline_expr(f, report))
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(inline_expr(i, report))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, inline_expr(ent.1, report)))
      }
      ObjectLit(new_entries)
    }
    Spread(e) => Spread(inline_expr(e, report))
    Await(e) => Await(inline_expr(e, report))
    YieldStar(e) => YieldStar(inline_expr(e, report))
    NonNull(e) => NonNull(inline_expr(e, report))
    OptionalChain(e) => OptionalChain(inline_expr(e, report))
    Yield(opt) =>
      Yield(match opt {
        Some(e) => Some(inline_expr(e, report))
        None => None
      })
    Seq(l, r) => Seq(inline_expr(l, report), inline_expr(r, report))
    AssignExpr(name, e) => AssignExpr(name, inline_expr(e, report))
    AssignPattern(b, e) => AssignPattern(b, inline_expr(e, report))
    CompoundAssignExpr(target, op, e) =>
      CompoundAssignExpr(
        inline_expr(target, report),
        op,
        inline_expr(e, report),
      )
    PropAssignExpr(recv, prop, value) =>
      PropAssignExpr(
        inline_expr(recv, report),
        prop,
        inline_expr(value, report),
      )
    IndexAssignExpr(recv, idx, value) =>
      IndexAssignExpr(
        inline_expr(recv, report),
        inline_expr(idx, report),
        inline_expr(value, report),
      )
    ComputedProp(k, v) =>
      ComputedProp(inline_expr(k, report), inline_expr(v, report))
    ArrowFunc(params, ret, body, is_async) => {
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(inline_expr(e, report))
        ArrowBlock(b) => @ast.TsArrowBody::ArrowBlock(inline_block(b, report))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => {
      let new_body = inline_block(f.body, report)
      FuncExpr({ ..f, body: new_body })
    }
    TaggedTemplate(tag, strs, raws, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(inline_expr(e, report))
      }
      TaggedTemplate(inline_expr(tag, report), strs, raws, new_exprs)
    }
    TemplateLiteral(strs, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(inline_expr(e, report))
      }
      TemplateLiteral(strs, new_exprs)
    }
    As(e, t) => As(inline_expr(e, report), t)
    Satisfies(e, t) => Satisfies(inline_expr(e, report), t)
    DynamicImport(spec, opt) =>
      DynamicImport(
        inline_expr(spec, report),
        match opt {
          Some(o) => Some(inline_expr(o, report))
          None => None
        },
      )
    _ => expr
  }
}

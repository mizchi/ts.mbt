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
  analyze_immutable_consts_with_sigs(blocks, [])
}

///|
/// Like `analyze_immutable_consts`, but uses `funcs` — a list of
/// function signatures from the bundle's declaration tables — to
/// relax the "passing X as an argument disqualifies X" rule when
/// the called function's matching parameter has a readonly /
/// `ReadonlyArray<T>` / `Readonly<T>` annotation. The TS type
/// system promises the callee won't mutate through such a
/// parameter; we trust that promise.
pub fn analyze_immutable_consts_with_sigs(
  blocks : Array[@ast.TsBlock],
  funcs : Array[@ast.TsFunc],
) -> ImmutabilityReport {
  // Pass 1: find every `const X = ObjectLit(…)` or
  // `const X = ArrayLit(…)` candidate (top-level *and* nested inside
  // function bodies — see `collect_candidates_in_block`). Arrays
  // include both the bare `[...]` form and the parser's
  // `As(ArrayLit(...), ConstAssertion)` wrapping for `... as const`.
  // Both shapes contribute the same disqualifier checks.
  let candidates : Map[String, Array[(String, @ast.TsExpr)]] = {}
  for b in blocks {
    collect_candidates_in_block(b, candidates)
  }
  // Index function signatures by name so the per-callsite check is
  // a single map lookup.
  let func_sigs : Map[String, @ast.TsFunc] = {}
  for f in funcs {
    func_sigs[f.name] = f
  }
  // Pass 2: walk every expression in every block and disqualify any
  // candidate whose `Var(name)` appears in a context that could
  // observe / cause mutation.
  let disqualified : Map[String, Bool] = {}
  for b in blocks {
    for s in b.stmts {
      visit_stmt_for_disqualification(s, candidates, disqualified, func_sigs)
    }
  }
  // Survivors: keep every entry (primitive *and* nested) on the
  // report so multi-level access (`cfg.db.host`) can drill in.
  // The inline pass guards the final substitution on
  // `is_simple_literal` — non-primitive values pulled from the
  // report are used only as receivers for further drilling.
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
        continue
      }
      props[key] = value
    }
    if props.size() > 0 {
      immutable_objects[name] = props
    }
  }
  { immutable_objects, }
}

///|
/// Walk a block (and every nested function / arrow body) recording
/// every `const X = ObjectLit(…)` / `const X = ArrayLit(…)` /
/// `const X = (... as const)` shape we encounter. Candidates whose
/// name appears more than once are dropped — the analyzer can't
/// know which shape wins after concat.
fn collect_candidates_in_block(
  block : @ast.TsBlock,
  candidates : Map[String, Array[(String, @ast.TsExpr)]],
) -> Unit {
  for s in block.stmts {
    collect_candidates_in_stmt(s, candidates)
  }
}

///|
fn collect_candidates_in_stmt(
  stmt : @ast.TsStmt,
  candidates : Map[String, Array[(String, @ast.TsExpr)]],
) -> Unit {
  match stmt {
    Const(@ast.TsBinding::Ident(name), _, init) => {
      record_candidate(name, init, candidates)
      // Still walk the init — a `const foo = () => { const cfg = …; … }`
      // shape has a candidate inside the arrow body we'd otherwise miss.
      collect_candidates_in_expr(init, candidates)
    }
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) | Throw(e) =>
      collect_candidates_in_expr(e, candidates)
    Return(opt) =>
      match opt {
        Some(e) => collect_candidates_in_expr(e, candidates)
        None => ()
      }
    Assign(_, e) | CompoundAssign(_, _, e) =>
      collect_candidates_in_expr(e, candidates)
    PropAssign(recv, _, value) => {
      collect_candidates_in_expr(recv, candidates)
      collect_candidates_in_expr(value, candidates)
    }
    IndexAssign(recv, idx, value) => {
      collect_candidates_in_expr(recv, candidates)
      collect_candidates_in_expr(idx, candidates)
      collect_candidates_in_expr(value, candidates)
    }
    If(c, t, e_opt) => {
      collect_candidates_in_expr(c, candidates)
      collect_candidates_in_block(t, candidates)
      match e_opt {
        Some(b) => collect_candidates_in_block(b, candidates)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) => {
      collect_candidates_in_expr(c, candidates)
      collect_candidates_in_block(b, candidates)
    }
    For(init_opt, cond_opt, update_opt, body) => {
      match init_opt {
        Some(s) => collect_candidates_in_stmt(s, candidates)
        None => ()
      }
      match cond_opt {
        Some(c) => collect_candidates_in_expr(c, candidates)
        None => ()
      }
      match update_opt {
        Some(s) => collect_candidates_in_stmt(s, candidates)
        None => ()
      }
      collect_candidates_in_block(body, candidates)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      collect_candidates_in_expr(iter, candidates)
      collect_candidates_in_block(body, candidates)
    }
    Switch(scrut, cases) => {
      collect_candidates_in_expr(scrut, candidates)
      for c in cases {
        match c.test_expr {
          Some(t) => collect_candidates_in_expr(t, candidates)
          None => ()
        }
        collect_candidates_in_block(c.body, candidates)
      }
    }
    Try(t, _, c, f) => {
      collect_candidates_in_block(t, candidates)
      match c {
        Some(b) => collect_candidates_in_block(b, candidates)
        None => ()
      }
      match f {
        Some(b) => collect_candidates_in_block(b, candidates)
        None => ()
      }
    }
    Block(b) => collect_candidates_in_block(b, candidates)
    Label(_, inner) => collect_candidates_in_stmt(inner, candidates)
    With(target, body) => {
      collect_candidates_in_expr(target, candidates)
      collect_candidates_in_block(body, candidates)
    }
    Break(_) | Continue(_) | Empty | Debugger => ()
  }
}

///|
fn collect_candidates_in_expr(
  expr : @ast.TsExpr,
  candidates : Map[String, Array[(String, @ast.TsExpr)]],
) -> Unit {
  match expr {
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => collect_candidates_in_expr(e, candidates)
        ArrowBlock(b) => collect_candidates_in_block(b, candidates)
      }
    FuncExpr(f) => collect_candidates_in_block(f.body, candidates)
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_candidates_in_expr(callee, candidates)
      for a in args {
        collect_candidates_in_expr(a, candidates)
      }
    }
    Call(_, args) | New(_, args) =>
      for a in args {
        collect_candidates_in_expr(a, candidates)
      }
    MethodCall(recv, _, args) => {
      collect_candidates_in_expr(recv, candidates)
      for a in args {
        collect_candidates_in_expr(a, candidates)
      }
    }
    ObjectLit(entries) =>
      for ent in entries {
        collect_candidates_in_expr(ent.1, candidates)
      }
    ArrayLit(items) =>
      for it in items {
        collect_candidates_in_expr(it, candidates)
      }
    BinOp(_, l, r) | Seq(l, r) => {
      collect_candidates_in_expr(l, candidates)
      collect_candidates_in_expr(r, candidates)
    }
    UnaryOp(_, e) | Spread(e) | Await(e) | NonNull(e) | OptionalChain(e)
    | YieldStar(e) => collect_candidates_in_expr(e, candidates)
    Yield(opt) =>
      match opt {
        Some(e) => collect_candidates_in_expr(e, candidates)
        None => ()
      }
    Cond(c, t, f) => {
      collect_candidates_in_expr(c, candidates)
      collect_candidates_in_expr(t, candidates)
      collect_candidates_in_expr(f, candidates)
    }
    PropAccess(recv, _) => collect_candidates_in_expr(recv, candidates)
    IndexAccess(recv, idx) => {
      collect_candidates_in_expr(recv, candidates)
      collect_candidates_in_expr(idx, candidates)
    }
    AssignExpr(_, e) | AssignPattern(_, e) =>
      collect_candidates_in_expr(e, candidates)
    CompoundAssignExpr(target, _, e) => {
      collect_candidates_in_expr(target, candidates)
      collect_candidates_in_expr(e, candidates)
    }
    PropAssignExpr(recv, _, value) => {
      collect_candidates_in_expr(recv, candidates)
      collect_candidates_in_expr(value, candidates)
    }
    IndexAssignExpr(recv, idx, value) => {
      collect_candidates_in_expr(recv, candidates)
      collect_candidates_in_expr(idx, candidates)
      collect_candidates_in_expr(value, candidates)
    }
    ComputedProp(k, v) => {
      collect_candidates_in_expr(k, candidates)
      collect_candidates_in_expr(v, candidates)
    }
    As(e, _) | Satisfies(e, _) => collect_candidates_in_expr(e, candidates)
    TaggedTemplate(tag, _, _, exprs) => {
      collect_candidates_in_expr(tag, candidates)
      for e in exprs {
        collect_candidates_in_expr(e, candidates)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_candidates_in_expr(e, candidates)
      }
    DynamicImport(spec, opt) => {
      collect_candidates_in_expr(spec, candidates)
      match opt {
        Some(o) => collect_candidates_in_expr(o, candidates)
        None => ()
      }
    }
    _ => ()
  }
}

///|
/// Record a `const X = init` candidate. Peels `As(_, ConstAssertion)`
/// so `... as const` wrappings flow through transparently. Same-name
/// duplicates disqualify (we can't know which wins after concat).
fn record_candidate(
  name : String,
  init : @ast.TsExpr,
  candidates : Map[String, Array[(String, @ast.TsExpr)]],
) -> Unit {
  let peeled = @ast.peel_const_assertion(init)
  match peeled {
    ObjectLit(entries) =>
      if candidates.contains(name) {
        let _ = candidates.remove(name)
      } else {
        candidates[name] = entries
      }
    ArrayLit(items) =>
      if candidates.contains(name) {
        let _ = candidates.remove(name)
      } else {
        let entries : Array[(String, @ast.TsExpr)] = []
        for i, it in items {
          entries.push((i.to_string(), it))
        }
        entries.push(("length", IntLit(items.length())))
        candidates[name] = entries
      }
    _ => ()
  }
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
  func_sigs : Map[String, @ast.TsFunc],
) -> Unit {
  match stmt {
    // Reassignment of `X` itself — the value can change.
    Assign(name, e) | CompoundAssign(name, _, e) => {
      if candidates.contains(name) {
        disqualified[name] = true
      }
      visit_expr_for_disqualification(e, candidates, disqualified, func_sigs)
    }
    // `X.foo = …` and `X[expr] = …` mutate the receiver.
    PropAssign(recv, _, value) => {
      match recv {
        Var(n) =>
          if candidates.contains(n) {
            disqualified[n] = true
          }
        _ => visit_expr_for_disqualification(recv, candidates, disqualified, func_sigs)
      }
      visit_expr_for_disqualification(value, candidates, disqualified, func_sigs)
    }
    IndexAssign(recv, idx, value) => {
      match recv {
        Var(n) =>
          if candidates.contains(n) {
            disqualified[n] = true
          }
        _ => visit_expr_for_disqualification(recv, candidates, disqualified, func_sigs)
      }
      visit_expr_for_disqualification(idx, candidates, disqualified, func_sigs)
      visit_expr_for_disqualification(value, candidates, disqualified, func_sigs)
    }
    // The initialization of the candidate itself doesn't disqualify
    // (we already captured its literal); but visit the RHS in case
    // a *different* candidate is referenced inside it.
    Const(@ast.TsBinding::Ident(n), _, _) if candidates.contains(n) =>
      // The candidate `n`'s initializer is its own ObjectLit — its
      // entries are values, not references to `n`. Skip walking.
      ()
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) | Throw(e) =>
      visit_expr_for_disqualification(e, candidates, disqualified, func_sigs)
    Return(opt) =>
      match opt {
        Some(e) => visit_expr_for_disqualification(e, candidates, disqualified, func_sigs)
        None => ()
      }
    If(c, t, e_opt) => {
      visit_expr_for_disqualification(c, candidates, disqualified, func_sigs)
      visit_block_for_disqualification(t, candidates, disqualified, func_sigs)
      match e_opt {
        Some(b) => visit_block_for_disqualification(b, candidates, disqualified, func_sigs)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) => {
      visit_expr_for_disqualification(c, candidates, disqualified, func_sigs)
      visit_block_for_disqualification(b, candidates, disqualified, func_sigs)
    }
    For(init_opt, cond_opt, update_opt, body) => {
      match init_opt {
        Some(s) =>
          visit_stmt_for_disqualification(s, candidates, disqualified, func_sigs)
        None => ()
      }
      match cond_opt {
        Some(c) =>
          visit_expr_for_disqualification(c, candidates, disqualified, func_sigs)
        None => ()
      }
      match update_opt {
        Some(s) =>
          visit_stmt_for_disqualification(s, candidates, disqualified, func_sigs)
        None => ()
      }
      visit_block_for_disqualification(body, candidates, disqualified, func_sigs)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      visit_expr_for_disqualification(iter, candidates, disqualified, func_sigs)
      visit_block_for_disqualification(body, candidates, disqualified, func_sigs)
    }
    Switch(scrut, cases) => {
      visit_expr_for_disqualification(scrut, candidates, disqualified, func_sigs)
      for c in cases {
        match c.test_expr {
          Some(t) =>
            visit_expr_for_disqualification(t, candidates, disqualified, func_sigs)
          None => ()
        }
        visit_block_for_disqualification(c.body, candidates, disqualified, func_sigs)
      }
    }
    Try(t, _, c, f) => {
      visit_block_for_disqualification(t, candidates, disqualified, func_sigs)
      match c {
        Some(b) => visit_block_for_disqualification(b, candidates, disqualified, func_sigs)
        None => ()
      }
      match f {
        Some(b) => visit_block_for_disqualification(b, candidates, disqualified, func_sigs)
        None => ()
      }
    }
    Block(b) => visit_block_for_disqualification(b, candidates, disqualified, func_sigs)
    Label(_, inner) =>
      visit_stmt_for_disqualification(inner, candidates, disqualified, func_sigs)
    With(target, body) => {
      visit_expr_for_disqualification(target, candidates, disqualified, func_sigs)
      visit_block_for_disqualification(body, candidates, disqualified, func_sigs)
    }
    Break(_) | Continue(_) | Empty | Debugger => ()
  }
}

///|
fn visit_block_for_disqualification(
  block : @ast.TsBlock,
  candidates : Map[String, Array[(String, @ast.TsExpr)]],
  disqualified : Map[String, Bool],
  func_sigs : Map[String, @ast.TsFunc],
) -> Unit {
  for s in block.stmts {
    visit_stmt_for_disqualification(s, candidates, disqualified, func_sigs)
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
  func_sigs : Map[String, @ast.TsFunc],
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
        _ => visit_expr_for_disqualification(recv, candidates, disqualified, func_sigs)
      }
    IndexAccess(recv, idx) => {
      match recv {
        Var(_) => ()
        _ => visit_expr_for_disqualification(recv, candidates, disqualified, func_sigs)
      }
      visit_expr_for_disqualification(idx, candidates, disqualified, func_sigs)
    }
    MethodCall(recv, _, args) => {
      // `obj.method(…)` reads then calls — the call could mutate
      // the receiver. Disqualify if `recv` is one of ours.
      match recv {
        Var(n) =>
          if candidates.contains(n) {
            disqualified[n] = true
          }
        _ => visit_expr_for_disqualification(recv, candidates, disqualified, func_sigs)
      }
      for a in args {
        visit_expr_for_disqualification(a, candidates, disqualified, func_sigs)
      }
    }
    Call(callee_name, args) => {
      // Per-position check: if `callee_name`'s parameter at index
      // `i` is annotated `readonly` / `ReadonlyArray<T>` /
      // `Readonly<T>`, the call doesn't mutate our candidate, so a
      // bare `Var(candidate)` at that arg slot doesn't disqualify.
      // We still walk the inner expressions so nested mutations are
      // caught.
      visit_call_args(callee_name, args, candidates, disqualified, func_sigs)
    }
    New(_, args) =>
      // `new Foo(X)` — we don't track constructor params yet,
      // conservatively disqualify on bare `Var(X)`.
      for a in args {
        visit_expr_for_disqualification(a, candidates, disqualified, func_sigs)
      }
    CallExpr(callee, args) => {
      visit_expr_for_disqualification(callee, candidates, disqualified, func_sigs)
      // `CallExpr(Var(name), args)` mirrors the `Call(name, args)`
      // pattern — same param-by-param readonly check.
      match callee {
        Var(callee_name) =>
          visit_call_args(callee_name, args, candidates, disqualified, func_sigs)
        _ =>
          for a in args {
            visit_expr_for_disqualification(a, candidates, disqualified, func_sigs)
          }
      }
    }
    NewExpr(callee, args) => {
      visit_expr_for_disqualification(callee, candidates, disqualified, func_sigs)
      for a in args {
        visit_expr_for_disqualification(a, candidates, disqualified, func_sigs)
      }
    }
    ObjectLit(entries) =>
      for ent in entries {
        visit_expr_for_disqualification(ent.1, candidates, disqualified, func_sigs)
      }
    ArrayLit(items) =>
      for it in items {
        visit_expr_for_disqualification(it, candidates, disqualified, func_sigs)
      }
    ComputedProp(k, v) => {
      visit_expr_for_disqualification(k, candidates, disqualified, func_sigs)
      visit_expr_for_disqualification(v, candidates, disqualified, func_sigs)
    }
    Spread(e) | Await(e) | YieldStar(e) | NonNull(e) | UnaryOp(_, e) =>
      visit_expr_for_disqualification(e, candidates, disqualified, func_sigs)
    OptionalChain(e) => visit_expr_for_disqualification(e, candidates, disqualified, func_sigs)
    Yield(opt) =>
      match opt {
        Some(e) => visit_expr_for_disqualification(e, candidates, disqualified, func_sigs)
        None => ()
      }
    BinOp(_, l, r) | Seq(l, r) => {
      visit_expr_for_disqualification(l, candidates, disqualified, func_sigs)
      visit_expr_for_disqualification(r, candidates, disqualified, func_sigs)
    }
    Cond(c, t, f) => {
      visit_expr_for_disqualification(c, candidates, disqualified, func_sigs)
      visit_expr_for_disqualification(t, candidates, disqualified, func_sigs)
      visit_expr_for_disqualification(f, candidates, disqualified, func_sigs)
    }
    AssignExpr(name, e) => {
      if candidates.contains(name) {
        disqualified[name] = true
      }
      visit_expr_for_disqualification(e, candidates, disqualified, func_sigs)
    }
    AssignPattern(_, e) =>
      visit_expr_for_disqualification(e, candidates, disqualified, func_sigs)
    CompoundAssignExpr(target, _, e) => {
      visit_expr_for_disqualification(target, candidates, disqualified, func_sigs)
      visit_expr_for_disqualification(e, candidates, disqualified, func_sigs)
    }
    PropAssignExpr(recv, _, value) => {
      match recv {
        Var(n) =>
          if candidates.contains(n) {
            disqualified[n] = true
          }
        _ => visit_expr_for_disqualification(recv, candidates, disqualified, func_sigs)
      }
      visit_expr_for_disqualification(value, candidates, disqualified, func_sigs)
    }
    IndexAssignExpr(recv, idx, value) => {
      match recv {
        Var(n) =>
          if candidates.contains(n) {
            disqualified[n] = true
          }
        _ => visit_expr_for_disqualification(recv, candidates, disqualified, func_sigs)
      }
      visit_expr_for_disqualification(idx, candidates, disqualified, func_sigs)
      visit_expr_for_disqualification(value, candidates, disqualified, func_sigs)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) =>
          visit_expr_for_disqualification(e, candidates, disqualified, func_sigs)
        ArrowBlock(b) =>
          visit_block_for_disqualification(b, candidates, disqualified, func_sigs)
      }
    FuncExpr(f) =>
      visit_block_for_disqualification(f.body, candidates, disqualified, func_sigs)
    TaggedTemplate(tag, _, _, exprs) => {
      visit_expr_for_disqualification(tag, candidates, disqualified, func_sigs)
      for e in exprs {
        visit_expr_for_disqualification(e, candidates, disqualified, func_sigs)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        visit_expr_for_disqualification(e, candidates, disqualified, func_sigs)
      }
    As(e, _) | Satisfies(e, _) =>
      visit_expr_for_disqualification(e, candidates, disqualified, func_sigs)
    DynamicImport(spec, opt) => {
      visit_expr_for_disqualification(spec, candidates, disqualified, func_sigs)
      match opt {
        Some(o) => visit_expr_for_disqualification(o, candidates, disqualified, func_sigs)
        None => ()
      }
    }
    _ => ()
  }
}

///|
/// Walk a call's argument list, treating each arg slot as either a
/// "readonly-safe" position (per the callee's signature) or a
/// possibly-mutating one. A bare `Var(candidate)` in a readonly
/// slot doesn't disqualify; inner expressions inside the arg still
/// get walked so nested writes aren't missed.
fn visit_call_args(
  callee_name : String,
  args : Array[@ast.TsExpr],
  candidates : Map[String, Array[(String, @ast.TsExpr)]],
  disqualified : Map[String, Bool],
  func_sigs : Map[String, @ast.TsFunc],
) -> Unit {
  let sig = func_sigs.get(callee_name)
  for i, a in args {
    let slot_is_readonly = match sig {
      Some(f) =>
        if i < f.params.length() {
          param_is_readonly(f.params[i].type_)
        } else {
          false
        }
      None => false
    }
    if slot_is_readonly {
      // Bare `Var(candidate)` here doesn't disqualify; descend
      // *into* the arg if it's a composite expression so nested
      // mutations / escapes are still caught.
      match a {
        Var(name) =>
          if !candidates.contains(name) {
            // Already not a candidate — nothing to skip.
            ()
          }
        // Anything else: still recurse normally. A nested
        // `(x as readonly Y) === foo`, etc. doesn't get a free pass
        // beyond the top-level bare reference.
        _ =>
          visit_expr_for_disqualification(a, candidates, disqualified, func_sigs)
      }
    } else {
      visit_expr_for_disqualification(a, candidates, disqualified, func_sigs)
    }
  }
}

///|
/// `true` when a TypeScript parameter type carries an explicit
/// "no mutation through this slot" guarantee. Currently covers:
///   - `ReadonlyArray<T>`, `ReadonlySet<T>`, `ReadonlyMap<K, V>`,
///     `Readonly<T>` (TS standard utility types).
///   - `readonly T[]` — the parser doesn't surface a distinct
///     shape for this, but `Applied("ReadonlyArray", ...)` covers
///     the canonical form.
fn param_is_readonly(ty : @ast.TsType) -> Bool {
  match ty {
    Applied(name, _) =>
      name == "ReadonlyArray" ||
      name == "ReadonlySet" ||
      name == "ReadonlyMap" ||
      name == "Readonly"
    _ => false
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
        Const(@ast.TsBinding::Ident(name), _, init) => {
          let peeled = @ast.peel_const_assertion(init)
          let is_droppable_shape = match peeled {
            ObjectLit(_) | ArrayLit(_) => true
            _ => false
          }
          is_droppable_shape &&
          report.is_immutable(name) &&
          !referenced.contains(name)
        }
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
/// Walk `expr` (assumed to be a `PropAccess` or `IndexAccess`) and
/// try to resolve it to the literal value the immutable report
/// records for the chain. Returns `None` when any link in the chain
/// is something the analysis can't pin down.
///
/// Handles:
///   - `Var(name).prop` / `Var(name)["prop"]` — top-level lookup.
///   - `Var(name)[IntLit(n)]` — array index lookup.
///   - Nested receivers, recursing on the receiver to surface its
///     literal first, then plucking the next field.
fn resolve_chain(
  expr : @ast.TsExpr,
  report : ImmutabilityReport,
) -> @ast.TsExpr? {
  match expr {
    PropAccess(Var(name), prop) => report.lookup(name, prop)
    IndexAccess(Var(name), StringLit(prop)) => report.lookup(name, prop)
    IndexAccess(Var(name), IntLit(n)) => report.lookup(name, n.to_string())
    PropAccess(recv, prop) =>
      match resolve_chain(recv, report) {
        Some(ObjectLit(entries)) => find_object_field(entries, prop)
        Some(ArrayLit(items)) =>
          if prop == "length" {
            Some(IntLit(items.length()))
          } else {
            None
          }
        _ => None
      }
    IndexAccess(recv, idx) =>
      match (resolve_chain(recv, report), idx) {
        (Some(ObjectLit(entries)), StringLit(prop)) =>
          find_object_field(entries, prop)
        (Some(ArrayLit(items)), IntLit(n)) =>
          if n >= 0 && n < items.length() {
            Some(items[n])
          } else {
            None
          }
        _ => None
      }
    _ => None
  }
}

///|
fn find_object_field(
  entries : Array[(String, @ast.TsExpr)],
  key : String,
) -> @ast.TsExpr? {
  for ent in entries {
    if ent.0 == key {
      return Some(ent.1)
    }
  }
  None
}

///|
/// Structural fall-through for a `PropAccess` / `IndexAccess` the
/// chain resolver couldn't fold — recurse into the receiver so any
/// embedded expressions still get visited.
fn fallthrough_prop_index(
  expr : @ast.TsExpr,
  report : ImmutabilityReport,
) -> @ast.TsExpr {
  match expr {
    PropAccess(recv, prop) => PropAccess(inline_expr(recv, report), prop)
    IndexAccess(recv, idx) =>
      IndexAccess(inline_expr(recv, report), inline_expr(idx, report))
    _ => expr
  }
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
    PropAccess(_, _) | IndexAccess(_, _) =>
      // Try drilling through the report — handles both single-level
      // (`cfg.foo` → primitive) and multi-level (`cfg.db.host` →
      // primitive via the intermediate ObjectLit on the report) in
      // one shot.
      match resolve_chain(expr, report) {
        Some(value) =>
          if is_simple_literal(value) {
            value
          } else {
            // Resolved to a non-primitive (nested ObjectLit / ArrayLit).
            // Don't substitute — would duplicate code. Fall through
            // to the structural rewrite below so we still walk into
            // the receivers.
            fallthrough_prop_index(expr, report)
          }
        None => fallthrough_prop_index(expr, report)
      }
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

// Bundle-level tree-shaking pass.
//
// `treeshake_block` takes the merged top-level block produced by the
// bundler and removes name-binding declarations that aren't reachable
// from any side-effect statement. The pass is intentionally
// conservative: it only drops a declaration when (a) it's a single-
// name binding and (b) its initializer is statically pure (literal,
// function expression, arrow, object/array literal of pure values).
// Anything else is treated as a side-effect root and kept verbatim.
//
// Cross-function references over-approximate: a function body's
// inner references count toward the names it pulls in, even when an
// inner local shadows a top-level binding. That over-approximation
// keeps live code; it only costs a marginal amount of dead bytes,
// which is acceptable for a v0 pass.

///|
priv struct DeclEntry {
  // Names referenced by the rhs of this declaration. Computed once
  // and cached so the BFS doesn't re-walk function bodies.
  refs : Map[String, Bool]
}

///|
/// Drop top-level declarations that no live statement transitively
/// references. Only run me on a flattened bundle block — sub-blocks
/// (function bodies, control flow) are left alone.
pub fn treeshake_block(
  block : @ast.TsBlock,
  roots? : Map[String, Bool] = {},
  pure_calls? : Map[String, Bool] = {},
) -> @ast.TsBlock {
  // Flatten fold's multi-declarator Block wrappers (`const a=1, b=2;`
  // is stored as `Block([Const(a), Const(b)])`) back into individual
  // top-level statements so each declarator can be independently
  // classified and dropped when dead.
  let flat_stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    match s {
      Block(inner) if is_pure_multi_decl_block(inner) =>
        for inner_s in inner.stmts {
          flat_stmts.push(inner_s)
        }
      _ => flat_stmts.push(s)
    }
  }
  let flat_block : @ast.TsBlock = {
    stmts: flat_stmts,
    stmt_positions: block.stmt_positions,
  }
  treeshake_flat_block(
    drop_dead_stores(flat_block, roots, pure_calls),
    roots,
    pure_calls,
  )
}

///|
/// Drop a store to a binding nothing ever READS.
///
///     let v = 1;
///     v = 2;
///     console.log("live");
///
/// Both statements are dead, and neither was being dropped: the main
/// pass counts a write as a reference, so `v = 2` kept `v` alive and
/// `v` kept its own declaration alive. Removing the store first lets
/// the existing liveness walk finish the job.
///
/// What makes this safe is what it does NOT do. Only a STATEMENT-level
/// `v = <pure>` at the top of this block is dropped, and only when `v`
/// is declared here as a plain binding, is not a root (an export an
/// importer could read), and is read nowhere — including from a nested
/// scope, since the reference walk descends into blocks and function
/// bodies. A store buried inside an `if` is left alone, and the main
/// pass still counts that one as a reference, so the declaration
/// survives with it rather than leaving the store assigning to nothing.
fn drop_dead_stores(
  block : @ast.TsBlock,
  roots : Map[String, Bool],
  pure_calls : Map[String, Bool],
) -> @ast.TsBlock {
  // Plain bindings declared by this block. A name declared elsewhere
  // could be a host global, and `globalThing = 1` is observable.
  let declared : Map[String, Bool] = {}
  for stmt in block.stmts {
    match stmt {
      Let(@ast.TsBinding::Ident(n), _, _)
      | Const(@ast.TsBinding::Ident(n), _, _)
      | Var(@ast.TsBinding::Ident(n), _, _) => declared[n] = true
      _ => ()
    }
  }
  if declared.is_empty() {
    return block
  }
  // Names that are READ. A statement-level `v = rhs` reads `rhs` but
  // not `v`; a declaration reads its initializer but not the name it
  // binds. Everything else goes through the ordinary reference walk,
  // which counts an assignment target as a reference — deliberately, so
  // the two rules cannot disagree about a store this pass declines.
  let reads : Map[String, Bool] = {}
  for stmt in block.stmts {
    match stmt {
      // Both spellings of a statement-level assignment. The parser
      // produces `Assign` on some paths and `Expr(AssignExpr(...))` on
      // others, and handling only the first one made this pass a no-op
      // on exactly the case it was written for.
      Assign(n, rhs) | Expr(@ast.TsExpr::AssignExpr(n, rhs)) if declared.contains(
          n,
        ) => collect_var_refs_in_expr(rhs, reads)
      Let(@ast.TsBinding::Ident(_), _, rhs)
      | Const(@ast.TsBinding::Ident(_), _, rhs)
      | Var(@ast.TsBinding::Ident(_), _, rhs) =>
        collect_var_refs_in_expr(rhs, reads)
      _ => collect_var_refs_in_stmt(stmt, reads)
    }
  }
  let kept : Array[@ast.TsStmt] = []
  let kept_positions : Array[Int] = []
  let has_positions = block.stmt_positions.length() == block.stmts.length()
  let mut dropped = false
  for i, stmt in block.stmts {
    let drop = match stmt {
      Assign(n, rhs) | Expr(@ast.TsExpr::AssignExpr(n, rhs)) =>
        declared.contains(n) &&
        !reads.contains(n) &&
        !roots.contains(n) &&
        is_pure_init(rhs, pure_calls)
      _ => false
    }
    if drop {
      dropped = true
      continue
    }
    kept.push(stmt)
    if has_positions {
      kept_positions.push(block.stmt_positions[i])
    }
  }
  if !dropped {
    return block
  }
  {
    stmts: kept,
    stmt_positions: if has_positions {
      kept_positions
    } else {
      block.stmt_positions
    },
  }
}

///|
fn treeshake_flat_block(
  block : @ast.TsBlock,
  roots : Map[String, Bool],
  pure_calls : Map[String, Bool],
) -> @ast.TsBlock {
  // Pass 1: classify every stmt as either a droppable declaration
  // (single name + pure rhs) or a side-effect root. Build a name ->
  // DeclEntry index for the BFS.
  let decls : Array[DeclEntry] = []
  let decl_by_name : Map[String, Int] = {}
  let is_decl : Array[Bool] = []
  for stmt in block.stmts {
    let _ = stmt
    is_decl.push(false)
  }
  for i, stmt in block.stmts {
    match stmt {
      Let(@ast.TsBinding::Ident(name), _, rhs)
      | Const(@ast.TsBinding::Ident(name), _, rhs)
      | Var(@ast.TsBinding::Ident(name), _, rhs) =>
        if is_pure_init(rhs, pure_calls) {
          let refs : Map[String, Bool] = {}
          collect_var_refs_in_expr(rhs, refs)
          decl_by_name[name] = decls.length()
          decls.push({ refs, })
          is_decl[i] = true
        }
      // Native class declarations (`class Foo { … }`) are a
      // declaration form too. They're droppable when nothing
      // instantiates or extends `Foo`. Treat them analogously to a
      // `const Foo = /* @__PURE__ */ class { … }` for the purpose
      // of treeshake. The RHS "references" are: the base class (if
      // `extends Base`) and all method body free variables.
      NativeClassStmt(decl, ctor) if decl.name != "" => {
        let refs : Map[String, Bool] = {}
        // Base class reference
        match decl.base_expr {
          Some(e) => collect_var_refs_in_expr(e, refs)
          None => ()
        }
        for n in decl.base_names {
          if n != "" && n != "<expr-base>" {
            refs[n] = true
          }
        }
        // Constructor body refs (params first — default expressions like
        // `{guid = uuidv4(), …} = {}` carry references that the body walk
        // won't see).
        match ctor {
          Some(f) => {
            collect_var_refs_in_params(f.params, refs)
            collect_var_refs_in_block(f.body, refs)
          }
          None => ()
        }
        // Method body refs (param_defaults, computed keys, and bodies)
        for m in decl.methods {
          for d in m.param_defaults {
            match d {
              Some(e) => collect_var_refs_in_expr(e, refs)
              None => ()
            }
          }
          // Computed method keys like `[OP_TAG](op) { … }` reference symbols
          // that must be kept alive.
          match m.key_expr {
            Some(ke) => collect_var_refs_in_expr(ke, refs)
            None => ()
          }
          match m.body {
            Some(b) => collect_var_refs_in_block(b, refs)
            None => ()
          }
        }
        // Static field initializer refs
        for sf in decl.static_field_inits {
          collect_var_refs_in_expr(sf.1, refs)
        }
        decl_by_name[decl.name] = decls.length()
        decls.push({ refs, })
        is_decl[i] = true
      }
      _ => ()
    }
  }

  // Pass 2: seed the live set with every name that appears in a
  // root (non-droppable) stmt. Walk the stmt's full expression tree.
  let live : Map[String, Bool] = {}
  let worklist : Array[String] = []
  // Caller-supplied roots: the names the bundle EXPORTS. Nothing inside
  // the bundle has to reference an exported binding, so without this
  // seed `export function pub() {}` looked dead and the emit was left
  // with an export clause naming a declaration that no longer existed.
  for name in roots.keys() {
    if !live.contains(name) {
      live[name] = true
      worklist.push(name)
    }
  }
  for i, stmt in block.stmts {
    if is_decl[i] {
      continue
    }
    let refs : Map[String, Bool] = {}
    collect_var_refs_in_stmt(stmt, refs)
    for r in refs.keys() {
      if decl_by_name.contains(r) && !live.contains(r) {
        live[r] = true
        worklist.push(r)
      }
    }
  }

  // Pass 3: BFS through decl-to-decl references.
  while worklist.length() > 0 {
    let n = worklist[worklist.length() - 1]
    let _ = worklist.pop()
    let idx = match decl_by_name.get(n) {
      Some(i) => i
      None => continue
    }
    for r in decls[idx].refs.keys() {
      if decl_by_name.contains(r) && !live.contains(r) {
        live[r] = true
        worklist.push(r)
      }
    }
  }

  // Pass 4: re-emit. Keep every root stmt in order; keep declarations
  // only when their name is live. Statement positions for survivors
  // are carried over so downstream source-map emission can still map
  // each remaining stmt back to its input position.
  let kept : Array[@ast.TsStmt] = []
  let kept_positions : Array[Int] = []
  let has_positions = block.stmt_positions.length() == block.stmts.length()
  for i, stmt in block.stmts {
    let keep = if is_decl[i] {
      let name = match stmt {
        Let(@ast.TsBinding::Ident(n), _, _)
        | Const(@ast.TsBinding::Ident(n), _, _)
        | Var(@ast.TsBinding::Ident(n), _, _) => n
        NativeClassStmt(decl, _) => decl.name
        _ => ""
      }
      live.contains(name)
    } else {
      // Drop pure-expression statements at the root level — they
      // have no observable effect even though they aren't decls.
      match stmt {
        Expr(e) => !is_pure_init(e, pure_calls)
        _ => true
      }
    }
    if keep {
      kept.push(stmt)
      if has_positions {
        kept_positions.push(block.stmt_positions[i])
      }
    }
  }
  { stmts: kept, stmt_positions: kept_positions }
}

///|

///|
fn all_pure_inits(
  exprs : Array[@ast.TsExpr],
  pure_calls : Map[String, Bool],
) -> Bool {
  for e in exprs {
    if !is_pure_init(e, pure_calls) {
      return false
    }
  }
  true
}

///|
/// Return `true` when `expr` is statically pure — safe to drop along
/// with its enclosing declaration if no live reference remains.
///
/// `pure_calls` names the bundle-internal functions a purity proof
/// cleared (see `purity.mbt`). Empty means "trust nothing but syntax",
/// which is the behaviour every caller had before the proof was wired
/// in.
fn is_pure_init(expr : @ast.TsExpr, pure_calls : Map[String, Bool]) -> Bool {
  match expr {
    NumberLit(_)
    | IntLit(_)
    | BigIntLit(_)
    | BoolLit(_)
    | StringLit(_)
    | NullLit
    | ArrayHole
    | Var(_)
    | FuncExpr(_)
    | ArrowFunc(_, _, _, _)
    | NativeClassExpr(_, _) => true
    ArrayLit(items) => {
      for e in items {
        if !is_pure_init(e, pure_calls) {
          return false
        }
      }
      true
    }
    ObjectLit(entries) => {
      for ent in entries {
        if !is_pure_init(ent.1, pure_calls) {
          return false
        }
      }
      true
    }
    // `++` / `--` / `delete` MUTATE, so the operator decides this, not
    // the operand. Ignoring it made `c--;` a pure expression statement
    // because `c` is pure, and the statement was dropped:
    //
    //   let c = 0; c--; console.log([c]);   printed [0], not [-1]
    //
    // A `let y = c--;` whose `y` nobody reads went the same way. It took
    // `--treeshake` and a statement-position update to show, and
    // `c -= 1` was unaffected because peephole only rewrites that to
    // `c--` later, after this pass has run. `purity.mbt` draws the same
    // distinction correctly — this second predicate did not.
    //
    // Found by `just fuzz-mangle`, shrunk to four nodes.
    UnaryOp(op, inner) =>
      match op {
        PreInc | PreDec | PostInc | PostDec | Delete => false
        _ => is_pure_init(inner, pure_calls)
      }
    BinOp(_, l, r) => is_pure_init(l, pure_calls) && is_pure_init(r, pure_calls)
    Cond(c, t, e) =>
      is_pure_init(c, pure_calls) &&
      is_pure_init(t, pure_calls) &&
      is_pure_init(e, pure_calls)
    // `/* @__PURE__ */ f(...)` — the user asserted purity, so
    // treeshake can drop the binding when the result is unused.
    PureCall(_) => true
    // Same conclusion, reached by proof instead of by annotation:
    // `pure_calls` holds the bundle-internal functions
    // `analyze_purity` showed write nothing outside their own scope
    // and call nothing impure, transitively. A call to one of those
    // whose result nobody reads is as droppable as a literal. The
    // arguments still have to be pure in their own right — the callee
    // being harmless says nothing about `f(sideEffect())`.
    Call(callee, args) =>
      pure_calls.contains(callee) && all_pure_inits(args, pure_calls)
    CallExpr(@ast.TsExpr::Var(callee), args) =>
      pure_calls.contains(callee) && all_pure_inits(args, pure_calls)
    // An effect-free host static (`Math.max(a, b)`, `Object.keys(o)`).
    // The table is per-member and excludes every mutator; see
    // `is_effect_free_static_call`.
    MethodCall(@ast.TsExpr::Var(ns), meth, args) =>
      is_effect_free_static_call(ns, meth, args.length()) &&
      all_pure_inits(args, pure_calls)
    // Template literals are pure when every interpolated expression
    // is pure (the tag-less form just concatenates strings).
    TemplateLiteral(_, exprs) => {
      for e in exprs {
        if !is_pure_init(e, pure_calls) {
          return false
        }
      }
      true
    }
    // TypeScript cast / non-null / optional-chain wrappers don't
    // introduce side effects on their own. `TypeArgs` is the same kind
    // of wrapper — `f<T>(x)` parses as `TypeArgs([T], Call(f, [x]))` —
    // and NOT peeling it here made every such initializer read as
    // impure, which is only a lost opportunity. Peeling it in
    // `collect_var_refs_in_expr` is the one that matters; see the note
    // there.
    As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner)
    | TypeArgs(_, inner) => is_pure_init(inner, pure_calls)
    // Spread of a pure value is itself pure (used in array literals).
    Spread(inner) => is_pure_init(inner, pure_calls)
    _ => false
  }
}

///|
/// Collect every name that `stmt` references in an rvalue position
/// (i.e. names that would resolve to a binding). `Var(n)` counts;
/// the receivers of `Call(n, args)`, `New(n, args)`,
/// `AssignExpr(n, _)`, `CompoundAssignExpr(_, _, _)` all count.
fn collect_var_refs_in_stmt(
  stmt : @ast.TsStmt,
  out : Map[String, Bool],
) -> Unit {
  match stmt {
    Var(b, _, rhs) | Let(b, _, rhs) | Const(b, _, rhs) => {
      // Destructuring defaults can carry the only reference to a
      // top-level helper —
      // `const { invalid = defaultInvalidHandler } = opts` is the
      // only use of `defaultInvalidHandler` in prettier's
      // options.js. Without walking the binding tree, treeshake
      // drops the helper and the call site throws at runtime.
      collect_var_refs_in_binding(b, out)
      collect_var_refs_in_expr(rhs, out)
    }
    Assign(name, rhs) => {
      out[name] = true
      collect_var_refs_in_expr(rhs, out)
    }
    CompoundAssign(name, _, rhs) => {
      out[name] = true
      collect_var_refs_in_expr(rhs, out)
    }
    IndexAssign(target, idx, val) => {
      collect_var_refs_in_expr(target, out)
      collect_var_refs_in_expr(idx, out)
      collect_var_refs_in_expr(val, out)
    }
    PropAssign(target, _, val) => {
      collect_var_refs_in_expr(target, out)
      collect_var_refs_in_expr(val, out)
    }
    Expr(e) | Throw(e) => collect_var_refs_in_expr(e, out)
    Return(Some(e)) => collect_var_refs_in_expr(e, out)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => ()
    If(c, t, e) => {
      collect_var_refs_in_expr(c, out)
      collect_var_refs_in_block(t, out)
      match e {
        Some(b) => collect_var_refs_in_block(b, out)
        None => ()
      }
    }
    While(c, body) | DoWhile(c, body) | With(c, body) => {
      collect_var_refs_in_expr(c, out)
      collect_var_refs_in_block(body, out)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => collect_var_refs_in_stmt(s, out)
        None => ()
      }
      match cond {
        Some(e) => collect_var_refs_in_expr(e, out)
        None => ()
      }
      match update {
        Some(s) => collect_var_refs_in_stmt(s, out)
        None => ()
      }
      collect_var_refs_in_block(body, out)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      collect_var_refs_in_expr(iter, out)
      collect_var_refs_in_block(body, out)
    }
    Switch(e, cases) => {
      collect_var_refs_in_expr(e, out)
      for c in cases {
        match c.test_expr {
          Some(t) => collect_var_refs_in_expr(t, out)
          None => ()
        }
        collect_var_refs_in_block(c.body, out)
      }
    }
    Try(b, _, catch_b, finally_b) => {
      collect_var_refs_in_block(b, out)
      match catch_b {
        Some(cb) => collect_var_refs_in_block(cb, out)
        None => ()
      }
      match finally_b {
        Some(fb) => collect_var_refs_in_block(fb, out)
        None => ()
      }
    }
    Label(_, inner) => collect_var_refs_in_stmt(inner, out)
    Block(b) => collect_var_refs_in_block(b, out)
    NativeClassStmt(decl, ctor_body) => {
      collect_var_refs_in_class_decl(decl, out)
      match ctor_body {
        Some(f) => {
          // Constructor parameter defaults can carry the only
          // reference to a top-level binding (e.g. Yjs's `Doc`
          // ctor: `{guid = uuidv4(), ...} = {}`). Walk every
          // default expression — including the inner destructure
          // defaults — so treeshake doesn't drop those bindings.
          collect_var_refs_in_params(f.params, out)
          collect_var_refs_in_block(f.body, out)
        }
        None => ()
      }
    }
  }
}

///|
/// A NativeClassStmt / NativeClassExpr references its base classes
/// (`extends Base`), its decorators, and every name used inside
/// methods / constructor. Treeshake needs to follow all of these so
/// the bases / call-targets don't get dropped as unused.
fn collect_var_refs_in_class_decl(
  decl : @ast.TsClassDecl,
  out : Map[String, Bool],
) -> Unit {
  for base in decl.base_names {
    out[base] = true
  }
  // `base_expr` carries the expression form of `extends …` heritage
  // (`extends declare(args)` / `extends Context.Reference()(…)`).
  // Without walking it the references it pulls in get dropped as
  // unused.
  match decl.base_expr {
    Some(e) => collect_var_refs_in_expr(e, out)
    None => ()
  }
  // Static field initializers (`static foo = init;`) live on the
  // class decl directly when the class is in native form. Without
  // walking them, references that only appear in `static` slots
  // (effect Schema's `static make = …` / drizzle's
  // `PgTable.Symbol = { …, EnableRLS }`) get dropped.
  for entry in decl.static_field_inits {
    collect_var_refs_in_expr(entry.1, out)
  }
  for dec in decl.decorators {
    collect_var_refs_in_expr(dec, out)
  }
  for m in decl.methods {
    match m.body {
      Some(b) => collect_var_refs_in_block(b, out)
      None => ()
    }
    // Computed-key methods (`[OpCodes.OP_ON_SUCCESS](op) {…}`) have
    // their key expression on `m.key_expr`. Walk it so the
    // referenced bindings stay alive.
    match m.key_expr {
      Some(e) => collect_var_refs_in_expr(e, out)
      None => ()
    }
  }
}

///|
fn collect_var_refs_in_block(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    collect_var_refs_in_stmt(s, out)
  }
}

///|
fn collect_var_refs_in_expr(
  expr : @ast.TsExpr,
  out : Map[String, Bool],
) -> Unit {
  match expr {
    Var(n) => out[n] = true
    Call(n, args) | New(n, args) => {
      out[n] = true
      for a in args {
        collect_var_refs_in_expr(a, out)
      }
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_var_refs_in_expr(callee, out)
      for a in args {
        collect_var_refs_in_expr(a, out)
      }
    }
    MethodCall(recv, _, args) => {
      collect_var_refs_in_expr(recv, out)
      for a in args {
        collect_var_refs_in_expr(a, out)
      }
    }
    BinOp(_, l, r) => {
      collect_var_refs_in_expr(l, out)
      collect_var_refs_in_expr(r, out)
    }
    UnaryOp(_, inner) | Spread(inner) | Await(inner) | YieldStar(inner) =>
      collect_var_refs_in_expr(inner, out)
    Yield(opt) =>
      match opt {
        Some(e) => collect_var_refs_in_expr(e, out)
        None => ()
      }
    Cond(c, t, e) => {
      collect_var_refs_in_expr(c, out)
      collect_var_refs_in_expr(t, out)
      collect_var_refs_in_expr(e, out)
    }
    ArrayLit(items) =>
      for i in items {
        collect_var_refs_in_expr(i, out)
      }
    ObjectLit(entries) =>
      for ent in entries {
        collect_var_refs_in_expr(ent.1, out)
      }
    ComputedProp(k, v) => {
      collect_var_refs_in_expr(k, out)
      collect_var_refs_in_expr(v, out)
    }
    IndexAccess(recv, idx) => {
      collect_var_refs_in_expr(recv, out)
      collect_var_refs_in_expr(idx, out)
    }
    PropAccess(recv, _) => collect_var_refs_in_expr(recv, out)
    AssignExpr(name, value) => {
      out[name] = true
      collect_var_refs_in_expr(value, out)
    }
    CompoundAssignExpr(target, _, value) => {
      collect_var_refs_in_expr(target, out)
      collect_var_refs_in_expr(value, out)
    }
    AssignPattern(_, value) => collect_var_refs_in_expr(value, out)
    PropAssignExpr(recv, _, value) => {
      collect_var_refs_in_expr(recv, out)
      collect_var_refs_in_expr(value, out)
    }
    IndexAssignExpr(recv, idx, value) => {
      collect_var_refs_in_expr(recv, out)
      collect_var_refs_in_expr(idx, out)
      collect_var_refs_in_expr(value, out)
    }
    Seq(a, b) => {
      collect_var_refs_in_expr(a, out)
      collect_var_refs_in_expr(b, out)
    }
    ArrowFunc(params, _, body, _) => {
      collect_var_refs_in_params(params, out)
      match body {
        ArrowExpr(e) => collect_var_refs_in_expr(e, out)
        ArrowBlock(b) => collect_var_refs_in_block(b, out)
      }
    }
    FuncExpr(f) => {
      collect_var_refs_in_params(f.params, out)
      collect_var_refs_in_block(f.body, out)
    }
    DynamicImport(spec, opts) => {
      collect_var_refs_in_expr(spec, out)
      match opts {
        Some(o) => collect_var_refs_in_expr(o, out)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      collect_var_refs_in_expr(tag, out)
      for e in exprs {
        collect_var_refs_in_expr(e, out)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_var_refs_in_expr(e, out)
      }
    // Wrappers a value-level pass has to see through. `TypeArgs` is one
    // of them, and missing it here was not a lost opportunity — it was a
    // deleted live binding.
    //
    // `f<T>(x)` / `new C<T>(x)` / `o.m<T>(x)` parse as
    // `TypeArgs([T], <the call>)`, a wrapper kept so the pervasive
    // `Call` / `New` / `MethodCall` match sites did not have to change.
    // The cost of that choice is exactly this: a walker with a catch-all
    // arm does not fall through to the inner call, it silently sees
    // NOTHING. Every name referenced anywhere inside such a call was
    // invisible to liveness, so treeshake deleted its declaration and
    // left the reference standing:
    //
    //   const CODES = { Z: "KeyZ" };
    //   const map = new Map<string, string>([["z", CODES.Z]]);
    //
    // became `new Map([["z", CODES.Z]])` with no `CODES` — a
    // ReferenceError at module load. Found on Excalidraw's
    // `packages/common/src/keys.ts`, which writes exactly that.
    As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner)
    | TypeArgs(_, inner) => collect_var_refs_in_expr(inner, out)
    NativeClassExpr(decl, ctor_body) => {
      collect_var_refs_in_class_decl(decl, out)
      match ctor_body {
        Some(f) => {
          collect_var_refs_in_params(f.params, out)
          collect_var_refs_in_block(f.body, out)
        }
        None => ()
      }
    }
    PureCall(inner) => collect_var_refs_in_expr(inner, out)
    _ => ()
  }
}

///|
/// Walk every default expression reachable from a parameter list,
/// including nested destructure-element defaults. `Param.default`
/// covers the top-level `(x = expr)` shape; `Param.binding`'s tree
/// covers `({a = expr} = {})` and `([x = expr])` shapes. Both must
/// be walked so treeshake / linker passes don't lose references
/// that only appear inside destructuring defaults.
fn collect_var_refs_in_params(
  params : Array[@ast.TsParam],
  out : Map[String, Bool],
) -> Unit {
  for p in params {
    match p.default {
      Some(d) => collect_var_refs_in_expr(d, out)
      None => ()
    }
    match p.binding {
      Some(b) => collect_var_refs_in_binding(b, out)
      None => ()
    }
  }
}

///|
fn collect_var_refs_in_binding(
  binding : @ast.TsBinding,
  out : Map[String, Bool],
) -> Unit {
  match binding {
    Ident(_) => ()
    Array(ab) => {
      for elem in ab.items {
        match elem {
          Some(be) => {
            collect_var_refs_in_binding(be.binding, out)
            match be.default {
              Some(d) => collect_var_refs_in_expr(d, out)
              None => ()
            }
          }
          None => ()
        }
      }
      match ab.rest {
        Some(r) => collect_var_refs_in_binding(r, out)
        None => ()
      }
    }
    Object(ob) =>
      for prop in ob.props {
        collect_var_refs_in_binding(prop.binding, out)
        match prop.default {
          Some(d) => collect_var_refs_in_expr(d, out)
          None => ()
        }
        match prop.key_expr {
          Some(k) => collect_var_refs_in_expr(k, out)
          None => ()
        }
      }
    Target(e) => collect_var_refs_in_expr(e, out)
  }
}

///|
/// True when `block` is a fold-produced multi-declarator group:
/// every statement is a `Const`/`Let`/`Var` with a plain `Ident`
/// binding and a pure initializer, and none uses a `FuncExpr`
/// initializer (those emit as `function f(){}` and must stay
/// as standalone statements).
fn is_pure_multi_decl_block(block : @ast.TsBlock) -> Bool {
  if block.stmts.length() < 2 {
    return false
  }
  let mut kind = ""
  for s in block.stmts {
    match s {
      Const(@ast.TsBinding::Ident(_), _, rhs) =>
        match rhs {
          @ast.TsExpr::FuncExpr(_) => return false
          _ =>
            if kind == "" {
              kind = "const"
            } else if kind != "const" {
              return false
            }
        }
      Let(@ast.TsBinding::Ident(_), _, rhs) =>
        match rhs {
          @ast.TsExpr::FuncExpr(_) => return false
          _ =>
            if kind == "" {
              kind = "let"
            } else if kind != "let" {
              return false
            }
        }
      Var(@ast.TsBinding::Ident(_), _, rhs) =>
        match rhs {
          @ast.TsExpr::FuncExpr(_) => return false
          _ =>
            if kind == "" {
              kind = "var"
            } else if kind != "var" {
              return false
            }
        }
      _ => return false
    }
  }
  kind != ""
}

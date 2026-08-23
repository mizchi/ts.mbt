// Trailing-parameter trimming.
//
// A bundle-internal function whose last parameters nobody reads is
// carrying dead weight in its signature AND at every call site:
//
//   function fmt(value, unusedOpts) { return String(value); }
//   fmt(a, {});  fmt(b, {});  fmt(c, {});
//
// becomes
//
//   function fmt(value) { return String(value); }
//   fmt(a);  fmt(b);  fmt(c);
//
// Terser won't do this — it is a cross-function edit, and JavaScript
// gives a function's arity observable meaning (`f.length`, `arguments`,
// a host that calls back with its own argument count). Which is exactly
// why it belongs here: `export_surface.mbt` and `callee_provenance.mbt`
// already answer "can anything outside this bundle get hold of `f` as a
// value?", and that is the whole proof.
//
// What has to hold, all of it, for one function:
//
//   1. `f` is a top-level binding whose initializer is a function, and
//      nothing reassigns it.
//   2. `f` is not one of the names the entry exports. An exported
//      function's arity is part of the package ABI.
//   3. Every single reference to `f` is in *callee* position. That one
//      condition carries most of the weight: it means `f` is never
//      passed to a foreign call (which could invoke it with any
//      arity), never stored in an object that escapes, never reached
//      through `f.call` / `f.apply` / `f.length`, and never used as a
//      constructor.
//   4. The body never mentions `arguments` — dropping a parameter
//      changes what that sees even when the parameter itself is unused.
//   5. Every parameter is a plain identifier: no destructuring, no rest,
//      no default. A default on a dropped parameter would stop being
//      evaluated.
//   6. Only a contiguous *trailing* run is dropped, so no surviving
//      argument changes position.
//   7. At every call site, the arguments being dropped are pure. They
//      are evaluated today; removing a call to `sideEffect()` would
//      change the program even though the parameter is dead.
//
// Anything the analysis can't establish leaves the function alone.

///|
/// How many parameters each trimmable function keeps.
pub(all) struct ArityPlan {
  keep_count : Map[String, Int]
}

///|
priv struct ParamScan {
  // Candidate name -> its parameter list.
  params : Map[String, Array[@ast.TsParam]]
  // Candidate name -> the block to scan for parameter reads. An
  // expression-bodied arrow is wrapped as a single `return`.
  bodies : Map[String, @ast.TsBlock]
  // Occurrences of `Var(name)` anywhere, and of `Var(name)` specifically
  // as the callee of a `CallExpr`. A name whose plain-reference count
  // exceeds its callee count is used as a value somewhere.
  var_hits : Map[String, Int]
  callee_hits : Map[String, Int]
  // Argument lists seen at call sites, in the two call shapes.
  calls : Map[String, Array[Array[@ast.TsExpr]]]
  // Names an assignment writes to, and names used as a constructor.
  written : Map[String, Bool]
  constructed : Map[String, Bool]
}

///|
fn bump(counter : Map[String, Int], name : String) -> Unit {
  counter[name] = counter.get(name).unwrap_or(0) + 1
}

///|
fn record_call(
  scan : ParamScan,
  name : String,
  args : Array[@ast.TsExpr],
) -> Unit {
  match scan.calls.get(name) {
    Some(arr) => arr.push(args)
    None => scan.calls[name] = [args]
  }
}

///|
/// Work out which functions can lose how many trailing parameters.
///
/// `keep` names functions whose arity must not change — the entry's
/// exported bindings.
pub fn plan_unused_params(
  block : @ast.TsBlock,
  keep? : Map[String, Bool] = {},
) -> ArityPlan {
  let scan : ParamScan = {
    params: {},
    bodies: {},
    var_hits: {},
    callee_hits: {},
    calls: {},
    written: {},
    constructed: {},
  }
  index_param_candidates(scan, block)
  if scan.params.is_empty() {
    return { keep_count: {} }
  }
  scan_param_uses(scan, block)
  let keep_count : Map[String, Int] = {}
  for entry in scan.params {
    let (name, params) = entry
    if keep.contains(name) || scan.written.contains(name) {
      continue
    }
    if scan.constructed.contains(name) {
      continue
    }
    // (3) Every reference is a callee. `Call(name, …)` stores the callee
    // as a string and contributes no `Var` node at all, so the counts
    // only have to balance for the `CallExpr` shape.
    if scan.var_hits.get(name).unwrap_or(0) >
      scan.callee_hits.get(name).unwrap_or(0) {
      continue
    }
    let body = match scan.bodies.get(name) {
      Some(b) => b
      None => continue
    }
    // (5) plain identifiers only.
    let mut plain = true
    for p in params {
      if p.is_rest || p.name == "" || p.default is Some(_) {
        plain = false
      }
      match p.binding {
        Some(@ast.TsBinding::Ident(_)) | None => ()
        Some(_) => plain = false
      }
    }
    if !plain {
      continue
    }
    // (4) `arguments` sees the real argument list whatever the
    // parameters say.
    let referenced : Map[String, Bool] = {}
    collect_var_refs_in_block(body, referenced)
    if referenced.contains("arguments") {
      continue
    }
    // (6) How many trailing parameters does the body ignore?
    let mut droppable = 0
    let mut i = params.length() - 1
    while i >= 0 && !referenced.contains(params[i].name) {
      droppable = droppable + 1
      i = i - 1
    }
    if droppable == 0 {
      continue
    }
    // (7) Narrow the drop to what every call site can actually spare.
    let mut allowed = droppable
    match scan.calls.get(name) {
      Some(sites) =>
        for args in sites {
          // A spread argument makes positions unknowable.
          for a in args {
            if a is @ast.TsExpr::Spread(_) {
              allowed = 0
            }
          }
          if allowed == 0 {
            break
          }
          // Walk back from the end of the ARGUMENT list: a site may pass
          // more arguments than there are parameters, and those extras
          // have to be droppable too.
          let last = @cmp.maximum(args.length(), params.length())
          let mut can = 0
          let mut j = last - 1
          while j >= params.length() - droppable {
            if j < args.length() && !is_pure_init(args[j], {}) {
              break
            }
            if j < params.length() {
              can = can + 1
            }
            j = j - 1
          }
          if can < allowed {
            allowed = can
          }
        }
      // Never called: trimming it changes nothing observable, and
      // treeshake will most likely delete it anyway.
      None => ()
    }
    if allowed > 0 {
      keep_count[name] = params.length() - allowed
    }
  }
  { keep_count, }
}

///|
/// Rewrite the planned functions and their call sites.
pub fn drop_unused_params_block(
  block : @ast.TsBlock,
  plan : ArityPlan,
) -> @ast.TsBlock {
  if plan.keep_count.is_empty() {
    return block
  }
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(trim_params_stmt(s, plan))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

// ---------------------------------------------------------------------------
// Indexing
// ---------------------------------------------------------------------------

///|
fn index_param_candidates(scan : ParamScan, block : @ast.TsBlock) -> Unit {
  for s in block.stmts {
    match s {
      Var(@ast.TsBinding::Ident(n), _, init)
      | Let(@ast.TsBinding::Ident(n), _, init)
      | Const(@ast.TsBinding::Ident(n), _, init) =>
        match init {
          @ast.TsExpr::FuncExpr(f) =>
            if !f.is_generator {
              scan.params[n] = f.params
              scan.bodies[n] = f.body
            }
          @ast.TsExpr::ArrowFunc(params, _, body, _) => {
            scan.params[n] = params
            scan.bodies[n] = match body {
              ArrowBlock(b) => b
              ArrowExpr(e) =>
                { stmts: [@ast.TsStmt::Return(Some(e))], stmt_positions: [] }
            }
          }
          _ => ()
        }
      // `var a = 1, b = 2;` and the class-lift pass nest declarations one
      // block deep.
      Block(inner) => index_param_candidates(scan, inner)
      _ => ()
    }
  }
}

///|
fn scan_param_uses(scan : ParamScan, block : @ast.TsBlock) -> Unit {
  // Assignment targets first: those are statement-level and the
  // expression visitor doesn't carry the name.
  scan_param_writes(scan, block)
  surface_visit_exprs_block(block, e => {
    match e {
      @ast.TsExpr::Var(n) => bump(scan.var_hits, n)
      @ast.TsExpr::Call(n, args) => record_call(scan, n, args)
      @ast.TsExpr::CallExpr(@ast.TsExpr::Var(n), args) => {
        bump(scan.callee_hits, n)
        record_call(scan, n, args)
      }
      @ast.TsExpr::New(n, _) => scan.constructed[n] = true
      @ast.TsExpr::NewExpr(@ast.TsExpr::Var(n), _) => scan.constructed[n] = true
      @ast.TsExpr::AssignExpr(n, _) => scan.written[n] = true
      @ast.TsExpr::CompoundAssignExpr(@ast.TsExpr::Var(n), _, _) =>
        scan.written[n] = true
      _ => ()
    }
  })
}

///|
fn scan_param_writes(scan : ParamScan, block : @ast.TsBlock) -> Unit {
  for s in block.stmts {
    match s {
      Assign(n, _) | CompoundAssign(n, _, _) => scan.written[n] = true
      _ => ()
    }
    // Nested blocks. Function bodies are covered by the expression
    // visitor above, which descends into them.
    match s {
      Block(b) | While(_, b) | DoWhile(_, b) | With(_, b) | For(_, _, _, b) =>
        scan_param_writes(scan, b)
      ForOf(_, _, _, _, b) | ForAwaitOf(_, _, _, _, b) | ForIn(_, _, _, _, b) =>
        scan_param_writes(scan, b)
      If(_, t, e) => {
        scan_param_writes(scan, t)
        match e {
          Some(eb) => scan_param_writes(scan, eb)
          None => ()
        }
      }
      Try(b, _, c, f) => {
        scan_param_writes(scan, b)
        match c {
          Some(cb) => scan_param_writes(scan, cb)
          None => ()
        }
        match f {
          Some(fb) => scan_param_writes(scan, fb)
          None => ()
        }
      }
      Switch(_, cases) =>
        for case_ in cases {
          scan_param_writes(scan, case_.body)
        }
      Label(_, inner) =>
        scan_param_writes(scan, { stmts: [inner], stmt_positions: [] })
      _ => ()
    }
  }
}

// ---------------------------------------------------------------------------
// Rewriting
// ---------------------------------------------------------------------------

///|
fn trim_args(
  name : String,
  args : Array[@ast.TsExpr],
  plan : ArityPlan,
) -> Array[@ast.TsExpr] {
  let keep = match plan.keep_count.get(name) {
    Some(k) => k
    None => return args
  }
  let out : Array[@ast.TsExpr] = []
  for i, a in args {
    if i < keep {
      out.push(a)
    }
  }
  out
}

///|
fn trim_params(params : Array[@ast.TsParam], keep : Int) -> Array[@ast.TsParam] {
  let out : Array[@ast.TsParam] = []
  for i, p in params {
    if i < keep {
      out.push(p)
    }
  }
  out
}

///|
fn trim_params_stmt(stmt : @ast.TsStmt, plan : ArityPlan) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) => Var(b, t, trim_params_decl(b, e, plan))
    Let(b, t, e) => Let(b, t, trim_params_decl(b, e, plan))
    Const(b, t, e) => Const(b, t, trim_params_decl(b, e, plan))
    Assign(n, e) => Assign(n, trim_params_expr(e, plan))
    CompoundAssign(n, op, e) => CompoundAssign(n, op, trim_params_expr(e, plan))
    IndexAssign(a, b, c) =>
      IndexAssign(
        trim_params_expr(a, plan),
        trim_params_expr(b, plan),
        trim_params_expr(c, plan),
      )
    PropAssign(a, p, b) =>
      PropAssign(trim_params_expr(a, plan), p, trim_params_expr(b, plan))
    Expr(e) => Expr(trim_params_expr(e, plan))
    Throw(e) => Throw(trim_params_expr(e, plan))
    Return(Some(e)) => Return(Some(trim_params_expr(e, plan)))
    Return(None) => stmt
    If(c, t, e) =>
      If(
        trim_params_expr(c, plan),
        drop_unused_params_block(t, plan),
        match e {
          Some(b) => Some(drop_unused_params_block(b, plan))
          None => None
        },
      )
    While(c, b) =>
      While(trim_params_expr(c, plan), drop_unused_params_block(b, plan))
    DoWhile(c, b) =>
      DoWhile(trim_params_expr(c, plan), drop_unused_params_block(b, plan))
    With(c, b) =>
      With(trim_params_expr(c, plan), drop_unused_params_block(b, plan))
    For(init, cond, upd, b) =>
      For(
        match init {
          Some(s) => Some(trim_params_stmt(s, plan))
          None => None
        },
        match cond {
          Some(e) => Some(trim_params_expr(e, plan))
          None => None
        },
        match upd {
          Some(s) => Some(trim_params_stmt(s, plan))
          None => None
        },
        drop_unused_params_block(b, plan),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(
        k,
        b,
        t,
        trim_params_expr(iter, plan),
        drop_unused_params_block(body, plan),
      )
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(
        k,
        b,
        t,
        trim_params_expr(iter, plan),
        drop_unused_params_block(body, plan),
      )
    ForIn(k, b, t, iter, body) =>
      ForIn(
        k,
        b,
        t,
        trim_params_expr(iter, plan),
        drop_unused_params_block(body, plan),
      )
    Switch(e, cases) => {
      let out : Array[@ast.TsSwitchCase] = []
      for c in cases {
        out.push({
          ..c,
          test_expr: match c.test_expr {
            Some(te) => Some(trim_params_expr(te, plan))
            None => None
          },
          body: drop_unused_params_block(c.body, plan),
        })
      }
      Switch(trim_params_expr(e, plan), out)
    }
    Try(b, bind, c, f) =>
      Try(
        drop_unused_params_block(b, plan),
        bind,
        match c {
          Some(cb) => Some(drop_unused_params_block(cb, plan))
          None => None
        },
        match f {
          Some(fb) => Some(drop_unused_params_block(fb, plan))
          None => None
        },
      )
    Label(l, inner) => Label(l, trim_params_stmt(inner, plan))
    Block(b) => Block(drop_unused_params_block(b, plan))
    NativeClassStmt(decl, ctor) =>
      NativeClassStmt(
        trim_params_class(decl, plan),
        match ctor {
          Some(f) => Some({ ..f, body: drop_unused_params_block(f.body, plan) })
          None => None
        },
      )
    _ => stmt
  }
}

///|
/// A declaration whose binding is a planned function gets its parameter
/// list truncated; everything else just recurses.
fn trim_params_decl(
  b : @ast.TsBinding,
  init : @ast.TsExpr,
  plan : ArityPlan,
) -> @ast.TsExpr {
  let keep = match b {
    @ast.TsBinding::Ident(n) => plan.keep_count.get(n)
    _ => None
  }
  match (keep, init) {
    (Some(k), @ast.TsExpr::FuncExpr(f)) =>
      @ast.TsExpr::FuncExpr({
        ..f,
        params: trim_params(f.params, k),
        body: drop_unused_params_block(f.body, plan),
      })
    (Some(k), @ast.TsExpr::ArrowFunc(params, ret, body, is_async)) =>
      @ast.TsExpr::ArrowFunc(
        trim_params(params, k),
        ret,
        match body {
          ArrowBlock(bb) => ArrowBlock(drop_unused_params_block(bb, plan))
          ArrowExpr(e) => ArrowExpr(trim_params_expr(e, plan))
        },
        is_async,
      )
    _ => trim_params_expr(init, plan)
  }
}

///|
fn trim_params_class(
  decl : @ast.TsClassDecl,
  plan : ArityPlan,
) -> @ast.TsClassDecl {
  let methods : Array[@ast.TsClassMethodDecl] = []
  for m in decl.methods {
    methods.push({
      ..m,
      body: match m.body {
        Some(b) => Some(drop_unused_params_block(b, plan))
        None => None
      },
    })
  }
  let statics : Array[(String, @ast.TsExpr)] = []
  for sf in decl.static_field_inits {
    statics.push((sf.0, trim_params_expr(sf.1, plan)))
  }
  { ..decl, methods, static_field_inits: statics }
}

///|
fn trim_params_expr(expr : @ast.TsExpr, plan : ArityPlan) -> @ast.TsExpr {
  match expr {
    Call(name, args) => Call(name, trim_args_rec(name, args, plan))
    CallExpr(@ast.TsExpr::Var(name), args) =>
      CallExpr(@ast.TsExpr::Var(name), trim_args_rec(name, args, plan))
    CallExpr(callee, args) =>
      CallExpr(trim_params_expr(callee, plan), trim_exprs(args, plan))
    New(n, args) => New(n, trim_exprs(args, plan))
    NewExpr(callee, args) =>
      NewExpr(trim_params_expr(callee, plan), trim_exprs(args, plan))
    MethodCall(recv, m, args) =>
      MethodCall(trim_params_expr(recv, plan), m, trim_exprs(args, plan))
    BinOp(op, a, b) =>
      BinOp(op, trim_params_expr(a, plan), trim_params_expr(b, plan))
    UnaryOp(op, inner) => UnaryOp(op, trim_params_expr(inner, plan))
    Spread(inner) => Spread(trim_params_expr(inner, plan))
    Await(inner) => Await(trim_params_expr(inner, plan))
    YieldStar(inner) => YieldStar(trim_params_expr(inner, plan))
    Yield(Some(inner)) => Yield(Some(trim_params_expr(inner, plan)))
    Yield(None) => expr
    As(inner, t) => As(trim_params_expr(inner, plan), t)
    Satisfies(inner, t) => Satisfies(trim_params_expr(inner, plan), t)
    NonNull(inner) => NonNull(trim_params_expr(inner, plan))
    OptionalChain(inner) => OptionalChain(trim_params_expr(inner, plan))
    PureCall(inner) => PureCall(trim_params_expr(inner, plan))
    TypeArgs(t, inner) => TypeArgs(t, trim_params_expr(inner, plan))
    Cond(c, t, e) =>
      Cond(
        trim_params_expr(c, plan),
        trim_params_expr(t, plan),
        trim_params_expr(e, plan),
      )
    Seq(a, b) => Seq(trim_params_expr(a, plan), trim_params_expr(b, plan))
    PropAccess(recv, p) => PropAccess(trim_params_expr(recv, plan), p)
    IndexAccess(recv, idx) =>
      IndexAccess(trim_params_expr(recv, plan), trim_params_expr(idx, plan))
    ArrayLit(items) => ArrayLit(trim_exprs(items, plan))
    ObjectLit(entries) => {
      let out : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        out.push((ent.0, trim_params_expr(ent.1, plan)))
      }
      ObjectLit(out)
    }
    ComputedProp(k, v) =>
      ComputedProp(trim_params_expr(k, plan), trim_params_expr(v, plan))
    AssignExpr(n, v) => AssignExpr(n, trim_params_expr(v, plan))
    AssignPattern(b, v) => AssignPattern(b, trim_params_expr(v, plan))
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(
        trim_params_expr(t, plan),
        op,
        trim_params_expr(v, plan),
      )
    PropAssignExpr(t, p, v) =>
      PropAssignExpr(trim_params_expr(t, plan), p, trim_params_expr(v, plan))
    IndexAssignExpr(t, idx, v) =>
      IndexAssignExpr(
        trim_params_expr(t, plan),
        trim_params_expr(idx, plan),
        trim_params_expr(v, plan),
      )
    ArrowFunc(params, ret, body, is_async) =>
      ArrowFunc(
        params,
        ret,
        match body {
          ArrowBlock(b) => ArrowBlock(drop_unused_params_block(b, plan))
          ArrowExpr(e) => ArrowExpr(trim_params_expr(e, plan))
        },
        is_async,
      )
    FuncExpr(f) =>
      FuncExpr({ ..f, body: drop_unused_params_block(f.body, plan) })
    NativeClassExpr(decl, ctor) =>
      NativeClassExpr(
        trim_params_class(decl, plan),
        match ctor {
          Some(f) => Some({ ..f, body: drop_unused_params_block(f.body, plan) })
          None => None
        },
      )
    DynamicImport(spec, opts) =>
      DynamicImport(
        trim_params_expr(spec, plan),
        match opts {
          Some(o) => Some(trim_params_expr(o, plan))
          None => None
        },
      )
    TaggedTemplate(tag, cooked, raw, exprs) =>
      TaggedTemplate(
        trim_params_expr(tag, plan),
        cooked,
        raw,
        trim_exprs(exprs, plan),
      )
    TemplateLiteral(parts, exprs) =>
      TemplateLiteral(parts, trim_exprs(exprs, plan))
    _ => expr
  }
}

///|
fn trim_args_rec(
  name : String,
  args : Array[@ast.TsExpr],
  plan : ArityPlan,
) -> Array[@ast.TsExpr] {
  trim_exprs(trim_args(name, args, plan), plan)
}

///|
fn trim_exprs(
  exprs : Array[@ast.TsExpr],
  plan : ArityPlan,
) -> Array[@ast.TsExpr] {
  let out : Array[@ast.TsExpr] = []
  for e in exprs {
    out.push(trim_params_expr(e, plan))
  }
  out
}

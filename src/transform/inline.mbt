// Single-use const / let inlining.
//
// Folds the pattern:
//
//   const X = rhs;
//   <use of X exactly once in the next stmt>
//
// into the next statement, dropping the declaration. This is the
// last byte-shaving win we can grab without giving up obvious
// correctness — running rolldown on the same corpus produces the
// same shape because TypeScript code naturally generates lots of
// "compute once, use once" intermediaries.
//
// Safety rules:
//
//   1. The binding is a simple identifier (no destructuring).
//   2. The next statement (immediately after the decl) contains
//      exactly one Var(X) reference at the top level — i.e. not
//      inside a nested function / arrow body. Closure captures
//      would change evaluation timing.
//   3. No other statement in the block (or any descendant) refers
//      to X.
//   4. X is never reassigned (no Assign / CompoundAssign /
//      PreInc / PostInc / etc. targeting X in this block or any
//      descendant).
//
// Under those constraints, moving the rhs to the single use site
// keeps the same number of evaluations in the same total order.
// The emitter's precedence-aware wrapper takes care of any paren
// needs when the rhs is a low-precedence operator dropped into a
// higher-precedence context.

///|
/// Inline single-use const / let bindings throughout a block.
/// Recurses into nested function bodies so the optimization runs
/// inside every scope.
pub fn inline_block(block : @ast.TsBlock) -> @ast.TsBlock {
  // First, recurse into nested blocks (function bodies, control
  // flow). That way the OUTER pass sees already-inlined inner
  // statements; the win compounds through wrapper functions.
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(inline_into_stmt(s))
  }
  let positions = if block.stmt_positions.length() == block.stmts.length() {
    block.stmt_positions
  } else {
    []
  }
  // Multi-declarator `let a = 1, b = 2;` parses as
  // `Block({stmts:[Let(a, …), Let(b, …)]})` because
  // `merge_decl_stmts` wraps the list. Emit unwraps it back to a
  // single chained `let` (the bindings stay in the parent scope),
  // but `inline_pass` only sees the inner block — so a `let e =
  // …, s = …;` followed by `if (!s) { …e… }` looks like `e` is
  // used exactly once (inside the same Block) and inline drops the
  // binding, leaving `if (!s) { …e… }` with `e` undefined. Flatten
  // these multi-decl Blocks into the parent's stmt list before the
  // single-use pass runs.
  let flattened : Array[@ast.TsStmt] = []
  let flat_positions : Array[Int] = []
  let has_positions = positions.length() == stmts.length()
  for i, s in stmts {
    match s {
      Block(inner) =>
        if is_multi_decl_block(inner) {
          for inner_s in inner.stmts {
            flattened.push(inner_s)
            if has_positions {
              flat_positions.push(positions[i])
            }
          }
        } else {
          flattened.push(s)
          if has_positions {
            flat_positions.push(positions[i])
          }
        }
      _ => {
        flattened.push(s)
        if has_positions {
          flat_positions.push(positions[i])
        }
      }
    }
  }
  // Run inline_pass to fixpoint: chained decls (`const a = rhs; const b = f(a); use(b)`)
  // need two passes — first to inline `a` into `b`, then to inline `b` into `use(b)`.
  // Each pass either reduces the statement count or makes no progress, so the loop
  // terminates in O(chain_length) iterations, typically 2–3.
  let mut cur = inline_pass(flattened, flat_positions)
  let mut prev_len = flattened.length()
  while cur.stmts.length() < prev_len {
    prev_len = cur.stmts.length()
    cur = inline_pass(cur.stmts, cur.stmt_positions)
  }
  cur
}

///|
/// Mirror of `try_emit_multi_decl_inline`'s shape check: a block whose
/// stmts are ALL `Var` / ALL `Let` / ALL `Const`, matching the
/// chained-declarator pattern that `parse_var_like` wraps in
/// `Block(…)`.
fn is_multi_decl_block(block : @ast.TsBlock) -> Bool {
  // `merge_decl_stmts` only wraps when there are 2+ declarators —
  // a real `{ let a = 1; }` block has exactly one stmt and must
  // keep its own scope. Flattening a length-1 Block would lift the
  // binding into the parent scope and change runtime semantics.
  if block.stmts.length() < 2 {
    return false
  }
  let kind = match block.stmts[0] {
    Var(_, _, _) => 0
    Let(_, _, _) => 1
    Const(_, _, _) => 2
    _ => return false
  }
  for s in block.stmts {
    match s {
      Var(_, _, _) => if kind != 0 { return false }
      Let(_, _, _) => if kind != 1 { return false }
      Const(_, _, _) => if kind != 2 { return false }
      _ => return false
    }
  }
  true
}

///|
/// Recurse: rebuild a stmt with its nested blocks/exprs inlined.
fn inline_into_stmt(stmt : @ast.TsStmt) -> @ast.TsStmt {
  match stmt {
    Var(b, t, rhs) => Var(b, t, inline_into_expr(rhs))
    Let(b, t, rhs) => Let(b, t, inline_into_expr(rhs))
    Const(b, t, rhs) => Const(b, t, inline_into_expr(rhs))
    Assign(n, rhs) => Assign(n, inline_into_expr(rhs))
    CompoundAssign(n, op, rhs) => CompoundAssign(n, op, inline_into_expr(rhs))
    IndexAssign(target, idx, val) =>
      IndexAssign(
        inline_into_expr(target),
        inline_into_expr(idx),
        inline_into_expr(val),
      )
    PropAssign(target, prop, val) =>
      PropAssign(inline_into_expr(target), prop, inline_into_expr(val))
    Expr(e) => Expr(inline_into_expr(e))
    Return(Some(e)) => Return(Some(inline_into_expr(e)))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => stmt
    Throw(e) => Throw(inline_into_expr(e))
    If(c, t, e) =>
      If(
        inline_into_expr(c),
        inline_block(t),
        match e {
          Some(b) => Some(inline_block(b))
          None => None
        },
      )
    While(c, body) => While(inline_into_expr(c), inline_block(body))
    DoWhile(c, body) => DoWhile(inline_into_expr(c), inline_block(body))
    With(c, body) => With(inline_into_expr(c), inline_block(body))
    For(init, cond, update, body) =>
      For(
        match init {
          Some(s) => Some(inline_into_stmt(s))
          None => None
        },
        match cond {
          Some(e) => Some(inline_into_expr(e))
          None => None
        },
        match update {
          Some(s) => Some(inline_into_stmt(s))
          None => None
        },
        inline_block(body),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(k, b, t, inline_into_expr(iter), inline_block(body))
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(k, b, t, inline_into_expr(iter), inline_block(body))
    ForIn(k, b, t, iter, body) =>
      ForIn(k, b, t, inline_into_expr(iter), inline_block(body))
    Switch(e, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(te) => Some(inline_into_expr(te))
            None => None
          },
          body: inline_block(c.body),
        })
      }
      Switch(inline_into_expr(e), new_cases)
    }
    Try(b, bnd, cb, fb) =>
      Try(
        inline_block(b),
        bnd,
        match cb {
          Some(blk) => Some(inline_block(blk))
          None => None
        },
        match fb {
          Some(blk) => Some(inline_block(blk))
          None => None
        },
      )
    Label(name, inner) => Label(name, inline_into_stmt(inner))
    Block(b) =>
      // The parser wraps `let a = 1, b = 2;` as
      // `Block({stmts:[Let(a, …), Let(b, …)]})` but emit unwraps
      // those bindings back into the parent scope. Running
      // `inline_block` on the wrapper would treat the wrapper as a
      // fresh scope, see only the inner two stmts, and inline the
      // first declarator into the second — even when the binding
      // is also referenced LATER in the parent (`if (!s) { …e… }`),
      // because the parent's stmts aren't visible from inside the
      // wrapper. Skip the recursive pass for multi-decl wrappers;
      // the parent `inline_block` flattens them just before its
      // own pass so the cross-statement use-counts come out right.
      if is_multi_decl_block(b) {
        Block(b)
      } else {
        Block(inline_block(b))
      }
    NativeClassStmt(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: inline_block(f.body) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(inline_block(b))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, inline_into_expr(sf.1)))
      }
      NativeClassStmt(
        { ..decl, methods: new_methods, static_field_inits: new_static_fields },
        new_ctor,
      )
    }
  }
}

///|
fn inline_into_expr(expr : @ast.TsExpr) -> @ast.TsExpr {
  match expr {
    FuncExpr(f) => {
      let new_body = inline_block(f.body)
      FuncExpr({ ..f, body: new_body })
    }
    ArrowFunc(params, ret, body, is_async) => {
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(inline_into_expr(e))
        ArrowBlock(b) => @ast.TsArrowBody::ArrowBlock(inline_block(b))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    BinOp(op, l, r) => BinOp(op, inline_into_expr(l), inline_into_expr(r))
    UnaryOp(op, inner) => UnaryOp(op, inline_into_expr(inner))
    Cond(c, t, e) =>
      Cond(inline_into_expr(c), inline_into_expr(t), inline_into_expr(e))
    Call(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_into_expr(a))
      }
      Call(name, new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_into_expr(a))
      }
      CallExpr(inline_into_expr(callee), new_args)
    }
    New(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_into_expr(a))
      }
      New(name, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_into_expr(a))
      }
      NewExpr(inline_into_expr(callee), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_into_expr(a))
      }
      MethodCall(inline_into_expr(recv), m, new_args)
    }
    PropAccess(recv, p) => PropAccess(inline_into_expr(recv), p)
    IndexAccess(recv, idx) =>
      IndexAccess(inline_into_expr(recv), inline_into_expr(idx))
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(inline_into_expr(i))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, inline_into_expr(ent.1)))
      }
      ObjectLit(new_entries)
    }
    ComputedProp(k, v) => ComputedProp(inline_into_expr(k), inline_into_expr(v))
    Spread(inner) => Spread(inline_into_expr(inner))
    Yield(Some(inner)) => Yield(Some(inline_into_expr(inner)))
    YieldStar(inner) => YieldStar(inline_into_expr(inner))
    Await(inner) => Await(inline_into_expr(inner))
    Seq(a, b) => Seq(inline_into_expr(a), inline_into_expr(b))
    AssignExpr(n, v) => AssignExpr(n, inline_into_expr(v))
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(inline_into_expr(t), op, inline_into_expr(v))
    AssignPattern(b, v) => AssignPattern(b, inline_into_expr(v))
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(inline_into_expr(recv), p, inline_into_expr(v))
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        inline_into_expr(recv),
        inline_into_expr(idx),
        inline_into_expr(v),
      )
    DynamicImport(spec, opts) => {
      let opts_f = match opts {
        Some(o) => Some(inline_into_expr(o))
        None => None
      }
      DynamicImport(inline_into_expr(spec), opts_f)
    }
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(inline_into_expr(e))
      }
      TaggedTemplate(inline_into_expr(tag), raw, cooked, new_exprs)
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(inline_into_expr(e))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(inline_into_expr(inner), ty)
    Satisfies(inner, ty) => Satisfies(inline_into_expr(inner), ty)
    NonNull(inner) => NonNull(inline_into_expr(inner))
    OptionalChain(inner) => OptionalChain(inline_into_expr(inner))
    NativeClassExpr(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: inline_block(f.body) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(inline_block(b))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, inline_into_expr(sf.1)))
      }
      NativeClassExpr(
        { ..decl, methods: new_methods, static_field_inits: new_static_fields },
        new_ctor,
      )
    }
    _ => expr
  }
}

///|
/// Single-use inlining pass on a flat statement list. Doesn't
/// recurse into nested blocks — `inline_block` does that first so
/// each pass sees an already-inlined inner scope.
fn inline_pass(
  input : Array[@ast.TsStmt],
  input_positions : Array[Int],
) -> @ast.TsBlock {
  // Reassignment / closure-capture tracking is per-scope, so we
  // collect once over the entire block. A single name reassigned
  // ANYWHERE (even in a nested function) disqualifies it from
  // inlining — that includes the rhs being moved.
  let reassigned : Map[String, Bool] = {}
  let captured : Map[String, Bool] = {}
  for s in input {
    collect_reassigned_stmt(s, reassigned)
    collect_captured_stmt(s, captured)
  }
  let out : Array[@ast.TsStmt] = []
  let out_positions : Array[Int] = []
  let has_positions = input_positions.length() == input.length()
  let mut i = 0
  while i < input.length() {
    let stmt = input[i]
    let candidate = match stmt {
      Let(@ast.TsBinding::Ident(name), _, rhs)
      | Const(@ast.TsBinding::Ident(name), _, rhs) =>
        if try_inline(name, rhs, input, i, reassigned, captured) {
          Some(name)
        } else {
          None
        }
      _ => None
    }
    match candidate {
      Some(name) => {
        // Replace the single Var(name) in the next stmt with the
        // rhs, drop the current decl, advance past both. Carry the
        // position of `next` (the surviving stmt) into the output.
        let rhs = match stmt {
          Let(_, _, r) | Const(_, _, r) => r
          _ => abort("unreachable")
        }
        let next = input[i + 1]
        let rewritten = substitute_stmt(next, name, rhs)
        out.push(rewritten)
        if has_positions {
          out_positions.push(input_positions[i + 1])
        }
        i = i + 2
      }
      None => {
        out.push(stmt)
        if has_positions {
          out_positions.push(input_positions[i])
        }
        i = i + 1
      }
    }
  }
  { stmts: out, stmt_positions: out_positions }
}

///|
fn try_inline(
  name : String,
  rhs : @ast.TsExpr,
  input : Array[@ast.TsStmt],
  i : Int,
  reassigned : Map[String, Bool],
  captured : Map[String, Bool],
) -> Bool {
  // Reassignment / closure capture of the binding itself.
  if reassigned.contains(name) || captured.contains(name) {
    return false
  }
  // The rhs's free variables: if any of them is reassigned in this
  // scope, we can't safely defer the rhs to the use site (its
  // value at the use point could differ from its value at the
  // decl point).
  let rhs_refs : Map[String, Bool] = {}
  collect_var_refs_in_expr_local(rhs, rhs_refs)
  for r in rhs_refs.keys() {
    if reassigned.contains(r) {
      return false
    }
  }
  // The use must be in the immediately-next statement and nowhere
  // else. Also: zero references inside any nested function body
  // (closure capture would change timing).
  if i + 1 >= input.length() {
    return false
  }
  let (uses_in_next, captures_in_next) = count_var_uses_stmt(
    input[i + 1],
    name,
    0,
    0,
    false,
  )
  if uses_in_next != 1 || captures_in_next != 0 {
    return false
  }
  // No other statement in this block (skipping i and i+1).
  for j in 0..<input.length() {
    if j == i || j == i + 1 {
      continue
    }
    let (local, nested) = count_var_uses_stmt(input[j], name, 0, 0, false)
    if local != 0 || nested != 0 {
      return false
    }
  }
  true
}

///|
/// Substitute every `Var(name)` reference inside `stmt` with `rhs`.
/// Only called when the caller has verified there's exactly one
/// such reference (and it isn't inside a nested function), so this
/// just runs the rewrite — no scope-tracking needed.
fn substitute_stmt(
  stmt : @ast.TsStmt,
  name : String,
  rhs : @ast.TsExpr,
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, init) => Var(b, t, substitute_expr(init, name, rhs))
    Let(b, t, init) => Let(b, t, substitute_expr(init, name, rhs))
    Const(b, t, init) => Const(b, t, substitute_expr(init, name, rhs))
    Assign(n, init) => Assign(n, substitute_expr(init, name, rhs))
    CompoundAssign(n, op, init) =>
      CompoundAssign(n, op, substitute_expr(init, name, rhs))
    IndexAssign(target, idx, val) =>
      IndexAssign(
        substitute_expr(target, name, rhs),
        substitute_expr(idx, name, rhs),
        substitute_expr(val, name, rhs),
      )
    PropAssign(target, prop, val) =>
      PropAssign(
        substitute_expr(target, name, rhs),
        prop,
        substitute_expr(val, name, rhs),
      )
    Expr(e) => Expr(substitute_expr(e, name, rhs))
    Return(Some(e)) => Return(Some(substitute_expr(e, name, rhs)))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => stmt
    Throw(e) => Throw(substitute_expr(e, name, rhs))
    If(c, t, e) =>
      // Recurse into then/else bodies too — the use site we
      // verified is unique might live there, and the previous
      // "rewrite condition only, leave bodies alone" emitted a
      // bare reference with the declaration already dropped.
      // Safe for `if` because the body runs at most once
      // (single-evaluation invariant preserved). Loops still
      // bail out via `count_var_uses_stmt`'s nested-tagging.
      If(
        substitute_expr(c, name, rhs),
        substitute_block(t, name, rhs),
        match e {
          Some(b) => Some(substitute_block(b, name, rhs))
          None => None
        },
      )
    While(c, body) => While(substitute_expr(c, name, rhs), body)
    DoWhile(c, body) => DoWhile(substitute_expr(c, name, rhs), body)
    For(init, cond, update, body) =>
      For(
        match init {
          Some(s) => Some(substitute_stmt(s, name, rhs))
          None => None
        },
        match cond {
          Some(e) => Some(substitute_expr(e, name, rhs))
          None => None
        },
        match update {
          Some(s) => Some(substitute_stmt(s, name, rhs))
          None => None
        },
        body,
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(k, b, t, substitute_expr(iter, name, rhs), body)
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(k, b, t, substitute_expr(iter, name, rhs), body)
    ForIn(k, b, t, iter, body) =>
      ForIn(k, b, t, substitute_expr(iter, name, rhs), body)
    Switch(e, cases) => Switch(substitute_expr(e, name, rhs), cases)
    Label(lname, inner) => Label(lname, substitute_stmt(inner, name, rhs))
    NativeClassStmt(decl, ctor) => {
      let new_base = match decl.base_expr {
        Some(b) => Some(substitute_expr(b, name, rhs))
        None => None
      }
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: substitute_block(f.body, name, rhs) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(substitute_block(b, name, rhs))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, substitute_expr(sf.1, name, rhs)))
      }
      NativeClassStmt(
        { ..decl, base_expr: new_base, methods: new_methods, static_field_inits: new_static_fields },
        new_ctor,
      )
    }
    _ => stmt
  }
}

///|
/// Recurse `substitute_stmt` over an entire block, returning a
/// rebuilt block. Used by branch bodies (`if` / `else`) where the
/// `count_var_uses` machinery already proved the rhs may safely
/// move inside the body (single evaluation).
fn substitute_block(
  block : @ast.TsBlock,
  name : String,
  rhs : @ast.TsExpr,
) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(substitute_stmt(s, name, rhs))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn substitute_expr(
  expr : @ast.TsExpr,
  name : String,
  rhs : @ast.TsExpr,
) -> @ast.TsExpr {
  match expr {
    Var(n) => if n == name { rhs } else { expr }
    Call(n, args) =>
      if n == name {
        // Rare: would mean rhs is being called as a function. If
        // rhs is itself a `Var(other)` we can rewrite to
        // `Call(other, args)`; otherwise fall back to `CallExpr`.
        let new_args : Array[@ast.TsExpr] = []
        for a in args {
          new_args.push(substitute_expr(a, name, rhs))
        }
        match rhs {
          Var(other) => Call(other, new_args)
          _ => CallExpr(rhs, new_args)
        }
      } else {
        let new_args : Array[@ast.TsExpr] = []
        for a in args {
          new_args.push(substitute_expr(a, name, rhs))
        }
        Call(n, new_args)
      }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_expr(a, name, rhs))
      }
      CallExpr(substitute_expr(callee, name, rhs), new_args)
    }
    BinOp(op, l, r) =>
      BinOp(op, substitute_expr(l, name, rhs), substitute_expr(r, name, rhs))
    UnaryOp(op, inner) => UnaryOp(op, substitute_expr(inner, name, rhs))
    Cond(c, t, e) =>
      Cond(
        substitute_expr(c, name, rhs),
        substitute_expr(t, name, rhs),
        substitute_expr(e, name, rhs),
      )
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_expr(a, name, rhs))
      }
      MethodCall(substitute_expr(recv, name, rhs), m, new_args)
    }
    New(n, args) =>
      if n == name {
        // The binding being inlined is used as a constructor — emit
        // `new <rhs>(args)`. When `rhs` is itself a `Var(other)` we
        // can keep the tighter `New(other, args)` shape; otherwise
        // fall back to `NewExpr(rhs, args)` which accepts any
        // expression as the callee.
        let new_args : Array[@ast.TsExpr] = []
        for a in args {
          new_args.push(substitute_expr(a, name, rhs))
        }
        match rhs {
          Var(other) => New(other, new_args)
          _ => NewExpr(rhs, new_args)
        }
      } else {
        let new_args : Array[@ast.TsExpr] = []
        for a in args {
          new_args.push(substitute_expr(a, name, rhs))
        }
        New(n, new_args)
      }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_expr(a, name, rhs))
      }
      NewExpr(substitute_expr(callee, name, rhs), new_args)
    }
    PropAccess(recv, p) => PropAccess(substitute_expr(recv, name, rhs), p)
    IndexAccess(recv, idx) =>
      IndexAccess(
        substitute_expr(recv, name, rhs),
        substitute_expr(idx, name, rhs),
      )
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(substitute_expr(i, name, rhs))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, substitute_expr(ent.1, name, rhs)))
      }
      ObjectLit(new_entries)
    }
    ComputedProp(k, v) =>
      ComputedProp(substitute_expr(k, name, rhs), substitute_expr(v, name, rhs))
    Spread(inner) => Spread(substitute_expr(inner, name, rhs))
    Await(inner) => Await(substitute_expr(inner, name, rhs))
    YieldStar(inner) => YieldStar(substitute_expr(inner, name, rhs))
    Yield(Some(inner)) => Yield(Some(substitute_expr(inner, name, rhs)))
    Seq(a, b) =>
      Seq(substitute_expr(a, name, rhs), substitute_expr(b, name, rhs))
    AssignExpr(n, v) => AssignExpr(n, substitute_expr(v, name, rhs))
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(
        substitute_expr(t, name, rhs),
        op,
        substitute_expr(v, name, rhs),
      )
    AssignPattern(b, v) => AssignPattern(b, substitute_expr(v, name, rhs))
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(
        substitute_expr(recv, name, rhs),
        p,
        substitute_expr(v, name, rhs),
      )
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        substitute_expr(recv, name, rhs),
        substitute_expr(idx, name, rhs),
        substitute_expr(v, name, rhs),
      )
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(substitute_expr(e, name, rhs))
      }
      TaggedTemplate(substitute_expr(tag, name, rhs), raw, cooked, new_exprs)
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(substitute_expr(e, name, rhs))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(substitute_expr(inner, name, rhs), ty)
    Satisfies(inner, ty) => Satisfies(substitute_expr(inner, name, rhs), ty)
    NonNull(inner) => NonNull(substitute_expr(inner, name, rhs))
    OptionalChain(inner) => OptionalChain(substitute_expr(inner, name, rhs))
    NativeClassExpr(decl, ctor) => {
      let new_base = match decl.base_expr {
        Some(b) => Some(substitute_expr(b, name, rhs))
        None => None
      }
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: substitute_block(f.body, name, rhs) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(substitute_block(b, name, rhs))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, substitute_expr(sf.1, name, rhs)))
      }
      NativeClassExpr(
        { ..decl, base_expr: new_base, methods: new_methods, static_field_inits: new_static_fields },
        new_ctor,
      )
    }
    _ => expr
  }
}

///|
/// Count Var(name) references inside `stmt`, splitting local refs
/// (in the same scope) from refs inside nested function / arrow
/// bodies. Local + nested are returned via out-parameters so the
/// caller can decide whether the binding is closure-captured.
fn count_var_uses_stmt(
  stmt : @ast.TsStmt,
  name : String,
  local : Int,
  nested : Int,
  inside_func : Bool,
) -> (Int, Int) {
  let mut l = local
  let mut n = nested
  match stmt {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) => {
      let (l2, n2) = count_var_uses_expr(e, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
    }
    Assign(n_, e) => {
      if n_ == name {
        l = l + 1
      }
      let (l2, n2) = count_var_uses_expr(e, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
    }
    CompoundAssign(n_, _, e) => {
      if n_ == name {
        l = l + 1
      }
      let (l2, n2) = count_var_uses_expr(e, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
    }
    IndexAssign(t, idx, v) => {
      let (l2, n2) = count_var_uses_expr(t, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      let (l3, n3) = count_var_uses_expr(idx, name, 0, 0, inside_func)
      l = l + l3
      n = n + n3
      let (l4, n4) = count_var_uses_expr(v, name, 0, 0, inside_func)
      l = l + l4
      n = n + n4
    }
    PropAssign(t, _, v) => {
      let (l2, n2) = count_var_uses_expr(t, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      let (l3, n3) = count_var_uses_expr(v, name, 0, 0, inside_func)
      l = l + l3
      n = n + n3
    }
    Expr(e) | Throw(e) => {
      let (l2, n2) = count_var_uses_expr(e, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
    }
    Return(Some(e)) => {
      let (l2, n2) = count_var_uses_expr(e, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
    }
    If(c, t, e) => {
      let (l2, n2) = count_var_uses_expr(c, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      let (l3, n3) = count_var_uses_block(t, name, inside_func)
      l = l + l3
      n = n + n3
      match e {
        Some(b) => {
          let (l4, n4) = count_var_uses_block(b, name, inside_func)
          l = l + l4
          n = n + n4
        }
        None => ()
      }
    }
    While(c, body) | DoWhile(c, body) | With(c, body) => {
      let (l2, n2) = count_var_uses_expr(c, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      // Loop body uses are counted as "nested" so single-use
      // inlining refuses to fold a declaration's rhs into a body
      // that would re-evaluate it each iteration. The semantics of
      // `const X = expr; while (…) { use(X) }` keep `expr` evaluated
      // exactly once; collapsing X into the body would lift that to
      // N evaluations.
      let (l3, n3) = count_var_uses_block(body, name, true)
      l = l + l3
      n = n + n3
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => {
          let (l2, n2) = count_var_uses_stmt(s, name, 0, 0, inside_func)
          l = l + l2
          n = n + n2
        }
        None => ()
      }
      match cond {
        Some(e) => {
          let (l2, n2) = count_var_uses_expr(e, name, 0, 0, inside_func)
          l = l + l2
          n = n + n2
        }
        None => ()
      }
      match update {
        Some(s) => {
          let (l2, n2) = count_var_uses_stmt(s, name, 0, 0, inside_func)
          l = l + l2
          n = n + n2
        }
        None => ()
      }
      // Same loop-body protection as `While` / `DoWhile`: refuse
      // inlining when the use sits inside the iterated body.
      let (l2, n2) = count_var_uses_block(body, name, true)
      l = l + l2
      n = n + n2
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      let (l2, n2) = count_var_uses_expr(iter, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      let (l3, n3) = count_var_uses_block(body, name, true)
      l = l + l3
      n = n + n3
    }
    Switch(e, cases) => {
      let (l2, n2) = count_var_uses_expr(e, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      for c in cases {
        match c.test_expr {
          Some(te) => {
            let (l3, n3) = count_var_uses_expr(te, name, 0, 0, inside_func)
            l = l + l3
            n = n + n3
          }
          None => ()
        }
        let (l3, n3) = count_var_uses_block(c.body, name, inside_func)
        l = l + l3
        n = n + n3
      }
    }
    Try(b, _, cb, fb) => {
      let (l2, n2) = count_var_uses_block(b, name, inside_func)
      l = l + l2
      n = n + n2
      match cb {
        Some(blk) => {
          let (l3, n3) = count_var_uses_block(blk, name, inside_func)
          l = l + l3
          n = n + n3
        }
        None => ()
      }
      match fb {
        Some(blk) => {
          let (l3, n3) = count_var_uses_block(blk, name, inside_func)
          l = l + l3
          n = n + n3
        }
        None => ()
      }
    }
    Label(_, inner) => {
      let (l2, n2) = count_var_uses_stmt(inner, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
    }
    Block(b) => {
      let (l2, n2) = count_var_uses_block(b, name, inside_func)
      l = l + l2
      n = n + n2
    }
    NativeClassStmt(decl, ctor) => {
      // All uses inside a class body are "nested" (they live inside
      // function scopes — constructor / method bodies / static inits).
      // Treat them as nested so single-use inlining never moves a
      // binding's rhs into a class body.
      let walk_block_nested = fn(blk : @ast.TsBlock) {
        let (l2, n2) = count_var_uses_block(blk, name, true)
        l = l + l2
        n = n + n2
      }
      match ctor {
        Some(f) => walk_block_nested(f.body)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => walk_block_nested(b)
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        let (l2, n2) = count_var_uses_expr(sf.1, name, 0, 0, true)
        l = l + l2
        n = n + n2
      }
    }
    _ => ()
  }
  (l, n)
}

///|
fn count_var_uses_block(
  block : @ast.TsBlock,
  name : String,
  inside_func : Bool,
) -> (Int, Int) {
  let mut l = 0
  let mut n = 0
  for s in block.stmts {
    let (l2, n2) = count_var_uses_stmt(s, name, 0, 0, inside_func)
    l = l + l2
    n = n + n2
  }
  (l, n)
}

///|
fn count_var_uses_expr(
  expr : @ast.TsExpr,
  name : String,
  local : Int,
  nested : Int,
  inside_func : Bool,
) -> (Int, Int) {
  let mut l = local
  let mut n = nested
  match expr {
    Var(v) => if v == name { if inside_func { n = n + 1 } else { l = l + 1 } }
    Call(v, args) => {
      if v == name {
        if inside_func {
          n = n + 1
        } else {
          l = l + 1
        }
      }
      for a in args {
        let (l2, n2) = count_var_uses_expr(a, name, 0, 0, inside_func)
        l = l + l2
        n = n + n2
      }
    }
    CallExpr(callee, args) => {
      let (l2, n2) = count_var_uses_expr(callee, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      for a in args {
        let (l3, n3) = count_var_uses_expr(a, name, 0, 0, inside_func)
        l = l + l3
        n = n + n3
      }
    }
    New(v, args) => {
      if v == name {
        if inside_func {
          n = n + 1
        } else {
          l = l + 1
        }
      }
      for a in args {
        let (l2, n2) = count_var_uses_expr(a, name, 0, 0, inside_func)
        l = l + l2
        n = n + n2
      }
    }
    NewExpr(callee, args) => {
      let (l2, n2) = count_var_uses_expr(callee, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      for a in args {
        let (l3, n3) = count_var_uses_expr(a, name, 0, 0, inside_func)
        l = l + l3
        n = n + n3
      }
    }
    MethodCall(recv, _, args) => {
      let (l2, n2) = count_var_uses_expr(recv, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      for a in args {
        let (l3, n3) = count_var_uses_expr(a, name, 0, 0, inside_func)
        l = l + l3
        n = n + n3
      }
    }
    BinOp(_, le, re) => {
      let (l2, n2) = count_var_uses_expr(le, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      let (l3, n3) = count_var_uses_expr(re, name, 0, 0, inside_func)
      l = l + l3
      n = n + n3
    }
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | YieldStar(inner)
    | As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner) => {
      let (l2, n2) = count_var_uses_expr(inner, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
    }
    Yield(Some(inner)) => {
      let (l2, n2) = count_var_uses_expr(inner, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
    }
    Cond(c, t, e) => {
      let (l2, n2) = count_var_uses_expr(c, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      let (l3, n3) = count_var_uses_expr(t, name, 0, 0, inside_func)
      l = l + l3
      n = n + n3
      let (l4, n4) = count_var_uses_expr(e, name, 0, 0, inside_func)
      l = l + l4
      n = n + n4
    }
    ArrayLit(items) =>
      for it in items {
        let (l2, n2) = count_var_uses_expr(it, name, 0, 0, inside_func)
        l = l + l2
        n = n + n2
      }
    ObjectLit(entries) =>
      for ent in entries {
        let (l2, n2) = count_var_uses_expr(ent.1, name, 0, 0, inside_func)
        l = l + l2
        n = n + n2
      }
    ComputedProp(k, v) => {
      let (l2, n2) = count_var_uses_expr(k, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      let (l3, n3) = count_var_uses_expr(v, name, 0, 0, inside_func)
      l = l + l3
      n = n + n3
    }
    IndexAccess(recv, idx) => {
      let (l2, n2) = count_var_uses_expr(recv, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      let (l3, n3) = count_var_uses_expr(idx, name, 0, 0, inside_func)
      l = l + l3
      n = n + n3
    }
    PropAccess(recv, _) => {
      let (l2, n2) = count_var_uses_expr(recv, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
    }
    AssignExpr(v, val) => {
      if v == name {
        if inside_func {
          n = n + 1
        } else {
          l = l + 1
        }
      }
      let (l2, n2) = count_var_uses_expr(val, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
    }
    CompoundAssignExpr(t, _, v) => {
      let (l2, n2) = count_var_uses_expr(t, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      let (l3, n3) = count_var_uses_expr(v, name, 0, 0, inside_func)
      l = l + l3
      n = n + n3
    }
    AssignPattern(_, v) => {
      let (l2, n2) = count_var_uses_expr(v, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
    }
    PropAssignExpr(recv, _, v) => {
      let (l2, n2) = count_var_uses_expr(recv, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      let (l3, n3) = count_var_uses_expr(v, name, 0, 0, inside_func)
      l = l + l3
      n = n + n3
    }
    IndexAssignExpr(recv, idx, v) => {
      let (l2, n2) = count_var_uses_expr(recv, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      let (l3, n3) = count_var_uses_expr(idx, name, 0, 0, inside_func)
      l = l + l3
      n = n + n3
      let (l4, n4) = count_var_uses_expr(v, name, 0, 0, inside_func)
      l = l + l4
      n = n + n4
    }
    Seq(a, b) => {
      let (l2, n2) = count_var_uses_expr(a, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      let (l3, n3) = count_var_uses_expr(b, name, 0, 0, inside_func)
      l = l + l3
      n = n + n3
    }
    ArrowFunc(_, _, body, _) =>
      // Crossing a function boundary: refs inside count as nested
      // (closure capture).
      match body {
        ArrowExpr(e) => {
          let (l2, n2) = count_var_uses_expr(e, name, 0, 0, true)
          l = l + l2
          n = n + n2
        }
        ArrowBlock(b) => {
          let (l2, n2) = count_var_uses_block(b, name, true)
          l = l + l2
          n = n + n2
        }
      }
    FuncExpr(f) => {
      let (l2, n2) = count_var_uses_block(f.body, name, true)
      l = l + l2
      n = n + n2
    }
    DynamicImport(spec, opts) => {
      let (l2, n2) = count_var_uses_expr(spec, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      match opts {
        Some(o) => {
          let (l3, n3) = count_var_uses_expr(o, name, 0, 0, inside_func)
          l = l + l3
          n = n + n3
        }
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      let (l2, n2) = count_var_uses_expr(tag, name, 0, 0, inside_func)
      l = l + l2
      n = n + n2
      for e in exprs {
        let (l3, n3) = count_var_uses_expr(e, name, 0, 0, inside_func)
        l = l + l3
        n = n + n3
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        let (l2, n2) = count_var_uses_expr(e, name, 0, 0, inside_func)
        l = l + l2
        n = n + n2
      }
    NativeClassExpr(decl, ctor) => {
      // Class bodies are nested function scopes — count as nested.
      let walk_block_nested = fn(blk : @ast.TsBlock) {
        let (l2, n2) = count_var_uses_block(blk, name, true)
        l = l + l2
        n = n + n2
      }
      match ctor {
        Some(f) => walk_block_nested(f.body)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => walk_block_nested(b)
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        let (l2, n2) = count_var_uses_expr(sf.1, name, 0, 0, inside_func)
        l = l + l2
        n = n + n2
      }
    }
    _ => ()
  }
  (l, n)
}

///|
/// Collect names reassigned anywhere in / under this statement.
fn collect_reassigned_stmt(stmt : @ast.TsStmt, out : Map[String, Bool]) -> Unit {
  match stmt {
    Assign(n, _) | CompoundAssign(n, _, _) => out[n] = true
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) | Throw(e) =>
      collect_reassigned_expr(e, out)
    Return(Some(e)) => collect_reassigned_expr(e, out)
    If(c, t, e) => {
      collect_reassigned_expr(c, out)
      collect_reassigned_block(t, out)
      match e {
        Some(b) => collect_reassigned_block(b, out)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) | With(c, b) => {
      collect_reassigned_expr(c, out)
      collect_reassigned_block(b, out)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => collect_reassigned_stmt(s, out)
        None => ()
      }
      match cond {
        Some(e) => collect_reassigned_expr(e, out)
        None => ()
      }
      match update {
        Some(s) => collect_reassigned_stmt(s, out)
        None => ()
      }
      collect_reassigned_block(body, out)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      collect_reassigned_expr(iter, out)
      collect_reassigned_block(body, out)
    }
    Switch(e, cases) => {
      collect_reassigned_expr(e, out)
      for c in cases {
        match c.test_expr {
          Some(te) => collect_reassigned_expr(te, out)
          None => ()
        }
        collect_reassigned_block(c.body, out)
      }
    }
    Try(b, _, cb, fb) => {
      collect_reassigned_block(b, out)
      match cb {
        Some(blk) => collect_reassigned_block(blk, out)
        None => ()
      }
      match fb {
        Some(blk) => collect_reassigned_block(blk, out)
        None => ()
      }
    }
    Label(_, inner) => collect_reassigned_stmt(inner, out)
    Block(b) => collect_reassigned_block(b, out)
    NativeClassStmt(decl, ctor) => {
      match ctor {
        Some(f) => collect_reassigned_block(f.body, out)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => collect_reassigned_block(b, out)
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        collect_reassigned_expr(sf.1, out)
      }
    }
    _ => ()
  }
}

///|
fn collect_reassigned_block(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    collect_reassigned_stmt(s, out)
  }
}

///|
fn collect_reassigned_binding(
  binding : @ast.TsBinding,
  out : Map[String, Bool],
) -> Unit {
  match binding {
    Ident(n) => out[n] = true
    Array(ab) => {
      for elem in ab.items {
        match elem {
          Some(be) => collect_reassigned_binding(be.binding, out)
          None => ()
        }
      }
      match ab.rest {
        Some(r) => collect_reassigned_binding(r, out)
        None => ()
      }
    }
    Object(ob) => {
      for prop in ob.props {
        collect_reassigned_binding(prop.binding, out)
      }
      match ob.rest {
        Some(r) => out[r] = true
        None => ()
      }
    }
    Target(_) => ()
  }
}

///|
fn collect_reassigned_expr(expr : @ast.TsExpr, out : Map[String, Bool]) -> Unit {
  match expr {
    AssignExpr(n, v) => {
      out[n] = true
      collect_reassigned_expr(v, out)
    }
    UnaryOp(op, inner) => {
      match (op, inner) {
        (PreInc, Var(n))
        | (PreDec, Var(n))
        | (PostInc, Var(n))
        | (PostDec, Var(n)) => out[n] = true
        _ => ()
      }
      collect_reassigned_expr(inner, out)
    }
    CompoundAssignExpr(t, _, v) => {
      match t {
        Var(n) => out[n] = true
        _ => ()
      }
      collect_reassigned_expr(t, out)
      collect_reassigned_expr(v, out)
    }
    BinOp(_, l, r) => {
      collect_reassigned_expr(l, out)
      collect_reassigned_expr(r, out)
    }
    Cond(c, t, e) => {
      collect_reassigned_expr(c, out)
      collect_reassigned_expr(t, out)
      collect_reassigned_expr(e, out)
    }
    Call(_, args) | New(_, args) =>
      for a in args {
        collect_reassigned_expr(a, out)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_reassigned_expr(callee, out)
      for a in args {
        collect_reassigned_expr(a, out)
      }
    }
    MethodCall(recv, _, args) => {
      collect_reassigned_expr(recv, out)
      for a in args {
        collect_reassigned_expr(a, out)
      }
    }
    PropAccess(recv, _) => collect_reassigned_expr(recv, out)
    IndexAccess(recv, idx) => {
      collect_reassigned_expr(recv, out)
      collect_reassigned_expr(idx, out)
    }
    ArrayLit(items) =>
      for it in items {
        collect_reassigned_expr(it, out)
      }
    ObjectLit(entries) =>
      for ent in entries {
        collect_reassigned_expr(ent.1, out)
      }
    ComputedProp(k, v) => {
      collect_reassigned_expr(k, out)
      collect_reassigned_expr(v, out)
    }
    Spread(inner)
    | Await(inner)
    | YieldStar(inner)
    | As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner) => collect_reassigned_expr(inner, out)
    Yield(Some(inner)) => collect_reassigned_expr(inner, out)
    Seq(a, b) => {
      collect_reassigned_expr(a, out)
      collect_reassigned_expr(b, out)
    }
    AssignPattern(b, v) => {
      // Destructuring assignment `[r, n] = i` reassigns every
      // `Ident` in the binding — that's the whole point of the
      // expression. Skipping the binding lets inline drop the
      // declaration of `n` thinking it's never written, breaking
      // the assignment site.
      collect_reassigned_binding(b, out)
      collect_reassigned_expr(v, out)
    }
    PropAssignExpr(recv, _, v) => {
      collect_reassigned_expr(recv, out)
      collect_reassigned_expr(v, out)
    }
    IndexAssignExpr(recv, idx, v) => {
      collect_reassigned_expr(recv, out)
      collect_reassigned_expr(idx, out)
      collect_reassigned_expr(v, out)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => collect_reassigned_expr(e, out)
        ArrowBlock(b) => collect_reassigned_block(b, out)
      }
    FuncExpr(f) => collect_reassigned_block(f.body, out)
    DynamicImport(spec, opts) => {
      collect_reassigned_expr(spec, out)
      match opts {
        Some(o) => collect_reassigned_expr(o, out)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      collect_reassigned_expr(tag, out)
      for e in exprs {
        collect_reassigned_expr(e, out)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_reassigned_expr(e, out)
      }
    NativeClassExpr(decl, ctor) => {
      match ctor {
        Some(f) => collect_reassigned_block(f.body, out)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => collect_reassigned_block(b, out)
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        collect_reassigned_expr(sf.1, out)
      }
    }
    _ => ()
  }
}

///|
/// Names referenced inside any nested function body. The
/// distinction matters because moving a `const X = …; expr(X)`
/// rewrite changes when `X` is captured if `X` is referenced from
/// a closure — even if the closure isn't called yet.
fn collect_captured_stmt(stmt : @ast.TsStmt, out : Map[String, Bool]) -> Unit {
  match stmt {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) | Throw(e) =>
      collect_captured_expr(e, out, false)
    Assign(_, e) | CompoundAssign(_, _, e) =>
      collect_captured_expr(e, out, false)
    Return(Some(e)) => collect_captured_expr(e, out, false)
    If(c, t, e) => {
      collect_captured_expr(c, out, false)
      collect_captured_block(t, out, false)
      match e {
        Some(b) => collect_captured_block(b, out, false)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) | With(c, b) => {
      collect_captured_expr(c, out, false)
      collect_captured_block(b, out, false)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => collect_captured_stmt(s, out)
        None => ()
      }
      match cond {
        Some(e) => collect_captured_expr(e, out, false)
        None => ()
      }
      match update {
        Some(s) => collect_captured_stmt(s, out)
        None => ()
      }
      collect_captured_block(body, out, false)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      collect_captured_expr(iter, out, false)
      collect_captured_block(body, out, false)
    }
    Switch(e, cases) => {
      collect_captured_expr(e, out, false)
      for c in cases {
        match c.test_expr {
          Some(te) => collect_captured_expr(te, out, false)
          None => ()
        }
        collect_captured_block(c.body, out, false)
      }
    }
    Try(b, _, cb, fb) => {
      collect_captured_block(b, out, false)
      match cb {
        Some(blk) => collect_captured_block(blk, out, false)
        None => ()
      }
      match fb {
        Some(blk) => collect_captured_block(blk, out, false)
        None => ()
      }
    }
    Label(_, inner) => collect_captured_stmt(inner, out)
    Block(b) => collect_captured_block(b, out, false)
    NativeClassStmt(decl, ctor) => {
      // Class method / constructor bodies are nested function scopes.
      match ctor {
        Some(f) => collect_captured_block(f.body, out, true)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => collect_captured_block(b, out, true)
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        collect_captured_expr(sf.1, out, false)
      }
    }
    _ => ()
  }
}

///|
fn collect_captured_block(
  block : @ast.TsBlock,
  out : Map[String, Bool],
  inside_func : Bool,
) -> Unit {
  for s in block.stmts {
    collect_captured_block_stmt(s, out, inside_func)
  }
}

///|
fn collect_captured_block_stmt(
  stmt : @ast.TsStmt,
  out : Map[String, Bool],
  inside_func : Bool,
) -> Unit {
  match stmt {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) | Throw(e) =>
      collect_captured_expr(e, out, inside_func)
    Assign(n, e) => {
      if inside_func {
        out[n] = true
      }
      collect_captured_expr(e, out, inside_func)
    }
    CompoundAssign(n, _, e) => {
      if inside_func {
        out[n] = true
      }
      collect_captured_expr(e, out, inside_func)
    }
    Return(Some(e)) => collect_captured_expr(e, out, inside_func)
    If(c, t, e) => {
      collect_captured_expr(c, out, inside_func)
      collect_captured_block(t, out, inside_func)
      match e {
        Some(b) => collect_captured_block(b, out, inside_func)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) | With(c, b) => {
      collect_captured_expr(c, out, inside_func)
      collect_captured_block(b, out, inside_func)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => collect_captured_block_stmt(s, out, inside_func)
        None => ()
      }
      match cond {
        Some(e) => collect_captured_expr(e, out, inside_func)
        None => ()
      }
      match update {
        Some(s) => collect_captured_block_stmt(s, out, inside_func)
        None => ()
      }
      collect_captured_block(body, out, inside_func)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      collect_captured_expr(iter, out, inside_func)
      collect_captured_block(body, out, inside_func)
    }
    Switch(e, cases) => {
      collect_captured_expr(e, out, inside_func)
      for c in cases {
        match c.test_expr {
          Some(te) => collect_captured_expr(te, out, inside_func)
          None => ()
        }
        collect_captured_block(c.body, out, inside_func)
      }
    }
    Try(b, _, cb, fb) => {
      collect_captured_block(b, out, inside_func)
      match cb {
        Some(blk) => collect_captured_block(blk, out, inside_func)
        None => ()
      }
      match fb {
        Some(blk) => collect_captured_block(blk, out, inside_func)
        None => ()
      }
    }
    Label(_, inner) => collect_captured_block_stmt(inner, out, inside_func)
    Block(b) => collect_captured_block(b, out, inside_func)
    _ => ()
  }
}

///|
fn collect_captured_expr(
  expr : @ast.TsExpr,
  out : Map[String, Bool],
  inside_func : Bool,
) -> Unit {
  match expr {
    Var(n) => if inside_func { out[n] = true }
    Call(n, args) => {
      if inside_func {
        out[n] = true
      }
      for a in args {
        collect_captured_expr(a, out, inside_func)
      }
    }
    CallExpr(callee, args) => {
      collect_captured_expr(callee, out, inside_func)
      for a in args {
        collect_captured_expr(a, out, inside_func)
      }
    }
    New(n, args) => {
      if inside_func {
        out[n] = true
      }
      for a in args {
        collect_captured_expr(a, out, inside_func)
      }
    }
    NewExpr(callee, args) => {
      collect_captured_expr(callee, out, inside_func)
      for a in args {
        collect_captured_expr(a, out, inside_func)
      }
    }
    MethodCall(recv, _, args) => {
      collect_captured_expr(recv, out, inside_func)
      for a in args {
        collect_captured_expr(a, out, inside_func)
      }
    }
    BinOp(_, l, r) => {
      collect_captured_expr(l, out, inside_func)
      collect_captured_expr(r, out, inside_func)
    }
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | YieldStar(inner)
    | As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner) => collect_captured_expr(inner, out, inside_func)
    Yield(Some(inner)) => collect_captured_expr(inner, out, inside_func)
    Cond(c, t, e) => {
      collect_captured_expr(c, out, inside_func)
      collect_captured_expr(t, out, inside_func)
      collect_captured_expr(e, out, inside_func)
    }
    ArrayLit(items) =>
      for it in items {
        collect_captured_expr(it, out, inside_func)
      }
    ObjectLit(entries) =>
      for ent in entries {
        collect_captured_expr(ent.1, out, inside_func)
      }
    ComputedProp(k, v) => {
      collect_captured_expr(k, out, inside_func)
      collect_captured_expr(v, out, inside_func)
    }
    IndexAccess(recv, idx) => {
      collect_captured_expr(recv, out, inside_func)
      collect_captured_expr(idx, out, inside_func)
    }
    PropAccess(recv, _) => collect_captured_expr(recv, out, inside_func)
    AssignExpr(n, v) => {
      if inside_func {
        out[n] = true
      }
      collect_captured_expr(v, out, inside_func)
    }
    CompoundAssignExpr(t, _, v) => {
      collect_captured_expr(t, out, inside_func)
      collect_captured_expr(v, out, inside_func)
    }
    AssignPattern(_, v) => collect_captured_expr(v, out, inside_func)
    PropAssignExpr(recv, _, v) => {
      collect_captured_expr(recv, out, inside_func)
      collect_captured_expr(v, out, inside_func)
    }
    IndexAssignExpr(recv, idx, v) => {
      collect_captured_expr(recv, out, inside_func)
      collect_captured_expr(idx, out, inside_func)
      collect_captured_expr(v, out, inside_func)
    }
    Seq(a, b) => {
      collect_captured_expr(a, out, inside_func)
      collect_captured_expr(b, out, inside_func)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => collect_captured_expr(e, out, true)
        ArrowBlock(b) => collect_captured_block(b, out, true)
      }
    FuncExpr(f) => collect_captured_block(f.body, out, true)
    DynamicImport(spec, opts) => {
      collect_captured_expr(spec, out, inside_func)
      match opts {
        Some(o) => collect_captured_expr(o, out, inside_func)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      collect_captured_expr(tag, out, inside_func)
      for e in exprs {
        collect_captured_expr(e, out, inside_func)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_captured_expr(e, out, inside_func)
      }
    NativeClassExpr(decl, ctor) => {
      // Class method / constructor bodies are nested function scopes.
      match ctor {
        Some(f) => collect_captured_block(f.body, out, true)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => collect_captured_block(b, out, true)
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        collect_captured_expr(sf.1, out, inside_func)
      }
    }
    _ => ()
  }
}

///|
/// Used to gather the rhs's free variables so we can verify none
/// of them are reassigned in the enclosing scope. Doesn't cross
/// function boundaries because closures bind their references to
/// the bindings, not the rhs's value — capturing freely is fine.
fn collect_var_refs_in_expr_local(
  expr : @ast.TsExpr,
  out : Map[String, Bool],
) -> Unit {
  match expr {
    Var(n) => out[n] = true
    Call(n, args) => {
      out[n] = true
      for a in args {
        collect_var_refs_in_expr_local(a, out)
      }
    }
    CallExpr(callee, args) => {
      collect_var_refs_in_expr_local(callee, out)
      for a in args {
        collect_var_refs_in_expr_local(a, out)
      }
    }
    New(n, args) => {
      out[n] = true
      for a in args {
        collect_var_refs_in_expr_local(a, out)
      }
    }
    NewExpr(callee, args) => {
      collect_var_refs_in_expr_local(callee, out)
      for a in args {
        collect_var_refs_in_expr_local(a, out)
      }
    }
    MethodCall(recv, _, args) => {
      collect_var_refs_in_expr_local(recv, out)
      for a in args {
        collect_var_refs_in_expr_local(a, out)
      }
    }
    BinOp(_, l, r) => {
      collect_var_refs_in_expr_local(l, out)
      collect_var_refs_in_expr_local(r, out)
    }
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | YieldStar(inner)
    | As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner) => collect_var_refs_in_expr_local(inner, out)
    Yield(Some(inner)) => collect_var_refs_in_expr_local(inner, out)
    Cond(c, t, e) => {
      collect_var_refs_in_expr_local(c, out)
      collect_var_refs_in_expr_local(t, out)
      collect_var_refs_in_expr_local(e, out)
    }
    ArrayLit(items) =>
      for it in items {
        collect_var_refs_in_expr_local(it, out)
      }
    ObjectLit(entries) =>
      for ent in entries {
        collect_var_refs_in_expr_local(ent.1, out)
      }
    ComputedProp(k, v) => {
      collect_var_refs_in_expr_local(k, out)
      collect_var_refs_in_expr_local(v, out)
    }
    IndexAccess(recv, idx) => {
      collect_var_refs_in_expr_local(recv, out)
      collect_var_refs_in_expr_local(idx, out)
    }
    PropAccess(recv, _) => collect_var_refs_in_expr_local(recv, out)
    AssignExpr(n, v) => {
      out[n] = true
      collect_var_refs_in_expr_local(v, out)
    }
    CompoundAssignExpr(t, _, v) => {
      collect_var_refs_in_expr_local(t, out)
      collect_var_refs_in_expr_local(v, out)
    }
    AssignPattern(_, v) => collect_var_refs_in_expr_local(v, out)
    PropAssignExpr(recv, _, v) => {
      collect_var_refs_in_expr_local(recv, out)
      collect_var_refs_in_expr_local(v, out)
    }
    IndexAssignExpr(recv, idx, v) => {
      collect_var_refs_in_expr_local(recv, out)
      collect_var_refs_in_expr_local(idx, out)
      collect_var_refs_in_expr_local(v, out)
    }
    Seq(a, b) => {
      collect_var_refs_in_expr_local(a, out)
      collect_var_refs_in_expr_local(b, out)
    }
    // Function expressions are skipped — their refs are captures,
    // which the bundler will resolve through the surrounding scope
    // at call time, not at decl time.
    ArrowFunc(_, _, _, _) | FuncExpr(_) => ()
    // For class expressions, the base class is evaluated at definition
    // time; method/ctor bodies are captures (skip them). Static field
    // initializers also run at definition time and must be tracked.
    NativeClassExpr(decl, _) => {
      match decl.base_expr {
        Some(b) => collect_var_refs_in_expr_local(b, out)
        None => ()
      }
      for sf in decl.static_field_inits {
        collect_var_refs_in_expr_local(sf.1, out)
      }
    }
    DynamicImport(spec, opts) => {
      collect_var_refs_in_expr_local(spec, out)
      match opts {
        Some(o) => collect_var_refs_in_expr_local(o, out)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      collect_var_refs_in_expr_local(tag, out)
      for e in exprs {
        collect_var_refs_in_expr_local(e, out)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_var_refs_in_expr_local(e, out)
      }
    _ => ()
  }
}

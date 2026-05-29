// Peephole rewrites that shave bytes off the emitted JS without
// changing observable behavior. Runs after fold + treeshake + mangle
// so the input is already as small as the structural passes can
// make it.
//
// Implemented rewrites:
//
//   x = x + y     -> x += y
//   x = x - y     -> x -= y
//   x = x * y     -> x *= y          (and friends: /, %, &, |, ^, <<, >>, >>>, **)
//   x = x && y    -> x &&= y         (preserved for ES2021+ consumers)
//   x = x || y    -> x ||= y
//   x = x ?? y    -> x ??= y
//   undefined     -> void 0          (when `undefined` is never bound)
//   true          -> !0              (saves 2 bytes)
//   false         -> !1              (saves 3 bytes)
//   !(a === b)    -> a !== b         (saves 3 bytes: `!(` + `)` vs `!==`)
//   !(a !== b)    -> a === b
//   !(a == b)     -> a != b
//   !(a != b)     -> a == b
//   !(a < b)      -> a >= b
//   !(a <= b)     -> a > b
//   !(a > b)      -> a <= b
//   !(a >= b)     -> a < b
//   x===null||x===void 0  -> x==null   (saves ~13 bytes per occurrence)
//   x!==null&&x!==void 0  -> x!=null
//   Number(x)             -> +x        (saves up to 6 bytes)
//   Boolean(x)            -> !!x       (saves up to 4 bytes)
//   Math.pow(x, y)        -> x**y      (saves up to 8 bytes)
//   Array.from(x)         -> [...x]    (saves ~6 bytes; single-arg only)
//   x.length !== 0        -> !!x.length  (saves ~4 bytes; also .size)
//   x.size === 0          -> !x.size
//   x!=null ? x.p : void 0       -> x?.p         (optional chaining, saves ~14 bytes)
//   x!=null ? x[k] : void 0      -> x?.[k]
//   x==null ? y : x               -> x ?? y       (flipped nullish coalescing)
//   this.x=void 0;…;this.x=val  -> this.x=val  (drop TS class-field placeholders)
//
// The compound-assign rewrite touches both expression-level
// `AssignExpr` and statement-level `Assign`. The `undefined ->
// void 0` rewrite walks the whole AST and checks a pre-built
// "undefined is shadowed somewhere" flag — if anything binds
// `undefined`, we leave the references alone.

///|
/// Apply peephole rewrites across a block. Returns a fresh block.
pub fn peephole_block(block : @ast.TsBlock) -> @ast.TsBlock {
  let shadowed = block_binds_undefined(block)
  let ctx : PeepCtx = { undefined_shadowed: shadowed }
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(peep_stmt(s, ctx))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
priv struct PeepCtx {
  undefined_shadowed : Bool
}

///|
fn peep_stmt(stmt : @ast.TsStmt, ctx : PeepCtx) -> @ast.TsStmt {
  match stmt {
    Assign(name, rhs) => {
      // `x = x op y` -> `x op= y` when the lhs of the inner binop
      // matches the assignment target and `op` has a compound form.
      // Also folds `x = x + 1` → `x++` and `x = x - 1` → `x--`
      // in one step without needing two peephole passes.
      // `x = x` → drop (self-assignment is a no-op; saves n+3 bytes).
      match rhs {
        @ast.TsExpr::Var(v) if v == name => return Empty
        _ => ()
      }
      let rhs_p = peep_expr(rhs, ctx)
      match rhs_p {
        BinOp(op, @ast.TsExpr::Var(other), value) =>
          if other == name {
            match (compound_for_binop(op), value) {
              (Some(AddAssign), @ast.TsExpr::IntLit(1)) =>
                return Expr(
                  @ast.TsExpr::UnaryOp(
                    @ast.TsUnaryOp::PostInc,
                    @ast.TsExpr::Var(name),
                  ),
                )
              (Some(SubAssign), @ast.TsExpr::IntLit(1)) =>
                return Expr(
                  @ast.TsExpr::UnaryOp(
                    @ast.TsUnaryOp::PostDec,
                    @ast.TsExpr::Var(name),
                  ),
                )
              (Some(cop), _) => return CompoundAssign(name, cop, value)
              (None, _) => ()
            }
          }
        _ => ()
      }
      Assign(name, rhs_p)
    }
    Var(b, t, rhs) => Var(b, t, peep_expr(rhs, ctx))
    Let(b, t, rhs) => Let(b, t, peep_expr(rhs, ctx))
    Const(b, t, rhs) => Const(b, t, peep_expr(rhs, ctx))
    CompoundAssign(n, op, rhs) => {
      let rhs_p = peep_expr(rhs, ctx)
      // `x += 1` → `x++` (saves 3 bytes in statement position)
      match (op, rhs_p) {
        (AddAssign, @ast.TsExpr::IntLit(1)) =>
          Expr(@ast.TsExpr::UnaryOp(@ast.TsUnaryOp::PostInc, @ast.TsExpr::Var(n)))
        (SubAssign, @ast.TsExpr::IntLit(1)) =>
          Expr(@ast.TsExpr::UnaryOp(@ast.TsUnaryOp::PostDec, @ast.TsExpr::Var(n)))
        _ => CompoundAssign(n, op, rhs_p)
      }
    }
    IndexAssign(target, idx, val) => {
      let target_p = peep_expr(target, ctx)
      let idx_p = peep_expr(idx, ctx)
      let val_p = peep_expr(val, ctx)
      // `x[i] = x[i] OP y` → `x[i] OP= y` (and `x[i] = x[i] + 1` → `x[i]++`).
      // Only fold when both target and index are bare Vars (no double evaluation).
      match (target_p, idx_p, val_p) {
        (
          Var(tn),
          Var(ik),
          BinOp(
            op,
            @ast.TsExpr::IndexAccess(@ast.TsExpr::Var(rn), @ast.TsExpr::Var(rk)),
            rhs,
          ),
        ) if tn == rn && ik == rk =>
          match (compound_for_binop(op), rhs) {
            (Some(AddAssign), @ast.TsExpr::IntLit(1)) =>
              Expr(
                @ast.TsExpr::UnaryOp(
                  @ast.TsUnaryOp::PostInc,
                  @ast.TsExpr::IndexAccess(@ast.TsExpr::Var(tn), @ast.TsExpr::Var(ik)),
                ),
              )
            (Some(SubAssign), @ast.TsExpr::IntLit(1)) =>
              Expr(
                @ast.TsExpr::UnaryOp(
                  @ast.TsUnaryOp::PostDec,
                  @ast.TsExpr::IndexAccess(@ast.TsExpr::Var(tn), @ast.TsExpr::Var(ik)),
                ),
              )
            (Some(cop), _) =>
              Expr(
                @ast.TsExpr::CompoundAssignExpr(
                  @ast.TsExpr::IndexAccess(@ast.TsExpr::Var(tn), @ast.TsExpr::Var(ik)),
                  cop,
                  rhs,
                ),
              )
            _ =>
              IndexAssign(
                Var(tn),
                Var(ik),
                BinOp(op, IndexAccess(Var(rn), Var(rk)), rhs),
              )
          }
        (t, i, v) => IndexAssign(t, i, v)
      }
    }
    PropAssign(target, prop, val) => {
      let target_p = peep_expr(target, ctx)
      let val_p = peep_expr(val, ctx)
      // `x.prop = x.prop OP y` → `x.prop OP= y` (and `x.prop = x.prop + 1` → `x.prop++`).
      // Only fold when the receiver is a bare `Var` (no double evaluation).
      match (target_p, val_p) {
        (Var(tn), BinOp(op, @ast.TsExpr::PropAccess(@ast.TsExpr::Var(rn), rprop), rhs)) if tn == rn && prop == rprop =>
          match (compound_for_binop(op), rhs) {
            (Some(AddAssign), @ast.TsExpr::IntLit(1)) =>
              Expr(
                @ast.TsExpr::UnaryOp(
                  @ast.TsUnaryOp::PostInc,
                  @ast.TsExpr::PropAccess(@ast.TsExpr::Var(tn), prop),
                ),
              )
            (Some(SubAssign), @ast.TsExpr::IntLit(1)) =>
              Expr(
                @ast.TsExpr::UnaryOp(
                  @ast.TsUnaryOp::PostDec,
                  @ast.TsExpr::PropAccess(@ast.TsExpr::Var(tn), prop),
                ),
              )
            (Some(cop), _) =>
              Expr(
                @ast.TsExpr::CompoundAssignExpr(
                  @ast.TsExpr::PropAccess(@ast.TsExpr::Var(tn), prop),
                  cop,
                  rhs,
                ),
              )
            _ => PropAssign(Var(tn), prop, BinOp(op, PropAccess(Var(rn), rprop), rhs))
          }
        (t, v) => PropAssign(t, prop, v)
      }
    }
    Expr(e) => Expr(peep_expr(e, ctx))
    Return(Some(e)) => {
      let ep = peep_expr(e, ctx)
      // `return undefined` / `return void 0` → `return` (saves bytes).
      match ep {
        Var("undefined") if not(ctx.undefined_shadowed) => Return(None)
        UnaryOp(@ast.TsUnaryOp::Void, _) => Return(None)
        _ => Return(Some(ep))
      }
    }
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => stmt
    Throw(e) => Throw(peep_expr(e, ctx))
    If(c, t, e) => {
      let cp = peep_expr(c, ctx)
      let tp = peep_block(t, ctx)
      let ep = match e {
        Some(b) => Some(peep_block(b, ctx))
        None => None
      }
      // `if (c) return a; else return b;` → `return c ? a : b;`
      // Apply peep_expr to the resulting expression so further folding
      // (e.g. `c?!0:!1` → `!!c`) happens in the same pass.
      match (tp.stmts, ep) {
        ([Return(Some(a))], Some({ stmts: [Return(Some(b))], .. })) =>
          Return(Some(peep_expr(Cond(cp, a, b), ctx)))
        // `if (c) x = a; else x = b;` → `x = c ? a : b;`
        (
          [Assign(n1, a)],
          Some({ stmts: [Assign(n2, b)], .. }),
        ) if n1 == n2 =>
          Assign(n1, peep_expr(Cond(cp, a, b), ctx))
        // `if (c) expr_a; else expr_b;` → `c ? expr_a : expr_b;`
        ([Expr(a)], Some({ stmts: [Expr(b)], .. })) =>
          Expr(peep_expr(Cond(cp, a, b), ctx))
        // `if (c) expr;` (no else) → `c && expr;` (short-circuit)
        ([Expr(a)], None) =>
          Expr(peep_expr(BinOp(@ast.TsBinOp::And, cp, a), ctx))
        // `if (c) {} else { stmts }` → `if (!c) { stmts }` (invert + drop empty then)
        ([], Some(else_block)) =>
          If(
            peep_expr(UnaryOp(@ast.TsUnaryOp::Not, cp), ctx),
            else_block,
            None,
          )
        _ => If(cp, tp, ep)
      }
    }
    While(c, body) => While(peep_expr(c, ctx), peep_block(body, ctx))
    DoWhile(c, body) => DoWhile(peep_expr(c, ctx), peep_block(body, ctx))
    With(c, body) => With(peep_expr(c, ctx), peep_block(body, ctx))
    For(init, cond, update, body) =>
      For(
        match init {
          Some(s) => Some(peep_stmt(s, ctx))
          None => None
        },
        match cond {
          Some(e) => Some(peep_expr(e, ctx))
          None => None
        },
        match update {
          Some(s) => Some(peep_stmt(s, ctx))
          None => None
        },
        peep_block(body, ctx),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(k, b, t, peep_expr(iter, ctx), peep_block(body, ctx))
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(k, b, t, peep_expr(iter, ctx), peep_block(body, ctx))
    ForIn(k, b, t, iter, body) =>
      ForIn(k, b, t, peep_expr(iter, ctx), peep_block(body, ctx))
    Switch(e, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(te) => Some(peep_expr(te, ctx))
            None => None
          },
          body: peep_block(c.body, ctx),
        })
      }
      // Drop a trailing `break;` (no label) from the last case body —
      // after the switch it has nowhere to break to, so it's dead code.
      // Saves 6 bytes (`break;` + preceding newline/space) per switch.
      let n_cases = new_cases.length()
      if n_cases > 0 {
        let last = new_cases[n_cases - 1]
        let last_stmts = last.body.stmts
        let m = last_stmts.length()
        if m > 0 {
          match last_stmts[m - 1] {
            Break(None) => {
              let trimmed : Array[@ast.TsStmt] = []
              for i, s in last_stmts {
                if i < m - 1 {
                  trimmed.push(s)
                }
              }
              new_cases[n_cases - 1] = {
                ..last,
                body: { stmts: trimmed, stmt_positions: [] },
              }
            }
            _ => ()
          }
        }
      }
      Switch(peep_expr(e, ctx), new_cases)
    }
    Try(b, bnd, cb, fb) =>
      Try(
        peep_block(b, ctx),
        bnd,
        match cb {
          Some(blk) => Some(peep_block(blk, ctx))
          None => None
        },
        match fb {
          Some(blk) => Some(peep_block(blk, ctx))
          None => None
        },
      )
    Label(name, inner) => Label(name, peep_stmt(inner, ctx))
    Block(b) => Block(peep_block(b, ctx))
    NativeClassStmt(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: peep_block(f.body, ctx) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(peep_block(b, ctx))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, peep_expr(sf.1, ctx)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(peep_expr(b, ctx))
        None => None
      }
      NativeClassStmt(
        { ..decl, base_expr: new_base_expr, methods: new_methods, static_field_inits: new_static_fields },
        new_ctor,
      )
    }
  }
}

///|
fn block_ends_with_terminator(b : @ast.TsBlock) -> Bool {
  let n = b.stmts.length()
  if n == 0 {
    return false
  }
  match b.stmts[n - 1] {
    Return(_) | Throw(_) | Break(_) | Continue(_) => true
    _ => false
  }
}

///|
fn peep_block(block : @ast.TsBlock, ctx : PeepCtx) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  // Emit statements, stopping after the first hard terminator
  // (Return / Throw / Break / Continue). Subsequent statements in the
  // same block are unreachable and can be dropped.
  for s in block.stmts {
    let ps = peep_stmt(s, ctx)
    // `if (c) { …; return; } else { stmts }` → `if (c) { …; return; }` +
    // `stmts` spliced inline. Saves the `else ` keyword (5 bytes) and the
    // braces (2 bytes) for every such pattern.
    match ps {
      If(cond, then_block, Some(else_block)) if block_ends_with_terminator(then_block) => {
        stmts.push(If(cond, then_block, None))
        for es in else_block.stmts {
          stmts.push(es)
        }
        continue
      }
      _ => ()
    }
    // `this.prop = void 0; …; this.prop = value;` → drop the void-0 init.
    // TypeScript class field initializers emit `this.x = void 0` as a
    // placeholder before the constructor body assigns the real value.
    // Scan backwards through already-emitted statements to find a
    // matching void-0 init and remove it in-place.
    // The parser emits `Expr(PropAssignExpr(...))` in regular function bodies
    // and `PropAssign(...)` in class-desugared IIFE bodies — handle both.
    let this_prop_is_void_free = fn(s : @ast.TsStmt) -> Bool {
      // Returns true when `s` assigns `void 0` to a property of `this`.
      match s {
        PropAssign(
          @ast.TsExpr::Var("this"),
          _,
          @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, _),
        ) => true
        Expr(
          @ast.TsExpr::PropAssignExpr(
            @ast.TsExpr::Var("this"),
            _,
            @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, _),
          ),
        ) => true
        _ => false
      }
    }
    let this_prop_name = fn(s : @ast.TsStmt) -> String? {
      match s {
        PropAssign(@ast.TsExpr::Var("this"), p, _) => Some(p)
        Expr(@ast.TsExpr::PropAssignExpr(@ast.TsExpr::Var("this"), p, _)) => Some(p)
        _ => None
      }
    }
    match this_prop_name(ps) {
      Some(prop2) => {
        // Look for an earlier `this.prop2 = void 0` in the already-emitted
        // stmts and remove it. Only safe if the value was `void 0` (not a
        // real expression that would have side effects when dropped).
        let mut i = stmts.length()
        while i > 0 {
          i = i - 1
          match this_prop_name(stmts[i]) {
            Some(p) if p == prop2 => {
              if this_prop_is_void_free(stmts[i]) {
                // Remove the void-0 initializer.
                stmts.remove(i) |> ignore
              }
              // Whether we removed it or not, stop searching — found
              // a prior assignment to this property.
              break
            }
            // A different this.prop assignment — keep searching backwards.
            Some(_) => ()
            // Something else (control flow, other stmt) — stop searching,
            // we can't safely remove an earlier initializer.
            None => break
          }
        }
      }
      None => ()
    }
    // Skip empty statements entirely — they're no-ops that would
    // emit a stray `;` in minify mode. Produced by `x = x` → Empty.
    match ps {
      Empty => ()
      _ => {
        stmts.push(ps)
        match ps {
          Return(_) | Throw(_) | Break(_) | Continue(_) => break
          _ => ()
        }
      }
    }
  }
  // Fold `if (c) return a; return b;` → `return c ? a : b;` and
  // `let/const/var x = expr; return x;` → `return expr;`.
  // Loop to fixpoint so chains like `if(a) return x; if(b) return y; return z;`
  // collapse all the way to `return a?x:b?y:z;` in a single pass.
  let mut folded = true
  while folded {
    folded = false
    let n = stmts.length()
    if n < 2 {
      break
    }
    match (stmts[n - 2], stmts[n - 1]) {
      (If(c, { stmts: [Return(Some(a))], .. }, None), Return(Some(b))) => {
        stmts[n - 2] = Return(Some(peep_expr(Cond(c, a, b), ctx)))
        stmts.pop() |> ignore
        folded = true
      }
      // `let/const/var x = expr; return x;` → `return expr;`
      (Let(Ident(vname), _, init), Return(Some(Var(rname)))) if vname == rname => {
        stmts[n - 2] = Return(Some(peep_expr(init, ctx)))
        stmts.pop() |> ignore
        folded = true
      }
      (Const(Ident(vname), _, init), Return(Some(Var(rname)))) if vname == rname => {
        stmts[n - 2] = Return(Some(peep_expr(init, ctx)))
        stmts.pop() |> ignore
        folded = true
      }
      (Var(Ident(vname), _, init), Return(Some(Var(rname)))) if vname == rname => {
        stmts[n - 2] = Return(Some(peep_expr(init, ctx)))
        stmts.pop() |> ignore
        folded = true
      }
      _ => ()
    }
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn peep_expr(expr : @ast.TsExpr, ctx : PeepCtx) -> @ast.TsExpr {
  match expr {
    BoolLit(b) =>
      // `true` → `!0` (2 bytes saved), `false` → `!1` (3 bytes saved).
      // `!0` evaluates to `true` and `!1` evaluates to `false` in all
      // JS engines; no context requires the identifier spelling.
      UnaryOp(Not, IntLit(if b { 0 } else { 1 }))
    Var(name) =>
      // `undefined` is a writable global on the spec's whatwg side,
      // but in practice it's always the singleton value. `void 0`
      // evaluates to the same value in 2 fewer bytes than the
      // identifier reference, with the bonus that it can't be
      // shadowed by a local binding to something else.
      if name == "undefined" && not(ctx.undefined_shadowed) {
        UnaryOp(Void, IntLit(0))
      } else {
        expr
      }
    AssignExpr(name, rhs) => {
      let rhs_p = peep_expr(rhs, ctx)
      match rhs_p {
        BinOp(op, @ast.TsExpr::Var(other), value) =>
          if other == name {
            match (compound_for_binop(op), value) {
              (Some(AddAssign), @ast.TsExpr::IntLit(1)) =>
                return UnaryOp(@ast.TsUnaryOp::PostInc, Var(name))
              (Some(SubAssign), @ast.TsExpr::IntLit(1)) =>
                return UnaryOp(@ast.TsUnaryOp::PostDec, Var(name))
              (Some(cop), _) => return CompoundAssignExpr(Var(name), cop, value)
              _ => ()
            }
          }
        _ => ()
      }
      AssignExpr(name, rhs_p)
    }
    BinOp(op, l, r) => {
      let lp = peep_expr(l, ctx)
      let rp = peep_expr(r, ctx)
      // `x === null || x === void 0` → `x == null`  (saves ~13 bytes)
      // `x !== null && x !== void 0` → `x != null`
      match op {
        Or =>
          match fold_null_undef_or(lp, rp) {
            Some(e) => e
            None => BinOp(op, lp, rp)
          }
        And =>
          match fold_null_undef_and(lp, rp) {
            Some(e) => e
            None => BinOp(op, lp, rp)
          }
        BinEq =>
          // `x.length === 0` → `!x.length`  (saves 4 bytes; .length is
          // always a non-negative integer so the coercion is lossless)
          // Same applies to `.size` (Map/Set) which is also non-negative.
          match (lp, rp) {
            (PropAccess(_, "length"), IntLit(0))
            | (PropAccess(_, "size"), IntLit(0)) =>
              UnaryOp(@ast.TsUnaryOp::Not, lp)
            (IntLit(0), PropAccess(_, "length"))
            | (IntLit(0), PropAccess(_, "size")) =>
              UnaryOp(@ast.TsUnaryOp::Not, rp)
            (lp, rp) => BinOp(op, lp, rp)
          }
        BinNe =>
          // `x.length !== 0` → `!!x.length` (saves ~4 bytes; same
          // reasoning as the === 0 case: .length is always non-negative)
          match (lp, rp) {
            (PropAccess(_, "length"), IntLit(0))
            | (PropAccess(_, "size"), IntLit(0)) =>
              UnaryOp(@ast.TsUnaryOp::Not, UnaryOp(@ast.TsUnaryOp::Not, lp))
            (IntLit(0), PropAccess(_, "length"))
            | (IntLit(0), PropAccess(_, "size")) =>
              UnaryOp(@ast.TsUnaryOp::Not, UnaryOp(@ast.TsUnaryOp::Not, rp))
            (lp, rp) => BinOp(op, lp, rp)
          }
        _ => BinOp(op, lp, rp)
      }
    }
    UnaryOp(Not, inner) => {
      let inner_p = peep_expr(inner, ctx)
      // `!(a OP b)` → `a INV_OP b` — saves the two wrapping characters.
      // `!!(bool_expr)` → `bool_expr` — double negation on a comparison is
      // a no-op (comparisons already yield boolean). Saves 2 bytes.
      match inner_p {
        BinOp(@ast.TsBinOp::BinEq, a, b) => BinOp(@ast.TsBinOp::BinNe, a, b)
        BinOp(@ast.TsBinOp::BinNe, a, b) => BinOp(@ast.TsBinOp::BinEq, a, b)
        BinOp(@ast.TsBinOp::AbstractEq, a, b) => BinOp(@ast.TsBinOp::AbstractNe, a, b)
        BinOp(@ast.TsBinOp::AbstractNe, a, b) => BinOp(@ast.TsBinOp::AbstractEq, a, b)
        BinOp(@ast.TsBinOp::BinLt, a, b) => BinOp(@ast.TsBinOp::BinGe, a, b)
        BinOp(@ast.TsBinOp::BinLe, a, b) => BinOp(@ast.TsBinOp::BinGt, a, b)
        BinOp(@ast.TsBinOp::BinGt, a, b) => BinOp(@ast.TsBinOp::BinLe, a, b)
        BinOp(@ast.TsBinOp::BinGe, a, b) => BinOp(@ast.TsBinOp::BinLt, a, b)
        // `!!(comparison)` → `comparison`
        UnaryOp(@ast.TsUnaryOp::Not, bool_expr) if is_bool_expr(bool_expr) =>
          bool_expr
        _ => UnaryOp(@ast.TsUnaryOp::Not, inner_p)
      }
    }
    UnaryOp(op, inner) => UnaryOp(op, peep_expr(inner, ctx))
    Cond(c, t, e) => {
      let cp = peep_expr(c, ctx)
      let tp = peep_expr(t, ctx)
      let ep = peep_expr(e, ctx)
      // `c ? !0 : !1` → `!!c` (4 bytes saved; both evaluate to true/false).
      // After BoolLit → `!0`/`!1` rewrite, `true ? … : …` patterns land here.
      match (tp, ep) {
        (
          UnaryOp(@ast.TsUnaryOp::Not, IntLit(0)),
          UnaryOp(@ast.TsUnaryOp::Not, IntLit(1)),
        ) =>
          UnaryOp(
            @ast.TsUnaryOp::Not,
            UnaryOp(@ast.TsUnaryOp::Not, cp),
          )
        // `c ? !1 : !0` → `!c` (c ? false : true).
        (
          UnaryOp(@ast.TsUnaryOp::Not, IntLit(1)),
          UnaryOp(@ast.TsUnaryOp::Not, IntLit(0)),
        ) =>
          UnaryOp(@ast.TsUnaryOp::Not, cp)
        // `x != null ? x : y` → `x ?? y` (nullish coalescing, saves ~8 bytes).
        // After `x!==null&&x!==undefined` → `x!=null`, this pattern is common
        // in TypeScript generated code for default-value patterns.
        //
        // `x != null ? x.prop : void 0` → `x?.prop` (optional chaining).
        // `x != null ? x[key] : void 0` → `x?.[key]`.
        // TypeScript emits this pattern when downleveling `x?.prop` to ES5/ES2019.
        // The else-arm can be either `void 0` or `undefined` (both denote undefined).
        (t_val, e_val) =>
          match cp {
            BinOp(@ast.TsBinOp::AbstractNe, check_x, NullLit) => {
              let is_void_else = match e_val {
                UnaryOp(@ast.TsUnaryOp::Void, _) => true
                Var("undefined") if not(ctx.undefined_shadowed) => true
                _ => false
              }
              if exprs_eq(check_x, t_val) {
                // `x != null ? x : y` → `x ?? y`
                BinOp(@ast.TsBinOp::Coalesce, check_x, e_val)
              } else if is_void_else {
                match t_val {
                  PropAccess(recv, prop) if exprs_eq(check_x, recv) =>
                    OptionalChain(PropAccess(check_x, prop))
                  IndexAccess(recv, idx) if exprs_eq(check_x, recv) =>
                    OptionalChain(IndexAccess(check_x, idx))
                  MethodCall(recv, method, args) if exprs_eq(check_x, recv) =>
                    OptionalChain(MethodCall(check_x, method, args))
                  _ => Cond(cp, t_val, e_val)
                }
              } else {
                Cond(cp, t_val, e_val)
              }
            }
            // `x == null ? y : x` → `x ?? y` (flipped nullish coalescing).
            // TypeScript sometimes emits the eq-form for null-default patterns.
            BinOp(@ast.TsBinOp::AbstractEq, check_x, NullLit) =>
              if exprs_eq(check_x, e_val) {
                BinOp(@ast.TsBinOp::Coalesce, check_x, t_val)
              } else {
                Cond(cp, t_val, e_val)
              }
            _ => Cond(cp, t_val, e_val)
          }
      }
    }
    Call(name, args) => {
      // `Number(x)` → `+x`  (saves up to 6 bytes)
      // `Boolean(x)` → `!!x` (saves up to 4 bytes)
      // Both are strictly equivalent to the stdlib coercions.
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(peep_expr(a, ctx))
      }
      if new_args.length() == 1 {
        if name == "Number" {
          return UnaryOp(@ast.TsUnaryOp::Plus, new_args[0])
        } else if name == "Boolean" {
          // Boolean(bool_expr) → bool_expr directly (skip the !! round-trip)
          if is_bool_expr(new_args[0]) {
            return new_args[0]
          }
          return UnaryOp(
            @ast.TsUnaryOp::Not,
            UnaryOp(@ast.TsUnaryOp::Not, new_args[0]),
          )
        }
      }
      Call(name, new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(peep_expr(a, ctx))
      }
      CallExpr(peep_expr(callee, ctx), new_args)
    }
    New(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(peep_expr(a, ctx))
      }
      New(name, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(peep_expr(a, ctx))
      }
      NewExpr(peep_expr(callee, ctx), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(peep_expr(a, ctx))
      }
      let recv_p = peep_expr(recv, ctx)
      // `Math.pow(x, y)` → `x**y` (saves up to 8 bytes)
      if m == "pow" && new_args.length() == 2 {
        match recv_p {
          Var("Math") => return BinOp(@ast.TsBinOp::Pow, new_args[0], new_args[1])
          _ => ()
        }
      }
      // `Array.from(x)` → `[...x]` (saves ~6 bytes; single-arg only —
      // two-arg form has a map function and must be left alone).
      if m == "from" && new_args.length() == 1 {
        match recv_p {
          Var("Array") =>
            return ArrayLit([Spread(new_args[0])])
          _ => ()
        }
      }
      MethodCall(recv_p, m, new_args)
    }
    PropAccess(recv, p) => PropAccess(peep_expr(recv, ctx), p)
    IndexAccess(recv, idx) =>
      IndexAccess(peep_expr(recv, ctx), peep_expr(idx, ctx))
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(peep_expr(i, ctx))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, peep_expr(ent.1, ctx)))
      }
      ObjectLit(new_entries)
    }
    ComputedProp(k, v) => ComputedProp(peep_expr(k, ctx), peep_expr(v, ctx))
    Spread(inner) => Spread(peep_expr(inner, ctx))
    Yield(Some(inner)) => Yield(Some(peep_expr(inner, ctx)))
    YieldStar(inner) => YieldStar(peep_expr(inner, ctx))
    Await(inner) => Await(peep_expr(inner, ctx))
    Seq(a, b) => Seq(peep_expr(a, ctx), peep_expr(b, ctx))
    CompoundAssignExpr(t, op, v) => {
      let tp = peep_expr(t, ctx)
      let vp = peep_expr(v, ctx)
      // `expr += 1` → `expr++` and `expr -= 1` → `expr--` in expression
      // position. Saves 2 bytes vs the compound-assign form.
      match (op, vp) {
        (AddAssign, @ast.TsExpr::IntLit(1)) =>
          UnaryOp(@ast.TsUnaryOp::PostInc, tp)
        (SubAssign, @ast.TsExpr::IntLit(1)) =>
          UnaryOp(@ast.TsUnaryOp::PostDec, tp)
        _ => CompoundAssignExpr(tp, op, vp)
      }
    }
    AssignPattern(b, v) => AssignPattern(b, peep_expr(v, ctx))
    PropAssignExpr(recv, p, v) => {
      let recv_p = peep_expr(recv, ctx)
      let v_p = peep_expr(v, ctx)
      // `x.prop = x.prop OP y` → `x.prop OP= y` (and `x.prop = x.prop + 1` → `x.prop++`).
      // Only fold when receiver is a bare Var (no double evaluation).
      match (recv_p, v_p) {
        (Var(tn), BinOp(op, @ast.TsExpr::PropAccess(@ast.TsExpr::Var(rn), rp), rhs)) if tn == rn && p == rp =>
          match (compound_for_binop(op), rhs) {
            (Some(AddAssign), @ast.TsExpr::IntLit(1)) =>
              UnaryOp(@ast.TsUnaryOp::PostInc, PropAccess(Var(tn), p))
            (Some(SubAssign), @ast.TsExpr::IntLit(1)) =>
              UnaryOp(@ast.TsUnaryOp::PostDec, PropAccess(Var(tn), p))
            (Some(cop), _) =>
              CompoundAssignExpr(PropAccess(Var(tn), p), cop, rhs)
            _ => PropAssignExpr(Var(tn), p, BinOp(op, PropAccess(Var(rn), rp), rhs))
          }
        (t, v) => PropAssignExpr(t, p, v)
      }
    }
    IndexAssignExpr(recv, idx, v) => {
      let recv_p = peep_expr(recv, ctx)
      let idx_p = peep_expr(idx, ctx)
      let v_p = peep_expr(v, ctx)
      // `x[i] = x[i] OP y` → `x[i] OP= y` (and `x[i] = x[i] + 1` → `x[i]++`).
      // Only fold when both target and index are bare Vars (no double evaluation).
      match (recv_p, idx_p, v_p) {
        (
          Var(tn),
          Var(ik),
          BinOp(op, @ast.TsExpr::IndexAccess(@ast.TsExpr::Var(rn), @ast.TsExpr::Var(rk)), rhs),
        ) if tn == rn && ik == rk =>
          match (compound_for_binop(op), rhs) {
            (Some(AddAssign), @ast.TsExpr::IntLit(1)) =>
              UnaryOp(@ast.TsUnaryOp::PostInc, IndexAccess(Var(tn), Var(ik)))
            (Some(SubAssign), @ast.TsExpr::IntLit(1)) =>
              UnaryOp(@ast.TsUnaryOp::PostDec, IndexAccess(Var(tn), Var(ik)))
            (Some(cop), _) =>
              CompoundAssignExpr(IndexAccess(Var(tn), Var(ik)), cop, rhs)
            _ =>
              IndexAssignExpr(Var(tn), Var(ik), BinOp(op, IndexAccess(Var(rn), Var(rk)), rhs))
          }
        (t, i, v) => IndexAssignExpr(t, i, v)
      }
    }
    ArrowFunc(params, ret, body, is_async) => {
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(peep_expr(e, ctx))
        ArrowBlock(b) => {
          let bp = peep_block(b, ctx)
          // `=> { return expr; }` → `=> expr` (concise arrow body).
          // Saves 9 bytes (`{ return ` + ` }`) per single-return arrow.
          match bp.stmts {
            [Return(Some(inner))] => @ast.TsArrowBody::ArrowExpr(inner)
            // `=> { return; }` / `=> {}` → `=> {}` (void arrow, no concise form)
            _ => @ast.TsArrowBody::ArrowBlock(bp)
          }
        }
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => {
      let folded : @ast.TsFunc = { ..f, body: peep_block(f.body, ctx) }
      FuncExpr(folded)
    }
    DynamicImport(spec, opts) => {
      let opts_f = match opts {
        Some(o) => Some(peep_expr(o, ctx))
        None => None
      }
      DynamicImport(peep_expr(spec, ctx), opts_f)
    }
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(peep_expr(e, ctx))
      }
      TaggedTemplate(peep_expr(tag, ctx), raw, cooked, new_exprs)
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(peep_expr(e, ctx))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(peep_expr(inner, ctx), ty)
    Satisfies(inner, ty) => Satisfies(peep_expr(inner, ctx), ty)
    NonNull(inner) => NonNull(peep_expr(inner, ctx))
    OptionalChain(inner) => OptionalChain(peep_expr(inner, ctx))
    NativeClassExpr(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: peep_block(f.body, ctx) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(peep_block(b, ctx))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, peep_expr(sf.1, ctx)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(peep_expr(b, ctx))
        None => None
      }
      NativeClassExpr(
        { ..decl, base_expr: new_base_expr, methods: new_methods, static_field_inits: new_static_fields },
        new_ctor,
      )
    }
    _ => expr
  }
}

///|
/// Map a binary operator to its compound-assignment equivalent.
/// Returns `None` for ops that don't have one (comparisons,
/// `instanceof`, `in`).
fn compound_for_binop(op : @ast.TsBinOp) -> @ast.TsCompoundOp? {
  match op {
    Add => Some(AddAssign)
    Sub => Some(SubAssign)
    Mul => Some(MulAssign)
    Div => Some(DivAssign)
    Mod => Some(ModAssign)
    Pow => Some(PowAssign)
    BitAnd => Some(BitAndAssign)
    BitOr => Some(BitOrAssign)
    BitXor => Some(BitXorAssign)
    Shl => Some(ShlAssign)
    Shr => Some(ShrAssign)
    UShr => Some(UShrAssign)
    And => Some(AndAssign)
    Or => Some(OrAssign)
    Coalesce => Some(CoalesceAssign)
    _ => None
  }
}

///|
/// Does any binding within `block` (or nested function bodies)
/// bind the name `undefined`? Used to gate the
/// `undefined -> void 0` rewrite. Anything that introduces an
/// `undefined` slot (let / const / var / function param / function
/// decl name / catch binding) counts.
fn block_binds_undefined(block : @ast.TsBlock) -> Bool {
  for s in block.stmts {
    if stmt_binds_undefined(s) {
      return true
    }
  }
  false
}

///|
fn stmt_binds_undefined(stmt : @ast.TsStmt) -> Bool {
  match stmt {
    Var(b, _, _) | Let(b, _, _) | Const(b, _, _) =>
      binding_contains_undefined(b)
    If(_, t, e) => {
      if block_binds_undefined(t) {
        return true
      }
      match e {
        Some(b) => block_binds_undefined(b)
        None => false
      }
    }
    While(_, b)
    | DoWhile(_, b)
    | With(_, b)
    | ForOf(_, _, _, _, b)
    | ForAwaitOf(_, _, _, _, b)
    | ForIn(_, _, _, _, b)
    | Block(b) => block_binds_undefined(b)
    For(init, _, _, body) => {
      match init {
        Some(s) => if stmt_binds_undefined(s) { return true }
        None => ()
      }
      block_binds_undefined(body)
    }
    Switch(_, cases) => {
      for c in cases {
        if block_binds_undefined(c.body) {
          return true
        }
      }
      false
    }
    Try(b, _, cb, fb) => {
      if block_binds_undefined(b) {
        return true
      }
      match cb {
        Some(blk) => if block_binds_undefined(blk) { return true }
        None => ()
      }
      match fb {
        Some(blk) => block_binds_undefined(blk)
        None => false
      }
    }
    Label(_, inner) => stmt_binds_undefined(inner)
    _ => false
  }
}

///|
fn binding_contains_undefined(binding : @ast.TsBinding) -> Bool {
  match binding {
    Ident(n) => n == "undefined"
    Array(ab) => {
      for elem in ab.items {
        match elem {
          Some(be) => if binding_contains_undefined(be.binding) { return true }
          None => ()
        }
      }
      match ab.rest {
        Some(r) => binding_contains_undefined(r)
        None => false
      }
    }
    Object(ob) => {
      for p in ob.props {
        if binding_contains_undefined(p.binding) {
          return true
        }
      }
      match ob.rest {
        Some(n) => n == "undefined"
        None => false
      }
    }
    Target(_) => false
  }
}


///|
/// Given one side of a `===` / `!==` check, return `(checked_expr, is_null)`
/// where `is_null` is true for `null` (vs `void 0` for undefined).
/// Returns `None` when neither operand is a null/undefined sentinel.
fn extract_null_check(
  a : @ast.TsExpr,
  b : @ast.TsExpr,
) -> (@ast.TsExpr, Bool)? {
  match b {
    @ast.TsExpr::NullLit => Some((a, true))
    @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, @ast.TsExpr::IntLit(0)) =>
      Some((a, false))
    _ =>
      match a {
        @ast.TsExpr::NullLit => Some((b, true))
        @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, @ast.TsExpr::IntLit(0)) =>
          Some((b, false))
        _ => None
      }
  }
}

///|
/// `x === null || x === void 0` → `x == null`
/// Only applies when the checked expression is a simple variable reference
/// (safe to duplicate / no side effects).
fn fold_null_undef_or(
  l : @ast.TsExpr,
  r : @ast.TsExpr,
) -> @ast.TsExpr? {
  match (l, r) {
    (
      @ast.TsExpr::BinOp(@ast.TsBinOp::BinEq, la, lb),
      @ast.TsExpr::BinOp(@ast.TsBinOp::BinEq, ra, rb),
    ) =>
      match (extract_null_check(la, lb), extract_null_check(ra, rb)) {
        (Some((lexpr, l_is_null)), Some((rexpr, r_is_null))) => {
          // One side must be the null check, the other undefined.
          if l_is_null == r_is_null {
            return None
          }
          // The checked expressions must be equal side-effect-free expressions.
          match (lexpr, rexpr) {
            (@ast.TsExpr::Var(n1), @ast.TsExpr::Var(n2)) if n1 == n2 =>
              Some(
                @ast.TsExpr::BinOp(
                  @ast.TsBinOp::AbstractEq,
                  @ast.TsExpr::Var(n1),
                  @ast.TsExpr::NullLit,
                ),
              )
            // `obj.prop === null || obj.prop === void 0` → `obj.prop == null`
            (
              @ast.TsExpr::PropAccess(@ast.TsExpr::Var(o1), p1),
              @ast.TsExpr::PropAccess(@ast.TsExpr::Var(o2), p2),
            ) if o1 == o2 && p1 == p2 =>
              Some(
                @ast.TsExpr::BinOp(
                  @ast.TsBinOp::AbstractEq,
                  @ast.TsExpr::PropAccess(@ast.TsExpr::Var(o1), p1),
                  @ast.TsExpr::NullLit,
                ),
              )
            _ => None
          }
        }
        _ => None
      }
    _ => None
  }
}

///|
/// `x !== null && x !== void 0` → `x != null`
fn fold_null_undef_and(
  l : @ast.TsExpr,
  r : @ast.TsExpr,
) -> @ast.TsExpr? {
  match (l, r) {
    (
      @ast.TsExpr::BinOp(@ast.TsBinOp::BinNe, la, lb),
      @ast.TsExpr::BinOp(@ast.TsBinOp::BinNe, ra, rb),
    ) =>
      match (extract_null_check(la, lb), extract_null_check(ra, rb)) {
        (Some((lexpr, l_is_null)), Some((rexpr, r_is_null))) => {
          if l_is_null == r_is_null {
            return None
          }
          match (lexpr, rexpr) {
            (@ast.TsExpr::Var(n1), @ast.TsExpr::Var(n2)) if n1 == n2 =>
              Some(
                @ast.TsExpr::BinOp(
                  @ast.TsBinOp::AbstractNe,
                  @ast.TsExpr::Var(n1),
                  @ast.TsExpr::NullLit,
                ),
              )
            (
              @ast.TsExpr::PropAccess(@ast.TsExpr::Var(o1), p1),
              @ast.TsExpr::PropAccess(@ast.TsExpr::Var(o2), p2),
            ) if o1 == o2 && p1 == p2 =>
              Some(
                @ast.TsExpr::BinOp(
                  @ast.TsBinOp::AbstractNe,
                  @ast.TsExpr::PropAccess(@ast.TsExpr::Var(o1), p1),
                  @ast.TsExpr::NullLit,
                ),
              )
            _ => None
          }
        }
        _ => None
      }
    _ => None
  }
}

///|
/// Returns true when an expression is guaranteed to be boolean-typed:
/// comparisons, `instanceof`, `in`, and logical-not. Used by the
/// `!!(expr)` → `expr` peephole to strip redundant double-negation.
fn is_bool_expr(e : @ast.TsExpr) -> Bool {
  match e {
    @ast.TsExpr::BinOp(op, l, r) =>
      match op {
        @ast.TsBinOp::BinEq
        | @ast.TsBinOp::BinNe
        | @ast.TsBinOp::AbstractEq
        | @ast.TsBinOp::AbstractNe
        | @ast.TsBinOp::BinLt
        | @ast.TsBinOp::BinLe
        | @ast.TsBinOp::BinGt
        | @ast.TsBinOp::BinGe
        | @ast.TsBinOp::Instanceof
        | @ast.TsBinOp::In => true
        // `a && b` and `a || b` are boolean when both operands are boolean.
        @ast.TsBinOp::And | @ast.TsBinOp::Or =>
          is_bool_expr(l) && is_bool_expr(r)
        _ => false
      }
    @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Not, _) => true
    @ast.TsExpr::BoolLit(_) => true
    _ => false
  }
}

///|
/// Shallow structural equality for simple expressions used in peephole guards.
/// Only handles the most common patterns (Var, PropAccess(Var, _), literals).
fn exprs_eq(a : @ast.TsExpr, b : @ast.TsExpr) -> Bool {
  match (a, b) {
    (Var(n1), Var(n2)) => n1 == n2
    (PropAccess(Var(r1), p1), PropAccess(Var(r2), p2)) => r1 == r2 && p1 == p2
    (NullLit, NullLit) | (IntLit(0), IntLit(0)) => true
    _ => false
  }
}

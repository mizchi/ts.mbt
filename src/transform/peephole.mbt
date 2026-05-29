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
//   Array.prototype.slice.call(x) -> [...x]  (saves ~21 bytes)
//   String(x)             -> ""+x      (saves up to 5 bytes)
//   `${x}`                -> ""+x      (saves 2 bytes; empty prefix+suffix)
//   `prefix${x}`          -> "prefix"+x (saves 2 bytes; non-empty prefix OK)
//   +new Date()           -> Date.now() (saves 1 byte; same timestamp semantics)
//   arr.slice(0)          -> [...arr]   (saves ~5 bytes; 0-start shallow copy)
//   if(c){if(d){S}}      -> if(c&&d){S}  (merge nested no-else ifs; saves ~8 bytes)
//   Object.assign({},a,b)     -> {...a,...b}     (saves ~12 bytes)
//   Object.assign({x:1},a,b) -> {x:1,...a,...b}  (literal target also safe)
//   new Array(0) / new Array() -> []    (saves up to 11 bytes)
//   new Object()           -> {}        (saves up to 12 bytes)
//   [].concat(a,b)         -> [...a,...b] (saves ~5 bytes per element)
//   !!x ? a : b            -> x ? a : b  (double negation in cond is no-op)
//   x && x.prop            -> x?.prop    (optional chain from && guard)
//   x && x[k]              -> x?.[k]
//   x && x.method(args)    -> x?.method(args)
//   switch { …; default: } -> switch { … }  (drop empty trailing cases)
//   { ...{a,b} }           -> { a, b }     (flatten literal object spread)
//   [...a,...[1,2],...b]   -> [...a,1,2,...b] (flatten literal array spread)
//   x==null ? void 0 : x.p  -> x?.p         (flipped optional chain)
//   if (c) {…} else {}     -> if (c) {…}   (drop empty else)
//   new Error(msg)         -> Error(msg)   (saves `new `, 4 bytes; also TypeError etc.)
//   fn.call(null, a, b)    -> fn(a, b)     (null/undefined this → direct call)
//   fn.apply(null, arr)    -> fn(...arr)   (null/undefined this → spread call)
//   void f() (stmt)        -> f()         (return value discarded at stmt level)
//   x.length !== 0        -> !!x.length  (saves ~4 bytes; also .size)
//   x.length > 0          -> !!x.length  (saves ~3 bytes)
//   x.length <= 0         -> !x.length   (saves ~4 bytes)
//   x.size === 0          -> !x.size
//   x!=null ? x.p : void 0       -> x?.p         (optional chaining, saves ~14 bytes)
//   x!=null ? x[k] : void 0      -> x?.[k]
//   x==null ? y : x               -> x ?? y       (flipped nullish coalescing)
//   c ? (x=a) : (x=b)             -> x = c ? a : b  (hoist common assignment)
//   x ? x : y                     -> x || y          (saves 3 bytes)
//   x ? y : x                     -> x && y          (saves 3 bytes)
//   this.x=void 0;…;this.x=val  -> this.x=val  (drop TS class-field placeholders)
//   typeof x === "undefined"    -> x === void 0  (saves ~9 bytes; combines with x==null rule)
//   typeof x !== "undefined"    -> x !== void 0
//   !x ? b : a                  -> x ? a : b   (flip branches, drop negation)
//   `text` (no exprs)           -> "text"       (saves 2 backtick bytes)
//   Number.parseInt(x)          -> parseInt(x)  (saves 7 bytes; same fn per spec)
//   Number.parseFloat(x)        -> parseFloat(x)
//   Array.prototype.slice.call(x,0) -> [...x]   (saves ~24 bytes; 0-start copy)
//   switch(x){case a:S}                  -> if(x===a){S}   (enables further if→ternary folds)
//   switch(x){case a:S default:T}        -> if(x===a){S}else{T}
//   switch(x){case a:S1 case b:S2 …}    -> if(x===a){S1}else if(x===b){S2}… (all-terminator multi-case)
//   catch(e){…not using e…}     -> catch{…}   (saves 3 bytes; ES2019 optional binding)
//   if(x==null){x=y}            -> x??=y       (saves ~10 bytes; ES2021 CoalesceAssign)
//   x === true                  -> x            (saves 7 bytes; drops bool literal cmp)
//   x === false                 -> !x           (saves 6 bytes)
//   x !== true                  -> !x           (saves 6 bytes)
//   x !== false                 -> x            (saves 7 bytes)
//   Object.prototype.hasOwnProperty.call(o,k) -> Object.hasOwn(o,k)  (saves ~22 bytes; ES2022)
//   x.hasOwnProperty(k)                       -> Object.hasOwn(x,k)  (saves ~8 bytes; ES2022)
//   c ? expr : void 0           -> c && expr    (saves ~7 bytes; short-circuit form)
//   !0 ? a : b                  -> a            (constant condition evaluation)
//   !1 ? a : b                  -> b            (constant condition evaluation)
//   if (!0) { S }               -> S            (dead-else elimination)
//   "a" === "b"                 -> !1           (string literal strict comparison)
//   "a" !== "b"                 -> !0
//   function(p){return e}       -> (p) => e    (saves ~16 bytes; no this/arguments/self-ref)
//   function(p){stmts}          -> (p) => {stmts} (saves ~9 bytes)
//   Array.prototype.METHOD.call(arr, args) -> arr.METHOD(args)  (saves ~22 bytes)
//   x.toString()                -> ""+x         (saves ~9 bytes; same as String(x))
//   (0, fn)(args)               -> fn(args)      (saves 4 bytes; indirect call in ESM is redundant)
//   "a" + "b"                -> "ab"           (string literal concatenation folding)
//   0 + x / x + 0           -> x              (additive identity for integers)
//   n + m / n - m / n * m   -> <result>       (integer literal arithmetic)
//   x - 0 / x * 1 / 1 * x  -> x              (multiplicative identity)
//   if (!!x) …              -> if (x) …       (strip double negation in condition)
//   while (!!x) …           -> while (x) …
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
          Expr(
            @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::PostInc, @ast.TsExpr::Var(n)),
          )
        (SubAssign, @ast.TsExpr::IntLit(1)) =>
          Expr(
            @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::PostDec, @ast.TsExpr::Var(n)),
          )
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
            rhs
          ),
        ) if tn == rn && ik == rk =>
          match (compound_for_binop(op), rhs) {
            (Some(AddAssign), @ast.TsExpr::IntLit(1)) =>
              Expr(
                @ast.TsExpr::UnaryOp(
                  @ast.TsUnaryOp::PostInc,
                  @ast.TsExpr::IndexAccess(
                    @ast.TsExpr::Var(tn),
                    @ast.TsExpr::Var(ik),
                  ),
                ),
              )
            (Some(SubAssign), @ast.TsExpr::IntLit(1)) =>
              Expr(
                @ast.TsExpr::UnaryOp(
                  @ast.TsUnaryOp::PostDec,
                  @ast.TsExpr::IndexAccess(
                    @ast.TsExpr::Var(tn),
                    @ast.TsExpr::Var(ik),
                  ),
                ),
              )
            (Some(cop), _) =>
              Expr(
                @ast.TsExpr::CompoundAssignExpr(
                  @ast.TsExpr::IndexAccess(
                    @ast.TsExpr::Var(tn),
                    @ast.TsExpr::Var(ik),
                  ),
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
    PropAssign(_, prop, _) if prop == "__super_proto" => return Empty
    PropAssign(target, prop, val) => {
      let target_p = peep_expr(target, ctx)
      let val_p = peep_expr(val, ctx)
      // `x.prop = x.prop OP y` → `x.prop OP= y` (and `x.prop = x.prop + 1` → `x.prop++`).
      // Only fold when the receiver is a bare `Var` (no double evaluation).
      match (target_p, val_p) {
        (
          Var(tn),
          BinOp(op, @ast.TsExpr::PropAccess(@ast.TsExpr::Var(rn), rprop), rhs),
        ) if tn == rn && prop == rprop =>
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
            _ =>
              PropAssign(
                Var(tn),
                prop,
                BinOp(op, PropAccess(Var(rn), rprop), rhs),
              )
          }
        (t, v) => PropAssign(t, prop, v)
      }
    }
    Expr(@ast.TsExpr::PropAssignExpr(_, prop, _)) if prop == "__super_proto" =>
      return Empty
    Expr(e) => {
      let ep = peep_expr(e, ctx)
      // `void f()` as a statement → `f()` — the return value of the
      // expression is discarded at statement level anyway, so `void` is
      // redundant. Saves the 5 chars `void `.
      match ep {
        @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, inner) => Expr(inner)
        _ => Expr(ep)
      }
    }
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
      let cp_raw = peep_expr(c, ctx)
      // Constant condition: `if (!0) { … }` → inline body; `if (!1) { … }` → else body.
      // Produced when literal comparisons from switch→ternary collapse to `!0`/`!1`.
      match cp_raw {
        UnaryOp(@ast.TsUnaryOp::Not, IntLit(0)) => {
          let tp = peep_block(t, ctx)
          return match tp.stmts {
            [single] => single
            _ => Block(tp)
          }
        }
        UnaryOp(@ast.TsUnaryOp::Not, IntLit(1)) =>
          match e {
            Some(eb) => {
              let ep = peep_block(eb, ctx)
              return match ep.stmts {
                [single] => single
                _ => Block(ep)
              }
            }
            None => return Empty
          }
        _ => ()
      }
      // `if (!!x) …` → `if (x) …`  (strip double negation from condition;
      // truthiness coercion makes the extra `!!` a no-op in boolean context).
      let cp = match cp_raw {
        UnaryOp(@ast.TsUnaryOp::Not, UnaryOp(@ast.TsUnaryOp::Not, inner)) =>
          inner
        _ => cp_raw
      }
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
        ([Assign(n1, a)], Some({ stmts: [Assign(n2, b)], .. })) if n1 == n2 =>
          Assign(n1, peep_expr(Cond(cp, a, b), ctx))
        // `if (c) expr_a; else expr_b;` → `c ? expr_a : expr_b;`
        ([Expr(a)], Some({ stmts: [Expr(b)], .. })) =>
          Expr(peep_expr(Cond(cp, a, b), ctx))
        // `if (x == null) { x = y; }` → `x ??= y` (saves ~10 bytes; ES2021)
        ([Expr(@ast.TsExpr::AssignExpr(n, v))], None) => {
          let coalesce_assign : @ast.TsStmt? = match cp {
            BinOp(@ast.TsBinOp::AbstractEq, @ast.TsExpr::Var(check_n), NullLit) =>
              if check_n == n {
                Some(
                  @ast.TsStmt::Expr(
                    @ast.TsExpr::CompoundAssignExpr(
                      @ast.TsExpr::Var(n),
                      @ast.TsCompoundOp::CoalesceAssign,
                      v,
                    ),
                  ),
                )
              } else {
                None
              }
            _ => None
          }
          match coalesce_assign {
            Some(s) => s
            None =>
              @ast.TsStmt::Expr(
                peep_expr(
                  BinOp(@ast.TsBinOp::And, cp, @ast.TsExpr::AssignExpr(n, v)),
                  ctx,
                ),
              )
          }
        }
        // `if (c) expr;` (no else) → `c && expr;` (short-circuit)
        ([Expr(a)], None) =>
          Expr(peep_expr(BinOp(@ast.TsBinOp::And, cp, a), ctx))
        // `if (c) {} else { stmts }` → `if (!c) { stmts }` (invert + drop empty then)
        ([], Some(else_block)) =>
          If(peep_expr(UnaryOp(@ast.TsUnaryOp::Not, cp), ctx), else_block, None)
        // `if (c) { stmts } else {}` → `if (c) { stmts }` (drop empty else)
        (_, Some({ stmts: [], .. })) => If(cp, tp, None)
        // `if (c) { if (d) { stmts } }` → `if (c && d) { stmts }`
        // Merge nested no-else ifs into a conjunction. Saves `if (`, `) {`,
        // `}` and indentation — roughly 8 bytes per merge, more in pretty mode.
        ([If(d, inner_block, None)], None) =>
          peep_stmt(
            If(
              peep_expr(BinOp(@ast.TsBinOp::And, cp, d), ctx),
              inner_block,
              None,
            ),
            ctx,
          )
        _ => If(cp, tp, ep)
      }
    }
    While(c, body) => {
      let cp_raw = peep_expr(c, ctx)
      // `while (!!x) …` → `while (x) …`  (strip double negation; same as If)
      let cp = match cp_raw {
        UnaryOp(@ast.TsUnaryOp::Not, UnaryOp(@ast.TsUnaryOp::Not, inner)) =>
          inner
        _ => cp_raw
      }
      While(cp, peep_block(body, ctx))
    }
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
      // Drop empty trailing `default:` cases — a `default:` with no body
      // is a no-op. Saves the `default:` label (8 bytes) per switch.
      // Also drop empty trailing `case X:` only when there is no fall-through
      // from it (the only use-case for an empty case is fall-through to the
      // next case — but if it's the LAST case it can't fall through anywhere
      // useful, so it's dead).
      let mut trimmed_cases = new_cases.length()
      while trimmed_cases > 0 {
        let last = new_cases[trimmed_cases - 1]
        if last.body.stmts.length() == 0 {
          trimmed_cases = trimmed_cases - 1
        } else {
          break
        }
      }
      let final_cases = if trimmed_cases < new_cases.length() {
        let arr : Array[@ast.TsSwitchCase] = []
        for i in 0..<trimmed_cases {
          arr.push(new_cases[i])
        }
        arr
      } else {
        new_cases
      }
      let ep = peep_expr(e, ctx)
      // Convert small switches to if / ternary when they're non-fall-through:
      //   switch(x){case a:S}           -> if(x===a){S}
      //   switch(x){case a:S default:T} -> if(x===a){S}else{T}
      // Only when the case body ends with a terminator (return/throw/break)
      // so fall-through is impossible. The resulting if/else can then
      // collapse further via the `if (c) return a; return b;` rule.
      match final_cases[:] {
        [{ test_expr: Some(case_e), body: case_body }] => {
          // A `break` terminator is only valid inside a switch / loop, so
          // don't lift a single-case switch to `if` when the body ends with
          // `break` or contains an internal bare break — the resulting
          // `if(…){…;break}` would be a SyntaxError outside a switch/loop.
          let has_bare_break = block_has_bare_break(case_body)
          let last_is_terminator = match case_body.stmts.last() {
            Some(Return(_)) | Some(Throw(_)) => true
            _ => false
          }
          let is_non_fall_through = not(has_bare_break) && last_is_terminator
          if is_non_fall_through {
            let if_stmt = peep_stmt(
              If(BinOp(@ast.TsBinOp::BinEq, ep, case_e), case_body, None),
              ctx,
            )
            if_stmt
          } else {
            Switch(ep, final_cases)
          }
        }
        [
          { test_expr: Some(case_e), body: case_body },
          { test_expr: None, body: default_body },
        ] => {
          let has_bare_break2 = block_has_bare_break(case_body)
          let last_is_term2 = match case_body.stmts.last() {
            Some(Return(_)) | Some(Throw(_)) => true
            _ => false
          }
          let is_non_fall_through = not(has_bare_break2) && last_is_term2
          if is_non_fall_through {
            let if_stmt = peep_stmt(
              If(
                BinOp(@ast.TsBinOp::BinEq, ep, case_e),
                case_body,
                Some(default_body),
              ),
              ctx,
            )
            if_stmt
          } else {
            Switch(ep, final_cases)
          }
        }
        // Multi-case switch where EVERY named case ends with a hard
        // terminator (return/throw/break): convert to an if-else chain.
        //   switch(x){case a:S1 case b:S2 default:T}
        //     → if(x===a){S1}else if(x===b){S2}else{T}
        // The resulting if-else chain then collapses via the
        // `if(c)return a; return b;` block-level fold into ternaries.
        _ => {
          // Check all named cases end with a terminator and have no
          // internal bare breaks (a bare break inside a case targets the
          // switch; lifting to if would make it a SyntaxError).
          let all_non_fall_through = {
            let mut ok = final_cases.length() > 1
            for c in final_cases {
              match c.test_expr {
                Some(_) => {
                  // Also bail out if the body has any mid-body bare break —
                  // those target the switch and become illegal in an if-else.
                  if block_has_bare_break(c.body) {
                    ok = false
                    break
                  }
                  match c.body.stmts.last() {
                    // Break is only valid inside switch/loop — don't
                    // lift to if-else where it would be a SyntaxError.
                    Some(Return(_)) | Some(Throw(_)) => ()
                    _ => {
                      ok = false
                      break
                    }
                  }
                }
                None => () // default — no terminator required
              }
            }
            ok
          }
          if all_non_fall_through {
            // Build the if-else chain from right to left.
            // Start from the default (if any) or None.
            let default_block : @ast.TsBlock? = match final_cases.last() {
              Some({ test_expr: None, body: db }) => Some(db)
              _ => None
            }
            let named : Array[@ast.TsSwitchCase] = []
            for c in final_cases {
              match c.test_expr {
                Some(_) => named.push(c)
                None => ()
              }
            }
            // Build else chain: rightmost named case first.
            let mut else_block : @ast.TsBlock? = default_block
            let mut i = named.length() - 1
            while i >= 0 {
              let c = named[i]
              let test_e = match c.test_expr {
                Some(te) => te
                None => break
              }
              let new_if = peep_stmt(
                If(BinOp(@ast.TsBinOp::BinEq, ep, test_e), c.body, else_block),
                ctx,
              )
              else_block = Some({ stmts: [new_if], stmt_positions: [] })
              i = i - 1
            }
            match else_block {
              Some({ stmts: [single], .. }) => single
              Some(blk) => If(BoolLit(true), blk, None) // fallback (shouldn't happen)
              None => Switch(ep, final_cases)
            }
          } else {
            Switch(ep, final_cases)
          }
        }
      }
    }
    Try(b, bnd, cb, fb) => {
      let cb_p = match cb {
        Some(blk) => Some(peep_block(blk, ctx))
        None => None
      }
      // `catch (e) { … }` → `catch { … }` when the binding variable is
      // never referenced in the catch body (saves 3 bytes: `(e)`).
      // ES2019 optional catch binding is supported by all modern runtimes.
      let bnd_p = match (bnd, cb_p) {
        (Some(@ast.TsBinding::Ident(name)), Some(catch_blk)) =>
          if block_references_name(catch_blk, name) {
            bnd
          } else {
            None
          }
        _ => bnd
      }
      Try(
        peep_block(b, ctx),
        bnd_p,
        cb_p,
        match fb {
          Some(blk) => Some(peep_block(blk, ctx))
          None => None
        },
      )
    }
    Label(name, inner) => Label(name, peep_stmt(inner, ctx))
    Block(b) => Block(peep_block(b, ctx))
    NativeClassStmt(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) =>
          Some({ ..f, body: elim_ctor_void_inits(peep_block(f.body, ctx)) })
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
/// Eliminate `this.X = void 0` initializers in a constructor body when
/// the same property is unconditionally overwritten later at the top level
/// of the same block. TypeScript class-field lowering emits these as a
/// placeholder before the real assignment — they're dead writes.
///
/// Only removes an init when the later assignment is a plain top-level
/// statement (not nested in a branch or loop), so the removal is safe.
fn elim_ctor_void_inits(block : @ast.TsBlock) -> @ast.TsBlock {
  // Collect the indices of top-level `this.X = void 0` statements.
  let void_inits : Map[String, Int] = {}
  for i, s in block.stmts {
    match s {
      PropAssign(
        @ast.TsExpr::Var("this"),
        p,
        @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, _)
      )
      | Expr(
        @ast.TsExpr::PropAssignExpr(
          @ast.TsExpr::Var("this"),
          p,
          @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, _)
        )
      ) => void_inits[p] = i
      _ => ()
    }
  }
  if void_inits.is_empty() {
    return block
  }
  // For each void-0 init, check if there is a later top-level unconditional
  // assignment to the same property. If so, mark it for removal.
  let removals : Map[Int, Bool] = {}
  for p, init_idx in void_inits {
    for j = init_idx + 1; j < block.stmts.length(); j = j + 1 {
      let s = block.stmts[j]
      let is_override = match s {
        PropAssign(
          @ast.TsExpr::Var("this"),
          q,
          @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, _)
        ) => q == p // another void-0: update the "latest init" index instead
        PropAssign(@ast.TsExpr::Var("this"), q, _) => q == p
        Expr(
          @ast.TsExpr::PropAssignExpr(
            @ast.TsExpr::Var("this"),
            q,
            @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, _)
          )
        ) => q == p
        Expr(@ast.TsExpr::PropAssignExpr(@ast.TsExpr::Var("this"), q, _)) =>
          q == p
        _ => false
      }
      if is_override {
        removals[init_idx] = true
        break
      }
    }
  }
  if removals.is_empty() {
    return block
  }
  let stmts : Array[@ast.TsStmt] = []
  for i, s in block.stmts {
    if removals.contains(i) {
      continue
    }
    stmts.push(s)
  }
  { ..block, stmts, }
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
      If(cond, then_block, Some(else_block)) if block_ends_with_terminator(
          then_block,
        ) => {
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
          @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, _)
        ) => true
        Expr(
          @ast.TsExpr::PropAssignExpr(
            @ast.TsExpr::Var("this"),
            _,
            @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, _)
          )
        ) => true
        _ => false
      }
    }
    let this_prop_name = fn(s : @ast.TsStmt) -> String? {
      match s {
        PropAssign(@ast.TsExpr::Var("this"), p, _) => Some(p)
        Expr(@ast.TsExpr::PropAssignExpr(@ast.TsExpr::Var("this"), p, _)) =>
          Some(p)
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
            // NOTE: `x && x.prop` → `x?.prop` is NOT applied here.
            // Optional chaining short-circuits only on null/undefined, but
            // `x && x.prop` short-circuits on ANY falsy value. More critically,
            // `null && null.prop` returns `null` while `null?.prop` returns
            // `undefined` — downstream code that uses `=== null` to distinguish
            // the two cases (e.g. yjs's `compareIDs`) will silently misbehave.
            None => BinOp(op, lp, rp)
          }
        BinEq =>
          // `x.length === 0` → `!x.length`  (saves 4 bytes; .length is
          // always a non-negative integer so the coercion is lossless)
          // Same applies to `.size` (Map/Set) which is also non-negative.
          // Also do literal constant folding here: `"a" === "b"` → `!1`,
          // `"a" === "a"` → `!0`. This is important because the switch→ternary
          // peephole runs after fold, so string comparisons from switch cases
          // need to be constant-folded in the peephole pass.
          match (lp, rp) {
            (StringLit(a), StringLit(b)) =>
              UnaryOp(@ast.TsUnaryOp::Not, IntLit(if a == b { 0 } else { 1 }))
            (IntLit(a), IntLit(b)) =>
              UnaryOp(@ast.TsUnaryOp::Not, IntLit(if a == b { 0 } else { 1 }))
            (PropAccess(_, "length"), IntLit(0))
            | (PropAccess(_, "size"), IntLit(0)) =>
              UnaryOp(@ast.TsUnaryOp::Not, lp)
            (IntLit(0), PropAccess(_, "length"))
            | (IntLit(0), PropAccess(_, "size")) =>
              UnaryOp(@ast.TsUnaryOp::Not, rp)
            // `typeof x === "undefined"` → `x === void 0`  (saves ~9 bytes)
            // `"undefined" === typeof x` → `x === void 0`
            // Only safe when x is not a bare Var — undeclared globals like
            // `document`, `window`, `DOMParser` throw ReferenceError when
            // accessed directly; `typeof` is the safe guard for those.
            (UnaryOp(@ast.TsUnaryOp::Typeof, @ast.TsExpr::Var(_)), StringLit("undefined"))
            | (StringLit("undefined"), UnaryOp(@ast.TsUnaryOp::Typeof, @ast.TsExpr::Var(_))) =>
              BinOp(op, lp, rp)
            (UnaryOp(@ast.TsUnaryOp::Typeof, x), StringLit("undefined"))
            | (StringLit("undefined"), UnaryOp(@ast.TsUnaryOp::Typeof, x)) =>
              BinOp(
                @ast.TsBinOp::BinEq,
                x,
                UnaryOp(@ast.TsUnaryOp::Void, IntLit(0)),
              )
            // `x === true` / `x === !0` → `x`  (saves 7 bytes; x is already boolean)
            (x, BoolLit(true))
            | (BoolLit(true), x)
            | (x, UnaryOp(@ast.TsUnaryOp::Not, IntLit(0)))
            | (UnaryOp(@ast.TsUnaryOp::Not, IntLit(0)), x) => x
            // `x === false` / `x === !1` → `!x`  (saves 6 bytes)
            (x, BoolLit(false))
            | (BoolLit(false), x)
            | (x, UnaryOp(@ast.TsUnaryOp::Not, IntLit(1)))
            | (UnaryOp(@ast.TsUnaryOp::Not, IntLit(1)), x) =>
              UnaryOp(@ast.TsUnaryOp::Not, x)
            (lp, rp) => BinOp(op, lp, rp)
          }
        BinNe =>
          // `x.length !== 0` → `!!x.length` (saves ~4 bytes; same
          // reasoning as the === 0 case: .length is always non-negative)
          // Literal constant folding (same idea as BinEq above):
          // `"a" !== "b"` → `!0`, `"a" !== "a"` → `!1`.
          match (lp, rp) {
            (StringLit(a), StringLit(b)) =>
              UnaryOp(@ast.TsUnaryOp::Not, IntLit(if a != b { 0 } else { 1 }))
            (IntLit(a), IntLit(b)) =>
              UnaryOp(@ast.TsUnaryOp::Not, IntLit(if a != b { 0 } else { 1 }))
            (PropAccess(_, "length"), IntLit(0))
            | (PropAccess(_, "size"), IntLit(0)) =>
              UnaryOp(@ast.TsUnaryOp::Not, UnaryOp(@ast.TsUnaryOp::Not, lp))
            (IntLit(0), PropAccess(_, "length"))
            | (IntLit(0), PropAccess(_, "size")) =>
              UnaryOp(@ast.TsUnaryOp::Not, UnaryOp(@ast.TsUnaryOp::Not, rp))
            // `typeof x !== "undefined"` → `x !== void 0`  (saves ~9 bytes)
            // Only safe when x is not a bare Var — undeclared globals like
            // `document`, `window`, `DOMParser` throw ReferenceError when
            // accessed directly; `typeof` is the safe guard for those.
            (UnaryOp(@ast.TsUnaryOp::Typeof, @ast.TsExpr::Var(_)), StringLit("undefined"))
            | (StringLit("undefined"), UnaryOp(@ast.TsUnaryOp::Typeof, @ast.TsExpr::Var(_))) =>
              BinOp(op, lp, rp)
            (UnaryOp(@ast.TsUnaryOp::Typeof, x), StringLit("undefined"))
            | (StringLit("undefined"), UnaryOp(@ast.TsUnaryOp::Typeof, x)) =>
              BinOp(
                @ast.TsBinOp::BinNe,
                x,
                UnaryOp(@ast.TsUnaryOp::Void, IntLit(0)),
              )
            // `x !== true` / `x !== !0` → `!x`  (saves 6 bytes)
            (x, BoolLit(true))
            | (BoolLit(true), x)
            | (x, UnaryOp(@ast.TsUnaryOp::Not, IntLit(0)))
            | (UnaryOp(@ast.TsUnaryOp::Not, IntLit(0)), x) =>
              UnaryOp(@ast.TsUnaryOp::Not, x)
            // `x !== false` / `x !== !1` → `x`  (saves 7 bytes)
            (x, BoolLit(false))
            | (BoolLit(false), x)
            | (x, UnaryOp(@ast.TsUnaryOp::Not, IntLit(1)))
            | (UnaryOp(@ast.TsUnaryOp::Not, IntLit(1)), x) => x
            (lp, rp) => BinOp(op, lp, rp)
          }
        // `x.length > 0` → `!!x.length`  (saves ~3 bytes; length is non-negative)
        // `x.length <= 0` → `!x.length`  (saves ~4 bytes)
        // `0 < x.length` / `0 >= x.length` — swapped forms
        BinGt =>
          match (lp, rp) {
            (PropAccess(_, "length"), IntLit(0))
            | (PropAccess(_, "size"), IntLit(0)) =>
              UnaryOp(@ast.TsUnaryOp::Not, UnaryOp(@ast.TsUnaryOp::Not, lp))
            (IntLit(0), PropAccess(_, "length"))
            | (IntLit(0), PropAccess(_, "size")) =>
              UnaryOp(@ast.TsUnaryOp::Not, UnaryOp(@ast.TsUnaryOp::Not, rp))
            _ => BinOp(op, lp, rp)
          }
        BinLe =>
          match (lp, rp) {
            (PropAccess(_, "length"), IntLit(0))
            | (PropAccess(_, "size"), IntLit(0)) =>
              UnaryOp(@ast.TsUnaryOp::Not, lp)
            (IntLit(0), PropAccess(_, "length"))
            | (IntLit(0), PropAccess(_, "size")) =>
              UnaryOp(@ast.TsUnaryOp::Not, rp)
            _ => BinOp(op, lp, rp)
          }
        // `"a" + "b"` → `"ab"`  (string constant folding; saves quotes + operator)
        // Produced when template literals like `"prefix" + x + "suffix"` get
        // partially evaluated, leaving adjacent string literals next to each other.
        // Also handles `"" + ""` → `""` (empty-string identity).
        Add =>
          match (lp, rp) {
            (StringLit(a), StringLit(b)) => StringLit(a + b)
            // `0 + x` / `x + 0` → `x`  (identity under addition for numbers).
            // Only safe when the other operand is an integer literal (so no
            // string coercion occurs).
            (IntLit(0), _) => rp
            (_, IntLit(0)) => lp
            // `n + m` → constant  (integer literal arithmetic folding).
            (IntLit(a), IntLit(b)) => IntLit(a + b)
            _ => BinOp(op, lp, rp)
          }
        // `n - m` → constant  (integer literal subtraction).
        Sub =>
          match (lp, rp) {
            (IntLit(a), IntLit(b)) => IntLit(a - b)
            // `x - 0` → `x`
            (_, IntLit(0)) => lp
            _ => BinOp(op, lp, rp)
          }
        // `n * m` → constant  (integer literal multiplication).
        Mul =>
          match (lp, rp) {
            (IntLit(a), IntLit(b)) => IntLit(a * b)
            // `x * 1` / `1 * x` → `x`
            (_, IntLit(1)) => lp
            (IntLit(1), _) => rp
            // `x * 0` / `0 * x` → `0`  (safe only when x has no side effects,
            // but IntLit(0) * anything is only folded when BOTH sides are IntLit)
            _ => BinOp(op, lp, rp)
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
        BinOp(@ast.TsBinOp::AbstractEq, a, b) =>
          BinOp(@ast.TsBinOp::AbstractNe, a, b)
        BinOp(@ast.TsBinOp::AbstractNe, a, b) =>
          BinOp(@ast.TsBinOp::AbstractEq, a, b)
        BinOp(@ast.TsBinOp::BinLt, a, b) => BinOp(@ast.TsBinOp::BinGe, a, b)
        BinOp(@ast.TsBinOp::BinLe, a, b) => BinOp(@ast.TsBinOp::BinGt, a, b)
        BinOp(@ast.TsBinOp::BinGt, a, b) => BinOp(@ast.TsBinOp::BinLe, a, b)
        BinOp(@ast.TsBinOp::BinGe, a, b) => BinOp(@ast.TsBinOp::BinLt, a, b)
        // `!!(comparison)` → `comparison`
        UnaryOp(@ast.TsUnaryOp::Not, bool_expr) if is_bool_expr(bool_expr) =>
          bool_expr
        // `!void 0` / `!null` → `!0` (saves bytes; all three are `true`)
        @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, _) | @ast.TsExpr::NullLit =>
          UnaryOp(@ast.TsUnaryOp::Not, IntLit(0))
        _ => UnaryOp(@ast.TsUnaryOp::Not, inner_p)
      }
    }
    UnaryOp(Plus, inner) => {
      let inner_p = peep_expr(inner, ctx)
      // `+new Date()` → `Date.now()` (saves 1 byte; semantically equivalent
      // for getting the current timestamp in milliseconds).
      match inner_p {
        @ast.TsExpr::New("Date", []) => MethodCall(Var("Date"), "now", [])
        _ => UnaryOp(@ast.TsUnaryOp::Plus, inner_p)
      }
    }
    UnaryOp(op, inner) => UnaryOp(op, peep_expr(inner, ctx))
    Cond(c, t, e) => {
      let cp = peep_expr(c, ctx)
      let tp = peep_expr(t, ctx)
      let ep = peep_expr(e, ctx)
      // Constant condition: `!0 ? a : b` → `a`, `!1 ? a : b` → `b`.
      // After literal comparisons collapse to `!0`/`!1` in the peephole
      // (e.g. from switch→ternary chains), this rule evaluates the ternary.
      match cp {
        UnaryOp(@ast.TsUnaryOp::Not, IntLit(0)) => return tp
        UnaryOp(@ast.TsUnaryOp::Not, IntLit(1)) => return ep
        _ => ()
      }
      // `!!x ? a : b` → `x ? a : b` (double negation in condition is a no-op
      // in a ternary since the truthiness test already coerces to boolean).
      // Saves 2 bytes per occurrence. Unwrap any number of `!!` layers.
      // `!x ? b : a` → `x ? a : b` (flip branches, drop negation, saves 1 byte).
      let (cp, tp, ep) = match cp {
        UnaryOp(@ast.TsUnaryOp::Not, UnaryOp(@ast.TsUnaryOp::Not, inner)) =>
          (inner, tp, ep)
        UnaryOp(@ast.TsUnaryOp::Not, inner) => (inner, ep, tp)
        _ => (cp, tp, ep)
      }
      // `x ? x : y` → `x || y` (saves 3 bytes: `? x :` → `||`)
      // `x ? y : x` → `x && y` (saves 3 bytes: `? y :` → `&&`)
      // Only safe when the condition and the matching branch are the same
      // pure expression (no double evaluation concern for vars/prop access).
      if exprs_eq(cp, tp) {
        return BinOp(@ast.TsBinOp::Or, cp, ep)
      }
      if exprs_eq(cp, ep) {
        return BinOp(@ast.TsBinOp::And, cp, tp)
      }
      // `c ? !0 : !1` → `!!c` (4 bytes saved; both evaluate to true/false).
      // After BoolLit → `!0`/`!1` rewrite, `true ? … : …` patterns land here.
      match (tp, ep) {
        (
          UnaryOp(@ast.TsUnaryOp::Not, IntLit(0)),
          UnaryOp(@ast.TsUnaryOp::Not, IntLit(1)),
        ) => UnaryOp(@ast.TsUnaryOp::Not, UnaryOp(@ast.TsUnaryOp::Not, cp))
        // `c ? !1 : !0` → `!c` (c ? false : true).
        (
          UnaryOp(@ast.TsUnaryOp::Not, IntLit(1)),
          UnaryOp(@ast.TsUnaryOp::Not, IntLit(0)),
        ) => UnaryOp(@ast.TsUnaryOp::Not, cp)
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
                  // `x != null ? x() : void 0` → `x?.()` (optional call)
                  Call(fn_name, args) =>
                    if exprs_eq(check_x, Var(fn_name)) {
                      OptionalChain(Call(fn_name, args))
                    } else {
                      Cond(cp, t_val, e_val)
                    }
                  CallExpr(callee, args) if exprs_eq(check_x, callee) =>
                    OptionalChain(CallExpr(check_x, args))
                  _ => Cond(cp, t_val, e_val)
                }
              } else {
                Cond(cp, t_val, e_val)
              }
            }
            // `x == null ? y : x` → `x ?? y` (flipped nullish coalescing).
            // `x == null ? void 0 : x.prop` → `x?.prop` (flipped optional chain).
            // `x == null ? void 0 : x[key]` → `x?.[key]`
            // `x == null ? void 0 : x.method(args)` → `x?.method(args)`
            // TypeScript sometimes emits the eq-form for null-default patterns.
            BinOp(@ast.TsBinOp::AbstractEq, check_x, NullLit) => {
              let is_void_then = match t_val {
                UnaryOp(@ast.TsUnaryOp::Void, _) => true
                Var("undefined") if not(ctx.undefined_shadowed) => true
                _ => false
              }
              if exprs_eq(check_x, e_val) {
                BinOp(@ast.TsBinOp::Coalesce, check_x, t_val)
              } else if is_void_then {
                // `x == null ? void 0 : x.prop` → `x?.prop`
                match e_val {
                  PropAccess(recv, prop) if exprs_eq(check_x, recv) =>
                    OptionalChain(PropAccess(check_x, prop))
                  IndexAccess(recv, idx) if exprs_eq(check_x, recv) =>
                    OptionalChain(IndexAccess(check_x, idx))
                  Call(fn_name, args) =>
                    if exprs_eq(check_x, Var(fn_name)) {
                      OptionalChain(Call(fn_name, args))
                    } else {
                      Cond(cp, t_val, e_val)
                    }
                  CallExpr(callee, args) if exprs_eq(check_x, callee) =>
                    OptionalChain(CallExpr(check_x, args))
                  _ => Cond(cp, t_val, e_val)
                }
              } else {
                Cond(cp, t_val, e_val)
              }
            }
            // `c ? (x = a) : (x = b)` → `x = c ? a : b`.
            // Hoists the assignment outside the ternary; saves `x=` bytes
            // in the then-branch and enables further folding on the condition.
            _ =>
              match (t_val, e_val) {
                (AssignExpr(n1, v1), AssignExpr(n2, v2)) if n1 == n2 =>
                  AssignExpr(n1, peep_expr(Cond(cp, v1, v2), ctx))
                // `c ? expr : void 0` → `c && expr`  (saves ~7 bytes).
                // When the else-branch is undefined/void the ternary is
                // equivalent to a short-circuit `&&`. The `!x ? b : a`
                // flip already turns `c ? void 0 : expr` into `!c ? expr : void 0`
                // which then lands here.
                (t_expr, UnaryOp(@ast.TsUnaryOp::Void, _)) =>
                  BinOp(@ast.TsBinOp::And, cp, t_expr)
                _ => Cond(cp, t_val, e_val)
              }
          }
      }
    }
    Call(name, args) => {
      // `Number(x)` → `+x`  (saves up to 6 bytes)
      // `Boolean(x)` → `!!x` (saves up to 4 bytes)
      // `String(x)`  → `""+x` (saves up to 5 bytes; ""+x and String(x)
      //   are semantically equivalent for all non-Symbol values, which is
      //   the common case in bundled code)
      // All are strictly equivalent for the typical bundled code use cases.
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
        } else if name == "String" {
          return BinOp(@ast.TsBinOp::Add, StringLit(""), new_args[0])
        }
      }
      Call(name, new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(peep_expr(a, ctx))
      }
      let callee_p = peep_expr(callee, ctx)
      // `(0, fn)(args)` → `fn(args)`  (indirect call pattern; saves 4 bytes).
      // TypeScript emits `(0, expr)()` to avoid binding `this` to the callee.
      // In ES modules (which bundled code always produces), a bare `fn()`
      // call already has `this=undefined`, so the indirection is redundant.
      // Only fold when the indirected expression is a bare identifier.
      let callee_p = match callee_p {
        Seq(@ast.TsExpr::IntLit(0), @ast.TsExpr::Var(_) as fn_expr) => fn_expr
        _ => callee_p
      }
      CallExpr(callee_p, new_args)
    }
    New(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(peep_expr(a, ctx))
      }
      // `new Array(0)` → `[]` and `new Array()` → `[]` (saves up to 11 bytes).
      // `new Object()` → `{}` (saves up to 12 bytes).
      // Only fold the zero-argument or literal-zero forms; `new Array(n)` with
      // a positive literal creates a sparse array and must be kept.
      if name == "Array" {
        match new_args {
          [] | [IntLit(0)] => return ArrayLit([])
          _ => ()
        }
      } else if name == "Object" && new_args.length() == 0 {
        return ObjectLit([])
      } else if name == "Error" ||
        name == "TypeError" ||
        name == "RangeError" ||
        name == "ReferenceError" ||
        name == "SyntaxError" {
        // `new Error(msg)` → `Error(msg)` (saves 4 bytes: `new `).
        // The built-in Error constructors return a new Error object whether
        // called with or without `new` — the spec guarantees it.
        return Call(name, new_args)
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
      // `Number.parseInt(x)` → `parseInt(x)` (saves 7 bytes; same function per spec)
      // `Number.parseFloat(x)` → `parseFloat(x)` (saves 7 bytes; same function)
      if m == "parseInt" || m == "parseFloat" {
        match recv_p {
          Var("Number") => return Call(m, new_args)
          _ => ()
        }
      }
      // `Math.pow(x, y)` → `x**y` (saves up to 8 bytes)
      if m == "pow" && new_args.length() == 2 {
        match recv_p {
          Var("Math") =>
            return BinOp(@ast.TsBinOp::Pow, new_args[0], new_args[1])
          _ => ()
        }
      }
      // `Array.from(x)` → `[...x]` (saves ~6 bytes; single-arg only —
      // two-arg form has a map function and must be left alone).
      if m == "from" && new_args.length() == 1 {
        match recv_p {
          Var("Array") => return ArrayLit([Spread(new_args[0])])
          _ => ()
        }
      }
      // `Array.prototype.slice.call(x)` → `[...x]` (saves ~21 bytes).
      // `Array.prototype.slice.call(x, 0)` → `[...x]` (saves ~24 bytes).
      // This pattern converts array-likes (arguments, NodeLists) to
      // real arrays. Spread is semantically equivalent for iterable inputs.
      if m == "call" &&
        (
          new_args.length() == 1 ||
          (
            new_args.length() == 2 &&
            exprs_eq(new_args[1], @ast.TsExpr::IntLit(0))
          )
        ) {
        match recv_p {
          PropAccess(
            PropAccess(@ast.TsExpr::Var("Array"), "prototype"),
            "slice"
          ) => return ArrayLit([Spread(new_args[0])])
          _ => ()
        }
      }
      // `Array.prototype.METHOD.call(arr, arg1, arg2, ...)` → `arr.METHOD(arg1, arg2, ...)`.
      // TypeScript's `__spreadArray` helper and some polyfills call Array
      // prototype methods indirectly. The `.call` form is safe to collapse
      // when the first argument (the `this` receiver) is a plain array or
      // a var — the method semantics are the same. Only fold when the
      // receiver is `Array.prototype.METHOD` (not e.g. `[].METHOD`).
      // Saves ~22 bytes for methods like forEach, map, filter, reduce, etc.
      if m == "call" && new_args.length() >= 1 {
        match recv_p {
          PropAccess(
            PropAccess(@ast.TsExpr::Var("Array"), "prototype"),
            method_name
          ) if method_name != "slice" => {
            // Rewrite to `new_args[0].method_name(new_args[1..])`.
            let rest : Array[@ast.TsExpr] = []
            for ii, a in new_args {
              if ii > 0 {
                rest.push(a)
              }
            }
            return MethodCall(new_args[0], method_name, rest)
          }
          _ => ()
        }
      }
      // `Object.prototype.hasOwnProperty.call(obj, key)` → `Object.hasOwn(obj, key)`
      // ES2022+; saves ~22 bytes and is the modern idiom.
      // Also handles the shorter `{}.hasOwnProperty.call(obj, key)` form.
      if m == "call" && new_args.length() == 2 {
        let is_hasown_recv = match recv_p {
          PropAccess(
            PropAccess(@ast.TsExpr::Var("Object"), "prototype"),
            "hasOwnProperty"
          ) => true
          PropAccess(@ast.TsExpr::ObjectLit([]), "hasOwnProperty") => true
          _ => false
        }
        if is_hasown_recv {
          return MethodCall(Var("Object"), "hasOwn", new_args)
        }
      }
      // `x.hasOwnProperty(key)` → `Object.hasOwn(x, key)` (saves ~8 bytes; ES2022).
      // The direct `.hasOwnProperty()` call is subtly unsafe if the prototype
      // chain is modified, but for bundled code it's equivalent and shorter.
      if m == "hasOwnProperty" && new_args.length() == 1 {
        return MethodCall(Var("Object"), "hasOwn", [recv_p, new_args[0]])
      }
      // `Object.assign({}, a, b, …)` → `{...a, ...b, …}` (object spread).
      // `Object.assign({x:1}, a, b)` → `{x:1, ...a, ...b}` (literal target).
      // Safe when the first argument is an object literal (creates a fresh
      // copy; the target is never shared). Sources are inlined or spread.
      if m == "assign" && new_args.length() >= 2 {
        match (recv_p, new_args[0]) {
          (Var("Object"), @ast.TsExpr::ObjectLit(init_ents)) => {
            let entries : Array[(String, @ast.TsExpr)] = []
            for ie in init_ents {
              entries.push(ie)
            }
            for i, a in new_args {
              if i == 0 {
                continue
              }
              match a {
                ObjectLit(ents) =>
                  for e in ents {
                    entries.push(e)
                  }
                // Non-ObjectLit sources: spread them in. `("...", Spread(e))`
                // is the sentinel that ObjectLit emit uses for `...e`.
                _ => entries.push(("...", Spread(a)))
              }
            }
            return ObjectLit(entries)
          }
          _ => ()
        }
      }
      // `[].concat(a, b, …)` → `[...a, ...b, …]` (array spread).
      // TypeScript's `__spreadArray` helper or manual concatenation emits this.
      // Safe because `concat` on a fresh `[]` never mutates anything and
      // spread is semantically equivalent for iterable arrays.
      if m == "concat" && new_args.length() >= 1 {
        match recv_p {
          ArrayLit([]) => {
            let items : Array[@ast.TsExpr] = []
            for a in new_args {
              match a {
                ArrayLit(elems) =>
                  for e in elems {
                    items.push(e)
                  }
                _ => items.push(Spread(a))
              }
            }
            return ArrayLit(items)
          }
          _ => ()
        }
      }
      // `fn.call(null, a, b)` → `fn(a, b)` (saves ~6 bytes).
      // `fn.call(undefined, a, b)` → `fn(a, b)` (same).
      // Only fold when the `this` argument is null/undefined — those are
      // the same as an unbound call in sloppy mode and throw in strict mode
      // (same as a direct call). NOT safe for `fn.call(obj, ...)` where
      // `obj` provides a meaningful `this`.
      if m == "call" && new_args.length() >= 1 {
        let is_null_this = match new_args[0] {
          @ast.TsExpr::NullLit => true
          @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, _) => true
          @ast.TsExpr::Var("undefined") if not(ctx.undefined_shadowed) => true
          _ => false
        }
        if is_null_this {
          let rest_args : Array[@ast.TsExpr] = []
          for i, a in new_args {
            if i == 0 {
              continue
            }
            rest_args.push(a)
          }
          return CallExpr(recv_p, rest_args)
        }
      }
      // `fn.apply(null, argsArray)` → `fn(...argsArray)` (saves ~7 bytes).
      // Only fold the single-arg form where the array arg is known.
      if m == "apply" && new_args.length() == 2 {
        let is_null_this = match new_args[0] {
          @ast.TsExpr::NullLit => true
          @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, _) => true
          @ast.TsExpr::Var("undefined") if not(ctx.undefined_shadowed) => true
          _ => false
        }
        if is_null_this {
          return CallExpr(recv_p, [Spread(new_args[1])])
        }
      }
      // `arr.slice(0)` → `[...arr]` (saves ~5 bytes; shallow copy of array).
      // Only the single-arg form with literal 0 (from-start copy); multi-arg
      // and non-zero-start forms can't be simplified to a spread.
      if m == "slice" &&
        new_args.length() == 1 &&
        exprs_eq(new_args[0], @ast.TsExpr::IntLit(0)) {
        return ArrayLit([Spread(recv_p)])
      }
      // `x.toString()` → `""+x`  (saves ~9 bytes; same as String(x)).
      // Safe for all non-Symbol values which is the common case in bundled code.
      // The no-arg form only — `.toString(radix)` must be preserved.
      // Never apply to `super.toString()` — `super` is not a valid expression
      // value in JS; `"" + super` is a SyntaxError outside class methods.
      let is_super_recv = match recv_p {
        @ast.TsExpr::Var("super") => true
        _ => false
      }
      if m == "toString" && new_args.length() == 0 && not(is_super_recv) {
        return BinOp(@ast.TsBinOp::Add, StringLit(""), recv_p)
      }
      MethodCall(recv_p, m, new_args)
    }
    PropAccess(recv, p) => PropAccess(peep_expr(recv, ctx), p)
    IndexAccess(recv, idx) =>
      IndexAccess(peep_expr(recv, ctx), peep_expr(idx, ctx))
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        let ip = peep_expr(i, ctx)
        // `[...a, ...[1,2,3], ...b]` → `[...a, 1, 2, 3, ...b]`
        // Flatten spreads of literal arrays in-place.
        match ip {
          @ast.TsExpr::Spread(@ast.TsExpr::ArrayLit(inner)) =>
            for e in inner {
              new_items.push(e)
            }
          _ => new_items.push(ip)
        }
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        let val_p = peep_expr(ent.1, ctx)
        // `{ ...{a:1, b:2} }` → `{ a:1, b:2 }` — flatten literal-object
        // spreads in-place. The spread of a literal is semantically
        // equivalent to inlining its entries in order.
        // The parser uses `("@@spread:N", expr)` for object spread;
        // JSX runtime uses `("...", Spread(expr))`. Handle both.
        let is_spread_entry = ent.0 == "..." || ent.0.has_prefix("@@spread:")
        if is_spread_entry {
          match val_p {
            @ast.TsExpr::ObjectLit(inner_ents) => {
              for ie in inner_ents {
                new_entries.push(ie)
              }
              continue
            }
            @ast.TsExpr::Spread(@ast.TsExpr::ObjectLit(inner_ents)) => {
              for ie in inner_ents {
                new_entries.push(ie)
              }
              continue
            }
            _ => ()
          }
        }
        new_entries.push((ent.0, val_p))
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
        (
          Var(tn),
          BinOp(op, @ast.TsExpr::PropAccess(@ast.TsExpr::Var(rn), rp), rhs),
        ) if tn == rn && p == rp =>
          match (compound_for_binop(op), rhs) {
            (Some(AddAssign), @ast.TsExpr::IntLit(1)) =>
              UnaryOp(@ast.TsUnaryOp::PostInc, PropAccess(Var(tn), p))
            (Some(SubAssign), @ast.TsExpr::IntLit(1)) =>
              UnaryOp(@ast.TsUnaryOp::PostDec, PropAccess(Var(tn), p))
            (Some(cop), _) =>
              CompoundAssignExpr(PropAccess(Var(tn), p), cop, rhs)
            _ =>
              PropAssignExpr(
                Var(tn),
                p,
                BinOp(op, PropAccess(Var(rn), rp), rhs),
              )
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
          BinOp(
            op,
            @ast.TsExpr::IndexAccess(@ast.TsExpr::Var(rn), @ast.TsExpr::Var(rk)),
            rhs
          ),
        ) if tn == rn && ik == rk =>
          match (compound_for_binop(op), rhs) {
            (Some(AddAssign), @ast.TsExpr::IntLit(1)) =>
              UnaryOp(@ast.TsUnaryOp::PostInc, IndexAccess(Var(tn), Var(ik)))
            (Some(SubAssign), @ast.TsExpr::IntLit(1)) =>
              UnaryOp(@ast.TsUnaryOp::PostDec, IndexAccess(Var(tn), Var(ik)))
            (Some(cop), _) =>
              CompoundAssignExpr(IndexAccess(Var(tn), Var(ik)), cop, rhs)
            _ =>
              IndexAssignExpr(
                Var(tn),
                Var(ik),
                BinOp(op, IndexAccess(Var(rn), Var(rk)), rhs),
              )
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
      let folded : @ast.TsBlock = peep_block(f.body, ctx)
      // Convert `function(params) { return expr; }` → `(params) => expr` (saves ~16 bytes).
      // Also `function(params) { stmts; }` → `(params) => { stmts; }` (saves ~9 bytes: `function` vs `=>`).
      // Safe only when:
      //   - Not a generator function.
      //   - Body doesn't reference `this` or `arguments` (arrow functions capture these lexically).
      //   - Not named (or the name isn't used inside the body as a recursive ref).
      //   - Not async (async arrows are fine syntax-wise, but we only need to handle the common case).
      // Only convert ANONYMOUS function expressions to arrows.  Named
      // FuncExprs (`let foo = function foo(){...}`) are the parser's
      // representation of `function foo(){}` declarations, which are
      // hoisted in JS. Converting to an arrow would prevent
      // `try_emit_function_decl` from emitting a real function declaration
      // and break forward references.  Also guard against empty-body
      // functions used as constructor bases (arrows lack `.prototype`).
      let can_arrow = not(f.is_generator) &&
        f.name == "" &&
        not(folded.stmts.is_empty()) &&
        not(block_references_name(folded, "this")) &&
        not(block_references_name(folded, "arguments"))
      if can_arrow {
        let arrow_body = match folded.stmts {
          [Return(Some(inner))] => @ast.TsArrowBody::ArrowExpr(inner)
          _ => @ast.TsArrowBody::ArrowBlock(folded)
        }
        ArrowFunc(f.params, f.return_type, arrow_body, f.is_async)
      } else {
        FuncExpr({ ..f, body: folded })
      }
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
      // `` `text` `` → `"text"` (no interpolations; saves 2 bytes for the backticks).
      if new_exprs.length() == 0 && parts.length() == 1 {
        StringLit(parts[0])
        // Single-interpolation templates with empty suffix save 2 bytes over
        // string concatenation. Only the suffix-empty case is shorter:
        //   `` `${x}` ``       → `""+x`       (saves 2 bytes; empty prefix+suffix)
        //   `` `prefix${x}` `` → `"prefix"+x`  (saves 2 bytes; non-empty prefix OK)
        // Suffix-non-empty forms are NOT shorter: `` `${x}s` `` = `""+x+"s"` (same or longer).
      } else if new_exprs.length() == 1 && parts.length() == 2 && parts[1] == "" {
        BinOp(@ast.TsBinOp::Add, StringLit(parts[0]), new_exprs[0])
      } else {
        TemplateLiteral(parts, new_exprs)
      }
    }
    As(inner, ty) => As(peep_expr(inner, ctx), ty)
    Satisfies(inner, ty) => Satisfies(peep_expr(inner, ctx), ty)
    NonNull(inner) => NonNull(peep_expr(inner, ctx))
    OptionalChain(inner) => OptionalChain(peep_expr(inner, ctx))
    NativeClassExpr(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) =>
          Some({ ..f, body: elim_ctor_void_inits(peep_block(f.body, ctx)) })
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
fn extract_null_check(a : @ast.TsExpr, b : @ast.TsExpr) -> (@ast.TsExpr, Bool)? {
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
fn fold_null_undef_or(l : @ast.TsExpr, r : @ast.TsExpr) -> @ast.TsExpr? {
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
          // The checked expressions must be structurally equal.
          // `exprs_eq` handles Var, PropAccess chains, IndexAccess chains, and literals.
          if exprs_eq(lexpr, rexpr) {
            Some(
              @ast.TsExpr::BinOp(
                @ast.TsBinOp::AbstractEq,
                lexpr,
                @ast.TsExpr::NullLit,
              ),
            )
          } else {
            None
          }
        }
        _ => None
      }
    _ => None
  }
}

///|
/// `x !== null && x !== void 0` → `x != null`
fn fold_null_undef_and(l : @ast.TsExpr, r : @ast.TsExpr) -> @ast.TsExpr? {
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
          if exprs_eq(lexpr, rexpr) {
            Some(
              @ast.TsExpr::BinOp(
                @ast.TsBinOp::AbstractNe,
                lexpr,
                @ast.TsExpr::NullLit,
              ),
            )
          } else {
            None
          }
        }
        _ => None
      }
    _ => None
  }
}

///|
/// `x && x.prop` → `x?.prop`, `x && x[k]` → `x?.[k]`, etc.
/// TypeScript emits `&&` chains for optional access when targeting
/// older ES versions (pre-ES2020). Only folds bare-Var guards whose
/// rhs receiver is the same name.
fn fold_and_optional_chain(lp : @ast.TsExpr, rp : @ast.TsExpr) -> @ast.TsExpr {
  match lp {
    @ast.TsExpr::Var(guard_n) =>
      match rp {
        @ast.TsExpr::PropAccess(@ast.TsExpr::Var(recv_n), prop) =>
          if guard_n == recv_n {
            @ast.TsExpr::OptionalChain(
              @ast.TsExpr::PropAccess(@ast.TsExpr::Var(guard_n), prop),
            )
          } else {
            @ast.TsExpr::BinOp(@ast.TsBinOp::And, lp, rp)
          }
        @ast.TsExpr::IndexAccess(@ast.TsExpr::Var(recv_n), idx) =>
          if guard_n == recv_n {
            @ast.TsExpr::OptionalChain(
              @ast.TsExpr::IndexAccess(@ast.TsExpr::Var(guard_n), idx),
            )
          } else {
            @ast.TsExpr::BinOp(@ast.TsBinOp::And, lp, rp)
          }
        @ast.TsExpr::MethodCall(@ast.TsExpr::Var(recv_n), method, args) =>
          if guard_n == recv_n {
            @ast.TsExpr::OptionalChain(
              @ast.TsExpr::MethodCall(@ast.TsExpr::Var(guard_n), method, args),
            )
          } else {
            @ast.TsExpr::BinOp(@ast.TsBinOp::And, lp, rp)
          }
        _ => @ast.TsExpr::BinOp(@ast.TsBinOp::And, lp, rp)
      }
    _ => @ast.TsExpr::BinOp(@ast.TsBinOp::And, lp, rp)
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
    (PropAccess(r1, p1), PropAccess(r2, p2)) => p1 == p2 && exprs_eq(r1, r2)
    (IndexAccess(r1, i1), IndexAccess(r2, i2)) =>
      exprs_eq(r1, r2) && exprs_eq(i1, i2)
    (NullLit, NullLit) | (IntLit(0), IntLit(0)) => true
    (StringLit(s1), StringLit(s2)) => s1 == s2
    _ => false
  }
}

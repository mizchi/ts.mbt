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
// (removed) x.length !== 0 -> !!x.length, and the > 0 / <= 0 / === 0
//   siblings. They assume `.length` is a non-negative number, and the
//   receiver can be anything: `(0).length` is `undefined`, so
//   `undefined <= 0` is false while `!undefined` is true, and
//   `{ length: -1 }` makes `> 0` false while `!!(-1)` is true. Peephole
//   has no types to consult, and the saving was 3-4 bytes.
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
//   `p${s}` (s a string)        -> "p"+s        (saves 2 bytes; ToString
//     and ToPrimitive agree only when the hole is already a string)
//   Number.parseInt(x)          -> parseInt(x)  (saves 7 bytes; same fn per spec)
//   Number.parseFloat(x)        -> parseFloat(x)
// (removed) Array.prototype.slice.call(x,0) -> [...x]: `slice` accepts
//   any array-LIKE, a spread needs an ITERABLE.
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
// (removed) x.hasOwnProperty(k) -> Object.hasOwn(x,k): replaces
//   whatever the receiver's own `hasOwnProperty` is with the built-in.
//   c ? expr : void 0           -> c && expr    (saves ~7 bytes; short-circuit form)
//   !0 ? a : b                  -> a            (constant condition evaluation)
//   !1 ? a : b                  -> b            (constant condition evaluation)
//   if (!0) { S }               -> S            (dead-else elimination)
//   "a" === "b"                 -> !1           (string literal strict comparison)
//   "a" !== "b"                 -> !0
//   function(p){return e}       -> (p) => e    (saves ~16 bytes; no this/arguments/self-ref)
//   function(p){stmts}          -> (p) => {stmts} (saves ~9 bytes)
//   Array.prototype.METHOD.call(arr, args) -> arr.METHOD(args)  (saves ~22 bytes)
// (removed) x.toString() -> ""+x: `undefined.toString()` throws where
//   `"" + undefined` does not, `+` prefers `valueOf` over `toString`,
//   and a Symbol is the other way round again.
//   (0, fn)(args)               -> fn(args)      (saves 4 bytes; indirect call in ESM is redundant)
//   "a" + "b"                -> "ab"           (string literal concatenation folding)
//   0 + x / x + 0           -> x              (only for a number that
//     cannot be -0: `undefined + 0` is NaN, `"a" + 0` is "a0",
//     `-0 + 0` is 0)
//   n + m / n - m / n * m   -> <result>       (integer literal arithmetic)
//   x - 0 / x * 1 / 1 * x  -> x              (only for a number)
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
  let ctx : PeepCtx = {
    undefined_shadowed: shadowed,
    undeclared: undeclared_referenced_names(block),
  }
  let stmts : Array[@ast.TsStmt] = []
  let positions : Array[Int] = []
  // Positions are tracked per surviving statement rather than carried
  // over wholesale: this loop can now DROP a statement, and a positions
  // array left at the original length would either be discarded by the
  // length check downstream or — worse — line up by coincidence and
  // shift every source-map entry after the hole.
  let has_positions = block.stmt_positions.length() == block.stmts.length()
  for i, s in block.stmts {
    match peep_block_level(peep_stmt(s, ctx)) {
      Some(kept) =>
        // The top level has its own driver: `peep_block` handles every
        // NESTED block and this loop handles the outermost one. A
        // statement-level rewrite therefore has to be wired into both,
        // and the IIFE splice below is the one that matters most here —
        // a bundle's side-effect wrappers are at the top level almost
        // by definition.
        match iife_splice_stmts(kept) {
          Some(spliced) =>
            for sp in spliced {
              stmts.push(sp)
              if has_positions {
                positions.push(block.stmt_positions[i])
              }
            }
          None => {
            stmts.push(kept)
            if has_positions {
              positions.push(block.stmt_positions[i])
            }
          }
        }
      None => ()
    }
  }
  {
    stmts,
    stmt_positions: if has_positions {
      positions
    } else {
      block.stmt_positions
    },
  }
}

///|
priv struct PeepCtx {
  undefined_shadowed : Bool
  // Names the block references but never declares — host globals, in
  // other words. `typeof x === "undefined"` is TRUE for an undeclared
  // `x`, while `void 0 === x` THROWS, so that rewrite is only sound for
  // a name this bundle declares. Anything absent from here is declared.
  undeclared : Map[String, Bool]
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
    Var(b, t, rhs) => Var(b, t, peep_decl_rhs(b, rhs, ctx))
    Let(b, t, rhs) => Let(b, t, peep_decl_rhs(b, rhs, ctx))
    Const(b, t, rhs) => Const(b, t, peep_decl_rhs(b, rhs, ctx))
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
        Var("undefined") if !ctx.undefined_shadowed => Return(None)
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
      // terser's `loops`: `for(;;)` is shorter than any spelling of an
      // always-true `while` condition, and `while (!0)` is what the
      // BoolLit rewrite above turns `while (true)` into.
      let body_p = collapse_loop_body(peep_block(body, ctx))
      if expr_is_always_truthy(cp) {
        For(None, None, None, body_p)
      } else {
        While(cp, body_p)
      }
    }
    DoWhile(c, body) =>
      DoWhile(peep_expr(c, ctx), collapse_loop_body(peep_block(body, ctx)))
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
        collapse_loop_body(peep_block(body, ctx)),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(
        k,
        b,
        t,
        peep_expr(iter, ctx),
        collapse_loop_body(peep_block(body, ctx)),
      )
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(
        k,
        b,
        t,
        peep_expr(iter, ctx),
        collapse_loop_body(peep_block(body, ctx)),
      )
    ForIn(k, b, t, iter, body) =>
      ForIn(
        k,
        b,
        t,
        peep_expr(iter, ctx),
        collapse_loop_body(peep_block(body, ctx)),
      )
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
          let is_non_fall_through = !has_bare_break && last_is_terminator
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
          let is_non_fall_through = !has_bare_break2 && last_is_term2
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
fn arrow_body_uses_this(body : @ast.TsArrowBody) -> Bool {
  match body {
    @ast.TsArrowBody::ArrowExpr(inner) => expr_uses_this(inner)
    @ast.TsArrowBody::ArrowBlock(blk) => block_uses_this(blk)
  }
}

///|
fn expr_uses_this(e : @ast.TsExpr) -> Bool {
  match e {
    Var("this") => true
    BinOp(_, a, b) => expr_uses_this(a) || expr_uses_this(b)
    UnaryOp(_, a) => expr_uses_this(a)
    CallExpr(f, args) => expr_uses_this(f) || args.iter().any(expr_uses_this)
    Call(_, args) => args.iter().any(expr_uses_this)
    Cond(c, t, f) => expr_uses_this(c) || expr_uses_this(t) || expr_uses_this(f)
    ArrayLit(elems) => elems.iter().any(expr_uses_this)
    Spread(a) => expr_uses_this(a)
    ObjectLit(ents) => ents.iter().any(fn(kv) { expr_uses_this(kv.1) })
    ComputedProp(k, v) => expr_uses_this(k) || expr_uses_this(v)
    IndexAccess(a, b) => expr_uses_this(a) || expr_uses_this(b)
    PropAccess(a, _) => expr_uses_this(a)
    New(_, args) => args.iter().any(expr_uses_this)
    NewExpr(f, args) => expr_uses_this(f) || args.iter().any(expr_uses_this)
    MethodCall(recv, _, args) =>
      expr_uses_this(recv) || args.iter().any(expr_uses_this)
    AssignExpr(_, v) => expr_uses_this(v)
    AssignPattern(b, v) =>
      binding_subexprs(b).iter().any(expr_uses_this) || expr_uses_this(v)
    CompoundAssignExpr(a, _, b) => expr_uses_this(a) || expr_uses_this(b)
    PropAssignExpr(a, _, b) => expr_uses_this(a) || expr_uses_this(b)
    IndexAssignExpr(a, b, c) =>
      expr_uses_this(a) || expr_uses_this(b) || expr_uses_this(c)
    Seq(a, b) => expr_uses_this(a) || expr_uses_this(b)
    // Arrow functions share `this` with their enclosing context — recurse,
    // parameter defaults included.
    ArrowFunc(params, _, body, _) =>
      param_subexprs(params).iter().any(expr_uses_this) ||
      arrow_body_uses_this(body)
    // Regular functions and classes introduce their own `this` — don't descend.
    FuncExpr(_) | NativeClassExpr(_, _) => false
    PureCall(inner) => expr_uses_this(inner)
    Yield(Some(inner)) => expr_uses_this(inner)
    YieldStar(inner) => expr_uses_this(inner)
    Await(inner) => expr_uses_this(inner)
    DynamicImport(a, b) => expr_uses_this(a) || b.map_or(false, expr_uses_this)
    TaggedTemplate(tag, _, _, exprs) =>
      expr_uses_this(tag) || exprs.iter().any(expr_uses_this)
    TemplateLiteral(_, exprs) => exprs.iter().any(expr_uses_this)
    As(inner, _) => expr_uses_this(inner)
    _ => false
  }
}

///|
fn block_uses_this(blk : @ast.TsBlock) -> Bool {
  blk.stmts.iter().any(stmt_uses_this)
}

///|
fn stmt_uses_this(s : @ast.TsStmt) -> Bool {
  match s {
    @ast.TsStmt::Expr(e) => expr_uses_this(e)
    @ast.TsStmt::Return(Some(e)) => expr_uses_this(e)
    @ast.TsStmt::Return(None) => false
    @ast.TsStmt::Var(b, _, e)
    | @ast.TsStmt::Let(b, _, e)
    | @ast.TsStmt::Const(b, _, e) =>
      binding_subexprs(b).iter().any(expr_uses_this) || expr_uses_this(e)
    @ast.TsStmt::Assign(_, e) => expr_uses_this(e)
    @ast.TsStmt::CompoundAssign(_, _, e) => expr_uses_this(e)
    @ast.TsStmt::If(c, t, e) =>
      expr_uses_this(c) ||
      block_uses_this(t) ||
      e.map_or(false, block_uses_this)
    @ast.TsStmt::While(c, b) => expr_uses_this(c) || block_uses_this(b)
    @ast.TsStmt::DoWhile(c, b) => expr_uses_this(c) || block_uses_this(b)
    @ast.TsStmt::For(init, cond, update, body) =>
      init.map_or(false, stmt_uses_this) ||
      cond.map_or(false, expr_uses_this) ||
      update.map_or(false, stmt_uses_this) ||
      block_uses_this(body)
    @ast.TsStmt::ForOf(_, b, _, iter, body)
    | @ast.TsStmt::ForAwaitOf(_, b, _, iter, body)
    | @ast.TsStmt::ForIn(_, b, _, iter, body) =>
      binding_subexprs(b).iter().any(expr_uses_this) ||
      expr_uses_this(iter) ||
      block_uses_this(body)
    @ast.TsStmt::Block(b) => block_uses_this(b)
    @ast.TsStmt::Throw(e) => expr_uses_this(e)
    @ast.TsStmt::Try(b, catch_b, cb, fb) =>
      block_uses_this(b) ||
      catch_b.map_or(false, fn(cbind) {
        binding_subexprs(cbind).iter().any(expr_uses_this)
      }) ||
      cb.map_or(false, block_uses_this) ||
      fb.map_or(false, block_uses_this)
    @ast.TsStmt::Switch(e, cases) =>
      expr_uses_this(e) || cases.iter().any(fn(c) { block_uses_this(c.body) })
    @ast.TsStmt::Label(_, inner) => stmt_uses_this(inner)
    // FuncDecl/NativeClassStmt introduce their own `this` — don't descend.
    _ => false
  }
}

// Returns true if the expression contains a `super` reference that would be
// captured by an enclosing arrow function (i.e., not shielded by a
// non-arrow function boundary). Used to prevent the arrow→FuncExpr conversion
// that breaks `super` inside arrow bodies.

///|
fn expr_uses_super(e : @ast.TsExpr) -> Bool {
  match e {
    Var("super") => true
    Call("super", _) => true
    BinOp(_, a, b) => expr_uses_super(a) || expr_uses_super(b)
    UnaryOp(_, a) => expr_uses_super(a)
    CallExpr(f, args) => expr_uses_super(f) || args.iter().any(expr_uses_super)
    Cond(c, t, f) =>
      expr_uses_super(c) || expr_uses_super(t) || expr_uses_super(f)
    ArrayLit(elems) => elems.iter().any(expr_uses_super)
    Spread(a) => expr_uses_super(a)
    ObjectLit(ents) => ents.iter().any(fn(kv) { expr_uses_super(kv.1) })
    ComputedProp(k, v) => expr_uses_super(k) || expr_uses_super(v)
    IndexAccess(a, b) => expr_uses_super(a) || expr_uses_super(b)
    PropAccess(a, _) => expr_uses_super(a)
    New(_, args) => args.iter().any(expr_uses_super)
    NewExpr(f, args) => expr_uses_super(f) || args.iter().any(expr_uses_super)
    MethodCall(recv, _, args) =>
      expr_uses_super(recv) || args.iter().any(expr_uses_super)
    AssignExpr(_, v) => expr_uses_super(v)
    AssignPattern(b, v) =>
      binding_subexprs(b).iter().any(expr_uses_super) || expr_uses_super(v)
    CompoundAssignExpr(a, _, b) => expr_uses_super(a) || expr_uses_super(b)
    PropAssignExpr(a, _, b) => expr_uses_super(a) || expr_uses_super(b)
    IndexAssignExpr(a, b, c) =>
      expr_uses_super(a) || expr_uses_super(b) || expr_uses_super(c)
    Seq(a, b) => expr_uses_super(a) || expr_uses_super(b)
    // Arrow functions DO share super with their enclosing context —
    // parameter defaults included.
    ArrowFunc(params, _, body, _) =>
      param_subexprs(params).iter().any(expr_uses_super) ||
      (match body {
        @ast.TsArrowBody::ArrowExpr(inner) => expr_uses_super(inner)
        @ast.TsArrowBody::ArrowBlock(blk) => block_uses_super(blk)
      })
    // Regular function expressions and class expressions introduce their own
    // super binding — do NOT descend into them.
    FuncExpr(_) | NativeClassExpr(_, _) => false
    PureCall(inner) => expr_uses_super(inner)
    Yield(Some(inner)) => expr_uses_super(inner)
    YieldStar(inner) => expr_uses_super(inner)
    Await(inner) => expr_uses_super(inner)
    DynamicImport(a, b) =>
      expr_uses_super(a) || b.map_or(false, expr_uses_super)
    TaggedTemplate(tag, _, _, exprs) =>
      expr_uses_super(tag) || exprs.iter().any(expr_uses_super)
    TemplateLiteral(_, exprs) => exprs.iter().any(expr_uses_super)
    As(inner, _) => expr_uses_super(inner)
    _ => false
  }
}

///|
fn block_uses_super(blk : @ast.TsBlock) -> Bool {
  blk.stmts.iter().any(stmt_uses_super)
}

///|
fn stmt_uses_super(s : @ast.TsStmt) -> Bool {
  match s {
    Expr(e) => expr_uses_super(e)
    Return(Some(e)) => expr_uses_super(e)
    Throw(e) => expr_uses_super(e)
    Let(bd, _, e) | Const(bd, _, e) | Var(bd, _, e) =>
      binding_subexprs(bd).iter().any(expr_uses_super) || expr_uses_super(e)
    Assign(_, e) => expr_uses_super(e)
    CompoundAssign(_, _, e) => expr_uses_super(e)
    IndexAssign(a, b, c) =>
      expr_uses_super(a) || expr_uses_super(b) || expr_uses_super(c)
    PropAssign(a, _, b) => expr_uses_super(a) || expr_uses_super(b)
    If(c, t, Some(f)) =>
      expr_uses_super(c) || block_uses_super(t) || block_uses_super(f)
    If(c, t, None) => expr_uses_super(c) || block_uses_super(t)
    While(c, b) => expr_uses_super(c) || block_uses_super(b)
    DoWhile(c, b) => expr_uses_super(c) || block_uses_super(b)
    For(init, cond, update, body) =>
      init.map_or(false, stmt_uses_super) ||
      cond.map_or(false, expr_uses_super) ||
      update.map_or(false, stmt_uses_super) ||
      block_uses_super(body)
    ForOf(_, bd, _, iter, body)
    | ForIn(_, bd, _, iter, body)
    | ForAwaitOf(_, bd, _, iter, body) =>
      binding_subexprs(bd).iter().any(expr_uses_super) ||
      expr_uses_super(iter) ||
      block_uses_super(body)
    Try(b, cbind, catch_b, finally_b) =>
      block_uses_super(b) ||
      cbind.map_or(false, fn(bd) {
        binding_subexprs(bd).iter().any(expr_uses_super)
      }) ||
      catch_b.map_or(false, block_uses_super) ||
      finally_b.map_or(false, block_uses_super)
    Switch(e, cases) =>
      expr_uses_super(e) || cases.iter().any(fn(c) { block_uses_super(c.body) })
    Block(b) => block_uses_super(b)
    Label(_, s) => stmt_uses_super(s)
    With(e, b) => expr_uses_super(e) || block_uses_super(b)
    _ => false
  }
}

// Peephole a declaration RHS with special handling for named function bindings.
// Goals:
//   1. `let f = function(){}` must NOT become an arrow — keep FuncExpr so
//      try_emit_function_decl can hoist it as `function f(){}`.
//   2. `let f = (...) => { block }` (block-body arrow) also converts to FuncExpr
//      for the same hoisting reason; block arrows are never shorter than the
//      equivalent function expression, and hoisting avoids TDZ issues in bundles.
//   3. `let f = x => x+1` and `let f = (x) => { return x+1; }` stay arrows
//      after peep_expr folds them to concise form (smaller, no hoisting needed).

///|
fn peep_decl_rhs(
  binding : @ast.TsBinding,
  rhs : @ast.TsExpr,
  ctx : PeepCtx,
) -> @ast.TsExpr {
  let name = match binding {
    @ast.TsBinding::Ident(n) => n
    _ => ""
  }
  if name != "" {
    match rhs {
      // `let f = function() {}` — fold the body but keep it as FuncExpr.
      @ast.TsExpr::FuncExpr(f) => {
        let folded = peep_block(f.body, ctx)
        return @ast.TsExpr::FuncExpr({ ..f, body: folded })
      }
      _ => ()
    }
  }
  let result = peep_expr(rhs, ctx)
  if name != "" {
    match result {
      // Block-body arrow after peephole: convert to FuncExpr for hoisting.
      // Concise arrows (ArrowExpr body) were either already concise or folded
      // from `{return expr}` — those stay arrows.
      @ast.TsExpr::ArrowFunc(
        params,
        ret,
        @ast.TsArrowBody::ArrowBlock(blk),
        is_async
      ) if !(block_uses_super(blk) || block_uses_this(blk)) =>
        @ast.TsExpr::FuncExpr({
          name: "",
          type_params: [],
          type_param_bounds: [],
          const_type_params: [],
          params,
          return_type: ret,
          body: blk,
          is_generator: false,
          is_async,
        })
      _ => result
    }
  } else {
    result
  }
}

///|
/// Rewrites that belong to a statement's position in a LIST rather than
/// to the statement itself, so every walker over a statement list can
/// share them. `None` means drop the statement.
///
/// Keeping them in one function is deliberate: `peephole_block` (the
/// top-level entry) and `peep_block` (every nested block) each run their
/// own loop, and while these two rules lived only in the second one,
/// nothing at the top level of a module was rewritten at all.
/// An object-literal entry whose computed key is a plain string literal
/// naming a valid identifier, as `(key, value)`. The parser stores such
/// an entry under the `@@computed:N` sentinel with the key expression on
/// a `ComputedProp` wrapper.
fn computed_prop_literal_key(
  entry : (String, @ast.TsExpr),
) -> (String, @ast.TsExpr)? {
  if !entry.0.has_prefix("@@computed:") {
    return None
  }
  match entry.1 {
    @ast.TsExpr::ComputedProp(@ast.TsExpr::StringLit(key), value) =>
      // `__proto__` is the one valid identifier this rewrite must not
      // produce: `{ ["__proto__"]: v }` defines an ordinary own
      // property, while `{ __proto__: v }` SETS THE PROTOTYPE. The two
      // spellings look interchangeable and are not.
      if is_valid_js_ident(key) && key != "__proto__" {
        Some((key, value))
      } else {
        None
      }
    _ => None
  }
}

///|
/// Recognise `typeof x === "undefined"` and its three siblings, for a
/// simple named operand. Returns the name and whether the comparison was
/// negated (`!==` / `!=`).
///
/// Both operand orders are accepted: `"undefined" === typeof x` is the
/// same test written the other way round, and real code has both.
fn typeof_undefined_operand(expr : @ast.TsExpr) -> (String, Bool)? {
  let (op, left, right) = match expr {
    BinOp(op, l, r) => (op, l, r)
    _ => return None
  }
  let negated = match op {
    BinEq | AbstractEq => false
    BinNe | AbstractNe => true
    _ => return None
  }
  fn name_of(e : @ast.TsExpr) -> String? {
    match e {
      UnaryOp(@ast.TsUnaryOp::Typeof, @ast.TsExpr::Var(n)) => Some(n)
      _ => None
    }
  }

  fn is_undefined_string(e : @ast.TsExpr) -> Bool {
    e is StringLit("undefined")
  }

  if is_undefined_string(right) {
    match name_of(left) {
      Some(n) => return Some((n, negated))
      None => ()
    }
  }
  if is_undefined_string(left) {
    match name_of(right) {
      Some(n) => return Some((n, negated))
      None => ()
    }
  }
  None
}

///|
/// What kind of value is this expression certainly? Only used to decide
/// whether a relational comparison can produce NaN.
priv enum CmpKind {
  CmpNum
  CmpStr
  CmpUnknown
}

///|
fn cmp_kind(e : @ast.TsExpr) -> CmpKind {
  match e {
    IntLit(_) | BigIntLit(_) => CmpNum
    // `NaN` itself is spelled as a name, and a literal NaN cannot be
    // written, so a numeric literal here is a real number.
    NumberLit(_) => CmpNum
    // A boolean coerces to 0 or 1.
    BoolLit(_) | UnaryOp(@ast.TsUnaryOp::Not, _) => CmpNum
    // Every bitwise operator returns a 32-bit integer.
    BinOp(BitAnd, _, _)
    | BinOp(BitOr, _, _)
    | BinOp(BitXor, _, _)
    | BinOp(Shl, _, _)
    | BinOp(Shr, _, _)
    | BinOp(UShr, _, _) => CmpNum
    // A comparison is a boolean, so it too coerces to 0 or 1.
    BinOp(BinEq, _, _)
    | BinOp(BinNe, _, _)
    | BinOp(AbstractEq, _, _)
    | BinOp(AbstractNe, _, _)
    | BinOp(BinLt, _, _)
    | BinOp(BinLe, _, _)
    | BinOp(BinGt, _, _)
    | BinOp(BinGe, _, _)
    | BinOp(Instanceof, _, _)
    | BinOp(In, _, _) => CmpNum
    // A collection size is a non-negative integer.
    PropAccess(_, "length") | PropAccess(_, "size") => CmpNum
    // `~x` is a 32-bit integer whatever `x` was.
    UnaryOp(@ast.TsUnaryOp::BitwiseNot, _) => CmpNum
    // `-x` is a number, but `-"abc"` is NaN — so only when `x` already
    // was a number.
    UnaryOp(@ast.TsUnaryOp::Neg, inner) =>
      match cmp_kind(inner) {
        CmpNum => CmpNum
        _ => CmpUnknown
      }
    // A tag-less template literal is always a string.
    StringLit(_) | TemplateLiteral(_, _) => CmpStr
    // `+` with a string operand is string concatenation, so the result
    // is a string whenever it does not throw — and it throws on exactly
    // the operands (a Symbol) that the other side would throw on too.
    BinOp(Add, l, r) =>
      if cmp_kind(l) is CmpStr || cmp_kind(r) is CmpStr {
        CmpStr
      } else {
        CmpUnknown
      }
    As(inner, _) | Satisfies(inner, _) | NonNull(inner) | TypeArgs(_, inner) =>
      cmp_kind(inner)
    _ => CmpUnknown
  }
}

///|
/// May `!(a REL b)` be rewritten as `a INV_REL b`? Only when the
/// comparison cannot go through NaN.
fn relational_negation_is_safe(a : @ast.TsExpr, b : @ast.TsExpr) -> Bool {
  match (cmp_kind(a), cmp_kind(b)) {
    (CmpNum, CmpNum) | (CmpStr, CmpStr) => true
    _ => false
  }
}

///|
/// Is this expression's value certainly a boolean?
///
/// `x === true` -> `x` and its three siblings are only sound for a
/// boolean `x`, and peephole runs on the erased AST with no types to
/// consult, so the answer has to come from the expression's own shape.
/// A bare `Var` is never accepted: that is exactly the case that was
/// getting this wrong.
fn expr_is_boolean_valued(e : @ast.TsExpr) -> Bool {
  match e {
    BoolLit(_) => true
    UnaryOp(@ast.TsUnaryOp::Not, _) => true
    // Every equality and relational operator yields a boolean.
    BinOp(BinEq, _, _)
    | BinOp(BinNe, _, _)
    | BinOp(AbstractEq, _, _)
    | BinOp(AbstractNe, _, _)
    | BinOp(BinLt, _, _)
    | BinOp(BinLe, _, _)
    | BinOp(BinGt, _, _)
    | BinOp(BinGe, _, _)
    | BinOp(Instanceof, _, _)
    | BinOp(In, _, _) => true
    // `&&` / `||` / `??` return one of their operands, so both have to
    // be booleans.
    BinOp(And, l, r) | BinOp(Or, l, r) | BinOp(Coalesce, l, r) =>
      expr_is_boolean_valued(l) && expr_is_boolean_valued(r)
    Cond(_, t, f) => expr_is_boolean_valued(t) && expr_is_boolean_valued(f)
    // `Boolean(x)` — the global. A bundle that shadows `Boolean` has
    // bigger problems than this rewrite.
    Call("Boolean", args) => args.length() == 1
    Seq(_, b) => expr_is_boolean_valued(b)
    As(inner, _) | Satisfies(inner, _) | NonNull(inner) | TypeArgs(_, inner) =>
      expr_is_boolean_valued(inner)
    _ => false
  }
}

///|
/// Is this condition true every time it is evaluated? Only the literal
/// spellings — anything requiring evaluation is not this function's
/// business.
fn expr_is_always_truthy(expr : @ast.TsExpr) -> Bool {
  match expr {
    BoolLit(true) => true
    // `!0`, which is what the BoolLit rewrite emits for `true`.
    UnaryOp(@ast.TsUnaryOp::Not, IntLit(0)) => true
    IntLit(n) => n != 0
    NumberLit(n) => n != 0.0 && n == n
    StringLit(s) => s != ""
    _ => false
  }
}

///|
fn peep_block_level(stmt : @ast.TsStmt) -> @ast.TsStmt? {
  // terser's `drop_debugger`, which is on by default there too. A
  // `debugger` statement is a development aid; nothing in a minified
  // bundle wants to break into a debugger at that point.
  if stmt is Debugger {
    return None
  }
  // An empty block is two bytes of nothing. It has no statements to
  // scope, so unlike a declarator group there is nothing its braces
  // could be holding.
  if stmt is Block(b) && b.stmts.length() == 0 {
    return None
  }
  match stmt {
    // A label nothing jumps to is dead. `L: for (…) {…}` with no
    // `break L` / `continue L` inside costs its name plus a colon and
    // changes nothing.
    //
    // Declined when the body re-declares the same label: an inner
    // `break L` then targets the inner one, and removing the outer label
    // would change which statement it means.
    Label(lname, inner) =>
      if !stmt_targets_label(inner, lname) &&
        !stmt_redeclares_label(inner, lname) {
        Some(inner)
      } else {
        Some(stmt)
      }
    _ => Some(stmt)
  }
}

///|
/// Does anything inside `stmt` jump to the label `name`?
///
/// Nested functions are not walked: `break`/`continue` cannot cross a
/// function boundary, so a label mentioned in there is a different one
/// (and would be a syntax error if it were not).
fn stmt_targets_label(stmt : @ast.TsStmt, name : String) -> Bool {
  match stmt {
    Break(Some(l)) | Continue(Some(l)) => l == name
    Block(b) => block_targets_label(b, name)
    Label(_, inner) => stmt_targets_label(inner, name)
    If(_, t, e) =>
      block_targets_label(t, name) ||
      (match e {
        Some(b) => block_targets_label(b, name)
        None => false
      })
    While(_, b) | DoWhile(_, b) => block_targets_label(b, name)
    For(init, _, update, b) =>
      (match init {
        Some(i) => stmt_targets_label(i, name)
        None => false
      }) ||
      (match update {
        Some(u) => stmt_targets_label(u, name)
        None => false
      }) ||
      block_targets_label(b, name)
    ForOf(_, _, _, _, b) | ForAwaitOf(_, _, _, _, b) | ForIn(_, _, _, _, b) =>
      block_targets_label(b, name)
    Switch(_, cases) => {
      for c in cases {
        if block_targets_label(c.body, name) {
          return true
        }
      }
      false
    }
    Try(b, _, cb, fb) =>
      block_targets_label(b, name) ||
      (match cb {
        Some(blk) => block_targets_label(blk, name)
        None => false
      }) ||
      (match fb {
        Some(blk) => block_targets_label(blk, name)
        None => false
      })
    With(_, b) => block_targets_label(b, name)
    _ => false
  }
}

///|
fn block_targets_label(block : @ast.TsBlock, name : String) -> Bool {
  for s in block.stmts {
    if stmt_targets_label(s, name) {
      return true
    }
  }
  false
}

///|
/// Is `name` declared again as a label anywhere inside `stmt`?
fn stmt_redeclares_label(stmt : @ast.TsStmt, name : String) -> Bool {
  match stmt {
    Label(l, inner) => l == name || stmt_redeclares_label(inner, name)
    Block(b) => block_redeclares_label(b, name)
    If(_, t, e) =>
      block_redeclares_label(t, name) ||
      (match e {
        Some(b) => block_redeclares_label(b, name)
        None => false
      })
    While(_, b) | DoWhile(_, b) => block_redeclares_label(b, name)
    For(_, _, _, b) => block_redeclares_label(b, name)
    ForOf(_, _, _, _, b) | ForAwaitOf(_, _, _, _, b) | ForIn(_, _, _, _, b) =>
      block_redeclares_label(b, name)
    Switch(_, cases) => {
      for c in cases {
        if block_redeclares_label(c.body, name) {
          return true
        }
      }
      false
    }
    Try(b, _, cb, fb) =>
      block_redeclares_label(b, name) ||
      (match cb {
        Some(blk) => block_redeclares_label(blk, name)
        None => false
      }) ||
      (match fb {
        Some(blk) => block_redeclares_label(blk, name)
        None => false
      })
    With(_, b) => block_redeclares_label(b, name)
    _ => false
  }
}

///|
fn block_redeclares_label(block : @ast.TsBlock, name : String) -> Bool {
  for s in block.stmts {
    if stmt_redeclares_label(s, name) {
      return true
    }
  }
  false
}

///|
/// terser's `sequences`, in the one position where it pays for itself:
/// a loop body of leading expression statements plus one final
/// statement collapses to a single statement, and a single-statement
/// loop body needs no braces.
///
///     for (;;) { i++; if (i > 2) return i; }
///     for (;;) if (i++, i > 2) return i;
///
/// The comma itself is free — `a;b` and `a,b` are the same length — so
/// the entire win is the two braces, which is why this only fires when
/// the merge leaves EXACTLY one statement. Evaluation order is
/// unchanged: a comma expression evaluates left to right and discards
/// every value but the last, which is what a run of expression
/// statements does.
///
/// Only expression statements are absorbed, so nothing here can move a
/// declaration into or out of a scope.
fn collapse_loop_body(b : @ast.TsBlock) -> @ast.TsBlock {
  let n = b.stmts.length()
  if n < 2 {
    return b
  }
  for i in 0..<(n - 1) {
    if !(b.stmts[i] is Expr(_)) {
      return b
    }
  }
  let mut lead = match b.stmts[0] {
    Expr(e) => e
    _ => return b
  }
  for i in 1..<(n - 1) {
    match b.stmts[i] {
      Expr(e) => lead = @ast.TsExpr::Seq(lead, e)
      _ => return b
    }
  }
  let merged : @ast.TsStmt = match b.stmts[n - 1] {
    Expr(e) => Expr(Seq(lead, e))
    Return(Some(e)) => Return(Some(Seq(lead, e)))
    Throw(e) => Throw(Seq(lead, e))
    If(cond, t, e) => If(Seq(lead, cond), t, e)
    Switch(disc, cases) => Switch(Seq(lead, disc), cases)
    // `Return(None)`, `Break`, `Continue` carry no expression to merge
    // into, and a declaration cannot be brace-less anyway.
    _ => return b
  }
  { stmts: [merged], stmt_positions: [] }
}

///|
/// The statements a side-effect-only IIFE can be replaced by, or `None`
/// when it cannot.
///
///     (function () { globalThis.__sink = 1; })();
///     globalThis.__sink = 1;
///
/// terser calls its version of this `negate_iife`; the byte win here is
/// the wrapper itself — 13 bytes for `(function(){})()`, 8 for the arrow
/// form — not the negation.
///
/// The conditions are all about what the wrapper was providing:
///
///   * A SCOPE. Any declaration in the body is scoped by the wrapper,
///     and splicing it out moves the binding into the enclosing scope,
///     where it can collide with a binding already there (a SyntaxError
///     for `let`, silent aliasing for `var`). So the body has to be
///     expression statements and nothing else — which also rules out
///     `return`, whose value would now have nowhere to go.
///   * A `this` / `arguments` BINDING, for the `function` form. Called
///     as `f()`, `this` inside is `undefined` in a module and the body's
///     `arguments` is its own; spliced out, both mean something else.
///     An arrow never had either — it reads them from the same
///     enclosing function the splice lands in — so the arrow form needs
///     no such check.
///   * A call BOUNDARY, for `async` / generator wrappers: those do not
///     run their body to completion at the call site at all.
fn iife_splice_stmts(stmt : @ast.TsStmt) -> Array[@ast.TsStmt]? {
  let (body, needs_this_check) = match stmt {
    Expr(CallExpr(FuncExpr(f), args)) =>
      if args.is_empty() &&
        f.params.is_empty() &&
        !f.is_async &&
        !f.is_generator {
        (f.body, true)
      } else {
        return None
      }
    Expr(CallExpr(ArrowFunc(params, _, body, is_async), args)) =>
      if args.is_empty() && params.is_empty() && !is_async {
        match body {
          @ast.TsArrowBody::ArrowBlock(b) => (b, false)
          // `(() => sideEffect())()` — the concise form has no
          // statements to check at all.
          @ast.TsArrowBody::ArrowExpr(e) => return Some([@ast.TsStmt::Expr(e)])
        }
      } else {
        return None
      }
    _ => return None
  }
  for s in body.stmts {
    if !(s is Expr(_)) {
      return None
    }
  }
  if needs_this_check &&
    (
      block_uses_this(body) ||
      block_uses_super(body) ||
      block_references_name(body, "arguments")
    ) {
    return None
  }
  let out : Array[@ast.TsStmt] = []
  for s in body.stmts {
    out.push(s)
  }
  Some(out)
}

///|
fn peep_block(block : @ast.TsBlock, ctx : PeepCtx) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  // A function declaration after the terminator is NOT unreachable —
  // it is hoisted, so the code before the `return` can call it, and
  // `return f;` can hand it out. TypeScript's own `typescript.js` is
  // built that way:
  //
  //     var createUIStringComparer = (() => {
  //       return createIntlCollatorStringComparer;
  //       function createIntlCollatorStringComparer(locale) { … }
  //     })();
  //
  // Dropping those left `return f` pointing at nothing, so loading the
  // minified compiler threw `ReferenceError`. Collected here and
  // spliced back in before the terminator, the same way `fold_block`
  // handles it.
  let hoisted : Array[@ast.TsStmt] = []
  // Everything else after the first hard terminator (Return / Throw /
  // Break / Continue) really is unreachable and gets dropped.
  let mut exited = false
  for s in block.stmts {
    if exited {
      if stmt_is_hoisted_function(s) {
        hoisted.push(peep_stmt(s, ctx))
      }
      continue
    }
    let ps = peep_stmt(s, ctx)
    let ps = match peep_block_level(ps) {
      Some(replacement) => replacement
      None => continue
    }
    // `(function () { sideEffect(); })();` → `sideEffect();`
    match iife_splice_stmts(ps) {
      Some(spliced) => {
        for s in spliced {
          stmts.push(s)
        }
        continue
      }
      None => ()
    }
    // `if (c) { …; return; } else { stmts }` → `if (c) { …; return; }` +
    // `stmts` spliced inline. Saves the `else ` keyword (5 bytes) and the
    // braces (2 bytes) for every such pattern.
    match ps {
      // The braces are not only control flow: a `let` / `const` / class
      // inside the else block is scoped BY them, and splicing it into
      // the enclosing block can collide with a same-named binding
      // already there — a SyntaxError, so nothing in the file loads.
      // `block_declares_lexical` (fold.mbt) is the same guard the
      // else-hoist in `fold_stmt_into` uses; this is the second copy of
      // that rewrite and it needs the same condition.
      If(cond, then_block, Some(else_block)) if block_ends_with_terminator(
          then_block,
        ) &&
        !block_declares_lexical(else_block) => {
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
          Return(_) | Throw(_) | Break(_) | Continue(_) => exited = true
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
      // `let/const/var x = expr; return x;` → `return expr;` — unless
      // `expr` refers to `x` itself. A self-referential initializer is
      // ordinary JavaScript when the reference is deferred into a
      // closure, and TypeScript's own compiler host is built that way:
      //
      //     const compilerHost = {
      //       getSourceFile: withCache(f => compilerHost.readFile(f)),
      //       …
      //     };
      //     return compilerHost;
      //
      // Fold that and the closure points at a name that no longer
      // exists — or, after mangling, at whatever else now holds the
      // short name. Here it silently became a different function, so
      // every lib file read came back empty and the minified compiler
      // reported `Cannot find name 'Math'`.
      (Let(Ident(vname), _, init), Return(Some(Var(rname)))) if foldable_tail_decl(
          vname, rname, init,
        ) => {
        stmts[n - 2] = Return(Some(peep_expr(init, ctx)))
        stmts.pop() |> ignore
        folded = true
      }
      (Const(Ident(vname), _, init), Return(Some(Var(rname)))) if foldable_tail_decl(
          vname, rname, init,
        ) => {
        stmts[n - 2] = Return(Some(peep_expr(init, ctx)))
        stmts.pop() |> ignore
        folded = true
      }
      (Var(Ident(vname), _, init), Return(Some(Var(rname)))) if foldable_tail_decl(
          vname, rname, init,
        ) => {
        stmts[n - 2] = Return(Some(peep_expr(init, ctx)))
        stmts.pop() |> ignore
        folded = true
      }
      _ => ()
    }
  }
  // Put the hoisted declarations back, just before the terminator they
  // followed. Their position in the source does not matter — hoisting
  // is what makes them visible — but keeping them inside the block does.
  if hoisted.length() > 0 {
    let exit_idx = stmts.length() - 1
    let result : Array[@ast.TsStmt] = []
    for j, st in stmts {
      if j == exit_idx {
        for h in hoisted {
          result.push(h)
        }
      }
      result.push(st)
    }
    return { stmts: result, stmt_positions: [] }
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
/// `let x = expr; return x;` collapses only when `x` is what is
/// returned and `expr` does not refer to `x` itself.
fn foldable_tail_decl(
  vname : String,
  rname : String,
  init : @ast.TsExpr,
) -> Bool {
  vname == rname && !expr_refers_to(init, vname)
}

///|
/// Does `expr` mention `name` anywhere, nested functions included?
///
/// `collect_var_refs_in_expr_local` deliberately stops at a function
/// boundary. For a self-reference check that is exactly the wrong place
/// to stop: the reference that matters is the one inside a closure,
/// where it is legal precisely because it is deferred.
fn expr_refers_to(expr : @ast.TsExpr, name : String) -> Bool {
  let refs : Map[String, Bool] = {}
  collect_var_refs_in_expr(expr, refs)
  refs.contains(name)
}

///|
/// A statement that declares a function and therefore hoists. The
/// parser lowers `function f() {}` to `let f = function f() {}`, which
/// loses the hoisting in the AST but not in the emitted JavaScript —
/// `try_emit_function_decl` writes it back out as a declaration.
fn stmt_is_hoisted_function(s : @ast.TsStmt) -> Bool {
  match s {
    Let(_, _, FuncExpr(_))
    | Var(_, _, FuncExpr(_))
    | Const(_, _, FuncExpr(_)) => true
    _ => false
  }
}

///|
fn peep_expr(expr : @ast.TsExpr, ctx : PeepCtx) -> @ast.TsExpr {
  // terser's `typeofs`: `typeof x === "undefined"` -> `void 0 === x`,
  // eleven bytes, and it appears in guard code everywhere.
  //
  // The two are NOT interchangeable in general: `typeof x` is `"undefined"`
  // for an UNDECLARED `x`, while `void 0 === x` throws a ReferenceError.
  // So the rewrite is gated on `x` being a name this bundle declares —
  // `ctx.undeclared` holds the ones it does not, which are the host
  // globals a feature test would be probing for. That is exactly the
  // case that must keep `typeof`.
  match typeof_undefined_operand(expr) {
    Some((name, negated)) =>
      if !ctx.undeclared.contains(name) {
        let cmp = if negated {
          @ast.TsBinOp::BinNe
        } else {
          @ast.TsBinOp::BinEq
        }
        return BinOp(cmp, UnaryOp(@ast.TsUnaryOp::Void, IntLit(0)), Var(name))
      }
    None => ()
  }
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
      if name == "undefined" && !ctx.undefined_shadowed {
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
        // `a || (b || c)` → `(a || b) || c`. `||` and `&&` are
        // left-associative, so the emitter has to parenthesize a
        // right-nested one and the parens are 2 bytes for nothing.
        // Short-circuit order is identical in both spellings: the
        // operands are still evaluated left to right, and each still
        // stops the chain on the same value.
        //
        // `fold_guard_return` produces exactly this shape — nested
        // guard clauses collapse inner-first, so `if (a) return;
        // if (b) return; g()` arrives here as `a || (b || g())`.
        Or if rp is BinOp(Or, _, _) =>
          match rp {
            BinOp(_, rl, rr) => BinOp(Or, BinOp(Or, lp, rl), rr)
            _ => BinOp(op, lp, rp)
          }
        And if rp is BinOp(And, _, _) =>
          match rp {
            BinOp(_, rl, rr) => BinOp(And, BinOp(And, lp, rl), rr)
            _ => BinOp(op, lp, rp)
          }
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
            // `typeof x === "undefined"` → `x === void 0`  (saves ~9 bytes)
            // `"undefined" === typeof x` → `x === void 0`
            // Only safe when x is not a bare Var — undeclared globals like
            // `document`, `window`, `DOMParser` throw ReferenceError when
            // accessed directly; `typeof` is the safe guard for those.
            (
              UnaryOp(@ast.TsUnaryOp::Typeof, @ast.TsExpr::Var(_)),
              StringLit("undefined"),
            )
            | (
              StringLit("undefined"),
              UnaryOp(@ast.TsUnaryOp::Typeof, @ast.TsExpr::Var(_)),
            ) => BinOp(op, lp, rp)
            // `typeof void 0 === "undefined"` → `!0`. The rule below
            // rewrites the whole comparison to `x === void 0`, and when
            // `x` is itself `void 0` the result is a 14-byte constant
            // that nothing after this pass will fold: `fold` DOES have
            // this rule (`both_literal_undefined`), but `fold-2` runs
            // BEFORE peephole, and it is peephole that creates the
            // shape. `f(undefined)` inlined into a body of
            // `typeof x === "undefined"` shipped as
            // `void 0 === void 0` for exactly that reason.
            (
              UnaryOp(@ast.TsUnaryOp::Typeof, @ast.TsExpr::UnaryOp(Void, _)),
              StringLit("undefined"),
            )
            | (
              StringLit("undefined"),
              UnaryOp(@ast.TsUnaryOp::Typeof, @ast.TsExpr::UnaryOp(Void, _)),
            ) => UnaryOp(@ast.TsUnaryOp::Not, IntLit(0))
            (UnaryOp(@ast.TsUnaryOp::Typeof, x), StringLit("undefined"))
            | (StringLit("undefined"), UnaryOp(@ast.TsUnaryOp::Typeof, x)) =>
              BinOp(
                @ast.TsBinOp::BinEq,
                x,
                UnaryOp(@ast.TsUnaryOp::Void, IntLit(0)),
              )
            // The same constant, arrived at from the other direction:
            // an inline substituted `void 0` into a comparison that was
            // already `x === void 0`.
            (UnaryOp(Void, a), UnaryOp(Void, b)) if is_pure_value(a) &&
              is_pure_value(b) => UnaryOp(@ast.TsUnaryOp::Not, IntLit(0))
            // `x === true` / `x === !0` → `x`  (saves 7 bytes)
            // `x === false` / `x === !1` → `!x`  (saves 6 bytes)
            //
            // Only when `x` IS a boolean. The comment here used to
            // assert that and nothing checked it: for `x = 1`,
            // `x === true` is false while `x` is truthy; for `x = 0`,
            // `x === false` is false while `!x` is true.
            (x, BoolLit(true))
            | (BoolLit(true), x)
            | (x, UnaryOp(@ast.TsUnaryOp::Not, IntLit(0)))
            | (UnaryOp(@ast.TsUnaryOp::Not, IntLit(0)), x) if expr_is_boolean_valued(
                x,
              ) => x
            (x, BoolLit(false))
            | (BoolLit(false), x)
            | (x, UnaryOp(@ast.TsUnaryOp::Not, IntLit(1)))
            | (UnaryOp(@ast.TsUnaryOp::Not, IntLit(1)), x) if expr_is_boolean_valued(
                x,
              ) => UnaryOp(@ast.TsUnaryOp::Not, x)
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
            // `typeof x !== "undefined"` → `x !== void 0`  (saves ~9 bytes)
            // Only safe when x is not a bare Var — undeclared globals like
            // `document`, `window`, `DOMParser` throw ReferenceError when
            // accessed directly; `typeof` is the safe guard for those.
            (
              UnaryOp(@ast.TsUnaryOp::Typeof, @ast.TsExpr::Var(_)),
              StringLit("undefined"),
            )
            | (
              StringLit("undefined"),
              UnaryOp(@ast.TsUnaryOp::Typeof, @ast.TsExpr::Var(_)),
            ) => BinOp(op, lp, rp)
            // The `!==` mirror of the `===` constant above.
            (
              UnaryOp(@ast.TsUnaryOp::Typeof, @ast.TsExpr::UnaryOp(Void, _)),
              StringLit("undefined"),
            )
            | (
              StringLit("undefined"),
              UnaryOp(@ast.TsUnaryOp::Typeof, @ast.TsExpr::UnaryOp(Void, _)),
            ) => UnaryOp(@ast.TsUnaryOp::Not, IntLit(1))
            (UnaryOp(@ast.TsUnaryOp::Typeof, x), StringLit("undefined"))
            | (StringLit("undefined"), UnaryOp(@ast.TsUnaryOp::Typeof, x)) =>
              BinOp(
                @ast.TsBinOp::BinNe,
                x,
                UnaryOp(@ast.TsUnaryOp::Void, IntLit(0)),
              )
            (UnaryOp(Void, a), UnaryOp(Void, b)) if is_pure_value(a) &&
              is_pure_value(b) => UnaryOp(@ast.TsUnaryOp::Not, IntLit(1))
            // `x !== true` / `x !== !0` → `!x`  (saves 6 bytes)
            // `x !== false` / `x !== !1` → `x`  (saves 7 bytes)
            //
            // Same gate as `===`, and this is the one caught in the
            // wild: `symbol.constEnumOnlyModule !== false` is `true`
            // when the field is `undefined`, while
            // `symbol.constEnumOnlyModule` is `undefined`. TypeScript's
            // binder writes exactly that.
            (x, BoolLit(true))
            | (BoolLit(true), x)
            | (x, UnaryOp(@ast.TsUnaryOp::Not, IntLit(0)))
            | (UnaryOp(@ast.TsUnaryOp::Not, IntLit(0)), x) if expr_is_boolean_valued(
                x,
              ) => UnaryOp(@ast.TsUnaryOp::Not, x)
            (x, BoolLit(false))
            | (BoolLit(false), x)
            | (x, UnaryOp(@ast.TsUnaryOp::Not, IntLit(1)))
            | (UnaryOp(@ast.TsUnaryOp::Not, IntLit(1)), x) if expr_is_boolean_valued(
                x,
              ) => x
            (lp, rp) => BinOp(op, lp, rp)
          }
        // `x.length > 0` → `!!x.length`  (saves ~3 bytes; length is non-negative)
        // `x.length <= 0` → `!x.length`  (saves ~4 bytes)
        // `0 < x.length` / `0 >= x.length` — swapped forms
        BinGt =>
          match (lp, rp) {
            _ => BinOp(op, lp, rp)
          }
        BinLe =>
          match (lp, rp) {
            _ => BinOp(op, lp, rp)
          }
        // `"a" + "b"` → `"ab"`  (string constant folding; saves quotes + operator)
        // Produced when template literals like `"prefix" + x + "suffix"` get
        // partially evaluated, leaving adjacent string literals next to each other.
        // Also handles `"" + ""` → `""` (empty-string identity).
        Add =>
          match (lp, rp) {
            (StringLit(a), StringLit(b)) => StringLit(a + b)
            // `n + m` → constant  (integer literal arithmetic folding).
            (IntLit(a), IntLit(b)) => IntLit(a + b)
            // `0 + x` / `x + 0` → `x`.
            //
            // The old comment claimed this was "only safe when the other
            // operand is an integer literal (so no string coercion
            // occurs)" — but the pattern matched ANY other operand, so
            // `undefined + 0` became `undefined` instead of `NaN` and
            // `"a" + 0` became `"a"` instead of `"a0"`. Even for a
            // number it needs care: `-0 + 0` is `0` while `-0` is `-0`.
            // `fold.mbt` gates the same rule; this copy did not.
            (IntLit(0), _) if is_number_never_negzero(rp) => rp
            (_, IntLit(0)) if is_number_never_negzero(lp) => lp
            _ => BinOp(op, lp, rp)
          }
        // `n - m` → constant  (integer literal subtraction).
        Sub =>
          match (lp, rp) {
            (IntLit(a), IntLit(b)) => IntLit(a - b)
            // `x - 0` → `x`. `-0 - 0` is `-0`, so this one only needs
            // the operand to be a number at all.
            (_, IntLit(0)) if is_number_valued(lp) => lp
            _ => BinOp(op, lp, rp)
          }
        // `n * m` → constant  (integer literal multiplication).
        Mul =>
          match (lp, rp) {
            (IntLit(a), IntLit(b)) => IntLit(a * b)
            // `x * 1` / `1 * x` → `x`
            (_, IntLit(1)) if is_number_valued(lp) => lp
            (IntLit(1), _) if is_number_valued(rp) => rp
            // `x * 0` / `0 * x` → `0` is NOT folded here: `-1 * 0` is
            // `-0` and `"a" * 0` is `NaN`. `fold.mbt` does it under a
            // non-negative-number gate.
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
        // The RELATIONAL negations are not the same shape of fact as the
        // equality ones above. `!(a < b)` is `a >= b` only when the
        // comparison is not NaN-based, and every NaN comparison is false,
        // so both `a < b` and `a >= b` come out false while `!(a < b)` is
        // true:
        //
        //   a = undefined, b = 1 -> !(a < b) is true,  a >= b is false
        //   a = "x",       b = 3 -> !(a < b) is true,  a >= b is false
        //
        // `undefined` is not an exotic input, so this is gated on both
        // operands being comparable without NaN — two numbers, or two
        // strings. See `relational_negation_is_safe`.
        BinOp(@ast.TsBinOp::BinLt, a, b) if relational_negation_is_safe(a, b) =>
          BinOp(@ast.TsBinOp::BinGe, a, b)
        BinOp(@ast.TsBinOp::BinLe, a, b) if relational_negation_is_safe(a, b) =>
          BinOp(@ast.TsBinOp::BinGt, a, b)
        BinOp(@ast.TsBinOp::BinGt, a, b) if relational_negation_is_safe(a, b) =>
          BinOp(@ast.TsBinOp::BinLe, a, b)
        BinOp(@ast.TsBinOp::BinGe, a, b) if relational_negation_is_safe(a, b) =>
          BinOp(@ast.TsBinOp::BinLt, a, b)
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
                Var("undefined") if !ctx.undefined_shadowed => true
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
                  // NOTE: `x != null ? x.method(a) : void 0` is NOT converted to
                  // `x?.method(a)` — `OptionalChain(MethodCall)` emits as
                  // `x.method?.(a)` (optional call), not `x?.method(a)` (optional
                  // access). These differ when x is undefined: `x.method?.(a)`
                  // throws accessing `.method` on undefined.
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
            // TypeScript sometimes emits the eq-form for null-default patterns.
            BinOp(@ast.TsBinOp::AbstractEq, check_x, NullLit) => {
              let is_void_then = match t_val {
                UnaryOp(@ast.TsUnaryOp::Void, _) => true
                Var("undefined") if !ctx.undefined_shadowed => true
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
                  // NOTE: MethodCall not converted — see note above for AbstractNe.
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
                // NOTE: `c ? expr : void 0` → `c && expr` is NOT applied here.
                // `c && expr` returns `c` (not undefined) when c is falsy.
                // `null ? x : void 0` returns undefined, but `null && x` returns null.
                // Code that distinguishes null/undefined would silently misbehave.
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
          // `String(x)` -> `"" + x` saves 6 bytes and is NOT the same
          // conversion: `String` calls ToString, `+` calls ToPrimitive
          // with a DEFAULT hint. A Symbol is the sharp end —
          // `String(sym)` is `"Symbol(s)"` and `"" + sym` throws — and
          // any object with both `valueOf` and `toString` differs
          // quietly. Only take it when the operand is already a string
          // or a number.
          if cmp_kind(new_args[0]) is (CmpStr | CmpNum) {
            return BinOp(@ast.TsBinOp::Add, StringLit(""), new_args[0])
          }
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
      // `Math.pow(x, y)` → `x**y` (saves up to 8 bytes).
      //
      // These two agree on every value but one pair: `Math.pow` coerces
      // with ToNumber, which THROWS on a BigInt, while `**` computes.
      // `Math.pow(10n, 10n)` is a TypeError and `10n ** 10n` is
      // 10000000000. A mixed pair throws either way, so proving that
      // ONE operand cannot be a BigInt is enough — which a non-BigInt
      // literal on either side does, and that covers the common
      // `Math.pow(x, 2)`. Found by
      // `scripts/verify_rule_equivalence.mjs`.
      if m == "pow" && new_args.length() == 2 {
        match recv_p {
          Var("Math") =>
            if is_definitely_not_bigint(new_args[0]) ||
              is_definitely_not_bigint(new_args[1]) {
              return BinOp(@ast.TsBinOp::Pow, new_args[0], new_args[1])
            }
          _ => ()
        }
      }
      // `Array.from(x)` → `[...x]` (saves ~6 bytes; single-arg only —
      // two-arg form has a map function and must be left alone).
      //
      // Gated on the receiver being provably ITERABLE, which is not the
      // same set `Array.from` accepts: it also takes an array-LIKE, an
      // object with `length` and index properties and no
      // `Symbol.iterator`. `Array.from({ length: 256 })` is 256
      // `undefined`s; `[...{ length: 256 }]` throws. typebox's
      // `hash.ts` does exactly that and the bundle died on load.
      //
      // The `Array.prototype.slice.call` rewrite three lines below had
      // already been removed for this same reason, which is the part
      // worth noticing: the knowledge was adjacent and the rule shipped
      // anyway, because nothing asked this rule the question. It is in
      // `scripts/verify_rule_equivalence.mjs` now.
      if m == "from" && new_args.length() == 1 {
        match recv_p {
          Var("Array") =>
            if is_definitely_iterable(new_args[0]) {
              return ArrayLit([Spread(new_args[0])])
            }
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
        // (removed) `Array.prototype.slice.call(x, 0)` -> `[...x]`.
        // `slice` works on any array-LIKE — an object with `length` and
        // index properties — while a spread needs an ITERABLE. So
        // `Array.prototype.slice.call(0, 0)` is `[]` and `[...0]`
        // throws, and the same goes for `arguments`-shaped objects in
        // code that has not been through a transpiler. Found by
        // `scripts/verify_rule_equivalence.mjs`.
        ignore(recv_p)
      }
      // (removed) `Array.prototype.METHOD.call(x, …)` -> `x.METHOD(…)`.
      //
      // The old comment said this is safe "when the first argument is a
      // plain array or a var", and a var is not a proof of anything.
      // Two ways apart, and the rewrite is on the wrong side of both:
      //
      //   * The `.call` form names the built-in EXPLICITLY and works on
      //     anything array-like or iterable — a string, `arguments`, a
      //     NodeList, `{ length: 2, 0: "a", 1: "b" }`. The direct call
      //     needs the receiver to HAVE that method, so all of those
      //     become `TypeError: x.indexOf is not a function`.
      //   * Where the receiver DOES have a same-named method, the
      //     rewrite calls that one instead of the built-in — the same
      //     mistake as the removed `x.hasOwnProperty(k)` rewrite below.
      //
      // Which is why `slice` was already excluded here: it was the one
      // instance somebody had hit. Found for the whole family by
      // `scripts/verify_rule_equivalence.mjs`.
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
      // (removed) `x.hasOwnProperty(key)` -> `Object.hasOwn(x, key)`.
      // The old comment said the direct call is "subtly unsafe if the
      // prototype chain is modified, but for bundled code it's
      // equivalent" — which gets the direction backwards. The rewrite
      // REPLACES whatever `x.hasOwnProperty` resolves to with the
      // built-in, so an object that defines its own `hasOwnProperty`
      // (a parsed JSON payload, a config bag) stops calling it. The
      // `Object.prototype.hasOwnProperty.call(x, k)` form above names
      // the built-in explicitly and is kept.
      // `Object.assign({}, a, b, …)` → `{...a, ...b, …}` (object spread).
      // `Object.assign({x:1}, a, b)` → `{x:1, ...a, ...b}` (literal target).
      // Safe when the first argument is an object literal (creates a fresh
      // copy; the target is never shared). Sources are inlined or spread.
      if m == "assign" && new_args.length() >= 2 {
        match (recv_p, new_args[0]) {
          (Var("Object"), @ast.TsExpr::ObjectLit(init_ents)) => {
            // Bail if any source is a Spread call-arg. `Object.assign({}, ...arr, x)`
            // expands `arr` as multiple arguments at call time (each element merged
            // separately), which is NOT the same as `{...arr, ...x}` where `arr` is
            // spread as a numeric-keyed object. Only convert when all sources are
            // plain expressions.
            let has_spread_arg = new_args
              .iter()
              .drop(1)
              .any(fn(a) { a is Spread(_) })
            if has_spread_arg {
              ()
            } else {
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
          }
          _ => ()
        }
      }
      // `[].concat([a], [b], …)` → `[a, b, …]` (array spread).
      // TypeScript's `__spreadArray` helper or manual concatenation emits this.
      //
      // Every argument must be an array LITERAL, and the reason is that
      // `concat` and spread disagree about non-arrays in the loudest
      // possible way: `concat` APPENDS a non-array as one element, so
      // `[].concat(undefined)` is `[undefined]` and `[].concat(1)` is
      // `[1]`, while `[...undefined]` and `[...1]` both throw. The old
      // code spread anything that was not a literal. Found by
      // `scripts/verify_rule_equivalence.mjs`.
      if m == "concat" && new_args.length() >= 1 {
        let all_array_lits = new_args.iter().all(fn(a) { a is ArrayLit(_) })
        match recv_p {
          ArrayLit([]) if all_array_lits => {
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
          @ast.TsExpr::Var("undefined") if !ctx.undefined_shadowed => true
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
      //
      // The args list must be provably iterable, and `apply` accepts
      // more than that: an array-LIKE, and also `null` / `undefined`,
      // which mean "no arguments". `f.apply(null, undefined)` calls `f()`
      // and `f(...undefined)` throws. The comment used to say "only fold
      // the single-arg form where the array arg is known" — the arity was
      // checked and the "known" was not. Found by
      // `scripts/verify_rule_equivalence.mjs`.
      if m == "apply" && new_args.length() == 2 {
        let is_null_this = match new_args[0] {
          @ast.TsExpr::NullLit => true
          @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, _) => true
          @ast.TsExpr::Var("undefined") if !ctx.undefined_shadowed => true
          _ => false
        }
        if is_null_this && is_definitely_iterable(new_args[1]) {
          return CallExpr(recv_p, [Spread(new_args[1])])
        }
      }
      // (removed) `x.slice(0)` -> `[...x]`.
      //
      // `slice` is a method on Array AND on String, and the two return
      // different kinds of thing: `"ab".slice(0)` is the string `"ab"`,
      // `[..."ab"]` is `["a", "b"]`. It also reaches array-likes through
      // `.call`, where a spread throws. The old comment reasoned only
      // about "shallow copy of array" — which is correct about arrays and
      // says nothing about why the receiver must be one. Found by
      // `scripts/verify_rule_equivalence.mjs`.
      //
      // An `ArrayLit` receiver would be provable, and pointless:
      // `[...[1, 2]]` is longer than `[1, 2].slice(0)` is worth.
      // (removed) `x.toString()` -> `"" + x`. Three ways apart:
      //
      //   * `undefined.toString()` throws; `"" + undefined` is
      //     `"undefined"`. Same for `null`.
      //   * `+` uses ToPrimitive with a DEFAULT hint, so it prefers
      //     `valueOf`. An object with both — a Date, a boxed number, a
      //     value object — stringifies differently.
      //   * a Symbol's `toString()` works while `"" + sym` throws.
      //
      // The old comment said "safe for all non-Symbol values", which is
      // two of those three. Found by
      // `scripts/verify_rule_equivalence.mjs`.
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
    // terser's `computed_props`: a computed key that is a string
    // literal is just that key. `{ ["a"]: 1 }` -> `{ a: 1 }`, four
    // bytes, and it is what a spread-and-rename codemod leaves behind.
    ObjectLit(entries) if entries
      .iter()
      .any(fn(ent) { computed_prop_literal_key(ent) is Some(_) }) => {
      let rebuilt : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        match computed_prop_literal_key(ent) {
          Some((key, value)) => rebuilt.push((key, peep_expr(value, ctx)))
          None => rebuilt.push((ent.0, peep_expr(ent.1, ctx)))
        }
      }
      ObjectLit(rebuilt)
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
      // Parameter defaults are evaluated in the callee's scope, so
      // `function (x = this.y) {}` reads the callee's `this` just as a
      // body reference would.
      let param_exprs = param_subexprs(f.params)
      let can_arrow = !f.is_generator &&
        f.name == "" &&
        !folded.stmts.is_empty() &&
        !block_references_name(folded, "this") &&
        !block_references_name(folded, "arguments") &&
        !param_exprs.iter().any(fn(e) { expr_references_name(e, "this") }) &&
        !param_exprs.iter().any(fn(e) { expr_references_name(e, "arguments") })
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
      } else if new_exprs.length() == 1 &&
        parts.length() == 2 &&
        parts[1] == "" &&
        // Template interpolation is ToString; `+` is ToPrimitive with a
        // DEFAULT hint, which prefers `valueOf`. For an object with both
        // — a Date, a boxed number, any value object — the two produce
        // different strings, and for a Symbol one throws and the other
        // does not. So the saving is only available when the hole is
        // already a string.
        cmp_kind(new_exprs[0]) is CmpStr {
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
/// Is `expr` something a spread can consume — i.e. does it certainly
/// have a `Symbol.iterator`?
///
/// This is the guard on every rewrite that replaces a built-in with a
/// spread, and it exists because those built-ins accept a WIDER set.
/// `Array.from`, `Array.prototype.slice.call` and `Function.prototype
/// .apply` all take an array-LIKE — an object with `length` and index
/// properties — where a spread throws. Three separate rewrites shipped
/// on the assumption that array-like and iterable are the same set;
/// they are not, and `{ length: n }` is the common way to say so.
///
/// The answer here is syntactic, so it is deliberately narrow: no
/// expression whose type we cannot read off its own shape qualifies. A
/// `Var` never does, however obviously an array it looks in context.
fn is_definitely_iterable(expr : @ast.TsExpr) -> Bool {
  match expr {
    // Literals whose iterability is part of the syntax.
    ArrayLit(_) | StringLit(_) | TemplateLiteral(_, _) => true
    // `new Set(…)` / `new Map(…)` / `new Array(…)` — the constructor
    // names the result's type. (A user-shadowed `Set` would break this,
    // and shadowing a global built-in constructor is already outside
    // what every other rule in this file assumes.)
    New("Set", _) | New("Map", _) | New("Array", _) => true
    // A parenthesized or type-annotated wrapper is transparent here.
    // Missing this is how a wrapper node costs a rewrite (see the
    // `TypeArgs` and `PureCall` families), so peel rather than default.
    TypeArgs(_, inner) | As(inner, _) | Satisfies(inner, _) | NonNull(inner) =>
      is_definitely_iterable(inner)
    _ => false
  }
}

///|
/// Can `expr` be ruled out as a BigInt from its shape alone?
///
/// Only `Math.pow` -> `**` needs this, and it needs surprisingly little:
/// the two agree everywhere except when BOTH operands are BigInts
/// (`Math.pow` coerces with ToNumber, which throws; `**` computes). A
/// mixed pair throws either way. So one non-BigInt operand licenses the
/// rewrite, and a plain number literal on either side is enough — which
/// is the shape `Math.pow(x, 2)` already has.
fn is_definitely_not_bigint(expr : @ast.TsExpr) -> Bool {
  match expr {
    IntLit(_) | NumberLit(_) | StringLit(_) | TemplateLiteral(_, _) => true
    BoolLit(_) => true
    NullLit => true
    ArrayLit(_) | ObjectLit(_) => true
    // `-x` / `+x` / `~x` / `!x`: the first three already ToNumber their
    // operand, so a BigInt has thrown before this expression's value
    // exists; `!x` is a boolean.
    UnaryOp(Neg, _)
    | UnaryOp(Plus, _)
    | UnaryOp(BitwiseNot, _)
    | UnaryOp(Not, _) => true
    TypeArgs(_, inner) | As(inner, _) | Satisfies(inner, _) | NonNull(inner) =>
      is_definitely_not_bigint(inner)
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

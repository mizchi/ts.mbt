// ---------------------------------------------------------------
// Where an impure initializer may be moved to
// ---------------------------------------------------------------
//
// The single-use inliner deletes `let s = <rhs>;` and substitutes
// `<rhs>` at the one place `s` is read. When `<rhs>` is a value that
// costs nothing to evaluate, that is always safe. When it is a CALL, it
// is only safe if the use site is evaluated exactly once, unconditionally,
// and before anything else with an effect.
//
// It found the TypeScript compiler's binder:
//
//   let symbol = declareSymbolAndAddToSymbolTable(node, 512, 110735);
//   file.patternAmbientModules = append(
//     file.patternAmbientModules,
//     pattern && !isString(pattern) ? { pattern, symbol } : undefined);
//
// The use is inside the `?` branch. `declare module "buffer"` has no `*`
// in its name, so `isString(pattern)` is true, the branch is not taken —
// and the call that DECLARES THE MODULE'S SYMBOL never runs. Every
// `type` alias inside that module then hit
// `container.symbol.exports` with `container.symbol` undefined, and the
// minified compiler died binding `@types/node`.
//
// Nothing smaller catches this. The corpus and the fuzzer generate
// programs where an unexecuted call is invisible: it has to be a call
// whose only job is a side effect on a value read much later, guarded by
// a condition that happens to be false. That is ordinary code, and only
// real code has enough of it.
//
// Two ways the move goes wrong, so two things to check:
//
//   * CONDITIONAL — the use sits in a `?:` branch, behind `&&` / `||` /
//     `??`, or in a loop or `if` body. The call would run fewer times,
//     or more.
//   * REORDERED — something else with an effect is evaluated before the
//     use within that statement. `f(g(), s)` becomes `f(g(), h())` where
//     the original ran `h()` before `g()`.
//
// The walk below answers both in one pass over the next statement, in
// evaluation order, marking a node's own effect AFTER its children (a
// call's arguments are evaluated before the call happens, so a use
// inside the arguments is still "before" it).

///|
/// May this expression simply not be evaluated, with nothing observable
/// lost? Deliberately stricter than `is_pure_value`, which counts
/// `a.b` as pure — a property read can run a getter or throw, and
/// skipping it is observable.
fn is_safe_to_defer(expr : @ast.TsExpr) -> Bool {
  match expr {
    NumberLit(_)
    | IntLit(_)
    | BigIntLit(_)
    | BoolLit(_)
    | StringLit(_)
    | NullLit
    | ArrayHole
    | Var(_)
    | ImportMeta
    | FuncExpr(_)
    | ArrowFunc(_, _, _, _) => true
    // `/* @__PURE__ */ f(...)`: the annotation is the caller asserting
    // exactly this.
    PureCall(_) => true
    BinOp(_, a, b) => is_safe_to_defer(a) && is_safe_to_defer(b)
    UnaryOp(op, inner) =>
      match op {
        PreInc | PreDec | PostInc | PostDec | Delete => false
        _ => is_safe_to_defer(inner)
      }
    Cond(c, t, e) =>
      is_safe_to_defer(c) && is_safe_to_defer(t) && is_safe_to_defer(e)
    Seq(a, b) => is_safe_to_defer(a) && is_safe_to_defer(b)
    ArrayLit(items) => {
      for it in items {
        if !is_safe_to_defer(it) {
          return false
        }
      }
      true
    }
    ObjectLit(entries) => {
      for ent in entries {
        // A spread copies through getters, a computed key runs
        // ToPropertyKey — neither is free.
        if ent.0.has_prefix("@@spread:") || ent.0.has_prefix("@@computed:") {
          return false
        }
        if !is_safe_to_defer(ent.1) {
          return false
        }
      }
      true
    }
    As(inner, _) | Satisfies(inner, _) => is_safe_to_defer(inner)
    _ => false
  }
}

///|
/// State for the evaluation-order walk. `done` means the single use was
/// reached in a position the initializer may be moved to; `refused`
/// means it was not.
priv struct DeferSeek {
  name : String
  mut effect_seen : Bool
  mut done : Bool
  mut refused : Bool
}

///|
/// Is the single use of `name` in `stmt` reached unconditionally, once,
/// and before any other effect?
fn use_accepts_impure_init(stmt : @ast.TsStmt, name : String) -> Bool {
  let s = DeferSeek::{ name, effect_seen: false, done: false, refused: false }
  defer_seek_stmt(s, stmt)
  s.done && !s.refused
}

///|
fn defer_seek_stmt(s : DeferSeek, stmt : @ast.TsStmt) -> Unit {
  match stmt {
    Expr(e) | Throw(e) | Return(Some(e)) => defer_seek(s, e, false)
    Assign(_, e) | CompoundAssign(_, _, e) => defer_seek(s, e, false)
    Var(b, _, e) | Let(b, _, e) | Const(b, _, e) => {
      defer_seek(s, e, false)
      // A destructuring default only runs when the property is absent.
      for sub in binding_subexprs(b) {
        defer_seek(s, sub, true)
      }
    }
    PropAssign(a, _, b) => {
      defer_seek(s, a, false)
      defer_seek(s, b, false)
    }
    IndexAssign(a, b, c) => {
      defer_seek(s, a, false)
      defer_seek(s, b, false)
      defer_seek(s, c, false)
    }
    // The condition runs once; a use in either branch does not.
    If(c, _, _) => defer_seek(s, c, false)
    Switch(scrut, _) => defer_seek(s, scrut, false)
    // The iterable is evaluated once, the body repeatedly.
    ForOf(_, _, _, iter, _)
    | ForAwaitOf(_, _, _, iter, _)
    | ForIn(_, _, _, iter, _) => defer_seek(s, iter, false)
    // Only the init runs exactly once; the condition and update repeat.
    For(init, _, _, _) =>
      match init {
        Some(inner) => defer_seek_stmt(s, inner)
        None => s.refused = true
      }
    // A `while` condition is re-evaluated, which would run the
    // initializer more than once.
    Return(None) | Break(_) | Continue(_) | Empty | Debugger => ()
    _ => s.refused = true
  }
}

///|
fn defer_seek(s : DeferSeek, e : @ast.TsExpr, guarded : Bool) -> Unit {
  // Once the use is placed, nothing after it can invalidate the move.
  if s.done || s.refused {
    return
  }
  match e {
    Var(n) =>
      if n == s.name {
        if guarded || s.effect_seen {
          s.refused = true
        } else {
          s.done = true
        }
      }
    NumberLit(_)
    | IntLit(_)
    | BigIntLit(_)
    | BoolLit(_)
    | StringLit(_)
    | NullLit
    | ArrayHole
    | ImportMeta => ()
    // Not entered: `try_inline` has already refused any use captured by
    // a nested function.
    FuncExpr(_) | ArrowFunc(_, _, _, _) | NativeClassExpr(_, _) => ()
    BinOp(op, l, r) => {
      defer_seek(s, l, guarded)
      // The right side of a short-circuit only runs sometimes.
      let right_guarded = match op {
        And | Or | Coalesce => true
        _ => guarded
      }
      defer_seek(s, r, right_guarded)
    }
    UnaryOp(op, inner) => {
      defer_seek(s, inner, guarded)
      match op {
        PreInc | PreDec | PostInc | PostDec | Delete => defer_mark_effect(s)
        _ => ()
      }
    }
    Cond(c, t, f) => {
      defer_seek(s, c, guarded)
      defer_seek(s, t, true)
      defer_seek(s, f, true)
    }
    Seq(a, b) => {
      defer_seek(s, a, guarded)
      defer_seek(s, b, guarded)
    }
    // A property read can run a getter and can throw.
    PropAccess(recv, _) => {
      defer_seek(s, recv, guarded)
      defer_mark_effect(s)
    }
    IndexAccess(a, b) => {
      defer_seek(s, a, guarded)
      defer_seek(s, b, guarded)
      defer_mark_effect(s)
    }
    // Everything after an optional link is conditional on it.
    OptionalChain(inner) => {
      defer_seek(s, inner, true)
      defer_mark_effect(s)
    }
    Call(_, args) | New(_, args) => {
      defer_seek_args(s, args, guarded)
      defer_mark_effect(s)
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      defer_seek(s, callee, guarded)
      defer_seek_args(s, args, guarded)
      defer_mark_effect(s)
    }
    MethodCall(recv, _, args) => {
      defer_seek(s, recv, guarded)
      defer_seek_args(s, args, guarded)
      defer_mark_effect(s)
    }
    TaggedTemplate(tag, _, _, exprs) => {
      defer_seek(s, tag, guarded)
      defer_seek_args(s, exprs, guarded)
      defer_mark_effect(s)
    }
    DynamicImport(spec, opts) => {
      defer_seek(s, spec, guarded)
      match opts {
        Some(o) => defer_seek(s, o, guarded)
        None => ()
      }
      defer_mark_effect(s)
    }
    ArrayLit(items) => defer_seek_args(s, items, guarded)
    ObjectLit(entries) =>
      for ent in entries {
        defer_seek(s, ent.1, guarded)
        // A spread reads through getters; a computed key runs
        // ToPropertyKey.
        if ent.0.has_prefix("@@spread:") || ent.0.has_prefix("@@computed:") {
          defer_mark_effect(s)
        }
      }
    ComputedProp(k, v) => {
      defer_seek(s, k, guarded)
      defer_seek(s, v, guarded)
      defer_mark_effect(s)
    }
    Spread(inner) => {
      defer_seek(s, inner, guarded)
      defer_mark_effect(s)
    }
    // String conversion of an interpolated value can run `toString`.
    TemplateLiteral(_, exprs) => {
      defer_seek_args(s, exprs, guarded)
      defer_mark_effect(s)
    }
    As(inner, _) | Satisfies(inner, _) | NonNull(inner) | TypeArgs(_, inner) =>
      defer_seek(s, inner, guarded)
    PureCall(inner) => defer_seek(s, inner, guarded)
    Await(inner) | Yield(Some(inner)) | YieldStar(inner) => {
      defer_seek(s, inner, guarded)
      defer_mark_effect(s)
    }
    Yield(None) => defer_mark_effect(s)
    AssignExpr(_, v) | AssignPattern(_, v) => {
      defer_seek(s, v, guarded)
      defer_mark_effect(s)
    }
    CompoundAssignExpr(a, _, b) | PropAssignExpr(a, _, b) => {
      defer_seek(s, a, guarded)
      defer_seek(s, b, guarded)
      defer_mark_effect(s)
    }
    IndexAssignExpr(a, b, c) => {
      defer_seek(s, a, guarded)
      defer_seek(s, b, guarded)
      defer_seek(s, c, guarded)
      defer_mark_effect(s)
    }
    // An unrecognised construct is not a place to move a call to.
    _ => s.refused = true
  }
}

///|
fn defer_seek_args(
  s : DeferSeek,
  args : Array[@ast.TsExpr],
  guarded : Bool,
) -> Unit {
  for a in args {
    defer_seek(s, a, guarded)
  }
}

///|
/// This node has an effect of its own, and it happens after its
/// children. Only matters while the use has not been reached: an effect
/// BEFORE the use means substituting would reorder the two.
fn defer_mark_effect(s : DeferSeek) -> Unit {
  if !s.done && !s.refused {
    s.effect_seen = true
  }
}

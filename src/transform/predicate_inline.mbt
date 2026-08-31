// Type-predicate function inlining.
//
// User-defined type guards like `function isFoo(x): x is Foo { … }`
// almost always have a trivial body (`return cond;`). At every
// call site `isFoo(value)`, the body's `cond` — with the
// parameter substituted by the actual argument — is equivalent
// to the call.
//
// "Inlining trades a function call for a few extra bytes of the
// substituted expression … and the unused-after-inline predicate
// declaration falls out via treeshake" is what this comment used to
// say, and both halves hold only when the predicate has ONE caller.
// With several, every call site pays a copy of the body and the
// declaration stays for the callers that were not inlined. On typebox
// that cost 5.9 KB, which was the entirety of its -2.98% against the
// types-erased leg. Worse, the substitution copies the ARGUMENT once
// per reference to the parameter, so `isOne(bump())` against a
// three-term guard called `bump()` three times.
//
// So the decision is now per call site and asks both questions —
// `should_inline_predicate`, `arg_is_duplicable`,
// `PREDICATE_INLINE_MAX_COST`.
//
// Constraints (conservative for now):
//   - The function has exactly one parameter (most type guards
//     do; multi-arg cases are rare and harder to substitute
//     safely without alpha-renaming).
//   - The return type is `TypePredicate(_, _)` (i.e. the
//     `x is T` form). Functions that happen to return bool but
//     aren't tagged as type guards are NOT inlined — those
//     might have side effects, and the user didn't claim
//     purity.
//   - The body is exactly `{ return <expr>; }`. Multi-statement
//     bodies bail out: even if pure, mangling at inlining
//     time is risky.

///|
/// Pre-built predicate-inlining table. Keys are the function
/// names; values carry the single parameter name + the body
/// expression to substitute.
pub(all) struct PredicateTable {
  entries : Map[String, PredicateEntry]
}

///|
/// Scope narrowing, without which the table means the wrong thing the
/// moment the walk enters a scope that re-binds one of its names.
///
///     function isNeg(v: number): v is number { return !v; }
///     function q(v: number) {
///       function isNeg(x: number) { return x === 7; }
///       return isNeg(v);
///     }
///
/// `q(7)` compiled to `!v` — the OUTER body, substituted over a call
/// that resolves to the local. A wrong value, not a crash. Same for a
/// parameter named `isNeg`, which no block declares and so no
/// block-level check can see.
///
/// The helpers are shared with every other name-keyed table; the
/// reasoning is at the top of `call_inline.mbt`.
fn PredicateTable::narrow(
  self : PredicateTable,
  names : Array[String],
) -> PredicateTable {
  { entries: narrow_trivial_fns(self.entries, names) }
}

///|
fn PredicateTable::narrow_block(
  self : PredicateTable,
  block : @ast.TsBlock,
) -> PredicateTable {
  let names : Array[String] = []
  collect_block_bound_names(block, names)
  self.narrow(names)
}

///|
fn PredicateTable::narrow_params(
  self : PredicateTable,
  params : Array[@ast.TsParam],
) -> PredicateTable {
  let names : Array[String] = []
  collect_param_bound_names(params, names)
  self.narrow(names)
}

///|
fn PredicateTable::narrow_named_params(
  self : PredicateTable,
  params : Array[(String, @ast.TsType)],
) -> PredicateTable {
  let names : Array[String] = []
  for pr in params {
    if pr.0 != "" {
      names.push(pr.0)
    }
  }
  self.narrow(names)
}

///|
fn PredicateTable::narrow_binding(
  self : PredicateTable,
  b : @ast.TsBinding,
) -> PredicateTable {
  let names : Array[String] = []
  collect_binding_bound_names(b, names)
  self.narrow(names)
}

///|
pub(all) struct PredicateEntry {
  param_name : String
  body_expr : @ast.TsExpr
  // How many times the body reads the parameter. The substitution
  // copies the ARGUMENT once per reference, so this is both a
  // correctness input and a size input.
  param_refs : Int
  // Node count of the body, as a stand-in for the bytes a copy costs.
  body_cost : Int
  // Calls to this predicate in the whole block. One call means the
  // declaration dies after inlining and the trade is unconditionally
  // good; several mean every copy is paid for again.
  call_sites : Int
  // Whether inlining every caller can actually delete the declaration.
  //
  // The first version of this asked only "does the entry export it?",
  // which is the wrong question in two directions and was wrong in
  // practice: typebox's guards are not in `export_roots` (they leave
  // through a synthesized namespace object, not a named export) so
  // every one of them looked removable, none of them was removed, and
  // the pass cost 362 bytes writing bodies twice.
  //
  // What actually has to hold is that a CALL is the only way the name
  // is mentioned. Anything else — a namespace object literal, a
  // re-export, a value passed by reference — keeps the declaration
  // alive no matter how many call sites the pass rewrites, so the
  // copies are pure cost.
  removable : Bool
}

///|
/// The names the inlined predicate body reads — the value half of the
/// scope narrowing described at the top of `call_inline.mbt`. The
/// parameter is substituted away, so naming it here only makes the pass
/// more conservative.
impl SubstitutedValue for PredicateEntry with fn free_names(self) {
  let out : Map[String, Bool] = {}
  collect_var_refs_expr(self.body_expr, out)
  out
}

///|
/// A body this big is not inlined into more than one call site.
///
/// typebox is what set this number. `IsExtendsTrueLike` reads
///
///   return IsExtendsUnion(value) || IsExtendsTrue(value);
///
/// and each of those guards is a five-term conjunction over
/// `Guard.IsObject` / `HasPropertyKey` / `IsEqual`. Inlining both put
/// 374 bytes where 46 had been, the two declarations stayed (other call
/// sites still need them), and across the bundle the pass added
/// **5.9 KB** — the whole of typebox's -2.98% against the types-erased
/// leg. The pass's own comment claimed it "trades a function call for a
/// few extra bytes … and the unused-after-inline predicate declaration
/// falls out via treeshake". Both halves of that are true only when the
/// predicate has ONE caller.
///
/// The number was 8 when that paragraph was written and is 2 now, and
/// moving it again was not what fixed the rest. `just
/// measure-type-aware --phases` prices the pass on its own, and at
/// budget 2 it was still -261 bytes on typebox — which was exactly
/// typebox's whole remaining LOSS against the types-erased leg. The
/// budget was not the reason: `removable` was lying (see the field's
/// comment), so bodies were being copied on the strength of a
/// declaration that was never going to be deleted. With that fixed
/// the budget only decides how large a body may be copied when the
/// declaration really does die.
const PREDICATE_INLINE_MAX_COST : Int = 2

///|
/// Is this argument safe to write more than once?
///
/// It has to be, when the body reads its parameter more than once,
/// because the substitution copies the argument into every one of those
/// positions. It did not check, and
///
///   function isOne(x: number): x is 1 { return x === 1 && x !== 2 && x > 0; }
///   isOne(bump())
///
/// became `bump() === 1 && bump() !== 2 && bump() > 0` — the argument
/// evaluated three times. `calls` came back 3 instead of 1. A call, an
/// assignment, `++`, an `await`: any of them changes what the program
/// does. Even a plain property read is not safe to duplicate, since a
/// getter runs on each read.
///
/// So the allowlist is what cannot observe anything twice: an
/// identifier, `this`, and literals.
fn arg_is_duplicable(arg : @ast.TsExpr) -> Bool {
  match arg {
    // `this` is `Var("this")` in this AST, so the identifier arm covers
    // it too.
    Var(_)
    | NumberLit(_)
    | IntLit(_)
    | BigIntLit(_)
    | BoolLit(_)
    | StringLit(_)
    | NullLit => true
    // The TypeScript-only wrappers are transparent: `x as Foo` reads
    // exactly what `x` reads.
    As(inner, _) | Satisfies(inner, _) | NonNull(inner) | TypeArgs(_, inner) =>
      arg_is_duplicable(inner)
    _ => false
  }
}

///|
/// `(node count, references to `param`)` for a predicate body, or `None`
/// when the body holds a shape this scan does not model.
///
/// `None` refuses the inline. Both numbers are load-bearing in the
/// unsafe direction — undercounting the references duplicates an
/// effectful argument, undercounting the cost inlines something large —
/// so an unrecognised node is not counted as a leaf, it stops the
/// decision.
fn predicate_body_facts(expr : @ast.TsExpr, param : String) -> (Int, Int)? {
  fn go(e : @ast.TsExpr) -> (Int, Int)? {
    match e {
      Var(n) => Some((1, if n == param { 1 } else { 0 }))
      NumberLit(_)
      | IntLit(_)
      | BigIntLit(_)
      | BoolLit(_)
      | StringLit(_)
      | NullLit
      | ArrayHole => Some((1, 0))
      PropAccess(recv, _) =>
        match go(recv) {
          Some((c, r)) => Some((c + 1, r))
          None => None
        }
      UnaryOp(_, inner)
      | Spread(inner)
      | As(inner, _)
      | Satisfies(inner, _)
      | NonNull(inner)
      | OptionalChain(inner)
      | TypeArgs(_, inner)
      | PureCall(inner) =>
        match go(inner) {
          Some((c, r)) => Some((c + 1, r))
          None => None
        }
      BinOp(_, l, r) | Seq(l, r) | IndexAccess(l, r) => join(go(l), go(r), 1)
      Cond(c, t, e2) => join(join(go(c), go(t), 0), go(e2), 1)
      Call(n, args) => {
        // The callee name is itself a reference when it happens to be
        // the parameter (`p(1)` where `p` is the param).
        let mut acc = Some((1, if n == param { 1 } else { 0 }))
        for a in args {
          acc = join(acc, go(a), 0)
        }
        acc
      }
      CallExpr(callee, args) | NewExpr(callee, args) => {
        let mut acc = go(callee)
        for a in args {
          acc = join(acc, go(a), 0)
        }
        match acc {
          Some((c, r)) => Some((c + 1, r))
          None => None
        }
      }
      New(n, args) => {
        let mut acc = Some((1, if n == param { 1 } else { 0 }))
        for a in args {
          acc = join(acc, go(a), 0)
        }
        acc
      }
      MethodCall(recv, _, args) => {
        let mut acc = go(recv)
        for a in args {
          acc = join(acc, go(a), 0)
        }
        match acc {
          Some((c, r)) => Some((c + 1, r))
          None => None
        }
      }
      ArrayLit(items) => {
        let mut acc = Some((1, 0))
        for it in items {
          acc = join(acc, go(it), 0)
        }
        acc
      }
      ObjectLit(entries) => {
        let mut acc = Some((1, 0))
        for ent in entries {
          acc = join(acc, go(ent.1), 0)
        }
        acc
      }
      TemplateLiteral(_, exprs) => {
        let mut acc = Some((1, 0))
        for x in exprs {
          acc = join(acc, go(x), 0)
        }
        acc
      }
      // A closure in the body captures the parameter rather than
      // reading it, and counting a capture as one read would let the
      // argument be duplicated into two closures. Not modelled.
      _ => None
    }
  }

  go(expr)
}

///|
/// Add two `(cost, refs)` results plus a cost for the node joining them.
/// `None` anywhere poisons the result, which is the point.
fn join(a : (Int, Int)?, b : (Int, Int)?, extra : Int) -> (Int, Int)? {
  match (a, b) {
    (Some((c1, r1)), Some((c2, r2))) => Some((c1 + c2 + extra, r1 + r2))
    _ => None
  }
}

///|
/// Mentions of each top-level name anywhere in the block, split into
/// the two categories the trade depends on: calls, which inlining
/// rewrites away, and everything else, which it cannot touch.
///
/// Counted on the pre-inline block, which is the right denominator:
/// what matters is how many copies the pass is about to make, and
/// whether anything is left holding the declaration alive afterwards.
fn count_predicate_calls(
  block : @ast.TsBlock,
  calls : Map[String, Int],
  other_refs : Map[String, Int],
) -> Unit {
  fn bump(m : Map[String, Int], n : String) -> Unit {
    m[n] = m.get(n).unwrap_or(0) + 1
  }

  // `surface_visit_exprs_block` already visits every expression in the
  // block, nested function bodies included, so this needs no traversal
  // of its own — the one thing a counter must not do is miss a call site
  // and conclude a predicate has fewer callers than it has.
  //
  // It also visits the CALLEE of a `CallExpr`, so a `CallExpr(Var(n))`
  // arrives twice: once as the call and once as a bare `Var(n)`. That
  // is why the non-call tally is `Var` sightings MINUS `CallExpr`
  // callees rather than a category of its own — miscounting that way
  // would make every called predicate look permanently referenced.
  let var_sightings : Map[String, Int] = {}
  let callee_vars : Map[String, Int] = {}
  surface_visit_exprs_block(block, e => {
    match e {
      Call(n, _) => bump(calls, n)
      CallExpr(@ast.TsExpr::Var(n), _) => {
        bump(calls, n)
        bump(callee_vars, n)
      }
      Var(n) => bump(var_sightings, n)
      _ => ()
    }
  })
  for name, seen in var_sightings {
    let as_callee = callee_vars.get(name).unwrap_or(0)
    if seen > as_callee {
      other_refs[name] = seen - as_callee
    }
  }
}

///|
/// Build the substitution table from a flat block of top-level
/// declarations. Only `Let / Const / Var(Ident(name), _,
/// FuncExpr({…}))` shapes with a `TypePredicate` return type and
/// a one-statement `Return(Some(_))` body qualify.
pub fn build_predicate_table(
  block : @ast.TsBlock,
  // The bundle's exported top-level names. A predicate the bundle
  // exports cannot be removed however few callers it has, so the
  // "one caller, the declaration dies" exemption below does not apply
  // to it.
  //
  // This is necessary but nowhere near sufficient, and believing it was
  // sufficient is what cost typebox 362 bytes: its guards do not appear
  // in `export_roots` at all — they leave through a namespace object the
  // linker synthesizes — so they read as removable and were copied. The
  // reference tally in `count_predicate_calls` is what actually decides
  // it; this list only covers the export SPECIFIERS, which are
  // statements rather than expressions and so are invisible to that
  // walk.
  exported? : Map[String, Bool] = {},
) -> PredicateTable {
  let entries : Map[String, PredicateEntry] = {}
  let calls : Map[String, Int] = {}
  let other_refs : Map[String, Int] = {}
  count_predicate_calls(block, calls, other_refs)
  for stmt in block.stmts {
    match stmt {
      Let(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f))
      | Const(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f))
      | Var(@ast.TsBinding::Ident(name), _, @ast.TsExpr::FuncExpr(f)) =>
        match try_extract_predicate(f) {
          Some((param_name, body_expr)) =>
            // A body the cost scan cannot model is not inlined at all;
            // see `predicate_body_facts`.
            match predicate_body_facts(body_expr, param_name) {
              Some((cost, refs)) =>
                entries[name] = {
                  param_name,
                  body_expr,
                  param_refs: refs,
                  body_cost: cost,
                  call_sites: calls.get(name).unwrap_or(0),
                  removable: not(exported.contains(name)) &&
                  other_refs.get(name).unwrap_or(0) == 0,
                }
              None => ()
            }
          None => ()
        }
      _ => ()
    }
  }
  { entries, }
}

///|
/// Should this particular call site be inlined?
///
/// Two independent questions, and the pass used to ask neither.
///
///  * Is it SAFE — the substitution copies the argument once per
///    reference to the parameter, so a body that reads its parameter
///    twice evaluates the argument twice.
///  * Is it WORTH IT — every call site pays a copy of the body, and the
///    declaration only disappears when the last caller is inlined.
fn should_inline_predicate(entry : PredicateEntry, arg : @ast.TsExpr) -> Bool {
  if entry.param_refs > 1 && not(arg_is_duplicable(arg)) {
    return false
  }
  // One caller AND removable: the body moves rather than multiplies,
  // and treeshake takes the declaration. Worth it whatever the size.
  if entry.call_sites <= 1 && entry.removable {
    return true
  }
  // Several callers: the body is COPIED into each one, and the only gain
  // is the declaration disappearing — so require that it actually can.
  // Without `removable` the pass pays N copies AND keeps the original,
  // which is a loss at every body size, not just a large one.
  entry.removable && entry.body_cost <= PREDICATE_INLINE_MAX_COST
}

///|
fn try_extract_predicate(f : @ast.TsFunc) -> (String, @ast.TsExpr)? {
  // Return type must be `TypePredicate(_, _)`.
  match f.return_type {
    TypePredicate(_, _) => ()
    _ => return None
  }
  if f.params.length() != 1 {
    return None
  }
  // Body must be a single `return EXPR;` stmt.
  if f.body.stmts.length() != 1 {
    return None
  }
  let return_expr = match f.body.stmts[0] {
    Return(Some(e)) => e
    _ => return None
  }
  let param = f.params[0]
  // The param is always a simple `name` for the type-guard
  // shape; destructuring as the lone param is rare and we
  // don't try to support it.
  let name = match param.binding {
    Some(@ast.TsBinding::Ident(n)) => n
    Some(_) => return None
    None => param.name
  }
  Some((name, return_expr))
}

///|
/// Walk `block`, substituting every call to a known predicate
/// with the inlined body expression (with the parameter
/// substituted by the actual argument).
pub fn inline_predicates(
  block : @ast.TsBlock,
  table : PredicateTable,
) -> @ast.TsBlock {
  if table.entries.is_empty() {
    return block
  }
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(inline_predicates_stmt(s, table))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn inline_predicates_stmt(
  stmt : @ast.TsStmt,
  table : PredicateTable,
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) => Var(b, t, inline_predicates_expr(e, table))
    Let(b, t, e) => Let(b, t, inline_predicates_expr(e, table))
    Const(b, t, e) => Const(b, t, inline_predicates_expr(e, table))
    Assign(n, e) => Assign(n, inline_predicates_expr(e, table))
    CompoundAssign(n, op, e) =>
      CompoundAssign(n, op, inline_predicates_expr(e, table))
    IndexAssign(t, idx, v) =>
      IndexAssign(
        inline_predicates_expr(t, table),
        inline_predicates_expr(idx, table),
        inline_predicates_expr(v, table),
      )
    PropAssign(t, prop, v) =>
      PropAssign(
        inline_predicates_expr(t, table),
        prop,
        inline_predicates_expr(v, table),
      )
    Expr(e) => Expr(inline_predicates_expr(e, table))
    Return(Some(e)) => Return(Some(inline_predicates_expr(e, table)))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => stmt
    Throw(e) => Throw(inline_predicates_expr(e, table))
    If(c, t, e) =>
      If(
        inline_predicates_expr(c, table),
        inline_predicates_block(t, table),
        match e {
          Some(b) => Some(inline_predicates_block(b, table))
          None => None
        },
      )
    While(c, body) =>
      While(
        inline_predicates_expr(c, table),
        inline_predicates_block(body, table),
      )
    DoWhile(c, body) =>
      DoWhile(
        inline_predicates_expr(c, table),
        inline_predicates_block(body, table),
      )
    With(c, body) =>
      With(
        inline_predicates_expr(c, table),
        inline_predicates_block(body, table),
      )
    For(init, cond, update, body) => {
      let inner = match init {
        Some(s) => {
          let names : Array[String] = []
          collect_stmt_bound_names(s, names)
          table.narrow(names)
        }
        None => table
      }
      For(
        match init {
          Some(s) => Some(inline_predicates_stmt(s, table))
          None => None
        },
        match cond {
          Some(e) => Some(inline_predicates_expr(e, inner))
          None => None
        },
        match update {
          Some(s) => Some(inline_predicates_stmt(s, inner))
          None => None
        },
        inline_predicates_block(body, inner),
      )
    }
    ForOf(k, b, t, iter, body) =>
      ForOf(
        k,
        b,
        t,
        inline_predicates_expr(iter, table),
        inline_predicates_block(body, table.narrow_binding(b)),
      )
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(
        k,
        b,
        t,
        inline_predicates_expr(iter, table),
        inline_predicates_block(body, table.narrow_binding(b)),
      )
    ForIn(k, b, t, iter, body) =>
      ForIn(
        k,
        b,
        t,
        inline_predicates_expr(iter, table),
        inline_predicates_block(body, table.narrow_binding(b)),
      )
    Switch(e, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(te) => Some(inline_predicates_expr(te, table))
            None => None
          },
          body: inline_predicates_block(c.body, table),
        })
      }
      Switch(inline_predicates_expr(e, table), new_cases)
    }
    Try(b, bnd, cb, fb) => {
      let catch_table = match bnd {
        Some(binding) => table.narrow_binding(binding)
        None => table
      }
      Try(
        inline_predicates_block(b, table),
        bnd,
        match cb {
          Some(blk) => Some(inline_predicates_block(blk, catch_table))
          None => None
        },
        match fb {
          Some(blk) => Some(inline_predicates_block(blk, table))
          None => None
        },
      )
    }
    Label(name, inner) => Label(name, inline_predicates_stmt(inner, table))
    Block(b) => Block(inline_predicates_block(b, table))
    NativeClassStmt(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) =>
          Some({
            ..f,
            body: inline_predicates_block(f.body, table.narrow_params(f.params)),
          })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let method_table = table.narrow_named_params(m.params)
        let new_body = match m.body {
          Some(b) => Some(inline_predicates_block(b, method_table))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, inline_predicates_expr(sf.1, table)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(inline_predicates_expr(b, table))
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
fn inline_predicates_block(
  block : @ast.TsBlock,
  table : PredicateTable,
) -> @ast.TsBlock {
  // Every nested block is a scope. The top-level entry point walks
  // statements directly, so the candidates' own declarations are not
  // narrowed away.
  let table = table.narrow_block(block)
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(inline_predicates_stmt(s, table))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn inline_predicates_expr(
  expr : @ast.TsExpr,
  table : PredicateTable,
) -> @ast.TsExpr {
  match expr {
    // The pattern we care about — `predicate(arg)` where
    // `predicate` is in the table.
    Call(name, args) =>
      match table.entries.get(name) {
        Some(entry) =>
          if args.length() == 1 && should_inline_predicate(entry, args[0]) {
            substitute_param_with_arg(
              entry.body_expr,
              entry.param_name,
              args[0],
            )
          } else {
            // Different arity than expected — fall back to the
            // original Call. (Type-guards always take one arg in
            // the shape we accept.)
            let new_args : Array[@ast.TsExpr] = []
            for a in args {
              new_args.push(inline_predicates_expr(a, table))
            }
            Call(name, new_args)
          }
        None => {
          let new_args : Array[@ast.TsExpr] = []
          for a in args {
            new_args.push(inline_predicates_expr(a, table))
          }
          Call(name, new_args)
        }
      }
    CallExpr(callee, args) => {
      // `CallExpr(Var(name), [arg])` — try the predicate rewrite
      // the same as the `Call(name, [arg])` form above.
      match callee {
        @ast.TsExpr::Var(name) =>
          match table.entries.get(name) {
            Some(entry) =>
              if args.length() == 1 && should_inline_predicate(entry, args[0]) {
                return substitute_param_with_arg(
                  entry.body_expr,
                  entry.param_name,
                  args[0],
                )
              }
            None => ()
          }
        _ => ()
      }
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_predicates_expr(a, table))
      }
      CallExpr(inline_predicates_expr(callee, table), new_args)
    }
    New(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_predicates_expr(a, table))
      }
      New(n, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_predicates_expr(a, table))
      }
      NewExpr(inline_predicates_expr(callee, table), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_predicates_expr(a, table))
      }
      MethodCall(inline_predicates_expr(recv, table), m, new_args)
    }
    BinOp(op, l, r) =>
      BinOp(
        op,
        inline_predicates_expr(l, table),
        inline_predicates_expr(r, table),
      )
    UnaryOp(op, inner) => UnaryOp(op, inline_predicates_expr(inner, table))
    Cond(c, t, e) =>
      Cond(
        inline_predicates_expr(c, table),
        inline_predicates_expr(t, table),
        inline_predicates_expr(e, table),
      )
    PropAccess(recv, p) => PropAccess(inline_predicates_expr(recv, table), p)
    IndexAccess(recv, idx) =>
      IndexAccess(
        inline_predicates_expr(recv, table),
        inline_predicates_expr(idx, table),
      )
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(inline_predicates_expr(i, table))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, inline_predicates_expr(ent.1, table)))
      }
      ObjectLit(new_entries)
    }
    Spread(inner) => Spread(inline_predicates_expr(inner, table))
    Yield(Some(inner)) => Yield(Some(inline_predicates_expr(inner, table)))
    YieldStar(inner) => YieldStar(inline_predicates_expr(inner, table))
    Await(inner) => Await(inline_predicates_expr(inner, table))
    Seq(a, b) =>
      Seq(inline_predicates_expr(a, table), inline_predicates_expr(b, table))
    AssignExpr(n, v) => AssignExpr(n, inline_predicates_expr(v, table))
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(
        inline_predicates_expr(t, table),
        op,
        inline_predicates_expr(v, table),
      )
    AssignPattern(b, v) => AssignPattern(b, inline_predicates_expr(v, table))
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(
        inline_predicates_expr(recv, table),
        p,
        inline_predicates_expr(v, table),
      )
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        inline_predicates_expr(recv, table),
        inline_predicates_expr(idx, table),
        inline_predicates_expr(v, table),
      )
    ComputedProp(k, v) =>
      ComputedProp(
        inline_predicates_expr(k, table),
        inline_predicates_expr(v, table),
      )
    ArrowFunc(params, ret, body, is_async) => {
      // A parameter shadowing a predicate is the case no block-level
      // check can see: `function f(isNeg) { return isNeg(v) }`.
      let table = table.narrow_params(params)
      let new_body = match body {
        ArrowExpr(e) =>
          @ast.TsArrowBody::ArrowExpr(inline_predicates_expr(e, table))
        ArrowBlock(b) =>
          @ast.TsArrowBody::ArrowBlock(inline_predicates_block(b, table))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => {
      let table = table.narrow_params(f.params)
      // A named function expression binds its own name in the body.
      let table = if f.name == "" { table } else { table.narrow([f.name]) }
      let new_body = inline_predicates_block(f.body, table)
      FuncExpr({ ..f, body: new_body })
    }
    DynamicImport(spec, opts) => {
      let opts_f = match opts {
        Some(o) => Some(inline_predicates_expr(o, table))
        None => None
      }
      DynamicImport(inline_predicates_expr(spec, table), opts_f)
    }
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(inline_predicates_expr(e, table))
      }
      TaggedTemplate(inline_predicates_expr(tag, table), raw, cooked, new_exprs)
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(inline_predicates_expr(e, table))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(inline_predicates_expr(inner, table), ty)
    Satisfies(inner, ty) => Satisfies(inline_predicates_expr(inner, table), ty)
    NonNull(inner) => NonNull(inline_predicates_expr(inner, table))
    TypeArgs(tys, inner) => TypeArgs(tys, inline_predicates_expr(inner, table))
    OptionalChain(inner) => OptionalChain(inline_predicates_expr(inner, table))
    PureCall(inner) => PureCall(inline_predicates_expr(inner, table))
    NativeClassExpr(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: inline_predicates_block(f.body, table) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(inline_predicates_block(b, table))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, inline_predicates_expr(sf.1, table)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(inline_predicates_expr(b, table))
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
/// Substitute every `Var(param_name)` reference inside `expr`
/// with `arg`. Inner function bodies create a new scope that
/// might shadow the parameter, but for the simple type-guard
/// shape we support (`return <cond>;`) closures inside the
/// expression are vanishingly rare; if seen, we still
/// substitute — at worst the inner closure was capturing the
/// outer param.
fn substitute_param_with_arg(
  expr : @ast.TsExpr,
  param_name : String,
  arg : @ast.TsExpr,
) -> @ast.TsExpr {
  match expr {
    Var(n) => if n == param_name { arg } else { expr }
    BinOp(op, l, r) =>
      BinOp(
        op,
        substitute_param_with_arg(l, param_name, arg),
        substitute_param_with_arg(r, param_name, arg),
      )
    UnaryOp(op, inner) =>
      UnaryOp(op, substitute_param_with_arg(inner, param_name, arg))
    Cond(c, t, e) =>
      Cond(
        substitute_param_with_arg(c, param_name, arg),
        substitute_param_with_arg(t, param_name, arg),
        substitute_param_with_arg(e, param_name, arg),
      )
    Call(n, args) =>
      if n == param_name {
        // Parameter being called — substitute through CallExpr.
        let new_args : Array[@ast.TsExpr] = []
        for a in args {
          new_args.push(substitute_param_with_arg(a, param_name, arg))
        }
        CallExpr(arg, new_args)
      } else {
        let new_args : Array[@ast.TsExpr] = []
        for a in args {
          new_args.push(substitute_param_with_arg(a, param_name, arg))
        }
        Call(n, new_args)
      }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_param_with_arg(a, param_name, arg))
      }
      CallExpr(substitute_param_with_arg(callee, param_name, arg), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_param_with_arg(a, param_name, arg))
      }
      MethodCall(substitute_param_with_arg(recv, param_name, arg), m, new_args)
    }
    New(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_param_with_arg(a, param_name, arg))
      }
      New(n, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_param_with_arg(a, param_name, arg))
      }
      NewExpr(substitute_param_with_arg(callee, param_name, arg), new_args)
    }
    PropAccess(recv, p) =>
      PropAccess(substitute_param_with_arg(recv, param_name, arg), p)
    IndexAccess(recv, idx) =>
      IndexAccess(
        substitute_param_with_arg(recv, param_name, arg),
        substitute_param_with_arg(idx, param_name, arg),
      )
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(substitute_param_with_arg(i, param_name, arg))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push(
          (ent.0, substitute_param_with_arg(ent.1, param_name, arg)),
        )
      }
      ObjectLit(new_entries)
    }
    Spread(inner) => Spread(substitute_param_with_arg(inner, param_name, arg))
    Await(inner) => Await(substitute_param_with_arg(inner, param_name, arg))
    NonNull(inner) => NonNull(substitute_param_with_arg(inner, param_name, arg))
    TypeArgs(tys, inner) =>
      TypeArgs(tys, substitute_param_with_arg(inner, param_name, arg))
    OptionalChain(inner) =>
      OptionalChain(substitute_param_with_arg(inner, param_name, arg))
    As(inner, ty) => As(substitute_param_with_arg(inner, param_name, arg), ty)
    Satisfies(inner, ty) =>
      Satisfies(substitute_param_with_arg(inner, param_name, arg), ty)
    _ => expr
  }
}

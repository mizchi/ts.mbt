// Phase 2 of the observability analysis: infer which bindings hold
// a numeric value.
//
// Motivation:
//   `parts[i]`, `expandedStates[i]`, `arr[offset + 0]` — the index
//   is provably a number-typed JS value, so the dynamic-access
//   wildcard fallback in `mangle_safety.collect_externally_visible_props`
//   shouldn't fire (we're reading an integer-keyed slot, not a
//   named property).
//
//   The previous static check only matched the literal expression
//   shapes (`NumberLit`, `i + 1`, `arr.length - 1`, `i++`). The
//   common case `let i = 0; …; arr[i]` slips past it because `i`
//   is a `Var(...)` at the access site.
//
// Approach:
//   Use the `SymbolGraph` to propagate a "definitely numeric"
//   flag. A symbol is numeric when it carries a `number` / `int`
//   annotation, or when EVERY def (initializer + reassignment)
//   writes a value that is itself numeric AND the binding isn't
//   captured by a closure (an unannotated binding a closure holds
//   could be mutated from another frame in ways we don't track).
//   An annotation outranks the closure guard: a write that violates
//   it isn't a write TypeScript admits, and it is the only proof
//   available for a parameter, which has no def to walk.
//
//   The lattice is two-valued (`Numeric` / `Maybe`) and the
//   propagation walks until fixed point. In practice 1-2 rounds
//   suffice on real bundles because numeric flows are short.
//
//   We intentionally start `Maybe` (= safe), and only PROMOTE to
//   `Numeric` when proof is in hand. False negatives (missed
//   numeric var) just keep the existing conservative behaviour;
//   false positives (claiming a string var is numeric) would
//   break property-mangle correctness.

///|
/// Run the numeric-variable inference and return the set of
/// symbol ids that are provably numeric.
pub fn infer_numeric_symbols(g : SymbolGraph) -> Map[SymbolId, Bool] {
  let numeric : Map[SymbolId, Bool] = {}
  let mut changed = true
  let mut rounds = 0
  // Bound iterations defensively. Each round can only ADD entries
  // (monotone), so the loop is guaranteed to converge in <= |symbols|
  // rounds; a 16-iteration cap covers anything realistic.
  while changed && rounds < 16 {
    changed = false
    rounds = rounds + 1
    // One O(|symbols|) projection per ROUND, rather than one scan of
    // every symbol per `Var(n)` lookup. The scan-per-lookup form was
    // quadratic: on 9 MB of `typescript.js` this fixed point and its
    // container twin were 5.5 s of a 10.9 s compile.
    let name_numeric = numeric_name_set(g, numeric)
    for sym in g.symbols {
      if numeric.contains(sym.id) {
        continue
      }
      // A `number` / `int` annotation is proof on its own, and it is
      // the only proof available for a parameter — a parameter has no
      // def to walk, so `dispatch(i: number)` used as `middleware[i]`
      // would otherwise never be recognized. Every write to the
      // binding has to satisfy the annotation, so the reassignment
      // walk below has nothing to add.
      match sym.ts_type {
        Number | Int => {
          numeric[sym.id] = true
          changed = true
          continue
        }
        _ => ()
      }
      // Closure capture: a nested function could write any value
      // into this binding, and without an annotation there is
      // nothing constraining what. Conservative -> stay Maybe.
      if sym.captured_by_closure {
        continue
      }
      // No def at all (param without a numeric annotation or an
      // observed init, ambient import, etc.) -> can't prove anything.
      if sym.defs.length() == 0 {
        continue
      }
      let mut all_numeric = true
      for d in sym.defs {
        match d.init {
          Some(e) =>
            if !is_expr_numeric_names(e, name_numeric) {
              all_numeric = false
              break
            }
          None => {
            all_numeric = false
            break
          }
        }
      }
      // Reassignments: each `x = rhs` / `x += rhs` records its
      // rhs verbatim on the symbol. Walk those expressions through
      // the same `is_expr_numeric` predicate; one non-numeric rhs
      // is enough to demote the binding.
      //
      // Handle the self-reference case `i = i + 1` with a tentative
      // promotion: temporarily add `sym` to `numeric` while we check
      // its own rhs, then revert if any rhs disproves the assumption.
      // This converges in one round instead of relying on the outer
      // fixed-point loop to catch `i` referencing itself.
      if all_numeric && sym.reassigned {
        let tentative_added = !numeric.contains(sym.id)
        if tentative_added {
          numeric[sym.id] = true
          // `i = i + 1` has to see its own speculative promotion, and
          // the round's projection was taken before it.
          if name_all_numeric(g, sym.name, numeric) {
            name_numeric[sym.name] = true
          }
        }
        let mut all_rhs_numeric = true
        for rhs in sym.reassign_rhs {
          if !is_expr_numeric_names(rhs, name_numeric) {
            all_rhs_numeric = false
            break
          }
        }
        if !all_rhs_numeric {
          if tentative_added {
            // Drop the speculative entry so we don't poison
            // other symbols' analyses later in the round.
            let _ = numeric.remove(sym.id)
            let _ = name_numeric.remove(sym.name)
          }
          all_numeric = false
        }
      }
      if all_numeric {
        numeric[sym.id] = true
        changed = true
      }
    }
  }
  numeric
}

///|
/// True when `name` is declared somewhere and every binding carrying it
/// is numeric. Only the fixed point's speculative self-promotion needs
/// this one-off scan; ordinary lookups read the per-round projection.
fn name_all_numeric(
  g : SymbolGraph,
  name : String,
  numeric : Map[SymbolId, Bool],
) -> Bool {
  let mut seen = false
  for s in g.symbols {
    if s.name == name {
      if !numeric.contains(s.id) {
        return false
      }
      seen = true
    }
  }
  seen
}

///|
/// Same predicate as `is_expr_numeric` but exported for the
/// property-escape analysis. The dynamic-access wildcard fallback
/// consults this to decide whether `obj[idx]` is reading a named
/// property (string-keyed) or an integer-keyed slot.
pub fn is_index_numeric_with_graph(
  idx : @ast.TsExpr,
  g : SymbolGraph,
  numeric : Map[SymbolId, Bool],
) -> Bool {
  is_expr_numeric_names(idx, numeric_name_set(g, numeric))
}

///|
/// Project the symbol-id-keyed numeric map down to a name-keyed
/// set. A name qualifies when EVERY binding carrying it is numeric:
/// the caller has no scope info at the access site, so it cannot
/// tell which binding `arr[i]` means — but if they are all numeric
/// it does not need to. (Requiring the name to be unique instead
/// gave up on `i`, which is declared in a dozen functions of any
/// real bundle and numeric in all of them.)
///
/// `mangle_safety.collect_props_on_external_*` consumes this so
/// the IndexAccess wildcard fallback can ask "is `idx` a numeric
/// variable?" without threading the whole graph through every
/// helper.
pub fn numeric_name_set(
  g : SymbolGraph,
  numeric : Map[SymbolId, Bool],
) -> Map[String, Bool] {
  let non_numeric : Map[String, Bool] = {}
  for s in g.symbols {
    if !numeric.contains(s.id) {
      non_numeric[s.name] = true
    }
  }
  let out : Map[String, Bool] = {}
  for s in g.symbols {
    if numeric.contains(s.id) && !non_numeric.contains(s.name) {
      out[s.name] = true
    }
  }
  out
}

///|
/// Cheap, name-set-only version of `is_expr_numeric` for callers
/// that don't want to carry the full graph. Same recursive rules,
/// `Var(n)` is numeric iff `n` is in the supplied set.
pub fn is_index_numeric_with_names(
  idx : @ast.TsExpr,
  numeric_names : Map[String, Bool],
) -> Bool {
  is_expr_numeric_names(idx, numeric_names)
}

///|
fn is_expr_numeric_names(
  expr : @ast.TsExpr,
  numeric_names : Map[String, Bool],
) -> Bool {
  match expr {
    NumberLit(_) | IntLit(_) | BigIntLit(_) => true
    PropAccess(_, "length") => true
    UnaryOp(op, inner) =>
      match op {
        Neg | Plus | BitwiseNot => is_expr_numeric_names(inner, numeric_names)
        PreInc | PreDec | PostInc | PostDec => true
        _ => false
      }
    BinOp(op, l, r) =>
      match op {
        Sub | Mul | Div | Mod | Pow => true
        BitAnd | BitOr | BitXor | Shl | Shr | UShr => true
        Add =>
          is_expr_numeric_names(l, numeric_names) &&
          is_expr_numeric_names(r, numeric_names)
        _ => false
      }
    Cond(_, t, e) =>
      is_expr_numeric_names(t, numeric_names) &&
      is_expr_numeric_names(e, numeric_names)
    AssignExpr(_, rhs) => is_expr_numeric_names(rhs, numeric_names)
    CompoundAssignExpr(_, _, _) => true
    Seq(_, b) => is_expr_numeric_names(b, numeric_names)
    @ast.TsExpr::Var(n) => numeric_names.contains(n)
    _ => false
  }
}

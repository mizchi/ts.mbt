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
//   flag. A symbol is numeric when EVERY def (initializer +
//   reassignment) writes a value that is itself numeric, AND the
//   binding isn't captured by a closure (a closure could mutate
//   it from another frame in ways we don't track here).
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
    for sym in g.symbols {
      if numeric.contains(sym.id) {
        continue
      }
      // Closure capture: a nested function could write any value
      // into this binding. Conservative -> stay Maybe.
      if sym.captured_by_closure {
        continue
      }
      // No def at all (param without observed init, ambient
      // import, etc.) -> can't prove anything.
      if sym.defs.length() == 0 {
        continue
      }
      let mut all_numeric = true
      for d in sym.defs {
        match d.init {
          Some(e) =>
            if !(is_expr_numeric(e, g, numeric)) {
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
        let tentative_added = !(numeric.contains(sym.id))
        if tentative_added {
          numeric[sym.id] = true
        }
        let mut all_rhs_numeric = true
        for rhs in sym.reassign_rhs {
          if !(is_expr_numeric(rhs, g, numeric)) {
            all_rhs_numeric = false
            break
          }
        }
        if !(all_rhs_numeric) {
          if tentative_added {
            // Drop the speculative entry so we don't poison
            // other symbols' analyses later in the round.
            let _ = numeric.remove(sym.id)
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
/// Is an expression provably a JS number? Mirrors the AST shapes
/// the JS spec lists as number-typed:
///   - numeric literals (`Int` / `Number` / `BigInt` only via
///     conversion are out of scope; tagged separately if needed)
///   - `+`/`-`/`~` unary on numeric, `++`/`--`
///   - `-`, `*`, `/`, `%`, `**`, bitwise binary
///   - `a + b` only when BOTH operands are numeric (string `+` is
///     overloaded — drop to conservative when either side could be
///     a string)
///   - `arr.length` (Array spec)
///   - `cond ? a : b` when both branches are numeric
///   - `Var(n)` resolved against the graph + a known-numeric map
fn is_expr_numeric(
  expr : @ast.TsExpr,
  g : SymbolGraph,
  numeric : Map[SymbolId, Bool],
) -> Bool {
  match expr {
    NumberLit(_) | IntLit(_) | BigIntLit(_) => true
    PropAccess(_, "length") => true
    UnaryOp(op, inner) =>
      match op {
        Neg | Plus | BitwiseNot => is_expr_numeric(inner, g, numeric)
        PreInc | PreDec | PostInc | PostDec => true
        _ => false
      }
    BinOp(op, l, r) =>
      match op {
        Sub | Mul | Div | Mod | Pow => true
        BitAnd | BitOr | BitXor | Shl | Shr | UShr => true
        Add => is_expr_numeric(l, g, numeric) && is_expr_numeric(r, g, numeric)
        _ => false
      }
    Cond(_, t, e) =>
      is_expr_numeric(t, g, numeric) && is_expr_numeric(e, g, numeric)
    // `a = N` (assignment expression) — the result is `rhs`. If
    // rhs is numeric, the whole expression is.
    AssignExpr(_, rhs) => is_expr_numeric(rhs, g, numeric)
    CompoundAssignExpr(_, _, _) => true // all compound assigns are numeric
    Seq(_, b) => is_expr_numeric(b, g, numeric)
    // Resolve `Var(n)` through the graph. We don't carry the
    // current scope here — names go through every scope they could
    // resolve to. Conservative: only proceed when the name appears
    // exactly once in `symbols` (= no shadowing). Production
    // implementations would thread scope info through; the
    // wildcard fallback keeps us safe either way.
    @ast.TsExpr::Var(n) =>
      // Find a UNIQUE matching symbol. Shadowed names give up.
      lookup_unique_symbol(g, n) is Some(id) && numeric.contains(id)
    _ => false
  }
}

///|
/// Find the single symbol matching `name` across the whole graph.
/// Returns `None` when the name doesn't appear or appears more than
/// once (shadowing in nested scopes — we conservatively decline).
fn lookup_unique_symbol(g : SymbolGraph, name : String) -> SymbolId? {
  let mut hit : SymbolId? = None
  for s in g.symbols {
    if s.name == name {
      if hit is Some(_) {
        return None // shadowed
      }
      hit = Some(s.id)
    }
  }
  hit
}

// ---------------------------------------------------------------------------
// Graph-aware version of the existing `is_index_known_numeric`
// check used by `mangle_safety.collect_props_on_external_expr`.
// ---------------------------------------------------------------------------

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
  is_expr_numeric(idx, g, numeric)
}

///|
/// Project the symbol-id-keyed numeric map down to a name-keyed
/// set, dropping any name that appears more than once in `g`
/// (shadowing — without scope info the caller can't tell which
/// binding the name refers to, so conservatively decline).
///
/// `mangle_safety.collect_props_on_external_*` consumes this so
/// the IndexAccess wildcard fallback can ask "is `idx` a numeric
/// variable?" without threading the whole graph through every
/// helper.
pub fn numeric_name_set(
  g : SymbolGraph,
  numeric : Map[SymbolId, Bool],
) -> Map[String, Bool] {
  let counts : Map[String, Int] = {}
  for s in g.symbols {
    counts[s.name] = counts.get(s.name).unwrap_or(0) + 1
  }
  let out : Map[String, Bool] = {}
  for s in g.symbols {
    if numeric.contains(s.id) && counts.get(s.name).unwrap_or(0) == 1 {
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

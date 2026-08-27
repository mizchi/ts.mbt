// Phase 2b of the observability analysis: infer which bindings hold a
// *keyed container* — an array, a tuple, a string, a `Record`-shaped
// map — rather than an object whose members have names.
//
// Motivation:
//   `class_method_dce` may not delete a method when the bundle reads a
//   member under a computed key it cannot predict. Two proofs clear
//   such a read. Either the key is provably numeric (that is
//   `numeric_vars.mbt`), or the RECEIVER is a keyed container: reading
//   `table[k]` out of a `Record<string, string>` returns an entry, and
//   an entry is not a method.
//
//   The declared type answers that directly when there is one. Real
//   code often has none at the binding that matters:
//
//     const middleware = this.#middleware            // field is typed
//     const tokens = markedPath.match(/…/g) || []    // string method
//     const resolvedBuffer = await Promise.all(buf)  // always an array
//
//   Each of these IS a container; only the annotation is missing. So
//   run the same shape of fixed point `numeric_vars.mbt` runs, over
//   container-yielding expressions instead of numeric ones.
//
// Soundness:
//   Start at "not a container" (= the conservative answer, which keeps
//   every method) and only promote with proof. A false negative costs
//   bytes. A false positive deletes a method something still reaches,
//   so every rule below has to hold for *any* runtime value the
//   expression can produce, not merely the expected one.
//
//   `x.match(re)` is worth spelling out: it yields an array or `null`.
//   `null[k]` throws whether or not the method is there, so the read
//   observes no name either way and the promotion is safe.

///|
/// Receiver types a computed-key read cannot reach a class method
/// through. `class_names` are the classes declared in this bundle —
/// the only ones whose methods can be deleted, and so the only names
/// that disqualify a generic head that happens to collide.
///
/// The caveat is structural typing: TypeScript would let a class
/// instance stand in for one of these if its members happened to fit.
/// That takes a class whose *every* member matches the container's
/// value type, which no real code writes on purpose.
pub fn type_is_keyed_container(
  t : @ast.TsType,
  class_names : Map[String, Bool],
  aliases : Map[String, @ast.TsType],
) -> Bool {
  type_is_keyed_container_seen(t, class_names, aliases, {})
}

///|
/// `seen` guards a self-referential alias (`type Tree = Record<string,
/// Tree>`) from recursing forever.
fn type_is_keyed_container_seen(
  t : @ast.TsType,
  class_names : Map[String, Bool],
  aliases : Map[String, @ast.TsType],
  seen : Map[String, Bool],
) -> Bool {
  match t {
    Array(_) | Tuple(_) | Rest(_) | String_ => true

    // An inline index-signature type — `{ [key: string]: Pattern }`.
    // Same standing as the `Record<string, Pattern>` spelling.
    Object(fields) => {
      for f in fields {
        match f.0 {
          String_ | Number | Int => return true
          _ => ()
        }
      }
      false
    }
    // `Record<string, string> | Record<string, string[]>` is a keyed
    // container whichever arm it turns out to be.
    Union(members) => {
      if members.is_empty() {
        return false
      }
      for m in members {
        if !type_is_keyed_container_seen(m, class_names, aliases, seen) {
          return false
        }
      }
      true
    }
    // A generic container head, then a named alias —
    // `type MatcherMap<T> = Record<string, Matcher<T>>` is a `Record`
    // however it is spelled at the use site. Type arguments are never
    // substituted: the question is the outermost shape, which does not
    // depend on them. A head that names a class declared here is
    // declined, since that is the class and not the utility type.
    Named(n) | Applied(n, _) =>
      if (
          n == "Record" ||
          n == "Array" ||
          n == "ReadonlyArray" ||
          n == "ReadonlyMap"
        ) &&
        !class_names.contains(n) {
        true
      } else if seen.contains(n) {
        false
      } else {
        match aliases.get(n) {
          Some(body) => {
            seen[n] = true
            let r = type_is_keyed_container_seen(
              body, class_names, aliases, seen,
            )
            seen.remove(n) |> ignore
            r
          }
          None => false
        }
      }
    _ => false
  }
}

///|
/// Everything the container inference needs about the bundle beyond
/// the symbol graph itself.
pub(all) struct ContainerFacts {
  /// Classes declared in this bundle.
  class_names : Map[String, Bool]
  /// Property names that are a keyed container on *every* class in the
  /// bundle that declares them, so `this.f` is one wherever it appears.
  this_fields : Map[String, Bool]
  /// Bindings declared `string`, so `s.match(…)` / `s.split(…)` on them
  /// is the `String` method and yields an array.
  strings : Map[String, Bool]
  /// `type X = …` bodies, so an alias to a container counts as one.
  aliases : Map[String, @ast.TsType]
}

///|
/// Run the container inference and return the set of symbol ids that
/// provably hold a keyed container.
pub fn infer_container_symbols(
  g : SymbolGraph,
  facts : ContainerFacts,
) -> Map[SymbolId, Bool] {
  let containers : Map[SymbolId, Bool] = {}
  let mut changed = true
  let mut rounds = 0
  // Monotone: each round only adds. The cap is a runaway backstop.
  while changed && rounds < 16 {
    changed = false
    rounds = rounds + 1
    // One projection per ROUND. `all_symbols_container` used to scan
    // every symbol per `Var(n)` lookup inside the round, which made
    // this quadratic — see the same note in `numeric_vars.mbt`.
    let name_container = container_name_set(g, containers)
    for sym in g.symbols {
      if containers.contains(sym.id) {
        continue
      }
      // The annotation settles it, and it is the only evidence a
      // parameter offers — there is no def to walk. It also outranks
      // the closure guard below: a write that violates the annotation
      // is not a write TypeScript admits.
      if type_is_keyed_container(sym.ts_type, facts.class_names, facts.aliases) {
        containers[sym.id] = true
        changed = true
        continue
      }
      // Without an annotation, a closure holding the binding could
      // write anything into it from a frame this pass does not follow.
      if sym.captured_by_closure {
        continue
      }
      if sym.defs.length() == 0 {
        continue
      }
      let mut all_container = true
      for d in sym.defs {
        match d.init {
          Some(e) =>
            if !is_expr_container(e, name_container, facts) {
              all_container = false
              break
            }
          None => {
            all_container = false
            break
          }
        }
      }
      // A reassignment can replace the value wholesale, so every rhs
      // has to be a container too. `x = x` style self-reference gets
      // the same tentative promotion `numeric_vars` uses.
      if all_container && sym.reassigned {
        let tentative_added = !containers.contains(sym.id)
        if tentative_added {
          containers[sym.id] = true
          if name_all_container(g, sym.name, containers) {
            name_container[sym.name] = true
          }
        }
        let mut all_rhs = true
        for rhs in sym.reassign_rhs {
          if !is_expr_container(rhs, name_container, facts) {
            all_rhs = false
            break
          }
        }
        if !all_rhs {
          if tentative_added {
            let _ = containers.remove(sym.id)
            let _ = name_container.remove(sym.name)
          }
          all_container = false
        }
      }
      if all_container {
        containers[sym.id] = true
        changed = true
      }
    }
  }
  containers
}

///|
/// Is every value this expression can produce a keyed container?
fn is_expr_container(
  expr : @ast.TsExpr,
  name_container : Map[String, Bool],
  facts : ContainerFacts,
) -> Bool {
  match expr {
    ArrayLit(_) => true
    StringLit(_) | TemplateLiteral(_, _) => true
    // Both arms have to be containers: `foo || []` where `foo` is an
    // object is not one.
    BinOp(op, l, r) =>
      match op {
        Or | Coalesce =>
          is_expr_container(l, name_container, facts) &&
          is_expr_container(r, name_container, facts)
        _ => false
      }
    Cond(_, t, e) =>
      is_expr_container(t, name_container, facts) &&
      is_expr_container(e, name_container, facts)
    Await(inner) | NonNull(inner) | TypeArgs(_, inner) | PureCall(inner) =>
      is_expr_container(inner, name_container, facts)
    // `Promise.all` / `Promise.allSettled` resolve to an array, always.
    // Declined if the bundle declares its own `Promise`.
    MethodCall(@ast.TsExpr::Var("Promise"), m, _) =>
      (m == "all" || m == "allSettled") &&
      !facts.class_names.contains("Promise")
    // A `String` method that returns an array. `match` can return
    // `null` instead, and `null[k]` throws whether or not the method
    // is still there, so it observes no name either way.
    MethodCall(recv, m, _) =>
      (m == "match" || m == "split" || m == "matchAll") &&
      is_string_receiver(recv, facts)
    // `this.f` inside a class body is that class's field. Promoted
    // only when every class declaring `f` types it as a container, so
    // it does not matter which class this is.
    PropAccess(@ast.TsExpr::Var("this"), f) => facts.this_fields.contains(f)
    // Resolve a bare name the way `numeric_vars` does: with no scope
    // at the use site, require every binding of the name to qualify.
    @ast.TsExpr::Var(n) => name_container.contains(n)
    _ => false
  }
}

///|
fn is_string_receiver(recv : @ast.TsExpr, facts : ContainerFacts) -> Bool {
  match recv {
    StringLit(_) | TemplateLiteral(_, _) => true
    Var(n) => facts.strings.contains(n)
    _ => false
  }
}

///|
/// True when `name` is declared somewhere and every binding carrying it
/// is a container. Only the fixed point's speculative self-promotion
/// needs this one-off scan; ordinary lookups read the per-round
/// projection.
fn name_all_container(
  g : SymbolGraph,
  name : String,
  containers : Map[SymbolId, Bool],
) -> Bool {
  let mut seen = false
  for s in g.symbols {
    if s.name == name {
      if !containers.contains(s.id) {
        return false
      }
      seen = true
    }
  }
  seen
}

///|
/// Project the symbol-id-keyed container map onto names, accepting a
/// name when every binding carrying it qualifies.
pub fn container_name_set(
  g : SymbolGraph,
  containers : Map[SymbolId, Bool],
) -> Map[String, Bool] {
  let disqualified : Map[String, Bool] = {}
  for s in g.symbols {
    if !containers.contains(s.id) {
      disqualified[s.name] = true
    }
  }
  let out : Map[String, Bool] = {}
  for s in g.symbols {
    if containers.contains(s.id) && !disqualified.contains(s.name) {
      out[s.name] = true
    }
  }
  out
}

///|
/// Bindings declared `string`, for the `s.match(…)` rule. Same
/// all-or-nothing projection as everything else here.
pub fn string_name_set(g : SymbolGraph) -> Map[String, Bool] {
  let disqualified : Map[String, Bool] = {}
  for s in g.symbols {
    if !(s.ts_type is String_) {
      disqualified[s.name] = true
    }
  }
  let out : Map[String, Bool] = {}
  for s in g.symbols {
    if s.ts_type is String_ && !disqualified.contains(s.name) {
      out[s.name] = true
    }
  }
  out
}

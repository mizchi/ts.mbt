// Why can't this code be minified?
//
// The escape analysis answers a yes/no question — is this property name
// observable from outside the bundle? — and the answer is all the
// mangler needs. It is not what a person needs. When
// `--mangle-properties` quietly declines to rename anything, or renames
// everything except the one name you expected it to shorten, the useful
// output is not a set of names: it is *which rule fired, on which
// expression, and what would have to change*.
//
// So the reserved set is computed here in pieces rather than merged, and
// each piece carries its own provenance. `collect_externally_visible_props`
// is a thin merge over this; nothing is analysed twice, and the
// explanation can't drift from the decision because they come from the
// same run.
//
// The wildcard gets special treatment. A single `*` suppresses property
// mangling for the entire bundle, so "why is the wildcard set?" is the
// question that matters most, and the answer names the binding or the
// expression responsible.

///|
/// The reserved set, unmerged, with the reason for each part.
pub(all) struct EscapeBreakdown {
  // Names read off an external import or an ambient global — someone
  // else's ABI.
  external_chain : Array[String]
  // Names the sink observability lattice reserved: the value reaches
  // `console.log`, `JSON.stringify`, `Object.keys`, a `for-in`, …
  sink_observability : Array[String]
  // Keys of an object literal handed straight to a sink, which has no
  // free variable for the flow analysis to seed.
  sink_literal : Array[String]
  // Names read off a value whose provenance is the host (`JSON.parse`
  // output, a foreign factory's result, a callback parameter).
  host_shaped : Array[String]
  // Names reached by the value-tree walk from a recursively observed
  // root.
  value_tree : Array[String]
  // Names spelled by a `"k" in obj` probe.
  in_probe : Array[String]
  // Why the wildcard fired. Empty means the analysis does not suppress
  // property mangling.
  wildcard_reasons : Array[String]
}

///|
/// Compute the reserved set in pieces. `collect_externally_visible_props`
/// merges the result; `--explain-mangle` prints it.
pub fn escape_breakdown(
  block : @ast.TsBlock,
  external_bindings : Map[String, Bool],
  type_env? : Map[String, @ast.TsType] = {},
) -> EscapeBreakdown {
  // Phase 0: whole-block provenance. Which binding names hold a value
  // the host owns, and which bundle functions hand one back. The graph
  // walk needs this up front so it can classify each call site by
  // "can I prove the callee is internal?" rather than by "is this one
  // of the calls I know to be dangerous?" — see
  // `callee_provenance.mbt` for why that inversion matters.
  let (host_shaped_names, host_returning) = host_provenance_names(
    block, external_bindings,
  )
  let (graph, scoped_sinks) = build_symbol_graph_with_sinks(
    block,
    external_bindings,
    host_shaped=host_shaped_names,
    host_returning~,
  )
  let numeric = infer_numeric_symbols(graph)
  let numeric_names = numeric_name_set(graph, numeric)
  // Bindings whose TS annotation is a closed string-literal type or a
  // union of them. Lets an `external.obj[k] = v` site reserve the exact
  // key set instead of the wildcard.
  let literal_idx_names = literal_string_name_set(graph)
  let reserved_external : Map[String, Bool] = {}
  collect_props_on_external_block(
    block, external_bindings, reserved_external, numeric_names, literal_idx_names,
  )
  // Backward-propagate observability from sinks through FuncReturn /
  // FuncArg edges, so a value reaching a sink through a parameter or a
  // return still tracks back to the binding it came from.
  let obs_map = analyze_observability(graph, scoped_sinks)
  // Class members, so an observed class contributes the names its
  // instances carry. `console.log(new C())` seeds C's own symbol (see
  // `seed_from_expr`) and this is what turns that into `C`'s field and
  // method names.
  let class_members = class_member_names(block)
  let reserved_obs = reserved_props_from_observability(
    graph,
    obs_map,
    type_env~,
    class_members~,
  )
  // A sink argument that IS an object literal (`external.send({ id: 1 })`)
  // has no free variable to seed, so the flow analysis never sees it.
  // Its keys leave all the same.
  let reserved_literals : Map[String, Bool] = {}
  for entry in scoped_sinks {
    let (sink, _) = entry
    match sink.observation {
      StringifyOnly => ()
      _ => collect_object_literal_keys(sink.expr, reserved_literals)
    }
  }
  // A value observed *recursively* exposes its whole tree, not just the
  // keys on its own initializer. Walking a value tree from a set of
  // roots is what door 1 does from the entry's exports; same walk,
  // different roots.
  let recursive_roots : Map[String, Bool] = {}
  for entry in obs_map {
    let (sym_id, obs) = entry
    let sym = graph.symbols[sym_id]
    match obs {
      RecursiveProps | External => recursive_roots[sym.name] = true
      // `Object.keys(x)` / `for-in x` enumerate ONE level, and keeping
      // that distinction is where the precision lives. But the one-level
      // rule reads keys off the binding's own object literal, so it
      // finds nothing when the value came from a function, an array
      // element or a constructor. Precise rule when the literal is
      // visible; whole tree when it isn't.
      DirectProps =>
        if !has_object_literal_def(sym) {
          recursive_roots[sym.name] = true
        }
      _ => ()
    }
  }
  let reserved_tree : Map[String, Bool] = {}
  if recursive_roots.size() > 0 {
    for n in exported_surface_props(block, recursive_roots) {
      reserved_tree[n] = true
    }
  }
  // A binding whose value CAME FROM outside carries a shape the host
  // owns. Note the direction: for a value coming IN, the names our code
  // reads off it are exactly the ones that must survive — a name we
  // never read can't be broken by renaming ours. The wildcard is for the
  // other direction, a value going OUT to a body we can't see.
  let reserved_from_external : Map[String, Bool] = {}
  for sym in graph.symbols {
    let mut from_external = host_shaped_names.contains(sym.name)
    for d in sym.defs {
      match d.init {
        Some(init) =>
          if is_external_chain(init, external_bindings) {
            from_external = true
          }
        None => ()
      }
    }
    if from_external {
      for u in sym.uses {
        match u.context {
          PropReceiver(p) => reserved_from_external[p] = true
          _ => ()
        }
      }
    }
  }
  // `"k" in obj` names a property with a string the mangler does not
  // rewrite, so `k` has to survive.
  let reserved_in_probes : Map[String, Bool] = {}
  collect_in_probe_names_block(block, reserved_in_probes)
  // Attribute the wildcard. Two sources: a binding that crosses the
  // boundary without a closed type annotation, and a dynamic write or
  // read on an external chain whose key can't be pinned down.
  let wildcard_reasons : Array[String] = []
  if reserved_obs.contains("*") {
    for entry in obs_map {
      let (sym_id, obs) = entry
      if obs is External {
        let sym = graph.symbols[sym_id]
        if type_observed_keys(sym.ts_type, type_env~) is None {
          wildcard_reasons.push(
            "binding `" +
            sym.name +
            "` crosses the bundle boundary and carries no closed type annotation, so every name on it is assumed reachable — annotating it with an interface, a type alias, or an inline object type whose keys are all literal narrows the reservation to those keys",
          )
        }
      }
    }
  }
  if reserved_external.contains("*") {
    explain_external_index_wildcards(
      block, external_bindings, numeric_names, literal_idx_names, wildcard_reasons,
    )
  }
  {
    external_chain: sorted_names(reserved_external),
    sink_observability: sorted_names(reserved_obs),
    sink_literal: sorted_names(reserved_literals),
    host_shaped: sorted_names(reserved_from_external),
    value_tree: sorted_names(reserved_tree),
    in_probe: sorted_names(reserved_in_probes),
    wildcard_reasons,
  }
}

///|
/// Every non-marker name in `m`, wildcard included, in a stable order.
fn sorted_names(m : Map[String, Bool]) -> Array[String] {
  let out : Array[String] = []
  for k in m.keys() {
    if !is_internal_marker_prop(k) {
      out.push(k)
    }
  }
  out.sort()
  out
}

///|
/// Find the `external.obj[key]` sites whose key the analysis couldn't
/// pin down, which is the other way the wildcard gets set.
///
/// Runs only in explain mode, and only when the wildcard is already
/// known to be present, so re-walking the block costs nothing in the
/// ordinary path.
fn explain_external_index_wildcards(
  block : @ast.TsBlock,
  externals : Map[String, Bool],
  numeric_names : Map[String, Bool],
  literal_idx_names : Map[String, Array[String]],
  out : Array[String],
) -> Unit {
  fn note(kind : String, recv : @ast.TsExpr) -> Unit {
    let root = external_chain_root(recv)
    let reason = "a dynamic " +
      kind +
      " on the external chain rooted at `" +
      root +
      "` uses a key the analysis can't pin down — giving the key expression a string-literal union type (`\"a\" | \"b\"`) narrows it to those names"
    if !out.contains(reason) {
      out.push(reason)
    }
  }

  fn check(recv : @ast.TsExpr, idx : @ast.TsExpr, kind : String) -> Unit {
    if is_external_chain(recv, externals) {
      let probe : Map[String, Bool] = {}
      if !reserve_external_index_keys(
          idx, probe, numeric_names, literal_idx_names,
        ) {
        note(kind, recv)
      }
    }
  }

  fn walk_stmt(s : @ast.TsStmt) -> Unit {
    match s {
      IndexAssign(t, idx, _) => check(t, idx, "write")
      _ => ()
    }
  }

  for s in block.stmts {
    walk_stmt(s)
  }
  surface_visit_exprs_block(block, e => {
    match e {
      @ast.TsExpr::IndexAccess(recv, idx) => check(recv, idx, "read")
      @ast.TsExpr::IndexAssignExpr(recv, idx, _) => check(recv, idx, "write")
      _ => ()
    }
  })
}

///|
/// The identifier an external chain starts from, for the message.
fn external_chain_root(expr : @ast.TsExpr) -> String {
  match expr {
    Var(n) => n
    PropAccess(recv, _)
    | MethodCall(recv, _, _)
    | IndexAccess(recv, _)
    | CallExpr(recv, _)
    | NewExpr(recv, _) => external_chain_root(recv)
    Call(n, _) | New(n, _) => n
    NonNull(i)
    | OptionalChain(i)
    | As(i, _)
    | Satisfies(i, _)
    | TypeArgs(_, i) => external_chain_root(i)
    _ => "?"
  }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

///|
fn explain_section(
  out : Array[String],
  title : String,
  names : Array[String],
) -> Unit {
  let shown : Array[String] = []
  for n in names {
    if n != "*" {
      shown.push(n)
    }
  }
  if shown.length() == 0 {
    return
  }
  out.push("  " + title + " (" + shown.length().to_string() + ")")
  // Long lists are the norm on a real bundle; the first handful plus a
  // count is what a person reads.
  let limit = 12
  let mut line = "   "
  for i, n in shown {
    if i >= limit {
      out.push(line)
      out.push(
        "      … and " + (shown.length() - limit).to_string() + " more",
      )
      return
    }
    line = line + " " + n
  }
  out.push(line)
}

///|
/// Render the breakdown as the body of `--explain-mangle`.
pub fn format_escape_explanation(b : EscapeBreakdown) -> Array[String] {
  let out : Array[String] = []
  out.push("property mangling: why names are reserved")
  out.push("")
  if b.wildcard_reasons.length() > 0 {
    out.push("  SUPPRESSED — the analysis reserved the wildcard, so no")
    out.push("  user-declared property name is renamed. Causes:")
    for r in b.wildcard_reasons {
      out.push("    * " + r)
    }
    out.push("")
  } else {
    out.push("  enabled — no wildcard; only the names below are reserved.")
    out.push("")
  }
  explain_section(
    out,
    "read off an external import or ambient global",
    b.external_chain,
  )
  explain_section(out, "reaches a side-effect sink", b.sink_observability)
  explain_section(out, "literal key handed straight to a sink", b.sink_literal)
  explain_section(out, "read off a host-shaped value", b.host_shaped)
  explain_section(out, "reachable through an observed value tree", b.value_tree)
  explain_section(out, "named by an `in` probe", b.in_probe)
  out
}

// Discriminant-tag string → number rewrite (whole-program).
//
// When a closed discriminated-union type alias has every variant
// tag as a string literal, and the bundle uses the discriminant
// property ONLY in `switch` heads and equality comparisons, the
// string-typed tag can be replaced by a small integer:
//
//   type Shape = { kind: "circle", r: number }
//              | { kind: "square", side: number };
//
//   const s: Shape = { kind: "circle", r: 3 };
//   switch (s.kind) {
//     case "circle": return Math.PI * s.r ** 2;
//     case "square": return s.side ** 2;
//   }
//
// becomes
//
//   const s = { kind: 0, r: 3 };
//   switch (s.kind) {
//     case 0: return Math.PI * s.r ** 2;
//     case 1: return s.side ** 2;
//   }
//
// Wins: small-integer comparison fast-paths, smaller output.
//
// Safety (whole-program). The rewrite is gated on the bundle
// containing NONE of these escape sinks anywhere — any of them
// could observe the original string value at runtime:
//
//   * `JSON.stringify` / `JSON.parse` (any args)
//   * `console.<anything>(...)` (any args)
//   * `fetch(...)` (any args)
//   * `Object.keys` / `entries` / `values` / `assign` / `fromEntries`
//   * Spread (`...x`)
//   * `for-in` loops
//   * Template literals with any interpolation
//
// Per-property safety: every `PropAccess(_, K)` /
// `IndexAccess(_, StringLit(K))` must appear in one of these
// safe positions:
//
//   * Discriminant of a `switch (e.K)` head, and every case in
//     that switch must be a `StringLit` in the union's literal
//     set (or `default:`).
//   * Either side of `BinOp(BinEq | BinNe | AbstractEq |
//     AbstractNe, ..., StringLit)` where the other side's literal
//     is in the union's set.
//
// Per-K object-literal safety: every `ObjectLit` whose keys
// include `K` must give it a `StringLit` value that's in the
// union's set. (Otherwise we don't know what shape the literal
// belongs to.)
//
// When all three gates clear, the rewrite is performed in a
// single pass: each literal in the union's set gets a stable
// non-negative integer; `{ K: "lit", ... }` → `{ K: <id>, ... }`;
// `case "lit":` → `case <id>:`; and `e.K === "lit"` →
// `e.K === <id>` (similar for `!==` / `==` / `!=`).

///|
/// The two facts about the bundle boundary that `tag_rewrite_block`
/// cannot derive from the block it is handed.
pub(all) struct TagRewriteBoundary {
  // The bundle's exported local names (`export_roots`). The export
  // surface is an escape route that leaves NO trace inside the bundle:
  // this pass rewrites a property's VALUE, so
  // `export const c: Shape = { kind: "circle" }` becoming `{ kind: 0 }`
  // makes the consumer's `c.kind === "circle"` false, and no sink inside
  // the bundle mentions it — the consumer's comparison is outside.
  // `export function area(s: Shape)` is the same hazard mirrored: there
  // the CONSUMER builds `{ kind: "circle" }` and the bundle compares it
  // against `0`.
  //
  // Deliberately not `exported_surface_props`. That set answers the
  // property mangler's question — "may this NAME be renamed" — and is
  // right to be broader: it follows a called function's body, so
  // `export const out = area(shapes[0])` reserves `kind` even though the
  // consumer only ever sees a number. Rewriting a value needs the
  // narrower fact, the same split `class_method_dce` needed against
  // `collect_externally_visible_props`.
  exported : Map[String, Bool]
  // Bindings that name something IMPORTED from outside the bundle. A
  // call through one hands the argument to code we cannot read, which is
  // the same escape as a sink — `callee_provenance.mbt` makes the same
  // fail-closed call for the property mangler. Deliberately not
  // `external_import_bindings`, which unions in every implicit global:
  // this pass has its own catalog for those
  // (`serializing_method_names` / `serializing_callable_names`), and it
  // is the more precise answer. `Math.max(s.r)` hands off a number, not
  // the tagged object.
  externals : Map[String, Bool]
}

///|
pub fn tag_rewrite_block(
  block : @ast.TsBlock,
  type_aliases : Array[@ast.TsTypeAlias],
  // What the pass needs to know about the bundle BOUNDARY. Required and
  // positional, with no default, for the same reason
  // `class_method_dce_block` takes its `off_bundle` that way: `None`
  // means the caller did not compute it and the pass declines. A
  // labelled default here would fail OPEN — an empty `externals` is
  // FEWER sinks, not fewer candidates — and a wrapper node's fail-open
  // default has already cost this pipeline two soundness bugs
  // (`TypeArgs`, `PureCall`).
  boundary : TagRewriteBoundary?,
  // Every `interface` in the bundle. A union declares its variants as
  // named interfaces far more often than as inline object literals —
  // `type Shape = Circle | Square` is what real code writes, and
  // without this table every one of those reads as "not an object" and
  // the union is rejected before any safety gate runs. Defaults to
  // empty, which only ever makes the pass find FEWER candidates.
  interfaces? : Array[@ast.TsInterface] = [],
  // `--explain-mangle`: one line per reason the pass did nothing. The
  // pass moved zero bytes on all ten type-aware corpus targets and the
  // size number cannot say whether that is "no bundle declares the
  // shape" or "the shape is there and a gate refused it" — those want
  // opposite fixes, so the pass has to name which one it hit.
  explain? : Array[String]? = None,
) -> @ast.TsBlock {
  // 0. The boundary question, before anything else. An unanswered one
  //    means no tag may be renumbered.
  let (exported, externals) = match boundary {
    None => {
      match explain {
        Some(out) =>
          out.push(
            "declined — the caller supplied no bundle-boundary facts, so an exported or handed-off tag could not be ruled out.",
          )
        None => ()
      }
      return block
    }
    Some(b) => (b.exported, b.externals)
  }
  // 1. Gather discriminant property names + literal sets from
  //    closed string-literal Object-unions, and the map
  //    `alias_name -> K` so we can recognize type-annotated
  //    bindings later.
  let shapes = collect_named_shapes(interfaces, type_aliases)
  let unions = collect_discriminated_unions(type_aliases, shapes)
  if unions.is_empty() {
    match explain {
      Some(out) => explain_no_union_found(out, type_aliases, shapes)
      None => ()
    }
    return block
  }
  let alias_to_k = collect_alias_to_k(type_aliases, shapes)
  // 2. Per-K escape-sink scan. Instead of one global "any sink
  //    aborts everything" gate, walk every sink-arg expression and
  //    check, per K, whether the arg references something we
  //    believe is a K-tagged value (top-level binding initialized
  //    to `{ K: <lit-in-L>, ... }`, a binding annotated with an
  //    alias that resolves to a K-DU, a function parameter so
  //    annotated, or an inline `ObjectLit` carrying key K).
  //    When K's bindings don't show up in any sink, K survives.
  let sink_args = collect_escape_sink_args(block, externals)
  //    An exported declaration's own value leaves the bundle, so it
  //    joins the sink args: `export const c = { kind: "circle" }` and
  //    `export const make = () => ({ kind: "circle" })` both hand a tag
  //    to the consumer.
  for e in collect_exported_value_exprs(block, exported) {
    sink_args.push(e)
  }
  //    An exported SIGNATURE is the mirrored hazard, and no expression
  //    walk can see it: when the consumer builds the value, the bundle
  //    is the side comparing against a renumbered tag.
  let exported_type_names = collect_exported_signature_type_names(
    block, exported,
  )
  // 3. For each candidate K, verify the safety gates.
  let candidates : Map[String, Map[String, Int]] = {}
  for entry in unions {
    let (k, literals) = entry
    if k_type_name_is_exported(k, alias_to_k, shapes, exported_type_names)
      is Some(tname) {
      match explain {
        Some(out) =>
          out.push(
            "`\{k}` (\{literals.length()} tags) — `\{tname}` is part of the bundle's exported signature, so a consumer builds or reads the tag as a string.",
          )
        None => ()
      }
      continue
    }
    let lit_set : Map[String, Bool] = {}
    for s in literals {
      lit_set[s] = true
    }
    let k_bindings = collect_du_bindings_for_k(block, k, lit_set, alias_to_k)
    if any_sink_arg_taints_k(sink_args, k, lit_set, k_bindings) {
      match explain {
        Some(out) =>
          out.push(
            "`\{k}` (\{literals.length()} tags) — a value carrying it reaches an escape sink, which could read the tag as a string.",
          )
        None => ()
      }
      continue
    }
    if !check_prop_uses_safe(block, k, literals) {
      match explain {
        Some(out) =>
          out.push(
            "`\{k}` (\{literals.length()} tags) — the property is read somewhere other than a switch head or an equality comparison against one of its tags.",
          )
        None => ()
      }
      continue
    }
    if !check_object_literals_safe(block, k, literals) {
      match explain {
        Some(out) =>
          out.push(
            "`\{k}` (\{literals.length()} tags) — an object literal gives it a value that is not one of the union's tags, so its shape is unknown.",
          )
        None => ()
      }
      continue
    }
    let id_map : Map[String, Int] = {}
    for i in 0..<literals.length() {
      id_map[literals[i]] = i
    }
    candidates[k] = id_map
  }
  if candidates.is_empty() {
    return block
  }
  // 4. Rewrite phase.
  let new_stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    new_stmts.push(tag_rewrite_stmt(s, candidates))
  }
  { stmts: new_stmts, stmt_positions: block.stmt_positions }
}

///|
/// `name -> its string-literal properties`, for every named object
/// shape in the bundle: an `interface` (including the properties it
/// inherits through `extends`) and a `type X = { … }` alias.
///
/// Only string-literal-valued properties are recorded, because that is
/// the whole of what a discriminant can be. That also makes generic
/// arguments irrelevant: a property whose type is a type PARAMETER is
/// `Named(T)`, never `Literal(_)`, so it is not in this table and no
/// substitution is needed to know that `Circle<Meters>` and
/// `Circle<Feet>` agree on `kind: "circle"`.
fn collect_named_shapes(
  interfaces : Array[@ast.TsInterface],
  type_aliases : Array[@ast.TsTypeAlias],
) -> Map[String, Map[String, String]] {
  let by_name : Map[String, @ast.TsInterface] = {}
  for i in interfaces {
    by_name[i.name] = i
  }
  let out : Map[String, Map[String, String]] = {}
  for i in interfaces {
    let fields : Map[String, String] = {}
    // Walk the `extends` chain so a discriminant declared on a shared
    // base counts for every derived variant. `visited` guards the
    // cyclic declarations a hand-written `.d.ts` can contain; a
    // derived interface's own field wins over an inherited one.
    let visited : Map[String, Bool] = {}
    let queue = [i.name]
    while queue.pop() is Some(n) {
      if visited.contains(n) {
        continue
      }
      visited[n] = true
      let cur = match by_name.get(n) {
        Some(c) => c
        None => continue
      }
      for f in cur.fields {
        if f.1 is Literal(s) && !fields.contains(f.0) {
          fields[f.0] = s
        }
      }
      for b in cur.extends_names {
        queue.push(b)
      }
    }
    out[i.name] = fields
  }
  for ta in type_aliases {
    if ta.type_ is Object(fs) {
      let fields : Map[String, String] = {}
      for f in fs {
        if f.0 is Literal(k) && f.1 is Literal(v) {
          fields[k] = v
        }
      }
      out[ta.name] = fields
    }
  }
  out
}

///|
/// The VALUES an exported declaration hands to the consumer.
///
/// For a plain binding that is its own initializer. For a function or
/// arrow the initializer itself is useless — `expr_mentions_k` calls
/// every closure tainted, which would turn the pass off for any bundle
/// that exports a function — so what leaves is what the function
/// RETURNS, collected from its body.
fn collect_exported_value_exprs(
  block : @ast.TsBlock,
  exported : Map[String, Bool],
) -> Array[@ast.TsExpr] {
  let out : Array[@ast.TsExpr] = []
  for s in block.stmts {
    match s {
      Var(b, _, init) | Let(b, _, init) | Const(b, _, init) => {
        let mut is_exported = false
        for n in binding_names_in_order(b) {
          if exported.contains(n) {
            is_exported = true
          }
        }
        if !is_exported {
          continue
        }
        match init {
          FuncExpr(f) => collect_return_exprs(f.body, out)
          ArrowFunc(_, _, body, _) =>
            match body {
              ArrowExpr(e) => out.push(e)
              ArrowBlock(b2) => collect_return_exprs(b2, out)
            }
          _ => out.push(init)
        }
      }
      // An exported class hands over whatever its methods return and
      // whatever its constructor stores on `this`.
      NativeClassStmt(decl, ctor) => {
        if !exported.contains(decl.name) {
          continue
        }
        match ctor {
          Some(f) => collect_return_exprs(f.body, out)
          None => ()
        }
        for m in decl.methods {
          match m.body {
            Some(b) => collect_return_exprs(b, out)
            None => ()
          }
        }
        for sf in decl.static_field_inits {
          out.push(sf.1)
        }
      }
      _ => ()
    }
  }
  out
}

///|
/// Every `return <expr>` in a block, not descending into a nested
/// function — a nested function's returns go to its own caller, which
/// is inside the bundle unless that function itself escapes, and the
/// escape-sink scan is what covers that.
fn collect_return_exprs(block : @ast.TsBlock, out : Array[@ast.TsExpr]) -> Unit {
  for s in block.stmts {
    collect_return_exprs_stmt(s, out)
  }
}

///|
fn collect_return_exprs_stmt(
  stmt : @ast.TsStmt,
  out : Array[@ast.TsExpr],
) -> Unit {
  match stmt {
    Return(Some(e)) => out.push(e)
    If(_, t, e) => {
      collect_return_exprs(t, out)
      match e {
        Some(b) => collect_return_exprs(b, out)
        None => ()
      }
    }
    While(_, b)
    | DoWhile(_, b)
    | With(_, b)
    | ForOf(_, _, _, _, b)
    | ForAwaitOf(_, _, _, _, b)
    | ForIn(_, _, _, _, b)
    | Block(b) => collect_return_exprs(b, out)
    For(init, _, update, b) => {
      match init {
        Some(s) => collect_return_exprs_stmt(s, out)
        None => ()
      }
      match update {
        Some(s) => collect_return_exprs_stmt(s, out)
        None => ()
      }
      collect_return_exprs(b, out)
    }
    Switch(_, cases) =>
      for c in cases {
        collect_return_exprs(c.body, out)
      }
    Try(b, _, cb, fb) => {
      collect_return_exprs(b, out)
      match cb {
        Some(blk) => collect_return_exprs(blk, out)
        None => ()
      }
      match fb {
        Some(blk) => collect_return_exprs(blk, out)
        None => ()
      }
    }
    Label(_, inner) => collect_return_exprs_stmt(inner, out)
    _ => ()
  }
}

///|
/// The type NAMES that appear in the annotations of exported
/// declarations — the bundle's declared ABI. A union whose name is in
/// here is one the consumer writes values of.
fn collect_exported_signature_type_names(
  block : @ast.TsBlock,
  exported : Map[String, Bool],
) -> Map[String, Bool] {
  let out : Map[String, Bool] = {}
  for s in block.stmts {
    match s {
      Var(b, ty, init) | Let(b, ty, init) | Const(b, ty, init) => {
        let mut is_exported = false
        for n in binding_names_in_order(b) {
          if exported.contains(n) {
            is_exported = true
          }
        }
        if !is_exported {
          continue
        }
        collect_type_names(ty, out)
        match init {
          FuncExpr(f) => collect_func_signature_type_names(f, out)
          ArrowFunc(params, ret, _, _) => {
            for p in params {
              collect_type_names(p.type_, out)
            }
            collect_type_names(ret, out)
          }
          _ => ()
        }
      }
      NativeClassStmt(decl, ctor) => {
        if !exported.contains(decl.name) {
          continue
        }
        match ctor {
          Some(f) => collect_func_signature_type_names(f, out)
          None => ()
        }
        for m in decl.methods {
          for p in m.params {
            collect_type_names(p.1, out)
          }
          collect_type_names(m.return_type, out)
        }
        for pr in decl.properties {
          collect_type_names(pr.type_, out)
        }
      }
      _ => ()
    }
  }
  out
}

///|
fn collect_func_signature_type_names(
  f : @ast.TsFunc,
  out : Map[String, Bool],
) -> Unit {
  for p in f.params {
    collect_type_names(p.type_, out)
  }
  collect_type_names(f.return_type, out)
}

///|
/// Every `Named` / `Applied` name reachable inside a type, so a union
/// nested in `Shape[]`, `Promise<Shape>` or `{ items: Shape[] }` counts
/// as exported too.
fn collect_type_names(ty : @ast.TsType, out : Map[String, Bool]) -> Unit {
  match ty {
    Named(n) => out[n] = true
    Applied(n, args) => {
      out[n] = true
      for a in args {
        collect_type_names(a, out)
      }
    }
    Array(inner) | Rest(inner) => collect_type_names(inner, out)
    Tuple(items) | Union(items) | Intersection(items) =>
      for i in items {
        collect_type_names(i, out)
      }
    Object(fields) =>
      for f in fields {
        collect_type_names(f.1, out)
      }
    Func(params, ret) => {
      for p in params {
        collect_type_names(p, out)
      }
      collect_type_names(ret, out)
    }
    _ => ()
  }
}

///|
/// When K's own declared type name is part of the exported signature,
/// return it (for the diagnostic). K's type names are the union aliases
/// that resolve to K plus the individual variant shapes carrying K —
/// naming one variant exposes the tag just as well as naming the union.
fn k_type_name_is_exported(
  k : String,
  alias_to_k : Map[String, String],
  shapes : Map[String, Map[String, String]],
  exported_type_names : Map[String, Bool],
) -> String? {
  for name in exported_type_names.keys() {
    if alias_to_k.get(name) is Some(kk) && kk == k {
      return Some(name)
    }
    if shapes.get(name) is Some(fields) && fields.contains(k) {
      return Some(name)
    }
  }
  None
}

///|
/// `--explain-mangle` for the case that ends the pass before any gate
/// runs: `collect_discriminated_unions` found nothing. "Nothing" has
/// two very different causes and the byte count cannot tell them
/// apart — no alias in the bundle is a multi-variant union at all
/// (the shape is absent, and nothing about this pass is worth
/// changing), or aliases ARE unions and `find_common_string_discriminant`
/// rejected them (the gate is too closed, and the reason names what to
/// open). Report the counts and the rejecting shape, per alias.
fn explain_no_union_found(
  out : Array[String],
  type_aliases : Array[@ast.TsTypeAlias],
  shapes : Map[String, Map[String, String]],
) -> Unit {
  let mut unions = 0
  let mut unresolved_variant = 0
  let mut no_common_key = 0
  // Which variant shape did the rejection. A named reference that
  // `shapes` cannot resolve is a variant declared outside the bundle
  // (an ambient `.d.ts`, a dependency's types) — that is a different
  // problem from a variant that is genuinely not an object.
  let labels : Map[String, Int] = {}
  for ta in type_aliases {
    match ta.type_ {
      Union(parts) => {
        if parts.length() < 2 {
          continue
        }
        unions = unions + 1
        let mut all_resolved = true
        for p in parts {
          if object_string_literal_fields(p, shapes) is None {
            all_resolved = false
            let s = type_shape_label(p)
            labels[s] = labels.get(s).unwrap_or(0) + 1
          }
        }
        if all_resolved {
          if find_common_string_discriminant(parts, shapes) is None {
            no_common_key = no_common_key + 1
          }
        } else {
          unresolved_variant = unresolved_variant + 1
        }
      }
      _ => ()
    }
  }
  if unions == 0 {
    out.push(
      "no candidate at all: of \{type_aliases.length()} type aliases in the bundle, none is a union of two or more variants. The shape this pass rewrites is absent.",
    )
    return
  }
  out.push(
    "no candidate: \{unions} of \{type_aliases.length()} type aliases are multi-variant unions, and every one was rejected.",
  )
  if unresolved_variant > 0 {
    let parts : Array[String] = []
    for s in labels.keys() {
      parts.push("\{s} x\{labels.get(s).unwrap_or(0)}")
    }
    parts.sort()
    out.push(
      "  \{unresolved_variant} had a variant that is not an object shape this pass can read (\{parts.join(", ")}).",
    )
  }
  if no_common_key > 0 {
    out.push(
      "  \{no_common_key} were unions of object shapes with no property that is a string literal in every variant.",
    )
  }
}

///|
/// A one-word label for a type's outermost shape, for the diagnostic
/// above. Not exhaustive: everything the classifier does not name
/// individually is "other", which is enough to say whether the
/// rejecting shape is the one worth teaching the pass about.
fn type_shape_label(ty : @ast.TsType) -> String {
  match ty {
    Named(_) => "named reference"
    Applied(_, _) => "generic reference"
    Literal(_) => "string literal"
    NumberLiteral(_) | BigIntLiteral(_) | BooleanLiteral(_) => "literal"
    Null | Undefined => "null/undefined"
    Number | Int | Boolean | String_ | BigInt | Symbol => "primitive"
    Array(_) | Tuple(_) => "array/tuple"
    Func(_, _) | GenericFunc(_, _, _) => "function"
    Intersection(_) => "intersection"
    Union(_) => "nested union"
    _ => "other"
  }
}

///|
/// Build a name -> K map for every type alias whose body is a
/// closed string-literal discriminated union with discriminant K.
fn collect_alias_to_k(
  type_aliases : Array[@ast.TsTypeAlias],
  shapes : Map[String, Map[String, String]],
) -> Map[String, String] {
  let out : Map[String, String] = {}
  for ta in type_aliases {
    match ta.type_ {
      Union(parts) => {
        if parts.length() < 2 {
          continue
        }
        match find_common_string_discriminant(parts, shapes) {
          Some((k, _)) => out[ta.name] = k
          None => ()
        }
      }
      _ => ()
    }
  }
  out
}

///|
/// Collect bindings that are statically known to carry a K-DU
/// value:
///   * `const x = ObjectLit([..., (K, StringLit(lit)), ...])`
///     where `lit ∈ literals`.
///   * `const x: Alias = …` / `let x: Alias = …` where `Alias` is
///     a known DU alias for `K`.
///   * Function parameter `(x: Alias)` where `Alias` resolves to K.
///     These get scoped per-function, but for the conservative
///     check we treat any such name as globally tainted.
///
/// Returns the union of all qualifying names. The pass is
/// intentionally lossy on scope — a name collision (parameter `s`
/// in one function, top-level `const s = …` elsewhere) errs on the
/// side of aborting K.
fn collect_du_bindings_for_k(
  block : @ast.TsBlock,
  k : String,
  literals : Map[String, Bool],
  alias_to_k : Map[String, String],
) -> Map[String, Bool] {
  let out : Map[String, Bool] = {}
  collect_du_bindings_block(block, k, literals, alias_to_k, out)
  out
}

///|
fn collect_du_bindings_block(
  block : @ast.TsBlock,
  k : String,
  literals : Map[String, Bool],
  alias_to_k : Map[String, String],
  out : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    collect_du_bindings_stmt(s, k, literals, alias_to_k, out)
  }
}

///|
fn collect_du_bindings_stmt(
  stmt : @ast.TsStmt,
  k : String,
  literals : Map[String, Bool],
  alias_to_k : Map[String, String],
  out : Map[String, Bool],
) -> Unit {
  match stmt {
    Var(b, t, e) | Let(b, t, e) | Const(b, t, e) => {
      match b {
        @ast.TsBinding::Ident(name) => {
          if binding_type_is_k_du(t, k, alias_to_k) {
            out[name] = true
          }
          if expr_is_k_du_obj_lit(e, k, literals) {
            out[name] = true
          }
          // Alias propagation: `const y = x` carries the taint.
          match e {
            @ast.TsExpr::Var(other) =>
              if out.contains(other) {
                out[name] = true
              }
            _ => ()
          }
        }
        _ => ()
      }
      collect_du_bindings_expr(e, k, literals, alias_to_k, out)
    }
    Expr(e) | Assign(_, e) | CompoundAssign(_, _, e) | Throw(e) =>
      collect_du_bindings_expr(e, k, literals, alias_to_k, out)
    Return(Some(e)) => collect_du_bindings_expr(e, k, literals, alias_to_k, out)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => ()
    IndexAssign(t, idx, v) => {
      collect_du_bindings_expr(t, k, literals, alias_to_k, out)
      collect_du_bindings_expr(idx, k, literals, alias_to_k, out)
      collect_du_bindings_expr(v, k, literals, alias_to_k, out)
    }
    PropAssign(t, _, v) => {
      collect_du_bindings_expr(t, k, literals, alias_to_k, out)
      collect_du_bindings_expr(v, k, literals, alias_to_k, out)
    }
    If(c, t, e) => {
      collect_du_bindings_expr(c, k, literals, alias_to_k, out)
      collect_du_bindings_block(t, k, literals, alias_to_k, out)
      match e {
        Some(b) => collect_du_bindings_block(b, k, literals, alias_to_k, out)
        None => ()
      }
    }
    While(c, body) | DoWhile(c, body) | With(c, body) => {
      collect_du_bindings_expr(c, k, literals, alias_to_k, out)
      collect_du_bindings_block(body, k, literals, alias_to_k, out)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => collect_du_bindings_stmt(s, k, literals, alias_to_k, out)
        None => ()
      }
      match cond {
        Some(e) => collect_du_bindings_expr(e, k, literals, alias_to_k, out)
        None => ()
      }
      match update {
        Some(s) => collect_du_bindings_stmt(s, k, literals, alias_to_k, out)
        None => ()
      }
      collect_du_bindings_block(body, k, literals, alias_to_k, out)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      collect_du_bindings_expr(iter, k, literals, alias_to_k, out)
      collect_du_bindings_block(body, k, literals, alias_to_k, out)
    }
    Switch(e, cases) => {
      collect_du_bindings_expr(e, k, literals, alias_to_k, out)
      for c in cases {
        match c.test_expr {
          Some(te) => collect_du_bindings_expr(te, k, literals, alias_to_k, out)
          None => ()
        }
        collect_du_bindings_block(c.body, k, literals, alias_to_k, out)
      }
    }
    Try(b, _, cb, fb) => {
      collect_du_bindings_block(b, k, literals, alias_to_k, out)
      match cb {
        Some(blk) =>
          collect_du_bindings_block(blk, k, literals, alias_to_k, out)
        None => ()
      }
      match fb {
        Some(blk) =>
          collect_du_bindings_block(blk, k, literals, alias_to_k, out)
        None => ()
      }
    }
    Label(_, inner) =>
      collect_du_bindings_stmt(inner, k, literals, alias_to_k, out)
    Block(b) => collect_du_bindings_block(b, k, literals, alias_to_k, out)
    NativeClassStmt(_, _) => ()
  }
}

///|
fn collect_du_bindings_expr(
  expr : @ast.TsExpr,
  k : String,
  literals : Map[String, Bool],
  alias_to_k : Map[String, String],
  out : Map[String, Bool],
) -> Unit {
  match expr {
    FuncExpr(f) => {
      // Function parameters annotated with a K-DU alias also count.
      for p in f.params {
        if binding_type_is_k_du(p.type_, k, alias_to_k) {
          out[p.name] = true
        }
      }
      collect_du_bindings_block(f.body, k, literals, alias_to_k, out)
    }
    ArrowFunc(params, _, body, _) => {
      for p in params {
        if binding_type_is_k_du(p.type_, k, alias_to_k) {
          out[p.name] = true
        }
      }
      match body {
        ArrowExpr(e) =>
          collect_du_bindings_expr(e, k, literals, alias_to_k, out)
        ArrowBlock(b) =>
          collect_du_bindings_block(b, k, literals, alias_to_k, out)
      }
    }
    BinOp(_, l, r) | Seq(l, r) => {
      collect_du_bindings_expr(l, k, literals, alias_to_k, out)
      collect_du_bindings_expr(r, k, literals, alias_to_k, out)
    }
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | TypeArgs(_, inner)
    | YieldStar(inner) =>
      collect_du_bindings_expr(inner, k, literals, alias_to_k, out)
    Cond(c, t, e) => {
      collect_du_bindings_expr(c, k, literals, alias_to_k, out)
      collect_du_bindings_expr(t, k, literals, alias_to_k, out)
      collect_du_bindings_expr(e, k, literals, alias_to_k, out)
    }
    PropAccess(recv, _) =>
      collect_du_bindings_expr(recv, k, literals, alias_to_k, out)
    IndexAccess(recv, idx) => {
      collect_du_bindings_expr(recv, k, literals, alias_to_k, out)
      collect_du_bindings_expr(idx, k, literals, alias_to_k, out)
    }
    Call(_, args) | New(_, args) =>
      for a in args {
        collect_du_bindings_expr(a, k, literals, alias_to_k, out)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_du_bindings_expr(callee, k, literals, alias_to_k, out)
      for a in args {
        collect_du_bindings_expr(a, k, literals, alias_to_k, out)
      }
    }
    MethodCall(recv, _, args) => {
      collect_du_bindings_expr(recv, k, literals, alias_to_k, out)
      for a in args {
        collect_du_bindings_expr(a, k, literals, alias_to_k, out)
      }
    }
    ArrayLit(items) =>
      for i in items {
        collect_du_bindings_expr(i, k, literals, alias_to_k, out)
      }
    ObjectLit(entries) =>
      for ent in entries {
        collect_du_bindings_expr(ent.1, k, literals, alias_to_k, out)
      }
    _ => ()
  }
}

///|
/// True when `t` is `Applied(name, _)` (or bare `Named(name)`) with
/// `name` resolving to a K-DU alias.
fn binding_type_is_k_du(
  t : @ast.TsType,
  k : String,
  alias_to_k : Map[String, String],
) -> Bool {
  match t {
    Applied(name, _) =>
      match alias_to_k.get(name) {
        Some(k2) => k2 == k
        None => false
      }
    _ => false
  }
}

///|
/// True when `e` is `ObjectLit([..., (K, StringLit(lit)), ...])`
/// with `lit ∈ literals`.
fn expr_is_k_du_obj_lit(
  e : @ast.TsExpr,
  k : String,
  literals : Map[String, Bool],
) -> Bool {
  match e {
    ObjectLit(entries) => {
      for ent in entries {
        if ent.0 == k {
          match ent.1 {
            StringLit(s) => return literals.contains(s)
            _ => return false
          }
        }
      }
      false
    }
    _ => false
  }
}

///|
/// Collects every expression that appears as an argument to (or
/// receiver of) a known escape sink anywhere in the bundle. The
/// per-K check later inspects these for K-tainted references.
fn collect_escape_sink_args(
  block : @ast.TsBlock,
  externals : Map[String, Bool],
) -> Array[@ast.TsExpr] {
  let out : Array[@ast.TsExpr] = []
  collect_sink_args_block(block, out, externals)
  out
}

///|
fn collect_sink_args_block(
  block : @ast.TsBlock,
  out : Array[@ast.TsExpr],
  externals : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    collect_sink_args_stmt(s, out, externals)
  }
}

///|
fn collect_sink_args_stmt(
  stmt : @ast.TsStmt,
  out : Array[@ast.TsExpr],
  externals : Map[String, Bool],
) -> Unit {
  match stmt {
    Var(_, _, e)
    | Let(_, _, e)
    | Const(_, _, e)
    | Expr(e)
    | Assign(_, e)
    | CompoundAssign(_, _, e)
    | Throw(e) => collect_sink_args_expr(e, out, externals)
    Return(Some(e)) => collect_sink_args_expr(e, out, externals)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => ()
    IndexAssign(t, idx, v) => {
      collect_sink_args_expr(t, out, externals)
      collect_sink_args_expr(idx, out, externals)
      collect_sink_args_expr(v, out, externals)
    }
    PropAssign(t, _, v) => {
      collect_sink_args_expr(t, out, externals)
      collect_sink_args_expr(v, out, externals)
    }
    If(c, t, e) => {
      collect_sink_args_expr(c, out, externals)
      collect_sink_args_block(t, out, externals)
      match e {
        Some(b) => collect_sink_args_block(b, out, externals)
        None => ()
      }
    }
    While(c, body) | DoWhile(c, body) | With(c, body) => {
      collect_sink_args_expr(c, out, externals)
      collect_sink_args_block(body, out, externals)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => collect_sink_args_stmt(s, out, externals)
        None => ()
      }
      match cond {
        Some(e) => collect_sink_args_expr(e, out, externals)
        None => ()
      }
      match update {
        Some(s) => collect_sink_args_stmt(s, out, externals)
        None => ()
      }
      collect_sink_args_block(body, out, externals)
    }
    // `for-in` enumerates property names — treat the iterable as
    // a sink arg (it observes its discriminant property name).
    ForIn(_, _, _, iter, body) => {
      out.push(iter)
      collect_sink_args_block(body, out, externals)
    }
    ForOf(_, _, _, iter, body) | ForAwaitOf(_, _, _, iter, body) => {
      collect_sink_args_expr(iter, out, externals)
      collect_sink_args_block(body, out, externals)
    }
    Switch(e, cases) => {
      collect_sink_args_expr(e, out, externals)
      for c in cases {
        match c.test_expr {
          Some(te) => collect_sink_args_expr(te, out, externals)
          None => ()
        }
        collect_sink_args_block(c.body, out, externals)
      }
    }
    Try(b, _, cb, fb) => {
      collect_sink_args_block(b, out, externals)
      match cb {
        Some(blk) => collect_sink_args_block(blk, out, externals)
        None => ()
      }
      match fb {
        Some(blk) => collect_sink_args_block(blk, out, externals)
        None => ()
      }
    }
    Label(_, inner) => collect_sink_args_stmt(inner, out, externals)
    Block(b) => collect_sink_args_block(b, out, externals)
    NativeClassStmt(decl, ctor) => {
      // Scan constructor and method bodies for escape sinks so the
      // tag-rewrite doesn't apply if e.g. `JSON.stringify(x)` appears
      // inside a method body.
      match ctor {
        Some(f) => collect_sink_args_block(f.body, out, externals)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => collect_sink_args_block(b, out, externals)
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        collect_sink_args_expr(sf.1, out, externals)
      }
    }
  }
}

///|
fn collect_sink_args_expr(
  expr : @ast.TsExpr,
  out : Array[@ast.TsExpr],
  externals : Map[String, Bool],
) -> Unit {
  match expr {
    MethodCall(@ast.TsExpr::Var(recv), m, args) => {
      // A method call on a namespace import (`import * as ext`) or a
      // named import hands the argument off the bundle.
      if externals.contains(recv) {
        for a in args {
          out.push(a)
        }
        return
      }
      let recv_is_dangerous = recv == "JSON" ||
        recv == "console" ||
        recv == "Object"
      if recv_is_dangerous && serializing_method_names.contains(m) {
        // Treat every arg as escaping.
        for a in args {
          out.push(a)
        }
        return
      }
      for a in args {
        collect_sink_args_expr(a, out, externals)
      }
    }
    Call(name, args) => {
      // Same fail-closed call for a direct call to an imported name.
      // `eval` joins them: whatever it runs is unreadable by definition.
      if serializing_callable_names.contains(name) ||
        name == "eval" ||
        externals.contains(name) {
        for a in args {
          out.push(a)
        }
        return
      }
      for a in args {
        collect_sink_args_expr(a, out, externals)
      }
    }
    Spread(inner) => {
      // Spread of anything: that anything escapes.
      out.push(inner)
      collect_sink_args_expr(inner, out, externals)
    }
    TaggedTemplate(tag, _, _, exprs) => {
      collect_sink_args_expr(tag, out, externals)
      // Every interpolated expression escapes via the tag function.
      for e in exprs {
        out.push(e)
      }
    }
    TemplateLiteral(_, exprs) =>
      if exprs.length() > 0 {
        for e in exprs {
          out.push(e)
        }
      }
    MethodCall(recv, _, args) => {
      collect_sink_args_expr(recv, out, externals)
      for a in args {
        collect_sink_args_expr(a, out, externals)
      }
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_sink_args_expr(callee, out, externals)
      for a in args {
        collect_sink_args_expr(a, out, externals)
      }
    }
    New(_, args) =>
      for a in args {
        collect_sink_args_expr(a, out, externals)
      }
    BinOp(_, l, r) | Seq(l, r) => {
      collect_sink_args_expr(l, out, externals)
      collect_sink_args_expr(r, out, externals)
    }
    UnaryOp(_, inner)
    | Await(inner)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | TypeArgs(_, inner)
    | YieldStar(inner) => collect_sink_args_expr(inner, out, externals)
    Cond(c, t, e) => {
      collect_sink_args_expr(c, out, externals)
      collect_sink_args_expr(t, out, externals)
      collect_sink_args_expr(e, out, externals)
    }
    PropAccess(recv, _) => collect_sink_args_expr(recv, out, externals)
    IndexAccess(recv, idx) => {
      collect_sink_args_expr(recv, out, externals)
      collect_sink_args_expr(idx, out, externals)
    }
    ArrayLit(items) =>
      for i in items {
        collect_sink_args_expr(i, out, externals)
      }
    ObjectLit(entries) =>
      for ent in entries {
        collect_sink_args_expr(ent.1, out, externals)
      }
    ComputedProp(k, v) => {
      collect_sink_args_expr(k, out, externals)
      collect_sink_args_expr(v, out, externals)
    }
    AssignExpr(_, v) | AssignPattern(_, v) | PropAssignExpr(_, _, v) =>
      collect_sink_args_expr(v, out, externals)
    CompoundAssignExpr(t, _, v) => {
      collect_sink_args_expr(t, out, externals)
      collect_sink_args_expr(v, out, externals)
    }
    IndexAssignExpr(recv, idx, v) => {
      collect_sink_args_expr(recv, out, externals)
      collect_sink_args_expr(idx, out, externals)
      collect_sink_args_expr(v, out, externals)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => collect_sink_args_expr(e, out, externals)
        ArrowBlock(b) => collect_sink_args_block(b, out, externals)
      }
    FuncExpr(f) => collect_sink_args_block(f.body, out, externals)
    DynamicImport(spec, opts) => {
      collect_sink_args_expr(spec, out, externals)
      match opts {
        Some(o) => collect_sink_args_expr(o, out, externals)
        None => ()
      }
    }
    Yield(Some(inner)) => collect_sink_args_expr(inner, out, externals)
    _ => ()
  }
}

///|
/// Returns true if any of the collected sink-arg expressions
/// references a K-tagged binding or constructs a K-tagged literal
/// inline.
fn any_sink_arg_taints_k(
  args : Array[@ast.TsExpr],
  k : String,
  literals : Map[String, Bool],
  bindings : Map[String, Bool],
) -> Bool {
  for a in args {
    if expr_mentions_k(a, k, literals, bindings) {
      return true
    }
  }
  false
}

///|
fn expr_mentions_k(
  expr : @ast.TsExpr,
  k : String,
  literals : Map[String, Bool],
  bindings : Map[String, Bool],
) -> Bool {
  match expr {
    Var(n) => bindings.contains(n)
    ObjectLit(entries) => {
      for ent in entries {
        if ent.0 == k {
          match ent.1 {
            StringLit(s) => if literals.contains(s) { return true }
            _ => ()
          }
        }
        if expr_mentions_k(ent.1, k, literals, bindings) {
          return true
        }
      }
      false
    }
    BinOp(_, l, r) | Seq(l, r) =>
      expr_mentions_k(l, k, literals, bindings) ||
      expr_mentions_k(r, k, literals, bindings)
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | TypeArgs(_, inner)
    | YieldStar(inner) => expr_mentions_k(inner, k, literals, bindings)
    Cond(c, t, e) =>
      expr_mentions_k(c, k, literals, bindings) ||
      expr_mentions_k(t, k, literals, bindings) ||
      expr_mentions_k(e, k, literals, bindings)
    PropAccess(recv, _) => expr_mentions_k(recv, k, literals, bindings)
    IndexAccess(recv, idx) =>
      expr_mentions_k(recv, k, literals, bindings) ||
      expr_mentions_k(idx, k, literals, bindings)
    Call(name, args) => {
      if bindings.contains(name) {
        return true
      }
      for a in args {
        if expr_mentions_k(a, k, literals, bindings) {
          return true
        }
      }
      false
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      if expr_mentions_k(callee, k, literals, bindings) {
        return true
      }
      for a in args {
        if expr_mentions_k(a, k, literals, bindings) {
          return true
        }
      }
      false
    }
    MethodCall(recv, _, args) => {
      if expr_mentions_k(recv, k, literals, bindings) {
        return true
      }
      for a in args {
        if expr_mentions_k(a, k, literals, bindings) {
          return true
        }
      }
      false
    }
    New(name, args) => {
      if bindings.contains(name) {
        return true
      }
      for a in args {
        if expr_mentions_k(a, k, literals, bindings) {
          return true
        }
      }
      false
    }
    ArrayLit(items) => {
      for i in items {
        if expr_mentions_k(i, k, literals, bindings) {
          return true
        }
      }
      false
    }
    ComputedProp(kx, v) =>
      expr_mentions_k(kx, k, literals, bindings) ||
      expr_mentions_k(v, k, literals, bindings)
    AssignExpr(_, v) | AssignPattern(_, v) | PropAssignExpr(_, _, v) =>
      expr_mentions_k(v, k, literals, bindings)
    CompoundAssignExpr(t, _, v) =>
      expr_mentions_k(t, k, literals, bindings) ||
      expr_mentions_k(v, k, literals, bindings)
    IndexAssignExpr(recv, idx, v) =>
      expr_mentions_k(recv, k, literals, bindings) ||
      expr_mentions_k(idx, k, literals, bindings) ||
      expr_mentions_k(v, k, literals, bindings)
    As(inner, _) | Satisfies(inner, _) =>
      expr_mentions_k(inner, k, literals, bindings)
    Yield(Some(inner)) => expr_mentions_k(inner, k, literals, bindings)
    TaggedTemplate(tag, _, _, exprs) => {
      if expr_mentions_k(tag, k, literals, bindings) {
        return true
      }
      for e in exprs {
        if expr_mentions_k(e, k, literals, bindings) {
          return true
        }
      }
      false
    }
    TemplateLiteral(_, exprs) => {
      for e in exprs {
        if expr_mentions_k(e, k, literals, bindings) {
          return true
        }
      }
      false
    }
    // FuncExpr / ArrowFunc bodies: conservatively assume they could
    // leak the value via their closure. If a sink arg IS a closure
    // (e.g. `arr.map(x => console.log(x))`), there might be leaks
    // we miss. The conservative call: a closure-typed sink arg
    // taints K.
    FuncExpr(_) | ArrowFunc(_, _, _, _) => true
    _ => false
  }
}

// -- Step 1: discover discriminated unions ----------------------------

///|
/// Returns a deduplicated list of `(K, ordered_literals)` pairs.
/// `K` is the common literal-property name; `ordered_literals` is
/// the union of every literal value seen across variants (insertion
/// order kept so integer IDs stay stable across runs).
fn collect_discriminated_unions(
  type_aliases : Array[@ast.TsTypeAlias],
  shapes : Map[String, Map[String, String]],
) -> Map[String, Array[String]] {
  let out : Map[String, Array[String]] = {}
  for ta in type_aliases {
    match ta.type_ {
      Union(parts) => {
        if parts.length() < 2 {
          continue
        }
        // Find a common literal-string property across every part.
        let common = find_common_string_discriminant(parts, shapes)
        match common {
          Some((k, literals)) => {
            let existing = out.get(k).unwrap_or([])
            let seen : Map[String, Bool] = {}
            for s in existing {
              seen[s] = true
            }
            for s in literals {
              if !seen.contains(s) {
                seen[s] = true
                existing.push(s)
              }
            }
            out[k] = existing
          }
          None => ()
        }
      }
      _ => ()
    }
  }
  out
}

///|
/// Given the variant list of a `Union`, returns `(K, literals)`
/// when there exists a property name `K` whose value in every
/// variant is `Literal(string)`. `literals` is ordered by variant
/// (one entry per variant).
fn find_common_string_discriminant(
  parts : Array[@ast.TsType],
  shapes : Map[String, Map[String, String]],
) -> (String, Array[String])? {
  // Each part must be an `Object(fields)` carrying at least one
  // field whose value is `Literal(string)`. Build the set of
  // candidate field names from the first part, then intersect with
  // every subsequent part.
  let first_fields = match object_string_literal_fields(parts[0], shapes) {
    Some(m) => m
    None => return None
  }
  let mut candidate_keys : Map[String, Bool] = {}
  for entry in first_fields {
    candidate_keys[entry.0] = true
  }
  let per_part : Array[Map[String, String]] = [first_fields]
  for i in 1..<parts.length() {
    let m = match object_string_literal_fields(parts[i], shapes) {
      Some(m) => m
      None => return None
    }
    let next_keys : Map[String, Bool] = {}
    for entry in m {
      if candidate_keys.contains(entry.0) {
        next_keys[entry.0] = true
      }
    }
    candidate_keys = next_keys
    per_part.push(m)
    if candidate_keys.is_empty() {
      return None
    }
  }
  // Pick the first remaining candidate key (typically `kind` /
  // `type` / `tag` etc.). If multiple are eligible we just pick
  // one — the rewrite always touches the chosen property name
  // independently of others.
  let k = match candidate_keys.keys().to_array().get(0) {
    Some(s) => s
    None => return None
  }
  // Collect the literal value at `k` for each variant.
  let literals : Array[String] = []
  let seen : Map[String, Bool] = {}
  for fields in per_part {
    match fields.get(k) {
      Some(lit) =>
        if !seen.contains(lit) {
          seen[lit] = true
          literals.push(lit)
        }
      None => return None
    }
  }
  Some((k, literals))
}

///|
/// If `ty` is `Object(fields)`, returns the subset of fields
/// whose key is `Literal(name)` and value is `Literal(s)` — i.e.
/// the candidate discriminant properties. Returns `None` for any
/// non-`Object` type.
fn object_string_literal_fields(
  ty : @ast.TsType,
  shapes : Map[String, Map[String, String]],
) -> Map[String, String]? {
  match ty {
    Object(fields) => {
      let out : Map[String, String] = {}
      for f in fields {
        let key = match f.0 {
          Literal(s) => s
          _ => continue
        }
        let val = match f.1 {
          Literal(s) => s
          _ => continue
        }
        out[key] = val
      }
      Some(out)
    }
    // A variant named rather than written out. `shapes` already holds
    // only string-literal properties, inherited ones included, so the
    // lookup answers the same question the inline arm does.
    Named(n) | Applied(n, _) => shapes.get(n)
    _ => None
  }
}

// -- Step 2: bundle-wide escape sink scan -----------------------------

///|
/// Names whose use ANYWHERE in the bundle aborts the rewrite —
/// any of them could observe a discriminant tag as a string at
/// runtime.
let serializing_method_names : Array[String] = [
  "stringify", "parse", "log", "info", "warn", "error", "debug", "trace", "keys",
  "values", "entries", "assign", "fromEntries",
]

///|
let serializing_callable_names : Array[String] = ["fetch"]

///|
fn block_has_escape_sink(block : @ast.TsBlock) -> Bool {
  for s in block.stmts {
    if stmt_has_escape_sink(s) {
      return true
    }
  }
  false
}

///|
fn stmt_has_escape_sink(stmt : @ast.TsStmt) -> Bool {
  match stmt {
    Var(_, _, e)
    | Let(_, _, e)
    | Const(_, _, e)
    | Expr(e)
    | Assign(_, e)
    | CompoundAssign(_, _, e)
    | Throw(e) => expr_has_escape_sink(e)
    Return(Some(e)) => expr_has_escape_sink(e)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => false
    IndexAssign(t, idx, v) =>
      expr_has_escape_sink(t) ||
      expr_has_escape_sink(idx) ||
      expr_has_escape_sink(v)
    PropAssign(t, _, v) => expr_has_escape_sink(t) || expr_has_escape_sink(v)
    If(c, t, e) => {
      if expr_has_escape_sink(c) {
        return true
      }
      if block_has_escape_sink(t) {
        return true
      }
      match e {
        Some(b) => block_has_escape_sink(b)
        None => false
      }
    }
    While(c, body) | DoWhile(c, body) | With(c, body) =>
      expr_has_escape_sink(c) || block_has_escape_sink(body)
    For(init, cond, update, body) => {
      let init_bad = match init {
        Some(s) => stmt_has_escape_sink(s)
        None => false
      }
      if init_bad {
        return true
      }
      let cond_bad = match cond {
        Some(e) => expr_has_escape_sink(e)
        None => false
      }
      if cond_bad {
        return true
      }
      let upd_bad = match update {
        Some(s) => stmt_has_escape_sink(s)
        None => false
      }
      if upd_bad {
        return true
      }
      block_has_escape_sink(body)
    }
    // `for-in` is itself a sink (reflects all keys).
    ForIn(_, _, _, _, _) => true
    ForOf(_, _, _, iter, body) | ForAwaitOf(_, _, _, iter, body) =>
      expr_has_escape_sink(iter) || block_has_escape_sink(body)
    Switch(e, cases) => {
      if expr_has_escape_sink(e) {
        return true
      }
      for c in cases {
        match c.test_expr {
          Some(te) => if expr_has_escape_sink(te) { return true }
          None => ()
        }
        if block_has_escape_sink(c.body) {
          return true
        }
      }
      false
    }
    Try(b, _, cb, fb) => {
      if block_has_escape_sink(b) {
        return true
      }
      let cb_bad = match cb {
        Some(blk) => block_has_escape_sink(blk)
        None => false
      }
      if cb_bad {
        return true
      }
      match fb {
        Some(blk) => block_has_escape_sink(blk)
        None => false
      }
    }
    Label(_, inner) => stmt_has_escape_sink(inner)
    Block(b) => block_has_escape_sink(b)
    NativeClassStmt(decl, ctor) => {
      match ctor {
        Some(f) if block_has_escape_sink(f.body) => return true
        _ => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) if block_has_escape_sink(b) => return true
          _ => ()
        }
      }
      for sf in decl.static_field_inits {
        if expr_has_escape_sink(sf.1) {
          return true
        }
      }
      false
    }
  }
}

///|
fn expr_has_escape_sink(expr : @ast.TsExpr) -> Bool {
  match expr {
    // `JSON.foo(...)` / `console.foo(...)` / `Object.foo(...)`.
    MethodCall(@ast.TsExpr::Var(recv), m, args) => {
      let recv_is_dangerous = recv == "JSON" ||
        recv == "console" ||
        recv == "Object"
      if recv_is_dangerous && serializing_method_names.contains(m) {
        return true
      }
      for a in args {
        if expr_has_escape_sink(a) {
          return true
        }
      }
      false
    }
    Call(name, args) => {
      if serializing_callable_names.contains(name) {
        return true
      }
      for a in args {
        if expr_has_escape_sink(a) {
          return true
        }
      }
      false
    }
    CallExpr(callee, args) => {
      if expr_has_escape_sink(callee) {
        return true
      }
      for a in args {
        if expr_has_escape_sink(a) {
          return true
        }
      }
      false
    }
    MethodCall(recv, _, args) => {
      if expr_has_escape_sink(recv) {
        return true
      }
      for a in args {
        if expr_has_escape_sink(a) {
          return true
        }
      }
      false
    }
    New(_, args) | NewExpr(_, args) => {
      for a in args {
        if expr_has_escape_sink(a) {
          return true
        }
      }
      false
    }
    Spread(_) => true
    TemplateLiteral(_, exprs) => {
      // Template literal with interpolation might serialize a tag.
      if exprs.length() > 0 {
        return true
      }
      false
    }
    TaggedTemplate(_, _, _, _) => true
    BinOp(_, l, r) | Seq(l, r) =>
      expr_has_escape_sink(l) || expr_has_escape_sink(r)
    UnaryOp(_, inner)
    | Await(inner)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | TypeArgs(_, inner)
    | YieldStar(inner) => expr_has_escape_sink(inner)
    Cond(c, t, e) =>
      expr_has_escape_sink(c) ||
      expr_has_escape_sink(t) ||
      expr_has_escape_sink(e)
    PropAccess(recv, _) => expr_has_escape_sink(recv)
    IndexAccess(recv, idx) =>
      expr_has_escape_sink(recv) || expr_has_escape_sink(idx)
    ArrayLit(items) => {
      for i in items {
        if expr_has_escape_sink(i) {
          return true
        }
      }
      false
    }
    ObjectLit(entries) => {
      for ent in entries {
        if expr_has_escape_sink(ent.1) {
          return true
        }
      }
      false
    }
    ComputedProp(k, v) => expr_has_escape_sink(k) || expr_has_escape_sink(v)
    AssignExpr(_, v) | AssignPattern(_, v) | PropAssignExpr(_, _, v) =>
      expr_has_escape_sink(v)
    CompoundAssignExpr(t, _, v) =>
      expr_has_escape_sink(t) || expr_has_escape_sink(v)
    IndexAssignExpr(recv, idx, v) =>
      expr_has_escape_sink(recv) ||
      expr_has_escape_sink(idx) ||
      expr_has_escape_sink(v)
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => expr_has_escape_sink(e)
        ArrowBlock(b) => block_has_escape_sink(b)
      }
    FuncExpr(f) => block_has_escape_sink(f.body)
    DynamicImport(spec, opts) => {
      if expr_has_escape_sink(spec) {
        return true
      }
      match opts {
        Some(o) => expr_has_escape_sink(o)
        None => false
      }
    }
    Yield(Some(inner)) => expr_has_escape_sink(inner)
    _ => false
  }
}

// -- Step 3: per-K property-read and object-literal safety ------------

///|
/// Walk the block. Every `PropAccess(_, K)` and
/// `IndexAccess(_, StringLit(K))` must appear in a safe context.
fn check_prop_uses_safe(
  block : @ast.TsBlock,
  k : String,
  literals : Array[String],
) -> Bool {
  let lit_set : Map[String, Bool] = {}
  for s in literals {
    lit_set[s] = true
  }
  for s in block.stmts {
    if !prop_uses_safe_stmt(s, k, lit_set, false) {
      return false
    }
  }
  true
}

///|
fn prop_uses_safe_stmt(
  stmt : @ast.TsStmt,
  k : String,
  lits : Map[String, Bool],
  in_safe_pos : Bool,
) -> Bool {
  let _ = in_safe_pos
  match stmt {
    Var(_, _, e)
    | Let(_, _, e)
    | Const(_, _, e)
    | Expr(e)
    | Assign(_, e)
    | CompoundAssign(_, _, e)
    | Throw(e) => prop_uses_safe_expr(e, k, lits, false)
    Return(Some(e)) => prop_uses_safe_expr(e, k, lits, false)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => true
    IndexAssign(t, idx, v) =>
      prop_uses_safe_expr(t, k, lits, false) &&
      prop_uses_safe_expr(idx, k, lits, false) &&
      prop_uses_safe_expr(v, k, lits, false)
    PropAssign(t, _, v) =>
      prop_uses_safe_expr(t, k, lits, false) &&
      prop_uses_safe_expr(v, k, lits, false)
    If(c, t, e) => {
      if !prop_uses_safe_expr(c, k, lits, false) {
        return false
      }
      for s in t.stmts {
        if !prop_uses_safe_stmt(s, k, lits, false) {
          return false
        }
      }
      match e {
        Some(b) =>
          for s in b.stmts {
            if !prop_uses_safe_stmt(s, k, lits, false) {
              return false
            }
          }
        None => ()
      }
      true
    }
    While(c, body) | DoWhile(c, body) | With(c, body) => {
      if !prop_uses_safe_expr(c, k, lits, false) {
        return false
      }
      for s in body.stmts {
        if !prop_uses_safe_stmt(s, k, lits, false) {
          return false
        }
      }
      true
    }
    For(init, cond, update, body) => {
      let init_ok = match init {
        Some(s) => prop_uses_safe_stmt(s, k, lits, false)
        None => true
      }
      if !init_ok {
        return false
      }
      let cond_ok = match cond {
        Some(e) => prop_uses_safe_expr(e, k, lits, false)
        None => true
      }
      if !cond_ok {
        return false
      }
      let upd_ok = match update {
        Some(s) => prop_uses_safe_stmt(s, k, lits, false)
        None => true
      }
      if !upd_ok {
        return false
      }
      for s in body.stmts {
        if !prop_uses_safe_stmt(s, k, lits, false) {
          return false
        }
      }
      true
    }
    ForOf(_, _, _, iter, body) | ForAwaitOf(_, _, _, iter, body) => {
      if !prop_uses_safe_expr(iter, k, lits, false) {
        return false
      }
      for s in body.stmts {
        if !prop_uses_safe_stmt(s, k, lits, false) {
          return false
        }
      }
      true
    }
    // for-in is already an escape sink (caught above), but stay safe.
    ForIn(_, _, _, _, _) => false
    Switch(e, cases) => {
      // A `switch (e.K) { ... }` puts `e.K` in a safe position; the
      // case labels must all be `StringLit(in_lits)` or default.
      let disc_is_k = match e {
        PropAccess(_, name) => name == k
        IndexAccess(_, @ast.TsExpr::StringLit(name)) => name == k
        _ => false
      }
      if disc_is_k {
        // The discriminant expression's receiver is checked
        // separately (e.g. `s.kind` -> the receiver `s` shouldn't
        // mention K). For the discriminant itself, K is safe.
        let recv = match e {
          PropAccess(r, _) => r
          IndexAccess(r, _) => r
          _ => return false
        }
        if !prop_uses_safe_expr(recv, k, lits, false) {
          return false
        }
        for c in cases {
          match c.test_expr {
            Some(@ast.TsExpr::StringLit(s)) =>
              if !lits.contains(s) {
                return false
              }
            // Existing int labels (idempotency) and `default:` arms
            // are also OK.
            Some(@ast.TsExpr::IntLit(_)) | Some(@ast.TsExpr::NumberLit(_)) => ()
            Some(_) => return false
            None => ()
          }
          for s in c.body.stmts {
            if !prop_uses_safe_stmt(s, k, lits, false) {
              return false
            }
          }
        }
        return true
      }
      if !prop_uses_safe_expr(e, k, lits, false) {
        return false
      }
      for c in cases {
        match c.test_expr {
          Some(te) =>
            if !prop_uses_safe_expr(te, k, lits, false) {
              return false
            }
          None => ()
        }
        for s in c.body.stmts {
          if !prop_uses_safe_stmt(s, k, lits, false) {
            return false
          }
        }
      }
      true
    }
    Try(b, _, cb, fb) => {
      for s in b.stmts {
        if !prop_uses_safe_stmt(s, k, lits, false) {
          return false
        }
      }
      let cb_ok = match cb {
        Some(blk) => {
          for s in blk.stmts {
            if !prop_uses_safe_stmt(s, k, lits, false) {
              return false
            }
          }
          true
        }
        None => true
      }
      if !cb_ok {
        return false
      }
      match fb {
        Some(blk) => {
          for s in blk.stmts {
            if !prop_uses_safe_stmt(s, k, lits, false) {
              return false
            }
          }
          true
        }
        None => true
      }
    }
    Label(_, inner) => prop_uses_safe_stmt(inner, k, lits, false)
    Block(b) =>
      for s in b.stmts {
        if !prop_uses_safe_stmt(s, k, lits, false) {
          return false
        }
      } nobreak {
        true
      }
    NativeClassStmt(decl, ctor) => {
      match ctor {
        Some(f) =>
          for s in f.body.stmts {
            if !prop_uses_safe_stmt(s, k, lits, false) {
              return false
            }
          }
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) =>
            for s in b.stmts {
              if !prop_uses_safe_stmt(s, k, lits, false) {
                return false
              }
            }
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        if !prop_uses_safe_expr(sf.1, k, lits, false) {
          return false
        }
      }
      true
    }
  }
}

///|
fn prop_uses_safe_expr(
  expr : @ast.TsExpr,
  k : String,
  lits : Map[String, Bool],
  _in_safe_pos : Bool,
) -> Bool {
  match expr {
    PropAccess(recv, prop) =>
      if prop == k {
        // Bare `e.K` access is unsafe (not in a safe context). Only
        // sites we explicitly cleared in the parent (switch head /
        // comparison) are safe; we get here via fall-through, so
        // this is by definition an unsafe context.
        false
      } else {
        prop_uses_safe_expr(recv, k, lits, false)
      }
    IndexAccess(recv, @ast.TsExpr::StringLit(s)) =>
      if s == k {
        false
      } else {
        prop_uses_safe_expr(recv, k, lits, false)
      }
    IndexAccess(recv, idx) =>
      prop_uses_safe_expr(recv, k, lits, false) &&
      prop_uses_safe_expr(idx, k, lits, false)
    // Equality comparisons: when one side is `e.K` and the other is
    // a string literal in `lits`, the `.K` access is in a safe
    // position. Still walk the receiver (it shouldn't mention K
    // somewhere else).
    BinOp(op, l, r) => {
      let is_eq_op = match op {
        BinEq | BinNe | AbstractEq | AbstractNe => true
        _ => false
      }
      if is_eq_op {
        let pair = classify_eq_operand(l, r, k, lits)
        match pair {
          Some((recv, _)) =>
            // `e.K === "lit"` (or symmetric). Just verify the
            // receiver part has no further K-related issues.
            return prop_uses_safe_expr(recv, k, lits, false)
          None => ()
        }
      }
      prop_uses_safe_expr(l, k, lits, false) &&
      prop_uses_safe_expr(r, k, lits, false)
    }
    Seq(l, r) =>
      prop_uses_safe_expr(l, k, lits, false) &&
      prop_uses_safe_expr(r, k, lits, false)
    UnaryOp(_, inner)
    | Await(inner)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | TypeArgs(_, inner)
    | YieldStar(inner) => prop_uses_safe_expr(inner, k, lits, false)
    Cond(c, t, e) =>
      prop_uses_safe_expr(c, k, lits, false) &&
      prop_uses_safe_expr(t, k, lits, false) &&
      prop_uses_safe_expr(e, k, lits, false)
    Call(_, args) | New(_, args) => {
      for a in args {
        if !prop_uses_safe_expr(a, k, lits, false) {
          return false
        }
      }
      true
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      if !prop_uses_safe_expr(callee, k, lits, false) {
        return false
      }
      for a in args {
        if !prop_uses_safe_expr(a, k, lits, false) {
          return false
        }
      }
      true
    }
    MethodCall(recv, _, args) => {
      if !prop_uses_safe_expr(recv, k, lits, false) {
        return false
      }
      for a in args {
        if !prop_uses_safe_expr(a, k, lits, false) {
          return false
        }
      }
      true
    }
    ArrayLit(items) => {
      for i in items {
        if !prop_uses_safe_expr(i, k, lits, false) {
          return false
        }
      }
      true
    }
    ObjectLit(entries) => {
      for ent in entries {
        if !prop_uses_safe_expr(ent.1, k, lits, false) {
          return false
        }
      }
      true
    }
    Spread(_) => false
    AssignExpr(_, v) | AssignPattern(_, v) | PropAssignExpr(_, _, v) =>
      prop_uses_safe_expr(v, k, lits, false)
    CompoundAssignExpr(t, _, v) =>
      prop_uses_safe_expr(t, k, lits, false) &&
      prop_uses_safe_expr(v, k, lits, false)
    IndexAssignExpr(recv, idx, v) =>
      prop_uses_safe_expr(recv, k, lits, false) &&
      prop_uses_safe_expr(idx, k, lits, false) &&
      prop_uses_safe_expr(v, k, lits, false)
    ComputedProp(kx, v) =>
      prop_uses_safe_expr(kx, k, lits, false) &&
      prop_uses_safe_expr(v, k, lits, false)
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => prop_uses_safe_expr(e, k, lits, false)
        ArrowBlock(b) => {
          for s in b.stmts {
            if !prop_uses_safe_stmt(s, k, lits, false) {
              return false
            }
          }
          true
        }
      }
    FuncExpr(f) =>
      for s in f.body.stmts {
        if !prop_uses_safe_stmt(s, k, lits, false) {
          return false
        }
      } nobreak {
        true
      }
    DynamicImport(spec, opts) => {
      if !prop_uses_safe_expr(spec, k, lits, false) {
        return false
      }
      match opts {
        Some(o) => prop_uses_safe_expr(o, k, lits, false)
        None => true
      }
    }
    TaggedTemplate(_, _, _, _) => false
    TemplateLiteral(_, _) => true
    As(inner, _) | Satisfies(inner, _) =>
      prop_uses_safe_expr(inner, k, lits, false)
    Yield(Some(inner)) => prop_uses_safe_expr(inner, k, lits, false)
    _ => true
  }
}

///|
/// Returns `Some((receiver, literal))` when `(l, r)` is the pair
/// `(e.K, StringLit(lit))` (or symmetric) with `lit` ∈ `lits`.
fn classify_eq_operand(
  l : @ast.TsExpr,
  r : @ast.TsExpr,
  k : String,
  lits : Map[String, Bool],
) -> (@ast.TsExpr, String)? {
  match (l, r) {
    (@ast.TsExpr::PropAccess(recv, name), @ast.TsExpr::StringLit(s)) =>
      if name == k && lits.contains(s) {
        Some((recv, s))
      } else {
        None
      }
    (@ast.TsExpr::StringLit(s), @ast.TsExpr::PropAccess(recv, name)) =>
      if name == k && lits.contains(s) {
        Some((recv, s))
      } else {
        None
      }
    _ => None
  }
}

///|
fn check_object_literals_safe(
  block : @ast.TsBlock,
  k : String,
  literals : Array[String],
) -> Bool {
  let lit_set : Map[String, Bool] = {}
  for s in literals {
    lit_set[s] = true
  }
  for s in block.stmts {
    if !object_literals_safe_stmt(s, k, lit_set) {
      return false
    }
  }
  true
}

///|
fn object_literals_safe_stmt(
  stmt : @ast.TsStmt,
  k : String,
  lits : Map[String, Bool],
) -> Bool {
  match stmt {
    Var(_, _, e)
    | Let(_, _, e)
    | Const(_, _, e)
    | Expr(e)
    | Assign(_, e)
    | CompoundAssign(_, _, e)
    | Throw(e) => object_literals_safe_expr(e, k, lits)
    Return(Some(e)) => object_literals_safe_expr(e, k, lits)
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => true
    IndexAssign(t, idx, v) =>
      object_literals_safe_expr(t, k, lits) &&
      object_literals_safe_expr(idx, k, lits) &&
      object_literals_safe_expr(v, k, lits)
    PropAssign(t, _, v) =>
      object_literals_safe_expr(t, k, lits) &&
      object_literals_safe_expr(v, k, lits)
    If(c, t, e) => {
      if !object_literals_safe_expr(c, k, lits) {
        return false
      }
      for s in t.stmts {
        if !object_literals_safe_stmt(s, k, lits) {
          return false
        }
      }
      match e {
        Some(b) =>
          for s in b.stmts {
            if !object_literals_safe_stmt(s, k, lits) {
              return false
            }
          }
        None => ()
      }
      true
    }
    While(c, body) | DoWhile(c, body) | With(c, body) => {
      if !object_literals_safe_expr(c, k, lits) {
        return false
      }
      for s in body.stmts {
        if !object_literals_safe_stmt(s, k, lits) {
          return false
        }
      }
      true
    }
    For(init, cond, update, body) => {
      let init_ok = match init {
        Some(s) => object_literals_safe_stmt(s, k, lits)
        None => true
      }
      if !init_ok {
        return false
      }
      let cond_ok = match cond {
        Some(e) => object_literals_safe_expr(e, k, lits)
        None => true
      }
      if !cond_ok {
        return false
      }
      let upd_ok = match update {
        Some(s) => object_literals_safe_stmt(s, k, lits)
        None => true
      }
      if !upd_ok {
        return false
      }
      for s in body.stmts {
        if !object_literals_safe_stmt(s, k, lits) {
          return false
        }
      }
      true
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      if !object_literals_safe_expr(iter, k, lits) {
        return false
      }
      for s in body.stmts {
        if !object_literals_safe_stmt(s, k, lits) {
          return false
        }
      }
      true
    }
    Switch(e, cases) => {
      if !object_literals_safe_expr(e, k, lits) {
        return false
      }
      for c in cases {
        match c.test_expr {
          Some(te) =>
            if !object_literals_safe_expr(te, k, lits) {
              return false
            }
          None => ()
        }
        for s in c.body.stmts {
          if !object_literals_safe_stmt(s, k, lits) {
            return false
          }
        }
      }
      true
    }
    Try(b, _, cb, fb) => {
      for s in b.stmts {
        if !object_literals_safe_stmt(s, k, lits) {
          return false
        }
      }
      let cb_ok = match cb {
        Some(blk) => {
          for s in blk.stmts {
            if !object_literals_safe_stmt(s, k, lits) {
              return false
            }
          }
          true
        }
        None => true
      }
      if !cb_ok {
        return false
      }
      match fb {
        Some(blk) => {
          for s in blk.stmts {
            if !object_literals_safe_stmt(s, k, lits) {
              return false
            }
          }
          true
        }
        None => true
      }
    }
    Label(_, inner) => object_literals_safe_stmt(inner, k, lits)
    Block(b) =>
      for s in b.stmts {
        if !object_literals_safe_stmt(s, k, lits) {
          return false
        }
      } nobreak {
        true
      }
    NativeClassStmt(decl, ctor) => {
      match ctor {
        Some(f) =>
          for s in f.body.stmts {
            if !object_literals_safe_stmt(s, k, lits) {
              return false
            }
          }
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) =>
            for s in b.stmts {
              if !object_literals_safe_stmt(s, k, lits) {
                return false
              }
            }
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        if !object_literals_safe_expr(sf.1, k, lits) {
          return false
        }
      }
      true
    }
  }
}

///|
fn object_literals_safe_expr(
  expr : @ast.TsExpr,
  k : String,
  lits : Map[String, Bool],
) -> Bool {
  match expr {
    ObjectLit(entries) => {
      for ent in entries {
        if ent.0 == k {
          // Must be a string literal in the union's set.
          match ent.1 {
            StringLit(s) => if !lits.contains(s) { return false }
            // Existing int form is idempotent.
            IntLit(_) | NumberLit(_) => ()
            _ => return false
          }
        }
        if !object_literals_safe_expr(ent.1, k, lits) {
          return false
        }
      }
      true
    }
    BinOp(_, l, r) | Seq(l, r) =>
      object_literals_safe_expr(l, k, lits) &&
      object_literals_safe_expr(r, k, lits)
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | TypeArgs(_, inner)
    | YieldStar(inner) => object_literals_safe_expr(inner, k, lits)
    Cond(c, t, e) =>
      object_literals_safe_expr(c, k, lits) &&
      object_literals_safe_expr(t, k, lits) &&
      object_literals_safe_expr(e, k, lits)
    PropAccess(recv, _) => object_literals_safe_expr(recv, k, lits)
    IndexAccess(recv, idx) =>
      object_literals_safe_expr(recv, k, lits) &&
      object_literals_safe_expr(idx, k, lits)
    Call(_, args) | New(_, args) => {
      for a in args {
        if !object_literals_safe_expr(a, k, lits) {
          return false
        }
      }
      true
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      if !object_literals_safe_expr(callee, k, lits) {
        return false
      }
      for a in args {
        if !object_literals_safe_expr(a, k, lits) {
          return false
        }
      }
      true
    }
    MethodCall(recv, _, args) => {
      if !object_literals_safe_expr(recv, k, lits) {
        return false
      }
      for a in args {
        if !object_literals_safe_expr(a, k, lits) {
          return false
        }
      }
      true
    }
    ArrayLit(items) => {
      for i in items {
        if !object_literals_safe_expr(i, k, lits) {
          return false
        }
      }
      true
    }
    ComputedProp(kx, v) =>
      object_literals_safe_expr(kx, k, lits) &&
      object_literals_safe_expr(v, k, lits)
    AssignExpr(_, v) | AssignPattern(_, v) | PropAssignExpr(_, _, v) =>
      object_literals_safe_expr(v, k, lits)
    CompoundAssignExpr(t, _, v) =>
      object_literals_safe_expr(t, k, lits) &&
      object_literals_safe_expr(v, k, lits)
    IndexAssignExpr(recv, idx, v) =>
      object_literals_safe_expr(recv, k, lits) &&
      object_literals_safe_expr(idx, k, lits) &&
      object_literals_safe_expr(v, k, lits)
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => object_literals_safe_expr(e, k, lits)
        ArrowBlock(b) => {
          for s in b.stmts {
            if !object_literals_safe_stmt(s, k, lits) {
              return false
            }
          }
          true
        }
      }
    FuncExpr(f) =>
      for s in f.body.stmts {
        if !object_literals_safe_stmt(s, k, lits) {
          return false
        }
      } nobreak {
        true
      }
    DynamicImport(spec, opts) => {
      if !object_literals_safe_expr(spec, k, lits) {
        return false
      }
      match opts {
        Some(o) => object_literals_safe_expr(o, k, lits)
        None => true
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      if !object_literals_safe_expr(tag, k, lits) {
        return false
      }
      for e in exprs {
        if !object_literals_safe_expr(e, k, lits) {
          return false
        }
      }
      true
    }
    TemplateLiteral(_, exprs) => {
      for e in exprs {
        if !object_literals_safe_expr(e, k, lits) {
          return false
        }
      }
      true
    }
    As(inner, _) | Satisfies(inner, _) =>
      object_literals_safe_expr(inner, k, lits)
    Yield(Some(inner)) => object_literals_safe_expr(inner, k, lits)
    _ => true
  }
}

// -- Step 4: rewrite --------------------------------------------------

///|
fn tag_rewrite_stmt(
  stmt : @ast.TsStmt,
  table : Map[String, Map[String, Int]],
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) => Var(b, t, tag_rewrite_expr(e, table))
    Let(b, t, e) => Let(b, t, tag_rewrite_expr(e, table))
    Const(b, t, e) => Const(b, t, tag_rewrite_expr(e, table))
    Assign(n, e) => Assign(n, tag_rewrite_expr(e, table))
    CompoundAssign(n, op, e) =>
      CompoundAssign(n, op, tag_rewrite_expr(e, table))
    IndexAssign(t, idx, v) =>
      IndexAssign(
        tag_rewrite_expr(t, table),
        tag_rewrite_expr(idx, table),
        tag_rewrite_expr(v, table),
      )
    PropAssign(t, p, v) =>
      PropAssign(tag_rewrite_expr(t, table), p, tag_rewrite_expr(v, table))
    Expr(e) => Expr(tag_rewrite_expr(e, table))
    Return(Some(e)) => Return(Some(tag_rewrite_expr(e, table)))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => stmt
    Throw(e) => Throw(tag_rewrite_expr(e, table))
    If(c, t, e) =>
      If(
        tag_rewrite_expr(c, table),
        tag_rewrite_block_inner(t, table),
        match e {
          Some(b) => Some(tag_rewrite_block_inner(b, table))
          None => None
        },
      )
    While(c, body) =>
      While(tag_rewrite_expr(c, table), tag_rewrite_block_inner(body, table))
    DoWhile(c, body) =>
      DoWhile(tag_rewrite_expr(c, table), tag_rewrite_block_inner(body, table))
    With(c, body) =>
      With(tag_rewrite_expr(c, table), tag_rewrite_block_inner(body, table))
    For(init, cond, update, body) =>
      For(
        match init {
          Some(s) => Some(tag_rewrite_stmt(s, table))
          None => None
        },
        match cond {
          Some(e) => Some(tag_rewrite_expr(e, table))
          None => None
        },
        match update {
          Some(s) => Some(tag_rewrite_stmt(s, table))
          None => None
        },
        tag_rewrite_block_inner(body, table),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(
        k,
        b,
        t,
        tag_rewrite_expr(iter, table),
        tag_rewrite_block_inner(body, table),
      )
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(
        k,
        b,
        t,
        tag_rewrite_expr(iter, table),
        tag_rewrite_block_inner(body, table),
      )
    ForIn(k, b, t, iter, body) =>
      ForIn(
        k,
        b,
        t,
        tag_rewrite_expr(iter, table),
        tag_rewrite_block_inner(body, table),
      )
    Switch(e, cases) => {
      // Identify the K (if any) being switched on. For each
      // `case "lit":` whose K is in the table, rewrite to
      // `case <id>:`.
      let switched_on : String? = match e {
        PropAccess(_, name) =>
          if table.contains(name) {
            Some(name)
          } else {
            None
          }
        IndexAccess(_, @ast.TsExpr::StringLit(name)) =>
          if table.contains(name) {
            Some(name)
          } else {
            None
          }
        _ => None
      }
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        let new_test = match (switched_on, c.test_expr) {
          (Some(k), Some(@ast.TsExpr::StringLit(s))) =>
            match table.get(k) {
              Some(id_map) =>
                match id_map.get(s) {
                  Some(id) => Some(@ast.TsExpr::IntLit(id))
                  None => Some(@ast.TsExpr::StringLit(s))
                }
              None => Some(@ast.TsExpr::StringLit(s))
            }
          (_, Some(te)) => Some(tag_rewrite_expr(te, table))
          (_, None) => None
        }
        new_cases.push({
          test_expr: new_test,
          body: tag_rewrite_block_inner(c.body, table),
        })
      }
      Switch(tag_rewrite_expr(e, table), new_cases)
    }
    Try(b, bnd, cb, fb) =>
      Try(
        tag_rewrite_block_inner(b, table),
        bnd,
        match cb {
          Some(blk) => Some(tag_rewrite_block_inner(blk, table))
          None => None
        },
        match fb {
          Some(blk) => Some(tag_rewrite_block_inner(blk, table))
          None => None
        },
      )
    Label(name, inner) => Label(name, tag_rewrite_stmt(inner, table))
    Block(b) => Block(tag_rewrite_block_inner(b, table))
    NativeClassStmt(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: tag_rewrite_block_inner(f.body, table) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(tag_rewrite_block_inner(b, table))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, tag_rewrite_expr(sf.1, table)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(tag_rewrite_expr(b, table))
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
fn tag_rewrite_block_inner(
  block : @ast.TsBlock,
  table : Map[String, Map[String, Int]],
) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(tag_rewrite_stmt(s, table))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn tag_rewrite_expr(
  expr : @ast.TsExpr,
  table : Map[String, Map[String, Int]],
) -> @ast.TsExpr {
  match expr {
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        let new_val = match (table.get(ent.0), ent.1) {
          (Some(id_map), @ast.TsExpr::StringLit(s)) =>
            match id_map.get(s) {
              Some(id) => @ast.TsExpr::IntLit(id)
              None => tag_rewrite_expr(ent.1, table)
            }
          _ => tag_rewrite_expr(ent.1, table)
        }
        new_entries.push((ent.0, new_val))
      }
      ObjectLit(new_entries)
    }
    BinOp(op, l, r) => {
      // Comparison form `e.K === "lit"` (or symmetric) — rewrite the
      // literal to the corresponding int.
      let is_eq_op = match op {
        BinEq | BinNe | AbstractEq | AbstractNe => true
        _ => false
      }
      if is_eq_op {
        match try_rewrite_eq(l, r, table) {
          Some((nl, nr)) => return BinOp(op, nl, nr)
          None => ()
        }
      }
      BinOp(op, tag_rewrite_expr(l, table), tag_rewrite_expr(r, table))
    }
    UnaryOp(op, inner) => UnaryOp(op, tag_rewrite_expr(inner, table))
    Cond(c, t, e) =>
      Cond(
        tag_rewrite_expr(c, table),
        tag_rewrite_expr(t, table),
        tag_rewrite_expr(e, table),
      )
    PropAccess(recv, p) => PropAccess(tag_rewrite_expr(recv, table), p)
    IndexAccess(recv, idx) =>
      IndexAccess(tag_rewrite_expr(recv, table), tag_rewrite_expr(idx, table))
    Call(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(tag_rewrite_expr(a, table))
      }
      Call(name, new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(tag_rewrite_expr(a, table))
      }
      CallExpr(tag_rewrite_expr(callee, table), new_args)
    }
    New(n, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(tag_rewrite_expr(a, table))
      }
      New(n, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(tag_rewrite_expr(a, table))
      }
      NewExpr(tag_rewrite_expr(callee, table), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(tag_rewrite_expr(a, table))
      }
      MethodCall(tag_rewrite_expr(recv, table), m, new_args)
    }
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(tag_rewrite_expr(i, table))
      }
      ArrayLit(new_items)
    }
    Spread(inner) => Spread(tag_rewrite_expr(inner, table))
    Yield(Some(inner)) => Yield(Some(tag_rewrite_expr(inner, table)))
    YieldStar(inner) => YieldStar(tag_rewrite_expr(inner, table))
    Await(inner) => Await(tag_rewrite_expr(inner, table))
    Seq(a, b) => Seq(tag_rewrite_expr(a, table), tag_rewrite_expr(b, table))
    AssignExpr(n, v) => AssignExpr(n, tag_rewrite_expr(v, table))
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(
        tag_rewrite_expr(t, table),
        op,
        tag_rewrite_expr(v, table),
      )
    AssignPattern(b, v) => AssignPattern(b, tag_rewrite_expr(v, table))
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(
        tag_rewrite_expr(recv, table),
        p,
        tag_rewrite_expr(v, table),
      )
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        tag_rewrite_expr(recv, table),
        tag_rewrite_expr(idx, table),
        tag_rewrite_expr(v, table),
      )
    ComputedProp(k, v) =>
      ComputedProp(tag_rewrite_expr(k, table), tag_rewrite_expr(v, table))
    ArrowFunc(params, ret, body, is_async) => {
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(tag_rewrite_expr(e, table))
        ArrowBlock(b) =>
          @ast.TsArrowBody::ArrowBlock(tag_rewrite_block_inner(b, table))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) =>
      FuncExpr({ ..f, body: tag_rewrite_block_inner(f.body, table) })
    DynamicImport(spec, opts) =>
      DynamicImport(
        tag_rewrite_expr(spec, table),
        match opts {
          Some(o) => Some(tag_rewrite_expr(o, table))
          None => None
        },
      )
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(tag_rewrite_expr(e, table))
      }
      TaggedTemplate(tag_rewrite_expr(tag, table), raw, cooked, new_exprs)
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(tag_rewrite_expr(e, table))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(tag_rewrite_expr(inner, table), ty)
    Satisfies(inner, ty) => Satisfies(tag_rewrite_expr(inner, table), ty)
    NonNull(inner) => NonNull(tag_rewrite_expr(inner, table))
    TypeArgs(tys, inner) => TypeArgs(tys, tag_rewrite_expr(inner, table))
    OptionalChain(inner) => OptionalChain(tag_rewrite_expr(inner, table))
    PureCall(inner) => PureCall(tag_rewrite_expr(inner, table))
    NativeClassExpr(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: tag_rewrite_block_inner(f.body, table) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(tag_rewrite_block_inner(b, table))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, tag_rewrite_expr(sf.1, table)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(tag_rewrite_expr(b, table))
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
fn try_rewrite_eq(
  l : @ast.TsExpr,
  r : @ast.TsExpr,
  table : Map[String, Map[String, Int]],
) -> (@ast.TsExpr, @ast.TsExpr)? {
  match (l, r) {
    (@ast.TsExpr::PropAccess(recv, name), @ast.TsExpr::StringLit(s)) =>
      match table.get(name) {
        Some(id_map) =>
          match id_map.get(s) {
            Some(id) =>
              Some(
                (
                  PropAccess(tag_rewrite_expr(recv, table), name),
                  @ast.TsExpr::IntLit(id),
                ),
              )
            None => None
          }
        None => None
      }
    (@ast.TsExpr::StringLit(s), @ast.TsExpr::PropAccess(recv, name)) =>
      match table.get(name) {
        Some(id_map) =>
          match id_map.get(s) {
            Some(id) =>
              Some(
                (
                  @ast.TsExpr::IntLit(id),
                  PropAccess(tag_rewrite_expr(recv, table), name),
                ),
              )
            None => None
          }
        None => None
      }
    _ => None
  }
}

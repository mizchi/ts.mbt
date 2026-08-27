// Type-driven safety analysis for property mangling.
//
// `--mangle-properties` is normally an opt-in "I know what I'm
// doing" mode because the mangler can't prove that renaming a
// property won't break some caller. The runtime heuristic
// (`mangler_builtin_reserved_properties`) is a static list of
// names known to live on JS / DOM / React / Node built-ins; it's
// best-effort, not provable.
//
// This pass adds a second source of reservations that IS
// provable: every property name accessed on a receiver that's
// known to escape the bundle. Concretely:
//
//   - External imports (bare specifiers we couldn't resolve, or
//     ones the caller explicitly marked `--external`) introduce
//     bindings whose property surface is determined by the
//     consuming package's ABI. We don't own those names.
//   - The bundle's own `export` declarations escape too — any
//     downstream consumer can read the bundle's emitted exports
//     by name. (We don't currently emit exports from the merged
//     block, so this branch is dormant.)
//   - JSON.stringify / Object.keys / `for-in` style reflection
//     on a value preserves property names verbatim. Conservative
//     analysis: any prop on a value passed to such a builtin is
//     reserved.
//
// The output is a list of names to add to the mangler's
// `reserved_properties` set. The point isn't to shrink output
// any further — without this list mangling already runs — but to
// upgrade `--mangle-properties` from "risky" to "type-checked",
// which is what the project's checker is supposed to unlock.

///|
/// Compute the set of property names that escape the bundle and
/// therefore can't be safely renamed.
///
/// `external_bindings` lists the LOCAL names introduced by
/// external (bare-spec) imports — e.g. `import { useState } from
/// "react"` contributes `useState`. The pass walks `block` and
/// adds any property name accessed on those bindings (or on a
/// known reflection sink like `JSON.stringify`) to the reserve
/// list.
pub fn collect_externally_visible_props(
  block : @ast.TsBlock,
  external_bindings : Map[String, Bool],
  type_env? : Map[String, @ast.TsType] = {},
) -> Array[String] {
  // A merge over `escape_breakdown`, which computes the same reserved
  // set in pieces and keeps the reason for each. Deliberately not a
  // second implementation: `--explain-mangle` has to describe the
  // decision this function makes, not a re-derivation of it that can
  // drift.
  let b = escape_breakdown(block, external_bindings, type_env~)
  let reserved : Map[String, Bool] = {}
  for
    group in [
      b.external_chain,
      b.sink_observability,
      b.sink_literal,
      b.host_shaped,
      b.value_tree,
      b.in_probe,
    ] {
    for k in group {
      // Internal mtsc markers (`__private_brand__N__X`, `__super_proto`,
      // `__brand__`) are synthesised private — no external consumer can
      // reference them by their desugared names, so they stay manglable
      // even when the containing object is transitively exported.
      // `sorted_names` has already dropped them.
      reserved[k] = true
    }
  }
  let out : Array[String] = []
  for k in reserved.keys() {
    out.push(k)
  }
  out
}

///|
/// Names the block references but never declares, in any scope. Such a
/// name can only come from the host — an ambient global from a `.d.ts`,
/// a runtime built-in, a script-tag global — so every property read on
/// it belongs to somebody else's ABI and must not be renamed.
///
/// The symbol graph supplies "declared anywhere" (it records every
/// binding in every scope) and the reference walk supplies "mentioned
/// anywhere". A name that some inner scope happens to declare is
/// treated as internal even if another scope reads it as a global; that
/// is the one imprecision here, and the built-in reserved list already
/// covers the real runtime globals.
pub fn undeclared_referenced_names(block : @ast.TsBlock) -> Map[String, Bool] {
  let graph = build_symbol_graph(block, {})
  let declared : Map[String, Bool] = {}
  for sym in graph.symbols {
    declared[sym.name] = true
  }
  let referenced : Map[String, Bool] = {}
  collect_var_refs_in_block(block, referenced)
  let out : Map[String, Bool] = {}
  for name in referenced.keys() {
    if !declared.contains(name) && !is_dynamically_bound_name(name) {
      out[name] = true
    }
  }
  out
}

///|
/// Property names spelled by a string on the left of an `in`.
///
/// Uses the export-surface pass's whole-block expression visitor, which
/// already descends into nested function bodies, so this needs no walk of
/// its own.
fn collect_in_probe_names_block(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  surface_visit_exprs_block(block, e => {
    match e {
      @ast.TsExpr::BinOp(In, @ast.TsExpr::StringLit(k), _) => out[k] = true
      _ => ()
    }
  })
}

///|
/// Names that are never "provided by the host" even though no
/// declaration binds them. `this` is the important one: it is bound by
/// the call, so `this.field` inside a bundle-internal method is an
/// internal access, and treating it as external would reserve the
/// property surface of every class and object literal in the bundle.
///
/// The exception this accepts: a callback handed to an external API can
/// have `this` bound to a foreign object (`external.on("x", function ()
/// { this.foo })`). That receiver's names would then be reserved only if
/// something else in the analysis reaches them.
fn is_dynamically_bound_name(name : String) -> Bool {
  name == "this" || name == "super" || name == "arguments"
}

///|
/// Does this binding hold an object literal we can read the first-level
/// keys off directly? Decides whether the one-level `DirectProps` rule
/// has anything to work with.
///
/// A spread or computed entry disqualifies the literal:
/// `{ ...base, wrap: … }` has first-level keys that aren't written here
/// at all, and reading only the ones that are is exactly how `alphaTop`
/// got dropped out from under a `for-in`.
fn has_object_literal_def(sym : Symbol) -> Bool {
  for d in sym.defs {
    match d.init {
      Some(@ast.TsExpr::ObjectLit(entries)) => {
        let mut opaque = false
        for ent in entries {
          if is_opaque_object_key(ent.0) {
            opaque = true
          }
        }
        if !opaque {
          return true
        }
      }
      _ => ()
    }
  }
  false
}

///|
/// Sentinel keys the AST uses for entries that are NOT a literal
/// property name. Object spread arrives as either `("...", Spread(e))`
/// (the JSX-runtime lowering) or `("@@spread:N", e)` (the ordinary
/// parser path), and a computed key `[k]: v` as `("@@computed:N",
/// ComputedProp(k, v))` — see `emit_expr`'s ObjectLit arm, which is
/// where the conventions are consumed.
///
/// Two consequences, and both bit: such a key must never be recorded as
/// a property name to reserve, and its presence means the literal's
/// first-level key set is NOT statically visible, so any rule that
/// reads keys straight off the literal has to decline.
fn is_opaque_object_key(key : String) -> Bool {
  key == "..." || key.has_prefix("@@spread:") || key.has_prefix("@@computed:")
}

///|
fn is_internal_marker_prop(name : String) -> Bool {
  name == "__super_proto" ||
  name == "__brand__" ||
  name.has_prefix("__private_brand__")
}

///|
/// Build the set of local-binding names contributed by external
/// imports. `import { x, y as z } from "lib"` yields `x` and `z`.
/// Default imports contribute their local name; namespace imports
/// (`import * as ns from "lib"`) contribute the namespace name.
pub fn external_import_bindings(
  external_imports : Array[@ast.TsImportDecl],
) -> Map[String, Bool] {
  let out : Map[String, Bool] = {}
  // Implicit globals — names that JS / browser / Node provide for
  // free. Property accesses on these all live in someone else's
  // ABI, so they're external by definition. Without this list,
  // `console.log(...)` would happily get renamed to
  // `console.a(...)` and break.
  for n in known_global_bindings {
    out[n] = true
  }
  for imp in external_imports {
    match imp.default_binding {
      Some(n) => out[n] = true
      None => ()
    }
    match imp.namespace_binding {
      Some(n) => out[n] = true
      None => ()
    }
    for nb in imp.named_bindings {
      // `nb.1` is the local name (potentially renamed via `as`).
      out[nb.1] = true
    }
  }
  out
}

///|
/// Names provided implicitly by the runtime (the JS standard
/// library globals, browser DOM, Node.js core, popular polyfills).
/// Property accesses anchored on one of these escape the bundle
/// through the underlying host implementation.
let known_global_bindings : Array[String] = [
  // JS standard
  "console", "Math", "JSON", "Object", "Array", "String", "Number", "Boolean", "Symbol",
  "BigInt", "Date", "RegExp", "Error", "TypeError", "RangeError", "SyntaxError",
  "ReferenceError", "Promise", "Proxy", "Reflect", "Map", "Set", "WeakMap", "WeakSet",
  "WeakRef", "ArrayBuffer", "SharedArrayBuffer", "DataView", "Int8Array", "Uint8Array",
  "Uint8ClampedArray", "Int16Array", "Uint16Array", "Int32Array", "Uint32Array",
  "Float32Array", "Float64Array", "BigInt64Array", "BigUint64Array", "Intl", "globalThis",
  "Function", "Iterator", "AsyncIterator",
  // Standard free functions / values
   "parseInt", "parseFloat", "isNaN", "isFinite", "encodeURI", "encodeURIComponent",
  "decodeURI", "decodeURIComponent", "NaN", "Infinity", "undefined", "eval", "structuredClone",
  // Async / timers
   "setTimeout", "clearTimeout", "setInterval", "clearInterval", "queueMicrotask",
  "requestAnimationFrame", "cancelAnimationFrame", "setImmediate", "clearImmediate",
  // Browser
   "window", "document", "navigator", "location", "history", "screen", "localStorage",
  "sessionStorage", "indexedDB", "fetch", "Request", "Response", "Headers", "URL",
  "URLSearchParams", "FormData", "Blob", "File", "FileReader", "WebSocket", "EventTarget",
  "Event", "CustomEvent", "MutationObserver", "ResizeObserver", "IntersectionObserver",
  "AbortController", "AbortSignal", "TextEncoder", "TextDecoder", "atob", "btoa",
  "crypto", "performance",
  // Node.js
   "process", "Buffer", "global", "require", "module", "exports", "__dirname", "__filename",
  // React conventions (when present)
   "React",
]

///|
// Map from binding name → the closed set of string literals its
// static TypeScript annotation permits. Only names with exactly one
// symbol-table entry contribute (so a name shadowed across nested
// scopes doesn't surface a stale narrowing at an unrelated site).
// The set powers Phase 2's IndexAssign narrowing: `external.obj[k]`
// where `k: "foo" | "bar"` reserves just `foo` / `bar` instead of
// the wildcard.
fn literal_string_name_set(g : SymbolGraph) -> Map[String, Array[String]] {
  let counts : Map[String, Int] = {}
  for s in g.symbols {
    counts[s.name] = counts.get(s.name).unwrap_or(0) + 1
  }
  let out : Map[String, Array[String]] = {}
  for s in g.symbols {
    if counts.get(s.name).unwrap_or(0) != 1 {
      continue
    }
    match type_literal_string_keys(s.ts_type) {
      Some(keys) => out[s.name] = keys
      None => ()
    }
  }
  out
}

///|
// Pull the closed set of string-literal values out of a TS type.
// `Literal("a")` → `Some(["a"])`; a union of string literals →
// `Some([…])`; anything else (primitive `String_`, mixed unions,
// objects, opaque references) → `None`.
fn type_literal_string_keys(t : @ast.TsType) -> Array[String]? {
  match t {
    Literal(s) => Some([s])
    Union(members) => {
      let out : Array[String] = []
      for m in members {
        match m {
          Literal(s) => if !out.contains(s) { out.push(s) }
          _ => return None
        }
      }
      if out.length() == 0 {
        None
      } else {
        Some(out)
      }
    }
    _ => None
  }
}

///|
/// Reserve for a computed key in a destructuring pattern —
/// `const { [k]: v } = obj`. The pattern reads a property under a name
/// the mangler cannot see, exactly like `obj[k]`, so an unnarrowed key
/// takes the wildcard. Without this the property was renamed AND the
/// dead-property pass dropped its only write, since neither could see
/// a read.
fn reserve_computed_binding_keys(
  b : @ast.TsBinding,
  out : Map[String, Bool],
  numeric_names : Map[String, Bool],
  literal_idx_names : Map[String, Array[String]],
) -> Unit {
  match b {
    Ident(_) | Target(_) => ()
    Array(ab) => {
      for item in ab.items {
        match item {
          Some(elem) =>
            reserve_computed_binding_keys(
              elem.binding,
              out,
              numeric_names,
              literal_idx_names,
            )
          None => ()
        }
      }
      match ab.rest {
        Some(r) =>
          reserve_computed_binding_keys(
            r, out, numeric_names, literal_idx_names,
          )
        None => ()
      }
    }
    Object(ob) =>
      for prop in ob.props {
        match prop.key_expr {
          Some(k) =>
            if !reserve_external_index_keys(
                k, out, numeric_names, literal_idx_names,
              ) {
              out["*"] = true
            }
          None => ()
        }
        reserve_computed_binding_keys(
          prop.binding,
          out,
          numeric_names,
          literal_idx_names,
        )
      }
  }
}

///|
/// True when a computed-index receiver is a plain binding, which is
/// what Phase 3+4 observability can follow. Anything else —
/// `this.f[k]`, `a.b[k]`, `f()[k]`, an element of an array — has no
/// symbol to attach an observability to, so the caller cannot leave
/// the key set to a later phase.
fn untracked_index_receiver(recv : @ast.TsExpr) -> Bool {
  match recv {
    // `this` is not a binding — no symbol, so nothing for Phase 3+4
    // to attach an observability to. `(this as any)[k]` on a class
    // instance reads a member under a name we cannot predict, and
    // treating it as tracked renamed a field the read still wanted.
    // Same for the other pseudo-names that parse as identifiers.
    Var("this") | Var("super") | Var("globalThis") | Var("arguments") => false
    Var(_) => true
    NonNull(inner) | As(inner, _) | Satisfies(inner, _) | PureCall(inner) =>
      untracked_index_receiver(inner)
    _ => false
  }
}

///|
// Phase 2 reservation rule for an external-chain `obj[idx]` site.
// Returns true when the index expression's keys were reserved
// concretely (caller skips the wildcard fallback), false when the
// index remains opaque enough to require `*`.
//
// Recognised narrow forms, in order:
//   1. `StringLit(s)`              — reserve `s`.
//   2. `is_index_numeric_with_names` — numeric key, no string-prop.
//   3. `Var(name)` with name in    — reserve the literal-union keys.
//      the literal-string set
//   4. `As(inner, ty)` whose       — same as (3) on the cast type.
//      cast type is a literal
//      string union
fn reserve_external_index_keys(
  idx : @ast.TsExpr,
  out : Map[String, Bool],
  numeric_names : Map[String, Bool],
  literal_idx_names : Map[String, Array[String]],
) -> Bool {
  match idx {
    StringLit(s) => {
      out[s] = true
      return true
    }
    _ => ()
  }
  if is_index_numeric_with_names(idx, numeric_names) {
    return true
  }
  match idx {
    Var(name) =>
      match literal_idx_names.get(name) {
        Some(keys) => {
          for k in keys {
            out[k] = true
          }
          return true
        }
        None => ()
      }
    As(_, ty) | Satisfies(_, ty) =>
      match type_literal_string_keys(ty) {
        Some(keys) => {
          for k in keys {
            out[k] = true
          }
          return true
        }
        None => ()
      }
    _ => ()
  }
  false
}

///|
/// Walk every statement collecting `PropAccess(Var(name), prop)`
/// where `name` is in `external_bindings`. Also tracks deeper
/// chains: `external.foo.bar.baz` reserves `foo`, `bar`, `baz`
/// because all three accessor segments live on the external API
/// chain.
fn collect_props_on_external_block(
  block : @ast.TsBlock,
  external_bindings : Map[String, Bool],
  out : Map[String, Bool],
  numeric_names : Map[String, Bool],
  literal_idx_names : Map[String, Array[String]],
) -> Unit {
  for s in block.stmts {
    collect_props_on_external_stmt(
      s, external_bindings, out, numeric_names, literal_idx_names,
    )
  }
}

///|
fn collect_props_on_external_stmt(
  stmt : @ast.TsStmt,
  externals : Map[String, Bool],
  out : Map[String, Bool],
  numeric_names : Map[String, Bool],
  literal_idx_names : Map[String, Array[String]],
) -> Unit {
  match stmt {
    Var(b, _, e) | Let(b, _, e) | Const(b, _, e) => {
      reserve_computed_binding_keys(b, out, numeric_names, literal_idx_names)
      collect_props_on_external_expr(
        e, externals, out, numeric_names, literal_idx_names,
      )
    }
    Expr(e) | Throw(e) =>
      collect_props_on_external_expr(
        e, externals, out, numeric_names, literal_idx_names,
      )
    Assign(_, e) | CompoundAssign(_, _, e) =>
      collect_props_on_external_expr(
        e, externals, out, numeric_names, literal_idx_names,
      )
    IndexAssign(t, idx, v) => {
      // A dynamic WRITE takes the wildcard at ANY receiver when the
      // key isn't narrowed — a bare binding included, where a read
      // would have been left to Phase 3+4. The asymmetry is real:
      // Phase 3+4 answers "what does something outside observe on
      // this binding", and a write observes nothing. What it does is
      // install a name the mangler cannot see, while the matching
      // static site is renamed on its own:
      //
      //   const payload: { alphaTop?: number } = {};
      //   function put(k: string, v: number) { payload[k] = v; }
      //   put("alphaTop", 1);
      //   payload.alphaTop        // became `payload.a` — undefined
      if !reserve_external_index_keys(
          idx, out, numeric_names, literal_idx_names,
        ) {
        out["*"] = true
      }
      collect_props_on_external_expr(
        t, externals, out, numeric_names, literal_idx_names,
      )
      collect_props_on_external_expr(
        idx, externals, out, numeric_names, literal_idx_names,
      )
      collect_props_on_external_expr(
        v, externals, out, numeric_names, literal_idx_names,
      )
    }
    PropAssign(t, prop, v) => {
      // `external.foo = ...` reserves `foo`.
      if is_external_chain(t, externals) {
        out[prop] = true
      }
      collect_props_on_external_expr(
        t, externals, out, numeric_names, literal_idx_names,
      )
      collect_props_on_external_expr(
        v, externals, out, numeric_names, literal_idx_names,
      )
    }
    Return(Some(e)) =>
      collect_props_on_external_expr(
        e, externals, out, numeric_names, literal_idx_names,
      )
    If(c, t, e) => {
      collect_props_on_external_expr(
        c, externals, out, numeric_names, literal_idx_names,
      )
      collect_props_on_external_block(
        t, externals, out, numeric_names, literal_idx_names,
      )
      match e {
        Some(b) =>
          collect_props_on_external_block(
            b, externals, out, numeric_names, literal_idx_names,
          )
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) | With(c, b) => {
      collect_props_on_external_expr(
        c, externals, out, numeric_names, literal_idx_names,
      )
      collect_props_on_external_block(
        b, externals, out, numeric_names, literal_idx_names,
      )
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) =>
          collect_props_on_external_stmt(
            s, externals, out, numeric_names, literal_idx_names,
          )
        None => ()
      }
      match cond {
        Some(e) =>
          collect_props_on_external_expr(
            e, externals, out, numeric_names, literal_idx_names,
          )
        None => ()
      }
      match update {
        Some(s) =>
          collect_props_on_external_stmt(
            s, externals, out, numeric_names, literal_idx_names,
          )
        None => ()
      }
      collect_props_on_external_block(
        body, externals, out, numeric_names, literal_idx_names,
      )
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      collect_props_on_external_expr(
        iter, externals, out, numeric_names, literal_idx_names,
      )
      collect_props_on_external_block(
        body, externals, out, numeric_names, literal_idx_names,
      )
    }
    Switch(e, cases) => {
      collect_props_on_external_expr(
        e, externals, out, numeric_names, literal_idx_names,
      )
      for c in cases {
        match c.test_expr {
          Some(te) =>
            collect_props_on_external_expr(
              te, externals, out, numeric_names, literal_idx_names,
            )
          None => ()
        }
        collect_props_on_external_block(
          c.body,
          externals,
          out,
          numeric_names,
          literal_idx_names,
        )
      }
    }
    Try(b, _, cb, fb) => {
      collect_props_on_external_block(
        b, externals, out, numeric_names, literal_idx_names,
      )
      match cb {
        Some(blk) =>
          collect_props_on_external_block(
            blk, externals, out, numeric_names, literal_idx_names,
          )
        None => ()
      }
      match fb {
        Some(blk) =>
          collect_props_on_external_block(
            blk, externals, out, numeric_names, literal_idx_names,
          )
        None => ()
      }
    }
    NativeClassStmt(decl, ctor) => {
      match decl.base_expr {
        Some(b) =>
          collect_props_on_external_expr(
            b, externals, out, numeric_names, literal_idx_names,
          )
        None => ()
      }
      match ctor {
        Some(f) =>
          collect_props_on_external_block(
            f.body,
            externals,
            out,
            numeric_names,
            literal_idx_names,
          )
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) =>
            collect_props_on_external_block(
              b, externals, out, numeric_names, literal_idx_names,
            )
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        collect_props_on_external_expr(
          sf.1,
          externals,
          out,
          numeric_names,
          literal_idx_names,
        )
      }
    }
    Label(_, inner) =>
      collect_props_on_external_stmt(
        inner, externals, out, numeric_names, literal_idx_names,
      )
    Block(b) =>
      collect_props_on_external_block(
        b, externals, out, numeric_names, literal_idx_names,
      )
    _ => ()
  }
}

///|
fn collect_props_on_external_expr(
  expr : @ast.TsExpr,
  externals : Map[String, Bool],
  out : Map[String, Bool],
  numeric_names : Map[String, Bool],
  literal_idx_names : Map[String, Array[String]],
) -> Unit {
  match expr {
    PropAccess(recv, prop) => {
      if is_external_chain(recv, externals) {
        out[prop] = true
      }
      collect_props_on_external_expr(
        recv, externals, out, numeric_names, literal_idx_names,
      )
    }
    MethodCall(recv, m, args) => {
      if is_external_chain(recv, externals) {
        out[m] = true
      }
      collect_props_on_external_expr(
        recv, externals, out, numeric_names, literal_idx_names,
      )
      for a in args {
        collect_props_on_external_expr(
          a, externals, out, numeric_names, literal_idx_names,
        )
      }
    }
    PropAssignExpr(recv, prop, v) => {
      if is_external_chain(recv, externals) {
        out[prop] = true
      }
      collect_props_on_external_expr(
        recv, externals, out, numeric_names, literal_idx_names,
      )
      collect_props_on_external_expr(
        v, externals, out, numeric_names, literal_idx_names,
      )
    }
    Call(_, args) | New(_, args) =>
      for a in args {
        collect_props_on_external_expr(
          a, externals, out, numeric_names, literal_idx_names,
        )
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_props_on_external_expr(
        callee, externals, out, numeric_names, literal_idx_names,
      )
      for a in args {
        collect_props_on_external_expr(
          a, externals, out, numeric_names, literal_idx_names,
        )
      }
    }
    BinOp(_, l, r) => {
      collect_props_on_external_expr(
        l, externals, out, numeric_names, literal_idx_names,
      )
      collect_props_on_external_expr(
        r, externals, out, numeric_names, literal_idx_names,
      )
    }
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | YieldStar(inner)
    | As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    // `/* @__PURE__ */ f(o)` hands `o` to `f` exactly as `f(o)` does;
    // the annotation is a claim about effects, not a scope.
    | PureCall(inner)
    | OptionalChain(inner) =>
      collect_props_on_external_expr(
        inner, externals, out, numeric_names, literal_idx_names,
      )
    Yield(Some(inner)) =>
      collect_props_on_external_expr(
        inner, externals, out, numeric_names, literal_idx_names,
      )
    Cond(c, t, e) => {
      collect_props_on_external_expr(
        c, externals, out, numeric_names, literal_idx_names,
      )
      collect_props_on_external_expr(
        t, externals, out, numeric_names, literal_idx_names,
      )
      collect_props_on_external_expr(
        e, externals, out, numeric_names, literal_idx_names,
      )
    }
    IndexAccess(recv, idx) => {
      // Dynamic indexing falls back to `*` unless the index
      // expression's type pins the key set down (Phase 2
      // narrowing). A LOCAL BINDING receiver is the exception:
      // Phase 3+4 observability tracks it, so only properties that
      // really escape to a sink get reserved and the rest stay
      // drop-eligible.
      //
      // Anything else — an external chain, but equally `this.f[k]`,
      // `a.b[k]`, `f()[k]` — has no binding for Phase 3+4 to track,
      // so the key set is nobody's to bound and the wildcard is the
      // only sound answer:
      //
      //   class R { #rows: Record<string, string> = { seed: "0" };
      //             read(k: string) { return this.#rows[k]; } }
      //   new R().read("seed")
      //
      // Renaming `seed` while `"seed"` stays a string VALUE turns
      // the read into `undefined` — a wrong answer, not a crash.
      if !reserve_external_index_keys(
          idx, out, numeric_names, literal_idx_names,
        ) &&
        (is_external_chain(recv, externals) || !untracked_index_receiver(recv)) {
        out["*"] = true
      }
      collect_props_on_external_expr(
        recv, externals, out, numeric_names, literal_idx_names,
      )
      collect_props_on_external_expr(
        idx, externals, out, numeric_names, literal_idx_names,
      )
    }
    ArrayLit(items) =>
      for it in items {
        collect_props_on_external_expr(
          it, externals, out, numeric_names, literal_idx_names,
        )
      }
    ObjectLit(entries) =>
      for ent in entries {
        collect_props_on_external_expr(
          ent.1,
          externals,
          out,
          numeric_names,
          literal_idx_names,
        )
      }
    ComputedProp(k, v) => {
      collect_props_on_external_expr(
        k, externals, out, numeric_names, literal_idx_names,
      )
      collect_props_on_external_expr(
        v, externals, out, numeric_names, literal_idx_names,
      )
    }
    AssignExpr(_, v) =>
      collect_props_on_external_expr(
        v, externals, out, numeric_names, literal_idx_names,
      )
    CompoundAssignExpr(t, _, v) => {
      collect_props_on_external_expr(
        t, externals, out, numeric_names, literal_idx_names,
      )
      collect_props_on_external_expr(
        v, externals, out, numeric_names, literal_idx_names,
      )
    }
    AssignPattern(_, v) =>
      collect_props_on_external_expr(
        v, externals, out, numeric_names, literal_idx_names,
      )
    IndexAssignExpr(recv, idx, v) => {
      // Same as the statement-level `IndexAssign`: a write under an
      // unnarrowed key takes the wildcard at any receiver.
      if !reserve_external_index_keys(
          idx, out, numeric_names, literal_idx_names,
        ) {
        out["*"] = true
      }
      collect_props_on_external_expr(
        recv, externals, out, numeric_names, literal_idx_names,
      )
      collect_props_on_external_expr(
        idx, externals, out, numeric_names, literal_idx_names,
      )
      collect_props_on_external_expr(
        v, externals, out, numeric_names, literal_idx_names,
      )
    }
    Seq(a, b) => {
      collect_props_on_external_expr(
        a, externals, out, numeric_names, literal_idx_names,
      )
      collect_props_on_external_expr(
        b, externals, out, numeric_names, literal_idx_names,
      )
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) =>
          collect_props_on_external_expr(
            e, externals, out, numeric_names, literal_idx_names,
          )
        ArrowBlock(b) =>
          collect_props_on_external_block(
            b, externals, out, numeric_names, literal_idx_names,
          )
      }
    FuncExpr(f) =>
      collect_props_on_external_block(
        f.body,
        externals,
        out,
        numeric_names,
        literal_idx_names,
      )
    DynamicImport(spec, opts) => {
      collect_props_on_external_expr(
        spec, externals, out, numeric_names, literal_idx_names,
      )
      match opts {
        Some(o) =>
          collect_props_on_external_expr(
            o, externals, out, numeric_names, literal_idx_names,
          )
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      collect_props_on_external_expr(
        tag, externals, out, numeric_names, literal_idx_names,
      )
      for e in exprs {
        collect_props_on_external_expr(
          e, externals, out, numeric_names, literal_idx_names,
        )
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_props_on_external_expr(
          e, externals, out, numeric_names, literal_idx_names,
        )
      }
    NativeClassExpr(decl, ctor) => {
      match decl.base_expr {
        Some(b) =>
          collect_props_on_external_expr(
            b, externals, out, numeric_names, literal_idx_names,
          )
        None => ()
      }
      match ctor {
        Some(f) =>
          collect_props_on_external_block(
            f.body,
            externals,
            out,
            numeric_names,
            literal_idx_names,
          )
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) =>
            collect_props_on_external_block(
              b, externals, out, numeric_names, literal_idx_names,
            )
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        collect_props_on_external_expr(
          sf.1,
          externals,
          out,
          numeric_names,
          literal_idx_names,
        )
      }
    }
    _ => ()
  }
}

///|
/// Does this expression "originate" in an external binding?
/// Recurses through PropAccess / MethodCall chains so
/// `external.foo.bar(...).baz` still classifies as external.
fn is_external_chain(expr : @ast.TsExpr, externals : Map[String, Bool]) -> Bool {
  match expr {
    Var(n) => externals.contains(n)
    PropAccess(recv, _) => is_external_chain(recv, externals)
    MethodCall(recv, _, _) => is_external_chain(recv, externals)
    Call(n, _) => externals.contains(n)
    CallExpr(callee, _) => is_external_chain(callee, externals)
    New(n, _) => externals.contains(n)
    NewExpr(callee, _) => is_external_chain(callee, externals)
    IndexAccess(recv, _) => is_external_chain(recv, externals)
    NonNull(inner)
    | OptionalChain(inner)
    | As(inner, _)
    | Satisfies(inner, _)
    | PureCall(inner) => is_external_chain(inner, externals)
    _ => false
  }
}

///|
/// Look for property names that flow into reflection sinks
/// (`JSON.stringify`, `Object.keys`, `Object.entries`, `Object.values`).
/// Any name that's a property of an object passed to such a
/// builtin escapes the bundle through the resulting JSON string /
/// array, so we conservatively reserve those names.
fn collect_reflection_sinks_block(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    collect_reflection_sinks_stmt(s, out)
  }
}

///|
fn collect_reflection_sinks_stmt(
  stmt : @ast.TsStmt,
  out : Map[String, Bool],
) -> Unit {
  match stmt {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) | Throw(e) =>
      collect_reflection_sinks_expr(e, out)
    Assign(_, e) | CompoundAssign(_, _, e) =>
      collect_reflection_sinks_expr(e, out)
    IndexAssign(t, idx, v) => {
      collect_reflection_sinks_expr(t, out)
      collect_reflection_sinks_expr(idx, out)
      collect_reflection_sinks_expr(v, out)
    }
    PropAssign(t, _, v) => {
      collect_reflection_sinks_expr(t, out)
      collect_reflection_sinks_expr(v, out)
    }
    Return(Some(e)) => collect_reflection_sinks_expr(e, out)
    If(c, t, e) => {
      collect_reflection_sinks_expr(c, out)
      collect_reflection_sinks_block(t, out)
      match e {
        Some(b) => collect_reflection_sinks_block(b, out)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) | With(c, b) => {
      collect_reflection_sinks_expr(c, out)
      collect_reflection_sinks_block(b, out)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => collect_reflection_sinks_stmt(s, out)
        None => ()
      }
      match cond {
        Some(e) => collect_reflection_sinks_expr(e, out)
        None => ()
      }
      match update {
        Some(s) => collect_reflection_sinks_stmt(s, out)
        None => ()
      }
      collect_reflection_sinks_block(body, out)
    }
    ForOf(_, _, _, iter, body) | ForAwaitOf(_, _, _, iter, body) => {
      collect_reflection_sinks_expr(iter, out)
      collect_reflection_sinks_block(body, out)
    }
    ForIn(_, _, _, iter, body) => {
      // `for-in` enumerates property names, so they're observed.
      // Mark every prop on the iter's object literal (best effort).
      match iter {
        Var(_) => out["*"] = true
        _ => ()
      }
      collect_reflection_sinks_expr(iter, out)
      collect_reflection_sinks_block(body, out)
    }
    Switch(e, cases) => {
      collect_reflection_sinks_expr(e, out)
      for c in cases {
        match c.test_expr {
          Some(te) => collect_reflection_sinks_expr(te, out)
          None => ()
        }
        collect_reflection_sinks_block(c.body, out)
      }
    }
    Try(b, _, cb, fb) => {
      collect_reflection_sinks_block(b, out)
      match cb {
        Some(blk) => collect_reflection_sinks_block(blk, out)
        None => ()
      }
      match fb {
        Some(blk) => collect_reflection_sinks_block(blk, out)
        None => ()
      }
    }
    NativeClassStmt(decl, ctor) => {
      match decl.base_expr {
        Some(b) => collect_reflection_sinks_expr(b, out)
        None => ()
      }
      match ctor {
        Some(f) => collect_reflection_sinks_block(f.body, out)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => collect_reflection_sinks_block(b, out)
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        collect_reflection_sinks_expr(sf.1, out)
      }
    }
    Label(_, inner) => collect_reflection_sinks_stmt(inner, out)
    Block(b) => collect_reflection_sinks_block(b, out)
    _ => ()
  }
}

///|
fn collect_reflection_sinks_expr(
  expr : @ast.TsExpr,
  out : Map[String, Bool],
) -> Unit {
  match expr {
    MethodCall(recv, m, args) => {
      // `JSON.stringify(x)` / `Object.keys(x)` / `Object.entries(x)` /
      // `Object.values(x)` / `Object.assign(target, ...)` all
      // expose property names.
      match recv {
        Var(name) =>
          if (name == "JSON" && m == "stringify") ||
            (
              name == "Object" &&
              (
                m == "keys" ||
                m == "entries" ||
                m == "values" ||
                m == "assign" ||
                m == "fromEntries"
              )
            ) {
            // Mark every literal property on the argument object,
            // and use the wildcard for anything dynamic.
            for a in args {
              collect_object_literal_keys(a, out)
              if !arg_is_literal_or_known(a) {
                out["*"] = true
              }
            }
          }
        _ => ()
      }
      collect_reflection_sinks_expr(recv, out)
      for a in args {
        collect_reflection_sinks_expr(a, out)
      }
    }
    BinOp(_, l, r) => {
      collect_reflection_sinks_expr(l, out)
      collect_reflection_sinks_expr(r, out)
    }
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | YieldStar(inner)
    | As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | PureCall(inner)
    | OptionalChain(inner) => collect_reflection_sinks_expr(inner, out)
    Yield(Some(inner)) => collect_reflection_sinks_expr(inner, out)
    Cond(c, t, e) => {
      collect_reflection_sinks_expr(c, out)
      collect_reflection_sinks_expr(t, out)
      collect_reflection_sinks_expr(e, out)
    }
    Call(_, args) | New(_, args) =>
      for a in args {
        collect_reflection_sinks_expr(a, out)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_reflection_sinks_expr(callee, out)
      for a in args {
        collect_reflection_sinks_expr(a, out)
      }
    }
    PropAccess(recv, _) => collect_reflection_sinks_expr(recv, out)
    IndexAccess(recv, idx) => {
      collect_reflection_sinks_expr(recv, out)
      collect_reflection_sinks_expr(idx, out)
    }
    ArrayLit(items) =>
      for it in items {
        collect_reflection_sinks_expr(it, out)
      }
    ObjectLit(entries) =>
      for ent in entries {
        collect_reflection_sinks_expr(ent.1, out)
      }
    ComputedProp(k, v) => {
      collect_reflection_sinks_expr(k, out)
      collect_reflection_sinks_expr(v, out)
    }
    AssignExpr(_, v) => collect_reflection_sinks_expr(v, out)
    CompoundAssignExpr(t, _, v) => {
      collect_reflection_sinks_expr(t, out)
      collect_reflection_sinks_expr(v, out)
    }
    AssignPattern(_, v) => collect_reflection_sinks_expr(v, out)
    PropAssignExpr(recv, _, v) => {
      collect_reflection_sinks_expr(recv, out)
      collect_reflection_sinks_expr(v, out)
    }
    IndexAssignExpr(recv, idx, v) => {
      collect_reflection_sinks_expr(recv, out)
      collect_reflection_sinks_expr(idx, out)
      collect_reflection_sinks_expr(v, out)
    }
    Seq(a, b) => {
      collect_reflection_sinks_expr(a, out)
      collect_reflection_sinks_expr(b, out)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => collect_reflection_sinks_expr(e, out)
        ArrowBlock(b) => collect_reflection_sinks_block(b, out)
      }
    FuncExpr(f) => collect_reflection_sinks_block(f.body, out)
    DynamicImport(spec, opts) => {
      collect_reflection_sinks_expr(spec, out)
      match opts {
        Some(o) => collect_reflection_sinks_expr(o, out)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      collect_reflection_sinks_expr(tag, out)
      for e in exprs {
        collect_reflection_sinks_expr(e, out)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_reflection_sinks_expr(e, out)
      }
    NativeClassExpr(decl, ctor) => {
      match decl.base_expr {
        Some(b) => collect_reflection_sinks_expr(b, out)
        None => ()
      }
      match ctor {
        Some(f) => collect_reflection_sinks_block(f.body, out)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => collect_reflection_sinks_block(b, out)
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        collect_reflection_sinks_expr(sf.1, out)
      }
    }
    _ => ()
  }
}

///|
/// Record every literal key in an object literal so it survives
/// the reflection pass. Used by `JSON.stringify({foo: 1})` etc.
///
/// Recurses through nested literals: `JSON.stringify({ a: { b: 1 } })`
/// serializes `b` just as visibly as `a`, and an array of literals
/// (`send([{ id: 1 }])`) carries its element keys out too.
fn collect_object_literal_keys(
  expr : @ast.TsExpr,
  out : Map[String, Bool],
) -> Unit {
  match expr {
    ObjectLit(entries) =>
      for ent in entries {
        if !is_opaque_object_key(ent.0) {
          out[ent.0] = true
        }
        collect_object_literal_keys(ent.1, out)
      }
    ArrayLit(items) =>
      for it in items {
        collect_object_literal_keys(it, out)
      }
    Spread(inner)
    | As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | TypeArgs(_, inner)
    | PureCall(inner)
    | Await(inner) => collect_object_literal_keys(inner, out)
    Cond(_, t, e) => {
      collect_object_literal_keys(t, out)
      collect_object_literal_keys(e, out)
    }
    _ => ()
  }
}

///|
/// Heuristic for "did we see enough of this argument to mark its
/// keys, vs is it an opaque value we know nothing about"?
/// `ObjectLit`s are transparent; anything else means we have to
/// fall back to the wildcard reservation.
fn arg_is_literal_or_known(expr : @ast.TsExpr) -> Bool {
  match expr {
    ObjectLit(_)
    | ArrayLit(_)
    | StringLit(_)
    | NumberLit(_)
    | IntLit(_)
    | BoolLit(_)
    | NullLit => true
    // `this.__private_brand__N__X` accesses are safe: the mtsc-synthesized
    // private-field maps contain only routing/structural data written by the
    // bundle itself, not arbitrary user-controlled property names.
    PropAccess(@ast.TsExpr::Var("this"), name) =>
      name.has_prefix("__private_brand__")
    _ => false
  }
}

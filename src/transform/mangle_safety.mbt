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
) -> Array[String] {
  let reserved : Map[String, Bool] = {}
  collect_props_on_external_block(block, external_bindings, reserved)
  collect_reflection_sinks_block(block, reserved)
  let out : Array[String] = []
  for k in reserved.keys() {
    out.push(k)
  }
  out
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
  "console", "Math", "JSON", "Object", "Array", "String", "Number",
  "Boolean", "Symbol", "BigInt", "Date", "RegExp", "Error", "TypeError",
  "RangeError", "SyntaxError", "ReferenceError", "Promise", "Proxy",
  "Reflect", "Map", "Set", "WeakMap", "WeakSet", "WeakRef", "ArrayBuffer",
  "SharedArrayBuffer", "DataView", "Int8Array", "Uint8Array",
  "Uint8ClampedArray", "Int16Array", "Uint16Array", "Int32Array",
  "Uint32Array", "Float32Array", "Float64Array", "BigInt64Array",
  "BigUint64Array", "Intl", "globalThis", "Function", "Iterator",
  "AsyncIterator",
  // Standard free functions / values
  "parseInt", "parseFloat", "isNaN", "isFinite", "encodeURI",
  "encodeURIComponent", "decodeURI", "decodeURIComponent", "NaN",
  "Infinity", "undefined", "eval", "structuredClone",
  // Async / timers
  "setTimeout", "clearTimeout", "setInterval", "clearInterval",
  "queueMicrotask", "requestAnimationFrame", "cancelAnimationFrame",
  "setImmediate", "clearImmediate",
  // Browser
  "window", "document", "navigator", "location", "history", "screen",
  "localStorage", "sessionStorage", "indexedDB", "fetch", "Request",
  "Response", "Headers", "URL", "URLSearchParams", "FormData", "Blob",
  "File", "FileReader", "WebSocket", "EventTarget", "Event", "CustomEvent",
  "MutationObserver", "ResizeObserver", "IntersectionObserver",
  "AbortController", "AbortSignal", "TextEncoder", "TextDecoder", "atob",
  "btoa", "crypto", "performance",
  // Node.js
  "process", "Buffer", "global", "require", "module", "exports", "__dirname",
  "__filename",
  // React conventions (when present)
  "React",
]

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
) -> Unit {
  for s in block.stmts {
    collect_props_on_external_stmt(s, external_bindings, out)
  }
}

///|
fn collect_props_on_external_stmt(
  stmt : @ast.TsStmt,
  externals : Map[String, Bool],
  out : Map[String, Bool],
) -> Unit {
  match stmt {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) | Expr(e) | Throw(e) =>
      collect_props_on_external_expr(e, externals, out)
    Assign(_, e) | CompoundAssign(_, _, e) =>
      collect_props_on_external_expr(e, externals, out)
    IndexAssign(t, idx, v) => {
      collect_props_on_external_expr(t, externals, out)
      collect_props_on_external_expr(idx, externals, out)
      collect_props_on_external_expr(v, externals, out)
    }
    PropAssign(t, prop, v) => {
      // `external.foo = ...` reserves `foo`.
      if is_external_chain(t, externals) {
        out[prop] = true
      }
      collect_props_on_external_expr(t, externals, out)
      collect_props_on_external_expr(v, externals, out)
    }
    Return(Some(e)) => collect_props_on_external_expr(e, externals, out)
    If(c, t, e) => {
      collect_props_on_external_expr(c, externals, out)
      collect_props_on_external_block(t, externals, out)
      match e {
        Some(b) => collect_props_on_external_block(b, externals, out)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) | With(c, b) => {
      collect_props_on_external_expr(c, externals, out)
      collect_props_on_external_block(b, externals, out)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => collect_props_on_external_stmt(s, externals, out)
        None => ()
      }
      match cond {
        Some(e) => collect_props_on_external_expr(e, externals, out)
        None => ()
      }
      match update {
        Some(s) => collect_props_on_external_stmt(s, externals, out)
        None => ()
      }
      collect_props_on_external_block(body, externals, out)
    }
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body)
    | ForIn(_, _, _, iter, body) => {
      collect_props_on_external_expr(iter, externals, out)
      collect_props_on_external_block(body, externals, out)
    }
    Switch(e, cases) => {
      collect_props_on_external_expr(e, externals, out)
      for c in cases {
        match c.test_expr {
          Some(te) => collect_props_on_external_expr(te, externals, out)
          None => ()
        }
        collect_props_on_external_block(c.body, externals, out)
      }
    }
    Try(b, _, cb, fb) => {
      collect_props_on_external_block(b, externals, out)
      match cb {
        Some(blk) => collect_props_on_external_block(blk, externals, out)
        None => ()
      }
      match fb {
        Some(blk) => collect_props_on_external_block(blk, externals, out)
        None => ()
      }
    }
    Label(_, inner) => collect_props_on_external_stmt(inner, externals, out)
    Block(b) => collect_props_on_external_block(b, externals, out)
    _ => ()
  }
}

///|
fn collect_props_on_external_expr(
  expr : @ast.TsExpr,
  externals : Map[String, Bool],
  out : Map[String, Bool],
) -> Unit {
  match expr {
    PropAccess(recv, prop) => {
      if is_external_chain(recv, externals) {
        out[prop] = true
      }
      collect_props_on_external_expr(recv, externals, out)
    }
    MethodCall(recv, m, args) => {
      if is_external_chain(recv, externals) {
        out[m] = true
      }
      collect_props_on_external_expr(recv, externals, out)
      for a in args {
        collect_props_on_external_expr(a, externals, out)
      }
    }
    PropAssignExpr(recv, prop, v) => {
      if is_external_chain(recv, externals) {
        out[prop] = true
      }
      collect_props_on_external_expr(recv, externals, out)
      collect_props_on_external_expr(v, externals, out)
    }
    Call(_, args) | New(_, args) => for a in args {
      collect_props_on_external_expr(a, externals, out)
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_props_on_external_expr(callee, externals, out)
      for a in args {
        collect_props_on_external_expr(a, externals, out)
      }
    }
    BinOp(_, l, r) => {
      collect_props_on_external_expr(l, externals, out)
      collect_props_on_external_expr(r, externals, out)
    }
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | YieldStar(inner)
    | As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner) =>
      collect_props_on_external_expr(inner, externals, out)
    Yield(Some(inner)) => collect_props_on_external_expr(inner, externals, out)
    Cond(c, t, e) => {
      collect_props_on_external_expr(c, externals, out)
      collect_props_on_external_expr(t, externals, out)
      collect_props_on_external_expr(e, externals, out)
    }
    IndexAccess(recv, idx) => {
      // Dynamic indexing into an external chain reserves *all*
      // property names — we can't tell which one is read at
      // runtime. Mark the property index expression's string
      // literal (if any), and fall back to a "give up" marker
      // that the mangler also checks.
      if is_external_chain(recv, externals) {
        match idx {
          StringLit(s) => out[s] = true
          _ => out["*"] = true
        }
      }
      collect_props_on_external_expr(recv, externals, out)
      collect_props_on_external_expr(idx, externals, out)
    }
    ArrayLit(items) => for it in items {
      collect_props_on_external_expr(it, externals, out)
    }
    ObjectLit(entries) => for ent in entries {
      collect_props_on_external_expr(ent.1, externals, out)
    }
    ComputedProp(k, v) => {
      collect_props_on_external_expr(k, externals, out)
      collect_props_on_external_expr(v, externals, out)
    }
    AssignExpr(_, v) => collect_props_on_external_expr(v, externals, out)
    CompoundAssignExpr(t, _, v) => {
      collect_props_on_external_expr(t, externals, out)
      collect_props_on_external_expr(v, externals, out)
    }
    AssignPattern(_, v) => collect_props_on_external_expr(v, externals, out)
    IndexAssignExpr(recv, idx, v) => {
      collect_props_on_external_expr(recv, externals, out)
      collect_props_on_external_expr(idx, externals, out)
      collect_props_on_external_expr(v, externals, out)
    }
    Seq(a, b) => {
      collect_props_on_external_expr(a, externals, out)
      collect_props_on_external_expr(b, externals, out)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => collect_props_on_external_expr(e, externals, out)
        ArrowBlock(b) => collect_props_on_external_block(b, externals, out)
      }
    FuncExpr(f) => collect_props_on_external_block(f.body, externals, out)
    DynamicImport(spec, opts) => {
      collect_props_on_external_expr(spec, externals, out)
      match opts {
        Some(o) => collect_props_on_external_expr(o, externals, out)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      collect_props_on_external_expr(tag, externals, out)
      for e in exprs {
        collect_props_on_external_expr(e, externals, out)
      }
    }
    TemplateLiteral(_, exprs) => for e in exprs {
      collect_props_on_external_expr(e, externals, out)
    }
    _ => ()
  }
}

///|
/// Does this expression "originate" in an external binding?
/// Recurses through PropAccess / MethodCall chains so
/// `external.foo.bar(...).baz` still classifies as external.
fn is_external_chain(
  expr : @ast.TsExpr,
  externals : Map[String, Bool],
) -> Bool {
  match expr {
    Var(n) => externals.contains(n)
    PropAccess(recv, _) => is_external_chain(recv, externals)
    MethodCall(recv, _, _) => is_external_chain(recv, externals)
    Call(n, _) => externals.contains(n)
    CallExpr(callee, _) => is_external_chain(callee, externals)
    New(n, _) => externals.contains(n)
    NewExpr(callee, _) => is_external_chain(callee, externals)
    IndexAccess(recv, _) => is_external_chain(recv, externals)
    NonNull(inner) | OptionalChain(inner) | As(inner, _) | Satisfies(inner, _) =>
      is_external_chain(inner, externals)
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
    Assign(_, e) | CompoundAssign(_, _, e) => collect_reflection_sinks_expr(e, out)
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
    ForOf(_, _, _, iter, body)
    | ForAwaitOf(_, _, _, iter, body) => {
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
             (name == "Object" &&
              (m == "keys" || m == "entries" || m == "values" ||
               m == "assign" || m == "fromEntries")) {
            // Mark every literal property on the argument object,
            // and use the wildcard for anything dynamic.
            for a in args {
              collect_object_literal_keys(a, out)
              if not(arg_is_literal_or_known(a)) {
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
    | OptionalChain(inner) =>
      collect_reflection_sinks_expr(inner, out)
    Yield(Some(inner)) => collect_reflection_sinks_expr(inner, out)
    Cond(c, t, e) => {
      collect_reflection_sinks_expr(c, out)
      collect_reflection_sinks_expr(t, out)
      collect_reflection_sinks_expr(e, out)
    }
    Call(_, args) | New(_, args) => for a in args {
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
    ArrayLit(items) => for it in items {
      collect_reflection_sinks_expr(it, out)
    }
    ObjectLit(entries) => for ent in entries {
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
    TemplateLiteral(_, exprs) => for e in exprs {
      collect_reflection_sinks_expr(e, out)
    }
    _ => ()
  }
}

///|
/// Record every literal key in an object literal so it survives
/// the reflection pass. Used by `JSON.stringify({foo: 1})` etc.
fn collect_object_literal_keys(
  expr : @ast.TsExpr,
  out : Map[String, Bool],
) -> Unit {
  match expr {
    ObjectLit(entries) =>
      for ent in entries {
        if ent.0 != "..." {
          out[ent.0] = true
        }
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
    ObjectLit(_) | ArrayLit(_) | StringLit(_) | NumberLit(_) | IntLit(_)
    | BoolLit(_) | NullLit => true
    _ => false
  }
}

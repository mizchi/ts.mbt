// Cross-module linker.
//
// `bundle_modules` concatenates each module's `block.stmts` into one
// combined block before mangle / treeshake / fold runs. That works
// fine when no two modules declare the same name and no module
// re-exports a binding under a different name. Real-world packages
// (Hono in particular) violate both: `hono-base.js` declares
// `var Hono = class _Hono { … }` and `export { Hono as HonoBase }`;
// `hono.js` also declares `var Hono = class extends HonoBase { … }`
// and `import { HonoBase } from "./hono-base"`. Naive concatenation:
//
//   1. Two `var Hono` declarations collide in the same scope — the
//      second one shadows the first.
//   2. `hono.js`'s `class extends HonoBase` references `HonoBase`,
//      which nothing in the combined block declares.
//
// The fix runs in two phases against the resolved-module graph
// before stmts are appended to `combined_stmts`:
//
//   Phase 1 — per-module unique renaming.
//     Walk every module's top-level bindings. The first module's
//     names stay as-is; later modules' bindings that collide get
//     a `$<n>` suffix. Each module's body is rewritten so its own
//     internal references use the (possibly renamed) form.
//
//   Phase 2 — cross-module alias resolution.
//     For each `import { Y as Z } from "./a"` in module B, look up
//     A's `export_specs` for the entry with `export_name == Y`,
//     read its post-rename `local_name`, and substitute references
//     to `Z` in B's body. (Default imports use `export_name ==
//     "default"`.)
//
// The output is still a `Map[path, ModuleNode]` with the same
// shape; only `.block.stmts` and the binding names inside have
// been rewritten. Downstream mangle / treeshake / fold see a graph
// where every top-level binding has a globally unique name and
// every cross-module reference points at the right declaration.

///|
/// Run the link pass over the bundle's resolved module graph. Mutates
/// each `ModuleNode.block` (and recreates it with the rewritten
/// stmts) so subsequent passes see a globally-disambiguated AST.
fn link_module_graph(
  modules : Map[String, ModuleNode],
  order : Array[String],
  external_imports : Array[@ast.TsImportDecl],
) -> Map[String, Map[String, String]] {
  // ---- Phase 1: collect declared names + assign unique renames ----
  // `taken` tracks every name claimed across the bundle so we know
  // when to suffix a later declaration. `rename_per_module[path]`
  // maps a module's original local name to its possibly-renamed
  // global form (entries are only present when a rename actually
  // happened — unchanged names stay implicit).
  let taken : Map[String, Bool] = {}
  // Pre-reserve JS globals so a module's local binding (typically a
  // synthesized namespace object — `export * as Symbol from "…"` →
  // `const Symbol = {…}`) doesn't TDZ-shadow the runtime global at
  // earlier code in the bundle. effect's Schema.js exposes
  // `Symbol`/`Array`/`Number`/etc. namespaces; without this guard
  // those overwrite globals like `Symbol.for(...)`.
  for n in js_runtime_global_names() {
    taken[n] = true
  }
  // External import bindings (`import os from "os"`, `import { x } from
  // "lib"`, `import * as ns from "lib"`) live in the same scope as the
  // merged module top-levels. Without reserving them up front, a
  // bundled module that happens to export a symbol named `os` aliases
  // it as `var os = …` and collides with the import.
  for ext in external_imports {
    match ext.default_binding {
      Some(n) => taken[n] = true
      None => ()
    }
    match ext.namespace_binding {
      Some(n) => taken[n] = true
      None => ()
    }
    for nb in ext.named_bindings {
      taken[nb.1] = true
    }
  }
  let rename_per_module : Map[String, Map[String, String]] = {}
  // namespace_local_renames[path][ns_local] = globally-unique name
  // used for the synthesized `const <unique> = { ... }` binding.
  // Built alongside the regular rename so the namespace synthesis
  // doesn't collide with any other top-level declaration.
  let namespace_local_renames : Map[String, Map[String, String]] = {}
  let mut suffix_counter = 0
  for path in order {
    let m = match modules.get(path) {
      Some(node) => node
      None => continue
    }
    let module_renames : Map[String, String] = {}
    let names = collect_top_level_decl_names(m.block)
    for name in names {
      if not(taken.contains(name)) {
        taken[name] = true
      } else {
        // Collision — invent a unique form.
        let renamed = mint_unique_name(name, taken, suffix_counter)
        suffix_counter = suffix_counter + 1
        taken[renamed] = true
        module_renames[name] = renamed
      }
    }
    // Reserve a unique name for every `import * as ns` namespace
    // local. The synthesized `const <ns> = {...}` decl uses this
    // name so it never clashes with another module's bindings.
    let ns_locals : Map[String, String] = {}
    for imp in m.import_decls {
      if imp.type_only || imp.side_effect_only {
        continue
      }
      match imp.namespace_binding {
        Some(ns_local) => {
          let final_name = if not(taken.contains(ns_local)) {
            taken[ns_local] = true
            ns_local
          } else {
            let renamed = mint_unique_name(ns_local, taken, suffix_counter)
            suffix_counter = suffix_counter + 1
            taken[renamed] = true
            renamed
          }
          ns_locals[ns_local] = final_name
        }
        None => ()
      }
    }
    // `export * as ns from "./X"` re-exports a namespace object. The
    // exporting module needs a real top-level `const ns = {...}`
    // binding so a downstream `import { ns }` (named-binding form)
    // can resolve to a value. Reserve the name here just like the
    // direct namespace-import case so phase-3 synthesis has a
    // collision-free local to bind to.
    for re in m.reexport_specs {
      if re.type_only {
        continue
      }
      match re.kind {
        @ast.TsReExportKind::Namespace(ns_local) =>
          if not(ns_locals.contains(ns_local)) {
            let final_name = if not(taken.contains(ns_local)) {
              taken[ns_local] = true
              ns_local
            } else {
              let renamed = mint_unique_name(ns_local, taken, suffix_counter)
              suffix_counter = suffix_counter + 1
              taken[renamed] = true
              renamed
            }
            ns_locals[ns_local] = final_name
          }
        _ => ()
      }
    }
    namespace_local_renames[path] = ns_locals
    rename_per_module[path] = module_renames
  }
  // ---- Phase 2: build per-module import substitution maps ----
  // `import_subs[path][local_alias_in_importer] = renamed_export_in_exporter`.
  // Walked AFTER phase 1 so we read the post-rename target name.
  // `namespace_subs_per_module[path][ns_local][exported_name] =
  // resolved_local_in_bundle` is the parallel table for `import *
  // as ns from "./a"` patterns. It's consumed in Phase 3 by a
  // dedicated walker that rewrites `ns.X` / `ns["X"]` / `ns.X(...)`
  // into a bare reference.
  let import_subs : Map[String, Map[String, String]] = {}
  let namespace_subs_per_module : Map[String, Map[String, Map[String, String]]] = {}
  // CJS property-access substitutions: for named imports from CJS-wrapped modules
  // that have no export_specs, substitute `localAlias` with `cjsVar.importedName`.
  // `cjs_prop_subs_per_module[path] = [(localAlias, cjsVar, importedName)]`
  let cjs_prop_subs_per_module : Map[String, Array[(String, String, String)]] = {}
  for path in order {
    let m = match modules.get(path) {
      Some(node) => node
      None => continue
    }
    let subs : Map[String, String] = {}
    let namespace_subs : Map[String, Map[String, String]] = {}
    let cjs_prop_subs : Array[(String, String, String)] = []
    for imp in m.import_decls {
      if imp.type_only || imp.side_effect_only {
        continue
      }
      // Resolve specifier → absolute path → exporting module.
      let dep_path = match m.resolved_imports.get(imp.module_spec) {
        Some(p) => p
        None => continue
      }
      let dep = match modules.get(dep_path) {
        Some(node) => node
        None => continue
      }
      // Default import: `import X from "./a"` → A's "default" export.
      match imp.default_binding {
        Some(local_alias) =>
          match
            resolve_export(
              modules, rename_per_module, namespace_local_renames, dep_path, "default",
            ) {
            Some(resolved) =>
              if resolved != local_alias {
                subs[local_alias] = resolved
              }
            None => ()
          }
        None => ()
      }
      // Named imports: `import { Y as Z }`.
      for nb in imp.named_bindings {
        let imported_name = nb.0
        let local_alias = nb.1
        match
          resolve_export(
            modules, rename_per_module, namespace_local_renames, dep_path, imported_name,
          ) {
          Some(resolved) =>
            if resolved != local_alias {
              subs[local_alias] = resolved
            }
          None =>
            // Module has no ESM export_specs. Fall back to CJS property access:
            // substitute `localAlias` → `cjsVar.importedName` at runtime.
            match dep.cjs_exports_var {
              Some(cjs_var) => {
                let actual_cjs_var = rename_per_module
                  .get(dep_path)
                  .unwrap_or({})
                  .get(cjs_var)
                  .unwrap_or(cjs_var)
                cjs_prop_subs.push((local_alias, actual_cjs_var, imported_name))
              }
              None => ()
            }
        }
      }
      // Namespace import: `import * as ns from "./a"`. Collect the
      // dependency's full export surface and build a property table
      // `ns.X -> resolved_local_in_bundle`. The Phase 3 walker uses
      // it to rewrite `PropAccess(Var(ns), X)` / `IndexAccess(Var(ns),
      // StringLit(X))` / `MethodCall(Var(ns), X, args)` into a plain
      // `Var(resolved_local)`. Bare references to `ns` itself (the
      // namespace escaping into a non-member position) are left alone
      // — those still ReferenceError, but the error points at the
      // actual escape site instead of the first member access.
      match imp.namespace_binding {
        Some(ns_local) => {
          let props : Map[String, String] = {}
          for spec in dep.export_specs {
            match
              resolve_export(
                modules,
                rename_per_module,
                namespace_local_renames,
                dep_path,
                spec.export_name,
              ) {
              Some(resolved) => props[spec.export_name] = resolved
              None => ()
            }
          }
          // `export * from "./b"` re-exports also flow through the
          // namespace. The exporter's `resolve_export` handles the
          // walk, but we need to enumerate the names available via
          // the wildcard re-export. Walk the dep's `reexport_specs`
          // for `All` kinds and merge their export surfaces in.
          enumerate_wildcard_reexports(
            modules,
            rename_per_module,
            namespace_local_renames,
            dep_path,
            props,
            {},
          )
          if not(props.is_empty()) {
            namespace_subs[ns_local] = props
          }
        }
        None => ()
      }
    }
    // `export * as ns from "./X"` mirrors the `import * as ns` path:
    // every named export of `X` (plus its wildcard re-exports) flows
    // into a synthesized namespace object that this module exports
    // as `ns`. Populate `namespace_subs` so the phase-3 synthesizer
    // emits `const ns = {...}` and downstream `import { ns }` can
    // resolve via the regular named-export path.
    for re in m.reexport_specs {
      if re.type_only {
        continue
      }
      let ns_local = match re.kind {
        @ast.TsReExportKind::Namespace(n) => n
        _ => continue
      }
      let dep_path = match m.resolved_imports.get(re.module_spec) {
        Some(p) => p
        None => continue
      }
      let dep = match modules.get(dep_path) {
        Some(node) => node
        None => continue
      }
      let props : Map[String, String] = {}
      for spec in dep.export_specs {
        match
          resolve_export(
            modules,
            rename_per_module,
            namespace_local_renames,
            dep_path,
            spec.export_name,
          ) {
          Some(resolved) => props[spec.export_name] = resolved
          None => ()
        }
      }
      enumerate_wildcard_reexports(
        modules,
        rename_per_module,
        namespace_local_renames,
        dep_path,
        props,
        {},
      )
      // Always record even when empty — keeps phase-3 synthesizer
      // in sync with the export-resolution path that treats the name
      // as "exists in this module".
      namespace_subs[ns_local] = props
    }
    import_subs[path] = subs
    namespace_subs_per_module[path] = namespace_subs
    if not(cjs_prop_subs.is_empty()) {
      cjs_prop_subs_per_module[path] = cjs_prop_subs
    }
  }
  // ---- Phase 3: apply substitution maps to each module's body ----
  // The walker takes both the flat rename map (local renames +
  // named-import alias substitution) and the namespace-access map.
  // Namespace patterns get rewritten BEFORE the rename lookup
  // applies, so `ns.X` becomes `Var(resolved)` directly.
  for path in order {
    let m = match modules.get(path) {
      Some(node) => node
      None => continue
    }
    let ns_subs = namespace_subs_per_module.get(path).unwrap_or({})
    let ns_locals = namespace_local_renames.get(path).unwrap_or({})
    let combined_map : Map[String, String] = {}
    let renames = rename_per_module.get(path).unwrap_or({})
    for entry in renames {
      combined_map[entry.0] = entry.1
    }
    let subs = import_subs.get(path).unwrap_or({})
    for entry in subs {
      combined_map[entry.0] = entry.1
    }
    // Rename in-body references to the namespace local to the
    // synthesized binding's globally-unique form.
    for entry in ns_locals {
      if entry.0 != entry.1 {
        combined_map[entry.0] = entry.1
      }
    }
    let has_cjs_subs = cjs_prop_subs_per_module.contains(path)
    if combined_map.is_empty() && ns_subs.is_empty() && not(has_cjs_subs) {
      continue
    }
    // Detect `ns.X -> resolved` substitutions whose target `resolved`
    // collides with a name declared LOCALLY in this module (anywhere
    // — including nested function bodies). The classic case is
    // `const isObject = util.isObject;` inside a function: naive
    // rewriting produces `const isObject = isObject;` which dies
    // with a TDZ ReferenceError. For each such namespace, drop the
    // colliding `(name -> resolved)` entries from the substitution
    // map (so `ns.name` stays un-rewritten) and force the namespace
    // into the escape list further down — the synthesized
    // `const ns = { ... }` binding then resolves the access at
    // runtime.
    let local_decl_names : Map[String, Bool] = {}
    collect_local_decl_names_in_block(m.block, local_decl_names)
    let forced_escape : Map[String, Bool] = {}
    let filtered_ns_subs : Map[String, Map[String, String]] = {}
    for entry in ns_subs {
      let original_ns = entry.0
      let final_ns = ns_locals.get(original_ns).unwrap_or(original_ns)
      let props = entry.1
      let kept : Map[String, String] = {}
      let mut had_collision = false
      for p in props {
        let exp_name = p.0
        let resolved = p.1
        if local_decl_names.contains(resolved) && resolved != final_ns {
          had_collision = true
        } else {
          kept[exp_name] = resolved
        }
      }
      if had_collision {
        forced_escape[original_ns] = true
      }
      filtered_ns_subs[original_ns] = kept
    }
    let new_block = substitute_var_names_in_block(
      m.block,
      combined_map,
      filtered_ns_subs,
    )
    // For each namespace import, also synthesize a real binding
    // `const <ns_local> = { <exp_name>: <resolved_local>, ... };` so
    // patterns the member-access rewrite can't reach — spreads
    // (`...ns`), identifier escapes (`return ns`), computed access
    // with runtime keys — still resolve at runtime.
    //
    // Synthesis is conditional: only emit the binding when the
    // namespace local actually escapes (i.e. still appears as a
    // `Var` after the rewrite pass). The common case is purely
    // `ns.X` access, which the rewrite converts entirely; emitting
    // the binding then would create a top-level reference to
    // every export, which TDZ-breaks circular-import patterns
    // like Zod's `./classic/iso.js` <-> `./classic/schemas.js`.
    let escaping_namespaces : Array[String] = []
    // `export * as ns from "./X"` re-exports always need the
    // synthesized object: downstream modules import `ns` by name and
    // expect a runtime binding to exist. Collect them up-front so
    // they bypass the in-module escape check.
    let reexport_namespaces : Map[String, Bool] = {}
    for re in m.reexport_specs {
      if re.type_only {
        continue
      }
      match re.kind {
        @ast.TsReExportKind::Namespace(ns_name) =>
          reexport_namespaces[ns_name] = true
        _ => ()
      }
    }
    for entry in ns_subs {
      let original_ns = entry.0
      let final_ns = ns_locals.get(original_ns).unwrap_or(original_ns)
      if reexport_namespaces.contains(original_ns) ||
        forced_escape.contains(original_ns) ||
        block_references_var(new_block, final_ns) {
        escaping_namespaces.push(original_ns)
      }
    }
    let synthesized = synthesize_namespace_bindings_for(
      escaping_namespaces, ns_subs, ns_locals,
    )
    // Synthesize `const localAlias = cjsVar.importedName;` for each
    // named import from a CJS-wrapped module (which has no export_specs).
    let cjs_stmts : Array[@ast.TsStmt] = []
    match cjs_prop_subs_per_module.get(path) {
      Some(cjs_subs) =>
        for sub in cjs_subs {
          let local_alias = sub.0
          let cjs_var = sub.1
          let imported_name = sub.2
          cjs_stmts.push(
            @ast.TsStmt::Const(
              @ast.TsBinding::Ident(local_alias),
              @ast.TsType::Any,
              @ast.TsExpr::PropAccess(@ast.TsExpr::Var(cjs_var), imported_name),
            ),
          )
        }
      None => ()
    }
    let all_prepend : Array[@ast.TsStmt] = []
    for s in synthesized {
      all_prepend.push(s)
    }
    for s in cjs_stmts {
      all_prepend.push(s)
    }
    let final_block = if all_prepend.is_empty() {
      new_block
    } else {
      let merged_stmts : Array[@ast.TsStmt] = []
      let merged_positions : Array[Int] = []
      for s in all_prepend {
        merged_stmts.push(s)
        merged_positions.push(-1)
      }
      for s in new_block.stmts {
        merged_stmts.push(s)
      }
      for p in new_block.stmt_positions {
        merged_positions.push(p)
      }
      { stmts: merged_stmts, stmt_positions: merged_positions }
    }
    modules[path] = { ..m, block: final_block }
  }
  rename_per_module
}

///|
/// Emit one `const ns_local = { exp1: resolved1, exp2: resolved2, ... };`
/// per namespace import seen in this module. The resulting binding
/// stands in for the namespace object at runtime, restoring spread /
/// escape / computed-access semantics.
fn synthesize_namespace_bindings_for(
  escaping_namespaces : Array[String],
  ns_subs : Map[String, Map[String, String]],
  ns_locals : Map[String, String],
) -> Array[@ast.TsStmt] {
  let out : Array[@ast.TsStmt] = []
  for ns_local in escaping_namespaces {
    let props = match ns_subs.get(ns_local) {
      Some(p) => p
      None => continue
    }
    let binding_name = ns_locals.get(ns_local).unwrap_or(ns_local)
    let lit_entries : Array[(String, @ast.TsExpr)] = []
    for p in props {
      lit_entries.push((p.0, @ast.TsExpr::Var(p.1)))
    }
    out.push(
      @ast.TsStmt::Const(
        @ast.TsBinding::Ident(binding_name),
        @ast.TsType::Any,
        @ast.TsExpr::ObjectLit(lit_entries),
      ),
    )
  }
  out
}

///|
fn mint_unique_name(
  base : String,
  taken : Map[String, Bool],
  start_counter : Int,
) -> String {
  let mut n = start_counter
  while true {
    let candidate = base + "$" + n.to_string()
    if not(taken.contains(candidate)) {
      return candidate
    }
    n = n + 1
  }
  // Unreachable.
  base + "$"
}

///|
/// Resolve `export_name` to the underlying module's renamed local
/// binding, walking through `export { X } from "./a"` / `export *
/// from "./a"` re-export chains until a concrete declaration is
/// found (or the trail goes cold, in which case `None`).
///
/// `visiting` is the cycle-guard — re-export cycles are illegal in
/// ESM but a guard keeps the linker terminating regardless.
fn resolve_export(
  modules : Map[String, ModuleNode],
  rename_per_module : Map[String, Map[String, String]],
  namespace_local_renames : Map[String, Map[String, String]],
  module_path : String,
  export_name : String,
) -> String? {
  let visited : Map[String, Bool] = {}
  resolve_export_with_visited(
    modules, rename_per_module, namespace_local_renames, module_path, export_name,
    visited,
  )
}

///|
fn resolve_export_with_visited(
  modules : Map[String, ModuleNode],
  rename_per_module : Map[String, Map[String, String]],
  namespace_local_renames : Map[String, Map[String, String]],
  module_path : String,
  export_name : String,
  visited : Map[String, Bool],
) -> String? {
  let key = module_path + "::" + export_name
  if visited.contains(key) {
    return None
  }
  visited[key] = true
  let m = match modules.get(module_path) {
    Some(node) => node
    None => return None
  }
  // 1. Direct named export: `export { X as Y }` (or just `export
  //    { Y }`, which the parser records as `local_name == Y`). The
  //    exported `local` may itself be an imported name (the pattern
  //    `import { X } from "./a"; export { X };` — common in
  //    barrel files), in which case we walk through to the
  //    source module first. Only when the local doesn't trace back
  //    to an import do we read the rename map for this module.
  match find_export_local(m.export_specs, export_name) {
    Some(local) =>
      match find_import_source(m, local) {
        Some(srcref) =>
          return resolve_export_with_visited(
            modules,
            rename_per_module,
            namespace_local_renames,
            srcref.0,
            srcref.1,
            visited,
          )
        None => {
          let renames = rename_per_module.get(module_path).unwrap_or({})
          return Some(renames.get(local).unwrap_or(local))
        }
      }
    None => ()
  }
  // 2. Re-exports: `export { X } from "./a"` and
  //    `export * from "./a"`. Walk through to the source.
  for re in m.reexport_specs {
    if re.type_only {
      continue
    }
    let dep_path = match m.resolved_imports.get(re.module_spec) {
      Some(p) => p
      None => continue
    }
    match re.kind {
      Named(items) =>
        // items is `[(imported, exported)]`.
        for it in items {
          if it.1 == export_name {
            return resolve_export_with_visited(
              modules,
              rename_per_module,
              namespace_local_renames,
              dep_path,
              it.0,
              visited,
            )
          }
        }
      All =>
        // `export * from "./a"` re-exports every NAMED export of A.
        // Try resolving `export_name` from the dependency.
        match
          resolve_export_with_visited(
            modules, rename_per_module, namespace_local_renames, dep_path, export_name,
            visited,
          ) {
          Some(r) => return Some(r)
          None => ()
        }
      Namespace(ns_name) =>
        // `export * as ns from "./a"` exports a namespace object
        // named `ns`. A downstream `import { ns }` resolves to the
        // synthesized `const ns = {...}` binding that phase 3 emits.
        // The reserved local name lives in `namespace_local_renames`
        // (collision-disambiguated in phase 1).
        if ns_name == export_name {
          let ns_locals = namespace_local_renames.get(module_path).unwrap_or({})
          return Some(ns_locals.get(ns_name).unwrap_or(ns_name))
        }
    }
  }
  None
}

///|
/// Recursively enumerate every name reachable through `export * from
/// "./b"` wildcard re-exports starting at `module_path`, populating
/// `props` with `exported_name -> resolved_local`. `visited` guards
/// against re-export cycles.
fn enumerate_wildcard_reexports(
  modules : Map[String, ModuleNode],
  rename_per_module : Map[String, Map[String, String]],
  namespace_local_renames : Map[String, Map[String, String]],
  module_path : String,
  props : Map[String, String],
  visited : Map[String, Bool],
) -> Unit {
  if visited.contains(module_path) {
    return
  }
  visited[module_path] = true
  let m = match modules.get(module_path) {
    Some(node) => node
    None => return
  }
  for re in m.reexport_specs {
    if re.type_only {
      continue
    }
    let dep_path = match m.resolved_imports.get(re.module_spec) {
      Some(p) => p
      None => continue
    }
    match re.kind {
      All => {
        let dep = match modules.get(dep_path) {
          Some(node) => node
          None => continue
        }
        for spec in dep.export_specs {
          if not(props.contains(spec.export_name)) {
            match
              resolve_export(
                modules,
                rename_per_module,
                namespace_local_renames,
                dep_path,
                spec.export_name,
              ) {
              Some(resolved) => props[spec.export_name] = resolved
              None => ()
            }
          }
        }
        enumerate_wildcard_reexports(
          modules, rename_per_module, namespace_local_renames, dep_path, props, visited,
        )
      }
      Named(items) =>
        // `export { X as Y, Z } from "./b"` — each `(imported,
        // exported)` pair becomes one entry in the namespace's
        // export surface.
        for it in items {
          let imported = it.0
          let exported = it.1
          if not(props.contains(exported)) {
            match
              resolve_export(
                modules, rename_per_module, namespace_local_renames, dep_path, imported,
              ) {
              Some(resolved) => props[exported] = resolved
              None => ()
            }
          }
        }
      Namespace(ns_name) =>
        // `export * as ns from "./X"` inside a wildcard chain
        // contributes `ns` as a key. Its value is the synthesized
        // namespace-object binding in the source module.
        if not(props.contains(ns_name)) {
          let dep_ns = namespace_local_renames.get(dep_path).unwrap_or({})
          match dep_ns.get(ns_name) {
            Some(local) => props[ns_name] = local
            None => ()
          }
        }
    }
  }
}

///|
/// If `name` is bound in `m` via one of its `import_decls` (e.g.
/// `import { X as name } from "./a"`), return the
/// `(dep_path, original_imported_name)` so the caller can keep
/// chasing. Returns `None` when the name corresponds to a real
/// local declaration.
fn find_import_source(m : ModuleNode, name : String) -> (String, String)? {
  for imp in m.import_decls {
    if imp.type_only || imp.side_effect_only {
      continue
    }
    let dep_path = match m.resolved_imports.get(imp.module_spec) {
      Some(p) => p
      None => continue
    }
    match imp.default_binding {
      Some(d) => if d == name { return Some((dep_path, "default")) }
      None => ()
    }
    for nb in imp.named_bindings {
      if nb.1 == name {
        return Some((dep_path, nb.0))
      }
    }
  }
  None
}

///|
fn find_export_local(
  specs : Array[@ast.TsExportSpec],
  export_name : String,
) -> String? {
  for s in specs {
    if s.export_name == export_name {
      return Some(s.local_name)
    }
  }
  None
}

///|
/// `ns.X` / `ns["X"]` / `ns.X(args)` patterns: if `recv` is a plain
/// `Var(name)` and `name` is a namespace import alias, look up the
/// property in the namespace's export surface and return the
/// resolved local binding name to substitute in place of the whole
/// member-access expression.
fn resolve_namespace_member(
  recv : @ast.TsExpr,
  prop : String,
  ns : Map[String, Map[String, String]],
) -> String? {
  match recv {
    Var(n) =>
      match ns.get(n) {
        Some(props) => props.get(prop)
        None => None
      }
    _ => None
  }
}

///|
/// Collect every name introduced by a top-level declaration in the
/// block. Covers `let` / `const` / `var` (binding identifier only —
/// destructured top-level decls keep their inner names too) and
/// `NativeClassStmt`.
fn collect_top_level_decl_names(block : @ast.TsBlock) -> Array[String] {
  let out : Array[String] = []
  collect_top_level_decl_names_into(block, out)
  out
}

///|
fn collect_top_level_decl_names_into(
  block : @ast.TsBlock,
  out : Array[String],
) -> Unit {
  for s in block.stmts {
    match s {
      Var(@ast.TsBinding::Ident(n), _, _)
      | Let(@ast.TsBinding::Ident(n), _, _)
      | Const(@ast.TsBinding::Ident(n), _, _) => out.push(n)
      Var(b, _, _) | Let(b, _, _) | Const(b, _, _) =>
        collect_binding_names_into(b, out)
      NativeClassStmt(decl, _) => out.push(decl.name)
      // A chained `var a = 1, b = 2;` is parsed as
      // `Block({stmts: [Var(a, …), Var(b, …)]})`. Without this
      // recursion the link pass only sees `a` (the lifted first
      // declarator) and misses `b`, letting a second module declare
      // a top-level `b` without renaming — `Identifier 'b' has
      // already been declared` at runtime.
      Block(inner) => collect_top_level_decl_names_into(inner, out)
      _ => ()
    }
  }
}

///|
fn collect_binding_names_into(
  binding : @ast.TsBinding,
  out : Array[String],
) -> Unit {
  match binding {
    Ident(n) => out.push(n)
    Array(ab) => {
      for elem in ab.items {
        match elem {
          Some(be) => collect_binding_names_into(be.binding, out)
          None => ()
        }
      }
      match ab.rest {
        Some(r) => collect_binding_names_into(r, out)
        None => ()
      }
    }
    Object(ob) => {
      for p in ob.props {
        collect_binding_names_into(p.binding, out)
      }
      match ob.rest {
        Some(r) => out.push(r)
        None => ()
      }
    }
    Target(_) => ()
  }
}

// -- Substitution with shadow tracking --------------------------------

///|
/// Walk the block, substituting every `Var(name)` reference using
/// `map` UNLESS an inner scope binds the same name (shadowing).
/// LHS occurrences of names in `map` (i.e. the declaration sites
/// being renamed) are also substituted, because the map only
/// contains names whose declarations need to change.
fn substitute_var_names_in_block(
  block : @ast.TsBlock,
  map : Map[String, String],
  ns : Map[String, Map[String, String]],
) -> @ast.TsBlock {
  let new_stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    new_stmts.push(substitute_var_names_in_stmt(s, map, ns))
  }
  { stmts: new_stmts, stmt_positions: block.stmt_positions }
}

///|
/// Per-stmt substitution. Note: top-level shadowing inside nested
/// scopes is rare in practice (and when present, the user's code
/// usually means to shadow). Bundle linker handles only the outer
/// scope — inside function bodies / arrow bodies, the same name
/// substitution applies. This is the same approach mangle's
/// scope-chain rename uses to resolve references.
fn substitute_var_names_in_stmt(
  stmt : @ast.TsStmt,
  map : Map[String, String],
  ns : Map[String, Map[String, String]],
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) =>
      Var(
        link_rename_binding_lhs(b, map),
        t,
        substitute_var_names_in_expr(e, map, ns),
      )
    Let(b, t, e) =>
      Let(
        link_rename_binding_lhs(b, map),
        t,
        substitute_var_names_in_expr(e, map, ns),
      )
    Const(b, t, e) =>
      Const(
        link_rename_binding_lhs(b, map),
        t,
        substitute_var_names_in_expr(e, map, ns),
      )
    Assign(name, e) => {
      let new_name = map.get(name).unwrap_or(name)
      Assign(new_name, substitute_var_names_in_expr(e, map, ns))
    }
    CompoundAssign(name, op, e) => {
      let new_name = map.get(name).unwrap_or(name)
      CompoundAssign(new_name, op, substitute_var_names_in_expr(e, map, ns))
    }
    IndexAssign(t, idx, v) =>
      IndexAssign(
        substitute_var_names_in_expr(t, map, ns),
        substitute_var_names_in_expr(idx, map, ns),
        substitute_var_names_in_expr(v, map, ns),
      )
    PropAssign(t, p, v) =>
      PropAssign(
        substitute_var_names_in_expr(t, map, ns),
        p,
        substitute_var_names_in_expr(v, map, ns),
      )
    Expr(e) => Expr(substitute_var_names_in_expr(e, map, ns))
    Return(Some(e)) => Return(Some(substitute_var_names_in_expr(e, map, ns)))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => stmt
    Throw(e) => Throw(substitute_var_names_in_expr(e, map, ns))
    If(c, t, e) =>
      If(
        substitute_var_names_in_expr(c, map, ns),
        substitute_var_names_in_block(t, map, ns),
        match e {
          Some(b) => Some(substitute_var_names_in_block(b, map, ns))
          None => None
        },
      )
    While(c, body) =>
      While(
        substitute_var_names_in_expr(c, map, ns),
        substitute_var_names_in_block(body, map, ns),
      )
    DoWhile(c, body) =>
      DoWhile(
        substitute_var_names_in_expr(c, map, ns),
        substitute_var_names_in_block(body, map, ns),
      )
    With(c, body) =>
      With(
        substitute_var_names_in_expr(c, map, ns),
        substitute_var_names_in_block(body, map, ns),
      )
    For(init, cond, update, body) =>
      For(
        match init {
          Some(s) => Some(substitute_var_names_in_stmt(s, map, ns))
          None => None
        },
        match cond {
          Some(e) => Some(substitute_var_names_in_expr(e, map, ns))
          None => None
        },
        match update {
          Some(s) => Some(substitute_var_names_in_stmt(s, map, ns))
          None => None
        },
        substitute_var_names_in_block(body, map, ns),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(
        k,
        link_rename_binding_lhs(b, map),
        t,
        substitute_var_names_in_expr(iter, map, ns),
        substitute_var_names_in_block(body, map, ns),
      )
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(
        k,
        link_rename_binding_lhs(b, map),
        t,
        substitute_var_names_in_expr(iter, map, ns),
        substitute_var_names_in_block(body, map, ns),
      )
    ForIn(k, b, t, iter, body) =>
      ForIn(
        k,
        link_rename_binding_lhs(b, map),
        t,
        substitute_var_names_in_expr(iter, map, ns),
        substitute_var_names_in_block(body, map, ns),
      )
    Switch(e, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(te) => Some(substitute_var_names_in_expr(te, map, ns))
            None => None
          },
          body: substitute_var_names_in_block(c.body, map, ns),
        })
      }
      Switch(substitute_var_names_in_expr(e, map, ns), new_cases)
    }
    Try(b, bnd, cb, fb) =>
      Try(
        substitute_var_names_in_block(b, map, ns),
        bnd,
        match cb {
          Some(blk) => Some(substitute_var_names_in_block(blk, map, ns))
          None => None
        },
        match fb {
          Some(blk) => Some(substitute_var_names_in_block(blk, map, ns))
          None => None
        },
      )
    Label(name, inner) =>
      Label(name, substitute_var_names_in_stmt(inner, map, ns))
    Block(b) => Block(substitute_var_names_in_block(b, map, ns))
    NativeClassStmt(decl, ctor_body) => {
      let new_name = map.get(decl.name).unwrap_or(decl.name)
      let new_base_names : Array[String] = []
      for b in decl.base_names {
        new_base_names.push(substitute_dotted_name(b, map, ns))
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for mth in decl.methods {
        let new_body = match mth.body {
          Some(b) => {
            // Method params shadow the linker's substitution map
            // the same way function params do — a parameter named
            // `f` must not be rewritten to a synthesized namespace
            // local that happens to also be called `f`.
            let inner_map = shadow_map_for_method_params(mth.params, map)
            let inner_ns = shadow_ns_for_method_params(mth.params, ns)
            Some(substitute_var_names_in_block(b, inner_map, inner_ns))
          }
          None => None
        }
        let new_key_expr = match mth.key_expr {
          Some(e) => Some(substitute_var_names_in_expr(e, map, ns))
          None => None
        }
        new_methods.push({ ..mth, body: new_body, key_expr: new_key_expr })
      }
      let new_decorators : Array[@ast.TsExpr] = []
      for d in decl.decorators {
        new_decorators.push(substitute_var_names_in_expr(d, map, ns))
      }
      let new_base_expr = match decl.base_expr {
        Some(e) => Some(substitute_var_names_in_expr(e, map, ns))
        None => None
      }
      let new_static_inits : Array[(String, @ast.TsExpr)] = []
      for entry in decl.static_field_inits {
        new_static_inits.push(
          (entry.0, substitute_var_names_in_expr(entry.1, map, ns)),
        )
      }
      let new_decl : @ast.TsClassDecl = {
        ..decl,
        name: new_name,
        base_names: new_base_names,
        base_expr: new_base_expr,
        static_field_inits: new_static_inits,
        methods: new_methods,
        decorators: new_decorators,
      }
      let new_ctor = match ctor_body {
        Some(f) => {
          let inner_map = shadow_map_for_params(f.params, map)
          let inner_ns = shadow_ns_for_params(f.params, ns)
          Some({
            ..f,
            params: substitute_var_names_in_params(f.params, map, ns),
            body: substitute_var_names_in_block(f.body, inner_map, inner_ns),
          })
        }
        None => None
      }
      NativeClassStmt(new_decl, new_ctor)
    }
  }
}

///|
/// Substitute Var references inside an expression. Function /
/// arrow / class bodies recurse — JS lexical scoping captures the
/// renamed binding through the closure.
fn substitute_var_names_in_expr(
  expr : @ast.TsExpr,
  map : Map[String, String],
  ns : Map[String, Map[String, String]],
) -> @ast.TsExpr {
  match expr {
    Var(n) => Var(map.get(n).unwrap_or(n))
    Call(n, args) => {
      let new_n = map.get(n).unwrap_or(n)
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_var_names_in_expr(a, map, ns))
      }
      Call(new_n, new_args)
    }
    New(n, args) => {
      let new_n = map.get(n).unwrap_or(n)
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_var_names_in_expr(a, map, ns))
      }
      New(new_n, new_args)
    }
    AssignExpr(n, v) => {
      let new_n = map.get(n).unwrap_or(n)
      AssignExpr(new_n, substitute_var_names_in_expr(v, map, ns))
    }
    BinOp(op, l, r) =>
      BinOp(
        op,
        substitute_var_names_in_expr(l, map, ns),
        substitute_var_names_in_expr(r, map, ns),
      )
    UnaryOp(op, inner) =>
      UnaryOp(op, substitute_var_names_in_expr(inner, map, ns))
    Cond(c, t, e) =>
      Cond(
        substitute_var_names_in_expr(c, map, ns),
        substitute_var_names_in_expr(t, map, ns),
        substitute_var_names_in_expr(e, map, ns),
      )
    PropAccess(recv, p) =>
      match resolve_namespace_member(recv, p, ns) {
        Some(resolved) => Var(resolved)
        None => PropAccess(substitute_var_names_in_expr(recv, map, ns), p)
      }
    IndexAccess(recv, idx) =>
      match idx {
        StringLit(p) =>
          match resolve_namespace_member(recv, p, ns) {
            Some(resolved) => Var(resolved)
            None =>
              IndexAccess(
                substitute_var_names_in_expr(recv, map, ns),
                substitute_var_names_in_expr(idx, map, ns),
              )
          }
        _ =>
          IndexAccess(
            substitute_var_names_in_expr(recv, map, ns),
            substitute_var_names_in_expr(idx, map, ns),
          )
      }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_var_names_in_expr(a, map, ns))
      }
      CallExpr(substitute_var_names_in_expr(callee, map, ns), new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_var_names_in_expr(a, map, ns))
      }
      NewExpr(substitute_var_names_in_expr(callee, map, ns), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_var_names_in_expr(a, map, ns))
      }
      match resolve_namespace_member(recv, m, ns) {
        Some(resolved) => Call(resolved, new_args)
        None =>
          MethodCall(substitute_var_names_in_expr(recv, map, ns), m, new_args)
      }
    }
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(substitute_var_names_in_expr(i, map, ns))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, substitute_var_names_in_expr(ent.1, map, ns)))
      }
      ObjectLit(new_entries)
    }
    Spread(inner) => Spread(substitute_var_names_in_expr(inner, map, ns))
    Await(inner) => Await(substitute_var_names_in_expr(inner, map, ns))
    NonNull(inner) => NonNull(substitute_var_names_in_expr(inner, map, ns))
    OptionalChain(inner) =>
      OptionalChain(substitute_var_names_in_expr(inner, map, ns))
    PureCall(inner) => PureCall(substitute_var_names_in_expr(inner, map, ns))
    Yield(Some(inner)) =>
      Yield(Some(substitute_var_names_in_expr(inner, map, ns)))
    YieldStar(inner) => YieldStar(substitute_var_names_in_expr(inner, map, ns))
    Seq(a, b) =>
      Seq(
        substitute_var_names_in_expr(a, map, ns),
        substitute_var_names_in_expr(b, map, ns),
      )
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(
        substitute_var_names_in_expr(t, map, ns),
        op,
        substitute_var_names_in_expr(v, map, ns),
      )
    AssignPattern(b, v) =>
      AssignPattern(
        link_rename_binding_lhs(b, map),
        substitute_var_names_in_expr(v, map, ns),
      )
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(
        substitute_var_names_in_expr(recv, map, ns),
        p,
        substitute_var_names_in_expr(v, map, ns),
      )
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        substitute_var_names_in_expr(recv, map, ns),
        substitute_var_names_in_expr(idx, map, ns),
        substitute_var_names_in_expr(v, map, ns),
      )
    ComputedProp(k, v) =>
      ComputedProp(
        substitute_var_names_in_expr(k, map, ns),
        substitute_var_names_in_expr(v, map, ns),
      )
    ArrowFunc(params, ret, body, is_async) => {
      let new_params = substitute_var_names_in_params(params, map, ns)
      let inner_map = shadow_map_for_params(params, map)
      let inner_ns = shadow_ns_for_params(params, ns)
      let new_body = match body {
        ArrowExpr(e) =>
          @ast.TsArrowBody::ArrowExpr(
            substitute_var_names_in_expr(e, inner_map, inner_ns),
          )
        ArrowBlock(b) =>
          @ast.TsArrowBody::ArrowBlock(
            substitute_var_names_in_block(b, inner_map, inner_ns),
          )
      }
      ArrowFunc(new_params, ret, new_body, is_async)
    }
    FuncExpr(f) => {
      let new_params = substitute_var_names_in_params(f.params, map, ns)
      let inner_map = shadow_map_for_params(f.params, map)
      let inner_ns = shadow_ns_for_params(f.params, ns)
      let new_body = substitute_var_names_in_block(f.body, inner_map, inner_ns)
      FuncExpr({ ..f, params: new_params, body: new_body })
    }
    DynamicImport(spec, opts) => {
      let opts_f = match opts {
        Some(o) => Some(substitute_var_names_in_expr(o, map, ns))
        None => None
      }
      DynamicImport(substitute_var_names_in_expr(spec, map, ns), opts_f)
    }
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(substitute_var_names_in_expr(e, map, ns))
      }
      TaggedTemplate(
        substitute_var_names_in_expr(tag, map, ns),
        raw,
        cooked,
        new_exprs,
      )
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(substitute_var_names_in_expr(e, map, ns))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(substitute_var_names_in_expr(inner, map, ns), ty)
    Satisfies(inner, ty) =>
      Satisfies(substitute_var_names_in_expr(inner, map, ns), ty)
    NativeClassExpr(decl, ctor_body) => {
      let new_name = map.get(decl.name).unwrap_or(decl.name)
      let new_base_names : Array[String] = []
      for b in decl.base_names {
        new_base_names.push(substitute_dotted_name(b, map, ns))
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for mth in decl.methods {
        let new_body = match mth.body {
          Some(b) => {
            let inner_map = shadow_map_for_method_params(mth.params, map)
            let inner_ns = shadow_ns_for_method_params(mth.params, ns)
            Some(substitute_var_names_in_block(b, inner_map, inner_ns))
          }
          None => None
        }
        new_methods.push({ ..mth, body: new_body })
      }
      let new_decorators : Array[@ast.TsExpr] = []
      for d in decl.decorators {
        new_decorators.push(substitute_var_names_in_expr(d, map, ns))
      }
      let new_base_expr = match decl.base_expr {
        Some(e) => Some(substitute_var_names_in_expr(e, map, ns))
        None => None
      }
      let new_static_inits : Array[(String, @ast.TsExpr)] = []
      for entry in decl.static_field_inits {
        new_static_inits.push(
          (entry.0, substitute_var_names_in_expr(entry.1, map, ns)),
        )
      }
      let new_decl : @ast.TsClassDecl = {
        ..decl,
        name: new_name,
        base_names: new_base_names,
        base_expr: new_base_expr,
        static_field_inits: new_static_inits,
        methods: new_methods,
        decorators: new_decorators,
      }
      let new_ctor = match ctor_body {
        Some(f) => {
          let inner_map = shadow_map_for_params(f.params, map)
          let inner_ns = shadow_ns_for_params(f.params, ns)
          Some({
            ..f,
            params: substitute_var_names_in_params(f.params, map, ns),
            body: substitute_var_names_in_block(f.body, inner_map, inner_ns),
          })
        }
        None => None
      }
      NativeClassExpr(new_decl, new_ctor)
    }
    _ => expr
  }
}

///|
/// Strip entries from the linker substitution map whose KEY (the
/// original name being rewritten) collides with a name introduced
/// by the given parameter list. Inside a function body the parameter
/// shadows whatever the top-level rename meant, so we must not
/// rewrite a `Var(f)` reference to the namespace alias `f$N` when
/// `f` is the function's own parameter.
fn shadow_map_for_params(
  params : Array[@ast.TsParam],
  map : Map[String, String],
) -> Map[String, String] {
  if map.is_empty() {
    return map
  }
  let names : Map[String, Bool] = {}
  collect_param_binding_names(params, names)
  if names.is_empty() {
    return map
  }
  let out : Map[String, String] = {}
  for entry in map {
    if not(names.contains(entry.0)) {
      out[entry.0] = entry.1
    }
  }
  out
}

///|
/// Same shadowing logic for the namespace-substitution map used by
/// `ns.X` rewrites. If the function parameter is named after a
/// namespace alias (`f`, `map`, …), references inside the body
/// belong to the parameter, not to the namespace's exported member.
fn shadow_ns_for_params(
  params : Array[@ast.TsParam],
  ns : Map[String, Map[String, String]],
) -> Map[String, Map[String, String]] {
  if ns.is_empty() {
    return ns
  }
  let names : Map[String, Bool] = {}
  collect_param_binding_names(params, names)
  if names.is_empty() {
    return ns
  }
  let out : Map[String, Map[String, String]] = {}
  for entry in ns {
    if not(names.contains(entry.0)) {
      out[entry.0] = entry.1
    }
  }
  out
}

///|
fn shadow_map_for_method_params(
  params : Array[(String, @ast.TsType)],
  map : Map[String, String],
) -> Map[String, String] {
  if map.is_empty() {
    return map
  }
  let names : Map[String, Bool] = {}
  for p in params {
    if p.0 != "" {
      names[p.0] = true
    }
  }
  if names.is_empty() {
    return map
  }
  let out : Map[String, String] = {}
  for entry in map {
    if not(names.contains(entry.0)) {
      out[entry.0] = entry.1
    }
  }
  out
}

///|
fn shadow_ns_for_method_params(
  params : Array[(String, @ast.TsType)],
  ns : Map[String, Map[String, String]],
) -> Map[String, Map[String, String]] {
  if ns.is_empty() {
    return ns
  }
  let names : Map[String, Bool] = {}
  for p in params {
    if p.0 != "" {
      names[p.0] = true
    }
  }
  if names.is_empty() {
    return ns
  }
  let out : Map[String, Map[String, String]] = {}
  for entry in ns {
    if not(names.contains(entry.0)) {
      out[entry.0] = entry.1
    }
  }
  out
}

///|
fn collect_param_binding_names(
  params : Array[@ast.TsParam],
  out : Map[String, Bool],
) -> Unit {
  for p in params {
    if p.name != "" {
      out[p.name] = true
    }
    match p.binding {
      Some(b) => {
        let names : Array[String] = []
        collect_binding_names_into(b, names)
        for n in names {
          out[n] = true
        }
      }
      None => ()
    }
  }
}

///|
/// Walk a function parameter list and substitute identifiers inside
/// every default expression — including destructuring defaults
/// (`{a = expr} = {}` / `[x = expr]`). Without this, namespace
/// rewrites like `import * as random` -> `random.uuidv4()` get lost
/// on constructor defaults such as Yjs's
/// `constructor({guid = random.uuidv4(), ...} = {})`.
fn substitute_var_names_in_params(
  params : Array[@ast.TsParam],
  map : Map[String, String],
  ns : Map[String, Map[String, String]],
) -> Array[@ast.TsParam] {
  let out : Array[@ast.TsParam] = []
  for p in params {
    let new_default = match p.default {
      Some(d) => Some(substitute_var_names_in_expr(d, map, ns))
      None => None
    }
    let new_binding = match p.binding {
      Some(b) => Some(substitute_var_names_in_binding(b, map, ns))
      None => None
    }
    out.push({ ..p, default: new_default, binding: new_binding })
  }
  out
}

///|
/// Recursively walk a destructuring binding pattern, substituting
/// inside every default-value expression and inside nested patterns.
/// Binding identifier names themselves are *not* rewritten — those
/// are local bindings introduced by the destructure, not references.
fn substitute_var_names_in_binding(
  binding : @ast.TsBinding,
  map : Map[String, String],
  ns : Map[String, Map[String, String]],
) -> @ast.TsBinding {
  match binding {
    Ident(_) => binding
    Array(ab) => {
      let new_items : Array[@ast.TsBindingElem?] = []
      for elem in ab.items {
        match elem {
          Some(be) => {
            let new_inner = substitute_var_names_in_binding(be.binding, map, ns)
            let new_default = match be.default {
              Some(d) => Some(substitute_var_names_in_expr(d, map, ns))
              None => None
            }
            new_items.push(Some({ binding: new_inner, default: new_default }))
          }
          None => new_items.push(None)
        }
      }
      let new_rest = match ab.rest {
        Some(r) => Some(substitute_var_names_in_binding(r, map, ns))
        None => None
      }
      Array({ items: new_items, rest: new_rest })
    }
    Object(ob) => {
      let new_props : Array[@ast.TsObjectBindingProp] = []
      for prop in ob.props {
        let new_inner = substitute_var_names_in_binding(prop.binding, map, ns)
        let new_default = match prop.default {
          Some(d) => Some(substitute_var_names_in_expr(d, map, ns))
          None => None
        }
        let new_key_expr = match prop.key_expr {
          Some(k) => Some(substitute_var_names_in_expr(k, map, ns))
          None => None
        }
        new_props.push({
          key: prop.key,
          key_expr: new_key_expr,
          binding: new_inner,
          default: new_default,
        })
      }
      Object({ props: new_props, rest: ob.rest })
    }
    Target(e) => Target(substitute_var_names_in_expr(e, map, ns))
  }
}

///|
/// Rename binding LHS occurrences for the destructuring forms. The
/// linker only renames bindings whose name appears in `map` (Phase
/// 1's per-module rename set) — that's always the simple
/// `Ident(name)` shape at top level, but the helper is consistent
/// for callers that pass arbitrary bindings (e.g. for-of loop var).
fn link_rename_binding_lhs(
  binding : @ast.TsBinding,
  map : Map[String, String],
) -> @ast.TsBinding {
  match binding {
    Ident(n) => Ident(map.get(n).unwrap_or(n))
    Array(ab) => {
      let new_items : Array[@ast.TsBindingElem?] = []
      for elem in ab.items {
        match elem {
          Some(be) =>
            new_items.push(
              Some({
                binding: link_rename_binding_lhs(be.binding, map),
                default: be.default,
              }),
            )
          None => new_items.push(None)
        }
      }
      let new_rest = match ab.rest {
        Some(r) => Some(link_rename_binding_lhs(r, map))
        None => None
      }
      Array({ items: new_items, rest: new_rest })
    }
    Object(ob) => {
      let new_props : Array[@ast.TsObjectBindingProp] = []
      for p in ob.props {
        new_props.push({ ..p, binding: link_rename_binding_lhs(p.binding, map) })
      }
      Object({ props: new_props, rest: ob.rest })
    }
    Target(_) => binding
  }
}

///|

///|
/// True when `block` contains a `Var(name)` reference anywhere in any
/// expression position. Used by the namespace synthesis pass to skip
/// emitting a binding when the namespace alias is fully consumed by
/// member-access rewrites (i.e. doesn't escape).

///|
/// Substitute a possibly-dotted base name (e.g. `"Effectable.Class"`)
/// through both the regular rename map and the namespace property
/// table. effect uses `class X extends Effectable.Class {...}` where
/// `Effectable` is a namespace import; `ns_subs["Effectable"]["Class"]`
/// resolves to the synthesized property table entry, and the result
/// emits as the bound local from that table. When the lookup misses
/// at any level the original dotted name flows through unchanged.
fn substitute_dotted_name(
  name : String,
  map : Map[String, String],
  ns : Map[String, Map[String, String]],
) -> String {
  let dot = find_char_index(name, '.')
  if dot < 0 {
    return map.get(name).unwrap_or(name)
  }
  let head = name.substring(start=0, end=dot).to_string()
  let tail = name.substring(start=dot + 1, end=name.length()).to_string()
  // Multi-segment dotted names: only the first lookup matters for
  // namespace resolution; further segments stay as property accesses
  // on the resolved binding. e.g. `A.B.C` with `ns["A"]["B"]` mapping
  // to `B_local` emits as `B_local.C`.
  let after_first_dot = find_char_index(tail, '.')
  let first_prop = if after_first_dot < 0 {
    tail
  } else {
    tail.substring(start=0, end=after_first_dot).to_string()
  }
  match ns.get(head) {
    Some(props) =>
      match props.get(first_prop) {
        Some(resolved) =>
          if after_first_dot < 0 {
            return resolved
          } else {
            return resolved +
              tail
              .substring(start=after_first_dot, end=tail.length())
              .to_string()
          }
        None => ()
      }
    None => ()
  }
  // No namespace match — fall back to renaming the leading identifier
  // through the regular rename map.
  let new_head = map.get(head).unwrap_or(head)
  new_head + "." + tail
}

///|
fn find_char_index(s : String, target : Char) -> Int {
  let mut idx = 0
  for c in s {
    if c == target {
      return idx
    }
    idx = idx + 1
  }
  -1
}

///|
fn block_references_var(block : @ast.TsBlock, name : String) -> Bool {
  let refs : Map[String, Bool] = {}
  collect_var_refs_in_block(block, refs)
  refs.contains(name)
}

///|
/// JS host / standard-library globals that user code routinely
/// references. Pre-seed `taken` with these so the linker's
/// collision-rename machinery treats them as already-occupied —
/// otherwise a module's local `Symbol` / `Array` / `Number` (often
/// synthesized from `export * as Symbol from "…"`) shadows the
/// real global at every earlier use in the bundle.
fn js_runtime_global_names() -> Array[String] {
  [
    // Built-in constructors
    "Object", "Array", "Function", "Boolean", "Number", "String", "Symbol", "BigInt",
    "Date", "RegExp", "Error", "TypeError", "RangeError", "ReferenceError", "SyntaxError",
    "EvalError", "URIError", "Map", "Set", "WeakMap", "WeakSet", "Promise", "Proxy",
    "Reflect", "JSON", "Math", "ArrayBuffer", "SharedArrayBuffer", "DataView", "Int8Array",
    "Uint8Array", "Uint8ClampedArray", "Int16Array", "Uint16Array", "Int32Array",
    "Uint32Array", "Float32Array", "Float64Array", "BigInt64Array", "BigUint64Array",
    "Iterator", "AsyncIterator", "Generator", "AsyncGenerator", "Intl", "URL", "URLSearchParams",
    "WeakRef", "FinalizationRegistry", "AggregateError",
    // Globals
     "globalThis", "undefined", "NaN", "Infinity", "console", "process", "globalThis",
    "self", "window", "document", "navigator", "location", "fetch", "structuredClone",
    "queueMicrotask", "setTimeout", "clearTimeout", "setInterval", "clearInterval",
    "setImmediate", "clearImmediate",
    // Top-level functions
     "parseInt", "parseFloat", "isNaN", "isFinite", "encodeURI", "encodeURIComponent",
    "decodeURI", "decodeURIComponent", "eval",
  ]
}

///|
/// Recursively gather every name introduced by a binding declaration
/// (`let` / `const` / `var` / `function` / `class`) anywhere in the
/// block tree — including nested function bodies, class methods, and
/// control-flow bodies. Used by the namespace rewriter to detect
/// `ns.X -> resolved` substitutions whose target collides with a
/// locally-bound name (e.g. zod's `const isObject = util.isObject;`).
fn collect_local_decl_names_in_block(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    collect_local_decl_names_in_stmt(s, out)
  }
}

///|
fn collect_local_decl_names_in_stmt(
  stmt : @ast.TsStmt,
  out : Map[String, Bool],
) -> Unit {
  match stmt {
    Var(b, _, init) | Let(b, _, init) | Const(b, _, init) => {
      let names : Array[String] = []
      collect_binding_names_into(b, names)
      for n in names {
        out[n] = true
      }
      collect_local_decl_names_in_expr(init, out)
    }
    Expr(e) | Throw(e) => collect_local_decl_names_in_expr(e, out)
    Return(opt) =>
      match opt {
        Some(e) => collect_local_decl_names_in_expr(e, out)
        None => ()
      }
    If(c, t, els) => {
      collect_local_decl_names_in_expr(c, out)
      collect_local_decl_names_in_block(t, out)
      match els {
        Some(b) => collect_local_decl_names_in_block(b, out)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) => {
      collect_local_decl_names_in_expr(c, out)
      collect_local_decl_names_in_block(b, out)
    }
    For(init, cond, update, body) => {
      match init {
        Some(s) => collect_local_decl_names_in_stmt(s, out)
        None => ()
      }
      match cond {
        Some(c) => collect_local_decl_names_in_expr(c, out)
        None => ()
      }
      match update {
        Some(u) => collect_local_decl_names_in_stmt(u, out)
        None => ()
      }
      collect_local_decl_names_in_block(body, out)
    }
    ForOf(_, binding, _, iter, body)
    | ForAwaitOf(_, binding, _, iter, body)
    | ForIn(_, binding, _, iter, body) => {
      let names : Array[String] = []
      collect_binding_names_into(binding, names)
      for n in names {
        out[n] = true
      }
      collect_local_decl_names_in_expr(iter, out)
      collect_local_decl_names_in_block(body, out)
    }
    Try(t, catch_param, catch_body, finally_) => {
      collect_local_decl_names_in_block(t, out)
      match catch_param {
        Some(b) => {
          let names : Array[String] = []
          collect_binding_names_into(b, names)
          for n in names {
            out[n] = true
          }
        }
        None => ()
      }
      match catch_body {
        Some(b) => collect_local_decl_names_in_block(b, out)
        None => ()
      }
      match finally_ {
        Some(b) => collect_local_decl_names_in_block(b, out)
        None => ()
      }
    }
    Switch(scr, cases) => {
      collect_local_decl_names_in_expr(scr, out)
      for c in cases {
        collect_local_decl_names_in_block(c.body, out)
      }
    }
    With(target, body) => {
      collect_local_decl_names_in_expr(target, out)
      collect_local_decl_names_in_block(body, out)
    }
    Block(b) => collect_local_decl_names_in_block(b, out)
    Label(_, inner) => collect_local_decl_names_in_stmt(inner, out)
    Assign(_, v) | CompoundAssign(_, _, v) =>
      collect_local_decl_names_in_expr(v, out)
    IndexAssign(recv, idx, v) => {
      collect_local_decl_names_in_expr(recv, out)
      collect_local_decl_names_in_expr(idx, out)
      collect_local_decl_names_in_expr(v, out)
    }
    PropAssign(recv, _, v) => {
      collect_local_decl_names_in_expr(recv, out)
      collect_local_decl_names_in_expr(v, out)
    }
    NativeClassStmt(decl, ctor_body) => {
      if decl.name != "" {
        out[decl.name] = true
      }
      for mth in decl.methods {
        match mth.body {
          Some(b) => collect_local_decl_names_in_block(b, out)
          None => ()
        }
      }
      match ctor_body {
        Some(f) => collect_local_decl_names_in_block(f.body, out)
        None => ()
      }
    }
    _ => ()
  }
}

///|
fn collect_local_decl_names_in_expr(
  expr : @ast.TsExpr,
  out : Map[String, Bool],
) -> Unit {
  match expr {
    FuncExpr(f) => {
      if f.name != "" {
        out[f.name] = true
      }
      collect_local_decl_names_in_block(f.body, out)
    }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => collect_local_decl_names_in_expr(e, out)
        ArrowBlock(b) => collect_local_decl_names_in_block(b, out)
      }
    Call(_, args) | New(_, args) =>
      for a in args {
        collect_local_decl_names_in_expr(a, out)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_local_decl_names_in_expr(callee, out)
      for a in args {
        collect_local_decl_names_in_expr(a, out)
      }
    }
    MethodCall(recv, _, args) => {
      collect_local_decl_names_in_expr(recv, out)
      for a in args {
        collect_local_decl_names_in_expr(a, out)
      }
    }
    PropAccess(recv, _) => collect_local_decl_names_in_expr(recv, out)
    IndexAccess(recv, idx) => {
      collect_local_decl_names_in_expr(recv, out)
      collect_local_decl_names_in_expr(idx, out)
    }
    AssignExpr(_, v)
    | Await(v)
    | NonNull(v)
    | OptionalChain(v)
    | PureCall(v)
    | YieldStar(v)
    | Spread(v)
    | UnaryOp(_, v) => collect_local_decl_names_in_expr(v, out)
    As(v, _) | Satisfies(v, _) => collect_local_decl_names_in_expr(v, out)
    Yield(opt) =>
      match opt {
        Some(v) => collect_local_decl_names_in_expr(v, out)
        None => ()
      }
    BinOp(_, l, r) | Seq(l, r) => {
      collect_local_decl_names_in_expr(l, out)
      collect_local_decl_names_in_expr(r, out)
    }
    Cond(c, t, els) => {
      collect_local_decl_names_in_expr(c, out)
      collect_local_decl_names_in_expr(t, out)
      collect_local_decl_names_in_expr(els, out)
    }
    CompoundAssignExpr(target, _, v) => {
      collect_local_decl_names_in_expr(target, out)
      collect_local_decl_names_in_expr(v, out)
    }
    AssignPattern(_, v) => collect_local_decl_names_in_expr(v, out)
    PropAssignExpr(recv, _, v) => {
      collect_local_decl_names_in_expr(recv, out)
      collect_local_decl_names_in_expr(v, out)
    }
    IndexAssignExpr(recv, idx, v) => {
      collect_local_decl_names_in_expr(recv, out)
      collect_local_decl_names_in_expr(idx, out)
      collect_local_decl_names_in_expr(v, out)
    }
    ComputedProp(k, v) => {
      collect_local_decl_names_in_expr(k, out)
      collect_local_decl_names_in_expr(v, out)
    }
    ArrayLit(items) =>
      for i in items {
        collect_local_decl_names_in_expr(i, out)
      }
    ObjectLit(entries) =>
      for e in entries {
        collect_local_decl_names_in_expr(e.1, out)
      }
    TaggedTemplate(tag, _, _, exprs) => {
      collect_local_decl_names_in_expr(tag, out)
      for e in exprs {
        collect_local_decl_names_in_expr(e, out)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_local_decl_names_in_expr(e, out)
      }
    DynamicImport(spec, opts) => {
      collect_local_decl_names_in_expr(spec, out)
      match opts {
        Some(o) => collect_local_decl_names_in_expr(o, out)
        None => ()
      }
    }
    NativeClassExpr(decl, ctor_body) => {
      if decl.name != "" {
        out[decl.name] = true
      }
      for mth in decl.methods {
        match mth.body {
          Some(b) => collect_local_decl_names_in_block(b, out)
          None => ()
        }
      }
      match ctor_body {
        Some(f) => collect_local_decl_names_in_block(f.body, out)
        None => ()
      }
    }
    _ => ()
  }
}

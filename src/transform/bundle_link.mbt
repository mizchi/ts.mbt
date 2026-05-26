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
) -> Map[String, Map[String, String]] {
  // ---- Phase 1: collect declared names + assign unique renames ----
  // `taken` tracks every name claimed across the bundle so we know
  // when to suffix a later declaration. `rename_per_module[path]`
  // maps a module's original local name to its possibly-renamed
  // global form (entries are only present when a rename actually
  // happened — unchanged names stay implicit).
  let taken : Map[String, Bool] = {}
  let rename_per_module : Map[String, Map[String, String]] = {}
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
    rename_per_module[path] = module_renames
  }
  // ---- Phase 2: build per-module import substitution maps ----
  // `import_subs[path][local_alias_in_importer] = renamed_export_in_exporter`.
  // Walked AFTER phase 1 so we read the post-rename target name.
  let import_subs : Map[String, Map[String, String]] = {}
  for path in order {
    let m = match modules.get(path) {
      Some(node) => node
      None => continue
    }
    let subs : Map[String, String] = {}
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
          match resolve_export(modules, rename_per_module, dep_path, "default") {
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
        match resolve_export(modules, rename_per_module, dep_path, imported_name) {
          Some(resolved) =>
            if resolved != local_alias {
              subs[local_alias] = resolved
            }
          None => ()
        }
      }
      // Namespace imports are out of scope here — they'd require
      // synthesizing a fresh object literal of the module's
      // exports. Leave the original `ns.x` references alone; if
      // they reach the bundle's free-variable surface, the user
      // sees the same `ReferenceError` as before the linker.
    }
    import_subs[path] = subs
  }
  // ---- Phase 3: apply both substitution maps to each module's body ----
  // The per-module rename and the import-substitution maps are
  // disjoint (local names vs. external alias names), so we merge
  // them into one map and walk the AST once per module.
  for path in order {
    let m = match modules.get(path) {
      Some(node) => node
      None => continue
    }
    let combined_map : Map[String, String] = {}
    let renames = rename_per_module.get(path).unwrap_or({})
    for entry in renames {
      combined_map[entry.0] = entry.1
    }
    let subs = import_subs.get(path).unwrap_or({})
    for entry in subs {
      combined_map[entry.0] = entry.1
    }
    if combined_map.is_empty() {
      continue
    }
    let new_block = substitute_var_names_in_block(m.block, combined_map)
    modules[path] = { ..m, block: new_block }
  }
  rename_per_module
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
  module_path : String,
  export_name : String,
) -> String? {
  let visited : Map[String, Bool] = {}
  resolve_export_with_visited(
    modules,
    rename_per_module,
    module_path,
    export_name,
    visited,
  )
}

///|
fn resolve_export_with_visited(
  modules : Map[String, ModuleNode],
  rename_per_module : Map[String, Map[String, String]],
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
    Some(local) => {
      match find_import_source(m, local) {
        Some(srcref) =>
          return resolve_export_with_visited(
            modules, rename_per_module, srcref.0, srcref.1, visited,
          )
        None => {
          let renames = rename_per_module.get(module_path).unwrap_or({})
          return Some(renames.get(local).unwrap_or(local))
        }
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
      Named(items) => {
        // items is `[(imported, exported)]`.
        for it in items {
          if it.1 == export_name {
            return resolve_export_with_visited(
              modules, rename_per_module, dep_path, it.0, visited,
            )
          }
        }
      }
      All =>
        // `export * from "./a"` re-exports every NAMED export of A.
        // Try resolving `export_name` from the dependency.
        match
          resolve_export_with_visited(
            modules, rename_per_module, dep_path, export_name, visited,
          ) {
          Some(r) => return Some(r)
          None => ()
        }
      Namespace(_) =>
        // `export * as ns from "./a"` exports a namespace object.
        // Out of scope for this linker — the consumer would need to
        // see a synthesized object literal.
        ()
    }
  }
  None
}

///|
/// If `name` is bound in `m` via one of its `import_decls` (e.g.
/// `import { X as name } from "./a"`), return the
/// `(dep_path, original_imported_name)` so the caller can keep
/// chasing. Returns `None` when the name corresponds to a real
/// local declaration.
fn find_import_source(
  m : ModuleNode,
  name : String,
) -> (String, String)? {
  for imp in m.import_decls {
    if imp.type_only || imp.side_effect_only {
      continue
    }
    let dep_path = match m.resolved_imports.get(imp.module_spec) {
      Some(p) => p
      None => continue
    }
    match imp.default_binding {
      Some(d) =>
        if d == name {
          return Some((dep_path, "default"))
        }
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
/// Collect every name introduced by a top-level declaration in the
/// block. Covers `let` / `const` / `var` (binding identifier only —
/// destructured top-level decls keep their inner names too) and
/// `NativeClassStmt`.
fn collect_top_level_decl_names(block : @ast.TsBlock) -> Array[String] {
  let out : Array[String] = []
  for s in block.stmts {
    match s {
      Var(@ast.TsBinding::Ident(n), _, _)
      | Let(@ast.TsBinding::Ident(n), _, _)
      | Const(@ast.TsBinding::Ident(n), _, _) => out.push(n)
      Var(b, _, _) | Let(b, _, _) | Const(b, _, _) =>
        collect_binding_names_into(b, out)
      NativeClassStmt(decl, _) => out.push(decl.name)
      _ => ()
    }
  }
  out
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
) -> @ast.TsBlock {
  let new_stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    new_stmts.push(substitute_var_names_in_stmt(s, map))
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
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) =>
      Var(link_rename_binding_lhs(b, map), t, substitute_var_names_in_expr(e, map))
    Let(b, t, e) =>
      Let(link_rename_binding_lhs(b, map), t, substitute_var_names_in_expr(e, map))
    Const(b, t, e) =>
      Const(link_rename_binding_lhs(b, map), t, substitute_var_names_in_expr(e, map))
    Assign(name, e) => {
      let new_name = map.get(name).unwrap_or(name)
      Assign(new_name, substitute_var_names_in_expr(e, map))
    }
    CompoundAssign(name, op, e) => {
      let new_name = map.get(name).unwrap_or(name)
      CompoundAssign(new_name, op, substitute_var_names_in_expr(e, map))
    }
    IndexAssign(t, idx, v) =>
      IndexAssign(
        substitute_var_names_in_expr(t, map),
        substitute_var_names_in_expr(idx, map),
        substitute_var_names_in_expr(v, map),
      )
    PropAssign(t, p, v) =>
      PropAssign(
        substitute_var_names_in_expr(t, map),
        p,
        substitute_var_names_in_expr(v, map),
      )
    Expr(e) => Expr(substitute_var_names_in_expr(e, map))
    Return(Some(e)) => Return(Some(substitute_var_names_in_expr(e, map)))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => stmt
    Throw(e) => Throw(substitute_var_names_in_expr(e, map))
    If(c, t, e) =>
      If(
        substitute_var_names_in_expr(c, map),
        substitute_var_names_in_block(t, map),
        match e {
          Some(b) => Some(substitute_var_names_in_block(b, map))
          None => None
        },
      )
    While(c, body) =>
      While(
        substitute_var_names_in_expr(c, map),
        substitute_var_names_in_block(body, map),
      )
    DoWhile(c, body) =>
      DoWhile(
        substitute_var_names_in_expr(c, map),
        substitute_var_names_in_block(body, map),
      )
    With(c, body) =>
      With(
        substitute_var_names_in_expr(c, map),
        substitute_var_names_in_block(body, map),
      )
    For(init, cond, update, body) =>
      For(
        match init {
          Some(s) => Some(substitute_var_names_in_stmt(s, map))
          None => None
        },
        match cond {
          Some(e) => Some(substitute_var_names_in_expr(e, map))
          None => None
        },
        match update {
          Some(s) => Some(substitute_var_names_in_stmt(s, map))
          None => None
        },
        substitute_var_names_in_block(body, map),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(
        k,
        link_rename_binding_lhs(b, map),
        t,
        substitute_var_names_in_expr(iter, map),
        substitute_var_names_in_block(body, map),
      )
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(
        k,
        link_rename_binding_lhs(b, map),
        t,
        substitute_var_names_in_expr(iter, map),
        substitute_var_names_in_block(body, map),
      )
    ForIn(k, b, t, iter, body) =>
      ForIn(
        k,
        link_rename_binding_lhs(b, map),
        t,
        substitute_var_names_in_expr(iter, map),
        substitute_var_names_in_block(body, map),
      )
    Switch(e, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(te) => Some(substitute_var_names_in_expr(te, map))
            None => None
          },
          body: substitute_var_names_in_block(c.body, map),
        })
      }
      Switch(substitute_var_names_in_expr(e, map), new_cases)
    }
    Try(b, bnd, cb, fb) =>
      Try(
        substitute_var_names_in_block(b, map),
        bnd,
        match cb {
          Some(blk) => Some(substitute_var_names_in_block(blk, map))
          None => None
        },
        match fb {
          Some(blk) => Some(substitute_var_names_in_block(blk, map))
          None => None
        },
      )
    Label(name, inner) =>
      Label(name, substitute_var_names_in_stmt(inner, map))
    Block(b) => Block(substitute_var_names_in_block(b, map))
    NativeClassStmt(decl, ctor_body) => {
      let new_name = map.get(decl.name).unwrap_or(decl.name)
      let new_base_names : Array[String] = []
      for b in decl.base_names {
        new_base_names.push(map.get(b).unwrap_or(b))
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for mth in decl.methods {
        let new_body = match mth.body {
          Some(b) => Some(substitute_var_names_in_block(b, map))
          None => None
        }
        new_methods.push({ ..mth, body: new_body })
      }
      let new_decorators : Array[@ast.TsExpr] = []
      for d in decl.decorators {
        new_decorators.push(substitute_var_names_in_expr(d, map))
      }
      let new_decl : @ast.TsClassDecl = {
        ..decl,
        name: new_name,
        base_names: new_base_names,
        methods: new_methods,
        decorators: new_decorators,
      }
      let new_ctor = match ctor_body {
        Some(f) =>
          Some({ ..f, body: substitute_var_names_in_block(f.body, map) })
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
) -> @ast.TsExpr {
  match expr {
    Var(n) => Var(map.get(n).unwrap_or(n))
    Call(n, args) => {
      let new_n = map.get(n).unwrap_or(n)
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_var_names_in_expr(a, map))
      }
      Call(new_n, new_args)
    }
    New(n, args) => {
      let new_n = map.get(n).unwrap_or(n)
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_var_names_in_expr(a, map))
      }
      New(new_n, new_args)
    }
    AssignExpr(n, v) => {
      let new_n = map.get(n).unwrap_or(n)
      AssignExpr(new_n, substitute_var_names_in_expr(v, map))
    }
    BinOp(op, l, r) =>
      BinOp(
        op,
        substitute_var_names_in_expr(l, map),
        substitute_var_names_in_expr(r, map),
      )
    UnaryOp(op, inner) =>
      UnaryOp(op, substitute_var_names_in_expr(inner, map))
    Cond(c, t, e) =>
      Cond(
        substitute_var_names_in_expr(c, map),
        substitute_var_names_in_expr(t, map),
        substitute_var_names_in_expr(e, map),
      )
    PropAccess(recv, p) =>
      PropAccess(substitute_var_names_in_expr(recv, map), p)
    IndexAccess(recv, idx) =>
      IndexAccess(
        substitute_var_names_in_expr(recv, map),
        substitute_var_names_in_expr(idx, map),
      )
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_var_names_in_expr(a, map))
      }
      CallExpr(substitute_var_names_in_expr(callee, map), new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_var_names_in_expr(a, map))
      }
      NewExpr(substitute_var_names_in_expr(callee, map), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(substitute_var_names_in_expr(a, map))
      }
      MethodCall(substitute_var_names_in_expr(recv, map), m, new_args)
    }
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(substitute_var_names_in_expr(i, map))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, substitute_var_names_in_expr(ent.1, map)))
      }
      ObjectLit(new_entries)
    }
    Spread(inner) => Spread(substitute_var_names_in_expr(inner, map))
    Await(inner) => Await(substitute_var_names_in_expr(inner, map))
    NonNull(inner) => NonNull(substitute_var_names_in_expr(inner, map))
    OptionalChain(inner) =>
      OptionalChain(substitute_var_names_in_expr(inner, map))
    PureCall(inner) => PureCall(substitute_var_names_in_expr(inner, map))
    Yield(Some(inner)) => Yield(Some(substitute_var_names_in_expr(inner, map)))
    YieldStar(inner) => YieldStar(substitute_var_names_in_expr(inner, map))
    Seq(a, b) =>
      Seq(
        substitute_var_names_in_expr(a, map),
        substitute_var_names_in_expr(b, map),
      )
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(
        substitute_var_names_in_expr(t, map),
        op,
        substitute_var_names_in_expr(v, map),
      )
    AssignPattern(b, v) =>
      AssignPattern(
        link_rename_binding_lhs(b, map),
        substitute_var_names_in_expr(v, map),
      )
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(
        substitute_var_names_in_expr(recv, map),
        p,
        substitute_var_names_in_expr(v, map),
      )
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        substitute_var_names_in_expr(recv, map),
        substitute_var_names_in_expr(idx, map),
        substitute_var_names_in_expr(v, map),
      )
    ComputedProp(k, v) =>
      ComputedProp(
        substitute_var_names_in_expr(k, map),
        substitute_var_names_in_expr(v, map),
      )
    ArrowFunc(params, ret, body, is_async) => {
      let new_body = match body {
        ArrowExpr(e) =>
          @ast.TsArrowBody::ArrowExpr(substitute_var_names_in_expr(e, map))
        ArrowBlock(b) =>
          @ast.TsArrowBody::ArrowBlock(substitute_var_names_in_block(b, map))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => {
      let new_body = substitute_var_names_in_block(f.body, map)
      FuncExpr({ ..f, body: new_body })
    }
    DynamicImport(spec, opts) => {
      let opts_f = match opts {
        Some(o) => Some(substitute_var_names_in_expr(o, map))
        None => None
      }
      DynamicImport(substitute_var_names_in_expr(spec, map), opts_f)
    }
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(substitute_var_names_in_expr(e, map))
      }
      TaggedTemplate(
        substitute_var_names_in_expr(tag, map),
        raw,
        cooked,
        new_exprs,
      )
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(substitute_var_names_in_expr(e, map))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(substitute_var_names_in_expr(inner, map), ty)
    Satisfies(inner, ty) =>
      Satisfies(substitute_var_names_in_expr(inner, map), ty)
    NativeClassExpr(decl, ctor_body) => {
      let new_name = map.get(decl.name).unwrap_or(decl.name)
      let new_base_names : Array[String] = []
      for b in decl.base_names {
        new_base_names.push(map.get(b).unwrap_or(b))
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for mth in decl.methods {
        let new_body = match mth.body {
          Some(b) => Some(substitute_var_names_in_block(b, map))
          None => None
        }
        new_methods.push({ ..mth, body: new_body })
      }
      let new_decorators : Array[@ast.TsExpr] = []
      for d in decl.decorators {
        new_decorators.push(substitute_var_names_in_expr(d, map))
      }
      let new_decl : @ast.TsClassDecl = {
        ..decl,
        name: new_name,
        base_names: new_base_names,
        methods: new_methods,
        decorators: new_decorators,
      }
      let new_ctor = match ctor_body {
        Some(f) =>
          Some({ ..f, body: substitute_var_names_in_block(f.body, map) })
        None => None
      }
      NativeClassExpr(new_decl, new_ctor)
    }
    _ => expr
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

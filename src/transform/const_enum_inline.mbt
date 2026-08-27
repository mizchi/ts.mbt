// `const enum` inlining.
//
// TypeScript's `const enum` semantics: every use site
// (`E.Member`) is replaced by the member's literal value, and
// the enum itself produces no runtime declaration. We collect
// const-enum members across the bundle, then substitute use sites
// throughout the merged block.
//
// Unlike a regular `enum`, the user never sees the value as an
// object — `Object.keys(E)` on a `const enum` is a TS error. So
// dropping the runtime side and inlining everywhere is correct.

///|
/// Build a substitution table from a list of enum decls. Only
/// `is_const` decls (and not `is_declare`) contribute. Each
/// member's value resolves through the same auto-increment +
/// literal-tracking logic as `lower_enum_decl_to_runtime_stmts`.
///
/// The key is `EnumName.MemberName`; the value is the literal
/// expression to substitute at use sites.
pub fn build_const_enum_table(
  enums : Array[@ast.TsEnumDecl],
) -> Map[String, @ast.TsExpr] {
  build_enum_inline_table(enums, include_non_const=false)
}

///|
/// Build the full enum-member → literal substitution table. When
/// `include_non_const` is `true`, regular (non-const) enums whose
/// members all have literal values also contribute. The runtime
/// `var EnumName = {…}` table the parser emits for regular enums
/// stays put — code that does `EnumName[reverseValue]` still
/// works — but member accesses `EnumName.Member` are folded to
/// the literal at use sites, saving a property lookup and a few
/// bytes per occurrence.
///
/// Members with a computed (non-literal) initializer disqualify
/// the whole enum from inlining; mixing literal and computed
/// members is a TS error anyway in the non-const case.
pub fn build_enum_inline_table(
  enums : Array[@ast.TsEnumDecl],
  include_non_const? : Bool = false,
) -> Map[String, @ast.TsExpr] {
  let out : Map[String, @ast.TsExpr] = {}
  for decl in enums {
    if decl.is_declare {
      continue
    }
    if !decl.is_const && !include_non_const {
      continue
    }
    // Non-const enums can carry computed initializers. We can
    // only inline when every member resolves to a literal — bail
    // out otherwise so accesses fall back to runtime lookup.
    if !decl.is_const {
      let mut all_literal = true
      for m in decl.members {
        if m.is_computed {
          all_literal = false
          break
        }
      }
      if !all_literal {
        continue
      }
    }
    let mut next_numeric : Int = 0
    for member_ in decl.members {
      let value_expr : @ast.TsExpr? = match member_.value {
        Some(@ast.TsEnumMemberValue::Number(s)) =>
          try @string.parse_int(s) catch {
            _ =>
              Some(
                @ast.TsExpr::NumberLit(
                  try @string.parse_double(s) catch {
                    _ => 0.0
                  } noraise {
                    d => d
                  },
                ),
              )
          } noraise {
            i => {
              next_numeric = i + 1
              Some(@ast.TsExpr::IntLit(i))
            }
          }
        Some(@ast.TsEnumMemberValue::String(s)) =>
          Some(@ast.TsExpr::StringLit(s))
        Some(@ast.TsEnumMemberValue::BigInt(s)) =>
          Some(@ast.TsExpr::BigIntLit(s))
        Some(@ast.TsEnumMemberValue::Bool(b)) => Some(@ast.TsExpr::BoolLit(b))
        None => {
          let v = next_numeric
          next_numeric = next_numeric + 1
          Some(@ast.TsExpr::IntLit(v))
        }
      }
      match value_expr {
        Some(v) => out[decl.name + "." + member_.name] = v
        None => ()
      }
    }
  }
  out
}

///|
/// Walk `block` substituting every `PropAccess(Var(E), M)` and
/// `IndexAccess(Var(E), StringLit(M))` use whose `E.M` lookup hits
/// the const-enum table. Returns a fresh block.
pub fn inline_const_enums(
  block : @ast.TsBlock,
  table : Map[String, @ast.TsExpr],
) -> @ast.TsBlock {
  if table.is_empty() {
    return block
  }
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(inline_const_enums_stmt(s, table))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn inline_const_enums_stmt(
  stmt : @ast.TsStmt,
  table : Map[String, @ast.TsExpr],
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, e) => Var(b, t, inline_const_enums_expr(e, table))
    Let(b, t, e) => Let(b, t, inline_const_enums_expr(e, table))
    Const(b, t, e) => Const(b, t, inline_const_enums_expr(e, table))
    Assign(n, e) => Assign(n, inline_const_enums_expr(e, table))
    CompoundAssign(n, op, e) =>
      CompoundAssign(n, op, inline_const_enums_expr(e, table))
    IndexAssign(t, idx, v) =>
      IndexAssign(
        inline_const_enums_expr(t, table),
        inline_const_enums_expr(idx, table),
        inline_const_enums_expr(v, table),
      )
    PropAssign(t, prop, v) =>
      PropAssign(
        inline_const_enums_expr(t, table),
        prop,
        inline_const_enums_expr(v, table),
      )
    Expr(e) => Expr(inline_const_enums_expr(e, table))
    Return(Some(e)) => Return(Some(inline_const_enums_expr(e, table)))
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => stmt
    Throw(e) => Throw(inline_const_enums_expr(e, table))
    If(c, t, e) =>
      If(
        inline_const_enums_expr(c, table),
        inline_const_enums_block(t, table),
        match e {
          Some(b) => Some(inline_const_enums_block(b, table))
          None => None
        },
      )
    While(c, body) =>
      While(
        inline_const_enums_expr(c, table),
        inline_const_enums_block(body, table),
      )
    DoWhile(c, body) =>
      DoWhile(
        inline_const_enums_expr(c, table),
        inline_const_enums_block(body, table),
      )
    With(c, body) =>
      With(
        inline_const_enums_expr(c, table),
        inline_const_enums_block(body, table),
      )
    For(init, cond, update, body) =>
      For(
        match init {
          Some(s) => Some(inline_const_enums_stmt(s, table))
          None => None
        },
        match cond {
          Some(e) => Some(inline_const_enums_expr(e, table))
          None => None
        },
        match update {
          Some(s) => Some(inline_const_enums_stmt(s, table))
          None => None
        },
        inline_const_enums_block(body, table),
      )
    ForOf(k, b, t, iter, body) =>
      ForOf(
        k,
        b,
        t,
        inline_const_enums_expr(iter, table),
        inline_const_enums_block(body, table),
      )
    ForAwaitOf(k, b, t, iter, body) =>
      ForAwaitOf(
        k,
        b,
        t,
        inline_const_enums_expr(iter, table),
        inline_const_enums_block(body, table),
      )
    ForIn(k, b, t, iter, body) =>
      ForIn(
        k,
        b,
        t,
        inline_const_enums_expr(iter, table),
        inline_const_enums_block(body, table),
      )
    Switch(e, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(te) => Some(inline_const_enums_expr(te, table))
            None => None
          },
          body: inline_const_enums_block(c.body, table),
        })
      }
      Switch(inline_const_enums_expr(e, table), new_cases)
    }
    Try(b, bnd, cb, fb) =>
      Try(
        inline_const_enums_block(b, table),
        bnd,
        match cb {
          Some(blk) => Some(inline_const_enums_block(blk, table))
          None => None
        },
        match fb {
          Some(blk) => Some(inline_const_enums_block(blk, table))
          None => None
        },
      )
    Label(name, inner) => Label(name, inline_const_enums_stmt(inner, table))
    Block(b) => Block(inline_const_enums_block(b, table))
    NativeClassStmt(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: inline_const_enums_block(f.body, table) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(inline_const_enums_block(b, table))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, inline_const_enums_expr(sf.1, table)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(inline_const_enums_expr(b, table))
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
fn inline_const_enums_block(
  block : @ast.TsBlock,
  table : Map[String, @ast.TsExpr],
) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(inline_const_enums_stmt(s, table))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn inline_const_enums_expr(
  expr : @ast.TsExpr,
  table : Map[String, @ast.TsExpr],
) -> @ast.TsExpr {
  match expr {
    // `import * as K` then `K.ArchType.Array` — a two-level access, so
    // the table carries the namespace-qualified path as its key. The
    // namespace object is synthesized for the module's runtime exports,
    // and a const enum has none, so leaving this to the flattening pass
    // that handles ordinary namespace members drops the reference.
    PropAccess(PropAccess(Var(ns), enum_name), member_) =>
      match table.get(ns + "." + enum_name + "." + member_) {
        Some(v) => v
        None =>
          PropAccess(
            inline_const_enums_expr(
              PropAccess(@ast.TsExpr::Var(ns), enum_name),
              table,
            ),
            member_,
          )
      }
    PropAccess(Var(enum_name), member_) =>
      match table.get(enum_name + "." + member_) {
        Some(v) => v
        None => PropAccess(@ast.TsExpr::Var(enum_name), member_)
      }
    IndexAccess(Var(enum_name), StringLit(member_)) =>
      match table.get(enum_name + "." + member_) {
        Some(v) => v
        None =>
          IndexAccess(
            @ast.TsExpr::Var(enum_name),
            @ast.TsExpr::StringLit(member_),
          )
      }
    PropAccess(recv, name) =>
      PropAccess(inline_const_enums_expr(recv, table), name)
    IndexAccess(recv, idx) =>
      IndexAccess(
        inline_const_enums_expr(recv, table),
        inline_const_enums_expr(idx, table),
      )
    BinOp(op, l, r) =>
      BinOp(
        op,
        inline_const_enums_expr(l, table),
        inline_const_enums_expr(r, table),
      )
    UnaryOp(op, inner) => UnaryOp(op, inline_const_enums_expr(inner, table))
    Cond(c, t, e) =>
      Cond(
        inline_const_enums_expr(c, table),
        inline_const_enums_expr(t, table),
        inline_const_enums_expr(e, table),
      )
    Call(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_const_enums_expr(a, table))
      }
      Call(name, new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_const_enums_expr(a, table))
      }
      CallExpr(inline_const_enums_expr(callee, table), new_args)
    }
    New(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_const_enums_expr(a, table))
      }
      New(name, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_const_enums_expr(a, table))
      }
      NewExpr(inline_const_enums_expr(callee, table), new_args)
    }
    MethodCall(recv, m, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(inline_const_enums_expr(a, table))
      }
      MethodCall(inline_const_enums_expr(recv, table), m, new_args)
    }
    ArrayLit(items) => {
      let new_items : Array[@ast.TsExpr] = []
      for i in items {
        new_items.push(inline_const_enums_expr(i, table))
      }
      ArrayLit(new_items)
    }
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, inline_const_enums_expr(ent.1, table)))
      }
      ObjectLit(new_entries)
    }
    ComputedProp(k, v) =>
      ComputedProp(
        inline_const_enums_expr(k, table),
        inline_const_enums_expr(v, table),
      )
    Spread(inner) => Spread(inline_const_enums_expr(inner, table))
    Yield(Some(inner)) => Yield(Some(inline_const_enums_expr(inner, table)))
    YieldStar(inner) => YieldStar(inline_const_enums_expr(inner, table))
    Await(inner) => Await(inline_const_enums_expr(inner, table))
    Seq(a, b) =>
      Seq(inline_const_enums_expr(a, table), inline_const_enums_expr(b, table))
    AssignExpr(n, v) => AssignExpr(n, inline_const_enums_expr(v, table))
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(
        inline_const_enums_expr(t, table),
        op,
        inline_const_enums_expr(v, table),
      )
    AssignPattern(b, v) => AssignPattern(b, inline_const_enums_expr(v, table))
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(
        inline_const_enums_expr(recv, table),
        p,
        inline_const_enums_expr(v, table),
      )
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        inline_const_enums_expr(recv, table),
        inline_const_enums_expr(idx, table),
        inline_const_enums_expr(v, table),
      )
    ArrowFunc(params, ret, body, is_async) => {
      let new_body = match body {
        ArrowExpr(e) =>
          @ast.TsArrowBody::ArrowExpr(inline_const_enums_expr(e, table))
        ArrowBlock(b) =>
          @ast.TsArrowBody::ArrowBlock(inline_const_enums_block(b, table))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    FuncExpr(f) => {
      let new_body = inline_const_enums_block(f.body, table)
      FuncExpr({ ..f, body: new_body })
    }
    DynamicImport(spec, opts) => {
      let opts_f = match opts {
        Some(o) => Some(inline_const_enums_expr(o, table))
        None => None
      }
      DynamicImport(inline_const_enums_expr(spec, table), opts_f)
    }
    TaggedTemplate(tag, raw, cooked, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(inline_const_enums_expr(e, table))
      }
      TaggedTemplate(
        inline_const_enums_expr(tag, table),
        raw,
        cooked,
        new_exprs,
      )
    }
    TemplateLiteral(parts, exprs) => {
      let new_exprs : Array[@ast.TsExpr] = []
      for e in exprs {
        new_exprs.push(inline_const_enums_expr(e, table))
      }
      TemplateLiteral(parts, new_exprs)
    }
    As(inner, ty) => As(inline_const_enums_expr(inner, table), ty)
    Satisfies(inner, ty) => Satisfies(inline_const_enums_expr(inner, table), ty)
    NonNull(inner) => NonNull(inline_const_enums_expr(inner, table))
    TypeArgs(tys, inner) => TypeArgs(tys, inline_const_enums_expr(inner, table))
    PureCall(inner) => PureCall(inline_const_enums_expr(inner, table))
    OptionalChain(inner) => OptionalChain(inline_const_enums_expr(inner, table))
    NativeClassExpr(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: inline_const_enums_block(f.body, table) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(inline_const_enums_block(b, table))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, inline_const_enums_expr(sf.1, table)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(inline_const_enums_expr(b, table))
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
/// The `const enum` declarations from one module's enum list — the ones
/// that produce no runtime binding and therefore MUST be substituted
/// wherever they are read, including from another module.
///
/// `is_declare` decls are excluded for the usual reason: `declare const
/// enum E` describes something the host provides, and the values may not
/// be the ones written down.
pub fn module_const_enums(
  enums : Array[@ast.TsEnumDecl],
) -> Array[@ast.TsEnumDecl] {
  let out : Array[@ast.TsEnumDecl] = []
  for d in enums {
    if d.is_const && !d.is_declare {
      out.push(d)
    }
  }
  out
}

///|
/// Substitution table for the const-enum members a module reads through
/// its IMPORTS, keyed by the local name the importing module uses.
///
/// The per-module inline in `load_module_graph` covers a module's own
/// const enums, which was quietly taken to be all of them — a bundle-wide
/// contract ("no `E.Member` reference survives") checked against one
/// module's declarations. It isn't: a const enum emits nothing, so
/// `import { ArchType } from "./kinds"` leaves the consumer with a
/// reference the linker has no binding to point at and the inliner never
/// saw. immer's bundle threw `ArchType is not defined` at load.
///
/// `resolve_exported_const_enum` follows `export { X as Y }` and
/// `export … from "…"` chains, so an enum re-exported through an
/// `index.ts` resolves the same way a normal binding would.
///
/// A namespace import (`import * as K`, then `K.ArchType.Array`) is a
/// two-level access, so its entries are keyed on the whole path
/// (`K.ArchType.Array`) and matched by the corresponding arm in
/// `inline_const_enums_expr`. It has to be handled here rather than left
/// to the pass that flattens namespace members, because the synthesized
/// namespace object carries the module's runtime exports and a const enum
/// has none.
pub fn imported_const_enum_table(
  imports : Array[@ast.TsImportDecl],
  resolved_imports : Map[String, String],
  const_enums_of : (String) -> Array[@ast.TsEnumDecl]?,
  export_specs_of : (String) -> Array[@ast.TsExportSpec]?,
  reexport_specs_of : (String) -> Array[@ast.TsReExportSpec]?,
  resolve_spec : (String, String) -> String?,
) -> Map[String, @ast.TsExpr] {
  let out : Map[String, @ast.TsExpr] = {}
  for imp in imports {
    if imp.type_only {
      continue
    }
    let dep = match resolved_imports.get(imp.module_spec) {
      Some(p) => p
      None => continue
    }
    // `import * as K from "./kinds"` reaches every const enum the dep
    // exports, under `K.<EnumName>.<Member>`.
    match imp.namespace_binding {
      Some(ns) =>
        for
          pair in collect_exported_const_enums(
            dep,
            const_enums_of,
            export_specs_of,
            reexport_specs_of,
            resolve_spec,
            {},
          ) {
          let renamed : @ast.TsEnumDecl = { ..pair.1, name: pair.0 }
          let table = build_const_enum_table([renamed])
          for entry in table {
            out[ns + "." + entry.0] = entry.1
          }
        }
      None => ()
    }
    for i, pair in imp.named_bindings {
      // `import { type E }` introduces nothing to substitute.
      if i < imp.named_type_only.length() && imp.named_type_only[i] {
        continue
      }
      let imported = pair.0
      let local = pair.1
      match
        resolve_exported_const_enum(
          dep,
          imported,
          const_enums_of,
          export_specs_of,
          reexport_specs_of,
          resolve_spec,
          {},
        ) {
        Some(decl) => {
          // Re-key the decl's members under the local name so
          // `import { ArchType as A }` substitutes `A.Array` too.
          let renamed : @ast.TsEnumDecl = { ..decl, name: local }
          let table = build_const_enum_table([renamed])
          for entry in table {
            out[entry.0] = entry.1
          }
        }
        None => ()
      }
    }
  }
  out
}

///|
/// Find the `const enum` a module exports under `name`, following
/// `export { local as name }` within the module and `export … from "…"`
/// out of it. `seen` breaks re-export cycles.
fn resolve_exported_const_enum(
  path : String,
  name : String,
  const_enums_of : (String) -> Array[@ast.TsEnumDecl]?,
  export_specs_of : (String) -> Array[@ast.TsExportSpec]?,
  reexport_specs_of : (String) -> Array[@ast.TsReExportSpec]?,
  resolve_spec : (String, String) -> String?,
  seen : Map[String, Bool],
) -> @ast.TsEnumDecl? {
  let key = path + "#" + name
  if seen.contains(key) {
    return None
  }
  seen[key] = true
  // Declared here under this name (`export const enum E`).
  match const_enums_of(path) {
    Some(decls) => {
      for d in decls {
        if d.name == name {
          return Some(d)
        }
      }
      // Declared here under a different name and aliased on the way out
      // (`const enum E … export { E as F }`).
      match export_specs_of(path) {
        Some(specs) =>
          for spec in specs {
            if spec.export_name == name {
              for d in decls {
                if d.name == spec.local_name {
                  return Some(d)
                }
              }
            }
          }
        None => ()
      }
    }
    None => return None
  }
  // Re-exported from somewhere else.
  match reexport_specs_of(path) {
    Some(specs) =>
      for spec in specs {
        if spec.type_only {
          continue
        }
        let next = match resolve_spec(path, spec.module_spec) {
          Some(p) => p
          None => continue
        }
        let upstream_name = match spec.kind {
          Named(pairs) => {
            let mut found : String? = None
            for pair in pairs {
              if pair.1 == name {
                found = Some(pair.0)
              }
            }
            match found {
              Some(n) => n
              // This `export { … } from` does not carry `name`.
              None => continue
            }
          }
          // `export * from "…"` forwards every name unchanged.
          All => name
          // `export * as ns from "…"` exposes `name` only as a member of
          // the namespace object, which this pass does not model.
          Namespace(_) => continue
        }
        match
          resolve_exported_const_enum(
            next, upstream_name, const_enums_of, export_specs_of, reexport_specs_of,
            resolve_spec, seen,
          ) {
          Some(d) => return Some(d)
          None => ()
        }
      }
    None => ()
  }
  None
}

///|
/// Every const enum a module exposes, paired with the name it exposes it
/// under. Used for `import * as ns`, which reaches all of them at once
/// and so cannot resolve one name at a time the way a named import does.
///
/// Walks the same three routes as `resolve_exported_const_enum`: declared
/// here, aliased out via `export { E as F }`, or forwarded from another
/// module. `seen` breaks re-export cycles.
fn collect_exported_const_enums(
  path : String,
  const_enums_of : (String) -> Array[@ast.TsEnumDecl]?,
  export_specs_of : (String) -> Array[@ast.TsExportSpec]?,
  reexport_specs_of : (String) -> Array[@ast.TsReExportSpec]?,
  resolve_spec : (String, String) -> String?,
  seen : Map[String, Bool],
) -> Array[(String, @ast.TsEnumDecl)] {
  let out : Array[(String, @ast.TsEnumDecl)] = []
  if seen.contains(path) {
    return out
  }
  seen[path] = true
  let own = match const_enums_of(path) {
    Some(decls) => decls
    None => return out
  }
  // Aliases first, so `export { E as F }` decides the exposed name and a
  // decl that is only reachable under its alias is not also exposed
  // under its local one.
  let aliased : Map[String, Bool] = {}
  match export_specs_of(path) {
    Some(specs) =>
      for spec in specs {
        for d in own {
          if d.name == spec.local_name {
            aliased[d.name] = true
            out.push((spec.export_name, d))
          }
        }
      }
    None => ()
  }
  for d in own {
    if !aliased.contains(d.name) {
      out.push((d.name, d))
    }
  }
  match reexport_specs_of(path) {
    Some(specs) =>
      for spec in specs {
        if spec.type_only {
          continue
        }
        let next = match resolve_spec(path, spec.module_spec) {
          Some(p) => p
          None => continue
        }
        let upstream = collect_exported_const_enums(
          next, const_enums_of, export_specs_of, reexport_specs_of, resolve_spec,
          seen,
        )
        match spec.kind {
          // `export { A as B } from "…"` forwards only the listed names.
          Named(pairs) =>
            for pair in pairs {
              for up in upstream {
                if up.0 == pair.0 {
                  out.push((pair.1, up.1))
                }
              }
            }
          All =>
            for up in upstream {
              out.push(up)
            }
          // `export * as ns from "…"` puts them a level deeper than this
          // pass models. Left alone rather than exposed at the wrong path.
          Namespace(_) => ()
        }
      }
    None => ()
  }
  out
}

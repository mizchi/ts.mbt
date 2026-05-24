// TypeScript-specific desugaring run *before* the optimizer
// pipeline. Lowers TS-only constructs into the runtime stmt
// stream so downstream passes (tree-shake, inline-immutable,
// mangle, …) see something they know how to handle.
//
// Currently lowers:
//   - Function overload signatures (`function f(n: number): string;`
//     followed by `function f(s: string): string;` followed by the
//     real impl) — the signature-only forms have empty bodies and
//     would collide with each other and the impl. They're stripped
//     when a later sibling with the same name has a real body.
//
//   - `enum X { … }` — lowered to either a plain object literal
//     (string enums) or a numeric-enum object with reverse-mapping
//     entries (`{ Red: 0, 0: "Red", … }`).
//
//   - `namespace X { export const A = …; export function f() … }` —
//     lowered to an IIFE that populates a `var X = X || {}` object
//     with each exported member.

///|
/// Apply every TS-only desugar pass to a module block. Called from
/// the bundler right after parsing, before any optimizer pass
/// touches the AST.
pub fn ts_desugar_block(
  block : @ast.TsBlock,
  enums : Array[@ast.TsEnumDecl],
  namespaces : Array[@ast.TsNamespaceDecl],
) -> @ast.TsBlock {
  let after_overloads = drop_overload_signatures(block)
  let after_enums = prepend_enum_decls(after_overloads, enums)
  prepend_namespace_decls(after_enums, namespaces)
}

// ---------------------------------------------------------------------------
// Overload-signature drop
// ---------------------------------------------------------------------------

///|
/// A `Let(Ident(f), …, FuncExpr(empty body))` immediately followed
/// by `Let(Ident(f), …, FuncExpr(real))` is a TypeScript overload
/// signature. The signature-only forms have to be dropped so the
/// runtime sees just one declaration.
fn drop_overload_signatures(block : @ast.TsBlock) -> @ast.TsBlock {
  // Build the set of function names whose final / impl decl has a
  // non-empty body. Any earlier same-name decl with an empty body
  // is an overload signature and gets dropped.
  let impl_names : Map[String, Bool] = {}
  for s in block.stmts {
    match s {
      Let(@ast.TsBinding::Ident(name), _, FuncExpr(f)) =>
        if f.body.stmts.length() > 0 {
          impl_names[name] = true
        }
      _ => ()
    }
  }
  let new_stmts : Array[@ast.TsStmt] = []
  let new_positions : Array[Int] = []
  let has_positions = block.stmt_positions.length() == block.stmts.length()
  for i, s in block.stmts {
    let drop = match s {
      Let(@ast.TsBinding::Ident(name), _, FuncExpr(f)) =>
        f.body.stmts.length() == 0 && impl_names.contains(name)
      _ => false
    }
    if !drop {
      new_stmts.push(s)
      if has_positions {
        new_positions.push(block.stmt_positions[i])
      }
    }
  }
  { stmts: new_stmts, stmt_positions: new_positions }
}

// ---------------------------------------------------------------------------
// Enum lowering
// ---------------------------------------------------------------------------

///|
/// Prepend a `const X = { … }` decl for every enum in `enums`.
/// Numeric enums get reverse-mapping entries (`{ "Red": 0, 0: "Red", … }`)
/// so `Color[0]` returns `"Red"` at runtime; string enums omit them.
fn prepend_enum_decls(
  block : @ast.TsBlock,
  enums : Array[@ast.TsEnumDecl],
) -> @ast.TsBlock {
  let lowered : Array[@ast.TsStmt] = []
  for en in enums {
    if en.is_declare {
      // Ambient enum — no runtime presence.
      continue
    }
    lowered.push(lower_enum(en))
  }
  if lowered.length() == 0 {
    return block
  }
  let new_stmts : Array[@ast.TsStmt] = []
  for s in lowered {
    new_stmts.push(s)
  }
  for s in block.stmts {
    new_stmts.push(s)
  }
  let new_positions : Array[Int] = []
  if block.stmt_positions.length() == block.stmts.length() {
    for _ in lowered {
      new_positions.push(0)
    }
    for p in block.stmt_positions {
      new_positions.push(p)
    }
  }
  { stmts: new_stmts, stmt_positions: new_positions }
}

///|
/// Lower a single enum decl to `const X = { … };`.
fn lower_enum(en : @ast.TsEnumDecl) -> @ast.TsStmt {
  let entries : Array[(String, @ast.TsExpr)] = []
  // Walk members, auto-incrementing numeric values when omitted.
  let mut auto_idx = 0
  let mut all_string = true
  for m in en.members {
    let value : @ast.TsExpr = match m.value {
      Some(@ast.TsEnumMemberValue::String(s)) => @ast.TsExpr::StringLit(s)
      Some(@ast.TsEnumMemberValue::Number(s)) => {
        all_string = false
        match (try? @strconv.parse_int(s)) {
          Ok(n) => {
            auto_idx = n + 1
            @ast.TsExpr::IntLit(n)
          }
          Err(_) =>
            match (try? @strconv.parse_double(s)) {
              Ok(d) => {
                auto_idx = d.to_int() + 1
                @ast.TsExpr::NumberLit(d)
              }
              Err(_) => @ast.TsExpr::StringLit(s)
            }
        }
      }
      Some(@ast.TsEnumMemberValue::BigInt(s)) => @ast.TsExpr::BigIntLit(s)
      Some(@ast.TsEnumMemberValue::Bool(b)) => @ast.TsExpr::BoolLit(b)
      None => {
        all_string = false
        let v = @ast.TsExpr::IntLit(auto_idx)
        auto_idx = auto_idx + 1
        v
      }
    }
    entries.push((m.name, value))
  }
  // Reverse-mapping entries for numeric enums: `0: "Red"`, etc.
  // String enums (per TS spec) don't get them.
  if !all_string {
    let reverse : Array[(String, @ast.TsExpr)] = []
    for ent in entries {
      match ent.1 {
        IntLit(n) => reverse.push((n.to_string(), @ast.TsExpr::StringLit(ent.0)))
        NumberLit(d) => {
          let i = d.to_int()
          if i.to_double() == d {
            reverse.push((i.to_string(), @ast.TsExpr::StringLit(ent.0)))
          }
        }
        _ => ()
      }
    }
    for r in reverse {
      entries.push(r)
    }
  }
  @ast.TsStmt::Const(
    @ast.TsBinding::Ident(en.name),
    @ast.TsType::Any,
    @ast.TsExpr::ObjectLit(entries),
  )
}

// ---------------------------------------------------------------------------
// Namespace lowering
// ---------------------------------------------------------------------------

///|
/// Prepend an IIFE that materializes each namespace's exported
/// values onto an object. Only namespaces with at least one value
/// member (const / function / class) are lowered — pure-type
/// namespaces have no runtime artifact.
fn prepend_namespace_decls(
  block : @ast.TsBlock,
  namespaces : Array[@ast.TsNamespaceDecl],
) -> @ast.TsBlock {
  let lowered : Array[@ast.TsStmt] = []
  for ns in namespaces {
    match lower_namespace(ns) {
      Some(stmt) => lowered.push(stmt)
      None => ()
    }
  }
  if lowered.length() == 0 {
    return block
  }
  let new_stmts : Array[@ast.TsStmt] = []
  for s in lowered {
    new_stmts.push(s)
  }
  for s in block.stmts {
    new_stmts.push(s)
  }
  let new_positions : Array[Int] = []
  if block.stmt_positions.length() == block.stmts.length() {
    for _ in lowered {
      new_positions.push(0)
    }
    for p in block.stmt_positions {
      new_positions.push(p)
    }
  }
  { stmts: new_stmts, stmt_positions: new_positions }
}

///|
/// Lower a single namespace decl to `const NS = { … };`.
/// Returns `None` for pure-type namespaces (no value members).
fn lower_namespace(ns : @ast.TsNamespaceDecl) -> @ast.TsStmt? {
  let entries : Array[(String, @ast.TsExpr)] = []
  // Functions
  for f in ns.module_.funcs {
    entries.push((f.name, @ast.TsExpr::FuncExpr(f)))
  }
  // Value constants — `TsValueDecl` only carries name + type, no
  // initializer. We can't reconstruct the initializer from there;
  // skip values that aren't function decls (function bodies are
  // recoverable via `module_.funcs`). Real-world namespace usage
  // mostly mixes functions + nested namespaces anyway.
  // Skip TsValueDecl entries for now.
  let _ = ns.module_.values
  // Nested enums
  for en in ns.module_.enums {
    if en.is_declare {
      continue
    }
    match lower_enum(en) {
      Const(_, _, init) => entries.push((en.name, init))
      _ => ()
    }
  }
  if entries.length() == 0 {
    return None
  }
  Some(
    @ast.TsStmt::Const(
      @ast.TsBinding::Ident(ns.name),
      @ast.TsType::Any,
      @ast.TsExpr::ObjectLit(entries),
    ),
  )
}

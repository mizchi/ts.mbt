// Module-level validation: surface declarations whose type references
// cannot be resolved against the names declared in the same module. Useful
// as a sanity check on `.d.ts` fixtures and synthesized scaffolds.

///|
// Return a deduplicated, ordered list of every Named/Applied reference name
// in `module_` that does not correspond to one of:
//   - an interface, type alias, class, enum, or namespace declared in the
//     module
//   - a generic parameter currently in scope at the use site
//   - a well-known TypeScript / standard-library identifier
//
// Imports are not consulted (they are bridged through external modules); a
// future overload could accept a name table to fold them in.
pub fn unresolved_type_references(module_ : @ast.TsModule) -> Array[String] {
  let declared = module_declared_name_set(module_)
  let acc : Array[String] = []
  let acc_set : Map[String, Unit] = {}
  let no_locals : Array[String] = []
  for iface in module_.interfaces {
    for field in iface.fields {
      check_type(field.1, declared, iface.type_params, acc, acc_set)
    }
  }
  for ta in module_.type_aliases {
    check_type(ta.type_, declared, ta.type_params, acc, acc_set)
  }
  for f in module_.funcs {
    for param in f.params {
      check_type(param.type_, declared, f.type_params, acc, acc_set)
    }
    check_type(f.return_type, declared, f.type_params, acc, acc_set)
  }
  for i in module_.imports {
    for param in i.params {
      check_type(param.1, declared, i.type_params, acc, acc_set)
    }
    check_type(i.return_type, declared, i.type_params, acc, acc_set)
  }
  for v in module_.values {
    check_type(v.type_, declared, no_locals, acc, acc_set)
  }
  acc
}

///|
// Return the base names of `typeof X` queries in `module_` that resolve to no
// known value. A value is "known" when it is declared in the module (function,
// ambient import, value, class, enum, namespace, or a top-level binding) or is
// a standard-library ambient global (`is_lib_global_value`, the generated
// 1000-name registry). Only `typeof` over a *provably* undeclared name is
// returned, so the check is false-positive-free: any name we cannot account
// for as a value is assumed known and left silent.
//
// Kept separate from `unresolved_type_references` (which resolves *type*
// names) because a `typeof` query references the *value* namespace; the two
// scopes differ (e.g. a `const` is a value but not a type).
pub fn unresolved_typeof_references(module_ : @ast.TsModule) -> Array[String] {
  // Gather every `typeof` base across all type positions.
  let bases : Array[String] = []
  for v in module_.values {
    collect_typeof_bases(v.type_, bases)
  }
  for iface in module_.interfaces {
    for field in iface.fields {
      collect_typeof_bases(field.1, bases)
    }
  }
  for ta in module_.type_aliases {
    collect_typeof_bases(ta.type_, bases)
  }
  for f in module_.funcs {
    for param in f.params {
      collect_typeof_bases(param.type_, bases)
    }
    collect_typeof_bases(f.return_type, bases)
  }
  for i in module_.imports {
    for param in i.params {
      collect_typeof_bases(param.1, bases)
    }
    collect_typeof_bases(i.return_type, bases)
  }
  for stmt in module_.top_level_stmts {
    match stmt {
      Var(_, declared, _) | Let(_, declared, _) | Const(_, declared, _) =>
        collect_typeof_bases(declared, bases)
      _ => ()
    }
  }
  if bases.length() == 0 {
    return []
  }
  let values = module_value_name_set(module_)
  let acc : Array[String] = []
  for base in bases {
    if !values.contains(base) &&
      !is_typeof_value_keyword(base) &&
      !is_lib_global_value(base) &&
      !acc.contains(base) {
      acc.push(base)
    }
  }
  acc
}

///|
// The in-scope *value*-namespace name set for a module. Maximally
// conservative: callers leave a name silent unless it is *provably*
// undeclared, so the set folds in every namespace a value could plausibly
// live in. Besides the obvious value declarations it includes function /
// import parameters (`[T, typeof obj]`), every declared *type* name (our
// parser lowers a field-only class to an interface, erasing its value side —
// treating the type name as in scope avoids a false positive there), and
// top-level statement bindings. Shared by `unresolved_typeof_references`
// (TS2304 over `typeof X`) and the computed-type-key check (TS2304 over
// `{ [e]: T }`).
fn module_value_name_set(module_ : @ast.TsModule) -> Map[String, Bool] {
  let values : Map[String, Bool] = {}
  for f in module_.funcs {
    values[f.name] = true
    for param in f.params {
      values[param.name] = true
    }
  }
  for i in module_.imports {
    values[i.name] = true
    for param in i.params {
      values[param.0] = true
    }
  }
  for n in module_.imported_binding_names {
    values[n] = true
  }
  for v in module_.values {
    values[v.name] = true
  }
  for c in module_.classes {
    values[c.name] = true
  }
  for e in module_.enums {
    values[e.name] = true
  }
  for ns in module_.namespaces {
    values[ns.name] = true
    // Fold nested declarations in as well: recordings that surface at the
    // root layer (`export = A` inside `declare module "M"`) resolve against
    // this set, and the referenced value may live in the nested scope.
    for kv in module_value_name_set(ns.module_) {
      values[kv.0] = true
    }
  }
  for aug in module_.module_augmentations {
    for kv in module_value_name_set(aug.1) {
      values[kv.0] = true
    }
  }
  for n in module_declared_names(module_) {
    values[n] = true
  }
  for stmt in module_.top_level_stmts {
    collect_stmt_value_names(stmt, values)
  }
  values
}

///|
/// TS1046 ("Top-level declarations in .d.ts files must start with either a
/// 'declare' or 'export' modifier."). Only meaningful for sources known to
/// be `.d.ts` files, so the CLI driver calls it by file extension rather
/// than the general check pipeline. Flags runtime function declarations
/// (an ambient `declare function` parses into `imports`, so anything in
/// `funcs` was written bare), non-declare enums / classes, and top-level
/// `var` / `let` / `const` statements -- unless the declaration carries the
/// parser's `<export-value>` marker (an `export` modifier satisfies the
/// rule). Interfaces / type aliases / imports are exempt in tsc.
pub fn check_dts_top_level_modifiers(
  module_ : @ast.TsModule,
) -> Array[ExprIssue] {
  let issues : Array[ExprIssue] = []
  let exported : Map[String, Unit] = {}
  for gm in module_.grammar_misuses {
    if gm.has_prefix("<export-value>") {
      exported[gm["<export-value>".length():].to_string()] = ()
    }
  }
  // Declarations written inside a `declare module "spec" { ... }` body are
  // ambient by construction and exempt from the rule, but the parser also
  // flattens them into the surrounding module's decl lists (so resolution
  // flows that don't consult `module_augmentations` still see them) —
  // exempt everything the augmentations contributed, by name
  // (@types/node's `declare module "node:fs" { function rename(...) }`).
  for entry in module_.module_augmentations {
    let (_, aug) = entry
    for f in aug.funcs {
      exported[f.name] = ()
    }
    for e in aug.enums {
      exported[e.name] = ()
    }
    for c in aug.classes {
      exported[c.name] = ()
    }
    for stmt in aug.top_level_stmts {
      match stmt {
        Var(Ident(n), _, _) | Let(Ident(n), _, _) | Const(Ident(n), _, _) =>
          exported[n] = ()
        _ => ()
      }
    }
  }
  fn flag(kind : String, name : String) -> Unit {
    if !exported.contains(name) {
      issues.push({
        path: "\{kind} `\{name}`",
        message: "top-level declarations in .d.ts files must start with either a `declare` or `export` modifier",
      })
    }
  }

  for f in module_.funcs {
    flag("function", f.name)
  }
  for e in module_.enums {
    if !e.is_declare {
      flag("enum", e.name)
    }
  }
  for c in module_.classes {
    if !c.is_declare {
      flag("class", c.name)
    }
  }
  for stmt in module_.top_level_stmts {
    match stmt {
      Var(Ident(n), _, _) | Let(Ident(n), _, _) | Const(Ident(n), _, _) =>
        flag("var", n)
      // TS1036: executable statements never belong in an ambient (.d.ts)
      // file (`{}`, `debugger;`, `for(…)…` — parserBlockStatement1.d et
      // al). Declaration-shaped statements are handled above; anything
      // control-flow / expression shaped is a definite error.
      Block(_)
      | Debugger
      | If(_, _, _)
      | While(_, _)
      | DoWhile(_, _)
      | For(_, _, _, _)
      | ForOf(_, _, _, _, _)
      | ForIn(_, _, _, _, _)
      | ForAwaitOf(_, _, _, _, _)
      | Switch(_, _)
      | Try(_, _, _, _)
      | With(_, _)
      | Throw(_)
      | Return(_)
      | Label(_, _)
      | Expr(_) =>
        issues.push({
          path: "ambient statement",
          message: "statements are not allowed in ambient contexts",
        })
      _ => ()
    }
  }
  issues
}

///|
// Global value keywords that a `typeof` query may target but which are not in
// the standard-library ambient-globals registry (they are language keywords /
// contextual values, not declared identifiers).
fn is_typeof_value_keyword(name : String) -> Bool {
  match name {
    "undefined"
    | "null"
    | "this"
    | "globalThis"
    | "NaN"
    | "Infinity"
    | "arguments"
    | "true"
    | "false"
    | "import" => true
    _ => false
  }
}

///|
fn module_declared_names(module_ : @ast.TsModule) -> Array[String] {
  // Deduplicate through a set so this stays O(n) in the declaration count
  // (an `Array::contains` per push made it O(n^2), which dominated the
  // checker on modules with thousands of interfaces).
  let names : Array[String] = []
  let seen : Map[String, Unit] = {}
  fn add(name : String) -> Unit {
    if not(seen.contains(name)) {
      seen[name] = ()
      names.push(name)
    }
  }

  for iface in module_.interfaces {
    add(iface.name)
  }
  for ta in module_.type_aliases {
    add(ta.name)
  }
  for c in module_.classes {
    add(c.name)
  }
  for e in module_.enums {
    add(e.name)
  }
  for ns in module_.namespaces {
    add(ns.name)
  }
  names
}

///|
/// Set form of `module_declared_names` for O(1) membership tests -- used by
/// the reference walk, which previously did a linear `Array::contains` per
/// referenced name (O(n^2) over the module surface).
fn module_declared_name_set(module_ : @ast.TsModule) -> Map[String, Unit] {
  let set : Map[String, Unit] = {}
  for iface in module_.interfaces {
    set[iface.name] = ()
  }
  for ta in module_.type_aliases {
    set[ta.name] = ()
  }
  for c in module_.classes {
    set[c.name] = ()
  }
  for e in module_.enums {
    set[e.name] = ()
  }
  for ns in module_.namespaces {
    set[ns.name] = ()
  }
  set
}

///|
fn is_well_known_type_name(name : String) -> Bool {
  match name {
    // Standard library / lib.dom.d.ts staples.
    "Array"
    | "ReadonlyArray"
    | "Promise"
    | "Map"
    | "Set"
    | "WeakMap"
    | "WeakSet"
    | "Record"
    | "Partial"
    | "Required"
    | "Readonly"
    | "Pick"
    | "Omit"
    | "Exclude"
    | "Extract"
    | "NonNullable"
    | "Parameters"
    | "ReturnType"
    | "InstanceType"
    | "Awaited"
    | "Date"
    | "RegExp"
    | "Error"
    | "TypeError"
    | "RangeError"
    | "SyntaxError"
    | "Object"
    | "Function"
    | "ArrayBuffer"
    | "Uint8Array"
    | "Uint16Array"
    | "Uint32Array"
    | "Int8Array"
    | "Int16Array"
    | "Int32Array"
    | "Float32Array"
    | "Float64Array"
    | "BigInt64Array"
    | "BigUint64Array"
    | "DataView"
    | "Iterable"
    | "Iterator"
    | "AsyncIterable"
    | "AsyncIterator"
    | "IterableIterator" => true
    // Everything else the TypeScript standard libraries declare
    // ambiently (PropertyKey, TemplateStringsArray, ThisType,
    // HTMLElement, ...) — the generated registry unions every lib
    // target, and a larger allowlist only ever suppresses a
    // diagnostic, never creates one.
    _ => is_lib_global_type(name)
  }
}

///|
// Collect the base identifier of every `typeof X` query reachable in `type_`
// (`typeof A` -> "A", `typeof A.B` -> "A"). `typeof import("…")` queries are
// skipped — they reference an external module, not a local value. Used to
// flag a `typeof` over an undefined name (TS2304). Mirrors `check_type`'s
// structural recursion so the query is found in every nested position.
fn collect_typeof_bases(type_ : @ast.TsType, acc : Array[String]) -> Unit {
  match type_ {
    TypeOf(query) => {
      if query.has_prefix("import(") {
        return
      }
      let base = match query.find(".") {
        Some(i) => query.substring(start=0, end=i)
        None => query
      }
      if base != "" && !acc.contains(base) {
        acc.push(base)
      }
    }
    Array(inner) => collect_typeof_bases(inner, acc)
    Applied(_, args) =>
      for a in args {
        collect_typeof_bases(a, acc)
      }
    Tuple(items) =>
      for it in items {
        collect_typeof_bases(it, acc)
      }
    Object(fields) =>
      for f in fields {
        collect_typeof_bases(f.0, acc)
        collect_typeof_bases(f.1, acc)
      }
    Struct(_, fields) =>
      for f in fields {
        collect_typeof_bases(f.1, acc)
      }
    Func(params, ret) => {
      for p in params {
        collect_typeof_bases(p, acc)
      }
      collect_typeof_bases(ret, acc)
    }
    Union(members) | Intersection(members) =>
      for m in members {
        collect_typeof_bases(m, acc)
      }
    Conditional(check_t, extends, t_branch, f_branch) => {
      collect_typeof_bases(check_t, acc)
      collect_typeof_bases(extends, acc)
      collect_typeof_bases(t_branch, acc)
      collect_typeof_bases(f_branch, acc)
    }
    IndexedAccess(base, key) => {
      collect_typeof_bases(base, acc)
      collect_typeof_bases(key, acc)
    }
    _ => ()
  }
}

///|
fn check_type(
  type_ : @ast.TsType,
  declared : Map[String, Unit],
  local : Array[String],
  acc : Array[String],
  acc_set : Map[String, Unit],
) -> Unit {
  // `declared` is a set (O(1) membership); `local` is the small type-parameter
  // list in scope at the current declaration (usually 0-3 entries), checked
  // linearly. Together they replace the old merged-and-copied `scope` array,
  // which made the walk O(n^2) over the module surface.
  fn in_scope(name : String) -> Bool {
    declared.contains(name) || local.contains(name)
  }

  fn note(name : String) -> Unit {
    if not(in_scope(name)) && not(is_well_known_type_name(name)) {
      if not(acc_set.contains(name)) {
        acc_set[name] = ()
        acc.push(name)
      }
    }
  }

  match type_ {
    Named(name) => note(name)
    Applied(name, args) => {
      note(name)
      for a in args {
        check_type(a, declared, local, acc, acc_set)
      }
    }
    Array(inner) => check_type(inner, declared, local, acc, acc_set)
    Tuple(items) =>
      for it in items {
        check_type(it, declared, local, acc, acc_set)
      }
    Object(fields) =>
      for f in fields {
        check_type(f.0, declared, local, acc, acc_set)
        check_type(f.1, declared, local, acc, acc_set)
      }
    Struct(_, fields) =>
      for f in fields {
        check_type(f.1, declared, local, acc, acc_set)
      }
    Func(params, ret) => {
      for p in params {
        check_type(p, declared, local, acc, acc_set)
      }
      check_type(ret, declared, local, acc, acc_set)
    }
    Union(members) | Intersection(members) =>
      for m in members {
        check_type(m, declared, local, acc, acc_set)
      }
    Conditional(check_t, extends, t_branch, f_branch) => {
      check_type(check_t, declared, local, acc, acc_set)
      check_type(extends, declared, local, acc, acc_set)
      check_type(t_branch, declared, local, acc, acc_set)
      check_type(f_branch, declared, local, acc, acc_set)
    }
    IndexedAccess(base, key) => {
      check_type(base, declared, local, acc, acc_set)
      check_type(key, declared, local, acc, acc_set)
    }
    _ => ()
  }
}

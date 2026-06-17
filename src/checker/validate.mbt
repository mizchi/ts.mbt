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
  let declared = module_declared_names(module_)
  let acc : Array[String] = []
  for iface in module_.interfaces {
    let scope = scope_with(declared, iface.type_params)
    for field in iface.fields {
      check_type(field.1, scope, acc)
    }
  }
  for ta in module_.type_aliases {
    let scope = scope_with(declared, ta.type_params)
    check_type(ta.type_, scope, acc)
  }
  for f in module_.funcs {
    let scope = scope_with(declared, f.type_params)
    for param in f.params {
      check_type(param.type_, scope, acc)
    }
    check_type(f.return_type, scope, acc)
  }
  for i in module_.imports {
    let scope = scope_with(declared, i.type_params)
    for param in i.params {
      check_type(param.1, scope, acc)
    }
    check_type(i.return_type, scope, acc)
  }
  for v in module_.values {
    check_type(v.type_, declared, acc)
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
  // Build the in-scope name set. Maximally conservative: a `typeof` base is
  // left silent unless we can *prove* it undeclared, so the set folds in every
  // namespace a value could plausibly live in. Besides the obvious value
  // declarations it includes function / import parameters (`[T, typeof obj]`),
  // every declared *type* name (our parser lowers a field-only class to an
  // interface, erasing its value side — treating the type name as in scope
  // avoids a false positive there), and the value keywords (`undefined`,
  // `this`, …) that are not in the lib-globals registry.
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
  }
  for n in module_declared_names(module_) {
    values[n] = true
  }
  for stmt in module_.top_level_stmts {
    collect_stmt_value_names(stmt, values)
  }
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
fn scope_with(
  declared : Array[String],
  type_params : Array[String],
) -> Array[String] {
  if type_params.length() == 0 {
    return declared
  }
  let result : Array[String] = []
  for d in declared {
    result.push(d)
  }
  for p in type_params {
    if !result.contains(p) {
      result.push(p)
    }
  }
  result
}

///|
fn module_declared_names(module_ : @ast.TsModule) -> Array[String] {
  let names : Array[String] = []
  for iface in module_.interfaces {
    if !names.contains(iface.name) {
      names.push(iface.name)
    }
  }
  for ta in module_.type_aliases {
    if !names.contains(ta.name) {
      names.push(ta.name)
    }
  }
  for c in module_.classes {
    if !names.contains(c.name) {
      names.push(c.name)
    }
  }
  for e in module_.enums {
    if !names.contains(e.name) {
      names.push(e.name)
    }
  }
  for ns in module_.namespaces {
    if !names.contains(ns.name) {
      names.push(ns.name)
    }
  }
  names
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
    _ => false
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
  scope : Array[String],
  acc : Array[String],
) -> Unit {
  match type_ {
    Named(name) =>
      if !scope.contains(name) && !is_well_known_type_name(name) {
        if !acc.contains(name) {
          acc.push(name)
        }
      }
    Applied(name, args) => {
      if !scope.contains(name) && !is_well_known_type_name(name) {
        if !acc.contains(name) {
          acc.push(name)
        }
      }
      for a in args {
        check_type(a, scope, acc)
      }
    }
    Array(inner) => check_type(inner, scope, acc)
    Tuple(items) =>
      for it in items {
        check_type(it, scope, acc)
      }
    Object(fields) =>
      for f in fields {
        check_type(f.0, scope, acc)
        check_type(f.1, scope, acc)
      }
    Struct(_, fields) =>
      for f in fields {
        check_type(f.1, scope, acc)
      }
    Func(params, ret) => {
      for p in params {
        check_type(p, scope, acc)
      }
      check_type(ret, scope, acc)
    }
    Union(members) | Intersection(members) =>
      for m in members {
        check_type(m, scope, acc)
      }
    Conditional(check_t, extends, t_branch, f_branch) => {
      check_type(check_t, scope, acc)
      check_type(extends, scope, acc)
      check_type(t_branch, scope, acc)
      check_type(f_branch, scope, acc)
    }
    IndexedAccess(base, key) => {
      check_type(base, scope, acc)
      check_type(key, scope, acc)
    }
    _ => ()
  }
}

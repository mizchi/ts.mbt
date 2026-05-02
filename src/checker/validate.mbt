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
    let scope = declared
    for param in f.params {
      check_type(param.type_, scope, acc)
    }
    check_type(f.return_type, scope, acc)
  }
  for i in module_.imports {
    for param in i.params {
      check_type(param.1, declared, acc)
    }
    check_type(i.return_type, declared, acc)
  }
  for v in module_.values {
    check_type(v.type_, declared, acc)
  }
  acc
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

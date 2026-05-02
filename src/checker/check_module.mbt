// High-level module-level type checker. Aggregates the individual checks
// (unresolved references, duplicate declarations, circular alias chains) into
// a single `TypeCheckReport` consumers can scan for issues. Designed so the
// bridge package can run it before generation and surface diagnostics back to
// the user.

///|
pub(all) enum TypeIssueKind {
  UnresolvedReference
  DuplicateDeclaration
  CircularTypeAlias
  TypeAliasArityMismatch
} derive(Eq, Debug)

///|
pub(all) struct TypeIssue {
  kind : TypeIssueKind
  name : String
  detail : String
} derive(Eq, Debug)

///|
pub(all) struct TypeCheckReport {
  issues : Array[TypeIssue]
}

///|
pub fn check_module(module_ : @ast.TsModule) -> TypeCheckReport {
  let issues : Array[TypeIssue] = []

  // 1. Duplicate declarations across all top-level kinds.
  let seen_names : Array[String] = []
  let duplicates : Array[String] = []
  for iface in module_.interfaces {
    record_or_duplicate(seen_names, duplicates, iface.name)
  }
  for ta in module_.type_aliases {
    record_or_duplicate(seen_names, duplicates, ta.name)
  }
  for c in module_.classes {
    record_or_duplicate(seen_names, duplicates, c.name)
  }
  for e in module_.enums {
    record_or_duplicate(seen_names, duplicates, e.name)
  }
  for n in module_.namespaces {
    record_or_duplicate(seen_names, duplicates, n.name)
  }
  for d in duplicates {
    issues.push({
      kind: DuplicateDeclaration,
      name: d,
      detail: "name declared more than once at top level",
    })
  }

  // 2. Unresolved type references.
  for n in unresolved_type_references(module_) {
    issues.push({
      kind: UnresolvedReference,
      name: n,
      detail: "no top-level interface, alias, class, enum, or namespace declares this name",
    })
  }

  // 3. Circular type-alias chains: a type alias whose body recursively reaches
  //    itself only through other Named references (not through generic args
  //    or compound shapes that interrupt the cycle).
  for ta in module_.type_aliases {
    if reaches_alias(module_, ta.name, ta.type_, []) {
      issues.push({
        kind: CircularTypeAlias,
        name: ta.name,
        detail: "type alias resolves to itself without an intervening structural form",
      })
    }
  }

  // 4. Type-alias arity mismatches: every `Applied(Name, args)` that resolves
  //    to a top-level type alias must use the alias's declared arity.
  let arities : Map[String, Int] = {}
  for ta in module_.type_aliases {
    arities[ta.name] = ta.type_params.length()
  }
  for iface in module_.interfaces {
    let scope = scope_with_iface_params(iface)
    for field in iface.fields {
      check_arity(field.1, scope, arities, issues)
    }
  }
  for ta in module_.type_aliases {
    let scope = ta.type_params
    check_arity(ta.type_, scope, arities, issues)
  }
  for f in module_.funcs {
    let scope : Array[String] = []
    for p in f.params {
      check_arity(p.type_, scope, arities, issues)
    }
    check_arity(f.return_type, scope, arities, issues)
  }
  for i in module_.imports {
    let scope : Array[String] = []
    for p in i.params {
      check_arity(p.1, scope, arities, issues)
    }
    check_arity(i.return_type, scope, arities, issues)
  }
  for v in module_.values {
    let scope : Array[String] = []
    check_arity(v.type_, scope, arities, issues)
  }
  { issues, }
}

///|
fn scope_with_iface_params(iface : @ast.TsInterface) -> Array[String] {
  iface.type_params
}

///|
fn check_arity(
  type_ : @ast.TsType,
  scope : Array[String],
  arities : Map[String, Int],
  issues : Array[TypeIssue],
) -> Unit {
  match type_ {
    Applied(name, args) => {
      if !scope.contains(name) {
        match arities.get(name) {
          Some(expected) =>
            if expected != args.length() {
              let already = issues.iter().any(fn(i) {
                i.kind == TypeAliasArityMismatch && i.name == name
              })
              if !already {
                issues.push({
                  kind: TypeAliasArityMismatch,
                  name,
                  detail: "type alias declared with \{expected} parameter(s) used with \{args.length()}",
                })
              }
            }
          None => ()
        }
      }
      for a in args {
        check_arity(a, scope, arities, issues)
      }
    }
    Array(inner) => check_arity(inner, scope, arities, issues)
    Tuple(items) =>
      for it in items {
        check_arity(it, scope, arities, issues)
      }
    Object(fields) =>
      for f in fields {
        check_arity(f.0, scope, arities, issues)
        check_arity(f.1, scope, arities, issues)
      }
    Func(params, ret) => {
      for p in params {
        check_arity(p, scope, arities, issues)
      }
      check_arity(ret, scope, arities, issues)
    }
    Union(items) | Intersection(items) =>
      for m in items {
        check_arity(m, scope, arities, issues)
      }
    Conditional(c, e, t, f) => {
      check_arity(c, scope, arities, issues)
      check_arity(e, scope, arities, issues)
      check_arity(t, scope, arities, issues)
      check_arity(f, scope, arities, issues)
    }
    IndexedAccess(b, k) => {
      check_arity(b, scope, arities, issues)
      check_arity(k, scope, arities, issues)
    }
    _ => ()
  }
}

///|
fn record_or_duplicate(
  seen : Array[String],
  duplicates : Array[String],
  name : String,
) -> Unit {
  if seen.contains(name) {
    if !duplicates.contains(name) {
      duplicates.push(name)
    }
  } else {
    seen.push(name)
  }
}

///|
// `reaches_alias(module_, target, body, visited)` returns true iff a Named
// reference back to `target` exists in `body` reachable only through Named
// references to other type aliases (not through Array/Object/Func/etc., which
// constitute structural barriers that break the cycle).
fn reaches_alias(
  module_ : @ast.TsModule,
  target : String,
  body : @ast.TsType,
  visited : Array[String],
) -> Bool {
  match body {
    Named(name) =>
      if name == target {
        return true
      } else if visited.contains(name) {
        return false
      } else {
        // Only follow into the body if `name` is itself a top-level alias.
        for ta in module_.type_aliases {
          if ta.name == name {
            visited.push(name)
            let result = reaches_alias(module_, target, ta.type_, visited)
            let _ = visited.pop()
            return result
          }
        }
        return false
      }
    Union(members) | Intersection(members) => {
      for m in members {
        if reaches_alias(module_, target, m, visited) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

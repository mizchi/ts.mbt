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
  { issues, }
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

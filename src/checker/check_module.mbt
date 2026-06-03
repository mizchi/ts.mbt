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
  TypeParameterConstraintViolation
  InterfaceFieldDuplicate
  EnumMemberDuplicate
  InterfaceExtendsCycle
  ClassPropertyDuplicate
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
// True iff the report has no issues. Convenience for `report.issues.length() == 0`.
pub fn TypeCheckReport::is_clean(self : TypeCheckReport) -> Bool {
  self.issues.length() == 0
}

///|
// Filter issues to only the given kind. Useful when callers want to handle
// `UnresolvedReference` separately from `DuplicateDeclaration`, etc.
pub fn TypeCheckReport::of_kind(
  self : TypeCheckReport,
  kind : TypeIssueKind,
) -> Array[TypeIssue] {
  let out : Array[TypeIssue] = []
  for i in self.issues {
    if i.kind == kind {
      out.push(i)
    }
  }
  out
}

///|
// Count issues of the given kind without materializing the array.
pub fn TypeCheckReport::count_of_kind(
  self : TypeCheckReport,
  kind : TypeIssueKind,
) -> Int {
  let mut n = 0
  for i in self.issues {
    if i.kind == kind {
      n += 1
    }
  }
  n
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

  // 3b. Interface extends-chain cycles: `interface A extends B {}` followed
  //     by `interface B extends A {}` — TypeScript rejects, synthesized
  //     output must not produce.
  for iface in module_.interfaces {
    if iface_extends_reaches(module_, iface.name, iface.extends_names, []) {
      issues.push({
        kind: InterfaceExtendsCycle,
        name: iface.name,
        detail: "interface extends chain reaches back to itself",
      })
    }
  }

  // 3c. Enum member duplicates: same member name listed twice in an enum.
  for e in module_.enums {
    let seen : Array[String] = []
    let dup : Array[String] = []
    for em in e.members {
      if seen.contains(em.name) {
        if !dup.contains(em.name) {
          dup.push(em.name)
        }
      } else {
        seen.push(em.name)
      }
    }
    for d in dup {
      issues.push({
        kind: EnumMemberDuplicate,
        name: "\{e.name}.\{d}",
        detail: "enum declares the same member name more than once",
      })
    }
  }

  // 3d. Class property duplicates: same property name listed twice on a
  //     class (instance + static treated separately, since TS allows
  //     `static x` alongside `x`). Methods are skipped because TS allows
  //     same-name method overloads.
  for c in module_.classes {
    let seen_inst : Array[String] = []
    let dup_inst : Array[String] = []
    let seen_static : Array[String] = []
    let dup_static : Array[String] = []
    for p in c.properties {
      let bucket = if p.is_static { seen_static } else { seen_inst }
      let dup = if p.is_static { dup_static } else { dup_inst }
      if bucket.contains(p.name) {
        if !dup.contains(p.name) {
          dup.push(p.name)
        }
      } else {
        bucket.push(p.name)
      }
    }
    for d in dup_inst {
      issues.push({
        kind: ClassPropertyDuplicate,
        name: "\{c.name}.\{d}",
        detail: "class declares the same instance property name more than once",
      })
    }
    for d in dup_static {
      issues.push({
        kind: ClassPropertyDuplicate,
        name: "\{c.name}.\{d}",
        detail: "class declares the same static property name more than once",
      })
    }
  }

  // 4. Duplicate field names within the same interface — TS rejects these,
  //    and synthesized interfaces should not produce them either.
  for iface in module_.interfaces {
    let seen_fields : Array[String] = []
    let dup_fields : Array[String] = []
    for f in iface.fields {
      if seen_fields.contains(f.0) {
        if !dup_fields.contains(f.0) {
          dup_fields.push(f.0)
        }
      } else {
        seen_fields.push(f.0)
      }
    }
    for d in dup_fields {
      issues.push({
        kind: InterfaceFieldDuplicate,
        name: "\{iface.name}.\{d}",
        detail: "interface declares the same field name more than once",
      })
    }
  }

  // 5. Type-alias arity mismatches: every `Applied(Name, args)` that resolves
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

  // 6. Generic type-parameter constraint violations: every
  //    `Applied(Name, args)` that resolves to a top-level type alias
  //    declared with `<P extends Bound>` must supply an argument that
  //    satisfies `Bound`. We use the three-valued `extends_decision`
  //    relation (TS's own constraint check) and only flag a *definite*
  //    `Some(false)` — opaque / nominal / unresolved shapes report
  //    `None` and stay silent, so external references and type-parameter
  //    forwarding never produce a false positive.
  let alias_params : Map[String, Array[String]] = {}
  let alias_bounds : Map[String, Array[(String, @ast.TsType)]] = {}
  let non_generic_alias_bodies : Map[String, @ast.TsType] = {}
  for ta in module_.type_aliases {
    if ta.type_param_bounds.length() > 0 {
      alias_params[ta.name] = ta.type_params
      alias_bounds[ta.name] = ta.type_param_bounds
    }
    // A non-generic alias can stand in for its body when deciding the
    // constraint relation (`type MyStr = string` lets `Foo<MyStr>`
    // satisfy `P extends string`). Generic aliases are left opaque.
    if ta.type_params.length() == 0 {
      non_generic_alias_bodies[ta.name] = ta.type_
    }
  }
  let resolve = fn(name : String) -> @ast.TsType? {
    non_generic_alias_bodies.get(name)
  }
  if alias_bounds.length() > 0 {
    for iface in module_.interfaces {
      let scope = scope_with_iface_params(iface)
      for field in iface.fields {
        check_constraints(
          field.1,
          scope,
          alias_params,
          alias_bounds,
          resolve,
          issues,
        )
      }
    }
    for ta in module_.type_aliases {
      check_constraints(
        ta.type_,
        ta.type_params,
        alias_params,
        alias_bounds,
        resolve,
        issues,
      )
    }
    for f in module_.funcs {
      for p in f.params {
        check_constraints(
          p.type_,
          [],
          alias_params,
          alias_bounds,
          resolve,
          issues,
        )
      }
      check_constraints(
        f.return_type,
        [],
        alias_params,
        alias_bounds,
        resolve,
        issues,
      )
    }
    for v in module_.values {
      check_constraints(
        v.type_,
        [],
        alias_params,
        alias_bounds,
        resolve,
        issues,
      )
    }
  }
  { issues, }
}

///|
// Walk a type looking for `Applied(name, args)` references to a generic
// type alias declared with `extends` bounds, and flag arguments that
// definitely violate their parameter's constraint. Mirrors
// `check_arity`'s traversal so every nested type position is covered.
fn check_constraints(
  type_ : @ast.TsType,
  scope : Array[String],
  alias_params : Map[String, Array[String]],
  alias_bounds : Map[String, Array[(String, @ast.TsType)]],
  resolve : (String) -> @ast.TsType?,
  issues : Array[TypeIssue],
) -> Unit {
  match type_ {
    Applied(name, args) => {
      if !scope.contains(name) {
        match (alias_params.get(name), alias_bounds.get(name)) {
          (Some(params), Some(bounds)) =>
            // Only check when the supplied arity matches the declared
            // parameters; arity mismatches are reported separately and
            // would make the positional substitution below meaningless.
            if params.length() == args.length() {
              for pair in bounds {
                let (pname, bound) = pair
                // Locate the constrained parameter's position so we can
                // pull the matching argument.
                let mut idx = -1
                for i in 0..<params.length() {
                  if params[i] == pname {
                    idx = i
                    break
                  }
                }
                if idx >= 0 {
                  // Substitute every parameter with its argument inside the
                  // bound so dependent constraints like `K extends keyof T`
                  // are evaluated against the concrete `T`.
                  let mut substituted = bound
                  for i in 0..<params.length() {
                    substituted = substitute_named(
                      substituted,
                      params[i],
                      args[i],
                    )
                  }
                  let target = simplify_type(substituted)
                  let arg = simplify_type(args[idx])
                  match extends_decision_with(arg, target, resolve) {
                    Some(false) => {
                      let issue_name = "\{name}<\{pname}>"
                      let already = issues
                        .iter()
                        .any(fn(i) {
                          i.kind == TypeParameterConstraintViolation &&
                          i.name == issue_name
                        })
                      if !already {
                        issues.push({
                          kind: TypeParameterConstraintViolation,
                          name: issue_name,
                          detail: "type argument does not satisfy the `\{pname}` constraint",
                        })
                      }
                    }
                    _ => ()
                  }
                }
              }
            }
          _ => ()
        }
      }
      for a in args {
        check_constraints(a, scope, alias_params, alias_bounds, resolve, issues)
      }
    }
    Array(inner) =>
      check_constraints(
        inner, scope, alias_params, alias_bounds, resolve, issues,
      )
    Tuple(items) =>
      for it in items {
        check_constraints(
          it, scope, alias_params, alias_bounds, resolve, issues,
        )
      }
    Object(fields) =>
      for f in fields {
        check_constraints(
          f.0,
          scope,
          alias_params,
          alias_bounds,
          resolve,
          issues,
        )
        check_constraints(
          f.1,
          scope,
          alias_params,
          alias_bounds,
          resolve,
          issues,
        )
      }
    Struct(_, fields) =>
      for f in fields {
        check_constraints(
          f.1,
          scope,
          alias_params,
          alias_bounds,
          resolve,
          issues,
        )
      }
    Func(params, ret) => {
      for p in params {
        check_constraints(p, scope, alias_params, alias_bounds, resolve, issues)
      }
      check_constraints(ret, scope, alias_params, alias_bounds, resolve, issues)
    }
    Union(items) | Intersection(items) =>
      for m in items {
        check_constraints(m, scope, alias_params, alias_bounds, resolve, issues)
      }
    Conditional(c, e, t, f) => {
      check_constraints(c, scope, alias_params, alias_bounds, resolve, issues)
      check_constraints(e, scope, alias_params, alias_bounds, resolve, issues)
      check_constraints(t, scope, alias_params, alias_bounds, resolve, issues)
      check_constraints(f, scope, alias_params, alias_bounds, resolve, issues)
    }
    IndexedAccess(b, k) => {
      check_constraints(b, scope, alias_params, alias_bounds, resolve, issues)
      check_constraints(k, scope, alias_params, alias_bounds, resolve, issues)
    }
    _ => ()
  }
}

///|
fn scope_with_iface_params(iface : @ast.TsInterface) -> Array[String] {
  iface.type_params
}

///|
fn iface_extends_reaches(
  module_ : @ast.TsModule,
  target : String,
  extends_names : Array[String],
  visited : Array[String],
) -> Bool {
  for name in extends_names {
    if name == target {
      return true
    }
    if visited.contains(name) {
      continue
    }
    for iface in module_.interfaces {
      if iface.name == name {
        visited.push(name)
        let reached = iface_extends_reaches(
          module_,
          target,
          iface.extends_names,
          visited,
        )
        let _ = visited.pop()
        if reached {
          return true
        }
      }
    }
  }
  false
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
              let already = issues
                .iter()
                .any(fn(i) {
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

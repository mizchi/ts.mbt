// Normalization helpers built on top of the assignability checker.

///|
// Two types are considered equivalent when each is assignable to the other.
// This is bidirectional structural assignability; it is order-insensitive on
// Union/Intersection because their members are checked symmetrically.
pub fn equivalent(a : @ast.TsType, b : @ast.TsType) -> Bool {
  is_assignable_to(a, b) && is_assignable_to(b, a)
}

///|
// Resolver-aware equivalence. Pre-expands `Named(n)` references via the
// resolver before testing.
pub fn equivalent_with(
  a : @ast.TsType,
  b : @ast.TsType,
  resolve : (String) -> @ast.TsType?,
) -> Bool {
  is_assignable_to_with(a, b, resolve) && is_assignable_to_with(b, a, resolve)
}

///|
// Generics-aware equivalence. Pre-expands both `Named(n)` and `Applied(n, args)`
// alias references before testing.
pub fn equivalent_with_generics(
  a : @ast.TsType,
  b : @ast.TsType,
  resolve : (String) -> AliasBinding?,
) -> Bool {
  is_assignable_to_with_generics(a, b, resolve) &&
  is_assignable_to_with_generics(b, a, resolve)
}

///|
// Reduce a list of union members by removing duplicates and members that are
// subsumed by another member already kept. The result preserves the order of
// the surviving members. If `Any` appears, the result is just `[Any]`.
// Nested `Union(...)` members are flattened recursively before subsumption.
pub fn simplify_union(members : Array[@ast.TsType]) -> Array[@ast.TsType] {
  let flattened : Array[@ast.TsType] = []
  flatten_into(members, flattened)
  // Short-circuit on Any.
  for m in flattened {
    match m {
      Any => return [Any]
      _ => ()
    }
  }
  // TS normalizes `true | false` to `boolean`: when both literal values
  // are present, replace the pair with the `Boolean` primitive so the
  // subsumption pass below can drop any remaining literal companions.
  let mut has_true = false
  let mut has_false = false
  for m in flattened {
    match m {
      BooleanLiteral(true) => has_true = true
      BooleanLiteral(false) => has_false = true
      _ => ()
    }
  }
  let flattened = if has_true && has_false {
    let collapsed : Array[@ast.TsType] = []
    let mut inserted_boolean = false
    for m in flattened {
      match m {
        BooleanLiteral(_) =>
          if !inserted_boolean {
            collapsed.push(Boolean)
            inserted_boolean = true
          }
        _ => collapsed.push(m)
      }
    }
    collapsed
  } else {
    flattened
  }
  let kept : Array[@ast.TsType] = []
  for m in flattened {
    let mut subsumed = false
    for k in kept {
      if is_assignable_to(m, k) {
        subsumed = true
        break
      }
    }
    if subsumed {
      continue
    }
    // m is not subsumed by any existing member. Drop any kept entries that m
    // itself subsumes, then push m.
    let surviving : Array[@ast.TsType] = []
    for k in kept {
      if !is_assignable_to(k, m) {
        surviving.push(k)
      }
    }
    kept.clear()
    for s in surviving {
      kept.push(s)
    }
    kept.push(m)
  }
  kept
}

///|
fn flatten_into(members : Array[@ast.TsType], acc : Array[@ast.TsType]) -> Unit {
  for m in members {
    match m {
      Union(inner) => flatten_into(inner, acc)
      _ => acc.push(m)
    }
  }
}

///|
// Walk a type and collect the deduplicated set of `Named` / `Applied`
// reference names it transitively mentions. Useful for declaration-level
// validation passes.
pub fn collect_referenced_names(type_ : @ast.TsType) -> Array[String] {
  let acc : Array[String] = []
  collect_into(type_, acc)
  acc
}

///|
fn collect_into(type_ : @ast.TsType, acc : Array[String]) -> Unit {
  match type_ {
    Named(name) => push_unique(acc, name)
    Applied(name, args) => {
      push_unique(acc, name)
      for a in args {
        collect_into(a, acc)
      }
    }
    Array(inner) => collect_into(inner, acc)
    Tuple(items) =>
      for it in items {
        collect_into(it, acc)
      }
    Object(fields) =>
      for f in fields {
        collect_into(f.0, acc)
        collect_into(f.1, acc)
      }
    Struct(_, fields) =>
      for f in fields {
        collect_into(f.1, acc)
      }
    Func(params, ret) => {
      for p in params {
        collect_into(p, acc)
      }
      collect_into(ret, acc)
    }
    Union(members) | Intersection(members) =>
      for m in members {
        collect_into(m, acc)
      }
    Conditional(check, extends, t_branch, f_branch) => {
      collect_into(check, acc)
      collect_into(extends, acc)
      collect_into(t_branch, acc)
      collect_into(f_branch, acc)
    }
    IndexedAccess(base, key) => {
      collect_into(base, acc)
      collect_into(key, acc)
    }
    _ => ()
  }
}

///|
fn push_unique(acc : Array[String], name : String) -> Unit {
  if !acc.contains(name) {
    acc.push(name)
  }
}

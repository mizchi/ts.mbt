// Minimal TypeScript-style assignability check operating on `@ast.TsType`.
// `is_assignable_to(source, target)` answers: can a value of type `source`
// be used where `target` is expected?
//
// The implementation is intentionally local — it does not resolve `Named`
// references against any module graph. Callers that need cross-reference
// resolution should pre-substitute aliases first.
//
// Function parameter variance defaults to *contravariant* (TS strict-mode
// behavior). Use `is_assignable_to_bivariant` to mirror non-strict TS where
// method-shorthand parameters are bivariant.

///|
pub fn is_assignable_to(source : @ast.TsType, target : @ast.TsType) -> Bool {
  is_assignable_to_inner(source, target, false)
}

///|
pub fn is_assignable_to_bivariant(
  source : @ast.TsType,
  target : @ast.TsType,
) -> Bool {
  is_assignable_to_inner(source, target, true)
}

///|
fn is_assignable_to_inner(
  source : @ast.TsType,
  target : @ast.TsType,
  bivariant_params : Bool,
) -> Bool {
  // Reflexive shortcut.
  if source == target {
    return true
  }
  // Resolve T[K] before matching — IndexedAccess that cannot be resolved is
  // treated as `Any`, which flows freely. Both sides are eagerly resolved.
  let source = resolve_indexed_access_local(source)
  let target = resolve_indexed_access_local(target)
  // Conditional types pick a branch when `extends` is decidable.
  let source = reduce_conditional(source)
  let target = reduce_conditional(target)
  if source == target {
    return true
  }
  // `any` is the universal escape hatch — it flows in either direction.
  match target {
    Any => return true
    _ => ()
  }
  match source {
    Any => return true
    _ => ()
  }
  // `never` is the bottom type: anything accepts it as a source.
  match source {
    Never => return true
    _ => ()
  }
  // The target side of a union accepts a source if any member matches.
  match target {
    Union(members) => {
      for m in members {
        if is_assignable_to_inner(source, m, bivariant_params) {
          return true
        }
      }
      // Fall through to source-side handling below for unions on the source.
      match source {
        Union(_) => ()
        _ => return false
      }
    }
    _ => ()
  }
  // The source side of a union flows into target only if every member fits.
  match source {
    Union(members) => {
      for m in members {
        if !is_assignable_to_inner(m, target, bivariant_params) {
          return false
        }
      }
      return true
    }
    _ => ()
  }
  // Target intersection: every component must accept the source.
  match target {
    Intersection(members) => {
      for m in members {
        if !is_assignable_to_inner(source, m, bivariant_params) {
          return false
        }
      }
      return true
    }
    _ => ()
  }
  // Source intersection: at least one component must satisfy the target.
  match source {
    Intersection(members) => {
      for m in members {
        if is_assignable_to_inner(m, target, bivariant_params) {
          return true
        }
      }
      return false
    }
    _ => ()
  }
  match (source, target) {
    // Literal subtyping: each literal kind narrows its primitive companion.
    (Literal(_), String_) => true
    (NumberLiteral(_), Number) => true
    (BigIntLiteral(_), BigInt) => true
    (BooleanLiteral(_), Boolean) => true
    // Compound covariance/contravariance.
    (Array(s_inner), Array(t_inner)) =>
      is_assignable_to_inner(s_inner, t_inner, bivariant_params)
    (Tuple(s_items), Tuple(t_items)) => {
      if s_items.length() != t_items.length() {
        return false
      }
      for i in 0..<s_items.length() {
        if !is_assignable_to_inner(s_items[i], t_items[i], bivariant_params) {
          return false
        }
      }
      return true
    }
    (Func(s_params, s_ret), Func(t_params, t_ret)) => {
      if s_params.length() != t_params.length() {
        return false
      }
      // Contravariant params (strict): target's param must flow into source's
      // param. Bivariant: either direction is acceptable.
      for i in 0..<s_params.length() {
        let ok = if bivariant_params {
          is_assignable_to_inner(s_params[i], t_params[i], bivariant_params) ||
          is_assignable_to_inner(t_params[i], s_params[i], bivariant_params)
        } else {
          is_assignable_to_inner(t_params[i], s_params[i], bivariant_params)
        }
        if !ok {
          return false
        }
      }
      // Covariant return.
      is_assignable_to_inner(s_ret, t_ret, bivariant_params)
    }
    (Object(s_fields), Object(t_fields)) =>
      is_object_assignable_inner(s_fields, t_fields, bivariant_params)
    // Named/applied references are nominal: only equal names match.
    (Named(a), Named(b)) => a == b
    (Applied(a, args_a), Applied(b, args_b)) => {
      if a != b || args_a.length() != args_b.length() {
        return false
      }
      for i in 0..<args_a.length() {
        if !is_assignable_to_inner(args_a[i], args_b[i], bivariant_params) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
fn is_object_assignable_inner(
  s_fields : Array[(@ast.TsType, @ast.TsType)],
  t_fields : Array[(@ast.TsType, @ast.TsType)],
  bivariant_params : Bool,
) -> Bool {
  for t_field in t_fields {
    let (t_key, t_type) = t_field
    let mut matched = false
    for s_field in s_fields {
      let (s_key, s_type) = s_field
      if s_key == t_key {
        if !is_assignable_to_inner(s_type, t_type, bivariant_params) {
          return false
        }
        matched = true
        break
      }
    }
    if !matched {
      // A target field whose type accepts `undefined` (the desugaring of
      // `x?: T`) tolerates the source missing that field entirely.
      if !type_accepts_undefined(t_type) {
        return false
      }
    }
  }
  true
}

///|
fn type_accepts_undefined(t : @ast.TsType) -> Bool {
  match t {
    Undefined | Any => true
    Union(members) => {
      for m in members {
        if type_accepts_undefined(m) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
// Resolve `T[K]` once: when `T` is a structural Object/Struct and `K` is a
// string literal that names one of the fields, return the field type. Any
// other case (generic T, computed K, missing field) returns `Any` to keep the
// caller permissive — TypeScript's fallback for unknown indexed access is
// effectively the same.
fn resolve_indexed_access_local(t : @ast.TsType) -> @ast.TsType {
  match t {
    IndexedAccess(base, key) => {
      let key_name = match key {
        Literal(name) => name
        _ => return Any
      }
      match base {
        Object(fields) => {
          for field in fields {
            let (k, v) = field
            match k {
              Literal(field_name) => if field_name == key_name { return v }
              _ => ()
            }
          }
          Any
        }
        Struct(_, fields) => {
          for field in fields {
            let (field_name, v) = field
            if field_name == key_name {
              return v
            }
          }
          Any
        }
        _ => Any
      }
    }
    _ => t
  }
}

///|
// Reduce `A extends B ? X : Y` to a concrete branch:
//   - If `B` contains `infer` markers, try `match_infer_pattern(A, B)` and
//     substitute the captured names into `X` on success. On failure (no
//     match), pick `Y`.
//   - Otherwise fall back to `is_assignable_to(A, B)`.
// If neither attempt yields a definite answer, return the conditional
// unchanged so the surrounding match falls through to `_ => false`.
fn reduce_conditional(t : @ast.TsType) -> @ast.TsType {
  match t {
    Conditional(check, extends, true_branch, false_branch) =>
      if contains_infer_marker(extends) {
        let bindings : Map[String, @ast.TsType] = {}
        if match_infer_pattern(check, extends, bindings) {
          substitute_inferred_type(true_branch, bindings)
        } else {
          false_branch
        }
      } else if is_assignable_to(check, extends) {
        true_branch
      } else {
        false_branch
      }
    _ => t
  }
}

///|
fn contains_infer_marker(t : @ast.TsType) -> Bool {
  match infer_marker_name(t) {
    Some(_) => return true
    None => ()
  }
  match t {
    Array(inner) => contains_infer_marker(inner)
    Tuple(items) => {
      for it in items {
        if contains_infer_marker(it) {
          return true
        }
      }
      false
    }
    Object(fields) => {
      for f in fields {
        if contains_infer_marker(f.0) || contains_infer_marker(f.1) {
          return true
        }
      }
      false
    }
    Func(params, ret) => {
      for p in params {
        if contains_infer_marker(p) {
          return true
        }
      }
      contains_infer_marker(ret)
    }
    Union(items) | Intersection(items) => {
      for it in items {
        if contains_infer_marker(it) {
          return true
        }
      }
      false
    }
    Conditional(check, extends, t_branch, f_branch) =>
      contains_infer_marker(check) ||
      contains_infer_marker(extends) ||
      contains_infer_marker(t_branch) ||
      contains_infer_marker(f_branch)
    Applied(_, args) => {
      for a in args {
        if contains_infer_marker(a) {
          return true
        }
      }
      false
    }
    IndexedAccess(base, key) =>
      contains_infer_marker(base) || contains_infer_marker(key)
    _ => false
  }
}

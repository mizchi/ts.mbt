// Minimal TypeScript-style assignability check operating on `@ast.TsType`.
// `is_assignable_to(source, target)` answers: can a value of type `source`
// be used where `target` is expected?
//
// The implementation is intentionally local — it does not resolve `Named`
// references against any module graph. Callers that need cross-reference
// resolution should pre-substitute aliases first.

///|
pub fn is_assignable_to(
  source : @ast.TsType,
  target : @ast.TsType,
) -> Bool {
  // Reflexive shortcut.
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
        if is_assignable_to(source, m) {
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
        if !is_assignable_to(m, target) {
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
        if !is_assignable_to(source, m) {
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
        if is_assignable_to(m, target) {
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
    (Array(s_inner), Array(t_inner)) => is_assignable_to(s_inner, t_inner)
    (Tuple(s_items), Tuple(t_items)) => {
      if s_items.length() != t_items.length() {
        return false
      }
      for i in 0..<s_items.length() {
        if !is_assignable_to(s_items[i], t_items[i]) {
          return false
        }
      }
      return true
    }
    (Func(s_params, s_ret), Func(t_params, t_ret)) => {
      if s_params.length() != t_params.length() {
        return false
      }
      // Contravariant params: target's param must flow into source's param.
      for i in 0..<s_params.length() {
        if !is_assignable_to(t_params[i], s_params[i]) {
          return false
        }
      }
      // Covariant return.
      is_assignable_to(s_ret, t_ret)
    }
    (Object(s_fields), Object(t_fields)) =>
      is_object_assignable(s_fields, t_fields)
    // Named/applied references are nominal: only equal names match.
    (Named(a), Named(b)) => a == b
    (Applied(a, args_a), Applied(b, args_b)) => {
      if a != b || args_a.length() != args_b.length() {
        return false
      }
      for i in 0..<args_a.length() {
        if !is_assignable_to(args_a[i], args_b[i]) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
fn is_object_assignable(
  s_fields : Array[(@ast.TsType, @ast.TsType)],
  t_fields : Array[(@ast.TsType, @ast.TsType)],
) -> Bool {
  for t_field in t_fields {
    let (t_key, t_type) = t_field
    let mut matched = false
    for s_field in s_fields {
      let (s_key, s_type) = s_field
      if s_key == t_key {
        if !is_assignable_to(s_type, t_type) {
          return false
        }
        matched = true
        break
      }
    }
    if !matched {
      return false
    }
  }
  true
}

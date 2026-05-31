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
// Single-type-argument generic names whose element type an array satisfies:
// `T[]` is assignable to each of these when the element types are compatible.
fn is_array_like_iterable_name(name : String) -> Bool {
  match name {
    "Iterable"
    | "IterableIterator"
    | "ArrayLike"
    | "ReadonlyArray"
    | "ConcatArray"
    | "RelativeIndexable" => true
    _ => false
  }
}

///|
// Position of the single `Rest(...)` element inside a tuple, if any. TS
// allows at most one variadic element per tuple type (e.g. `[A, ...B[], C]`).
fn tuple_rest_index(items : Array[@ast.TsType]) -> Int? {
  for i in 0..<items.length() {
    match items[i] {
      Rest(_) => return Some(i)
      _ => ()
    }
  }
  None
}

///|
// Element type a variadic tuple slot iterates over. `Rest(Array(T))` and
// `Rest(Tuple(...))` are the parser shapes; we strip the outer `Rest` and
// (for arrays) one level of element wrapping. Returns `None` when the
// inner shape is not a plain array — in that case we can't widen middle
// elements against it.
fn rest_element_type(t : @ast.TsType) -> @ast.TsType? {
  match t {
    Rest(Array(inner)) => Some(inner)
    Rest(Applied(name, [inner])) =>
      if is_array_like_iterable_name(name) || name == "Array" {
        Some(inner)
      } else {
        None
      }
    _ => None
  }
}

///|
// TS tuple assignability with variadic-element support. The variadic
// element may appear at any single position in either tuple; we handle
// the common cases by aligning the fixed prefix/suffix of both sides and
// distributing leftover source elements against the target's rest slot.
fn tuple_assignable(
  s_items : Array[@ast.TsType],
  t_items : Array[@ast.TsType],
  bivariant_params : Bool,
) -> Bool {
  let s_rest = tuple_rest_index(s_items)
  let t_rest = tuple_rest_index(t_items)
  match (s_rest, t_rest) {
    (None, None) => {
      if s_items.length() != t_items.length() {
        return false
      }
      for i in 0..<s_items.length() {
        if !is_assignable_to_inner(s_items[i], t_items[i], bivariant_params) {
          return false
        }
      }
      true
    }
    (None, Some(ri)) => {
      // Fixed-length source flowing into a variadic target slot.
      let prefix = ri
      let suffix = t_items.length() - ri - 1
      if s_items.length() < prefix + suffix {
        return false
      }
      for i in 0..<prefix {
        if !is_assignable_to_inner(s_items[i], t_items[i], bivariant_params) {
          return false
        }
      }
      for i in 0..<suffix {
        let s_idx = s_items.length() - suffix + i
        let t_idx = ri + 1 + i
        if !is_assignable_to_inner(
            s_items[s_idx],
            t_items[t_idx],
            bivariant_params,
          ) {
          return false
        }
      }
      match rest_element_type(t_items[ri]) {
        Some(rest_inner) =>
          for i in prefix..<(s_items.length() - suffix) {
            if !is_assignable_to_inner(s_items[i], rest_inner, bivariant_params) {
              return false
            }
          }
        None =>
          // Rest slot is not a plain array — only safe when no source
          // elements need to be distributed into it.
          if s_items.length() != prefix + suffix {
            return false
          }
      }
      true
    }
    (Some(ri), Some(rj)) => {
      // Both sides variadic. Require matching prefix/suffix lengths and
      // identical rest position so the existing pointwise rule applies.
      if s_items.length() != t_items.length() || ri != rj {
        return false
      }
      for i in 0..<s_items.length() {
        if !is_assignable_to_inner(s_items[i], t_items[i], bivariant_params) {
          return false
        }
      }
      true
    }
    (Some(_), None) =>
      // Variadic source flowing into a fixed target: source length is
      // unknown at the type level, so we conservatively reject. Real TS
      // would allow this when the variadic slot resolves to a fixed
      // tuple, but the parser already flattens those.
      false
  }
}

///|
// TS function-parameter arity rule: source may declare fewer parameters
// than target (caller-side extras are simply ignored by the source
// implementation). If source ends with a `Rest(...)` parameter, source
// can absorb any number of trailing args ≥ its fixed prefix length.
// Per-position variance is contravariant in strict mode, bivariant when
// requested.
fn func_params_assignable(
  s_params : Array[@ast.TsType],
  t_params : Array[@ast.TsType],
  bivariant_params : Bool,
) -> Bool {
  let s_len = s_params.length()
  let t_len = t_params.length()
  let s_trailing_rest = s_len > 0 &&
    (match s_params[s_len - 1] {
      Rest(_) => true
      _ => false
    })
  let s_fixed = if s_trailing_rest { s_len - 1 } else { s_len }
  if s_trailing_rest {
    if t_len < s_fixed {
      return false
    }
  } else if t_len < s_len {
    return false
  }
  let shared = if s_trailing_rest { t_len.min(s_fixed) } else { s_len }
  fn variance_ok(a, b) {
    if bivariant_params {
      is_assignable_to_inner(a, b, bivariant_params) ||
      is_assignable_to_inner(b, a, bivariant_params)
    } else {
      is_assignable_to_inner(b, a, bivariant_params)
    }
  }

  for i in 0..<shared {
    if !variance_ok(s_params[i], t_params[i]) {
      return false
    }
  }
  // Source has a trailing rest: target's tail params must each flow into
  // the rest's element type (contravariantly). When the rest is not a
  // plain array, only an exact-length match is safe.
  if s_trailing_rest {
    let rest_slot = s_params[s_len - 1]
    let rest_elem = rest_element_type(rest_slot)
    match rest_elem {
      Some(elem) =>
        for i in s_fixed..<t_len {
          if !variance_ok(elem, t_params[i]) {
            return false
          }
        }
      None => if t_len != s_fixed { return false }
    }
  }
  true
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
    // Template literal types are a subtype of string (and of each other when
    // they resolve to the same string set, which we approximate as true when
    // both are TemplateLiteralType — a conservative over-approximation).
    (TemplateLiteralType(_, _), String_) => true
    (TemplateLiteralType(_, _), Literal(_)) => false
    (TemplateLiteralType(s_parts, s_args), TemplateLiteralType(t_parts, t_args)) =>
      s_parts == t_parts &&
      s_args.length() == t_args.length() &&
      ({
        let mut ok = true
        for i in 0..<s_args.length() {
          if !is_assignable_to_inner(s_args[i], t_args[i], bivariant_params) {
            ok = false
            break
          }
        }
        ok
      })
    (NumberLiteral(_), Number) => true
    (BigIntLiteral(_), BigInt) => true
    (BooleanLiteral(_), Boolean) => true
    // Arrays / typed arrays are iterable: `T[]` is assignable to
    // `Iterable<T>` / `IterableIterator<T>` / `ArrayLike<T>` and the
    // `ReadonlyArray<T>` form. Element type is covariant.
    (Array(s_inner), Applied(t_name, [t_inner])) =>
      if is_array_like_iterable_name(t_name) {
        is_assignable_to_inner(s_inner, t_inner, bivariant_params)
      } else {
        false
      }
    // Compound covariance/contravariance.
    (Array(s_inner), Array(t_inner)) =>
      is_assignable_to_inner(s_inner, t_inner, bivariant_params)
    // Tuples are iterable: `[A, B]` is assignable to `Iterable<A | B>` etc.
    // The element type is the union of the tuple's slot types.
    (Tuple(s_items), Applied(t_name, [t_inner])) =>
      if is_array_like_iterable_name(t_name) {
        s_items
        .iter()
        .all(fn(it) { is_assignable_to_inner(it, t_inner, bivariant_params) })
      } else {
        false
      }
    (Tuple(s_items), Tuple(t_items)) =>
      tuple_assignable(s_items, t_items, bivariant_params)
    // Rest parameter types: `...args: T[]` — delegate to the inner array type.
    (Rest(s), Rest(t)) => is_assignable_to_inner(s, t, bivariant_params)
    (Rest(s), Array(t)) => is_assignable_to_inner(s, t, bivariant_params)
    (Array(s), Rest(t)) => is_assignable_to_inner(s, t, bivariant_params)
    // Constructor types: `new (...) => T`. Abstract constructors are a
    // subtype of non-abstract constructors (conservative approximation).
    (Constructor(s_params, s_ret, _), Constructor(t_params, t_ret, _)) => {
      if s_params.length() != t_params.length() {
        return false
      }
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
      is_assignable_to_inner(s_ret, t_ret, bivariant_params)
    }
    // A constructor type is callable as a function (via Reflect.construct etc.)
    (Constructor(s_params, s_ret, _), Func(t_params, t_ret)) => {
      if s_params.length() != t_params.length() {
        return false
      }
      for i in 0..<s_params.length() {
        if !is_assignable_to_inner(t_params[i], s_params[i], bivariant_params) {
          return false
        }
      }
      is_assignable_to_inner(s_ret, t_ret, bivariant_params)
    }
    (Func(s_params, s_ret), Func(t_params, t_ret)) => {
      if !func_params_assignable(s_params, t_params, bivariant_params) {
        return false
      }
      // Covariant return.
      is_assignable_to_inner(s_ret, t_ret, bivariant_params)
    }
    (Object(s_fields), Object(t_fields)) =>
      is_object_assignable_inner(s_fields, t_fields, bivariant_params)
    // Struct types are structurally compatible with Object types and each other.
    (Struct(_, s_fields), Struct(_, t_fields)) => {
      let s_obj = struct_fields_to_object(s_fields)
      let t_obj = struct_fields_to_object(t_fields)
      is_object_assignable_inner(s_obj, t_obj, bivariant_params)
    }
    (Struct(_, s_fields), Object(t_fields)) => {
      let s_obj = struct_fields_to_object(s_fields)
      is_object_assignable_inner(s_obj, t_fields, bivariant_params)
    }
    (Object(s_fields), Struct(_, t_fields)) => {
      let t_obj = struct_fields_to_object(t_fields)
      is_object_assignable_inner(s_fields, t_obj, bivariant_params)
    }
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
fn struct_fields_to_object(
  fields : Array[(String, @ast.TsType)],
) -> Array[(@ast.TsType, @ast.TsType)] {
  let out : Array[(@ast.TsType, @ast.TsType)] = []
  for f in fields {
    out.push((@ast.TsType::Literal(f.0), f.1))
  }
  out
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

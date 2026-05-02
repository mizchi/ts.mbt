// Structural classification helpers shared by parser, bridge generator, and
// future type-checking passes. They operate purely on @ast.TsType.

///|
// True iff `type_` is `Named(n)` or `Applied(n, _)` with `n` in `names`.
pub fn type_is_named(type_ : @ast.TsType, names : Array[String]) -> Bool {
  match type_ {
    Named(name) | Applied(name, _) => names.contains(name)
    _ => false
  }
}

///|
// True iff `type_` directly is one of `names` or contains a Union member that
// is. Does not recurse into Array/Tuple/Object/Func — by design, since callers
// typically use this for "this top-level form references X".
pub fn type_contains_named(type_ : @ast.TsType, names : Array[String]) -> Bool {
  if type_is_named(type_, names) {
    return true
  }
  match type_ {
    Union(items) => {
      for item in items {
        if type_contains_named(item, names) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
// True iff `type_` is a string-like primitive (`String_` or `Literal(_)`) or a
// Union with a string-like member. Recurses only through Union — matches the
// "this top-level form references string" pattern used by the bridge.
pub fn type_contains_string(type_ : @ast.TsType) -> Bool {
  match type_ {
    String_ | Literal(_) => true
    Union(items) => {
      for item in items {
        if type_contains_string(item) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
// True iff `type_` carries a boolean primitive somewhere in the typical
// containers. Unlike `type_contains_string`, this recurses through
// Union / Intersection / Tuple, plus through `Array` and `Promise<…>` /
// `PromiseLike<…>` payloads — boolean returns are interesting wherever
// they show up in the bridge's flow.
pub fn type_contains_boolean(type_ : @ast.TsType) -> Bool {
  match type_ {
    Boolean | BooleanLiteral(_) => true
    Union(items) | Intersection(items) | Tuple(items) => {
      for item in items {
        if type_contains_boolean(item) {
          return true
        }
      }
      false
    }
    Array(inner)
    | Applied("Promise", [inner])
    | Applied("PromiseLike", [inner]) => type_contains_boolean(inner)
    _ => false
  }
}

///|
// True iff `type_` is exactly a string-literal type or a Union whose every
// member is a string literal. Empty unions are rejected.
pub fn is_string_literal_union(type_ : @ast.TsType) -> Bool {
  match type_ {
    Literal(_) => true
    Union(items) => {
      if items.length() == 0 {
        return false
      }
      for item in items {
        match item {
          Literal(_) => ()
          _ => return false
        }
      }
      true
    }
    _ => false
  }
}

///|
// True iff `type_` is a `string[]` shape (`Array(String_-like)` or
// `Array<...>` / `ReadonlyArray<...>` of string-like) or a Union containing
// such a member.
pub fn type_contains_string_array(type_ : @ast.TsType) -> Bool {
  match type_ {
    Array(inner) => type_contains_string(inner)
    Applied("Array", [inner]) | Applied("ReadonlyArray", [inner]) =>
      type_contains_string(inner)
    Union(items) => {
      for item in items {
        if type_contains_string_array(item) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
pub fn is_empty_object_type(type_ : @ast.TsType) -> Bool {
  match type_ {
    Object(fields) => fields.length() == 0
    _ => false
  }
}

///|
pub fn is_simple_primitive_type(t : @ast.TsType) -> Bool {
  match t {
    Number
    | Int
    | Boolean
    | String_
    | Void
    | BigInt
    | Symbol
    | Null
    | Undefined => true
    _ => false
  }
}

///|
pub fn normalize_literal_type(type_ : @ast.TsType) -> @ast.TsType {
  match type_ {
    Literal(_) => String_
    NumberLiteral(_) => Number
    BigIntLiteral(_) => BigInt
    BooleanLiteral(_) => Boolean
    _ => type_
  }
}

///|
pub fn reduce_uniform_union(t : @ast.TsType) -> @ast.TsType {
  match t {
    Union(items) => {
      if items.length() == 0 {
        return t
      }
      let reduced : Array[@ast.TsType] = []
      for it in items {
        reduced.push(reduce_uniform_union(it))
      }
      let first = reduced[0]
      if !is_simple_primitive_type(first) {
        return Union(reduced)
      }
      let mut all_same = true
      for r in reduced {
        if r != first {
          all_same = false
          break
        }
      }
      if all_same {
        first
      } else {
        Union(reduced)
      }
    }
    _ => t
  }
}

///|
// Inspect a Union and decide whether it can be represented as
// `inner` (with `is_optional` indicating Null/Undefined membership). Returns
// None for unions that cannot be collapsed.
pub fn classify_optional_like_union(
  type_ : @ast.TsType,
) -> (@ast.TsType, Bool)? {
  match type_ {
    Union(items) => {
      let mut concrete : @ast.TsType? = None
      let mut has_any = false
      let mut is_optional = false
      let mut has_conflicting_concrete = false
      let mut has_error_member = false
      for item in items {
        match item {
          Any => has_any = true
          Undefined | Null => is_optional = true
          Named("Error") => has_error_member = true
          _ => {
            let normalized = normalize_literal_type(item)
            match concrete {
              Some(existing) =>
                if existing != normalized {
                  has_conflicting_concrete = true
                }
              None => concrete = Some(normalized)
            }
          }
        }
      }
      if has_error_member && concrete is None {
        concrete = Some(Named("Error"))
      }
      if has_conflicting_concrete {
        if is_optional {
          Some((Any, true))
        } else {
          None
        }
      } else {
        match concrete {
          Some(inner) =>
            if has_any {
              if is_optional {
                Some((Any, true))
              } else {
                None
              }
            } else {
              Some((inner, is_optional))
            }
          None => if has_any { Some((Any, is_optional)) } else { None }
        }
      }
    }
    _ => None
  }
}

///|
// Inspect an Intersection and return a single transparent component if the
// other components are empty `{}` or compatible primitives.
pub fn classify_transparent_intersection(type_ : @ast.TsType) -> @ast.TsType? {
  match type_ {
    Intersection(items) => {
      let concrete : Array[@ast.TsType] = []
      let named_constraints : Array[@ast.TsType] = []
      for item in items {
        if !is_empty_object_type(item) {
          let reduced = reduce_uniform_union(item)
          concrete.push(reduced)
          match reduced {
            Named(_) | Applied(_, _) => named_constraints.push(reduced)
            _ => ()
          }
        }
      }
      if concrete.length() == 1 {
        Some(concrete[0])
      } else if named_constraints.length() == 1 {
        Some(named_constraints[0])
      } else if concrete.length() > 0 && is_simple_primitive_type(concrete[0]) {
        let first = concrete[0]
        let mut all_same = true
        for c in concrete {
          if c != first {
            all_same = false
            break
          }
        }
        if all_same {
          Some(first)
        } else {
          None
        }
      } else {
        None
      }
    }
    _ => None
  }
}

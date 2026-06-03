// Aggregator that recursively normalizes a type using every locally-decidable
// simplification: IndexedAccess resolution against structural sources, union
// flatten + dedup + subsumption, transparent intersection collapse, and
// child-recursion. Idempotent. The base `simplify_type` does not consult any
// resolver; the `_with(_generics)?` variants pre-expand aliases first so
// IndexedAccess and Conditional reductions can see through Named/Applied
// references.

///|
pub fn simplify_type(type_ : @ast.TsType) -> @ast.TsType {
  // Recurse into children first, then apply local rewrites at the root.
  let recursed : @ast.TsType = match type_ {
    Array(inner) => Array(simplify_type(inner))
    Tuple(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(simplify_type(it))
      }
      Tuple(out)
    }
    Rest(inner) => Rest(simplify_type(inner))
    Object(fields) => {
      let out : Array[(@ast.TsType, @ast.TsType)] = []
      for f in fields {
        out.push((simplify_type(f.0), simplify_type(f.1)))
      }
      Object(out)
    }
    Struct(name, fields) => {
      let out : Array[(String, @ast.TsType)] = []
      for f in fields {
        out.push((f.0, simplify_type(f.1)))
      }
      Struct(name, out)
    }
    Func(params, ret) => {
      let out : Array[@ast.TsType] = []
      for p in params {
        out.push(simplify_type(p))
      }
      Func(out, simplify_type(ret))
    }
    Constructor(params, ret, is_abstract) => {
      let out : Array[@ast.TsType] = []
      for p in params {
        out.push(simplify_type(p))
      }
      Constructor(out, simplify_type(ret), is_abstract)
    }
    Applied(name, args) => {
      let out : Array[@ast.TsType] = []
      for a in args {
        out.push(simplify_type(a))
      }
      Applied(name, out)
    }
    Union(items) => {
      let inner : Array[@ast.TsType] = []
      for it in items {
        inner.push(simplify_type(it))
      }
      // Dedup + subsumption + flatten via simplify_union.
      let collapsed = simplify_union(inner)
      if collapsed.length() == 0 {
        Never
      } else if collapsed.length() == 1 {
        collapsed[0]
      } else {
        Union(collapsed)
      }
    }
    Intersection(items) => {
      let inner : Array[@ast.TsType] = []
      for it in items {
        inner.push(simplify_type(it))
      }
      // Try transparent collapse on the recursed Intersection.
      match classify_transparent_intersection(Intersection(inner)) {
        Some(t) => t
        None => Intersection(inner)
      }
    }
    Conditional(check, extends_, t_branch, f_branch) => {
      let s_check = simplify_type(check)
      let s_extends = simplify_type(extends_)
      let s_t = simplify_type(t_branch)
      let s_f = simplify_type(f_branch)
      // Non-distributive conditional pattern `[T] extends [U] ? X : Y`:
      // both sides are length-1 tuples, which TypeScript uses to opt
      // out of distribution. Unwrap and check the inner pair directly.
      match (s_check, s_extends) {
        (Tuple([inner_check]), Tuple([inner_extends])) =>
          return match extends_decision(inner_check, inner_extends) {
            Some(true) => s_t
            Some(false) => s_f
            None =>
              Conditional(
                Tuple([inner_check]),
                Tuple([inner_extends]),
                s_t,
                s_f,
              )
          }
        _ => ()
      }
      // Distributive conditional: `(A | B) extends T ? X : Y`
      // -> `(A extends T ? X : Y) | (B extends T ? X : Y)`. Each leaf is
      // resolved through `extends_decision`; only commit the distribution
      // when every leaf resolves definitively, otherwise keep the original
      // conditional so callers can retry after additional substitution.
      match s_check {
        Union(items) => {
          let results : Array[@ast.TsType] = []
          let mut all_resolved = true
          for item in items {
            match extends_decision(item, s_extends) {
              Some(true) => results.push(s_t)
              Some(false) => results.push(s_f)
              None => {
                all_resolved = false
                break
              }
            }
          }
          if all_resolved {
            let collapsed = simplify_union(results)
            if collapsed.length() == 0 {
              Never
            } else if collapsed.length() == 1 {
              collapsed[0]
            } else {
              Union(collapsed)
            }
          } else {
            Conditional(s_check, s_extends, s_t, s_f)
          }
        }
        _ =>
          // Direct decision for a non-union check.
          match extends_decision(s_check, s_extends) {
            Some(true) => s_t
            Some(false) => s_f
            None => Conditional(s_check, s_extends, s_t, s_f)
          }
      }
    }
    IndexedAccess(base, key) =>
      IndexedAccess(simplify_type(base), simplify_type(key))
    Keyof(inner) => Keyof(simplify_type(inner))
    MappedType(key_param, source, value, optional) =>
      MappedType(key_param, simplify_type(source), value, optional)
    MappedTypeRemap(key_param, source, remap, value, optional) =>
      MappedTypeRemap(key_param, simplify_type(source), remap, value, optional)
    TemplateLiteralType(parts, args) => {
      let inner : Array[@ast.TsType] = []
      for a in args {
        inner.push(simplify_type(a))
      }
      TemplateLiteralType(parts, inner)
    }
    _ => type_
  }
  // Resolve IndexedAccess / Keyof / MappedType / TemplateLiteralType
  // locally if the recursed base now permits it.
  match recursed {
    IndexedAccess(_, _) => simplify_indexed_access(recursed)
    Keyof(_) => simplify_keyof(recursed)
    MappedType(_, _, _, _) => simplify_mapped_type(recursed)
    MappedTypeRemap(_, _, _, _, _) => simplify_mapped_type_remap(recursed)
    TemplateLiteralType(_, _) => simplify_template_literal(recursed)
    Applied(name, args) =>
      match simplify_string_intrinsic(name, args) {
        Some(t) => t
        None => recursed
      }
    _ => recursed
  }
}

///|
/// `keyof T` evaluator. Resolves to a union of `Literal(name)` keys when
/// the operand is a struct or an object literal whose keys are themselves
/// string literals; preserved otherwise so later passes can retry after
/// substitution.
fn simplify_keyof(t : @ast.TsType) -> @ast.TsType {
  match t {
    Keyof(inner) =>
      match inner {
        Struct(_, fields) => {
          let keys : Array[@ast.TsType] = []
          for f in fields {
            keys.push(Literal(f.0))
          }
          if keys.length() == 0 {
            Never
          } else if keys.length() == 1 {
            keys[0]
          } else {
            Union(keys)
          }
        }
        Object(fields) => {
          let keys : Array[@ast.TsType] = []
          let mut all_literal = true
          for f in fields {
            match f.0 {
              Literal(_) => keys.push(f.0)
              _ => {
                all_literal = false
                break
              }
            }
          }
          if !all_literal {
            return t
          }
          if keys.length() == 0 {
            Never
          } else if keys.length() == 1 {
            keys[0]
          } else {
            Union(keys)
          }
        }
        _ => t
      }
    _ => t
  }
}

///|
/// Strip `Undefined` from a type produced by a mapped-type `-?` modifier.
/// Walks `Applied("__tsmbt_strip_undef", [t])` and removes the optional
/// branch; transparent on anything else.
fn unwrap_strip_undef(t : @ast.TsType) -> (@ast.TsType, Bool) {
  match t {
    Applied("__tsmbt_strip_undef", [inner]) => (inner, true)
    _ => (t, false)
  }
}

///|
/// Remove `Undefined` / `Null` (only undefined for `-?`) from a value
/// type. Used after per-key substitution when the mapped type carries
/// a `-?` strip marker.
fn strip_undefined_from(t : @ast.TsType) -> @ast.TsType {
  match t {
    Union(items) => {
      let kept : Array[@ast.TsType] = []
      for it in items {
        match it {
          Undefined => continue
          _ => kept.push(it)
        }
      }
      if kept.length() == 0 {
        Never
      } else if kept.length() == 1 {
        kept[0]
      } else {
        Union(kept)
      }
    }
    Undefined => Never
    _ => t
  }
}

///|
/// `{ [K in U]: V }` evaluator. Substitutes `K` with each literal in `U`
/// when the source resolves to a finite literal union (or single literal,
/// or `Keyof Struct(...)`), producing an `Object(fields)`. Preserved
/// otherwise so later passes can retry after substitution.
fn simplify_mapped_type(t : @ast.TsType) -> @ast.TsType {
  match t {
    MappedType(key_param, source, value, optional) => {
      let keys : Array[String] = match collect_mapped_source_keys(source) {
        Some(ks) => ks
        None => return t
      }
      let (raw_value, strip) = unwrap_strip_undef(value)
      let fields : Array[(@ast.TsType, @ast.TsType)] = []
      for k in keys {
        let substituted = substitute_named(raw_value, key_param, Literal(k))
        let field_type = simplify_type(substituted)
        let stripped = if strip {
          strip_undefined_from(field_type)
        } else {
          field_type
        }
        let final_type = if optional {
          @ast.TsType::Union([stripped, Undefined])
        } else {
          stripped
        }
        fields.push((Literal(k), final_type))
      }
      Object(fields)
    }
    _ => t
  }
}

///|
/// `{ [K in U as R]: V }` evaluator. When `U` resolves to a finite literal
/// set, substitute `K` -> `Literal(k)` inside both `R` and `V`. The
/// produced key set per source key comes from `resolve_literal_value_set`
/// of the simplified remap; `Never` (TS-style "filter this key out") drops
/// the entry; one or more literals emit one field each. Falls back to the
/// original variant when the source or any remap result is opaque.
fn simplify_mapped_type_remap(t : @ast.TsType) -> @ast.TsType {
  match t {
    MappedTypeRemap(key_param, source, remap, value, optional) => {
      let keys : Array[String] = match collect_mapped_source_keys(source) {
        Some(ks) => ks
        None => return t
      }
      let fields : Array[(@ast.TsType, @ast.TsType)] = []
      for k in keys {
        let remapped = simplify_type(
          substitute_named(remap, key_param, Literal(k)),
        )
        // `Never` filters this key out entirely (TS exclude pattern).
        let new_keys : Array[String] = match remapped {
          Never => continue
          _ =>
            match resolve_literal_value_set(remapped) {
              Some(ks) => ks
              None => return t
            }
        }
        let substituted_value = substitute_named(value, key_param, Literal(k))
        let field_type = simplify_type(substituted_value)
        let final_type = if optional {
          @ast.TsType::Union([field_type, Undefined])
        } else {
          field_type
        }
        for new_k in new_keys {
          fields.push((Literal(new_k), final_type))
        }
      }
      Object(fields)
    }
    _ => t
  }
}

///|
/// Try to read a finite list of literal key names out of a mapped-type
/// source. Recognizes `Literal(name)`, `Union([Literal(...), ...])`, and
/// `Keyof Struct(_, fields)` shapes; returns `None` for anything that
/// would require runtime-unbounded enumeration (`String_`, `Number`,
/// opaque `Named`, etc.).
fn collect_mapped_source_keys(source : @ast.TsType) -> Array[String]? {
  match source {
    Literal(name) => Some([name])
    Union(items) => {
      let out : Array[String] = []
      for it in items {
        match it {
          Literal(name) => out.push(name)
          _ => return None
        }
      }
      Some(out)
    }
    Keyof(inner) =>
      match inner {
        Struct(_, fields) => {
          let out : Array[String] = []
          for f in fields {
            out.push(f.0)
          }
          Some(out)
        }
        Object(fields) => {
          let out : Array[String] = []
          for f in fields {
            match f.0 {
              Literal(name) => out.push(name)
              _ => return None
            }
          }
          Some(out)
        }
        _ => None
      }
    _ => None
  }
}

///|
/// Replace every `Named(name)` reference inside `t` with `replacement`.
/// Used by the mapped-type evaluator to bind the key parameter to each
/// concrete key, and by tests; the substitution does not look through
/// alias bodies.
fn substitute_named(
  t : @ast.TsType,
  name : String,
  replacement : @ast.TsType,
) -> @ast.TsType {
  match t {
    Named(n) if n == name => replacement
    Array(inner) => Array(substitute_named(inner, name, replacement))
    Tuple(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(substitute_named(it, name, replacement))
      }
      Tuple(out)
    }
    Rest(inner) => Rest(substitute_named(inner, name, replacement))
    Object(fields) => {
      let out : Array[(@ast.TsType, @ast.TsType)] = []
      for f in fields {
        out.push(
          (
            substitute_named(f.0, name, replacement),
            substitute_named(f.1, name, replacement),
          ),
        )
      }
      Object(out)
    }
    Func(params, ret) => {
      let out : Array[@ast.TsType] = []
      for p in params {
        out.push(substitute_named(p, name, replacement))
      }
      Func(out, substitute_named(ret, name, replacement))
    }
    Constructor(params, ret, is_abstract) => {
      let out : Array[@ast.TsType] = []
      for p in params {
        out.push(substitute_named(p, name, replacement))
      }
      Constructor(out, substitute_named(ret, name, replacement), is_abstract)
    }
    Union(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(substitute_named(it, name, replacement))
      }
      Union(out)
    }
    Intersection(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(substitute_named(it, name, replacement))
      }
      Intersection(out)
    }
    Conditional(check, ext, t_branch, f_branch) =>
      Conditional(
        substitute_named(check, name, replacement),
        substitute_named(ext, name, replacement),
        substitute_named(t_branch, name, replacement),
        substitute_named(f_branch, name, replacement),
      )
    Applied(n, args) => {
      let out : Array[@ast.TsType] = []
      for a in args {
        out.push(substitute_named(a, name, replacement))
      }
      Applied(n, out)
    }
    IndexedAccess(base, key) =>
      IndexedAccess(
        substitute_named(base, name, replacement),
        substitute_named(key, name, replacement),
      )
    Keyof(inner) => Keyof(substitute_named(inner, name, replacement))
    MappedType(inner_key, _, _, _) if inner_key == name => t
    MappedType(inner_key, source, value, optional) =>
      MappedType(
        inner_key,
        substitute_named(source, name, replacement),
        substitute_named(value, name, replacement),
        optional,
      )
    MappedTypeRemap(inner_key, _, _, _, _) if inner_key == name => t
    MappedTypeRemap(inner_key, source, remap, value, optional) =>
      MappedTypeRemap(
        inner_key,
        substitute_named(source, name, replacement),
        substitute_named(remap, name, replacement),
        substitute_named(value, name, replacement),
        optional,
      )
    TemplateLiteralType(parts, args) => {
      let out : Array[@ast.TsType] = []
      for a in args {
        out.push(substitute_named(a, name, replacement))
      }
      TemplateLiteralType(parts, out)
    }
    _ => t
  }
}

///|
/// `Capitalize` / `Uncapitalize` / `Uppercase` / `Lowercase` intrinsic
/// applied to a single string value. Returns `None` for any other name
/// so callers can keep the original `Applied(...)` shape.
fn apply_string_intrinsic(intrinsic : String, value : String) -> String? {
  if value.length() == 0 {
    return Some(value)
  }
  let head = value[0].unsafe_to_char()
  let rest = value[1:].to_owned()
  match intrinsic {
    "Capitalize" =>
      if head >= 'a' && head <= 'z' {
        Some((head.to_int() - 32).unsafe_to_char().to_string() + rest)
      } else {
        Some(value)
      }
    "Uncapitalize" =>
      if head >= 'A' && head <= 'Z' {
        Some((head.to_int() + 32).unsafe_to_char().to_string() + rest)
      } else {
        Some(value)
      }
    "Uppercase" => Some(value.to_upper())
    "Lowercase" => Some(value.to_lower())
    _ => None
  }
}

///|
/// Recognize the four TypeScript intrinsic string-mapping type names.
fn is_string_intrinsic_name(name : String) -> Bool {
  name == "Uppercase" ||
  name == "Lowercase" ||
  name == "Capitalize" ||
  name == "Uncapitalize"
}

///|
/// Simplify a standalone intrinsic string-mapping application such as
/// `Uppercase<"foo">` -> `"FOO"` or `Capitalize<"a" | "b">` -> `"A" | "B"`.
/// Distributes over a finite union of literals exactly like TypeScript.
/// Returns `None` when the argument is not a finite literal set so the
/// caller keeps the original `Applied(...)` for a later retry. Outside of
/// template-literal interpolation this is the only place a bare
/// `Uppercase<...>` etc. gets folded.
fn simplify_string_intrinsic(
  name : String,
  args : Array[@ast.TsType],
) -> @ast.TsType? {
  if !is_string_intrinsic_name(name) {
    return None
  }
  match args {
    [arg] =>
      match resolve_literal_value_set(arg) {
        Some(values) => {
          let mapped : Array[@ast.TsType] = []
          for v in values {
            match apply_string_intrinsic(name, v) {
              Some(new_v) => mapped.push(Literal(new_v))
              None => return None
            }
          }
          if mapped.length() == 0 {
            Some(Never)
          } else if mapped.length() == 1 {
            Some(mapped[0])
          } else {
            Some(Union(mapped))
          }
        }
        None => None
      }
    _ => None
  }
}

///|
/// Resolve a type to its enumerated string-literal value set when it is a
/// literal, a finite union of literals, or an intrinsic string mapping
/// (`Capitalize<...>` etc.) applied to one of those shapes. Used by the
/// template-literal simplifier; returns `None` for anything that would
/// require unbounded enumeration.
fn resolve_literal_value_set(type_ : @ast.TsType) -> Array[String]? {
  match type_ {
    Literal(value) => Some([value])
    Union(items) => {
      let out : Array[String] = []
      for it in items {
        match it {
          Literal(v) => out.push(v)
          _ => return None
        }
      }
      Some(out)
    }
    Applied(name, [inner]) =>
      match resolve_literal_value_set(inner) {
        Some(values) => {
          let mapped : Array[String] = []
          for v in values {
            match apply_string_intrinsic(name, v) {
              Some(new_v) => mapped.push(new_v)
              None => return None
            }
          }
          Some(mapped)
        }
        None => None
      }
    TemplateLiteralType(_, _) =>
      match simplify_template_literal(type_) {
        Union(items) => {
          let out : Array[String] = []
          for it in items {
            match it {
              Literal(v) => out.push(v)
              _ => return None
            }
          }
          Some(out)
        }
        Literal(v) => Some([v])
        _ => None
      }
    _ => None
  }
}

///|
/// Cartesian-product expansion of a `TemplateLiteralType(parts, args)` to
/// a finite union of `Literal(...)` values. When every interpolation
/// resolves to a finite literal value set, materialize the cross product;
/// otherwise preserve the template so a later pass can retry after
/// substitution.
fn simplify_template_literal(t : @ast.TsType) -> @ast.TsType {
  match t {
    TemplateLiteralType(parts, args) => {
      let arg_value_sets : Array[Array[String]] = []
      for a in args {
        match resolve_literal_value_set(a) {
          Some(values) => arg_value_sets.push(values)
          None => return t
        }
      }
      let mut accumulators : Array[String] = [parts[0]]
      for i in 0..<arg_value_sets.length() {
        let next_accumulators : Array[String] = []
        for prefix in accumulators {
          for value in arg_value_sets[i] {
            next_accumulators.push(prefix + value + parts[i + 1])
          }
        }
        accumulators = next_accumulators
      }
      let result : Array[@ast.TsType] = []
      for s in accumulators {
        result.push(Literal(s))
      }
      if result.length() == 0 {
        Never
      } else if result.length() == 1 {
        result[0]
      } else {
        Union(result)
      }
    }
    _ => t
  }
}

///|
pub fn simplify_type_with(
  type_ : @ast.TsType,
  resolve : (String) -> @ast.TsType?,
) -> @ast.TsType {
  simplify_type(expand_aliases(type_, resolve, []))
}

///|
pub fn simplify_type_with_generics(
  type_ : @ast.TsType,
  resolve : (String) -> AliasBinding?,
) -> @ast.TsType {
  simplify_type(expand_generic(type_, resolve, []))
}

///|
fn simplify_indexed_access(t : @ast.TsType) -> @ast.TsType {
  match t {
    IndexedAccess(base, key) => {
      let key_name = match key {
        Literal(name) => name
        _ => return Any
      }
      match base {
        Object(fields) => {
          for f in fields {
            match f.0 {
              Literal(field_name) => if field_name == key_name { return f.1 }
              _ => ()
            }
          }
          Any
        }
        Struct(_, fields) => {
          for f in fields {
            if f.0 == key_name {
              return f.1
            }
          }
          Any
        }
        // `(A | B)[K]` distributes to `A[K] | B[K]` (TS rule). The
        // resolved members feed `simplify_union` so duplicate /
        // subsumed literals collapse — common after distributing
        // `Shape[K]` over a discriminated-union alias.
        Union(members) => {
          let parts : Array[@ast.TsType] = []
          for m in members {
            parts.push(simplify_indexed_access(IndexedAccess(m, key)))
          }
          let collapsed = simplify_union(parts)
          if collapsed.length() == 0 {
            Never
          } else if collapsed.length() == 1 {
            collapsed[0]
          } else {
            Union(collapsed)
          }
        }
        _ => Any
      }
    }
    _ => t
  }
}

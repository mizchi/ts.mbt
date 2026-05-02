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
    Conditional(check, extends, t_branch, f_branch) =>
      Conditional(
        simplify_type(check),
        simplify_type(extends),
        simplify_type(t_branch),
        simplify_type(f_branch),
      )
    IndexedAccess(base, key) =>
      IndexedAccess(simplify_type(base), simplify_type(key))
    _ => type_
  }
  // Resolve IndexedAccess locally if the recursed base now permits it.
  match recursed {
    IndexedAccess(_, _) => simplify_indexed_access(recursed)
    _ => recursed
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
              Literal(field_name) =>
                if field_name == key_name {
                  return f.1
                }
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
        _ => Any
      }
    }
    _ => t
  }
}

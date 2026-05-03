// Alias-aware assignability. The resolver maps a `Named(n)` reference to the
// type body declared elsewhere; cycles short-circuit to `Any` so we never
// recurse forever on `type Loop = Loop`.

///|
pub fn is_assignable_to_with(
  source : @ast.TsType,
  target : @ast.TsType,
  resolve : (String) -> @ast.TsType?,
) -> Bool {
  let s = expand_aliases(source, resolve, [])
  let t = expand_aliases(target, resolve, [])
  is_assignable_to(s, t)
}

///|
// Walk a type and substitute `Named(n)` references with their resolver body
// when one is available. Tracks a per-walk visited list to break cycles —
// re-entering a name during expansion collapses to `Any`. Generic Applied
// references are left untouched because we do not do parameter substitution.
fn expand_aliases(
  type_ : @ast.TsType,
  resolve : (String) -> @ast.TsType?,
  visited : Array[String],
) -> @ast.TsType {
  match type_ {
    Named(name) =>
      if visited.contains(name) {
        Any
      } else {
        match resolve(name) {
          Some(body) => {
            visited.push(name)
            let expanded = expand_aliases(body, resolve, visited)
            let _ = visited.pop()
            expanded
          }
          None => type_
        }
      }
    Applied(name, args) => {
      let new_args : Array[@ast.TsType] = []
      for a in args {
        new_args.push(expand_aliases(a, resolve, visited))
      }
      Applied(name, new_args)
    }
    Array(inner) => Array(expand_aliases(inner, resolve, visited))
    Tuple(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(expand_aliases(it, resolve, visited))
      }
      Tuple(out)
    }
    Object(fields) => {
      let out : Array[(@ast.TsType, @ast.TsType)] = []
      for f in fields {
        out.push(
          (
            expand_aliases(f.0, resolve, visited),
            expand_aliases(f.1, resolve, visited),
          ),
        )
      }
      Object(out)
    }
    Struct(name, fields) => {
      let out : Array[(String, @ast.TsType)] = []
      for f in fields {
        out.push((f.0, expand_aliases(f.1, resolve, visited)))
      }
      Struct(name, out)
    }
    Func(params, ret) => {
      let new_params : Array[@ast.TsType] = []
      for p in params {
        new_params.push(expand_aliases(p, resolve, visited))
      }
      Func(new_params, expand_aliases(ret, resolve, visited))
    }
    Union(members) => {
      let out : Array[@ast.TsType] = []
      for m in members {
        out.push(expand_aliases(m, resolve, visited))
      }
      Union(out)
    }
    Intersection(members) => {
      let out : Array[@ast.TsType] = []
      for m in members {
        out.push(expand_aliases(m, resolve, visited))
      }
      Intersection(out)
    }
    Conditional(check, extends, t_branch, f_branch) =>
      Conditional(
        expand_aliases(check, resolve, visited),
        expand_aliases(extends, resolve, visited),
        expand_aliases(t_branch, resolve, visited),
        expand_aliases(f_branch, resolve, visited),
      )
    IndexedAccess(base, key) =>
      IndexedAccess(
        expand_aliases(base, resolve, visited),
        expand_aliases(key, resolve, visited),
      )
    _ => type_
  }
}

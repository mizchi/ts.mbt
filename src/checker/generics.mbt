// Generic-aware alias expansion. The simpler `is_assignable_to_with` resolver
// returns a body for plain `Named(n)` references; this variant additionally
// substitutes type parameters when expanding `Applied(n, args)`.

///|
pub(all) struct AliasBinding {
  type_params : Array[String]
  body : @ast.TsType
}

///|
pub fn is_assignable_to_with_generics(
  source : @ast.TsType,
  target : @ast.TsType,
  resolve : (String) -> AliasBinding?,
) -> Bool {
  let s = expand_generic(source, resolve, [])
  let t = expand_generic(target, resolve, [])
  is_assignable_to(s, t)
}

///|
fn expand_generic(
  type_ : @ast.TsType,
  resolve : (String) -> AliasBinding?,
  visited : Array[String],
) -> @ast.TsType {
  match type_ {
    Named(name) =>
      if visited.contains(name) {
        Any
      } else {
        match resolve(name) {
          Some(binding) =>
            // A 0-ary alias is just a type substitution with empty params.
            if binding.type_params.length() == 0 {
              visited.push(name)
              let expanded = expand_generic(binding.body, resolve, visited)
              let _ = visited.pop()
              expanded
            } else {
              type_
            }
          None => type_
        }
      }
    Applied(name, args) => {
      let resolved_args : Array[@ast.TsType] = []
      for a in args {
        resolved_args.push(expand_generic(a, resolve, visited))
      }
      if visited.contains(name) {
        return Any
      }
      match resolve(name) {
        Some(binding) =>
          if binding.type_params.length() == resolved_args.length() &&
            binding.type_params.length() > 0 {
            let bindings : Map[String, @ast.TsType] = {}
            for i in 0..<binding.type_params.length() {
              bindings[binding.type_params[i]] = resolved_args[i]
            }
            let substituted = substitute_params(binding.body, bindings)
            visited.push(name)
            let expanded = expand_generic(substituted, resolve, visited)
            let _ = visited.pop()
            expanded
          } else {
            // Arity mismatch — keep as opaque Applied with resolved args.
            Applied(name, resolved_args)
          }
        None => Applied(name, resolved_args)
      }
    }
    Array(inner) => Array(expand_generic(inner, resolve, visited))
    Tuple(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(expand_generic(it, resolve, visited))
      }
      Tuple(out)
    }
    Object(fields) => {
      let out : Array[(@ast.TsType, @ast.TsType)] = []
      for f in fields {
        out.push((
          expand_generic(f.0, resolve, visited),
          expand_generic(f.1, resolve, visited),
        ))
      }
      Object(out)
    }
    Struct(name, fields) => {
      let out : Array[(String, @ast.TsType)] = []
      for f in fields {
        out.push((f.0, expand_generic(f.1, resolve, visited)))
      }
      Struct(name, out)
    }
    Func(params, ret) => {
      let new_params : Array[@ast.TsType] = []
      for p in params {
        new_params.push(expand_generic(p, resolve, visited))
      }
      Func(new_params, expand_generic(ret, resolve, visited))
    }
    Union(members) => {
      let out : Array[@ast.TsType] = []
      for m in members {
        out.push(expand_generic(m, resolve, visited))
      }
      Union(out)
    }
    Intersection(members) => {
      let out : Array[@ast.TsType] = []
      for m in members {
        out.push(expand_generic(m, resolve, visited))
      }
      Intersection(out)
    }
    Conditional(check, extends, t_branch, f_branch) =>
      Conditional(
        expand_generic(check, resolve, visited),
        expand_generic(extends, resolve, visited),
        expand_generic(t_branch, resolve, visited),
        expand_generic(f_branch, resolve, visited),
      )
    IndexedAccess(base, key) =>
      IndexedAccess(
        expand_generic(base, resolve, visited),
        expand_generic(key, resolve, visited),
      )
    _ => type_
  }
}

///|
// Walk a type and replace `Named(name)` references whose names appear in the
// bindings map with the bound type. Other constructs are reconstructed
// recursively. Type parameters that do not appear in the map are left as-is
// (they may be in scope of an outer generic).
fn substitute_params(
  type_ : @ast.TsType,
  bindings : Map[String, @ast.TsType],
) -> @ast.TsType {
  match type_ {
    Named(name) =>
      match bindings.get(name) {
        Some(t) => t
        None => type_
      }
    Applied(name, args) => {
      let new_args : Array[@ast.TsType] = []
      for a in args {
        new_args.push(substitute_params(a, bindings))
      }
      Applied(name, new_args)
    }
    Array(inner) => Array(substitute_params(inner, bindings))
    Tuple(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(substitute_params(it, bindings))
      }
      Tuple(out)
    }
    Object(fields) => {
      let out : Array[(@ast.TsType, @ast.TsType)] = []
      for f in fields {
        out.push((
          substitute_params(f.0, bindings),
          substitute_params(f.1, bindings),
        ))
      }
      Object(out)
    }
    Struct(name, fields) => {
      let out : Array[(String, @ast.TsType)] = []
      for f in fields {
        out.push((f.0, substitute_params(f.1, bindings)))
      }
      Struct(name, out)
    }
    Func(params, ret) => {
      let new_params : Array[@ast.TsType] = []
      for p in params {
        new_params.push(substitute_params(p, bindings))
      }
      Func(new_params, substitute_params(ret, bindings))
    }
    Union(members) => {
      let out : Array[@ast.TsType] = []
      for m in members {
        out.push(substitute_params(m, bindings))
      }
      Union(out)
    }
    Intersection(members) => {
      let out : Array[@ast.TsType] = []
      for m in members {
        out.push(substitute_params(m, bindings))
      }
      Intersection(out)
    }
    Conditional(check, extends, t_branch, f_branch) =>
      // Distributive conditional: when the check side is a naked type
      // parameter `T` bound to a Union, distribute the conditional over each
      // member. Mirrors TS:
      //   type ToArray<T> = T extends X ? f(T) : g(T)
      //   ToArray<A | B> ≡ ToArray<A> | ToArray<B>
      match check {
        Named(name) =>
          match bindings.get(name) {
            Some(Union(members)) => {
              let branches : Array[@ast.TsType] = []
              for m in members {
                let scoped : Map[String, @ast.TsType] = {}
                for entry in bindings {
                  scoped[entry.0] = entry.1
                }
                scoped[name] = m
                branches.push(
                  Conditional(
                    m,
                    substitute_params(extends, scoped),
                    substitute_params(t_branch, scoped),
                    substitute_params(f_branch, scoped),
                  ),
                )
              }
              Union(branches)
            }
            _ =>
              Conditional(
                substitute_params(check, bindings),
                substitute_params(extends, bindings),
                substitute_params(t_branch, bindings),
                substitute_params(f_branch, bindings),
              )
          }
        _ =>
          Conditional(
            substitute_params(check, bindings),
            substitute_params(extends, bindings),
            substitute_params(t_branch, bindings),
            substitute_params(f_branch, bindings),
          )
      }
    IndexedAccess(base, key) =>
      IndexedAccess(
        substitute_params(base, bindings),
        substitute_params(key, bindings),
      )
    _ => type_
  }
}

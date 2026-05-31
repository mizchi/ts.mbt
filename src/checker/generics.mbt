// Generic-aware alias expansion. The simpler `is_assignable_to_with` resolver
// returns a body for plain `Named(n)` references; this variant additionally
// substitutes type parameters when expanding `Applied(n, args)`.

///|
// Build a `(String) -> AliasBinding?` resolver that combines:
//  - every `type X<...> = ...` declared in `module_`,
//  - the `standard_utility_types()` table when `include_standard` is true.
// Module aliases shadow the standard table on name conflicts so callers can
// override stdlib utility shapes per-module.
pub fn module_alias_resolver(
  module_ : @ast.TsModule,
  include_standard? : Bool = true,
) -> (String) -> AliasBinding? {
  let table : Map[String, AliasBinding] = if include_standard {
    standard_utility_types()
  } else {
    {}
  }
  for ta in module_.type_aliases {
    table[ta.name] = { type_params: ta.type_params, body: ta.type_ }
  }
  fn(name) { table.get(name) }
}

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
  // Expansion alone leaves mapped types / indexed access / keyof in the
  // body unevaluated; simplify reduces them against the now-concrete
  // struct/object shapes so utility types like `Partial` and `Pick`
  // produce comparable object shapes for the assignability rule.
  let s = simplify_type(expand_generic(source, resolve, []))
  let t = simplify_type(expand_generic(target, resolve, []))
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
              // Pre-simplify the bound argument: `Keyof(Struct(...))` reduces
              // to a `Union` of literals so the distributive-conditional
              // path in `substitute_params` can recognize a Union check and
              // expand utility types like `Exclude<keyof T, K>` correctly.
              bindings[binding.type_params[i]] = simplify_type(resolved_args[i])
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
        out.push(
          (
            expand_generic(f.0, resolve, visited),
            expand_generic(f.1, resolve, visited),
          ),
        )
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
    Keyof(inner) => Keyof(expand_generic(inner, resolve, visited))
    MappedType(key_param, source, value, optional) =>
      MappedType(
        key_param,
        expand_generic(source, resolve, visited),
        expand_generic(value, resolve, visited),
        optional,
      )
    MappedTypeRemap(key_param, source, remap, value, optional) =>
      MappedTypeRemap(
        key_param,
        expand_generic(source, resolve, visited),
        expand_generic(remap, resolve, visited),
        expand_generic(value, resolve, visited),
        optional,
      )
    Constructor(params, ret, is_abstract) => {
      let new_params : Array[@ast.TsType] = []
      for p in params {
        new_params.push(expand_generic(p, resolve, visited))
      }
      Constructor(
        new_params,
        expand_generic(ret, resolve, visited),
        is_abstract,
      )
    }
    Rest(inner) => Rest(expand_generic(inner, resolve, visited))
    TemplateLiteralType(parts, args) => {
      let new_args : Array[@ast.TsType] = []
      for a in args {
        new_args.push(expand_generic(a, resolve, visited))
      }
      TemplateLiteralType(parts, new_args)
    }
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
        out.push(
          (substitute_params(f.0, bindings), substitute_params(f.1, bindings)),
        )
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
    Keyof(inner) => Keyof(substitute_params(inner, bindings))
    MappedType(key_param, source, value, optional) => {
      // `key_param` is bound inside `value` (and `source` is computed
      // before the binder is in scope). Remove the binder from bindings
      // when substituting the value side so an outer `T` named the same
      // as the binder doesn't leak in.
      let inner_bindings = scoped_without(bindings, key_param)
      MappedType(
        key_param,
        substitute_params(source, bindings),
        substitute_params(value, inner_bindings),
        optional,
      )
    }
    MappedTypeRemap(key_param, source, remap, value, optional) => {
      let inner_bindings = scoped_without(bindings, key_param)
      MappedTypeRemap(
        key_param,
        substitute_params(source, bindings),
        substitute_params(remap, inner_bindings),
        substitute_params(value, inner_bindings),
        optional,
      )
    }
    Constructor(params, ret, is_abstract) => {
      let new_params : Array[@ast.TsType] = []
      for p in params {
        new_params.push(substitute_params(p, bindings))
      }
      Constructor(new_params, substitute_params(ret, bindings), is_abstract)
    }
    Rest(inner) => Rest(substitute_params(inner, bindings))
    TemplateLiteralType(parts, args) => {
      let new_args : Array[@ast.TsType] = []
      for a in args {
        new_args.push(substitute_params(a, bindings))
      }
      TemplateLiteralType(parts, new_args)
    }
    _ => type_
  }
}

///|
// Return a copy of `bindings` with `name` removed. Used to mask a binder
// in mapped-type bodies so an outer parameter with the same name does
// not shadow the local binding.
fn scoped_without(
  bindings : Map[String, @ast.TsType],
  name : String,
) -> Map[String, @ast.TsType] {
  let out : Map[String, @ast.TsType] = {}
  for entry in bindings {
    if entry.0 != name {
      out[entry.0] = entry.1
    }
  }
  out
}

// Structured assignability diagnostics. `check_assignable(s, t)` returns an
// empty array on success, or one or more `AssignabilityIssue` records pinning
// the location and reason for the rejection. Path breadcrumbs use a JS-like
// dotted notation:
//   ""          — the root of the relation
//   ".name"     — object field access
//   "[i]"       — tuple element index
//   ".param[i]" — i-th function parameter (contravariant)
//   ".return"   — function return type

///|
pub(all) struct AssignabilityIssue {
  path : String
  message : String
}

///|
pub fn check_assignable(
  source : @ast.TsType,
  target : @ast.TsType,
) -> Array[AssignabilityIssue] {
  let acc : Array[AssignabilityIssue] = []
  check_at(source, target, "", acc)
  acc
}

///|
// Resolver-aware diagnostic check. Pre-expands `Named(n)` references on both
// sides via the resolver (with cycle protection) before walking the structure
// for issue reporting. The reported paths refer to the *expanded* types — the
// caller can reason about names via the resolver itself.
pub fn check_assignable_with(
  source : @ast.TsType,
  target : @ast.TsType,
  resolve : (String) -> @ast.TsType?,
) -> Array[AssignabilityIssue] {
  // Reuse the same expansion the assignability fast-path uses so the
  // diagnostic walk operates on the same shape. We delegate to
  // `is_assignable_to_with` first as a success oracle, then walk the expanded
  // types if the relation is rejected.
  if is_assignable_to_with(source, target, resolve) {
    return []
  }
  let s = expand_for_diagnostic(source, resolve, [])
  let t = expand_for_diagnostic(target, resolve, [])
  let acc : Array[AssignabilityIssue] = []
  check_at(s, t, "", acc)
  acc
}

///|
// Generic-aware diagnostic check: same as `check_assignable_with` but accepts
// an `AliasBinding` resolver so `Applied(Name, [args])` can be substituted
// before the walk.
pub fn check_assignable_with_generics(
  source : @ast.TsType,
  target : @ast.TsType,
  resolve : (String) -> AliasBinding?,
) -> Array[AssignabilityIssue] {
  if is_assignable_to_with_generics(source, target, resolve) {
    return []
  }
  let s = expand_for_diagnostic_generic(source, resolve, [])
  let t = expand_for_diagnostic_generic(target, resolve, [])
  let acc : Array[AssignabilityIssue] = []
  check_at(s, t, "", acc)
  acc
}

///|
fn expand_for_diagnostic(
  type_ : @ast.TsType,
  resolve : (String) -> @ast.TsType?,
  visited : Array[String],
) -> @ast.TsType {
  // Internal mirror of `expand_aliases` in resolver.mbt — duplicated here so
  // diagnostic.mbt does not need to peek at private helpers in other files.
  match type_ {
    Named(name) =>
      if visited.contains(name) {
        Any
      } else {
        match resolve(name) {
          Some(body) => {
            visited.push(name)
            let expanded = expand_for_diagnostic(body, resolve, visited)
            let _ = visited.pop()
            expanded
          }
          None => type_
        }
      }
    Array(inner) => Array(expand_for_diagnostic(inner, resolve, visited))
    Tuple(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(expand_for_diagnostic(it, resolve, visited))
      }
      Tuple(out)
    }
    Object(fields) => {
      let out : Array[(@ast.TsType, @ast.TsType)] = []
      for f in fields {
        out.push((
          expand_for_diagnostic(f.0, resolve, visited),
          expand_for_diagnostic(f.1, resolve, visited),
        ))
      }
      Object(out)
    }
    Func(params, ret) => {
      let out : Array[@ast.TsType] = []
      for p in params {
        out.push(expand_for_diagnostic(p, resolve, visited))
      }
      Func(out, expand_for_diagnostic(ret, resolve, visited))
    }
    Union(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(expand_for_diagnostic(it, resolve, visited))
      }
      Union(out)
    }
    Intersection(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(expand_for_diagnostic(it, resolve, visited))
      }
      Intersection(out)
    }
    _ => type_
  }
}

///|
fn expand_for_diagnostic_generic(
  type_ : @ast.TsType,
  resolve : (String) -> AliasBinding?,
  visited : Array[String],
) -> @ast.TsType {
  // Mirror of `expand_generic` for the diagnostic walk.
  match type_ {
    Named(name) =>
      if visited.contains(name) {
        Any
      } else {
        match resolve(name) {
          Some(b) =>
            if b.type_params.length() == 0 {
              visited.push(name)
              let expanded = expand_for_diagnostic_generic(
                b.body, resolve, visited,
              )
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
        resolved_args.push(expand_for_diagnostic_generic(a, resolve, visited))
      }
      if visited.contains(name) {
        return Any
      }
      match resolve(name) {
        Some(b) =>
          if b.type_params.length() == resolved_args.length() &&
            b.type_params.length() > 0 {
            let bindings : Map[String, @ast.TsType] = {}
            for i in 0..<b.type_params.length() {
              bindings[b.type_params[i]] = resolved_args[i]
            }
            let substituted = substitute_inferred_type(b.body, bindings)
            visited.push(name)
            let expanded = expand_for_diagnostic_generic(
              substituted, resolve, visited,
            )
            let _ = visited.pop()
            expanded
          } else {
            Applied(name, resolved_args)
          }
        None => Applied(name, resolved_args)
      }
    }
    Array(inner) =>
      Array(expand_for_diagnostic_generic(inner, resolve, visited))
    Tuple(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(expand_for_diagnostic_generic(it, resolve, visited))
      }
      Tuple(out)
    }
    Object(fields) => {
      let out : Array[(@ast.TsType, @ast.TsType)] = []
      for f in fields {
        out.push((
          expand_for_diagnostic_generic(f.0, resolve, visited),
          expand_for_diagnostic_generic(f.1, resolve, visited),
        ))
      }
      Object(out)
    }
    Func(params, ret) => {
      let out : Array[@ast.TsType] = []
      for p in params {
        out.push(expand_for_diagnostic_generic(p, resolve, visited))
      }
      Func(out, expand_for_diagnostic_generic(ret, resolve, visited))
    }
    Union(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(expand_for_diagnostic_generic(it, resolve, visited))
      }
      Union(out)
    }
    Intersection(items) => {
      let out : Array[@ast.TsType] = []
      for it in items {
        out.push(expand_for_diagnostic_generic(it, resolve, visited))
      }
      Intersection(out)
    }
    _ => type_
  }
}

///|
fn check_at(
  source : @ast.TsType,
  target : @ast.TsType,
  path : String,
  acc : Array[AssignabilityIssue],
) -> Unit {
  // Use the existing structural relation as a fast oracle. If it succeeds, no
  // diagnostic work is needed; otherwise we walk the structure to find a
  // concrete failure site.
  if is_assignable_to(source, target) {
    return
  }
  // Source/target unions: report a single root-level failure rather than
  // attempting to combine multi-branch diagnostics.
  match (source, target) {
    (Tuple(s_items), Tuple(t_items)) => {
      if s_items.length() != t_items.length() {
        acc.push({
          path,
          message: "tuple length mismatch (\{s_items.length()} vs \{t_items.length()})",
        })
        return
      }
      let mut found = false
      for i in 0..<s_items.length() {
        if !is_assignable_to(s_items[i], t_items[i]) {
          check_at(s_items[i], t_items[i], "\{path}[\{i}]", acc)
          found = true
        }
      }
      if !found {
        acc.push({ path, message: "tuple elements not assignable" })
      }
      return
    }
    (Object(s_fields), Object(t_fields)) => {
      let mut found = false
      for t_field in t_fields {
        let (t_key, t_type) = t_field
        let key_label = label_for_key(t_key)
        let mut matched = false
        for s_field in s_fields {
          if s_field.0 == t_key {
            if !is_assignable_to(s_field.1, t_type) {
              check_at(s_field.1, t_type, "\{path}\{key_label}", acc)
              found = true
            }
            matched = true
            break
          }
        }
        if !matched && !type_accepts_undefined(t_type) {
          acc.push({
            path: "\{path}\{key_label}",
            message: "missing required field",
          })
          found = true
        }
      }
      if !found {
        acc.push({ path, message: "object shapes incompatible" })
      }
      return
    }
    (Func(s_params, s_ret), Func(t_params, t_ret)) => {
      if s_params.length() != t_params.length() {
        acc.push({
          path,
          message: "function arity mismatch (\{s_params.length()} vs \{t_params.length()})",
        })
        return
      }
      let mut found = false
      for i in 0..<s_params.length() {
        // Contravariant: target param flows into source param.
        if !is_assignable_to(t_params[i], s_params[i]) {
          check_at(
            t_params[i], s_params[i], "\{path}.param[\{i}]", acc,
          )
          found = true
        }
      }
      if !is_assignable_to(s_ret, t_ret) {
        check_at(s_ret, t_ret, "\{path}.return", acc)
        found = true
      }
      if !found {
        acc.push({ path, message: "function shapes incompatible" })
      }
      return
    }
    (Array(s_inner), Array(t_inner)) => {
      check_at(s_inner, t_inner, "\{path}[]", acc)
      return
    }
    _ => ()
  }
  // Fall through: report the rejection at the current path.
  acc.push({ path, message: "type mismatch" })
}

///|
fn label_for_key(key : @ast.TsType) -> String {
  match key {
    Literal(name) => "." + name
    NumberLiteral(n) => "[" + n + "]"
    _ => ".<computed>"
  }
}

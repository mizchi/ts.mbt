// Pattern matcher for `infer X` clauses inside TypeScript conditional types.
// The parser encodes `infer X` as `Applied("__tsmbt_infer", [Named(X)])`.
// `match_infer_pattern(source, pattern, bindings)` walks the pattern in
// lockstep with source; whenever it encounters an infer marker it binds the
// corresponding source subtree under that name. Returns false on any
// structural mismatch (or conflicting bindings) and otherwise true.
//
// `substitute_inferred_type(body, bindings)` applies the bindings produced by
// `match_infer_pattern`, replacing both `Named(X)` and infer markers in the
// body with their bound types. This is what callers use to evaluate the
// `true_branch` of a conditional once the pattern matched.

///|
pub fn infer_marker_name(type_ : @ast.TsType) -> String? {
  match type_ {
    Applied("__tsmbt_infer", [Named(name)]) => Some(name)
    _ => None
  }
}

///|
pub fn bind_inferred_type(
  bindings : Map[String, @ast.TsType],
  name : String,
  type_ : @ast.TsType,
) -> Bool {
  match bindings.get(name) {
    Some(existing) => existing == type_
    None => {
      bindings[name] = type_
      true
    }
  }
}

///|
pub fn match_infer_pattern(
  source : @ast.TsType,
  pattern : @ast.TsType,
  bindings : Map[String, @ast.TsType],
) -> Bool {
  match infer_marker_name(pattern) {
    Some(name) => return bind_inferred_type(bindings, name, source)
    None => ()
  }
  if source == pattern {
    return true
  }
  match (source, pattern) {
    (_, Any) => true
    (Array(s_inner), Array(p_inner)) =>
      match_infer_pattern(s_inner, p_inner, bindings)
    (Array(s_inner), Applied("Array", [p_inner])) =>
      match_infer_pattern(s_inner, p_inner, bindings)
    (Applied("Array", [s_inner]), Array(p_inner)) =>
      match_infer_pattern(s_inner, p_inner, bindings)
    (Applied(s_name, s_args), Applied(p_name, p_args)) =>
      if s_name != p_name || s_args.length() != p_args.length() {
        false
      } else {
        for i in 0..<s_args.length() {
          if !match_infer_pattern(s_args[i], p_args[i], bindings) {
            return false
          }
        }
        true
      }
    (Tuple(s_items), Tuple(p_items)) =>
      if s_items.length() != p_items.length() {
        false
      } else {
        for i in 0..<s_items.length() {
          if !match_infer_pattern(s_items[i], p_items[i], bindings) {
            return false
          }
        }
        true
      }
    (Func(s_params, s_ret), Func(p_params, p_ret)) => {
      // Rest-parameter pattern: the pattern has a single parameter of the form
      // `Array(X)` representing `...args: X[]`. It matches any source arity.
      //   - If X is `infer P`, bind P to `Tuple(source_params)`.
      //   - Otherwise every source param must match X structurally
      //     (typical case: X = Any → unconstrained).
      if p_params.length() == 1 {
        match p_params[0] {
          Array(rest_inner) =>
            match infer_marker_name(rest_inner) {
              Some(rest_name) =>
                return bind_inferred_type(bindings, rest_name, Tuple(s_params)) &&
                  match_infer_pattern(s_ret, p_ret, bindings)
              None => {
                for sp in s_params {
                  if !match_infer_pattern(sp, rest_inner, bindings) {
                    return false
                  }
                }
                return match_infer_pattern(s_ret, p_ret, bindings)
              }
            }
          _ => ()
        }
      }
      if s_params.length() != p_params.length() {
        false
      } else {
        for i in 0..<s_params.length() {
          if !match_infer_pattern(s_params[i], p_params[i], bindings) {
            return false
          }
        }
        match_infer_pattern(s_ret, p_ret, bindings)
      }
    }
    (_, Union(p_items)) => {
      // Try each pattern branch in isolation; commit only if a branch matches
      // without conflicting with already-committed bindings.
      for p_item in p_items {
        let branch_bindings : Map[String, @ast.TsType] = {}
        if match_infer_pattern(source, p_item, branch_bindings) {
          for entry in branch_bindings {
            let (name, type_) = entry
            if !bind_inferred_type(bindings, name, type_) {
              return false
            }
          }
          return true
        }
      }
      false
    }
    (Object(s_fields), Object(p_fields)) => {
      // Each pattern field must appear in the source with a matching type.
      // Source may carry extra fields; that is the structural-subtype rule.
      for p_field in p_fields {
        let (p_key, p_type) = p_field
        let mut matched = false
        for s_field in s_fields {
          let (s_key, s_type) = s_field
          if s_key == p_key {
            if !match_infer_pattern(s_type, p_type, bindings) {
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
    (Intersection(s_items), Intersection(p_items)) =>
      if s_items.length() != p_items.length() {
        false
      } else {
        for i in 0..<s_items.length() {
          if !match_infer_pattern(s_items[i], p_items[i], bindings) {
            return false
          }
        }
        true
      }
    (
      Conditional(s_check, s_extends, s_t, s_f),
      Conditional(p_check, p_extends, p_t, p_f),
    ) =>
      match_infer_pattern(s_check, p_check, bindings) &&
      match_infer_pattern(s_extends, p_extends, bindings) &&
      match_infer_pattern(s_t, p_t, bindings) &&
      match_infer_pattern(s_f, p_f, bindings)
    _ => false
  }
}

///|
pub fn substitute_inferred_type(
  type_ : @ast.TsType,
  bindings : Map[String, @ast.TsType],
) -> @ast.TsType {
  match infer_marker_name(type_) {
    Some(name) =>
      match bindings.get(name) {
        Some(t) => return t
        None => ()
      }
    None => ()
  }
  match type_ {
    Named(name) =>
      match bindings.get(name) {
        Some(t) => t
        None => type_
      }
    Array(inner) => Array(substitute_inferred_type(inner, bindings))
    Tuple(items) => {
      let out : Array[@ast.TsType] = []
      for item in items {
        out.push(substitute_inferred_type(item, bindings))
      }
      Tuple(out)
    }
    Object(fields) => {
      let out : Array[(@ast.TsType, @ast.TsType)] = []
      for field in fields {
        let (key, value) = field
        out.push(
          (
            substitute_inferred_type(key, bindings),
            substitute_inferred_type(value, bindings),
          ),
        )
      }
      Object(out)
    }
    Func(params, ret) => {
      let out : Array[@ast.TsType] = []
      for param in params {
        out.push(substitute_inferred_type(param, bindings))
      }
      Func(out, substitute_inferred_type(ret, bindings))
    }
    Union(items) => {
      let out : Array[@ast.TsType] = []
      for item in items {
        out.push(substitute_inferred_type(item, bindings))
      }
      Union(out)
    }
    Intersection(items) => {
      let out : Array[@ast.TsType] = []
      for item in items {
        out.push(substitute_inferred_type(item, bindings))
      }
      Intersection(out)
    }
    Conditional(s, t, true_type, false_type) =>
      Conditional(
        substitute_inferred_type(s, bindings),
        substitute_inferred_type(t, bindings),
        substitute_inferred_type(true_type, bindings),
        substitute_inferred_type(false_type, bindings),
      )
    Applied(name, args) => {
      let out : Array[@ast.TsType] = []
      for arg in args {
        out.push(substitute_inferred_type(arg, bindings))
      }
      Applied(name, out)
    }
    _ => type_
  }
}

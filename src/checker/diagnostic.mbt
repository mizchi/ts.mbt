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

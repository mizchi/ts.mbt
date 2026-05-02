// Three-valued assignability ("does S extend T in the TS-conditional sense?"):
//   Some(true)  — definitely yes,
//   Some(false) — definitely no,
//   None        — undecidable from the structural information alone.
//
// This is the relation the bridge needs when reducing `Conditional(S, T, X, Y)`
// — picking a branch is only safe when the relation is definite. Differs from
// `is_assignable_to` mainly in that nominal mismatches (Named vs Named with
// different names, no resolver) report `None` instead of `false`, since at the
// declaration level the names might still ultimately resolve to compatible
// types.

///|
pub fn extends_decision(
  source : @ast.TsType,
  target : @ast.TsType,
) -> Bool? {
  if source == target {
    return Some(true)
  }
  match target {
    Any => return Some(true)
    Union(items) => {
      let mut saw_unknown = false
      for item in items {
        match extends_decision(source, item) {
          Some(true) => return Some(true)
          Some(false) => ()
          None => saw_unknown = true
        }
      }
      return if saw_unknown { None } else { Some(false) }
    }
    _ => ()
  }
  match source {
    Never => return Some(true)
    Union(items) => {
      let mut saw_unknown = false
      for item in items {
        match extends_decision(item, target) {
          Some(true) => ()
          Some(false) => return Some(false)
          None => saw_unknown = true
        }
      }
      return if saw_unknown { None } else { Some(true) }
    }
    Int if target == Number => return Some(true)
    _ => ()
  }
  // Literal narrowing: each literal kind extends its primitive companion.
  match (source, target) {
    (Literal(_), String_) => return Some(true)
    (NumberLiteral(_), Number) => return Some(true)
    (BigIntLiteral(_), BigInt) => return Some(true)
    (BooleanLiteral(_), Boolean) => return Some(true)
    _ => ()
  }
  match (source, target) {
    (
      Number
      | Int
      | Boolean
      | String_
      | Void
      | BigInt
      | Symbol
      | Null
      | Undefined,
      Number
      | Int
      | Boolean
      | String_
      | Void
      | BigInt
      | Symbol
      | Null
      | Undefined,
    ) => Some(false)
    _ => None
  }
}

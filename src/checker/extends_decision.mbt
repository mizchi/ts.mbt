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
//
// Resolver- and generics-aware variants pre-expand aliases via the matching
// resolvers from resolver.mbt / generics.mbt before delegating to the
// structural decision.

///|
pub fn extends_decision(source : @ast.TsType, target : @ast.TsType) -> Bool? {
  if source == target {
    return Some(true)
  }
  // `unique symbol` identity: two markers with different tags are
  // nominally disjoint; either side against bare `Symbol` widens.
  match (source, target) {
    (UniqueSymbol(a), UniqueSymbol(b)) =>
      return if a == b { Some(true) } else { Some(false) }
    (UniqueSymbol(_), Symbol) => return Some(true)
    (Symbol, UniqueSymbol(_)) => return Some(false)
    _ => ()
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
  // Two literals of the same kind with different values are disjoint —
  // TS `"a" extends "b"` is `false`. This matters for conditional
  // remap patterns like `K extends 'b' ? never : K`.
  match (source, target) {
    (Literal(_), Literal(_)) => return Some(false)
    (NumberLiteral(_), NumberLiteral(_)) => return Some(false)
    (BigIntLiteral(_), BigIntLiteral(_)) => return Some(false)
    (BooleanLiteral(_), BooleanLiteral(_)) => return Some(false)
    _ => ()
  }
  // Distinct primitive vs literal of a different kind: also disjoint.
  match (source, target) {
    (Literal(_), Number | Int | Boolean | BigInt | Void | Null | Undefined) =>
      return Some(false)
    (NumberLiteral(_), String_ | Boolean | BigInt | Void | Null | Undefined) =>
      return Some(false)
    (
      BigIntLiteral(_),
      String_
      | Number
      | Int
      | Boolean
      | Void
      | Null
      | Undefined,
    ) => return Some(false)
    (
      BooleanLiteral(_),
      String_
      | Number
      | Int
      | BigInt
      | Void
      | Null
      | Undefined,
    ) => return Some(false)
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

///|
pub fn extends_decision_with(
  source : @ast.TsType,
  target : @ast.TsType,
  resolve : (String) -> @ast.TsType?,
) -> Bool? {
  let s = expand_aliases(source, resolve, [])
  let t = expand_aliases(target, resolve, [])
  extends_decision(s, t)
}

///|
pub fn extends_decision_with_generics(
  source : @ast.TsType,
  target : @ast.TsType,
  resolve : (String) -> AliasBinding?,
) -> Bool? {
  let s = expand_generic(source, resolve, [])
  let t = expand_generic(target, resolve, [])
  extends_decision(s, t)
}

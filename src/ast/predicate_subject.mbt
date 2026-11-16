// The position of a type predicate's subject, carried in its name.
//
// A callable TYPE keeps parameter types and not names, so `(first: unknown,
// value: unknown) => value is string` cannot say which argument the guard
// narrows once it is a `Func`: every reader narrowed the first, and tsc
// narrows `value`. Where a callable type is built from a parameter list
// with names, a subject at position 1 or later is recorded as
// `"\u{1}<position>\u{1}<name>"`. Position 0 is left as written, so a
// predicate whose subject is the first parameter — nearly all of them — is
// unchanged everywhere. Anything that PRINTS the name reads it through
// `predicate_subject_name`.

///|
/// `ret` with its subject's position recorded, when it is a type predicate
/// over one of `names` other than the first.
pub fn index_predicate_subject(ret : TsType, names : Array[String]) -> TsType {
  match ret {
    TypePredicate(name, target) if !name.has_prefix("\u{1}") => {
      for i, n in names {
        if n == name {
          return if i == 0 {
            ret
          } else {
            TypePredicate("\u{1}" + i.to_string() + "\u{1}" + name, target)
          }
        }
      }
      ret
    }
    _ => ret
  }
}

///|
/// A predicate subject's name as written, without a recorded position.
pub fn predicate_subject_name(name : String) -> String {
  if !name.has_prefix("\u{1}") {
    return name
  }
  match name[1:].find("\u{1}") {
    Some(i) => name[i + 2:].to_owned()
    None => name
  }
}

///|
/// A predicate subject's recorded position, if one was recorded.
pub fn predicate_subject_position(name : String) -> Int32? {
  if !name.has_prefix("\u{1}") {
    return None
  }
  match name[1:].find("\u{1}") {
    Some(i) => {
      let digits = name[1:i + 1]
      if digits.length() == 0 {
        return None
      }
      let mut n = 0
      for c in digits {
        if c < '0' || c > '9' {
          return None
        }
        n = n * 10 + (c.to_int() - '0'.to_int())
      }
      Some(n)
    }
    None => None
  }
}

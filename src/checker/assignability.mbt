// Minimal TypeScript-style assignability check operating on `@ast.TsType`.
// `is_assignable_to(source, target)` answers: can a value of type `source`
// be used where `target` is expected?
//
// The implementation is intentionally local — it does not resolve `Named`
// references against any module graph. Callers that need cross-reference
// resolution should pre-substitute aliases first.
//
// Function parameter variance defaults to *contravariant* (TS strict-mode
// behavior). Use `is_assignable_to_bivariant` to mirror non-strict TS where
// method-shorthand parameters are bivariant.

///|
pub fn is_assignable_to(source : @ast.TsType, target : @ast.TsType) -> Bool {
  is_assignable_to_inner(source, target, false)
}

///|
// Single-type-argument generic names whose element type an array satisfies:
// `T[]` is assignable to each of these when the element types are compatible.
fn is_array_like_iterable_name(name : String) -> Bool {
  match name {
    "Iterable"
    | "IterableIterator"
    | "ArrayLike"
    | "ReadonlyArray"
    | "ConcatArray"
    | "RelativeIndexable" => true
    _ => false
  }
}

///|
// Position of the single `Rest(...)` element inside a tuple, if any. TS
// allows at most one variadic element per tuple type (e.g. `[A, ...B[], C]`).
fn tuple_rest_index(items : Array[@ast.TsType]) -> Int? {
  for i in 0..<items.length() {
    match items[i] {
      Rest(_) => return Some(i)
      _ => ()
    }
  }
  None
}

///|
// Element type a variadic tuple slot iterates over. `Rest(Array(T))` and
// `Rest(Tuple(...))` are the parser shapes; we strip the outer `Rest` and
// (for arrays) one level of element wrapping. Returns `None` when the
// inner shape is not a plain array — in that case we can't widen middle
// elements against it.
fn rest_element_type(t : @ast.TsType) -> @ast.TsType? {
  match t {
    Rest(Array(inner)) => Some(inner)
    Rest(Applied(name, [inner])) =>
      if is_array_like_iterable_name(name) || name == "Array" {
        Some(inner)
      } else {
        None
      }
    _ => None
  }
}

///|
// TS tuple assignability with variadic-element support. The variadic
// element may appear at any single position in either tuple; we handle
// the common cases by aligning the fixed prefix/suffix of both sides and
// distributing leftover source elements against the target's rest slot.
fn tuple_assignable(
  s_items : Array[@ast.TsType],
  t_items : Array[@ast.TsType],
  bivariant_params : Bool,
) -> Bool {
  let s_rest = tuple_rest_index(s_items)
  let t_rest = tuple_rest_index(t_items)
  match (s_rest, t_rest) {
    (None, None) => {
      if s_items.length() != t_items.length() {
        return false
      }
      for i in 0..<s_items.length() {
        if !is_assignable_to_inner(s_items[i], t_items[i], bivariant_params) {
          return false
        }
      }
      true
    }
    (None, Some(ri)) => {
      // Fixed-length source flowing into a variadic target slot.
      let prefix = ri
      let suffix = t_items.length() - ri - 1
      if s_items.length() < prefix + suffix {
        return false
      }
      for i in 0..<prefix {
        if !is_assignable_to_inner(s_items[i], t_items[i], bivariant_params) {
          return false
        }
      }
      for i in 0..<suffix {
        let s_idx = s_items.length() - suffix + i
        let t_idx = ri + 1 + i
        if !is_assignable_to_inner(
            s_items[s_idx],
            t_items[t_idx],
            bivariant_params,
          ) {
          return false
        }
      }
      match rest_element_type(t_items[ri]) {
        Some(rest_inner) =>
          for i in prefix..<(s_items.length() - suffix) {
            if !is_assignable_to_inner(s_items[i], rest_inner, bivariant_params) {
              return false
            }
          }
        None =>
          // Rest slot is not a plain array — only safe when no source
          // elements need to be distributed into it.
          if s_items.length() != prefix + suffix {
            return false
          }
      }
      true
    }
    (Some(ri), Some(rj)) => {
      // Both sides variadic. Require matching prefix/suffix lengths and
      // identical rest position so the existing pointwise rule applies.
      if s_items.length() != t_items.length() || ri != rj {
        return false
      }
      for i in 0..<s_items.length() {
        if !is_assignable_to_inner(s_items[i], t_items[i], bivariant_params) {
          return false
        }
      }
      true
    }
    (Some(_), None) =>
      // Variadic source flowing into a fixed target: source length is
      // unknown at the type level, so we conservatively reject. Real TS
      // would allow this when the variadic slot resolves to a fixed
      // tuple, but the parser already flattens those.
      false
  }
}

///|
// TS function-parameter arity rule: source may declare fewer parameters
// than target (caller-side extras are simply ignored by the source
// implementation). If source ends with a `Rest(...)` parameter, source
// can absorb any number of trailing args ≥ its fixed prefix length.
// Per-position variance is contravariant in strict mode, bivariant when
// requested.
fn func_params_assignable(
  s_params : Array[@ast.TsType],
  t_params : Array[@ast.TsType],
  bivariant_params : Bool,
) -> Bool {
  let s_len = s_params.length()
  let t_len = t_params.length()
  let s_trailing_rest = s_len > 0 &&
    (match s_params[s_len - 1] {
      Rest(_) => true
      _ => false
    })
  let s_fixed = if s_trailing_rest { s_len - 1 } else { s_len }
  if s_trailing_rest {
    if t_len < s_fixed {
      return false
    }
  } else if t_len < s_len {
    return false
  }
  let shared = if s_trailing_rest { t_len.min(s_fixed) } else { s_len }
  fn variance_ok(a, b) {
    if bivariant_params {
      is_assignable_to_inner(a, b, bivariant_params) ||
      is_assignable_to_inner(b, a, bivariant_params)
    } else {
      is_assignable_to_inner(b, a, bivariant_params)
    }
  }

  for i in 0..<shared {
    if !variance_ok(s_params[i], t_params[i]) {
      return false
    }
  }
  // Source has a trailing rest: target's tail params must each flow into
  // the rest's element type (contravariantly). When the rest is not a
  // plain array, only an exact-length match is safe.
  if s_trailing_rest {
    let rest_slot = s_params[s_len - 1]
    let rest_elem = rest_element_type(rest_slot)
    match rest_elem {
      Some(elem) =>
        for i in s_fixed..<t_len {
          if !variance_ok(elem, t_params[i]) {
            return false
          }
        }
      None => if t_len != s_fixed { return false }
    }
  }
  true
}

///|
// Set of strings a placeholder type can produce, used to decide whether a
// concrete substring satisfies the placeholder. `None` means "any string
// fits" (e.g. when the placeholder is `string` or a numeric primitive in a
// stringified position); `Some([...])` enumerates the exact accepted
// substrings. The caller decides which.
fn template_arg_accepts_substring(arg : @ast.TsType, sub : String) -> Bool {
  match arg {
    String_ => true
    Number => is_number_string(sub)
    BigInt => is_bigint_string(sub)
    Boolean => sub == "true" || sub == "false"
    Literal(name) => sub == name
    NumberLiteral(name) => sub == name
    BigIntLiteral(name) => sub == name
    BooleanLiteral(true) => sub == "true"
    BooleanLiteral(false) => sub == "false"
    Union(members) => {
      for m in members {
        if template_arg_accepts_substring(m, sub) {
          return true
        }
      }
      false
    }
    _ =>
      // Unknown / opaque type — conservatively accept so we don't reject a
      // template that might be compatible after substitution.
      true
  }
}

///|
fn is_number_string(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let mut seen_digit = false
  let mut seen_dot = false
  for i in 0..<s.length() {
    let c = s[i].to_int().unsafe_to_char()
    if c >= '0' && c <= '9' {
      seen_digit = true
    } else if c == '.' && !seen_dot {
      seen_dot = true
    } else if (c == '-' || c == '+') && i == 0 {
      ()
    } else {
      return false
    }
  }
  seen_digit
}

///|
fn is_bigint_string(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for i in 0..<s.length() {
    let c = s[i].to_int().unsafe_to_char()
    if c >= '0' && c <= '9' {
      ()
    } else if (c == '-' || c == '+') && i == 0 {
      ()
    } else {
      return false
    }
  }
  true
}

///|
// Try to match a concrete string against a TemplateLiteralType pattern.
// parts.length() == args.length() + 1; the pattern is
//   parts[0] · ⟨arg[0]⟩ · parts[1] · ⟨arg[1]⟩ · ... · parts[N]
// Matching greedily finds prefix / suffix bounds per part and verifies the
// intervening substring is accepted by each placeholder type.
fn literal_matches_template(
  name : String,
  parts : Array[String],
  args : Array[@ast.TsType],
  _bivariant_params : Bool,
) -> Bool {
  match try_match_literal_template(name, 0, parts, 0, args) {
    Some(_) => true
    None => false
  }
}

///|
// Recursive descent over template parts. Returns `Some(remaining_index)` on
// success so callers can confirm the whole input was consumed.
fn try_match_literal_template(
  name : String,
  pos : Int,
  parts : Array[String],
  arg_idx : Int,
  args : Array[@ast.TsType],
) -> Int? {
  let part = parts[arg_idx]
  // Source must contain `part` starting at `pos`.
  if pos + part.length() > name.length() {
    return None
  }
  for i in 0..<part.length() {
    if name[pos + i] != part[i] {
      return None
    }
  }
  let after_part = pos + part.length()
  if arg_idx >= args.length() {
    // No more placeholders: the rest of `name` must be empty.
    return if after_part == name.length() { Some(after_part) } else { None }
  }
  // Greedy/backtracking: try each split point in [after_part, end_for_next_part]
  // and see whether the gap text satisfies args[arg_idx] AND the remaining
  // string parses for the rest of the pattern.
  let next_part = parts[arg_idx + 1]
  let last_search = name.length() - next_part.length()
  if last_search < after_part {
    return None
  }
  for split in after_part..<=last_search {
    let buf = StringBuilder::new()
    for i in after_part..<split {
      buf.write_char(name[i].to_int().unsafe_to_char())
    }
    let gap = buf.to_string()
    if template_arg_accepts_substring(args[arg_idx], gap) {
      match try_match_literal_template(name, split, parts, arg_idx + 1, args) {
        Some(end) => return Some(end)
        None => ()
      }
    }
  }
  None
}

///|
// A template literal type can produce the single literal `name` iff the
// template is structurally equivalent to that literal: all parts concatenate
// to `name` and all placeholders are unit (singleton literal) types.
fn template_produces_single(
  parts : Array[String],
  args : Array[@ast.TsType],
  name : String,
) -> Bool {
  let buf = StringBuilder::new()
  for i in 0..<parts.length() {
    buf.write_string(parts[i])
    if i < args.length() {
      match args[i] {
        Literal(s) | NumberLiteral(s) | BigIntLiteral(s) => buf.write_string(s)
        BooleanLiteral(true) => buf.write_string("true")
        BooleanLiteral(false) => buf.write_string("false")
        _ => return false
      }
    }
  }
  buf.to_string() == name
}

///|
// Two TemplateLiteralType compatibility. The conservative branch (matching
// parts arrays) is the common case; for differing parts we attempt to match
// the source's structure against the target by combining adjacent literal
// parts where possible.
fn template_assignable(
  s_parts : Array[String],
  s_args : Array[@ast.TsType],
  t_parts : Array[String],
  t_args : Array[@ast.TsType],
  bivariant_params : Bool,
) -> Bool {
  if s_parts == t_parts && s_args.length() == t_args.length() {
    for i in 0..<s_args.length() {
      if !is_assignable_to_inner(s_args[i], t_args[i], bivariant_params) {
        return false
      }
    }
    return true
  }
  // Differing parts: source assignable to target iff target's first/last
  // literal anchors are a prefix/suffix of source's first/last literal
  // anchors AND the source produces no string violating target's
  // placeholders. We approximate by enforcing prefix/suffix match.
  if s_parts.length() == 0 || t_parts.length() == 0 {
    return false
  }
  let s_first = s_parts[0]
  let t_first = t_parts[0]
  let s_last = s_parts[s_parts.length() - 1]
  let t_last = t_parts[t_parts.length() - 1]
  if !s_first.has_prefix(t_first) || !s_last.has_suffix(t_last) {
    return false
  }
  // For the conservative TS-aligned approximation: when target has a
  // single placeholder of the widest stringifiable type (`string`), any
  // template with matching anchors fits. Otherwise we punt.
  if t_args.length() == 1 {
    match t_args[0] {
      String_ => return true
      _ => ()
    }
  }
  false
}

///|
pub fn is_assignable_to_bivariant(
  source : @ast.TsType,
  target : @ast.TsType,
) -> Bool {
  is_assignable_to_inner(source, target, true)
}

///|
fn is_assignable_to_inner(
  source : @ast.TsType,
  target : @ast.TsType,
  bivariant_params : Bool,
) -> Bool {
  // Reflexive shortcut.
  if source == target {
    return true
  }
  // Resolve T[K] before matching — IndexedAccess that cannot be resolved is
  // treated as `Any`, which flows freely. Both sides are eagerly resolved.
  let source = resolve_indexed_access_local(source)
  let target = resolve_indexed_access_local(target)
  // Conditional types pick a branch when `extends` is decidable.
  let source = reduce_conditional(source)
  let target = reduce_conditional(target)
  if source == target {
    return true
  }
  // `any` is the universal escape hatch — it flows in either direction.
  match target {
    Any => return true
    _ => ()
  }
  match source {
    Any => return true
    _ => ()
  }
  // `unknown` is the safe top type: every source flows into it, but it
  // only flows out to `unknown` itself (and `any`, which was already
  // handled above). This is what gives `unknown` its narrowing
  // discipline relative to `any`.
  match target {
    Unknown => return true
    _ => ()
  }
  match source {
    Unknown => return false
    _ => ()
  }
  // `never` is the bottom type: anything accepts it as a source.
  match source {
    Never => return true
    _ => ()
  }
  // The target side of a union accepts a source if any member matches.
  match target {
    Union(members) => {
      for m in members {
        if is_assignable_to_inner(source, m, bivariant_params) {
          return true
        }
      }
      // `true | false` is exactly `boolean`: a union covering both boolean
      // literals accepts `boolean` (and either literal) as a source. Without
      // this, `var a: true | false = b /* boolean */` false-flags.
      let mut has_true = false
      let mut has_false = false
      for m in members {
        match m {
          BooleanLiteral(true) => has_true = true
          BooleanLiteral(false) => has_false = true
          Boolean => {
            has_true = true
            has_false = true
          }
          _ => ()
        }
      }
      if has_true && has_false {
        match source {
          Boolean | BooleanLiteral(_) => return true
          _ => ()
        }
      }
      // Fall through to source-side handling below for unions on the source.
      match source {
        Union(_) => ()
        _ => return false
      }
    }
    _ => ()
  }
  // The source side of a union flows into target only if every member fits.
  match source {
    Union(members) => {
      for m in members {
        if !is_assignable_to_inner(m, target, bivariant_params) {
          return false
        }
      }
      return true
    }
    _ => ()
  }
  // Target intersection: every component must accept the source.
  match target {
    Intersection(members) => {
      for m in members {
        if !is_assignable_to_inner(source, m, bivariant_params) {
          return false
        }
      }
      return true
    }
    _ => ()
  }
  // Source intersection: at least one component must satisfy the target.
  match source {
    Intersection(members) => {
      for m in members {
        if is_assignable_to_inner(m, target, bivariant_params) {
          return true
        }
      }
      return false
    }
    _ => ()
  }
  match (source, target) {
    // Literal subtyping: each literal kind narrows its primitive companion.
    (Literal(_), String_) => true
    // Template literal types are a subtype of string. Two TemplateLiteralType
    // values are compatible when the source's set of producible strings is a
    // subset of the target's: we check by matching part literals position-wise
    // and verifying each placeholder's source type flows into the target's.
    (TemplateLiteralType(_, _), String_) => true
    (TemplateLiteralType(s_parts, s_args), Literal(name)) =>
      // Source produces multiple strings; the only way it fits a single
      // literal is if every placeholder is itself a literal matching at
      // the right offset. Reuse the literal->template matcher symmetrically.
      template_produces_single(s_parts, s_args, name)
    (Literal(name), TemplateLiteralType(t_parts, t_args)) =>
      // String literal matches a template pattern iff prefix/suffix line up
      // and each placeholder-bounded gap satisfies the placeholder's type.
      literal_matches_template(name, t_parts, t_args, bivariant_params)
    (TemplateLiteralType(s_parts, s_args), TemplateLiteralType(t_parts, t_args)) =>
      template_assignable(s_parts, s_args, t_parts, t_args, bivariant_params)
    (NumberLiteral(_), Number) => true
    (BigIntLiteral(_), BigInt) => true
    (BooleanLiteral(_), Boolean) => true
    // Arrays / typed arrays are iterable: `T[]` is assignable to
    // `Iterable<T>` / `IterableIterator<T>` / `ArrayLike<T>` and the
    // `ReadonlyArray<T>` form. Element type is covariant.
    (Array(s_inner), Applied(t_name, [t_inner])) =>
      if is_array_like_iterable_name(t_name) {
        is_assignable_to_inner(s_inner, t_inner, bivariant_params)
      } else {
        false
      }
    // `Array<T>` (Applied form) and `T[]` (Array form) are interchangeable
    // in TS. Treat `Applied("Array", [T])` as the canonical array on the
    // source side too, so it flows into `Array(U)` and into the other
    // iterable-named target types.
    (Applied("Array", [s_inner]), Array(t_inner)) =>
      is_assignable_to_inner(s_inner, t_inner, bivariant_params)
    // Readonly arrays / iterable protocol types: when the source is named
    // with one of the array-like iterable names, allow it to flow into any
    // other array-like iterable name (element type covariant). Excludes
    // `Array` itself from the source side to preserve readonly→mutable
    // rejection (that's the TS rule we care about).
    (Applied(s_name, [s_inner]), Applied(t_name, [t_inner])) =>
      if s_name == t_name {
        is_assignable_to_inner(s_inner, t_inner, bivariant_params)
      } else if is_array_like_iterable_name(s_name) &&
        is_array_like_iterable_name(t_name) &&
        // Mutable→readonly is fine; readonly→mutable is not. `Array`
        // doesn't appear in `is_array_like_iterable_name`, so a
        // mutable source named `Applied("Array", ...)` lands in the
        // preceding `(Applied("Array", ...), Array(...))` branch and
        // never reaches here.
        t_name != "Array" {
        is_assignable_to_inner(s_inner, t_inner, bivariant_params)
      } else {
        false
      }
    // Compound covariance/contravariance.
    (Array(s_inner), Array(t_inner)) =>
      is_assignable_to_inner(s_inner, t_inner, bivariant_params)
    // Tuples are iterable: `[A, B]` is assignable to `Iterable<A | B>` etc.
    // The element type is the union of the tuple's slot types.
    (Tuple(s_items), Applied(t_name, [t_inner])) =>
      if is_array_like_iterable_name(t_name) {
        s_items
        .iter()
        .all(fn(it) { is_assignable_to_inner(it, t_inner, bivariant_params) })
      } else {
        false
      }
    (Tuple(s_items), Tuple(t_items)) =>
      tuple_assignable(s_items, t_items, bivariant_params)
    // Rest parameter types: `...args: T[]` — delegate to the inner array type.
    (Rest(s), Rest(t)) => is_assignable_to_inner(s, t, bivariant_params)
    (Rest(s), Array(t)) => is_assignable_to_inner(s, t, bivariant_params)
    (Array(s), Rest(t)) => is_assignable_to_inner(s, t, bivariant_params)
    // Constructor types: `new (...) => T`. Abstract constructors are a
    // subtype of non-abstract constructors (conservative approximation).
    (Constructor(s_params, s_ret, _), Constructor(t_params, t_ret, _)) => {
      if s_params.length() != t_params.length() {
        return false
      }
      for i in 0..<s_params.length() {
        let ok = if bivariant_params {
          is_assignable_to_inner(s_params[i], t_params[i], bivariant_params) ||
          is_assignable_to_inner(t_params[i], s_params[i], bivariant_params)
        } else {
          is_assignable_to_inner(t_params[i], s_params[i], bivariant_params)
        }
        if !ok {
          return false
        }
      }
      is_assignable_to_inner(s_ret, t_ret, bivariant_params)
    }
    // A constructor type is callable as a function (via Reflect.construct etc.)
    (Constructor(s_params, s_ret, _), Func(t_params, t_ret)) => {
      if s_params.length() != t_params.length() {
        return false
      }
      for i in 0..<s_params.length() {
        if !is_assignable_to_inner(t_params[i], s_params[i], bivariant_params) {
          return false
        }
      }
      is_assignable_to_inner(s_ret, t_ret, bivariant_params)
    }
    (Func(s_params, s_ret), Func(t_params, t_ret)) => {
      if !func_params_assignable(s_params, t_params, bivariant_params) {
        return false
      }
      // Covariant return.
      is_assignable_to_inner(s_ret, t_ret, bivariant_params)
    }
    (Object(s_fields), Object(t_fields)) =>
      is_object_assignable_inner(s_fields, t_fields, bivariant_params)
    // Struct types are structurally compatible with Object types and each other.
    (Struct(_, s_fields), Struct(_, t_fields)) => {
      let s_obj = struct_fields_to_object(s_fields)
      let t_obj = struct_fields_to_object(t_fields)
      is_object_assignable_inner(s_obj, t_obj, bivariant_params)
    }
    (Struct(_, s_fields), Object(t_fields)) => {
      let s_obj = struct_fields_to_object(s_fields)
      is_object_assignable_inner(s_obj, t_fields, bivariant_params)
    }
    (Object(s_fields), Struct(_, t_fields)) => {
      let t_obj = struct_fields_to_object(t_fields)
      is_object_assignable_inner(s_fields, t_obj, bivariant_params)
    }
    // Named/applied references are nominal: only equal names match.
    (Named(a), Named(b)) => a == b
    (Applied(a, args_a), Applied(b, args_b)) => {
      if a != b || args_a.length() != args_b.length() {
        return false
      }
      for i in 0..<args_a.length() {
        if !is_assignable_to_inner(args_a[i], args_b[i], bivariant_params) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
fn struct_fields_to_object(
  fields : Array[(String, @ast.TsType)],
) -> Array[(@ast.TsType, @ast.TsType)] {
  let out : Array[(@ast.TsType, @ast.TsType)] = []
  for f in fields {
    out.push((@ast.TsType::Literal(f.0), f.1))
  }
  out
}

///|
// True when the key represents an index signature rather than a named
// property. TS supports `string`, `number`, and `symbol` keyed index
// signatures (and the parser may also surface `Literal("__index__")`
// shapes — those are unrelated and not handled here).
fn is_index_signature_key(key : @ast.TsType) -> Bool {
  match key {
    String_ | Number | Symbol => true
    _ => false
  }
}

///|
// Pull out the value type of an index signature on `key_kind` if `fields`
// declares one. Returns `None` when no matching signature exists.
fn find_index_signature(
  fields : Array[(@ast.TsType, @ast.TsType)],
  key_kind : @ast.TsType,
) -> @ast.TsType? {
  for f in fields {
    if f.0 == key_kind {
      return Some(f.1)
    }
  }
  None
}

///|
// Which index-signature bucket a literal key falls into. TS coerces
// numeric-string literal keys (`"0"`, `"42"`) into the number-index
// signature when one exists; otherwise the string-index signature.
fn literal_key_index_bucket(key : @ast.TsType) -> @ast.TsType? {
  match key {
    Literal(name) =>
      if is_number_string(name) {
        Some(Number)
      } else {
        Some(String_)
      }
    NumberLiteral(_) => Some(Number)
    _ => None
  }
}

///|
fn is_object_assignable_inner(
  s_fields : Array[(@ast.TsType, @ast.TsType)],
  t_fields : Array[(@ast.TsType, @ast.TsType)],
  bivariant_params : Bool,
) -> Bool {
  for t_field in t_fields {
    let (t_key, t_type) = t_field
    if is_index_signature_key(t_key) {
      // Every source field of a matching kind must satisfy the signature.
      for s_field in s_fields {
        let (s_key, s_type) = s_field
        let bucket = if is_index_signature_key(s_key) {
          Some(s_key)
        } else {
          literal_key_index_bucket(s_key)
        }
        match bucket {
          Some(k) if k == t_key =>
            if !is_assignable_to_inner(s_type, t_type, bivariant_params) {
              return false
            }
          _ => ()
        }
      }
      continue
    }
    let mut matched = false
    for s_field in s_fields {
      let (s_key, s_type) = s_field
      if s_key == t_key {
        if !is_assignable_to_inner(s_type, t_type, bivariant_params) {
          return false
        }
        matched = true
        break
      }
    }
    if matched {
      continue
    }
    // No exact source field — try matching against a source index signature
    // of the appropriate bucket. `{ [k: string]: number }` is assignable to
    // `{ foo: number }` because the indexer guarantees the named key, too.
    let bucket = literal_key_index_bucket(t_key)
    let source_index_value = match bucket {
      Some(Number) =>
        match find_index_signature(s_fields, Number) {
          Some(v) => Some(v)
          None => find_index_signature(s_fields, String_)
        }
      Some(String_) => find_index_signature(s_fields, String_)
      _ => None
    }
    match source_index_value {
      Some(v) =>
        if is_assignable_to_inner(v, t_type, bivariant_params) {
          continue
        }
      None => ()
    }
    // A target field whose type accepts `undefined` (the desugaring of
    // `x?: T`) tolerates the source missing that field entirely.
    if !type_accepts_undefined(t_type) {
      return false
    }
  }
  true
}

///|
fn type_accepts_undefined(t : @ast.TsType) -> Bool {
  match t {
    Undefined | Any => true
    Union(members) => {
      for m in members {
        if type_accepts_undefined(m) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
// Resolve `T[K]` once: when `T` is a structural Object/Struct and `K` is a
// string literal that names one of the fields, return the field type. Any
// other case (generic T, computed K, missing field) returns `Any` to keep the
// caller permissive — TypeScript's fallback for unknown indexed access is
// effectively the same.
fn resolve_indexed_access_local(t : @ast.TsType) -> @ast.TsType {
  match t {
    IndexedAccess(base, key) => {
      let key_name = match key {
        Literal(name) => name
        _ => return Any
      }
      match base {
        Object(fields) => {
          for field in fields {
            let (k, v) = field
            match k {
              Literal(field_name) => if field_name == key_name { return v }
              _ => ()
            }
          }
          Any
        }
        Struct(_, fields) => {
          for field in fields {
            let (field_name, v) = field
            if field_name == key_name {
              return v
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

///|
// Reduce `A extends B ? X : Y` to a concrete branch:
//   - If `B` contains `infer` markers, try `match_infer_pattern(A, B)` and
//     substitute the captured names into `X` on success. On failure (no
//     match), pick `Y`.
//   - Otherwise fall back to `is_assignable_to(A, B)`.
// If neither attempt yields a definite answer, return the conditional
// unchanged so the surrounding match falls through to `_ => false`.
fn reduce_conditional(t : @ast.TsType) -> @ast.TsType {
  match t {
    Conditional(check, extends, true_branch, false_branch) =>
      if contains_infer_marker(extends) {
        let bindings : Map[String, @ast.TsType] = {}
        if match_infer_pattern(check, extends, bindings) {
          substitute_inferred_type(true_branch, bindings)
        } else {
          false_branch
        }
      } else if is_assignable_to(check, extends) {
        true_branch
      } else {
        false_branch
      }
    _ => t
  }
}

///|
fn contains_infer_marker(t : @ast.TsType) -> Bool {
  match infer_marker_name(t) {
    Some(_) => return true
    None => ()
  }
  match t {
    Array(inner) => contains_infer_marker(inner)
    Tuple(items) => {
      for it in items {
        if contains_infer_marker(it) {
          return true
        }
      }
      false
    }
    Object(fields) => {
      for f in fields {
        if contains_infer_marker(f.0) || contains_infer_marker(f.1) {
          return true
        }
      }
      false
    }
    Func(params, ret) => {
      for p in params {
        if contains_infer_marker(p) {
          return true
        }
      }
      contains_infer_marker(ret)
    }
    Union(items) | Intersection(items) => {
      for it in items {
        if contains_infer_marker(it) {
          return true
        }
      }
      false
    }
    Conditional(check, extends, t_branch, f_branch) =>
      contains_infer_marker(check) ||
      contains_infer_marker(extends) ||
      contains_infer_marker(t_branch) ||
      contains_infer_marker(f_branch)
    Applied(_, args) => {
      for a in args {
        if contains_infer_marker(a) {
          return true
        }
      }
      false
    }
    IndexedAccess(base, key) =>
      contains_infer_marker(base) || contains_infer_marker(key)
    _ => false
  }
}

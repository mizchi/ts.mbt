// ============================================
// type
// ============================================

///|
/// Preserve the source spelling of optional callable parameters without
/// changing the existing `T | undefined` semantic representation. Wrapping
/// only when needed leaves ordinary function types structurally unchanged.
fn callable_type_with_optionality(
  callable : @ast.TsType,
  optional_params : Array[Bool],
) -> @ast.TsType {
  for is_optional in optional_params {
    if is_optional {
      return @ast.TsType::CallableMeta(callable, optional_params)
    }
  }
  callable
}

///|
/// Build a function type from declaration-style parameters while retaining
/// both the existing value-level shape and source optionality metadata.
fn callable_func_type_from_params(
  params : Array[@ast.TsParam],
  return_type : @ast.TsType,
) -> @ast.TsType {
  let types : Array[@ast.TsType] = []
  let optional : Array[Bool] = []
  for param in params {
    // Declaration-style rest parameters already carry their array-shaped
    // element type (`...checks: string[]` -> `Array[String]`). Keep the
    // existing representation used by interface/object members; function
    // *type* syntax builds `Rest` directly in `parse_paren_or_function_type`.
    types.push(param.type_)
    optional.push(param.is_optional)
  }
  callable_type_with_optionality(
    @ast.TsType::Func(types, return_type),
    optional,
  )
}

///|
/// The member-name spelling of a keyword token, for object-type members
/// whose key happens to be a keyword (`{ type: T }`, `{ function: T }`).
/// `New` is handled separately (construct-signature ambiguity).
fn keyword_member_name(kind : TokenKind) -> String? {
  match kind {
    Type => Some("type")
    Function => Some("function")
    Class => Some("class")
    Extends => Some("extends")
    Var => Some("var")
    Let => Some("let")
    Const => Some("const")
    Return => Some("return")
    If => Some("if")
    Else => Some("else")
    Switch => Some("switch")
    Case => Some("case")
    Default => Some("default")
    With => Some("with")
    Debugger => Some("debugger")
    Import => Some("import")
    Export => Some("export")
    From => Some("from")
    As => Some("as")
    While => Some("while")
    Do => Some("do")
    For => Some("for")
    Break => Some("break")
    Continue => Some("continue")
    Try => Some("try")
    Catch => Some("catch")
    Finally => Some("finally")
    Throw => Some("throw")
    Yield => Some("yield")
    Typeof => Some("typeof")
    Delete => Some("delete")
    Instanceof => Some("instanceof")
    Interface => Some("interface")
    Of => Some("of")
    In => Some("in")
    Declare => Some("declare")
    Null => Some("null")
    Bool(true) => Some("true")
    Bool(false) => Some("false")
    NumberType => Some("number")
    BooleanType => Some("boolean")
    StringType => Some("string")
    VoidType => Some("void")
    _ => None
  }
}

///|
/// Check if current token is an identifier
fn Parser::is_ident(self : Parser) -> Bool {
  match self.peek().kind {
    Ident(_) => true
    _ => false
  }
}

///|
fn Parser::parse_paren_or_function_type(
  self : Parser,
) -> @ast.TsType raise ParseError {
  let saved_pos = self.pos
  let _ = self.expect(LParen)
  if self.match_(RParen) {
    if self.match_(Arrow) {
      return Func([], self.parse_type())
    }
    return Any
  }

  let param_types : Array[@ast.TsType] = []
  let param_optional : Array[Bool] = []
  let mut can_be_function_type = true
  while true {
    let is_rest = self.match_ellipsis()
    let _ = self.parse_declare_param_name() catch {
      _ => {
        can_be_function_type = false
        break
      }
    }
    let is_optional = self.match_(Question)
    // Type annotation on a function-type parameter is optional —
    // `(item) => T` is a valid TS arrow function type. A `...rest` param is
    // wrapped in `Rest(...)` so call-site checking treats each trailing
    // argument as the array's *element* type (matching module-function
    // params), not the whole array.
    let pty = if self.match_(Colon) {
      self.parse_type()
    } else {
      @ast.TsType::Any
    }
    // An optional function-type parameter (`(x?: T) => R`) widens to
    // `T | undefined`, mirroring declaration parameters, so arity / required-
    // param reasoning sees it as omittable.
    let pty = if is_optional { wrap_optional_ts_type(pty) } else { pty }
    param_types.push(if is_rest { Rest(pty) } else { pty })
    param_optional.push(is_optional)
    if self.match_(Comma) {
      if self.check(RParen) {
        break
      }
      continue
    }
    break
  }
  if can_be_function_type && self.match_(RParen) && self.match_(Arrow) {
    return callable_type_with_optionality(
      Func(param_types, self.parse_type()),
      param_optional,
    )
  }

  self.pos = saved_pos
  let _ = self.expect(LParen)
  let inner = self.parse_type()
  let _ = self.expect(RParen)
  inner
}

///|
/// Parse the tail of a constructor type after the `new` keyword has been
/// consumed: optional `<...>` type params, `(...)` parameter list, then
/// `=> T`. Falls back to `Any` when any part fails so the existing
/// permissive behavior is preserved on malformed sources.
fn Parser::parse_constructor_tail(
  self : Parser,
  is_abstract : Bool,
) -> @ast.TsType raise ParseError {
  // Capture the constructor type's own generic parameters (`new <T>(x: T) =>
  // T`) so scope-aware checks can see the binder; the names are erased for
  // the value shape (see `GenericFunc`).
  let (tp_names, tp_bounds) = if self.check(Lt) {
    self.parse_type_param_names_and_bounds()
  } else {
    ([], [])
  }
  if !self.check(LParen) {
    return Any
  }
  let saved = self.pos
  let _ = self.expect(LParen)
  let param_types : Array[@ast.TsType] = []
  let param_optional : Array[Bool] = []
  if !self.match_(RParen) {
    let mut ok = true
    while true {
      let is_rest = self.match_ellipsis()
      let _ = self.parse_declare_param_name() catch {
        _ => {
          ok = false
          break
        }
      }
      let is_optional = self.match_(Question)
      let pty = if self.match_(Colon) {
        self.parse_type()
      } else {
        @ast.TsType::Any
      }
      // Optional constructor-type parameter widens to `T | undefined`, like
      // function-type and declaration parameters.
      let pty = if is_optional { wrap_optional_ts_type(pty) } else { pty }
      param_types.push(if is_rest { Rest(pty) } else { pty })
      param_optional.push(is_optional)
      if self.match_(Comma) {
        if self.check(RParen) {
          break
        }
        continue
      }
      break
    }
    if !ok {
      self.pos = saved
      self.skip_paren_type()
      return Any
    }
    let _ = self.expect(RParen)
  }
  if !self.match_(Arrow) {
    return Any
  }
  let ret = self.parse_type()
  let ctor = callable_type_with_optionality(
    @ast.TsType::Constructor(param_types, ret, is_abstract),
    param_optional,
  )
  if tp_names.length() > 0 {
    GenericFunc(tp_names, tp_bounds, ctor)
  } else {
    ctor
  }
}

///|
fn Parser::parse_tuple_type(self : Parser) -> @ast.TsType raise ParseError {
  let _ = self.expect(LBracket)
  let items : Array[@ast.TsType] = []
  if self.match_(RBracket) {
    return Tuple(items)
  }
  // TS1257: a required element cannot follow an optional one
  // (`[string?, number]`). A rest element is neither required nor optional
  // for this rule, so `[string?, ...number[]]` stays valid. Tracked across
  // the element loop and surfaced once per offending tuple.
  let mut seen_optional = false
  let mut required_after_optional = false
  while !self.check(Eof) {
    let is_rest = self.match_ellipsis()
    // Labels like `[name: T]` strip the label tokens; `[name?: T]` is
    // additionally an optional element (equivalent to a trailing `?`
    // on the type itself). TS allows reserved keywords as label
    // names (e.g. `[declare: AmdModuleDeclaration]`), so accept any
    // identifier-shaped token via `is_tuple_label_token` rather than
    // a strict `Ident(_)` match.
    let label_optional = if self.is_tuple_label_token(0) &&
      self.peek_at(1).kind == Colon {
      let _ = self.advance()
      let _ = self.expect(Colon)
      false
    } else if self.is_tuple_label_token(0) &&
      self.peek_at(1).kind == Question &&
      self.peek_at(2).kind == Colon {
      let _ = self.advance()
      let _ = self.advance()
      let _ = self.expect(Colon)
      true
    } else {
      false
    }
    let item_type = self.parse_type()
    let trailing_optional = self.match_(Question)
    let is_optional = label_optional || trailing_optional
    if is_optional {
      seen_optional = true
    } else if !is_rest && seen_optional {
      required_after_optional = true
    }
    let with_optional : @ast.TsType = if is_optional {
      wrap_optional_ts_type(item_type)
    } else {
      item_type
    }
    items.push(if is_rest { Rest(with_optional) } else { with_optional })
    if self.match_(Comma) {
      if self.match_(RBracket) {
        break
      }
      continue
    }
    let _ = self.expect(RBracket)
    break
  }
  if required_after_optional {
    self.interface_member_modifier_misuses.push(
      "<tuple-required-after-optional>",
    )
  }
  Tuple(items)
}

///|
fn mapped_object_key_names(type_ : @ast.TsType) -> Array[String]? {
  match type_ {
    Literal(name) => Some([name])
    Union(items) => {
      let names : Array[String] = []
      for item in items {
        match item {
          Literal(name) => names.push(name)
          _ => return None
        }
      }
      Some(names)
    }
    _ => None
  }
}

///|
fn Parser::try_parse_simple_mapped_object_type_after_lbrace(
  self : Parser,
) -> @ast.TsType? {
  let saved_pos = self.pos
  try {
    // Leading `readonly` / `+readonly` / `-readonly` modifier. We don't
    // track readonly at the type level, so the modifier is consumed but
    // not retained.
    if self.match_(Plus) || self.match_(Minus) {
      let _ = self.match_ident("readonly")
    } else {
      let _ = self.match_ident("readonly")
    }
    let _ = self.expect(LBracket)
    let key_param = match self.peek().kind {
      Ident(name) => {
        let _ = self.advance()
        name
      }
      _ => {
        self.pos = saved_pos
        return None
      }
    }
    if !(self.match_(In) || self.match_ident("in")) {
      self.pos = saved_pos
      return None
    }
    let keys_type = self.parse_type()
    let remap : @ast.TsType? = if self.match_(As) || self.match_ident("as") {
      Some(self.parse_type())
    } else {
      None
    }
    let _ = self.expect(RBracket)
    // Trailing optional modifier:
    //   `?`  / `+?` — widen value to `T | undefined`
    //   `-?`        — strip `undefined` from `T` (post-substitution)
    //   none        — use `T` as-is
    let optional = if self.match_(Question) {
      true
    } else if self.match_(Plus) {
      self.match_(Question)
    } else {
      false
    }
    let strip_undef = if !optional && self.match_(Minus) {
      self.match_(Question)
    } else {
      false
    }
    let _ = self.expect(Colon)
    let raw_value = self.parse_type()
    // Encode the `-?` modifier by wrapping the value in a marker the
    // simplifier strips after per-key substitution. Stays inert when
    // the source remains opaque, so legacy passes still see a normal
    // `MappedType`.
    let value_type : @ast.TsType = if strip_undef {
      Applied("__tsmbt_strip_undef", [raw_value])
    } else {
      raw_value
    }
    let _ = self.match_(Semicolon) || self.match_(Comma)
    let _ = self.expect(RBrace)
    // With `as Remap`: preserve the remap binder shape so the simplifier
    // can substitute per key. We don't take a fast-path here because the
    // remap may filter / rewrite keys.
    match remap {
      Some(r) =>
        return Some(
          MappedTypeRemap(key_param, keys_type, r, value_type, optional),
        )
      None => ()
    }
    // Fast path: when the key source is already a finite literal union
    // and the value never references the binder, just materialize an
    // object so legacy passes that don't know about `MappedType` keep
    // working. Otherwise preserve the binder shape so simplification can
    // resolve it later (e.g. when `Source` is `Keyof T` for an opaque
    // `T` that becomes concrete after substitution).
    match mapped_object_key_names(keys_type) {
      Some(keys) if !mapped_value_references_binder(value_type, key_param) => {
        let fields : Array[(@ast.TsType, @ast.TsType)] = []
        let field_type = if optional {
          wrap_optional_ts_type(value_type)
        } else {
          value_type
        }
        for key in keys {
          fields.push((Literal(key), field_type))
        }
        Some(Object(fields))
      }
      _ => Some(MappedType(key_param, keys_type, value_type, optional))
    }
  } catch {
    _ => {
      self.pos = saved_pos
      None
    }
  }
}

///|
/// Walk a value position of a mapped type (`{ [K in U]: V }`) and report
/// whether `V` references the binder `K` (as `Named(key_param)`). This
/// determines whether the parser materializes an Object eagerly or keeps
/// the `MappedType` so the simplifier can substitute per key.
fn mapped_value_references_binder(
  value : @ast.TsType,
  key_param : String,
) -> Bool {
  match value {
    Named(name) => name == key_param
    Applied(_, args) => {
      for a in args {
        if mapped_value_references_binder(a, key_param) {
          return true
        }
      }
      false
    }
    Array(inner) => mapped_value_references_binder(inner, key_param)
    Tuple(items) => {
      for it in items {
        if mapped_value_references_binder(it, key_param) {
          return true
        }
      }
      false
    }
    Rest(inner) => mapped_value_references_binder(inner, key_param)
    Object(fields) => {
      for f in fields {
        if mapped_value_references_binder(f.1, key_param) {
          return true
        }
      }
      false
    }
    Func(params, ret) => {
      for p in params {
        if mapped_value_references_binder(p, key_param) {
          return true
        }
      }
      mapped_value_references_binder(ret, key_param)
    }
    Union(items) | Intersection(items) => {
      for it in items {
        if mapped_value_references_binder(it, key_param) {
          return true
        }
      }
      false
    }
    Conditional(check, ext, t, f) =>
      mapped_value_references_binder(check, key_param) ||
      mapped_value_references_binder(ext, key_param) ||
      mapped_value_references_binder(t, key_param) ||
      mapped_value_references_binder(f, key_param)
    IndexedAccess(base, k) =>
      mapped_value_references_binder(base, key_param) ||
      mapped_value_references_binder(k, key_param)
    Keyof(inner) => mapped_value_references_binder(inner, key_param)
    MappedType(inner_key, _, _, _) if inner_key == key_param => false
    MappedType(_, src, val, _) =>
      mapped_value_references_binder(src, key_param) ||
      mapped_value_references_binder(val, key_param)
    MappedTypeRemap(inner_key, _, _, _, _) if inner_key == key_param => false
    MappedTypeRemap(_, src, rmap, val, _) =>
      mapped_value_references_binder(src, key_param) ||
      mapped_value_references_binder(rmap, key_param) ||
      mapped_value_references_binder(val, key_param)
    TemplateLiteralType(_, args) => {
      for a in args {
        if mapped_value_references_binder(a, key_param) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn Parser::try_parse_simple_object_type(self : Parser) -> @ast.TsType? {
  if !self.check(LBrace) {
    return None
  }
  let saved_pos = self.pos
  let fields : Array[(@ast.TsType, @ast.TsType)] = []
  try {
    let _ = self.expect(LBrace)
    match self.try_parse_simple_mapped_object_type_after_lbrace() {
      Some(type_) => return Some(type_)
      None => ()
    }
    while !self.check(Eof) && !self.check(RBrace) {
      // Accept identifiers *and* keyword tokens as property names
      // (`{ type: T }`, `{ default: U }`, …). `type` is the canonical
      // discriminated-union discriminant, so rejecting it here dropped the
      // whole object type and produced spurious "property does not exist"
      // diagnostics. `parse_property_name_token` handles every keyword the
      // interface parser does and raises on a genuine non-name token (call
      // / construct / index signatures, string/number literal names), which
      // the enclosing `try` turns into a clean fall-through to the fuller
      // member parser.
      let field_name = match self.peek().kind {
        LParen | Lt | New | LBracket | Str(_) | Number(_) | Int(_) => {
          self.pos = saved_pos
          return None
        }
        _ => self.parse_property_name_token()
      }
      let is_optional = self.match_(Question)
      let _ = self.expect(Colon)
      let field_type = self.parse_type()
      // A `?`-optional member desugars to `T | undefined` so assignability
      // tolerates the property being absent. The fuller member parser already
      // does this via `wrap_optional_ts_type`; this fast path previously
      // dropped the `?`, making optional members look required.
      fields.push(
        (
          Literal(field_name),
          if is_optional {
            wrap_optional_ts_type(field_type)
          } else {
            field_type
          },
        ),
      )
      if self.match_(Semicolon) || self.match_(Comma) {
        continue
      }
      if self.has_line_terminator_before() {
        match self.peek().kind {
          Ident(_) | RBrace => continue
          _ => ()
        }
      }
      if self.check(RBrace) {
        break
      }
      self.pos = saved_pos
      return None
    }
    let _ = self.expect(RBrace)
    Some(Object(fields))
  } catch {
    _ => {
      self.pos = saved_pos
      None
    }
  }
}

///|
/// True for an index-signature parameter type TypeScript definitely
/// rejects (TS1268). Legal keys are `string`, `number`, `symbol` and a
/// template literal type.
///
/// A DENYLIST rather than the complement of that four-element allowlist,
/// because the shapes that matter are the ones this must abstain on. Each
/// was probed against tsc:
///
///   type K = string; { [k: K]: V }        legal    (alias to `string`)
///   { [k: string | number]: V }           legal    (union)
///   { [k: RegExp]: V }                    TS1268
///
/// The alias and `RegExp` are the same `Named` node here, so no predicate
/// over the syntax can separate them without resolving the alias — which
/// the parser cannot do. Abstaining on `Named` costs `RegExp` (a MISS) and
/// keeps the alias (no FP), which is the correct direction for a 0-FP
/// gate. Unions, literal types (`{ [k: "lit"]: V }` is TS1337, a different
/// rule) and everything else likewise abstain.
fn index_signature_key_type_rejected(t : @ast.TsType) -> Bool {
  match t {
    Boolean
    | Any
    | Unknown
    | Never
    | Void
    | Undefined
    | Null
    | NonPrimitiveObject
    | BigInt => true
    _ => false
  }
}

///|
/// TS1169 / TS1170: a computed property name in an INTERFACE (1169) or a
/// TYPE LITERAL (1170) must refer to an expression whose type is a literal
/// type or a `unique symbol`. Recorded for the key expressions that
/// definitely are neither.
///
/// The cursor must sit just after the opening `[`. The test is a DENYLIST
/// of three token shapes at bracket depth 0, so an unrecognised key
/// abstains:
///
///   an assignment operator     `[a = 0]`        TS1169
///   a binary operator          `["" + ""]`      TS1169 / TS1170
///   a call's `(`, not first    `[foo<T>()]`     TS1169
///
/// Every legal spelling was probed and none matches: a string or number
/// literal key (`["lit"]`, `[1]`), a bare identifier (`[e]` over a
/// `unique symbol`), a dotted reference (`[E.A]` over a const enum), a
/// template literal, and a well-known symbol key (consumed earlier). The
/// "not first" condition on `(` is what keeps a parenthesised reference
/// (`[(e)]`) out of it while still catching a call.
///
/// The rule is interface / type-literal ONLY. A CLASS computed key and an
/// OBJECT LITERAL computed key are both legal with an arbitrary
/// expression (`class C { ["" + ""]() {} }` is clean tsc), which is why
/// this is not recorded from the class member parser.
fn Parser::record_computed_member_key_misuse(
  self : Parser,
  container : String,
) -> Unit {
  let mut i = 0
  let mut depth = 0
  let mut flagged = false
  // 64 tokens is well past any real computed key; a runaway scan abstains
  // rather than guessing.
  while i < 64 {
    let k = self.peek_at(i).kind
    match k {
      Eof => break
      RBracket => if depth == 0 { break } else { depth -= 1 }
      RParen | RBrace => depth -= 1
      LBracket | LBrace => depth += 1
      LParen => {
        // A call's argument list. At depth 0 and not the first token this
        // is `f(…)`; first means `( … )`, a parenthesised reference.
        if depth == 0 && i > 0 {
          flagged = true
        }
        depth += 1
      }
      Eq
      | Plus
      | Minus
      | Star
      | StarStar
      | Slash
      | Percent
      | Caret
      | Amp
      | Pipe => if depth == 0 { flagged = true }
      _ => ()
    }
    i += 1
  }
  if flagged {
    self.record_suppressible_grammar_misuse(
      "a computed property name in \{container} must refer to an expression whose type is a literal type or a `unique symbol` type",
    )
  }
}

///|
/// Record the malformed index-signature parameter lists, given a cursor
/// positioned just after the opening `[` of a bracket-headed type member.
///
/// Called from BOTH member parsers — the type-literal one in this file and
/// the interface one in `parser_function.mbt`. They are near-duplicates of
/// each other, and writing the rule inline at one of them is how it would
/// come to hold for `{ [k: any]: V }` and not for the identical
/// `interface I { [k: any]: V }`; the first draft of this batch did exactly
/// that and won 2 of 8 target files.
///
/// Only shapes no legal spelling produces are recorded. The ones that must
/// ABSTAIN were each probed against tsc: a mapped type
/// (`[K in keyof T]`, recognised by the `in` follower), a computed key
/// (`[e]` over a `unique symbol`), and a well-known-symbol key, all legal.
fn Parser::record_index_signature_shape_misuse(self : Parser) -> Unit {
  match (self.peek().kind, self.peek_at(1).kind) {
    // `[]: number` and `[a, b]: number` — TS1096.
    (RBracket, _) | (Ident(_), Comma) =>
      self.record_suppressible_grammar_misuse(
        "an index signature must have exactly one parameter",
      )
    // `[...a]` — TS1017.
    (Ellipsis, _) =>
      self.record_suppressible_grammar_misuse(
        "an index signature cannot have a rest parameter",
      )
    // `[a?]` / `[a?: string]` — TS1019.
    (Ident(_), Question) =>
      self.record_suppressible_grammar_misuse(
        "an index signature parameter cannot have a question mark",
      )
    _ => ()
  }
}

///|
/// TS1268 for a canonical `[ident: Type]` head whose key type TypeScript
/// rejects. See `index_signature_key_type_rejected` for why the decision is
/// a denylist, and `record_index_signature_shape_misuse` for why this is a
/// shared function rather than two copies.
fn Parser::record_index_signature_key_misuse(
  self : Parser,
  key_type : @ast.TsType,
) -> Unit {
  if index_signature_key_type_rejected(key_type) {
    self.record_suppressible_grammar_misuse(
      "an index signature parameter type must be `string`, `number`, `symbol` or a template literal type",
    )
  }
}

///|
/// TS1021: `interface I { [a: string] }` — a canonical index-signature head
/// with no value annotation. No legal spelling produces it: a mapped type
/// never reaches these arms, and an optional index signature
/// (`[k: string]?: V`) is itself a tsc syntax error.
fn Parser::record_index_signature_missing_annotation(self : Parser) -> Unit {
  self.record_suppressible_grammar_misuse(
    "an index signature must have a type annotation",
  )
}

///|
/// The standard well-known symbols of `SymbolConstructor`. Mirrors the
/// checker's `is_well_known_symbol_name`; the parser needs its own copy
/// (package boundary) to decide which `[Symbol.x]` type-literal keys are
/// safe to encode as `@@x` members.
fn is_standard_well_known_symbol(name : String) -> Bool {
  match name {
    "iterator"
    | "asyncIterator"
    | "hasInstance"
    | "isConcatSpreadable"
    | "match"
    | "matchAll"
    | "replace"
    | "search"
    | "species"
    | "split"
    | "toPrimitive"
    | "toStringTag"
    | "unscopables"
    | "dispose"
    | "asyncDispose"
    | "metadata" => true
    _ => false
  }
}

///|
/// Parse an object type literal that may include method signatures
/// (`m(x): T`), call signatures (`(x): T`), construct signatures
/// (`new (x): T`), index signatures (`[k: K]: V`), and ordinary
/// properties, producing an `Object`. Index signatures are kept (keyed
/// by the key type, with an `Any` value) so the "any key" meaning
/// survives; call / construct signatures use the `<call>` / `<new>`
/// sentinel keys the rest of the toolchain already uses. Returns `None`
/// (and restores the cursor) on any shape this parser doesn't
/// recognise, so the caller can fall back to the legacy skip-to-`Any`
/// path with no behavioural regression.
fn Parser::try_parse_object_type_with_members(self : Parser) -> @ast.TsType? {
  if !self.check(LBrace) {
    return None
  }
  let saved_pos = self.pos
  let fields : Array[(@ast.TsType, @ast.TsType)] = []
  // TS1005 (';' expected): two object-type members on the SAME line with no
  // `,` / `;` separator (`{ foo: string bar: string }`). A line break between
  // members is fine (ASI), so the check requires the next member token to sit
  // on the same line. Recorded only on the success path so a speculative parse
  // that later falls back leaves no spurious diagnostic.
  let mut missing_separator = false
  try {
    let _ = self.expect(LBrace)
    while !self.check(Eof) && !self.check(RBrace) {
      // Skip a leading `readonly` modifier (only meaningful for emit).
      if self.can_consume_interface_readonly_modifier() {
        let _ = self.advance()
      }
      let field_name : String = match self.peek().kind {
        LParen => "<call>"
        Lt => {
          self.skip_type_params()
          "<call>"
        }
        // `new` followed by a member-key token is a PROPERTY named
        // `new` (`{ new: string }`); otherwise it heads a construct
        // signature.
        New =>
          if self.peek_at(1).kind
            is (Colon | Question | Semicolon | Comma | RBrace) {
            let _ = self.advance()
            "new"
          } else {
            let _ = self.advance()
            "<new>"
          }
        LBracket => {
          // Index signature `[k: K]: V`. The checker / mangle passes
          // encode these inside `Object` as a field keyed by the *key
          // type itself* (`String_` / `Number` / `Symbol`, recognised by
          // `is_index_signature_key`), so preserve it that way rather
          // than dropping it (which would erase the "any key" meaning
          // mangle-safety relies on). Anything that isn't the canonical
          // `[ident: Type]: Type` shape (computed keys, etc.) falls back.
          let _ = self.advance()
          // Well-known symbol member key (`[Symbol.iterator]?(): T`):
          // encode with the toolchain's `@@name` convention so the
          // checker can reason about the iteration protocol (for-of29).
          // Only the STANDARD well-known symbols participate — a
          // user-augmented `Symbol.foo` (symbolProperty61) keeps the
          // legacy fall-back so we never invent a required member the
          // checker can't match structurally.
          let well_known_sym : String? = match
            (self.peek().kind, self.peek_at(1).kind, self.peek_at(2).kind) {
            (Ident("Symbol"), Dot, Ident(sym)) if self.peek_at(3).kind ==
              RBracket &&
              is_standard_well_known_symbol(sym) => Some(sym)
            _ => None
          }
          if well_known_sym is Some(sym) {
            let _ = self.advance()
            let _ = self.advance()
            let _ = self.advance()
            let _ = self.advance()
            "@@" + sym
          } else {
            let is_index_sig = match self.peek().kind {
              Ident(_) => self.peek_at(1).kind == Colon
              _ => false
            }
            if !is_index_sig {
              self.record_index_signature_shape_misuse()
              self.record_computed_member_key_misuse("a type literal")
              // TS2304: a computed key in a *type* literal (`{ [e]: number }`,
              // `{ [e](): T }`) references the value namespace. Record the
              // bare-identifier shape so the checker can flag a provably
              // undeclared name. Dotted keys (`[Symbol.iterator]`) don't match
              // the single-token shape, and function bodies are skipped (the
              // name may be a local we can't resolve at module level).
              match self.peek().kind {
                Ident(key) if self.peek_at(1).kind == RBracket &&
                  !self.in_function =>
                  self.grammar_misuses.push("<computed-type-key>" + key)
                _ => ()
              }
              self.pos = saved_pos
              return None
            }
            let _ = self.advance() // index name
            let _ = self.expect(Colon)
            let key_type = self.parse_type()
            self.record_index_signature_key_misuse(key_type)
            let _ = self.expect(RBracket)
            let _ = self.match_(Question)
            // Consume the value type to advance the cursor, but record the
            // signature with an `Any` value. Keeping the index signature
            // (key typed `String_` / `Number`) preserves the "any key"
            // meaning the mangle-safety and TS2454 passes need; widening
            // the value to `Any` keeps us from driving value-assignability
            // checks off an anonymous index signature, where our checker's
            // object-literal getter modelling (`get x()` rendered as
            // `() => T`) would otherwise produce spurious mismatches.
            if self.check(Colon) {
              let _ = self.advance()
              let _ = self.parse_type()
            } else {
              self.record_index_signature_missing_annotation()
            }
            fields.push((key_type, @ast.TsType::Any))
            let _ = self.match_(Semicolon) || self.match_(Comma)
            continue
          }
        }
        Ident(n) => {
          let _ = self.advance()
          n
        }
        // Keyword-token member names (`{ type: string; … }`,
        // `{ function: T }`, … — these lex as their own tokens). Only
        // when the next token proves this is a member key, so
        // `readonly` / call-signature shapes above keep their meaning.
        k if keyword_member_name(k) is Some(kw) &&
          self.peek_at(1).kind
          is (Colon | Question | Semicolon | Comma | LParen | RBrace) => {
          let _ = self.advance()
          kw
        }
        Str(s) => {
          let _ = self.advance()
          s
        }
        Int(n) => {
          let _ = self.advance()
          n.to_string()
        }
        Number(d) => {
          let _ = self.advance()
          d.to_string()
        }
        // Any other leading token (keyword-named members, etc.) is left
        // to the conservative fallback rather than risking a misparse.
        _ => {
          self.pos = saved_pos
          return None
        }
      }
      // Generic method type parameters `<T>` — recorded nowhere on an
      // anonymous object, so just skip them.
      let _ = self.parse_type_param_names_and_bounds()
      let is_optional = self.match_(Question)
      if self.check(LParen) {
        // Method / call / construct signature.
        let _ = self.advance()
        let method_params = self.parse_params()
        let _ = self.expect(RParen)
        let return_type = if self.check(Colon) {
          let _ = self.advance()
          self.parse_type()
        } else {
          @ast.TsType::Void
        }
        let field_type = callable_func_type_from_params(
          method_params, return_type,
        )
        fields.push(
          (
            Literal(field_name),
            if is_optional {
              wrap_optional_ts_type(field_type)
            } else {
              field_type
            },
          ),
        )
      } else if self.check(Colon) {
        // Ordinary property.
        let _ = self.advance()
        let field_type = self.parse_type()
        fields.push(
          (
            Literal(field_name),
            if is_optional {
              wrap_optional_ts_type(field_type)
            } else {
              field_type
            },
          ),
        )
      } else if self.check(Semicolon) || self.check(Comma) || self.check(RBrace) {
        // Shorthand type member (`{ x; y }`): an annotation-less member
        // means `any` — retaining the NAME keeps missing-member
        // assignability decisions alive (symbolProperty9's `{ x }` vs
        // `{ x; y }`).
        fields.push(
          (
            Literal(field_name),
            if is_optional {
              wrap_optional_ts_type(@ast.TsType::Any)
            } else {
              @ast.TsType::Any
            },
          ),
        )
      } else {
        // Not a member shape we handle; fall back.
        self.pos = saved_pos
        return None
      }
      let had_sep = self.match_(Semicolon) || self.match_(Comma)
      if !had_sep &&
        !self.check(RBrace) &&
        !self.check(Eof) &&
        !self.has_line_terminator_before() {
        missing_separator = true
      }
    }
    let _ = self.expect(RBrace)
    if missing_separator {
      self.interface_member_modifier_misuses.push(
        "<object-member-no-separator>",
      )
    }
    Some(Object(fields))
  } catch {
    _ => {
      self.pos = saved_pos
      None
    }
  }
}

///|
fn Parser::try_parse_simple_type_args(self : Parser) -> Array[@ast.TsType]? {
  if !self.check(Lt) {
    return None
  }
  let saved_pos = self.pos
  let args : Array[@ast.TsType] = []
  try {
    let _ = self.expect(Lt)
    while !self.check(Eof) {
      args.push(self.parse_type())
      if self.match_(Comma) {
        continue
      }
      match self.peek().kind {
        Gt => {
          let _ = self.advance()
          return Some(args)
        }
        GtGt => {
          let tok = self.advance()
          self.pending_gt += 1
          self.pending_gt_pos = tok.pos
          return Some(args)
        }
        GtGtGt => {
          let tok = self.advance()
          self.pending_gt += 2
          self.pending_gt_pos = tok.pos
          return Some(args)
        }
        _ => ()
      }
      self.pos = saved_pos
      self.pending_gt = 0
      return None
    }
    self.pos = saved_pos
    self.pending_gt = 0
    None
  } catch {
    _ => {
      self.pos = saved_pos
      self.pending_gt = 0
      None
    }
  }
}

///|
/// True when the token at `offset` is an identifier or a reserved
/// keyword that's still valid as a labeled-tuple element name. TS
/// permits any `IdentifierName` here, which includes most keywords.
fn Parser::is_tuple_label_token(self : Parser, offset : Int) -> Bool {
  match self.peek_at(offset).kind {
    Ident(_)
    | Type
    | Declare
    | Function
    | Class
    | New
    | Import
    | Export
    | From
    | As
    | In
    | Of
    | Extends
    | Typeof
    | Instanceof
    | Let
    | Const
    | Var
    | If
    | Else
    | Return
    | Throw
    | Try
    | Catch
    | Finally
    | For
    | While
    | Do
    | Switch
    | Case
    | Default
    | Break
    | Continue
    | With
    | Debugger
    | StringType
    | NumberType
    | BooleanType
    | IntType
    | VoidType
    | Interface
    | Null => true
    _ => false
  }
}

///|
fn Parser::is_qualified_type_name_part(self : Parser, offset : Int) -> Bool {
  match self.peek_at(offset).kind {
    Ident(_)
    | Type
    | Function
    | Class
    | New
    | Import
    | Export
    | From
    | As
    | In
    | Of
    | Extends
    | Typeof
    | Instanceof
    | StringType
    | NumberType
    | BooleanType
    | IntType
    | VoidType
    | Null => true
    _ => false
  }
}

///|
fn Parser::parse_named_type_tail(
  self : Parser,
  first_name : String,
) -> @ast.TsType raise ParseError {
  let mut full_name = first_name
  while self.check(Dot) && self.is_qualified_type_name_part(1) {
    let _ = self.advance()
    // A primitive-type KEYWORD can never be a qualified type-name segment
    // (`var v: x.void` — parservoidInQualifiedName2, TS1003/TS2503).
    match self.peek().kind {
      VoidType | StringType | NumberType | BooleanType =>
        self.grammar_misuses.push(
          "a primitive type keyword cannot appear in a qualified type name",
        )
      _ => ()
    }
    let next_name = self.parse_binding_ident()
    full_name = full_name + "." + next_name
  }
  if self.check(Lt) {
    match self.try_parse_simple_type_args() {
      Some(type_args) => Applied(full_name, type_args)
      None => {
        self.skip_type_args()
        Named(full_name)
      }
    }
  } else {
    Named(full_name)
  }
}

///|
fn Parser::local_type_param_bound(self : Parser, name : String) -> @ast.TsType? {
  fn direct(n : String) -> @ast.TsType? {
    let mut idx = self.local_type_param_bounds.length()
    while idx > 0 {
      idx -= 1
      let (param_name, bound) = self.local_type_param_bounds[idx]
      if param_name == n {
        return Some(bound)
      }
    }
    None
  }

  match direct(name) {
    None => None
    Some(bound) => {
      // Follow chains of type-parameter constraints to their ultimate bound:
      // `<T, V extends T, U extends V>` resolves `U` to `T`, not just `V`.
      // This keeps the inlined form transitively faithful so downstream
      // structural checks (e.g. type-parameter assignability) don't treat
      // `U` and `T` as unrelated. A visited set guards malformed cycles
      // (`<A extends B, B extends A>`).
      let mut cur = bound
      let seen : Map[String, Bool] = {}
      seen[name] = true
      while cur is Named(n) && !seen.contains(n) {
        seen[n] = true
        match direct(n) {
          Some(next) => cur = next
          None => break
        }
      }
      Some(cur)
    }
  }
}

///|
/// Parse a single type (not including union/intersection)
fn Parser::parse_primary_type(self : Parser) -> @ast.TsType raise ParseError {
  let tok = self.peek()
  let base_type : @ast.TsType = match tok.kind {
    Lt => {
      let (tp_names, tp_bounds) = self.parse_type_param_names_and_bounds()
      if self.check(LParen) {
        match self.parse_paren_or_function_type() {
          Func(_, _) | Constructor(_, _, _) | CallableMeta(_, _) as func_type =>
            if tp_names.length() > 0 {
              @ast.TsType::GenericFunc(tp_names, tp_bounds, func_type)
            } else {
              func_type
            }
          _ => Any
        }
      } else {
        Any
      }
    }
    NumberType => {
      let _ = self.advance()
      if self.check(Dot) {
        self.parse_named_type_tail("number")
      } else {
        Number
      }
    }
    IntType => {
      let _ = self.advance()
      if self.check(Dot) {
        self.parse_named_type_tail("int")
      } else {
        Int
      }
    }
    BooleanType => {
      let _ = self.advance()
      if self.check(Dot) {
        self.parse_named_type_tail("boolean")
      } else {
        Boolean
      }
    }
    StringType => {
      let _ = self.advance()
      if self.check(Dot) {
        self.parse_named_type_tail("string")
      } else {
        String_
      }
    }
    VoidType => {
      let _ = self.advance()
      if self.check(Dot) {
        // `void` can never head a qualified type name (`var v: void.x` —
        // TS1005, parservoidInQualifiedName1). Parse through for recovery
        // but record the misuse.
        self.grammar_misuses.push(
          "`void` cannot be used in a qualified type name",
        )
        self.parse_named_type_tail("void")
      } else {
        Void
      }
    }
    // Template literal type: `bg${ForegroundColorName}`. A
    // non-interpolating template is the string *literal* type of its text
    // (tsc semantics) — also keeps the `as`-cast reliability split from
    // firing on the ASI `as `Hello world`` mis-parse (asOperatorASI).
    Template(cooked_parts, _, expr_sources) => {
      let _ = self.advance()
      if expr_sources.length() == 0 {
        if cooked_parts.length() >= 1 {
          Literal(cooked_parts[0])
        } else {
          String_
        }
      } else {
        let type_args : Array[@ast.TsType] = []
        for src in expr_sources {
          let sub_parser = Parser::from_source(src)
          let arg_type = sub_parser.parse_type()
          type_args.push(arg_type)
        }
        TemplateLiteralType(cooked_parts, type_args)
      }
    }
    // Literal types: "foo", 1, true, false
    Str(value) => {
      let _ = self.advance()
      Literal(value)
    }
    Int(value) => {
      let _ = self.advance()
      NumberLiteral(value.to_string())
    }
    Number(value) => {
      let _ = self.advance()
      NumberLiteral(value.to_string())
    }
    BigInt(value) => {
      let _ = self.advance()
      BigIntLiteral(value)
    }
    Bool(value) => {
      let _ = self.advance()
      BooleanLiteral(value)
    }
    // null and undefined literal types
    Null => {
      let _ = self.advance()
      Null
    }
    Ident("any") | Ident("unknown") | Ident("object") | Ident("symbol") => {
      let name = match self.advance().kind {
        Ident(n) => n
        _ => "any"
      }
      if self.check(Dot) {
        self.parse_named_type_tail(name)
      } else if name == "unknown" {
        Unknown
      } else if name == "symbol" {
        Symbol
      } else if name == "object" {
        NonPrimitiveObject
      } else {
        Any
      }
    }
    Ident("bigint") => {
      let _ = self.advance()
      BigInt
    }
    Ident("undefined") => {
      let _ = self.advance()
      Undefined
    }
    Ident("null") => {
      let _ = self.advance()
      Null
    }
    Ident("never") => {
      let _ = self.advance()
      Never
    }
    Minus => {
      // Negative number literal: -1
      let _ = self.advance()
      match self.peek().kind {
        Int(value) => {
          let _ = self.advance()
          NumberLiteral("-" + value.to_string())
        }
        Number(value) => {
          let _ = self.advance()
          NumberLiteral("-" + value.to_string())
        }
        BigInt(value) => {
          let _ = self.advance()
          BigIntLiteral("-" + value)
        }
        _ => Any
      }
    }
    // Object type: { key: T; ... }
    LBrace =>
      match self.try_parse_simple_object_type() {
        Some(type_) => type_
        None =>
          // Fuller path: object type literals that carry method / call /
          // construct / index signatures (`{ m(x): T; (x): U }`), which
          // the simple parser can't handle. Falls back to the historical
          // skip-to-`Any` on anything unexpected so behaviour is only
          // ever widened, never regressed.
          match self.try_parse_object_type_with_members() {
            Some(type_) => type_
            None => {
              self.skip_object_type()
              Any
            }
          }
      }
    // Tuple type: [T, U]
    LBracket => self.parse_tuple_type()
    // Parenthesized type or function type: (T) or (x: T) => U
    LParen => self.parse_paren_or_function_type()
    // typeof T
    Typeof => {
      let _ = self.advance()
      let saved_pos = self.pos
      self.parse_typeof_type_query() catch {
        _ => {
          self.pos = saved_pos
          self.skip_typeof_operand()
          Any
        }
      }
    }
    // import("...").Type
    Import => {
      let _ = self.advance()
      if self.check(LParen) {
        let _ = self.advance()
        // TS2307 evidence: an import TYPE names a module the same way an
        // import statement does, so its specifier belongs in the list
        // that check reads. This arm consumed and DISCARDED it, which is
        // why `const x: import("fo") = …` — a typo next to a real
        // `declare module "foo"` — was silent. The ambient-module
        // exemption in the check is what keeps a correctly spelled
        // `import("foo")` quiet.
        match self.peek().kind {
          Str(spec) =>
            if not(self.multi_file_source) {
              self.import_module_specs.push(spec)
            }
          _ => ()
        }
        if self.check(Str("")) {
          let _ = self.advance()
        } else if self.peek().kind is Str(_) {
          let _ = self.advance()
        }
        let _ = self.expect(RParen)
        while self.check(Dot) {
          let _ = self.advance()
          match self.peek().kind {
            Ident(_)
            | NumberType
            | BooleanType
            | StringType
            | VoidType
            | Type
            | New
            | Extends
            | Import
            | Export
            | From
            | As => {
              let _ = self.advance()
            }
            _ => break
          }
        }
        if self.check(Lt) {
          self.skip_type_args()
        }
      }
      Any
    }
    // Constructor type: new (...args: T) => U
    New => {
      let _ = self.advance()
      self.parse_constructor_tail(false)
    }
    // abstract new (...) => T
    Ident("abstract") if self.peek_at(1).kind == New => {
      let _ = self.advance()
      let _ = self.advance()
      self.parse_constructor_tail(true)
    }
    // Special identifier-like keywords
    Ident("infer") => {
      let _ = self.advance()
      let name = if self.is_ident() { self.parse_binding_ident() } else { "_" }
      // May have extends constraint. Capture the bound as a second
      // marker argument so the renderer can fall back to it when the
      // surrounding conditional fails to resolve at the bridge boundary
      // (e.g. `infer DateType extends Date` -> `Date` instead of
      // `JSValue`). When no bound is present the marker keeps the
      // single-argument shape used elsewhere in the checker / parser.
      if self.check(Extends) {
        let _ = self.advance()
        let bound = self.parse_primary_type() catch { _ => @ast.TsType::Any }
        Applied("__tsmbt_infer", [Named(name), bound])
      } else {
        Applied("__tsmbt_infer", [Named(name)])
      }
    }
    Ident("keyof") => {
      let _ = self.advance()
      let operand = self.parse_primary_type() catch { _ => @ast.TsType::Any }
      Keyof(operand)
    }
    Ident("readonly") => {
      let _ = self.advance()
      self.parse_primary_type()
    }
    Ident("unique") => {
      // `unique symbol`: each occurrence gets a per-Parser tag so two
      // references that are reached from the same declaration share an
      // identity and distinct declarations don't.
      let _ = self.advance()
      match self.peek().kind {
        Ident("symbol") => {
          let _ = self.advance()
          self.unique_symbol_index = self.unique_symbol_index + 1
          UniqueSymbol("__tsmbt_us_" + self.unique_symbol_index.to_string())
        }
        _ => Any
      }
    }
    Ident("asserts") => {
      // `asserts x` / `asserts x is T`. Capture both shapes as
      // `AssertsPredicate(name, target?)` so the checker can narrow at
      // call sites; bridge emit treats the function return as `Void`.
      let _ = self.advance()
      let name = if self.is_ident() { self.parse_binding_ident() } else { "_" }
      let target : @ast.TsType? = if self.check(Ident("is")) {
        let _ = self.advance()
        Some(self.parse_type())
      } else {
        None
      }
      AssertsPredicate(name, target)
    }
    Const => {
      let _ = self.advance()
      Any
    }
    Function
    | Class
    | From
    | As
    | In
    | Of
    | Extends
    | Return
    | If
    | Else
    | While
    | Do
    | For
    | Switch
    | Case
    | Default
    | Break
    | Continue
    | Try
    | Catch
    | Finally
    | Throw
    | Let
    | Var
    | Declare
    | Delete
    | Debugger
    | Instanceof => {
      let name = self.parse_binding_ident()
      self.parse_named_type_tail(name)
    }
    Type => {
      let _ = self.advance()
      self.parse_named_type_tail("type")
    }
    // Ident or generic type: Foo, Array<T>
    Ident(name) => {
      let _ = self.advance()
      // TS2552: inside an `async` context `await` is a reserved word, so a
      // type reference spelled `await` (`var v: await`) can never resolve
      // (tsc suggests `Awaited`). Outside async it is a legal type name.
      if name == "await" && self.in_async {
        self.grammar_misuses.push(
          "cannot find name `await`. Did you mean `Awaited`?",
        )
      }
      match self.local_type_param_bound(name) {
        // A `T extends object` bound erases to `Any`, not `NonPrimitiveObject`:
        // the constraint promises "some object type", so treating a value of
        // type `T` as the bare `object` surface would let member-existence
        // checks false-flag properties the instantiation does have
        // (`unboxify<T extends object>(...): T` → `v.a`). Direct `: object`
        // annotations keep the first-class type.
        Some(NonPrimitiveObject) if !self.no_bound_inline => Any
        Some(bound) if !self.no_bound_inline => bound
        _ => self.parse_named_type_tail(name)
      }
    }
    _ => raise ParseError("Expected type, got \{tok.kind}")
  }
  // Handle postfix type operators
  self.parse_postfix_type(base_type)
}

///|
/// Parse postfix type operators: [], extends, etc.
fn Parser::parse_postfix_type(
  self : Parser,
  base_type : @ast.TsType,
) -> @ast.TsType raise ParseError {
  // Array type: T[] or indexed access T[K]
  if self.check(LBracket) && !self.has_line_terminator_before() {
    let _ = self.advance() // [
    if self.check(RBracket) {
      let _ = self.advance() // ]
      return self.parse_postfix_type(Array(base_type))
    }
    // Indexed access type: T[K]. Try to parse the index as a type so later
    // passes can resolve `T["field"]` etc. against concrete interfaces; if
    // parsing fails for any reason, fall back to the original skip-and-Any
    // behaviour so we don't regress more exotic forms.
    let saved_pos = self.pos
    let key_type = self.parse_type() catch {
      _ => {
        self.pos = saved_pos
        let mut bracket_depth = 1
        while bracket_depth > 0 && !self.check(Eof) {
          match self.peek().kind {
            LBracket => {
              bracket_depth += 1
              let _ = self.advance()
            }
            RBracket => {
              bracket_depth -= 1
              let _ = self.advance()
            }
            _ => {
              let _ = self.advance()
            }
          }
        }
        return self.parse_postfix_type(Any)
      }
    }
    if !self.check(RBracket) {
      // Unexpected token after the index type; bail out to the legacy path.
      let mut bracket_depth = 1
      while bracket_depth > 0 && !self.check(Eof) {
        match self.peek().kind {
          LBracket => {
            bracket_depth += 1
            let _ = self.advance()
          }
          RBracket => {
            bracket_depth -= 1
            let _ = self.advance()
          }
          _ => {
            let _ = self.advance()
          }
        }
      }
      return self.parse_postfix_type(Any)
    }
    let _ = self.advance() // ]
    return self.parse_postfix_type(IndexedAccess(base_type, key_type))
  }
  base_type
}

///|
fn Parser::parse_type_operand(self : Parser) -> @ast.TsType raise ParseError {
  let base = self.parse_primary_type()
  if !self.has_line_terminator_before() && self.match_ident("is") {
    let ty = self.parse_type()
    // `paramName is T` — record as `TypePredicate(name, T)` so the checker
    // can narrow callers on `if (isFoo(v))`. When the LHS isn't a simple
    // identifier (rare), fall back to `Boolean`.
    return match base {
      Named(name) => TypePredicate(name, ty)
      _ => Boolean
    }
  }
  base
}

///|
fn Parser::parse_intersection_type(
  self : Parser,
) -> @ast.TsType raise ParseError {
  // A leading `&` is decoration TS allows so a multi-line intersection
  // can put every member on its own line with an aligned operator. It
  // says nothing about the type, so consume it and carry on — handling
  // it in `parse_type` instead meant a second code path that forgot
  // what the first one did next.
  let _ = self.match_(Amp)
  let first = self.parse_type_operand()
  // Fast path: most types are not intersections — avoid allocating the
  // operand `Array` until we actually see a `&`.
  if !self.check(Amp) {
    return first
  }
  let items : Array[@ast.TsType] = [first]
  while self.match_(Amp) {
    items.push(self.parse_type_operand())
  }
  Intersection(items)
}

///|
fn is_definite_primitive_type(type_ : @ast.TsType) -> Bool {
  match type_ {
    Number
    | Int
    | Boolean
    | String_
    | Void
    | BigInt
    | Symbol
    | Null
    | Undefined => true
    _ => false
  }
}

///|
fn type_extends_simple(source : @ast.TsType, target : @ast.TsType) -> Bool? {
  if source == target {
    return Some(true)
  }
  match target {
    Any => return Some(true)
    Union(items) => {
      let mut saw_unknown = false
      for item in items {
        match type_extends_simple(source, item) {
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
        match type_extends_simple(item, target) {
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
  if is_definite_primitive_type(source) && is_definite_primitive_type(target) {
    Some(false)
  } else {
    None
  }
}

///|
fn infer_marker_name(type_ : @ast.TsType) -> String? {
  match type_ {
    Applied("__tsmbt_infer", [Named(name)]) => Some(name)
    Applied("__tsmbt_infer", [Named(name), _]) => Some(name)
    _ => None
  }
}

///|
fn bind_inferred_type(
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
fn match_infer_pattern(
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
    (Array(source_inner), Array(pattern_inner)) =>
      match_infer_pattern(source_inner, pattern_inner, bindings)
    (Array(source_inner), Applied("Array", [pattern_inner])) =>
      match_infer_pattern(source_inner, pattern_inner, bindings)
    (Applied("Array", [source_inner]), Array(pattern_inner)) =>
      match_infer_pattern(source_inner, pattern_inner, bindings)
    (Applied(source_name, source_args), Applied(pattern_name, pattern_args)) =>
      if source_name != pattern_name ||
        source_args.length() != pattern_args.length() {
        false
      } else {
        for i in 0..<source_args.length() {
          if !match_infer_pattern(source_args[i], pattern_args[i], bindings) {
            return false
          }
        }
        true
      }
    (Tuple(source_items), Tuple(pattern_items)) =>
      if source_items.length() != pattern_items.length() {
        false
      } else {
        for i in 0..<source_items.length() {
          if !match_infer_pattern(source_items[i], pattern_items[i], bindings) {
            return false
          }
        }
        true
      }
    (Func(source_params, source_ret), Func(pattern_params, pattern_ret)) =>
      if source_params.length() != pattern_params.length() {
        false
      } else {
        for i in 0..<source_params.length() {
          if !match_infer_pattern(source_params[i], pattern_params[i], bindings) {
            return false
          }
        }
        match_infer_pattern(source_ret, pattern_ret, bindings)
      }
    (_, Union(pattern_items)) => {
      for pattern_item in pattern_items {
        let branch_bindings : Map[String, @ast.TsType] = {}
        if match_infer_pattern(source, pattern_item, branch_bindings) {
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
    _ => false
  }
}

///|
fn substitute_inferred_type(
  type_ : @ast.TsType,
  bindings : Map[String, @ast.TsType],
) -> @ast.TsType {
  match infer_marker_name(type_) {
    Some(name) =>
      match bindings.get(name) {
        Some(type_) => return type_
        None => ()
      }
    None => ()
  }
  match type_ {
    Conditional(source, target, true_type, false_type) =>
      Conditional(
        substitute_inferred_type(source, bindings),
        substitute_inferred_type(target, bindings),
        substitute_inferred_type(true_type, bindings),
        substitute_inferred_type(false_type, bindings),
      )
    Named(name) =>
      match bindings.get(name) {
        Some(type_) => type_
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

///|
fn Parser::parse_conditional_type_tail(
  self : Parser,
  source : @ast.TsType,
) -> @ast.TsType raise ParseError {
  let _ = self.expect(Extends)
  // Per TS grammar, the extends-target is a `Type` that allows
  // unions / intersections but NOT another nested conditional
  // (`A extends B extends C ? … : …` is parse-rejected).
  let target_first = self.parse_intersection_type()
  let target = if self.check(Pipe) {
    let items : Array[@ast.TsType] = [target_first]
    while self.match_(Pipe) {
      items.push(self.parse_intersection_type())
    }
    @ast.TsType::Union(items)
  } else {
    target_first
  }
  let _ = self.expect(Question)
  let true_type = self.parse_type()
  let _ = self.expect(Colon)
  let false_type = self.parse_type()
  let infer_bindings : Map[String, @ast.TsType] = {}
  if match_infer_pattern(source, target, infer_bindings) {
    return substitute_inferred_type(true_type, infer_bindings)
  }
  match type_extends_simple(source, target) {
    Some(true) => true_type
    Some(false) => false_type
    None => Conditional(source, target, true_type, false_type)
  }
}

///|
/// Parse full type including union/intersection
fn Parser::parse_type(self : Parser) -> @ast.TsType raise ParseError {
  // The leading `|` (and the `&` handled one level down) is decoration,
  // not a different grammar: TS allows it so a union can be written one
  // member per line. It used to get its own branch here that built the
  // union and RETURNED — skipping the `extends` tail below, so a
  // conditional type whose check type was written that way lost its
  // condition. remeda's `setPath.ts` is
  //
  //     type Paths<T, Prefix …> =
  //       | Prefix
  //       | (T extends object ? … : …) extends infer Path
  //       ? Readonly<Path>
  //       : never;
  //
  // and mtsc could not parse the file at all, which blocked the whole
  // package. `T | string extends …` parsed fine, which is why it went
  // unnoticed: the bug needed the decoration, not the union.
  let _ = self.match_(Pipe)
  let base = self.parse_intersection_type()
  // Fast path: the common case is a non-union, non-conditional type
  // (`number`, `Foo<T>`, `T[]`, ...). Avoid the union-`Array` allocation
  // and the `saved_pos` snapshot until we see `extends` or `|`.
  if !self.check(Extends) && !self.check(Pipe) {
    return base
  }
  if self.check(Extends) {
    let saved_pos = self.pos
    try {
      return self.parse_conditional_type_tail(base)
    } catch {
      _ => {
        self.pos = saved_pos
        self.skip_conditional_type_tail()
        return Any
      }
    }
  }
  // Union type: T | U
  let items : Array[@ast.TsType] = [base]
  while self.match_(Pipe) {
    items.push(self.parse_intersection_type())
  }
  if self.check(Extends) {
    let saved_pos = self.pos
    try {
      return self.parse_conditional_type_tail(Union(items))
    } catch {
      _ => {
        self.pos = saved_pos
        self.skip_conditional_type_tail()
        return Any
      }
    }
  }
  Union(items)
}

///|
fn Parser::skip_conditional_type_segment(
  self : Parser,
  stop_on_question : Bool,
  stop_on_colon : Bool,
) -> Unit {
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut brace_depth = 0
  let mut angle_depth = 0
  let mut conditional_depth = 0
  while !self.check(Eof) {
    let top_level = paren_depth == 0 &&
      bracket_depth == 0 &&
      brace_depth == 0 &&
      angle_depth == 0
    match self.peek().kind {
      Question if top_level && stop_on_question && conditional_depth == 0 =>
        break
      Question if top_level => {
        conditional_depth += 1
        let _ = self.advance()
      }
      Colon if top_level && stop_on_colon && conditional_depth == 0 => break
      Colon if top_level && conditional_depth > 0 => {
        conditional_depth -= 1
        let _ = self.advance()
      }
      Semicolon | Comma | RParen | RBracket | RBrace if top_level &&
        conditional_depth == 0 => break
      Export | Declare | Interface | Type | Function | Class if top_level &&
        conditional_depth == 0 => break
      LParen => {
        paren_depth += 1
        let _ = self.advance()
      }
      RParen => {
        if paren_depth == 0 {
          break
        }
        paren_depth -= 1
        let _ = self.advance()
      }
      LBracket => {
        bracket_depth += 1
        let _ = self.advance()
      }
      RBracket => {
        if bracket_depth == 0 {
          break
        }
        bracket_depth -= 1
        let _ = self.advance()
      }
      LBrace => {
        brace_depth += 1
        let _ = self.advance()
      }
      RBrace => {
        if brace_depth == 0 {
          break
        }
        brace_depth -= 1
        let _ = self.advance()
      }
      Lt => {
        angle_depth += 1
        let _ = self.advance()
      }
      Gt => {
        if angle_depth > 0 {
          angle_depth -= 1
        }
        let _ = self.advance()
      }
      GtGt => {
        angle_depth = if angle_depth >= 2 { angle_depth - 2 } else { 0 }
        let _ = self.advance()
      }
      GtGtGt => {
        angle_depth = if angle_depth >= 3 { angle_depth - 3 } else { 0 }
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
fn Parser::skip_conditional_type_tail(self : Parser) -> Unit {
  let _ = self.advance() // consume extends
  self.skip_conditional_type_segment(true, false)
  if self.match_(Question) {
    self.skip_conditional_type_segment(false, true)
    let _ = self.match_(Colon)
    self.skip_conditional_type_segment(false, true)
  }
}

///|
/// Skip object type: { key: T; ... }
fn Parser::skip_object_type(self : Parser) -> Unit {
  let _ = self.advance() // consume {
  let mut depth = 1
  while depth > 0 && !self.check(Eof) {
    match self.peek().kind {
      LBrace => {
        depth += 1
        let _ = self.advance()
      }
      RBrace => {
        depth -= 1
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
/// Skip parenthesized type or function type: (T) or (x: T) => U
fn Parser::skip_paren_type(self : Parser) -> Unit raise ParseError {
  let _ = self.advance() // consume (
  let mut depth = 1
  while depth > 0 && !self.check(Eof) {
    match self.peek().kind {
      LParen => {
        depth += 1
        let _ = self.advance()
      }
      RParen => {
        depth -= 1
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
  // Check for arrow function type: => T
  if self.check(Arrow) {
    let _ = self.advance()
    let _ = self.parse_type()
  }
}

///|
/// Skip a type annotation until the top-level arrow of an arrow function.
/// Parse the return type annotation of an arrow function (`(x): T =>`)
/// and return it. Falls back to skipping tokens when the inner parser
/// throws — keeps the legacy resilience but lets the checker see the
/// annotation when it's parseable.
fn Parser::parse_arrow_return_type(self : Parser) -> @ast.TsType {
  let saved = self.pos
  try self.parse_type() catch {
    _ => {
      self.pos = saved
      self.skip_type_until_arrow()
      @ast.TsType::Any
    }
  } noraise {
    t => t
  }
}

///|
fn Parser::skip_type_until_arrow(self : Parser) -> Unit {
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut brace_depth = 0
  let mut angle_depth = 0
  while !self.check(Eof) {
    match self.peek().kind {
      Arrow if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => break
      LParen => {
        paren_depth += 1
        let _ = self.advance()
      }
      RParen => {
        if paren_depth == 0 {
          break
        }
        paren_depth -= 1
        let _ = self.advance()
      }
      LBracket => {
        bracket_depth += 1
        let _ = self.advance()
      }
      RBracket => {
        if bracket_depth == 0 {
          break
        }
        bracket_depth -= 1
        let _ = self.advance()
      }
      LBrace => {
        brace_depth += 1
        let _ = self.advance()
      }
      RBrace => {
        if brace_depth == 0 {
          break
        }
        brace_depth -= 1
        let _ = self.advance()
      }
      Lt => {
        angle_depth += 1
        let _ = self.advance()
      }
      Gt => {
        if angle_depth > 0 {
          angle_depth -= 1
        }
        let _ = self.advance()
      }
      GtGt => {
        angle_depth = if angle_depth >= 2 { angle_depth - 2 } else { 0 }
        let _ = self.advance()
      }
      GtGtGt => {
        angle_depth = if angle_depth >= 3 { angle_depth - 3 } else { 0 }
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
fn Parser::parse_typeof_type_query(
  self : Parser,
) -> @ast.TsType raise ParseError {
  if self.check(Import) {
    let _ = self.advance()
    let _ = self.expect(LParen)
    let module_spec = match self.advance().kind {
      Str(s) => s
      other => raise ParseError("Expected typeof import string, got \{other}")
    }
    let _ = self.expect(RParen)
    let mut query = "import(\"" + module_spec + "\")"
    while self.match_(Dot) {
      query += "." + self.parse_typeof_query_segment()
    }
    if self.check(Lt) {
      self.skip_type_args()
    }
    return @ast.TsType::TypeOf(query)
  }
  let first = self.parse_typeof_query_segment()
  let mut query = first
  while self.match_(Dot) {
    // Tolerate a trailing dot (`var v: typeof A.` -- parser error-recovery
    // fixtures): keep the query so the base name still resolves and an
    // undeclared `A` reports TS2304 instead of the whole annotation
    // collapsing to `Any`.
    let seg : String? = try self.parse_typeof_query_segment() catch {
      _ => None
    } noraise {
      s => Some(s)
    }
    match seg {
      Some(sg) => query += "." + sg
      None => break
    }
  }
  if self.check(Lt) {
    self.skip_type_args()
  }
  @ast.TsType::TypeOf(query)
}

///|
fn Parser::parse_typeof_query_segment(self : Parser) -> String raise ParseError {
  self.parse_binding_ident()
}

///|
/// Skip typeof operand
fn Parser::skip_typeof_operand(self : Parser) -> Unit raise ParseError {
  if self.check(Import) {
    let _ = self.advance()
    if self.check(LParen) {
      self.skip_paren_type()
    }
    while self.check(Dot) {
      let _ = self.advance()
      match self.peek().kind {
        Ident(_)
        | NumberType
        | BooleanType
        | StringType
        | VoidType
        | Type
        | New
        | Extends
        | Import
        | Export
        | From
        | As => {
          let _ = self.advance()
        }
        _ => break
      }
    }
    if self.check(Lt) {
      self.skip_type_args()
    }
    return
  }
  // Skip qualified name: x.y.z
  while self.is_ident() {
    let _ = self.advance()
    if self.check(Dot) {
      let _ = self.advance()
    } else {
      break
    }
  }
  // Skip generic args if present
  if self.check(Lt) {
    self.skip_type_args()
  }
}

///|
/// Skip type arguments: <T, U>
fn Parser::skip_type_args(self : Parser) -> Unit {
  let _ = self.try_skip_type_args()
}

///|
/// Same as `skip_type_args` but returns `true` only when a balanced
/// closing `>` was reached. Callers that are speculatively trying to
/// parse `S<...>` as a generic-instantiation expression (rather than
/// a `<` comparison) MUST check the return value — otherwise input
/// like `S<N;` happily scans to EOF, the caller treats it as a
/// successful skip, and the rest of the source disappears into the
/// "type arguments". This used to misparse
/// `for (let S = 0, N = …; S < N; ++S)` because the for-cond saw
/// `S<N;` as `S<N>` (instantiation) and dropped `<N` entirely.
fn Parser::try_skip_type_args(self : Parser) -> Bool {
  if !self.check(Lt) {
    return false
  }
  let _ = self.advance() // consume <
  let mut depth = 1
  // Bracket nesting INSIDE the candidate type-argument list. A type can
  // contain braces, parens and brackets (`f<{ a: number; b: T }>()`,
  // `f<(x: A) => B>()`, `f<[A, B]>()`), so those tokens are legal — but
  // only balanced. An unbalanced closer, or a `;` outside a `{…}`, means
  // the `<` was a comparison and the scan has already left the
  // expression it started in.
  //
  // "Balanced" has two halves and this scan only checked one of them.
  // The closer guards below catch a `}`/`)`/`]` this scan never
  // opened; the counts also have to be zero at the point `depth`
  // reaches 0, or the `>` that closed the candidate list was itself
  // nested inside a bracket the scan opened and never closed — the
  // same "the scan has left its expression" error, in the other
  // direction. `a < (b > (c))` is the minimal case: the scan consumes
  // `< ( b >`, stops at depth 0 with `parens == 1`, and the caller
  // sees the following `(` and commits to `a<(b>(c)` as a generic
  // call, leaving a stray `)` behind ("Expected Semicolon, got
  // RParen"; wrapped in parens it reads "Expected RParen, got
  // RParen"). Found by the mangle fuzzer, which produced
  // `(structuredClone(obj) < ({ ...bag } > (obj.q -= false)))`.
  let mut braces = 0
  let mut parens = 0
  let mut brackets = 0
  while depth > 0 && !self.check(Eof) {
    match self.peek().kind {
      Lt => {
        depth += 1
        let _ = self.advance()
      }
      Gt => {
        depth -= 1
        let _ = self.advance()
      }
      GtGt => {
        depth -= 2
        let _ = self.advance()
      }
      GtGtGt => {
        depth -= 3
        let _ = self.advance()
      }
      LBrace => {
        braces += 1
        let _ = self.advance()
      }
      RBrace =>
        // Closing a brace this scan never opened: the `}` belongs to the
        // block the expression lives in. `{ a < b; } c > (1);` used to
        // balance `<`…`>` straight across it, commit on the following
        // `(`, and swallow the rest of the file — which is how a single
        // relational operator anywhere in a large real-world source
        // could delete everything after it.
        if braces == 0 {
          return false
        } else {
          braces -= 1
          let _ = self.advance()
        }
      LParen => {
        parens += 1
        let _ = self.advance()
      }
      RParen =>
        if parens == 0 {
          return false
        } else {
          parens -= 1
          let _ = self.advance()
        }
      LBracket => {
        brackets += 1
        let _ = self.advance()
      }
      RBracket =>
        if brackets == 0 {
          return false
        } else {
          brackets -= 1
          let _ = self.advance()
        }
      // `;` separates members of an object type, so it is only legal
      // inside braces. Outside them it ends a statement.
      Semicolon =>
        if braces == 0 {
          return false
        } else {
          let _ = self.advance()
        }
      // Tokens that can start a statement but can never appear in a
      // type. Reaching one means the scan has run past the end of the
      // expression, whatever the bracket counts say.
      Return
      | If
      | Else
      | Switch
      | Case
      | While
      | Do
      | For
      | Break
      | Continue
      | Try
      | Catch
      | Finally
      | Throw
      | Var
      | Let
      | Debugger => return false
      _ => {
        let _ = self.advance()
      }
    }
  }
  depth <= 0 && braces == 0 && parens == 0 && brackets == 0
}

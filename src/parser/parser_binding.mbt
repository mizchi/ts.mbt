///|
/// The words ES reserves only in STRICT mode, minus the two this parser
/// already spells as their own token kinds (`let` and `yield`, handled in
/// their own arms below) and minus `eval` / `arguments`, which are not
/// reserved words at all — they are ordinary identifiers strict mode
/// forbids as a binding target, and the caller tests them separately.
///
/// TS1213 ("identifier expected — `X` is a reserved word in strict mode").
/// The rule was already here for `let` and `yield`, at two of the nine
/// spellings the language has, which is why `class C { constructor(static)
/// {} }` parsed clean: a class body is automatically strict
/// (`parser_class.mbt` sets `in_strict`), and `static` arrives through the
/// plain `Ident(_)` arm next to `eval` / `arguments`.
fn is_strict_reserved_word(name : String) -> Bool {
  name == "implements" ||
  name == "interface" ||
  name == "package" ||
  name == "private" ||
  name == "protected" ||
  name == "public" ||
  name == "static"
}

///|
// /
fn Parser::parse_binding_ident(self : Parser) -> String raise ParseError {
  match self.peek().kind {
    Ident(_) =>
      match self.advance().kind {
        Ident(n) => {
          // In strict mode, `eval` and `arguments` cannot be used as binding
          // identifiers (TS1100 family). Recorded -- not raised -- so the
          // file still parses and the checker reports the diagnostic.
          if (self.in_strict || self.directive_strict) &&
            (n == "eval" || n == "arguments" || is_strict_reserved_word(n)) {
            self.strict_mode_misuses.push(n)
          }
          n
        }
        _ => "<param>"
      }
    Yield => {
      let _ = self.advance()
      // TS1212: `yield` cannot be used as a binding identifier in strict
      // mode (class bodies, "use strict" prologues, @alwaysStrict runs).
      // The ES2015+-target reservation lives in `parse_binding_pattern`:
      // this parser is also used by lenient name positions (enum members,
      // import specifiers) where keywords stay legal.
      if self.in_strict || self.directive_strict {
        self.strict_mode_misuses.push("yield")
      }
      "yield"
    }
    NumberType => {
      let _ = self.advance()
      "number"
    }
    BooleanType => {
      let _ = self.advance()
      "boolean"
    }
    StringType => {
      let _ = self.advance()
      "string"
    }
    VoidType => {
      let _ = self.advance()
      "void"
    }
    IntType => {
      let _ = self.advance()
      "int"
    }
    Type => {
      let _ = self.advance()
      "type"
    }
    Function => {
      let _ = self.advance()
      "function"
    }
    Class => {
      let _ = self.advance()
      "class"
    }
    Interface => {
      let _ = self.advance()
      "interface"
    }
    New => {
      let _ = self.advance()
      "new"
    }
    Let => {
      let _ = self.advance()
      // TS1212: same strict-mode reservation as `yield` above (the
      // ES2015+-target rule lives in `parse_binding_pattern`).
      if self.in_strict || self.directive_strict {
        self.strict_mode_misuses.push("let")
      }
      "let"
    }
    Var => {
      let _ = self.advance()
      "var"
    }
    Const => {
      let _ = self.advance()
      "const"
    }
    Switch => {
      let _ = self.advance()
      "switch"
    }
    Case => {
      let _ = self.advance()
      "case"
    }
    If => {
      let _ = self.advance()
      "if"
    }
    Else => {
      let _ = self.advance()
      "else"
    }
    While => {
      let _ = self.advance()
      "while"
    }
    Do => {
      let _ = self.advance()
      "do"
    }
    For => {
      let _ = self.advance()
      "for"
    }
    Return => {
      let _ = self.advance()
      "return"
    }
    Break => {
      let _ = self.advance()
      "break"
    }
    Continue => {
      let _ = self.advance()
      "continue"
    }
    Default => {
      let _ = self.advance()
      "default"
    }
    With => {
      let _ = self.advance()
      "with"
    }
    Debugger => {
      let _ = self.advance()
      "debugger"
    }
    Try => {
      let _ = self.advance()
      "try"
    }
    Catch => {
      let _ = self.advance()
      "catch"
    }
    Finally => {
      let _ = self.advance()
      "finally"
    }
    Throw => {
      let _ = self.advance()
      "throw"
    }
    Import => {
      let _ = self.advance()
      "import"
    }
    Export => {
      let _ = self.advance()
      "export"
    }
    Declare => {
      let _ = self.advance()
      "declare"
    }
    From => {
      let _ = self.advance()
      "from"
    }
    Delete => {
      let _ = self.advance()
      "delete"
    }
    As => {
      let _ = self.advance()
      "as"
    }
    Of => {
      let _ = self.advance()
      "of"
    }
    In => {
      let _ = self.advance()
      "in"
    }
    Extends => {
      let _ = self.advance()
      "extends"
    }
    Typeof => {
      let _ = self.advance()
      "typeof"
    }
    Instanceof => {
      let _ = self.advance()
      "instanceof"
    }
    Null => {
      let _ = self.advance()
      "null"
    }
    Bool(true) => {
      let _ = self.advance()
      "true"
    }
    Bool(false) => {
      let _ = self.advance()
      "false"
    }
    k => raise ParseError("Expected identifier, got \{k}")
  }
}

///|
fn Parser::binding_first_name(
  self : Parser,
  binding : @ast.TsBinding,
) -> String {
  match binding {
    @ast.TsBinding::Ident(n) => n
    @ast.TsBinding::Array(arr) => {
      for item in arr.items {
        match item {
          Some(elem) => {
            let name = self.binding_first_name(elem.binding)
            if name != "<destruct>" {
              return name
            }
          }
          None => ()
        }
      }
      match arr.rest {
        Some(rest) => self.binding_first_name(rest)
        None => "<destruct>"
      }
    }
    @ast.TsBinding::Object(obj) => {
      for prop in obj.props {
        let name = self.binding_first_name(prop.binding)
        if name != "<destruct>" {
          return name
        }
      }
      match obj.rest {
        Some(name) => name
        None => "<destruct>"
      }
    }
    @ast.TsBinding::Target(_) => "<destruct>"
  }
}

///|
/// TS2451 ("Cannot redeclare block-scoped variable 'X'") for two elements
/// of ONE destructuring pattern that bind the same name —
/// `let { foo, foo }`, `const { a, b: a }`, `let [v, v]`.
///
/// `is_block_scoped` is required and has no default: `var [a, a] = …`
/// legally merges, so the caller has to say which keyword it parsed. Batch
/// CA's top-level rule made the same distinction for flat declarations and
/// deliberately let patterns fall through; this is that omission, closed at
/// the one place a pattern's whole name set is known.
///
/// `destructuringSameNames.ts` is the legal-neighbour list, written into
/// the corpus:
///   - `let { foo, foo: bar }` binds `foo` and `bar` — DISTINCT, legal;
///   - every ASSIGNMENT-pattern repeat (`({ foo, foo } = …)`,
///     `[foo, foo] = …`) is legal, because an assignment target is not a
///     declaration. Those parse as expressions and never reach a binding
///     parser, so they are excluded structurally rather than by a test.
///
/// `collect_binding_names` already flattens nested patterns and rest
/// elements, so `let { a: { x }, b: { x } }` — two different properties
/// binding one name — is caught without a second walk.
fn Parser::record_pattern_duplicate_bindings(
  self : Parser,
  binding : @ast.TsBinding,
  is_block_scoped : Bool,
) -> Unit {
  if not(is_block_scoped) {
    return
  }
  match binding {
    @ast.TsBinding::Array(_) | @ast.TsBinding::Object(_) => ()
    // A plain `let x` binds one name; repeats across STATEMENTS are batch
    // CA's rule, not this one.
    _ => return
  }
  let names : Array[String] = []
  self.collect_binding_names(binding, names)
  let seen : Map[String, Unit] = {}
  let reported : Map[String, Unit] = {}
  for n in names {
    if seen.contains(n) && not(reported.contains(n)) {
      reported[n] = ()
      self.grammar_misuses.push("cannot redeclare block-scoped variable `\{n}`")
    }
    seen[n] = ()
  }
}

///|
/// Two rules about a `for…of` / `for…in` HEAD binding, both keyed on the
/// loop variable's own name and needing no type inference:
///
///   - TS7022 ("'X' implicitly has type 'any' because it does not have a
///     type annotation and is referenced directly or indirectly in its own
///     initializer"): `for (var v of v)`, `let v = [1]; for (let v of v)`.
///     Only the DIRECT form is claimed — the head binds `v` and the
///     iterable expression mentions `v`, so the type of `v` is inferred
///     from `v`. The INDIRECT cases in the corpus (`for-of33` / `-34` /
///     `-35`, where a class's un-annotated `next()` returns the loop
///     variable) need an inference-cycle detector and abstain here.
///     Requires no annotation on the head: `for (var v: any of v)` is
///     legal, which is what `var_type` is read for.
///
///   - TS2481 ("Cannot initialize outer scoped variable 'X' in the same
///     scope as block scoped declaration 'X'"): `for (let v of []) { var v }`.
///     A `var` in the body hoists to the enclosing function while the head's
///     `let` owns the loop scope, so the two collide. Only a `let`/`const`
///     head qualifies, and only the body's own flat `var` statements are
///     read — a nested block or function is a different scope and falls
///     through, losing a finding rather than inventing one.
fn Parser::record_for_head_binding_misuses(
  self : Parser,
  kind : @ast.TsForOfKind,
  binding : @ast.TsBinding,
  var_type : @ast.TsType,
  iterable : @ast.TsExpr,
  body : @ast.TsBlock,
) -> Unit {
  let names : Array[String] = []
  self.collect_binding_names(binding, names)
  if names.length() == 0 {
    return
  }
  // TS7022: the head's own name read in the iterable, with no annotation
  // to break the cycle.
  //
  // `no_implicit_any` is REQUIRED here, and leaving it out was a false
  // positive on four TS7-ACCEPTED files: `for (var of of of) { }` and
  // `for (var of in of) { }` (parserForOfStatement18/19 and their ES5
  // twins) bind a variable named `of` and iterate a variable named `of`,
  // which is a genuine self-reference — but those files set
  // `@strict: false`, so tsc reports nothing. Every other
  // `<noimplicitany>` recorder in the parser gates on this flag; omitting
  // it here made this the twentieth instance in the repo of a rule applied
  // at some of its sites, and the first one written by the same pass that
  // was cataloguing them.
  if self.no_implicit_any && var_type is Any {
    let mentioned : Array[String] = []
    collect_iterable_var_names(iterable, mentioned)
    for n in names {
      if mentioned.contains(n) {
        self.grammar_misuses.push(
          "<noimplicitany>`\{n}` implicitly has type `any` because it does not have a type annotation and is referenced in its own initializer",
        )
        break
      }
    }
  }
  // TS2481: a body-level `var` of the head's name.
  if kind is (@ast.TsForOfKind::Let | @ast.TsForOfKind::Const) {
    for st in body.stmts {
      match st {
        @ast.TsStmt::Var(@ast.TsBinding::Ident(vn), _, _) =>
          if names.contains(vn) {
            self.grammar_misuses.push(
              "cannot initialize outer scoped variable `\{vn}` in the same scope as block scoped declaration `\{vn}`",
            )
            break
          }
        _ => ()
      }
    }
  }
}

///|
/// Bare `Var` names read by a `for…of` / `for…in` iterable expression, for
/// the TS7022 self-reference test above. Deliberately shallow: only the
/// spellings in which the loop variable's own name can be the thing being
/// iterated. A name reached through a call or a property is not the
/// iterable itself, so widening this would claim a cycle that is not one.
fn collect_iterable_var_names(e : @ast.TsExpr, out : Array[String]) -> Unit {
  match e {
    Var(n) => out.push(n)
    As(inner, _) | Satisfies(inner, _) | NonNull(inner) | PureCall(inner) =>
      collect_iterable_var_names(inner, out)
    _ => ()
  }
}

///|
/// Collect all bound names from a binding pattern
fn Parser::collect_binding_names(
  self : Parser,
  binding : @ast.TsBinding,
  names : Array[String],
) -> Unit {
  match binding {
    @ast.TsBinding::Ident(n) => names.push(n)
    @ast.TsBinding::Array(arr) => {
      for item in arr.items {
        match item {
          Some(elem) => self.collect_binding_names(elem.binding, names)
          None => ()
        }
      }
      match arr.rest {
        Some(rest) => self.collect_binding_names(rest, names)
        None => ()
      }
    }
    @ast.TsBinding::Object(obj) => {
      for prop in obj.props {
        self.collect_binding_names(prop.binding, names)
      }
      match obj.rest {
        Some(name) => names.push(name)
        None => ()
      }
    }
    @ast.TsBinding::Target(_) => ()
  }
}

///|
fn Parser::parse_binding_element(
  self : Parser,
) -> @ast.TsBindingElem raise ParseError {
  let binding = self.parse_binding_pattern()
  let default : @ast.TsExpr? = if self.match_(Eq) {
    Some(self.parse_assignment())
  } else {
    None
  }
  { binding, default }
}

///|
fn Parser::parse_binding_array(
  self : Parser,
) -> @ast.TsBinding raise ParseError {
  let _ = self.expect(LBracket)
  let items : Array[@ast.TsBindingElem?] = []
  let mut rest : @ast.TsBinding? = None
  while !self.check(RBracket) {
    if self.match_(Ellipsis) {
      let rest_binding = self.parse_binding_pattern()
      rest = Some(rest_binding)
      // TS1186, binding-declaration spelling: `var [...z = a] = a`. The
      // initializer is consumed so the rest of the pattern still parses —
      // this arm never handled `Eq`, so leaving it would turn a recorded
      // diagnostic into a parse failure on the closing bracket. The
      // destructuring-ASSIGNMENT spelling (`[...x = a] = a`) is the second
      // site and never reaches any pattern parser; see
      // `record_rest_element_initializer`.
      if self.check(Eq) {
        let _ = self.advance()
        let _ = self.parse_assignment()
        self.grammar_misuses.push("a rest element cannot have an initializer")
      }
      if self.match_(Comma) {
        // TS1013: a rest element may not be followed by a trailing comma.
        // No legal spelling produces it — `const [e,] = xs` (a trailing
        // comma after a NON-rest element) is fine and does not reach this
        // arm, which is the neighbour that had to be probed. Unlike the
        // parameter-list form (`declare function f(...a,)`, which tsc
        // ACCEPTS in an ambient declaration), the binding-pattern form has
        // no ambient exemption.
        self.record_suppressible_grammar_misuse(
          "a rest element may not have a trailing comma",
        )
      }
      break
    }
    if self.match_(Comma) {
      items.push(None)
      continue
    }
    items.push(Some(self.parse_binding_element()))
    if self.match_(Comma) {
      if self.check(RBracket) {
        break
      }
      continue
    } else {
      break
    }
  }
  let _ = self.expect(RBracket)
  @ast.TsBinding::Array({ items, rest })
}

///|
fn Parser::parse_object_binding_key(self : Parser) -> String raise ParseError {
  match self.advance().kind {
    Ident(n) => n
    Yield => "yield"
    Str(s) => s
    Number(n) => "\{n}"
    Int(n) => "\{n}"
    Return => "return"
    If => "if"
    Else => "else"
    For => "for"
    While => "while"
    Break => "break"
    Continue => "continue"
    Function => "function"
    Let => "let"
    Const => "const"
    Var => "var"
    New => "new"
    Typeof => "typeof"
    Of => "of"
    In => "in"
    Do => "do"
    Try => "try"
    Switch => "switch"
    Case => "case"
    Default => "default"
    With => "with"
    Debugger => "debugger"
    Import => "import"
    Export => "export"
    From => "from"
    As => "as"
    Catch => "catch"
    Finally => "finally"
    Throw => "throw"
    Delete => "delete"
    Declare => "declare"
    Interface => "interface"
    Class => "class"
    Instanceof => "instanceof"
    NumberType => "number"
    BooleanType => "boolean"
    StringType => "string"
    VoidType => "void"
    IntType => "int"
    Type => "type"
    Extends => "extends"
    Null => "null"
    // Boolean literals are valid as object-destructure keys
    // (e.g. `const { true: a, false: b } = ...`).
    Bool(true) => "true"
    Bool(false) => "false"
    k => raise ParseError("Expected object binding key, got \{k}")
  }
}

///|
fn Parser::parse_binding_object(
  self : Parser,
) -> @ast.TsBinding raise ParseError {
  let _ = self.expect(LBrace)
  let props : Array[@ast.TsObjectBindingProp] = []
  let mut rest : String? = None
  if !self.check(RBrace) {
    while true {
      if self.match_(Ellipsis) {
        let name = self.parse_binding_ident()
        rest = Some(name)
        if self.match_(Comma) {
          // TS1013, object form (`const {...b,} = o`). See the array arm.
          self.record_suppressible_grammar_misuse(
            "a rest element may not have a trailing comma",
          )
        }
        break
      }
      // A literal key token (string / number / boolean / null) can never be
      // a SHORTHAND binding — it needs the `: alias` form. Captured before
      // the key parse erases the token kind
      // (objectBindingPatternKeywordIdentifiers01/03).
      let key_is_literal_token = match self.peek().kind {
        Str(_) | Number(_) | Int(_) | Bool(_) | Null => true
        _ => false
      }
      let (key, key_expr) = if self.match_(LBracket) {
        let expr = self.parse_assignment()
        let _ = self.expect(RBracket)
        ("<computed>", Some(expr))
      } else {
        (self.parse_object_binding_key(), None)
      }
      if self.match_(Colon) {
        let elem = self.parse_binding_element()
        props.push({
          key,
          key_expr,
          binding: elem.binding,
          default: elem.default,
        })
      } else {
        match key_expr {
          Some(_) => raise ParseError("Expected Colon, got \{self.peek().kind}")
          None => {
            // Shorthand: the key IS the binding name. A hard-reserved word
            // (`var { while } = …`) or a literal key (`var { "while" } = …`)
            // is only legal with a `: alias` (TS1005).
            if key_is_literal_token {
              self.grammar_misuses.push(
                "a literal object-binding key needs a `:` alias",
              )
            } else {
              self.record_reserved_binding_name(key)
            }
            let mut default : @ast.TsExpr? = None
            if self.match_(Eq) {
              default = Some(self.parse_assignment())
            }
            props.push({
              key,
              key_expr: None,
              binding: @ast.TsBinding::Ident(key),
              default,
            })
          }
        }
      }
      if self.check(RBrace) {
        break
      }
      let _ = self.expect(Comma)
      if self.check(RBrace) {
        break
      }
    }
  }
  let _ = self.expect(RBrace)
  @ast.TsBinding::Object({ props, rest })
}

///|
fn Parser::parse_binding_pattern(
  self : Parser,
) -> @ast.TsBinding raise ParseError {
  match self.peek().kind {
    LBracket => self.parse_binding_array()
    LBrace => self.parse_binding_object()
    _ => {
      let name = self.parse_binding_ident()
      // Every caller of this parser is a genuine binding position
      // (var/let/const declarations, destructuring elements and rename
      // values, parameters, for-of bindings) -- a hard-reserved word is
      // never legal here (TS1359, `var { while: while } = …`).
      self.record_reserved_binding_name(name)
      // TS1212 at ES2015+ targets: the strict-reserved words are rejected
      // as *binding* names (`var interface`, `var let`,
      // `function f(yield = …)`) while staying legal in lenient name
      // positions (enum members, property names, import specifiers) --
      // which is why this lives here and not in `parse_binding_ident`.
      if self.target_es6_plus &&
        (name == "interface" || name == "let" || name == "yield") {
        self.strict_mode_misuses.push(name)
      }
      @ast.TsBinding::Ident(name)
    }
  }
}

///|
fn Parser::parse_assignment_target_expr(
  self : Parser,
) -> @ast.TsExpr raise ParseError {
  let expr = self.parse_ternary()
  match expr {
    Var(_) | PropAccess(_, _) | IndexAccess(_, _) => expr
    _ => raise ParseError("Invalid assignment target")
  }
}

///|
fn Parser::parse_assignment_binding_element(
  self : Parser,
) -> @ast.TsBindingElem raise ParseError {
  let binding = self.parse_assignment_binding_pattern()
  let default : @ast.TsExpr? = if self.match_(Eq) {
    Some(self.parse_assignment())
  } else {
    None
  }
  { binding, default }
}

///|
fn Parser::parse_assignment_binding_array(
  self : Parser,
) -> @ast.TsBinding raise ParseError {
  let _ = self.expect(LBracket)
  let items : Array[@ast.TsBindingElem?] = []
  let mut rest : @ast.TsBinding? = None
  while !self.check(RBracket) {
    if self.match_(Ellipsis) {
      let rest_binding = self.parse_assignment_binding_pattern()
      rest = Some(rest_binding)
      // TS1186 is not recorded here, and the reason is the one this
      // comment has always given: `[...x = a] = a` never reaches this
      // parser. `parse_assignment_binding_pattern` tries
      // `parse_assignment_target_expr` first, and for that source it
      // SUCCEEDS — the whole bracketed form parses as an expression — so
      // the array-pattern path is skipped. That is now handled where the
      // shape actually lands, in `record_rest_element_initializer`, called
      // from the object/array-literal arm of `parse_assignment`. The
      // binding-DECLARATION spelling (`var [...z = a] = a`) is the other
      // site and is checked in `parse_binding_array`.
      if self.match_(Comma) {
        // trailing comma after rest
      }
      break
    }
    if self.match_(Comma) {
      items.push(None)
      continue
    }
    items.push(Some(self.parse_assignment_binding_element()))
    if self.match_(Comma) {
      if self.check(RBracket) {
        break
      }
      continue
    } else {
      break
    }
  }
  let _ = self.expect(RBracket)
  @ast.TsBinding::Array({ items, rest })
}

///|
fn Parser::parse_assignment_binding_object(
  self : Parser,
) -> @ast.TsBinding raise ParseError {
  let _ = self.expect(LBrace)
  let props : Array[@ast.TsObjectBindingProp] = []
  let mut rest : String? = None
  if !self.check(RBrace) {
    while true {
      if self.match_(Ellipsis) {
        let name = self.parse_binding_ident()
        rest = Some(name)
        if self.match_(Comma) {
          // trailing comma
        }
        break
      }
      let (key, key_expr) = if self.match_(LBracket) {
        let expr = self.parse_assignment()
        let _ = self.expect(RBracket)
        ("<computed>", Some(expr))
      } else {
        (self.parse_object_binding_key(), None)
      }
      if self.match_(Colon) {
        let elem = self.parse_assignment_binding_element()
        props.push({
          key,
          key_expr,
          binding: elem.binding,
          default: elem.default,
        })
      } else {
        match key_expr {
          Some(_) => raise ParseError("Expected Colon, got \{self.peek().kind}")
          None => {
            let mut default : @ast.TsExpr? = None
            if self.match_(Eq) {
              default = Some(self.parse_assignment())
            }
            props.push({
              key,
              key_expr: None,
              binding: @ast.TsBinding::Ident(key),
              default,
            })
          }
        }
      }
      if self.check(RBrace) {
        break
      }
      let _ = self.expect(Comma)
      if self.check(RBrace) {
        break
      }
    }
  }
  let _ = self.expect(RBrace)
  @ast.TsBinding::Object({ props, rest })
}

///|
fn Parser::parse_assignment_binding_pattern(
  self : Parser,
) -> @ast.TsBinding raise ParseError {
  let saved_pos = self.pos
  let saved_gen = self.in_generator
  let target = Some(self.parse_assignment_target_expr()) catch { _ => None }
  match target {
    Some(expr) =>
      match expr {
        Var(name) => @ast.TsBinding::Ident(name)
        _ => @ast.TsBinding::Target(expr)
      }
    None => {
      self.pos = saved_pos
      self.in_generator = saved_gen
      match self.peek().kind {
        LBracket => self.parse_assignment_binding_array()
        LBrace => self.parse_assignment_binding_object()
        _ => {
          let name = self.parse_binding_ident()
          // TS1359: this slot is a genuine binding target (destructuring
          // element / rename value, `var { while: while } = …`), where a
          // hard-reserved word is never a legal name. `parse_binding_ident`
          // itself stays lenient because import/export specifiers and
          // property-name callers legitimately accept keywords.
          self.record_reserved_binding_name(name)
          @ast.TsBinding::Ident(name)
        }
      }
    }
  }
}

///|
/// Record a TS1359 ("Identifier expected. 'X' is a reserved word that
/// cannot be used here") when `name` is a hard-reserved word -- one that is
/// never a legal binding name in any mode. Contextual keywords (`of`,
/// `from`, `as`, `type`, `yield`, `let`, `await`, …) are excluded; their
/// mode-dependent rules live at their own parse sites.
fn Parser::record_reserved_binding_name(self : Parser, name : String) -> Unit {
  match name {
    "void"
    | "function"
    | "class"
    | "var"
    | "const"
    | "new"
    | "switch"
    | "case"
    | "if"
    | "else"
    | "while"
    | "do"
    | "for"
    | "return"
    | "break"
    | "continue"
    | "default"
    | "with"
    | "try"
    | "catch"
    | "finally"
    | "throw"
    | "delete"
    | "typeof"
    | "instanceof"
    | "in"
    // NOT `this`: a `this` first parameter (`function f(this: Foo)`) is a
    // legal this-type annotation and routes through the same binding parse.
    | "true"
    | "false"
    | "null"
    | "enum"
    | "import"
    | "export"
    | "extends"
    | "super"
    | "debugger" =>
      self.grammar_misuses.push(
        "`\{name}` is a reserved word and cannot be used as a binding name",
      )
    _ => ()
  }
}

///|
// / ...
fn Parser::match_ellipsis(self : Parser) -> Bool {
  self.match_(Ellipsis)
}

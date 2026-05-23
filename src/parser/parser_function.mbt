// ============================================
// function
// ============================================

///|
fn Parser::skip_param_decorators(self : Parser) -> Unit raise ParseError {
  while self.match_(At) {
    let _ = self.parse_binding_ident()
    while self.match_(Dot) {
      let _ = self.parse_binding_ident()
    }
    if self.check(Lt) {
      self.skip_type_args()
    }
    if self.check(LParen) {
      let _ = self.advance()
      let mut paren_depth = 1
      let mut brace_depth = 0
      let mut bracket_depth = 0
      while paren_depth > 0 && !self.check(Eof) {
        match self.peek().kind {
          LParen => {
            paren_depth += 1
            let _ = self.advance()
          }
          RParen => {
            paren_depth -= 1
            let _ = self.advance()
          }
          LBrace => {
            brace_depth += 1
            let _ = self.advance()
          }
          RBrace => {
            if brace_depth > 0 {
              brace_depth -= 1
            }
            let _ = self.advance()
          }
          LBracket => {
            bracket_depth += 1
            let _ = self.advance()
          }
          RBracket => {
            if bracket_depth > 0 {
              bracket_depth -= 1
            }
            let _ = self.advance()
          }
          _ => {
            let _ = self.advance()
          }
        }
      }
    }
  }
}

///|
fn Parser::skip_param_modifiers(self : Parser) -> Unit {
  let mut has_modifier = true
  while has_modifier {
    has_modifier = false
    match self.peek().kind {
      Ident(name) if name == "public" ||
        name == "private" ||
        name == "protected" ||
        name == "readonly" ||
        name == "override" =>
        match self.peek_at(1).kind {
          Ident(_)
          | PrivateIdent(_)
          | LBrace
          | LBracket
          | Yield
          | NumberType
          | BooleanType
          | StringType
          | VoidType
          | IntType
          | Type
          | Of
          | In => {
            let _ = self.advance()
            has_modifier = true
          }
          _ => ()
        }
      _ => ()
    }
  }
}

///|
fn wrap_optional_ts_type(type_ : @ast.TsType) -> @ast.TsType {
  match type_ {
    @ast.TsType::Undefined | @ast.TsType::Null =>
      @ast.TsType::Union([type_, @ast.TsType::Undefined])
    @ast.TsType::Union(items) => {
      for item in items {
        match item {
          @ast.TsType::Undefined | @ast.TsType::Null => return type_
          _ => ()
        }
      }
      @ast.TsType::Union([type_, @ast.TsType::Undefined])
    }
    _ => @ast.TsType::Union([type_, @ast.TsType::Undefined])
  }
}

///|
// / parameter
fn Parser::parse_param(self : Parser) -> @ast.TsParam raise ParseError {
  self.skip_param_decorators()
  self.skip_param_modifiers()
  let is_rest = self.match_ellipsis()
  let binding = self.parse_binding_pattern()
  let name = self.binding_first_name(binding)
  let is_optional = self.match_(Question)
  // type ()
  let base_type = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any // type Any
  }
  let type_ = if is_optional {
    wrap_optional_ts_type(base_type)
  } else {
    base_type
  }
  // check
  let default : @ast.TsExpr? = if self.match_(Eq) {
    Some(self.parse_assignment())
  } else {
    None
  }
  { name, binding: Some(binding), is_rest, type_, default }
}

///|
// / parameter
fn Parser::parse_params(self : Parser) -> Array[@ast.TsParam] raise ParseError {
  let params : Array[@ast.TsParam] = []
  if !self.check(RParen) {
    params.push(self.parse_param())
    while self.match_(Comma) {
      if self.check(RParen) {
        break
      }
      params.push(self.parse_param())
    }
  }
  // Check for duplicate parameter names
  // In strict mode or with non-simple parameters (default, rest, destructuring),
  // duplicate names are forbidden
  let has_default = params.iter().any(fn(p) { !(p.default is None) })
  let has_rest = params.iter().any(fn(p) { p.is_rest })
  let has_destructuring = params
    .iter()
    .any(fn(p) {
      match p.binding {
        Some(@ast.TsBinding::Array(_)) | Some(@ast.TsBinding::Object(_)) => true
        _ => false
      }
    })
  let is_simple = !has_default && !has_rest && !has_destructuring
  // Collect all bound names
  let all_names : Array[String] = []
  for param in params {
    match param.binding {
      Some(binding) => self.collect_binding_names(binding, all_names)
      None => ()
    }
  }
  // Check for duplicates
  let seen : Map[String, Bool] = {}
  for name in all_names {
    if seen.contains(name) {
      // In strict mode or with non-simple params, duplicates are errors
      if self.in_strict || !is_simple {
        raise ParseError("Duplicate parameter name '\{name}' not allowed")
      }
    }
    seen[name] = true
  }
  params
}

///|
// / function
pub fn Parser::parse_function(self : Parser) -> @ast.TsFunc raise ParseError {
  let _ = self.expect(Function)
  let is_generator = self.match_(Star)
  let is_async = self.in_async
  let name = self.parse_binding_ident()
  let (type_params, type_param_bounds) = self.parse_type_param_names_and_bounds()
  let local_type_param_bound_len = self.push_local_type_param_bounds(
    type_param_bounds,
  )
  let _ = self.expect(LParen)
  let params = self.parse_params()
  let _ = self.expect(RParen)
  // return valuetype ()
  let return_type = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any // type Any
  }
  self.restore_local_type_param_bounds(local_type_param_bound_len)
  if self.check(Semicolon) {
    let _ = self.advance()
    return {
      name,
      type_params,
      params,
      return_type,
      body: { stmts: [] },
      is_generator,
      is_async,
    }
  }
  if !self.check(LBrace) {
    return {
      name,
      type_params,
      params,
      return_type,
      body: { stmts: [] },
      is_generator,
      is_async,
    }
  }
  // Save and set function context (new function scope resets iteration/switch/labels context)
  let prev_generator = self.in_generator
  let prev_async = self.in_async
  let prev_function = self.in_function
  let prev_iteration = self.in_iteration
  let prev_switch = self.in_switch
  // Save labels and clear for new function scope (labels don't cross function boundaries)
  let prev_labels : Array[String] = []
  for label in self.labels {
    prev_labels.push(label)
  }
  if is_generator {
    self.in_generator = true
  }
  self.in_async = false // Reset for nested functions
  self.in_function = true
  self.in_iteration = false
  self.in_switch = false
  // Clear labels for new function scope
  while self.labels.length() > 0 {
    let _ = self.labels.pop()
  }
  let body = self.parse_block()
  self.in_generator = prev_generator
  self.in_async = prev_async
  self.in_function = prev_function
  self.in_iteration = prev_iteration
  self.in_switch = prev_switch
  // Restore labels
  while self.labels.length() > 0 {
    let _ = self.labels.pop()
  }
  for label in prev_labels {
    self.labels.push(label)
  }
  { name, type_params, params, return_type, body, is_generator, is_async }
}

///|
// / functionexpression()
fn Parser::parse_function_expr(self : Parser) -> @ast.TsFunc raise ParseError {
  let _ = self.expect(Function)
  let is_generator = self.match_(Star)
  let is_async = self.in_async
  let name = match self.peek().kind {
    Ident(_)
    | Yield
    | NumberType
    | BooleanType
    | StringType
    | VoidType
    | IntType
    | Type
    | Let
    | Switch
    | Case
    | Default
    | With
    | Debugger
    | Import
    | Export
    | From
    | As
    | Of
    | In => self.parse_binding_ident()
    _ => "<anon>"
  }
  let (type_params, _) = self.parse_type_param_names_and_bounds()
  let _ = self.expect(LParen)
  let params = self.parse_params()
  let _ = self.expect(RParen)
  let return_type = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any
  }
  // Save and set function context (new function scope resets iteration/switch/labels context)
  let prev_generator = self.in_generator
  let prev_async = self.in_async
  let prev_function = self.in_function
  let prev_iteration = self.in_iteration
  let prev_switch = self.in_switch
  // Save labels and clear for new function scope (labels don't cross function boundaries)
  let prev_labels : Array[String] = []
  for label in self.labels {
    prev_labels.push(label)
  }
  if is_generator {
    self.in_generator = true
  }
  self.in_async = false // Reset for nested functions
  self.in_function = true
  self.in_iteration = false
  self.in_switch = false
  // Clear labels for new function scope
  while self.labels.length() > 0 {
    let _ = self.labels.pop()
  }
  let body = self.parse_block()
  self.in_generator = prev_generator
  self.in_async = prev_async
  self.in_function = prev_function
  self.in_iteration = prev_iteration
  self.in_switch = prev_switch
  // Restore labels
  while self.labels.length() > 0 {
    let _ = self.labels.pop()
  }
  for label in prev_labels {
    self.labels.push(label)
  }
  { name, type_params, params, return_type, body, is_generator, is_async }
}

///|
/// Skip generic type parameters <T, U extends Foo, V = Default>
fn Parser::skip_type_params(self : Parser) -> Unit {
  if !self.check(Lt) {
    return
  }
  let _ = self.advance() // consume <
  let mut depth = 1
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
        // >> counts as two >
        depth -= 2
        let _ = self.advance()
      }
      GtGtGt => {
        // >>> counts as three >
        depth -= 3
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
fn Parser::skip_type_param_tail_until_delim(self : Parser) -> Unit {
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut brace_depth = 0
  let mut angle_depth = 0
  while !self.check(Eof) {
    match self.peek().kind {
      Comma if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => break
      Gt if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => break
      LParen => {
        paren_depth += 1
        let _ = self.advance()
      }
      RParen => {
        if paren_depth > 0 {
          paren_depth -= 1
        }
        let _ = self.advance()
      }
      LBracket => {
        bracket_depth += 1
        let _ = self.advance()
      }
      RBracket => {
        if bracket_depth > 0 {
          bracket_depth -= 1
        }
        let _ = self.advance()
      }
      LBrace => {
        brace_depth += 1
        let _ = self.advance()
      }
      RBrace =>
        if brace_depth > 0 {
          brace_depth -= 1
          let _ = self.advance()
        } else {
          break
        }
      Lt => {
        angle_depth += 1
        let _ = self.advance()
      }
      Gt =>
        if angle_depth > 0 {
          angle_depth -= 1
          let _ = self.advance()
        } else {
          break
        }
      GtGt =>
        if angle_depth >= 2 {
          angle_depth -= 2
          let _ = self.advance()
        } else if angle_depth == 1 {
          let tok = self.advance()
          self.pending_gt += 1
          self.pending_gt_pos = tok.pos
          angle_depth = 0
          break
        } else {
          break
        }
      GtGtGt =>
        if angle_depth >= 3 {
          angle_depth -= 3
          let _ = self.advance()
        } else if angle_depth == 2 {
          let tok = self.advance()
          self.pending_gt += 1
          self.pending_gt_pos = tok.pos
          angle_depth = 0
          break
        } else if angle_depth == 1 {
          let tok = self.advance()
          self.pending_gt += 2
          self.pending_gt_pos = tok.pos
          angle_depth = 0
          break
        } else {
          break
        }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
fn Parser::parse_type_param_names_and_bounds(
  self : Parser,
) -> (Array[String], Array[(String, @ast.TsType)]) {
  let names : Array[String] = []
  let bounds : Array[(String, @ast.TsType)] = []
  if !self.check(Lt) {
    return (names, bounds)
  }
  let _ = self.advance()
  while !self.check(Eof) {
    if self.check(Gt) {
      let _ = self.advance()
      break
    }
    // Optional `const` modifier introduced in TypeScript 5.0:
    // `<const T extends ...>`. The const modifier has no impact on the
    // erased generic shape we keep, so consume and discard it.
    if self.check(Const) {
      let _ = self.advance()
    }
    // Variance modifiers `in` / `out` (TypeScript 4.7+):
    // `<out T extends ..., in U, in out V>`. Both keywords are
    // context-sensitive and only act as modifiers when followed by an
    // identifier; they don't affect the erased generic shape, so consume
    // and discard. `in` lexes as the `In` keyword, `out` lexes as a plain
    // identifier.
    let mut consumed_variance = true
    while consumed_variance {
      consumed_variance = false
      if self.check(In) {
        match self.peek_at(1).kind {
          Ident(_) => {
            let _ = self.advance()
            consumed_variance = true
          }
          _ => ()
        }
      }
      match self.peek().kind {
        Ident("out") =>
          match self.peek_at(1).kind {
            Ident(_) => {
              let _ = self.advance()
              consumed_variance = true
            }
            _ => ()
          }
        _ => ()
      }
    }
    let mut name = ""
    if self.is_qualified_type_name_part(0) {
      name = self.parse_binding_ident() catch { _ => "_" }
    } else {
      self.skip_type_param_tail_until_delim()
      if self.check(Comma) {
        let _ = self.advance()
        continue
      }
      if self.check(Gt) {
        let _ = self.advance()
      }
      break
    }
    names.push(name)
    if self.match_(Extends) {
      let saved_pos = self.pos
      let saved_pending_gt = self.pending_gt
      let saved_pending_gt_pos = self.pending_gt_pos
      try {
        let bound = self.parse_type()
        bounds.push((name, bound))
      } catch {
        _ => {
          self.pos = saved_pos
          self.pending_gt = saved_pending_gt
          self.pending_gt_pos = saved_pending_gt_pos
          self.skip_type_param_tail_until_delim()
        }
      }
    }
    if self.match_(Eq) {
      self.skip_type_param_tail_until_delim()
    }
    if self.check(Comma) {
      let _ = self.advance()
      continue
    }
    if self.check(Gt) {
      let _ = self.advance()
      break
    }
  }
  (names, bounds)
}

///|
fn Parser::push_local_type_param_bounds(
  self : Parser,
  bounds : Array[(String, @ast.TsType)],
) -> Int {
  let old_len = self.local_type_param_bounds.length()
  for bound in bounds {
    self.local_type_param_bounds.push(bound)
  }
  old_len
}

///|
fn Parser::restore_local_type_param_bounds(
  self : Parser,
  old_len : Int,
) -> Unit {
  while self.local_type_param_bounds.length() > old_len {
    let _ = self.local_type_param_bounds.pop()
  }
}

///|
/// Parse simple `extends` names while still skipping complex generic clauses.
fn Parser::parse_extends_names_until_body(self : Parser) -> Array[String] {
  let (names, _) = self.parse_extends_clause_until_body()
  names
}

///|
/// Parse the `extends Foo<A>, Bar.Baz, Qux<X, Y>` clause and return both
/// the base names and the per-base type-argument lists. Used by the
/// interface parser so the checker can substitute `<A>` when walking
/// the inheritance chain.
fn Parser::parse_extends_clause_until_body(
  self : Parser,
) -> (Array[String], Array[Array[@ast.TsType]]) {
  let names : Array[String] = []
  let args_per_name : Array[Array[@ast.TsType]] = []
  if !self.check(Extends) {
    return (names, args_per_name)
  }
  let _ = self.advance() // consume extends
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut angle_depth = 0
  let mut expect_name = true
  while !self.check(Eof) {
    match self.peek().kind {
      LBrace if paren_depth == 0 && bracket_depth == 0 && angle_depth == 0 =>
        break
      Ident(name) if expect_name &&
        paren_depth == 0 &&
        bracket_depth == 0 &&
        angle_depth == 0 => {
        let mut full_name = name
        let _ = self.advance()
        while self.check(Dot) {
          match self.peek_at(1).kind {
            Ident(part) => {
              let _ = self.advance()
              let _ = self.advance()
              full_name = full_name + "." + part
            }
            _ => break
          }
        }
        // Capture type arguments if the next token is `<`. Defensive:
        // fall back to the depth-counting skip when parse_type throws
        // (e.g. on malformed input).
        let base_args : Array[@ast.TsType] = []
        if self.check(Lt) && paren_depth == 0 && bracket_depth == 0 {
          let saved = self.pos
          let parsed = try? ({
            let _ = self.expect(Lt)
            let first = self.parse_type()
            base_args.push(first)
            while self.match_(Comma) {
              if self.check(Gt) || self.check(GtGt) || self.check(GtGtGt) {
                break
              }
              base_args.push(self.parse_type())
            }
            // Accept `>` / `>>` / `>>>` as the closing token; the parser
            // already handles the `>>`/`>>>` ASR-rewrite for nested
            // type-arg lists.
            if self.match_(Gt) {
              ()
            } else if self.check(GtGt) {
              // Consume one `>` and leave a synthetic `Gt` for the outer
              // context — easiest: advance and let the outer depth
              // counter resync.
              let _ = self.advance()
            } else if self.check(GtGtGt) {
              let _ = self.advance()
            }
          })
          match parsed {
            Ok(_) => ()
            Err(_) => {
              self.pos = saved
              base_args.clear()
            }
          }
        }
        names.push(full_name)
        args_per_name.push(base_args)
        expect_name = false
      }
      LParen => {
        paren_depth += 1
        let _ = self.advance()
      }
      RParen => {
        if paren_depth > 0 {
          paren_depth -= 1
        }
        let _ = self.advance()
      }
      LBracket => {
        bracket_depth += 1
        let _ = self.advance()
      }
      RBracket => {
        if bracket_depth > 0 {
          bracket_depth -= 1
        }
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
      Comma => {
        if paren_depth == 0 && bracket_depth == 0 && angle_depth == 0 {
          expect_name = true
        }
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
  (names, args_per_name)
}

///|
fn Parser::can_consume_interface_readonly_modifier(self : Parser) -> Bool {
  if !self.check(Ident("readonly")) {
    return false
  }
  match self.peek_at(1).kind {
    Ident(_)
    | Str(_)
    | Int(_)
    | Number(_)
    | LBracket
    | New
    | Finally
    | Try
    | Catch
    | Throw
    | Delete
    | Debugger
    | Type
    | In
    | Of
    | For
    | From
    | With
    | Typeof
    | Return
    | If
    | Else
    | While
    | Do
    | Switch
    | Case
    | Default
    | Break
    | Continue
    | Extends
    | Class
    | Function
    | Var
    | Let
    | Const
    | StringType
    | NumberType
    | BooleanType
    | VoidType
    | IntType
    | Import
    | Export
    | As
    | Yield
    | Instanceof
    | Declare => true
    _ => false
  }
}

///|
// / interface
pub fn Parser::parse_interface(
  self : Parser,
) -> @ast.TsInterface raise ParseError {
  let _ = self.expect(Interface)
  let name = match self.advance().kind {
    Ident(n) => n
    k => raise ParseError("Expected interface name, got \{k}")
  }
  let (type_params, type_param_bounds) = self.parse_type_param_names_and_bounds()
  let local_type_param_bound_len = self.push_local_type_param_bounds(
    type_param_bounds,
  )
  let (extends_names, extends_args) = self.parse_extends_clause_until_body()
  let _ = self.expect(LBrace)
  let fields : Array[(String, @ast.TsType)] = []
  let readonly_fields : Array[String] = []
  let index_signatures : Array[(@ast.TsType, @ast.TsType)] = []
  while !self.check(RBrace) && !self.check(Eof) {
    // Skip readonly modifier
    let mut is_readonly_field = false
    if self.can_consume_interface_readonly_modifier() {
      let _ = self.advance()
      is_readonly_field = true
    }
    // Parse field/method name
    let field_name : String = match self.peek().kind {
      // Call signature: (...): T
      LParen => "<call>"
      // Generic call signature: <T>(...): U
      Lt => {
        self.skip_type_params()
        "<call>"
      }
      // Constructor signature: new(...): T
      New => {
        let _ = self.advance()
        "<new>"
      }
      // Computed property / index signature: [key: T]: U or [Symbol.xxx]: T
      LBracket => {
        let _ = self.advance()
        // An index signature has the canonical form `[<ident>: <type>]: <type>`,
        // distinguished from a computed property like `[Symbol.iterator]` by
        // the `<ident>` immediately followed by `:`. When recognised we parse
        // the key type directly so later passes can lower the signature into
        // `op_get` / `op_set` accessors instead of dropping the field.
        let is_index_sig_start = match self.peek().kind {
          Ident(_) => self.peek_at(1).kind == Colon
          _ => false
        }
        if is_index_sig_start {
          let _ = self.advance() // consume index name (ignored)
          let _ = self.expect(Colon)
          let key_type = self.parse_type()
          let _ = self.expect(RBracket)
          // Optional `?` is not meaningful on index signatures; consume to be
          // forgiving but ignore.
          let _ = self.match_(Question)
          let value_type = if self.check(Colon) {
            let _ = self.advance()
            self.parse_type()
          } else {
            @ast.TsType::Any
          }
          // Stash on a dedicated index_signatures channel so bridge passes
          // can lower the dynamic key/value pair to `op_get`/`op_set`
          // accessors without contaminating the regular named-field walk.
          index_signatures.push((key_type, value_type))
          let _ = is_readonly_field
          if self.check(Semicolon) || self.check(Comma) {
            let _ = self.advance()
          }
          continue
        }
        let mut saw_colon = false
        while !self.check(RBracket) && !self.check(Eof) {
          if self.check(Colon) {
            saw_colon = true
          }
          let _ = self.advance()
        }
        let _ = self.expect(RBracket)
        if saw_colon {
          "<index_signature>"
        } else {
          "<computed>"
        }
      }
      // Regular identifier
      Ident(n) => {
        let _ = self.advance()
        n
      }
      // String literal as field name: "fieldName"
      Str(s) => {
        let _ = self.advance()
        s
      }
      // Number literal as field name: 0, 1, etc. Both `Int` (integers that
      // fit in i32) and `Number` (anything else: `1.0`, `1e9`, etc.) are
      // valid TS property keys.
      Int(n) => {
        let _ = self.advance()
        n.to_string()
      }
      Number(d) => {
        let _ = self.advance()
        d.to_string()
      }
      // Keywords as field names (TypeScript allows this)
      Finally => {
        let _ = self.advance()
        "finally"
      }
      Try => {
        let _ = self.advance()
        "try"
      }
      Catch => {
        let _ = self.advance()
        "catch"
      }
      Throw => {
        let _ = self.advance()
        "throw"
      }
      Delete => {
        let _ = self.advance()
        "delete"
      }
      Debugger => {
        let _ = self.advance()
        "debugger"
      }
      Type => {
        let _ = self.advance()
        "type"
      }
      In => {
        let _ = self.advance()
        "in"
      }
      Of => {
        let _ = self.advance()
        "of"
      }
      For => {
        let _ = self.advance()
        "for"
      }
      From => {
        let _ = self.advance()
        "from"
      }
      With => {
        let _ = self.advance()
        "with"
      }
      Typeof => {
        let _ = self.advance()
        "typeof"
      }
      Return => {
        let _ = self.advance()
        "return"
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
      Switch => {
        let _ = self.advance()
        "switch"
      }
      Case => {
        let _ = self.advance()
        "case"
      }
      Default => {
        let _ = self.advance()
        "default"
      }
      Break => {
        let _ = self.advance()
        "break"
      }
      Continue => {
        let _ = self.advance()
        "continue"
      }
      Extends => {
        let _ = self.advance()
        "extends"
      }
      Class => {
        let _ = self.advance()
        "class"
      }
      Function => {
        let _ = self.advance()
        "function"
      }
      Var => {
        let _ = self.advance()
        "var"
      }
      Let => {
        let _ = self.advance()
        "let"
      }
      Const => {
        let _ = self.advance()
        "const"
      }
      StringType => {
        let _ = self.advance()
        "string"
      }
      NumberType => {
        let _ = self.advance()
        "number"
      }
      BooleanType => {
        let _ = self.advance()
        "boolean"
      }
      VoidType => {
        let _ = self.advance()
        "void"
      }
      IntType => {
        let _ = self.advance()
        "int"
      }
      Import => {
        let _ = self.advance()
        "import"
      }
      Export => {
        let _ = self.advance()
        "export"
      }
      As => {
        let _ = self.advance()
        "as"
      }
      Yield => {
        let _ = self.advance()
        "yield"
      }
      Instanceof => {
        let _ = self.advance()
        "instanceof"
      }
      Declare => {
        let _ = self.advance()
        "declare"
      }
      // Literal-keyword identifiers also stand in as property names.
      Bool(true) => {
        let _ = self.advance()
        "true"
      }
      Bool(false) => {
        let _ = self.advance()
        "false"
      }
      Null => {
        let _ = self.advance()
        "null"
      }
      // Additional reserved words allowed as interface field names —
      // TS accepts every keyword in property-name position.
      Interface => {
        let _ = self.advance()
        "interface"
      }
      Class => {
        let _ = self.advance()
        "class"
      }
      Const => {
        let _ = self.advance()
        "const"
      }
      Var => {
        let _ = self.advance()
        "var"
      }
      Let => {
        let _ = self.advance()
        "let"
      }
      New => {
        let _ = self.advance()
        "new"
      }
      Try => {
        let _ = self.advance()
        "try"
      }
      Catch => {
        let _ = self.advance()
        "catch"
      }
      Throw => {
        let _ = self.advance()
        "throw"
      }
      Finally => {
        let _ = self.advance()
        "finally"
      }
      Extends => {
        let _ = self.advance()
        "extends"
      }
      Function => {
        let _ = self.advance()
        "function"
      }
      k =>
        raise ParseError("Expected field name at \{self.peek().pos}, got \{k}")
    }
    // Skip method type parameters <T>
    self.skip_type_params()
    // Check for optional marker ?
    let is_optional = self.match_(Question)
    // Method signature: name(...): T or name<T>(...): U
    if self.check(LParen) {
      let _ = self.advance()
      let method_params = self.parse_params()
      let _ = self.expect(RParen)
      // Return type
      let return_type = if self.check(Colon) {
        let _ = self.advance()
        self.parse_type()
      } else {
        @ast.TsType::Void
      }
      let param_types : Array[@ast.TsType] = []
      for param in method_params {
        param_types.push(param.type_)
      }
      let field_type = @ast.TsType::Func(param_types, return_type)
      if field_name != "<index_signature>" {
        fields.push(
          (
            field_name,
            if is_optional {
              wrap_optional_ts_type(field_type)
            } else {
              field_type
            },
          ),
        )
      }
    } else if self.check(Colon) {
      // Property: name: T
      let _ = self.advance()
      let field_type = self.parse_type()
      if field_name != "<index_signature>" {
        fields.push(
          (
            field_name,
            if is_optional {
              wrap_optional_ts_type(field_type)
            } else {
              field_type
            },
          ),
        )
      }
    } else {
      // No type annotation - use Any
      let field_type = @ast.TsType::Any
      if field_name != "<index_signature>" {
        fields.push(
          (
            field_name,
            if is_optional {
              wrap_optional_ts_type(field_type)
            } else {
              field_type
            },
          ),
        )
      }
    }
    if is_readonly_field {
      readonly_fields.push(field_name)
    }
    // Skip trailing semicolon or comma (both optional)
    if self.check(Semicolon) || self.check(Comma) {
      let _ = self.advance()
    }
  }
  let _ = self.expect(RBrace)
  self.restore_local_type_param_bounds(local_type_param_bound_len)
  {
    name,
    type_params,
    extends_names,
    extends_args,
    fields,
    readonly_fields,
    index_signatures,
  }
}

///|
/// Skip until semicolon or end of file, respecting brace/bracket/paren nesting
fn Parser::skip_until_semicolon(self : Parser) -> Unit {
  let mut brace_depth = 0
  let mut bracket_depth = 0
  let mut paren_depth = 0
  while !self.check(Eof) {
    match self.peek().kind {
      Semicolon => {
        if brace_depth == 0 && bracket_depth == 0 && paren_depth == 0 {
          let _ = self.advance()
          return
        }
        let _ = self.advance()
      }
      LBrace => {
        brace_depth += 1
        let _ = self.advance()
      }
      RBrace => {
        brace_depth -= 1
        let _ = self.advance()
      }
      LBracket => {
        bracket_depth += 1
        let _ = self.advance()
      }
      RBracket => {
        bracket_depth -= 1
        let _ = self.advance()
      }
      LParen => {
        paren_depth += 1
        let _ = self.advance()
      }
      RParen => {
        paren_depth -= 1
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
fn Parser::is_top_level_decl_start_token(self : Parser) -> Bool {
  match self.peek().kind {
    Var
    | Let
    | Const
    | Class
    | Import
    | Export
    | Declare
    | Interface
    | Type
    | Function => true
    Ident(name) =>
      name == "abstract" ||
      name == "namespace" ||
      name == "module" ||
      name == "global" ||
      name == "enum" ||
      name == "class"
    _ => false
  }
}

///|
/// Skip type alias: type Name<T> = ...;
fn Parser::skip_type_alias(self : Parser) -> Unit {
  let _ = self.advance() // consume 'type'
  // Skip until semicolon, handling nested braces and angle brackets
  let mut brace_depth = 0
  let mut angle_depth = 0
  while !self.check(Eof) {
    match self.peek().kind {
      LBrace => {
        brace_depth += 1
        let _ = self.advance()
      }
      RBrace => {
        if brace_depth == 0 && angle_depth <= 0 {
          break
        }
        brace_depth -= 1
        let _ = self.advance()
        if brace_depth < 0 {
          break
        }
      }
      Lt => {
        angle_depth += 1
        let _ = self.advance()
      }
      Gt => {
        angle_depth -= 1
        let _ = self.advance()
      }
      GtGt => {
        // >> counts as two >
        angle_depth -= 2
        let _ = self.advance()
      }
      GtGtGt => {
        // >>> counts as three >
        angle_depth -= 3
        let _ = self.advance()
      }
      Semicolon => {
        if brace_depth == 0 && angle_depth <= 0 {
          let _ = self.advance()
          break
        }
        let _ = self.advance()
      }
      _ if brace_depth == 0 &&
        angle_depth <= 0 &&
        self.has_line_terminator_before() &&
        self.is_top_level_decl_start_token() => break
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
fn type_alias_object_fields_to_interface(
  name : String,
  type_params : Array[String],
  type_ : @ast.TsType,
) -> @ast.TsInterface? {
  match type_ {
    @ast.TsType::Object(fields) => {
      let iface_fields : Array[(String, @ast.TsType)] = []
      for field in fields {
        let (key_type, value_type) = field
        match key_type {
          @ast.TsType::Literal(field_name) =>
            iface_fields.push((field_name, value_type))
          _ => return None
        }
      }
      Some({
        name,
        type_params,
        extends_names: [],
        extends_args: [],
        fields: iface_fields,
        readonly_fields: [],
        index_signatures: [],
      })
    }
    _ => None
  }
}

///|
fn type_alias_to_interface(type_alias : @ast.TsTypeAlias) -> @ast.TsInterface? {
  // The conversion from `type X<T extends Bound> = { ... }` to interface is
  // already lossy on T (the resulting interface is treated structurally,
  // without the generic flowing through bridge synthesis). When the alias has
  // bounds, substitute every reference to a bounded type-param with the bound
  // BEFORE conversion. This recovers concrete shapes at value positions like
  // `form: Record<string, T | T[]>` → `Record<string, FormValue | FormValue[]>`
  // while leaving non-Object aliases (e.g. `DateArg<DateType> = DateType | ...`)
  // untouched, since `type_alias_object_fields_to_interface` only fires on
  // Object bodies.
  let body = if type_alias.type_param_bounds.length() > 0 {
    substitute_alias_param_bounds(
      type_alias.type_,
      type_alias.type_param_bounds,
    )
  } else {
    type_alias.type_
  }
  type_alias_object_fields_to_interface(
    type_alias.name,
    type_alias.type_params,
    body,
  )
}

///|
// Walk `type_` and substitute every `Named(name)` reference whose `name`
// appears in `bounds` with that name's bound. Operates structurally over
// every TsType variant. Used by `type_alias_to_interface` to project a
// generic Object-alias body into a concrete interface body.
fn substitute_alias_param_bounds(
  type_ : @ast.TsType,
  bounds : Array[(String, @ast.TsType)],
) -> @ast.TsType {
  fn lookup_bound(name : String) -> @ast.TsType? {
    for entry in bounds {
      if entry.0 == name {
        return Some(entry.1)
      }
    }
    None
  }

  fn walk(t : @ast.TsType) -> @ast.TsType {
    match t {
      Named(name) =>
        match lookup_bound(name) {
          Some(b) => b
          None => t
        }
      Applied(name, args) => {
        let new_args : Array[@ast.TsType] = []
        for a in args {
          new_args.push(walk(a))
        }
        Applied(name, new_args)
      }
      Array(inner) => Array(walk(inner))
      Tuple(items) => {
        let out : Array[@ast.TsType] = []
        for it in items {
          out.push(walk(it))
        }
        Tuple(out)
      }
      Object(fields) => {
        let out : Array[(@ast.TsType, @ast.TsType)] = []
        for f in fields {
          out.push((walk(f.0), walk(f.1)))
        }
        Object(out)
      }
      Func(params, ret) => {
        let new_params : Array[@ast.TsType] = []
        for p in params {
          new_params.push(walk(p))
        }
        Func(new_params, walk(ret))
      }
      Union(items) => {
        let out : Array[@ast.TsType] = []
        for it in items {
          out.push(walk(it))
        }
        Union(out)
      }
      Intersection(items) => {
        let out : Array[@ast.TsType] = []
        for it in items {
          out.push(walk(it))
        }
        Intersection(out)
      }
      Conditional(c, e, tb, fb) =>
        Conditional(walk(c), walk(e), walk(tb), walk(fb))
      IndexedAccess(base, k) => IndexedAccess(walk(base), walk(k))
      _ => t
    }
  }

  walk(type_)
}

///|
fn Parser::parse_type_alias_after_type_keyword(
  self : Parser,
) -> @ast.TsTypeAlias raise ParseError {
  let name = self.parse_binding_ident()
  // Capture the bounds in the AST so bridge passes can consult them at
  // use sites; do NOT push them as local bindings, because doing so would let
  // `parse_type` substitute `Named(T) → bound` inside the alias body, eagerly
  // erasing the generic shape (e.g. `DateArg<DateType>` would become
  // `Date | ...` and lose precision).
  let (type_params, type_param_bounds) = self.parse_type_param_names_and_bounds()
  let _ = self.expect(Eq)
  let alias_type = self.parse_type()
  self.consume_semicolon()
  { name, type_params, type_param_bounds, type_: alias_type }
}

///|
fn Parser::parse_type_alias(self : Parser) -> @ast.TsTypeAlias raise ParseError {
  let _ = self.expect(Type)
  self.parse_type_alias_after_type_keyword()
}

///|
/// Skip declaration block (namespace, module, class, enum, etc.)
fn Parser::skip_declaration_block(self : Parser) -> Unit {
  // Skip until we find { or ;
  while !self.check(LBrace) && !self.check(Semicolon) && !self.check(Eof) {
    let _ = self.advance()
  }
  if self.check(Semicolon) {
    let _ = self.advance()
    return
  }
  if self.check(LBrace) {
    let _ = self.advance()
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
}

///|
// / declare function (without 'declare function' prefix - already consumed)

///|
/// name(params): returnType;
pub fn Parser::parse_declare_function(
  self : Parser,
) -> @ast.TsImport raise ParseError {

  // function
  let name = self.parse_binding_ident()

  let (type_params, type_param_bounds) = self.parse_type_param_names_and_bounds()
  let local_type_param_bound_len = self.push_local_type_param_bounds(
    type_param_bounds,
  )
  // parameter
  let _ = self.expect(LParen)
  let params : Array[(String, @ast.TsType)] = []
  while !self.check(RParen) && !self.check(Eof) {
    // Handle rest parameter: ...name
    let _ = self.match_ellipsis()
    let param_name = self.parse_declare_param_name()
    // Handle optional parameter: name?
    let is_optional = self.match_(Question)
    // Type annotation is optional
    let computed_param_type = if self.check(Colon) {
      let _ = self.advance()
      let parsed = self.parse_type()
      if is_optional {
        wrap_optional_ts_type(parsed)
      } else {
        parsed
      }
    } else if is_optional {
      wrap_optional_ts_type(@ast.TsType::Any)
    } else {
      @ast.TsType::Any
    }
    // TypeScript's `this` parameter at index 0 (`afterAll(this: unknown,
    // fn, timeout)`) types the receiver — there is no runtime arg for
    // it. Drop it so the generated `bridge.js` body doesn't emit
    // `function f(this, ...)`, which Node rejects as a syntax error.
    if !(param_name == "this" && params.length() == 0) {
      params.push((param_name, computed_param_type))
    }
    if self.check(Comma) {
      let _ = self.advance()
    }
  }
  let _ = self.expect(RParen)

  // return valuetype — annotation is optional (TS treats a missing one as
  // `void` for `declare function`, but we use `Any` so the checker matches
  // the convention used elsewhere for un-annotated functions).
  let return_type = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    @ast.TsType::Any
  }
  self.restore_local_type_param_bounds(local_type_param_bound_len)
  self.consume_semicolon()
  { name, module_: "env", type_params, params, return_type }
}

///|
fn Parser::parse_declare_param_name(self : Parser) -> String raise ParseError {
  match self.peek().kind {
    Ident(n) => {
      let _ = self.advance()
      n
    }
    StringType => {
      let _ = self.advance()
      "string"
    }
    NumberType => {
      let _ = self.advance()
      "number"
    }
    BooleanType => {
      let _ = self.advance()
      "boolean"
    }
    VoidType => {
      let _ = self.advance()
      "void"
    }
    Type => {
      let _ = self.advance()
      "type"
    }
    New => {
      let _ = self.advance()
      "new"
    }
    Delete => {
      let _ = self.advance()
      "delete"
    }
    Typeof => {
      let _ = self.advance()
      "typeof"
    }
    In => {
      let _ = self.advance()
      "in"
    }
    Of => {
      let _ = self.advance()
      "of"
    }
    From => {
      let _ = self.advance()
      "from"
    }
    As => {
      let _ = self.advance()
      "as"
    }
    LBrace | LBracket => {
      let open_tok = self.peek().kind
      let close_tok : TokenKind = match open_tok {
        LBrace => RBrace
        _ => RBracket
      }
      let _ = self.advance()
      let mut depth = 1
      while depth > 0 && !self.check(Eof) {
        if self.peek().kind == open_tok {
          depth += 1
        } else if self.peek().kind == close_tok {
          depth -= 1
        }
        let _ = self.advance()
      }
      "<destructured>"
    }
    k => raise ParseError("Expected parameter name, got \{k}")
  }
}

///|
fn Parser::parse_declare_values(
  self : Parser,
) -> Array[@ast.TsValueDecl] raise ParseError {
  let values : Array[@ast.TsValueDecl] = []
  let name = self.parse_binding_ident()
  let type_ = self.parse_var_decl_type()
  if self.match_(Eq) {
    let _ = self.parse_expr()
  }
  values.push({ name, type_ })
  while self.match_(Comma) {
    let next_name = self.parse_binding_ident()
    let next_type = self.parse_var_decl_type()
    if self.match_(Eq) {
      let _ = self.parse_expr()
    }
    values.push({ name: next_name, type_: next_type })
  }
  self.consume_semicolon()
  values
}

///|
fn Parser::parse_declare_signature_params(
  self : Parser,
) -> Array[(String, @ast.TsType)] raise ParseError {
  let _ = self.expect(LParen)
  let params : Array[(String, @ast.TsType)] = []
  while !self.check(RParen) && !self.check(Eof) {
    let _ = self.match_ellipsis()
    let param_name = self.parse_declare_param_name()
    let is_optional = self.match_(Question)
    let base_param_type = if self.check(Colon) {
      let _ = self.advance()
      self.parse_type()
    } else {
      @ast.TsType::Any
    }
    let param_type = if is_optional {
      wrap_optional_ts_type(base_param_type)
    } else {
      base_param_type
    }
    // TypeScript's `this` parameter (`fn(this: T, x: number): void`) types
    // the receiver and is dropped at the JS boundary — there's no runtime
    // arg for it. Skipping it here keeps the generated `bridge.js` from
    // emitting `function f(this, ...)`, which `node` rejects with a
    // `SyntaxError: Unexpected token 'this'`.
    if !(param_name == "this" && params.length() == 0) {
      params.push((param_name, param_type))
    }
    if self.check(Comma) {
      let _ = self.advance()
    }
  }
  let _ = self.expect(RParen)
  params
}

///|
///|
/// Cheap shape check: confirms the token stream starts with `[ Ident :`,
/// the canonical opening of a TS index signature inside a class /
/// interface body. Returns false for the general computed-name pattern
/// `[expr]: T` so the existing skip path still handles it.
fn Parser::is_index_signature_shape_after_lbracket(self : Parser) -> Bool {
  if !self.check(LBracket) {
    return false
  }
  match (self.peek_at(1).kind, self.peek_at(2).kind) {
    (Ident(_), Colon) => true
    _ => false
  }
}

///|
/// Parse a TS index signature inside a class body: `[name: KeyType]:
/// ValueType`. Returns `None` if the shape doesn't match — callers
/// fall back to the original skip path.
fn Parser::try_parse_class_index_signature(
  self : Parser,
) -> (@ast.TsType, @ast.TsType)? raise ParseError {
  let saved = self.pos
  let _ = self.expect(LBracket)
  match self.peek().kind {
    Ident(_) => {
      let _ = self.advance()
    }
    _ => {
      self.pos = saved
      return None
    }
  }
  if !self.match_(Colon) {
    self.pos = saved
    return None
  }
  let key_type = self.parse_type()
  if !self.match_(RBracket) {
    self.pos = saved
    return None
  }
  if !self.match_(Colon) {
    self.pos = saved
    return None
  }
  let value_type = self.parse_type()
  self.consume_semicolon()
  Some((key_type, value_type))
}

fn Parser::parse_declare_class_member_name(
  self : Parser,
) -> String? raise ParseError {
  if self.match_(LBracket) {
    let mut depth = 1
    while depth > 0 && !self.check(Eof) {
      match self.peek().kind {
        LBracket => {
          depth += 1
          let _ = self.advance()
        }
        RBracket => {
          depth -= 1
          let _ = self.advance()
        }
        _ => {
          let _ = self.advance()
        }
      }
    }
    return None
  }
  let name = match self.advance().kind {
    Ident(n) => n
    PrivateIdent(n) => "#" + n
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
    Try => "try"
    Catch => "catch"
    Finally => "finally"
    Throw => "throw"
    Yield => "yield"
    Declare => "declare"
    Type => "type"
    Let => "let"
    Const => "const"
    Var => "var"
    Class => "class"
    New => "new"
    Default => "default"
    Do => "do"
    In => "in"
    Case => "case"
    VoidType => "void"
    With => "with"
    Switch => "switch"
    Typeof => "typeof"
    Delete => "delete"
    Export => "export"
    Import => "import"
    Debugger => "debugger"
    Interface => "interface"
    Instanceof => "instanceof"
    Extends => "extends"
    From => "from"
    As => "as"
    k => raise ParseError("Expected class member name, got \{k}")
  }
  Some(name)
}

///|
fn Parser::parse_declare_class_base_names(self : Parser) -> Array[String] {
  let names : Array[String] = []
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut brace_depth = 0
  let mut angle_depth = 0
  let mut in_extends = false
  let mut expect_name = false
  while !self.check(Eof) {
    match self.peek().kind {
      LBrace if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => break
      Extends if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => {
        in_extends = true
        expect_name = true
        let _ = self.advance()
      }
      Ident("implements") if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => {
        in_extends = false
        expect_name = false
        let _ = self.advance()
      }
      Ident(name) if in_extends &&
        expect_name &&
        paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => {
        let mut full_name = name
        let _ = self.advance()
        while self.check(Dot) {
          match self.peek_at(1).kind {
            Ident(part) => {
              let _ = self.advance()
              let _ = self.advance()
              full_name = full_name + "." + part
            }
            _ => break
          }
        }
        names.push(full_name)
        expect_name = false
      }
      LParen => {
        paren_depth += 1
        let _ = self.advance()
      }
      RParen => {
        if paren_depth > 0 {
          paren_depth -= 1
        }
        let _ = self.advance()
      }
      LBracket => {
        bracket_depth += 1
        let _ = self.advance()
      }
      RBracket => {
        if bracket_depth > 0 {
          bracket_depth -= 1
        }
        let _ = self.advance()
      }
      LBrace => {
        brace_depth += 1
        let _ = self.advance()
      }
      RBrace => {
        if brace_depth > 0 {
          brace_depth -= 1
        }
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
      Comma => {
        if in_extends &&
          paren_depth == 0 &&
          bracket_depth == 0 &&
          brace_depth == 0 &&
          angle_depth == 0 {
          expect_name = true
        }
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
  names
}

///|
fn upsert_class_property(
  properties : Array[@ast.TsClassPropertyDecl],
  property : @ast.TsClassPropertyDecl,
) -> Unit {
  for i in 0..<properties.length() {
    let existing = properties[i]
    if existing.name == property.name &&
      existing.is_static == property.is_static {
      let merged_type = match existing.type_ {
        Any => property.type_
        _ => existing.type_
      }
      properties[i] = {
        name: existing.name,
        type_: merged_type,
        is_static: existing.is_static,
        is_readonly: existing.is_readonly && property.is_readonly,
        is_accessor: false,
      }
      return
    }
  }
  properties.push(property)
}

///|
fn Parser::parse_declare_class(
  self : Parser,
  is_abstract : Bool,
) -> @ast.TsClassDecl raise ParseError {
  let _ = self.expect(Class)
  let name = self.parse_binding_ident()
  let mut class_type_params : Array[String] = []
  let mut class_type_param_bound_len = self.local_type_param_bounds.length()
  if self.check(Lt) {
    let (names, type_param_bounds) = self.parse_type_param_names_and_bounds()
    class_type_params = names
    class_type_param_bound_len = self.push_local_type_param_bounds(
      type_param_bounds,
    )
  }
  let base_names = self.parse_declare_class_base_names()
  let _ = self.expect(LBrace)
  let properties : Array[@ast.TsClassPropertyDecl] = []
  let methods : Array[@ast.TsClassMethodDecl] = []
  let index_signatures : Array[(@ast.TsType, @ast.TsType)] = []
  let mut constructor_params : Array[(String, @ast.TsType)]? = None
  let mut saw_public_constructor = false
  let mut saw_nonpublic_constructor = false
  while !self.check(RBrace) && !self.check(Eof) {
    if self.match_(Semicolon) {
      continue
    }
    // Index signature: `[name: KeyType]: ValueType`. Detect before any
    // modifier consumption so the shape isn't lost when the body opens
    // with `[`. Stale-pattern bail-out: revert to the original skip
    // path if the syntax doesn't match.
    if self.check(LBracket) &&
      self.is_index_signature_shape_after_lbracket() {
      match self.try_parse_class_index_signature() {
        Some(sig) => {
          index_signatures.push(sig)
          continue
        }
        None => ()
      }
    }
    let mut is_static = false
    let mut is_readonly = false
    let mut is_public = true
    let mut is_accessor = false
    let mut has_modifier = true
    while has_modifier {
      has_modifier = false
      match self.peek().kind {
        Ident(mod) if mod == "static" ||
          mod == "readonly" ||
          mod == "override" ||
          mod == "abstract" ||
          mod == "declare" ||
          mod == "accessor" ||
          mod == "public" ||
          mod == "private" ||
          mod == "protected" => {
          // A modifier-like keyword followed directly by `:` / `?:` / `(`
          // / `;` is actually being used as a class member name (TS allows
          // reserved words as property names). Stop consuming modifiers
          // so the regular member-name path picks it up. Drizzle uses
          // this for `protected: TValue` brand fields.
          match self.peek_at(1).kind {
            Colon | LParen | Semicolon | Comma | Eq => break
            Question =>
              match self.peek_at(2).kind {
                Colon | LParen | Semicolon | Comma | Eq => break
                _ => ()
              }
            _ => ()
          }
          let _ = self.advance()
          if mod == "static" {
            is_static = true
          }
          if mod == "readonly" {
            is_readonly = true
          }
          if mod == "accessor" {
            is_accessor = true
          }
          if mod == "private" || mod == "protected" {
            is_public = false
          }
          has_modifier = true
        }
        _ => ()
      }
    }
    let mut accessor_kind : String? = None
    match self.peek().kind {
      Ident(n) if (n == "get" || n == "set") &&
        self.peek_at(1).kind != LParen &&
        self.peek_at(1).kind != Lt &&
        self.peek_at(1).kind != Colon => {
        let _ = self.advance()
        accessor_kind = Some(n)
      }
      _ => ()
    }
    let member_name = self.parse_declare_class_member_name()
    let _ = self.match_(Question)
    // Definite-assignment assertion (`foo!: T`) on a class field. Also
    // tolerate a stray `!` after a method name even though that is not
    // standard syntax, mirroring how the runtime class parser handles it.
    let _ = self.match_(Bang)
    let mut local_type_param_bound_len = self.local_type_param_bounds.length()
    let mut method_type_params : Array[String] = []
    let mut method_type_param_bounds : Array[(String, @ast.TsType)] = []
    if self.check(Lt) {
      let (names, type_param_bounds) = self.parse_type_param_names_and_bounds()
      method_type_params = names
      method_type_param_bounds = type_param_bounds
      local_type_param_bound_len = self.push_local_type_param_bounds(
        type_param_bounds,
      )
    }
    if self.check(LParen) {
      let params = self.parse_declare_signature_params()
      let return_type = if self.check(Colon) {
        let _ = self.advance()
        self.parse_type()
      } else {
        @ast.TsType::Any
      }
      self.restore_local_type_param_bounds(local_type_param_bound_len)
      self.consume_semicolon()
      match member_name {
        Some(member_name) =>
          match accessor_kind {
            Some("get") if is_public =>
              upsert_class_property(properties, {
                name: member_name,
                type_: return_type,
                is_static,
                is_readonly: true,
                is_accessor: false,
              })
            Some("set") if is_public => {
              let setter_type = if params.length() > 0 {
                let (_, type_) = params[0]
                type_
              } else {
                @ast.TsType::Any
              }
              upsert_class_property(properties, {
                name: member_name,
                type_: setter_type,
                is_static,
                is_readonly: false,
                is_accessor: false,
              })
            }
            _ =>
              if member_name == "constructor" &&
                !is_static &&
                accessor_kind is None {
                if is_public {
                  constructor_params = Some(params)
                  saw_public_constructor = true
                } else {
                  saw_nonpublic_constructor = true
                }
              } else if is_public {
                methods.push({
                  name: member_name,
                  type_params: method_type_params,
                  type_param_bounds: method_type_param_bounds,
                  params,
                  return_type,
                  is_static,
                  // Ambient class declarations (`declare class`) and
                  // interface-style method signatures don't carry a
                  // body — leave it as `None`.
                  body: None,
                })
              }
          }
        None => ()
      }
      continue
    }
    self.restore_local_type_param_bounds(local_type_param_bound_len)
    let mut property_type = @ast.TsType::Any
    if self.match_(Colon) {
      property_type = self.parse_type()
    }
    if self.match_(Eq) {
      let _ = self.parse_assignment()
    }
    self.consume_semicolon()
    match member_name {
      Some(member_name) if is_public && accessor_kind is None =>
        upsert_class_property(properties, {
          name: member_name,
          type_: property_type,
          is_static,
          is_readonly,
          is_accessor,
        })
      _ => ()
    }
  }
  let _ = self.expect(RBrace)
  let _ = self.match_(Semicolon)
  let is_constructible = if saw_public_constructor {
    !is_abstract
  } else if saw_nonpublic_constructor {
    false
  } else {
    !is_abstract
  }
  self.restore_local_type_param_bounds(class_type_param_bound_len)
  {
    name,
    type_params: class_type_params,
    base_names,
    constructor_params,
    properties,
    methods,
    index_signatures,
    is_abstract,
    is_constructible,
    decorators: self.take_pending_decorators(),
  }
}

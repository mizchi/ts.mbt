// ============================================
// type
// ============================================

///|
/// Check if current token is a number literal (Int or Number)
fn Parser::is_number_literal(self : Parser) -> Bool {
  match self.peek().kind {
    Int(_) | Number(_) => true
    _ => false
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
fn Parser::is_function_type_param_name_start(self : Parser) -> Bool {
  match self.peek().kind {
    Ident(_)
    | NumberType
    | BooleanType
    | StringType
    | VoidType
    | IntType
    | Type
    | Of
    | In
    | From
    | Delete => true
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
  let mut can_be_function_type = true
  while true {
    let _ = self.match_ellipsis()
    if !self.is_function_type_param_name_start() {
      can_be_function_type = false
      break
    }
    let _ = self.advance()
    let _ = self.match_(Question)
    if !self.match_(Colon) {
      can_be_function_type = false
      break
    }
    param_types.push(self.parse_type())
    if self.match_(Comma) {
      continue
    }
    break
  }
  if can_be_function_type && self.match_(RParen) && self.match_(Arrow) {
    return Func(param_types, self.parse_type())
  }

  self.pos = saved_pos
  let _ = self.expect(LParen)
  let inner = self.parse_type()
  let _ = self.expect(RParen)
  inner
}

///|
/// Parse a single type (not including union/intersection)
fn Parser::parse_primary_type(self : Parser) -> @ast.TsType raise ParseError {
  let tok = self.peek()
  let base_type : @ast.TsType = match tok.kind {
    Lt => {
      self.skip_type_args()
      if self.check(LParen) {
        self.skip_paren_type()
      }
      if self.check(Arrow) {
        let _ = self.advance()
        let _ = self.parse_type()
      }
      Any
    }
    NumberType => {
      let _ = self.advance()
      Number
    }
    IntType => {
      let _ = self.advance()
      Int
    }
    BooleanType => {
      let _ = self.advance()
      Boolean
    }
    StringType => {
      let _ = self.advance()
      String_
    }
    VoidType => {
      let _ = self.advance()
      Void
    }
    Template(_, _, _) => {
      let _ = self.advance()
      String_
    }
    // Literal types: "foo", 1, true, false
    Str(_) => {
      let _ = self.advance()
      Any
    }
    Int(_) | Number(_) => {
      let _ = self.advance()
      Any
    }
    Bool(_) => {
      let _ = self.advance()
      Any
    }
    // null and undefined literal types
    Null => {
      let _ = self.advance()
      Any
    }
    Ident("null")
    | Ident("undefined")
    | Ident("never")
    | Ident("unknown")
    | Ident("object")
    | Ident("symbol")
    | Ident("bigint") => {
      let _ = self.advance()
      Any
    }
    Minus => {
      // Negative number literal: -1
      let _ = self.advance()
      if self.is_number_literal() {
        let _ = self.advance()
      }
      Any
    }
    // Object type: { key: T; ... }
    LBrace => {
      self.skip_object_type()
      Any
    }
    // Tuple type: [T, U]
    LBracket => {
      self.skip_bracket_type()
      Any
    }
    // Parenthesized type or function type: (T) or (x: T) => U
    LParen => self.parse_paren_or_function_type()
    // typeof T
    Typeof => {
      let _ = self.advance()
      self.skip_typeof_operand()
      Any
    }
    // import("...").Type
    Import => {
      let _ = self.advance()
      if self.check(LParen) {
        let _ = self.advance()
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
      // Skip type parameters if present
      if self.check(Lt) {
        self.skip_type_args()
      }
      // Skip parameter list
      if self.check(LParen) {
        self.skip_paren_type()
      }
      Any
    }
    // abstract new (...) => T
    Ident("abstract") => {
      let _ = self.advance()
      if self.check(New) {
        let _ = self.advance()
        if self.check(Lt) {
          self.skip_type_args()
        }
        if self.check(LParen) {
          self.skip_paren_type()
        }
      }
      Any
    }
    // Special identifier-like keywords
    Ident("infer") => {
      let _ = self.advance()
      if self.is_ident() {
        let _ = self.advance()
        // May have extends constraint
        if self.check(Extends) {
          let _ = self.advance()
          let _ = self.parse_primary_type()
        }
      }
      Any
    }
    Ident("keyof") => {
      let _ = self.advance()
      let _ = self.parse_primary_type()
      Any
    }
    Ident("readonly") => {
      let _ = self.advance()
      self.parse_primary_type()
    }
    Ident("unique") => {
      // unique symbol
      let _ = self.advance()
      if self.is_ident() {
        let _ = self.advance()
      }
      Any
    }
    Ident("asserts") => {
      // asserts x is T
      let _ = self.advance()
      self.skip_asserts_clause()
      Any
    }
    Const => {
      let _ = self.advance()
      Any
    }
    Type => {
      let _ = self.advance()
      Named("type")
    }
    // Ident or generic type: Foo, Array<T>
    Ident(name) => {
      let _ = self.advance()
      let mut full_name = name
      while self.check(Dot) && self.peek_at(1).kind is Ident(_) {
        let _ = self.advance()
        match self.advance().kind {
          Ident(next_name) => full_name = full_name + "." + next_name
          _ => ()
        }
      }
      // Check for generic type arguments <T, U>
      if self.check(Lt) {
        self.skip_type_args()
      }
      Named(full_name)
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
  if self.check(LBracket) {
    let _ = self.advance() // [
    if self.check(RBracket) {
      let _ = self.advance() // ]
      return self.parse_postfix_type(Array(base_type))
    }
    // Indexed access type: T[K] - skip it
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
  // Conditional type: T extends U ? V : W - skip it
  if self.check(Extends) {
    self.skip_conditional_type()
    return Any
  }
  base_type
}

///|
fn Parser::parse_type_operand(self : Parser) -> @ast.TsType raise ParseError {
  let base = self.parse_primary_type()
  if self.match_ident("is") {
    let _ = self.parse_type()
    return Boolean
  }
  if self.check(Amp) {
    while self.match_(Amp) {
      let _ = self.parse_primary_type()
    }
    return Any
  }
  base
}

///|
/// Parse full type including union/intersection
fn Parser::parse_type(self : Parser) -> @ast.TsType raise ParseError {
  if self.check(Pipe) {
    let _ = self.advance()
    let _ = self.parse_type_operand()
    while self.match_(Pipe) {
      let _ = self.parse_type_operand()
    }
    return Any
  }
  if self.check(Amp) {
    let _ = self.advance()
    let _ = self.parse_type_operand()
    while self.match_(Amp) {
      let _ = self.parse_type_operand()
    }
    return Any
  }
  let base = self.parse_type_operand()
  // Union type: T | U
  if self.check(Pipe) {
    while self.match_(Pipe) {
      let _ = self.parse_type_operand()
    }
    return Any // Return Any for union types
  }
  base
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
/// Skip bracket type (tuple or indexed): [T, U] or [key: T]
fn Parser::skip_bracket_type(self : Parser) -> Unit {
  let _ = self.advance() // consume [
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
/// Skip conditional type: extends U ? V : W
fn Parser::skip_conditional_type(self : Parser) -> Unit raise ParseError {
  let _ = self.advance() // consume 'extends'
  // Skip constraint type
  let _ = self.parse_primary_type()
  // Skip ? V : W
  if self.check(Question) {
    let _ = self.advance()
    let _ = self.parse_type()
    if self.check(Colon) {
      let _ = self.advance()
      let _ = self.parse_type()
    }
  }
}

///|
/// Skip asserts clause: asserts x is T or asserts x
fn Parser::skip_asserts_clause(self : Parser) -> Unit raise ParseError {
  // asserts x
  if self.is_ident() {
    let _ = self.advance()
  }
  // is T
  if self.check(Ident("is")) {
    let _ = self.advance()
    let _ = self.parse_type()
  }
}

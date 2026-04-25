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
fn Parser::parse_tuple_type(self : Parser) -> @ast.TsType raise ParseError {
  let _ = self.expect(LBracket)
  let items : Array[@ast.TsType] = []
  if self.match_(RBracket) {
    return Tuple(items)
  }
  while !self.check(Eof) {
    let _ = self.match_ellipsis()
    match self.peek().kind {
      Ident(_) if self.peek_at(1).kind == Colon => {
        let _ = self.advance()
        let _ = self.expect(Colon)
      }
      Ident(_) if self.peek_at(1).kind == Question &&
        self.peek_at(2).kind == Colon => {
        let _ = self.advance()
        let _ = self.advance()
        let _ = self.expect(Colon)
      }
      _ => ()
    }
    items.push(self.parse_type())
    if self.match_(Comma) {
      if self.match_(RBracket) {
        break
      }
      continue
    }
    let _ = self.expect(RBracket)
    break
  }
  Tuple(items)
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
    while !self.check(Eof) && !self.check(RBrace) {
      let field_name = match self.advance().kind {
        Ident(name) => name
        _ => {
          self.pos = saved_pos
          return None
        }
      }
      let _ = self.match_(Question)
      let _ = self.expect(Colon)
      fields.push((Literal(field_name), self.parse_type()))
      if self.match_(Semicolon) || self.match_(Comma) {
        continue
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
    Str(value) => {
      let _ = self.advance()
      Literal(value)
    }
    Int(value) => {
      let _ = self.advance()
      Literal(value.to_string())
    }
    Number(value) => {
      let _ = self.advance()
      Literal(value.to_string())
    }
    Bool(value) => {
      let _ = self.advance()
      Literal(value.to_string())
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
    LBrace =>
      match self.try_parse_simple_object_type() {
        Some(type_) => type_
        None => {
          self.skip_object_type()
          Any
        }
      }
    // Tuple type: [T, U]
    LBracket => self.parse_tuple_type()
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
        match self.try_parse_simple_type_args() {
          Some(type_args) => return Applied(full_name, type_args)
          None => self.skip_type_args()
        }
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
  base
}

///|
fn Parser::parse_intersection_type(
  self : Parser,
) -> @ast.TsType raise ParseError {
  let items : Array[@ast.TsType] = [self.parse_type_operand()]
  while self.match_(Amp) {
    items.push(self.parse_type_operand())
  }
  if items.length() == 1 {
    items[0]
  } else {
    Intersection(items)
  }
}

///|
/// Parse full type including union/intersection
fn Parser::parse_type(self : Parser) -> @ast.TsType raise ParseError {
  if self.check(Pipe) {
    let _ = self.advance()
    let items : Array[@ast.TsType] = [self.parse_intersection_type()]
    while self.match_(Pipe) {
      items.push(self.parse_intersection_type())
    }
    return Union(items)
  }
  if self.check(Amp) {
    let _ = self.advance()
    let items : Array[@ast.TsType] = [self.parse_type_operand()]
    while self.match_(Amp) {
      items.push(self.parse_type_operand())
    }
    return Intersection(items)
  }
  let base = self.parse_intersection_type()
  // Union type: T | U
  if self.check(Pipe) {
    let items : Array[@ast.TsType] = [base]
    while self.match_(Pipe) {
      items.push(self.parse_intersection_type())
    }
    return Union(items)
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

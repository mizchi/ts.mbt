// TypeScript

///|
// / error
pub(all) suberror ParseError {
  ParseError(String)
} derive(Show)

///|
// /
pub struct Parser {
  tokens : Array[Token]
  mut pos : Int
  mut in_generator : Bool
} derive(Show)

///|
// / create
pub fn Parser::new(tokens : Array[Token]) -> Parser {
  { tokens, pos: 0, in_generator: false }
}

///|
// / create
pub fn Parser::from_source(src : String) -> Parser {
  let lexer = Lexer::new(src)
  let tokens = lexer.tokenize()
  Parser::new(tokens)
}

///|
// / currentget
fn Parser::peek(self : Parser) -> Token {
  if self.pos >= self.tokens.length() {
    { kind: Eof, pos: 0 }
  } else {
    self.tokens[self.pos]
  }
}

///|
// /
fn Parser::advance(self : Parser) -> Token {
  let tok = self.peek()
  if tok.kind != Eof {
    self.pos += 1
  }
  tok
}

///|
// /
fn Parser::expect(
  self : Parser,
  expected : TokenKind,
) -> Token raise ParseError {
  let tok = self.peek()
  if tok.kind == expected {
    self.advance()
  } else {
    raise ParseError("Expected \{expected}, got \{tok.kind}")
  }
}

///|
// /
fn Parser::check(self : Parser, kind : TokenKind) -> Bool {
  self.peek().kind == kind
}

///|
// / get
fn Parser::peek_at(self : Parser, offset : Int) -> Token {
  let idx = self.pos + offset
  if idx >= self.tokens.length() {
    { kind: Eof, pos: 0 }
  } else {
    self.tokens[idx]
  }
}

///|
// / functioncheck (currentposition `(` )
fn Parser::is_arrow_function(self : Parser) -> Bool {
  // () =>
  if self.peek_at(1).kind == RParen && self.peek_at(2).kind == Arrow {
    return true
  }
  // (ident) => (ident: type) => parameter
  // simplecheck: ( ) , =>
  let mut i = 1
  let mut depth = 1
  while depth > 0 && i < 100 {
    let tok = self.peek_at(i)
    match tok.kind {
      LParen => depth += 1
      RParen => depth -= 1
      Eof => break
      _ => ()
    }
    i += 1
  }
  // i-1 ) position, i )
  self.peek_at(i).kind == Arrow
}

///|
// /
fn Parser::match_(self : Parser, kind : TokenKind) -> Bool {
  if self.check(kind) {
    let _ = self.advance()
    true
  } else {
    false
  }
}

///|
// / (ASIsimple)
fn Parser::consume_semicolon(self : Parser) -> Unit raise ParseError {
  if self.match_(Semicolon) {
    return
  }
  if self.check(RBrace) || self.check(Eof) {
    return
  }
  // ASIsimple: statement
  match self.peek().kind {
    Var
    | Let
    | Const
    | Return
    | Class
    | If
    | Switch
    | While
    | For
    | Break
    | Continue
    | Case
    | Default
    | With
    | Debugger
    | Try
    | Throw
    | Function
    | LBrace
    | Semicolon
    | Ident(_)
    | Number(_)
    | Int(_)
    | Str(_)
    | Bool(_)
    | Null
    | LParen
    | LBracket
    | New
    | PlusPlus
    | MinusMinus
    | Plus
    | Minus
    | Bang
    | Typeof
    | Regex(_, _) => return
    _ => ()
  }
  raise ParseError("Expected Semicolon, got \{self.peek().kind}")
}

///|
// /
fn Parser::consume_binding_name(self : Parser) -> String raise ParseError {
  let _ = self.advance()
  let mut depth = 1
  let mut name = "<destruct>"
  while depth > 0 {
    let tok = self.advance()
    match tok.kind {
      LBracket | LBrace => depth += 1
      RBracket | RBrace => {
        depth -= 1
        if depth == 0 {
          break
        }
      }
      Ident(n) =>
        if name == "<destruct>" {
          name = n
        }
      Eof => raise ParseError("Unexpected EOF in binding pattern")
      _ => ()
    }
  }
  name
}

///|
// /
fn Parser::parse_binding_ident(self : Parser) -> String raise ParseError {
  match self.peek().kind {
    Ident(_) => match self.advance().kind {
      Ident(n) => n
      _ => "<param>"
    }
    Yield => {
      let _ = self.advance()
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
    Let => {
      let _ = self.advance()
      "let"
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
    With => {
      let _ = self.advance()
      "with"
    }
    Debugger => {
      let _ = self.advance()
      "debugger"
    }
    k => raise ParseError("Expected identifier, got \{k}")
  }
}

///|
fn Parser::binding_first_name(self : Parser, binding : TsBinding) -> String {
  match binding {
    TsBinding::Ident(n) => n
    TsBinding::Array(arr) => {
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
    TsBinding::Object(obj) => {
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
    TsBinding::Target(_) => "<destruct>"
  }
}

///|
fn Parser::parse_binding_element(self : Parser) -> TsBindingElem raise ParseError {
  let binding = self.parse_binding_pattern()
  let default : TsExpr? = if self.match_(Eq) {
    Some(self.parse_assignment())
  } else {
    None
  }
  { binding, default }
}

///|
fn Parser::parse_binding_array(self : Parser) -> TsBinding raise ParseError {
  let _ = self.expect(LBracket)
  let items : Array[TsBindingElem?] = []
  let mut rest : TsBinding? = None
  while not(self.check(RBracket)) {
    if self.match_(Ellipsis) {
      let rest_binding = self.parse_binding_pattern()
      rest = Some(rest_binding)
      if self.match_(Comma) {
        // trailing comma after rest
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
  TsBinding::Array({ items, rest })
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
    k => raise ParseError("Expected object binding key, got \{k}")
  }
}

///|
fn Parser::parse_binding_object(self : Parser) -> TsBinding raise ParseError {
  let _ = self.expect(LBrace)
  let props : Array[TsObjectBindingProp] = []
  let mut rest : String? = None
  if not(self.check(RBrace)) {
    while true {
      if self.match_(Ellipsis) {
        let name = self.parse_binding_ident()
        rest = Some(name)
        if self.match_(Comma) {
          // trailing comma
        }
        break
      }
      let (key, key_expr) =
        if self.match_(LBracket) {
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
            let mut default : TsExpr? = None
            if self.match_(Eq) {
              default = Some(self.parse_assignment())
            }
            props.push({
              key,
              key_expr: None,
              binding: TsBinding::Ident(key),
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
  TsBinding::Object({ props, rest })
}

///|
fn Parser::parse_binding_pattern(self : Parser) -> TsBinding raise ParseError {
  match self.peek().kind {
    LBracket => self.parse_binding_array()
    LBrace => self.parse_binding_object()
    _ => {
      let name = self.parse_binding_ident()
      TsBinding::Ident(name)
    }
  }
}

///|
fn Parser::parse_assignment_target_expr(self : Parser) -> TsExpr raise ParseError {
  let expr = self.parse_ternary()
  match expr {
    Var(_) | PropAccess(_, _) | IndexAccess(_, _) => expr
    _ => raise ParseError("Invalid assignment target")
  }
}

///|
fn Parser::parse_assignment_binding_element(self : Parser) -> TsBindingElem raise ParseError {
  let binding = self.parse_assignment_binding_pattern()
  let default : TsExpr? = if self.match_(Eq) {
    Some(self.parse_assignment())
  } else {
    None
  }
  { binding, default }
}

///|
fn Parser::parse_assignment_binding_array(self : Parser) -> TsBinding raise ParseError {
  let _ = self.expect(LBracket)
  let items : Array[TsBindingElem?] = []
  let mut rest : TsBinding? = None
  while not(self.check(RBracket)) {
    if self.match_(Ellipsis) {
      let rest_binding = self.parse_assignment_binding_pattern()
      rest = Some(rest_binding)
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
  TsBinding::Array({ items, rest })
}

///|
fn Parser::parse_assignment_binding_object(self : Parser) -> TsBinding raise ParseError {
  let _ = self.expect(LBrace)
  let props : Array[TsObjectBindingProp] = []
  let mut rest : String? = None
  if not(self.check(RBrace)) {
    while true {
      if self.match_(Ellipsis) {
        let name = self.parse_binding_ident()
        rest = Some(name)
        if self.match_(Comma) {
          // trailing comma
        }
        break
      }
      let (key, key_expr) =
        if self.match_(LBracket) {
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
            let mut default : TsExpr? = None
            if self.match_(Eq) {
              default = Some(self.parse_assignment())
            }
            props.push({
              key,
              key_expr: None,
              binding: TsBinding::Ident(key),
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
  TsBinding::Object({ props, rest })
}

///|
fn Parser::parse_assignment_binding_pattern(self : Parser) -> TsBinding raise ParseError {
  let saved_pos = self.pos
  let saved_gen = self.in_generator
  let target =
    try {
      Some(self.parse_assignment_target_expr())
    } catch {
      _ => None
    }
  match target {
    Some(expr) =>
      match expr {
        Var(name) => TsBinding::Ident(name)
        _ => TsBinding::Target(expr)
      }
    None => {
      self.pos = saved_pos
      self.in_generator = saved_gen
      match self.peek().kind {
        LBracket => self.parse_assignment_binding_array()
        LBrace => self.parse_assignment_binding_object()
        _ => {
          let name = self.parse_binding_ident()
          TsBinding::Ident(name)
        }
      }
    }
  }
}

///|
// / ...
fn Parser::match_ellipsis(self : Parser) -> Bool {
  self.match_(Ellipsis)
}

// ============================================
// type
// ============================================

///|
// / type
fn Parser::parse_type(self : Parser) -> TsType raise ParseError {
  let tok = self.advance()
  let base_type : TsType = match tok.kind {
    NumberType => Number
    IntType => Int
    BooleanType => Boolean
    StringType => String_
    VoidType => Void
    Ident(name) => Named(name)
    _ => raise ParseError("Expected type, got \{tok.kind}")
  }
  // arraytypecheck: type[]
  if self.match_(LBracket) {
    let _ = self.expect(RBracket)
    Array(base_type)
  } else {
    base_type
  }
}

// ============================================
// expression
// ============================================

///|
// / expression (prefer)
pub fn Parser::parse_expr(self : Parser) -> TsExpr raise ParseError {
  self.parse_comma()
}

///|
// / operator
fn Parser::parse_comma(self : Parser) -> TsExpr raise ParseError {
  let mut expr = self.parse_assignment()
  while self.match_(Comma) {
    let right = self.parse_assignment()
    expr = Seq(expr, right)
  }
  expr
}

///|
// / assignmentexpression
fn Parser::parse_assignment(self : Parser) -> TsExpr raise ParseError {
  if (self.check(LBracket) || self.check(LBrace)) &&
    self.is_destructuring_assignment_start() {
    let pattern = self.parse_assignment_binding_pattern()
    let _ = self.expect(Eq)
    let right = self.parse_assignment()
    return AssignPattern(pattern, right)
  }
  let left = self.parse_ternary()
  if self.check(Eq) {
    match left {
      Var(name) => {
        let _ = self.advance()
        let right = self.parse_assignment()
        AssignExpr(name, right)
      }
      PropAccess(obj, prop) => {
        let _ = self.advance()
        let right = self.parse_assignment()
        PropAssignExpr(obj, prop, right)
      }
      IndexAccess(obj, index) => {
        let _ = self.advance()
        let right = self.parse_assignment()
        IndexAssignExpr(obj, index, right)
      }
      _ => left
    }
  } else if self.match_(PlusEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), AddAssign, right)
      PropAccess(obj, prop) => CompoundAssignExpr(PropAccess(obj, prop), AddAssign, right)
      IndexAccess(obj, index) => CompoundAssignExpr(IndexAccess(obj, index), AddAssign, right)
      _ => right
    }
  } else if self.match_(MinusEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), SubAssign, right)
      PropAccess(obj, prop) => CompoundAssignExpr(PropAccess(obj, prop), SubAssign, right)
      IndexAccess(obj, index) => CompoundAssignExpr(IndexAccess(obj, index), SubAssign, right)
      _ => right
    }
  } else if self.match_(StarEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), MulAssign, right)
      PropAccess(obj, prop) => CompoundAssignExpr(PropAccess(obj, prop), MulAssign, right)
      IndexAccess(obj, index) => CompoundAssignExpr(IndexAccess(obj, index), MulAssign, right)
      _ => right
    }
  } else if self.match_(SlashEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), DivAssign, right)
      PropAccess(obj, prop) => CompoundAssignExpr(PropAccess(obj, prop), DivAssign, right)
      IndexAccess(obj, index) => CompoundAssignExpr(IndexAccess(obj, index), DivAssign, right)
      _ => right
    }
  } else if self.match_(PercentEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), ModAssign, right)
      PropAccess(obj, prop) => CompoundAssignExpr(PropAccess(obj, prop), ModAssign, right)
      IndexAccess(obj, index) => CompoundAssignExpr(IndexAccess(obj, index), ModAssign, right)
      _ => right
    }
  } else if self.match_(AmpEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), BitAndAssign, right)
      PropAccess(obj, prop) => CompoundAssignExpr(PropAccess(obj, prop), BitAndAssign, right)
      IndexAccess(obj, index) => CompoundAssignExpr(IndexAccess(obj, index), BitAndAssign, right)
      _ => right
    }
  } else if self.match_(PipeEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), BitOrAssign, right)
      PropAccess(obj, prop) => CompoundAssignExpr(PropAccess(obj, prop), BitOrAssign, right)
      IndexAccess(obj, index) => CompoundAssignExpr(IndexAccess(obj, index), BitOrAssign, right)
      _ => right
    }
  } else if self.match_(CaretEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), BitXorAssign, right)
      PropAccess(obj, prop) => CompoundAssignExpr(PropAccess(obj, prop), BitXorAssign, right)
      IndexAccess(obj, index) => CompoundAssignExpr(IndexAccess(obj, index), BitXorAssign, right)
      _ => right
    }
  } else if self.match_(LtLtEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), ShlAssign, right)
      PropAccess(obj, prop) => CompoundAssignExpr(PropAccess(obj, prop), ShlAssign, right)
      IndexAccess(obj, index) => CompoundAssignExpr(IndexAccess(obj, index), ShlAssign, right)
      _ => right
    }
  } else if self.match_(GtGtEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), ShrAssign, right)
      PropAccess(obj, prop) => CompoundAssignExpr(PropAccess(obj, prop), ShrAssign, right)
      IndexAccess(obj, index) => CompoundAssignExpr(IndexAccess(obj, index), ShrAssign, right)
      _ => right
    }
  } else if self.match_(GtGtGtEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), UShrAssign, right)
      PropAccess(obj, prop) => CompoundAssignExpr(PropAccess(obj, prop), UShrAssign, right)
      IndexAccess(obj, index) => CompoundAssignExpr(IndexAccess(obj, index), UShrAssign, right)
      _ => right
    }
  } else if self.match_(StarStarEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), PowAssign, right)
      PropAccess(obj, prop) => CompoundAssignExpr(PropAccess(obj, prop), PowAssign, right)
      IndexAccess(obj, index) => CompoundAssignExpr(IndexAccess(obj, index), PowAssign, right)
      _ => right
    }
  } else {
    left
  }
}

///|
fn Parser::is_destructuring_assignment_start(self : Parser) -> Bool {
  let saved_pos = self.pos
  let saved_gen = self.in_generator
  let mut ok = false
  try {
    let _ = self.parse_assignment_binding_pattern()
    ok = self.check(Eq)
  } catch {
    _ => ok = false
  }
  self.pos = saved_pos
  self.in_generator = saved_gen
  ok
}

///|
// / operator: cond ? then : else
fn Parser::parse_ternary(self : Parser) -> TsExpr raise ParseError {
  let cond = self.parse_or()
  if self.match_(Question) {
    let then_expr = self.parse_expr()
    let _ = self.expect(Colon)
    let else_expr = self.parse_expr()
    Cond(cond, then_expr, else_expr)
  } else {
    cond
  }
}

///|
// / || (OR)
fn Parser::parse_or(self : Parser) -> TsExpr raise ParseError {
  let mut left = self.parse_and()
  while self.match_(PipePipe) {
    let right = self.parse_and()
    left = BinOp(Or, left, right)
  }
  left
}

///|
// / && (AND)
fn Parser::parse_and(self : Parser) -> TsExpr raise ParseError {
  let mut left = self.parse_bit_or()
  while self.match_(AmpAmp) {
    let right = self.parse_bit_or()
    left = BinOp(And, left, right)
  }
  left
}

///|
// / | (OR)
fn Parser::parse_bit_or(self : Parser) -> TsExpr raise ParseError {
  let mut left = self.parse_bit_xor()
  while self.match_(Pipe) {
    let right = self.parse_bit_xor()
    left = BinOp(BitOr, left, right)
  }
  left
}

///|
// / ^ (XOR)
fn Parser::parse_bit_xor(self : Parser) -> TsExpr raise ParseError {
  let mut left = self.parse_bit_and()
  while self.match_(Caret) {
    let right = self.parse_bit_and()
    left = BinOp(BitXor, left, right)
  }
  left
}

///|
// / & (AND)
fn Parser::parse_bit_and(self : Parser) -> TsExpr raise ParseError {
  let mut left = self.parse_equality()
  while self.match_(Amp) {
    let right = self.parse_equality()
    left = BinOp(BitAnd, left, right)
  }
  left
}

///|
// / === !== == != (comparison)
fn Parser::parse_equality(self : Parser) -> TsExpr raise ParseError {
  let mut left = self.parse_comparison()
  while true {
    if self.match_(EqEqEq) {
      let right = self.parse_comparison()
      left = BinOp(BinEq, left, right)
    } else if self.match_(BangEqEq) {
      let right = self.parse_comparison()
      left = BinOp(BinNe, left, right)
    } else if self.match_(EqEq) {
      let right = self.parse_comparison()
      left = BinOp(AbstractEq, left, right)
    } else if self.match_(BangEq) {
      let right = self.parse_comparison()
      left = BinOp(AbstractNe, left, right)
    } else {
      break
    }
  }
  left
}

///|
// / < <= > >= (comparison)
fn Parser::parse_comparison(self : Parser) -> TsExpr raise ParseError {
  let mut left = self.parse_shift()
  while true {
    if self.match_(Lt) {
      let right = self.parse_shift()
      left = BinOp(BinLt, left, right)
    } else if self.match_(Le) {
      let right = self.parse_shift()
      left = BinOp(BinLe, left, right)
    } else if self.match_(Gt) {
      let right = self.parse_shift()
      left = BinOp(BinGt, left, right)
    } else if self.match_(Ge) {
      let right = self.parse_shift()
      left = BinOp(BinGe, left, right)
    } else if self.match_(Instanceof) {
      let right = self.parse_shift()
      left = BinOp(Instanceof, left, right)
    } else if self.match_(In) {
      let right = self.parse_shift()
      left = BinOp(In, left, right)
    } else {
      break
    }
  }
  left
}

///|
// / << >> >>> ()
fn Parser::parse_shift(self : Parser) -> TsExpr raise ParseError {
  let mut left = self.parse_additive()
  while true {
    if self.match_(LtLt) {
      let right = self.parse_additive()
      left = BinOp(Shl, left, right)
    } else if self.match_(GtGt) {
      let right = self.parse_additive()
      left = BinOp(Shr, left, right)
    } else if self.match_(GtGtGt) {
      let right = self.parse_additive()
      left = BinOp(UShr, left, right)
    } else {
      break
    }
  }
  left
}

///|
// / + - ()
fn Parser::parse_additive(self : Parser) -> TsExpr raise ParseError {
  let mut left = self.parse_multiplicative()
  while true {
    if self.match_(Plus) {
      let right = self.parse_multiplicative()
      left = BinOp(Add, left, right)
    } else if self.match_(Minus) {
      let right = self.parse_multiplicative()
      left = BinOp(Sub, left, right)
    } else {
      break
    }
  }
  left
}

///|
// / * / % ()
fn Parser::parse_multiplicative(self : Parser) -> TsExpr raise ParseError {
  let mut left = self.parse_exponent()
  while true {
    if self.match_(Star) {
      let right = self.parse_exponent()
      left = BinOp(Mul, left, right)
    } else if self.match_(Slash) {
      let right = self.parse_exponent()
      left = BinOp(Div, left, right)
    } else if self.match_(Percent) {
      let right = self.parse_exponent()
      left = BinOp(Mod, left, right)
    } else {
      break
    }
  }
  left
}

///|
// / ** ()
fn Parser::parse_exponent(self : Parser) -> TsExpr raise ParseError {
  let left = self.parse_unary()
  if self.match_(StarStar) {
    let right = self.parse_exponent()
    BinOp(Pow, left, right)
  } else {
    left
  }
}

///|
// / unaryoperator
fn Parser::parse_unary(self : Parser) -> TsExpr raise ParseError {
  if self.match_(Minus) {
    let operand = self.parse_unary()
    UnaryOp(Neg, operand)
  } else if self.match_(Plus) {
    let operand = self.parse_unary()
    UnaryOp(Plus, operand)
  } else if self.match_(Typeof) {
    let operand = self.parse_unary()
    UnaryOp(Typeof, operand)
  } else if self.match_(Delete) {
    let operand = self.parse_unary()
    UnaryOp(Delete, operand)
  } else if self.match_(VoidType) {
    let operand = self.parse_unary()
    UnaryOp(Void, operand)
  } else if self.match_(Bang) {
    let operand = self.parse_unary()
    UnaryOp(Not, operand)
  } else if self.match_(PlusPlus) {
    // ++x ()
    let operand = self.parse_unary()
    UnaryOp(PreInc, operand)
  } else if self.match_(MinusMinus) {
    // --x ()
    let operand = self.parse_unary()
    UnaryOp(PreDec, operand)
  } else if self.match_(Yield) {
    if self.in_generator {
      let expr =
        if self.check(Semicolon) ||
          self.check(Comma) ||
          self.check(RParen) ||
          self.check(RBracket) ||
          self.check(RBrace) {
          None
        } else {
          Some(self.parse_unary())
        }
      Yield(expr)
    } else {
      Var("yield")
    }
  } else {
    self.parse_postfix()
  }
}

///|
// / operator (x++, x--)
fn Parser::parse_postfix(self : Parser) -> TsExpr raise ParseError {
  let mut expr = self.parse_call()
  while true {
    if self.match_(PlusPlus) {
      expr = UnaryOp(PostInc, expr)
    } else if self.match_(MinusMinus) {
      expr = UnaryOp(PostDec, expr)
    } else {
      break
    }
  }
  expr
}

///|
// / function, array, property, method
fn Parser::parse_call(self : Parser) -> TsExpr raise ParseError {
  let mut expr = self.parse_primary()

  // operatorcheck
  while true {
    if self.match_(LParen) {
      // function or method
      let args = self.parse_args()
      let _ = self.expect(RParen)
      match expr {
        Var(name) => {
          expr = Call(name, args)
        }
        PropAccess(receiver, method_name) => {
          // method: receiver.method(args)
          expr = MethodCall(receiver, method_name, args)
        }
        _ => {
          expr = CallExpr(expr, args)
        }
      }
    } else if self.match_(LBracket) {
      // array
      let index = self.parse_expr()
      let _ = self.expect(RBracket)
      expr = IndexAccess(expr, index)
    } else if self.check(Dot) {
      // property
      let _ = self.advance()
      let prop = match self.advance().kind {
        Ident(name) => name
        Return => "return"
        If => "if"
        Else => "else"
        For => "for"
        While => "while"
        Break => "break"
        Continue => "continue"
        Function => "function"
        Do => "do"
        Try => "try"
        Catch => "catch"
        Finally => "finally"
        Throw => "throw"
        Delete => "delete"
        Yield => "yield"
        Let => "let"
        Const => "const"
        Var => "var"
        New => "new"
        Typeof => "typeof"
        Of => "of"
        In => "in"
        Class => "class"
        Declare => "declare"
        Interface => "interface"
        Instanceof => "instanceof"
        NumberType => "number"
        BooleanType => "boolean"
        StringType => "string"
        VoidType => "void"
        IntType => "int"
        Type => "type"
        Extends => "extends"
        k => raise ParseError("Expected property name, got \{k}")
      }
      expr = PropAccess(expr, prop)
    } else {
      break
    }
  }
  expr
}

///|
// / argument
fn Parser::parse_args(self : Parser) -> Array[TsExpr] raise ParseError {
  let args : Array[TsExpr] = []
  if not(self.check(RParen)) {
    if self.match_ellipsis() {
      args.push(self.parse_assignment())
    } else {
      args.push(self.parse_assignment())
    }
    while self.match_(Comma) {
      if self.check(RParen) {
        break
      }
      if self.match_ellipsis() {
        args.push(self.parse_assignment())
      } else {
        args.push(self.parse_assignment())
      }
    }
  }
  args
}

///|
// / expression (literal, variable, , array, new)
fn Parser::parse_primary(self : Parser) -> TsExpr raise ParseError {
  let tok = self.peek()
  match tok.kind {
    Class => self.parse_class_stub()
    Number(n) => {
      let _ = self.advance()
      NumberLit(n)
    }
    Int(i) => {
      let _ = self.advance()
      IntLit(i)
    }
    Bool(b) => {
      let _ = self.advance()
      BoolLit(b)
    }
    NumberType => {
      let _ = self.advance()
      Var("number")
    }
    BooleanType => {
      let _ = self.advance()
      Var("boolean")
    }
    StringType => {
      let _ = self.advance()
      Var("string")
    }
    VoidType => {
      let _ = self.advance()
      Var("void")
    }
    IntType => {
      let _ = self.advance()
      Var("int")
    }
    Type => {
      let _ = self.advance()
      Var("type")
    }
    Str(s) => {
      let _ = self.advance()
      StringLit(s)
    }
    Regex(pattern, flags) => {
      let _ = self.advance()
      let args : Array[TsExpr] = []
      args.push(StringLit(pattern))
      if flags != "" {
        args.push(StringLit(flags))
      }
      New("RegExp", args)
    }
    Ident(name) => {
      if self.peek_at(1).kind == Arrow {
        let _ = self.advance()
        let _ = self.expect(Arrow)
        let body = if self.check(LBrace) {
          let block = self.parse_block()
          ArrowBlock(block)
        } else {
          let expr = self.parse_expr()
          ArrowExpr(expr)
        }
        ArrowFunc(
          [{
            name,
            binding: Some(TsBinding::Ident(name)),
            is_rest: false,
            type_: Any,
            default: None,
          }],
          body,
        )
      } else {
        let _ = self.advance()
        Var(name)
      }
    }
    LParen =>
      // functioncheck
      if self.is_arrow_function() {
        // function: (params) => body
        let _ = self.advance() // (
        let params = self.parse_params()
        let _ = self.expect(RParen)
        let _ = self.expect(Arrow)
        // : blockexpression
        let body = if self.check(LBrace) {
          let block = self.parse_block()
          ArrowBlock(block)
        } else {
          let expr = self.parse_expr()
          ArrowExpr(expr)
        }
        ArrowFunc(params, body)
      } else {
        // regularexpression
        let _ = self.advance()
        let expr = self.parse_expr()
        let _ = self.expect(RParen)
        expr
      }
    LBracket => {
      // arrayliteral: [1, 2, 3]
      let _ = self.advance()
      let elements : Array[TsExpr] = []
      while not(self.check(RBracket)) {
        if self.match_ellipsis() {
          elements.push(self.parse_assignment())
          if self.match_(Comma) {
            if self.check(RBracket) {
              break
            }
            continue
          }
          break
        }
        if self.check(Comma) {
          let _ = self.advance()
          elements.push(ArrayHole)
          continue
        }
        elements.push(self.parse_assignment())
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
      ArrayLit(elements)
    }
    New => {
      // new expression: new Array<number>(10)
      let _ = self.advance()
      if self.match_(Dot) {
        let prop = match self.advance().kind {
          Ident(n) => n
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
          Class => "class"
          NumberType => "number"
          BooleanType => "boolean"
          StringType => "string"
          VoidType => "void"
          IntType => "int"
          Type => "type"
          Extends => "extends"
          k => raise ParseError("Expected property name, got \{k}")
        }
        return PropAccess(Var("new"), prop)
      }
      let mut type_name = ""
      let mut callee_expr : TsExpr? = None
      match self.peek().kind {
        Ident(_) => {
          let first = match self.advance().kind {
            Ident(n) => n
            _ => "<call>"
          }
          type_name = first
          let mut expr : TsExpr = Var(first)
          // allow dotted constructor name: new obj.Type()
          while self.match_(Dot) {
            let part = match self.advance().kind {
              Ident(n) => n
              k => raise ParseError("Expected identifier after '.', got \{k}")
            }
            type_name = type_name + "." + part
            expr = PropAccess(expr, part)
          }
          callee_expr = Some(expr)
          // typeparameter (simpleimplementation)
          if self.match_(Lt) {
            let _ = self.parse_type()
            let _ = self.expect(Gt)
          }
        }
        NumberType => {
          let _ = self.advance()
          type_name = "number"
        }
        BooleanType => {
          let _ = self.advance()
          type_name = "boolean"
        }
        StringType => {
          let _ = self.advance()
          type_name = "string"
        }
        VoidType => {
          let _ = self.advance()
          type_name = "void"
        }
        IntType => {
          let _ = self.advance()
          type_name = "int"
        }
        Type => {
          let _ = self.advance()
          type_name = "type"
        }
        LParen => {
          let _ = self.advance()
          let expr = self.parse_expr()
          let _ = self.expect(RParen)
          callee_expr = Some(expr)
          type_name = "<call>"
        }
        Number(_) | Int(_) | Str(_) | Bool(_) | Null => {
          let expr = self.parse_primary()
          callee_expr = Some(expr)
          type_name = "<call>"
        }
        Function => {
          let func = self.parse_function_expr()
          callee_expr = Some(FuncExpr(func))
          type_name = "<call>"
        }
        Class => {
          let expr = self.parse_class_stub()
          callee_expr = Some(expr)
          type_name = "<class>"
        }
        New => {
          let expr = self.parse_primary()
          callee_expr = Some(expr)
          type_name = "<call>"
        }
        k => raise ParseError("Expected type name after new, got \{k}")
      }
      // If we can derive a dotted name from the callee expression, prefer it.
      match callee_expr {
        Some(expr) =>
          match expr {
            Var(n) => type_name = n
            PropAccess(Var(obj), prop) => type_name = obj + "." + prop
            _ => ()
          }
        None => ()
      }
      let args =
        if self.check(LParen) {
          let _ = self.expect(LParen)
          let args = self.parse_args()
          let _ = self.expect(RParen)
          args
        } else {
          []
        }
      match callee_expr {
        Some(expr) =>
          match expr {
            Var(_) => New(type_name, args)
            _ => NewExpr(expr, args)
          }
        None => New(type_name, args)
      }
    }
    LBrace => {
      // objectliteral: { key: value, ... }
      let _ = self.advance()
      let fields : Array[(String, TsExpr)] = []
      if not(self.check(RBrace)) {
        if self.match_ellipsis() {
          let _ = self.parse_assignment()
        } else {
        // field
        let mut is_ident_key = false
        let _ = self.match_(Star)
        let key = if self.match_(LBracket) {
          let key_expr = self.parse_assignment()
          let _ = self.expect(RBracket)
          self.computed_key_name(key_expr)
        } else {
          match self.advance().kind {
            Ident(n) => {
              is_ident_key = true
              n
            }
            Str(s) => s
            Int(i) => i.to_string()
            Number(n) => n.to_string()
            Yield => "yield"
            Return => "return"
            If => "if"
            Else => "else"
            For => "for"
            While => "while"
            Break => "break"
            Continue => "continue"
            Function => "function"
            Do => "do"
            Try => "try"
            Catch => "catch"
            Finally => "finally"
            Throw => "throw"
            Delete => "delete"
            Let => "let"
            Const => "const"
            Var => "var"
            New => "new"
            Typeof => "typeof"
            Of => "of"
            In => "in"
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
            k => raise ParseError("Expected property name, got \{k}")
          }
        }
        let mut prop_key = key
        let value =
          if is_ident_key &&
            (prop_key == "get" || prop_key == "set") &&
            not(self.check(Colon)) &&
            not(self.check(LParen)) &&
            not(self.check(Comma)) &&
            not(self.check(RBrace)) {
            let acc_key = if self.match_(LBracket) {
              let key_expr = self.parse_assignment()
              let _ = self.expect(RBracket)
              self.computed_key_name(key_expr)
            } else {
              match self.advance().kind {
                Ident(n) => n
                Str(s) => s
                Int(i) => i.to_string()
                Number(n) => n.to_string()
                Yield => "yield"
                Return => "return"
                If => "if"
                Else => "else"
                For => "for"
                While => "while"
                Break => "break"
                Continue => "continue"
                Function => "function"
                Do => "do"
                Try => "try"
                Catch => "catch"
                Finally => "finally"
                Throw => "throw"
                Delete => "delete"
                Let => "let"
                Const => "const"
                Var => "var"
                New => "new"
                Typeof => "typeof"
                Of => "of"
                In => "in"
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
                k => raise ParseError("Expected property name, got \{k}")
              }
            }
            let is_getter = prop_key == "get"
            let func_name = acc_key
            prop_key =
              if is_getter {
                "@@get:" + acc_key
              } else {
                "@@set:" + acc_key
              }
            let _ = self.expect(LParen)
            let params = self.parse_params()
            let _ = self.expect(RParen)
            let return_type = if self.check(Colon) {
              let _ = self.advance()
              self.parse_type()
            } else {
              Any
            }
            let body = self.parse_block()
            FuncExpr({
              name: func_name,
              params,
              return_type,
              body,
              is_generator: false,
            })
          } else if self.match_(Colon) {
            self.parse_assignment()
          } else if is_ident_key && self.match_(Eq) {
            self.parse_assignment()
          } else if self.check(LParen) {
            let _ = self.expect(LParen)
            let params = self.parse_params()
            let _ = self.expect(RParen)
            let return_type = if self.check(Colon) {
              let _ = self.advance()
              self.parse_type()
            } else {
              Any
            }
            let body = self.parse_block()
            FuncExpr({
              name: prop_key,
              params,
              return_type,
              body,
              is_generator: false,
            })
          } else if is_ident_key && (self.check(Comma) || self.check(RBrace)) {
            Var(prop_key)
          } else {
            raise ParseError("Expected Colon, got \{self.peek().kind}")
          }
        fields.push((prop_key, value))
        }
        // field
        while self.match_(Comma) {
          if self.check(RBrace) {
            break // trailing comma
          }
          if self.match_ellipsis() {
            let _ = self.parse_assignment()
            continue
          }
          let mut is_ident_key = false
          let _ = self.match_(Star)
          let key = if self.match_(LBracket) {
            let key_expr = self.parse_assignment()
            let _ = self.expect(RBracket)
            self.computed_key_name(key_expr)
          } else {
            match self.advance().kind {
              Ident(n) => {
                is_ident_key = true
                n
              }
              Str(s) => s
              Int(i) => i.to_string()
              Number(n) => n.to_string()
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
              NumberType => "number"
              BooleanType => "boolean"
              StringType => "string"
              VoidType => "void"
              IntType => "int"
              Type => "type"
              Extends => "extends"
              k => raise ParseError("Expected property name, got \{k}")
            }
          }
          let mut prop_key = key
          let value =
            if is_ident_key &&
              (prop_key == "get" || prop_key == "set") &&
              not(self.check(Colon)) &&
              not(self.check(LParen)) &&
              not(self.check(Comma)) &&
              not(self.check(RBrace)) {
              let acc_key = if self.match_(LBracket) {
                let key_expr = self.parse_assignment()
                let _ = self.expect(RBracket)
                self.computed_key_name(key_expr)
              } else {
                match self.advance().kind {
                  Ident(n) => n
                  Str(s) => s
                  Int(i) => i.to_string()
                  Number(n) => n.to_string()
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
                  NumberType => "number"
                  BooleanType => "boolean"
                  StringType => "string"
                  VoidType => "void"
                  IntType => "int"
                  Type => "type"
                  Extends => "extends"
                  k => raise ParseError("Expected property name, got \{k}")
                }
              }
            let is_getter = prop_key == "get"
            let func_name = acc_key
            prop_key =
              if is_getter {
                "@@get:" + acc_key
              } else {
                "@@set:" + acc_key
              }
            let _ = self.expect(LParen)
            let params = self.parse_params()
            let _ = self.expect(RParen)
              let return_type = if self.check(Colon) {
                let _ = self.advance()
                self.parse_type()
              } else {
                Any
              }
            let body = self.parse_block()
            FuncExpr({
              name: func_name,
              params,
              return_type,
              body,
              is_generator: false,
            })
            } else if self.match_(Colon) {
              self.parse_assignment()
            } else if is_ident_key && self.match_(Eq) {
              self.parse_assignment()
            } else if self.check(LParen) {
              let _ = self.expect(LParen)
              let params = self.parse_params()
              let _ = self.expect(RParen)
              let return_type = if self.check(Colon) {
                let _ = self.advance()
                self.parse_type()
              } else {
                Any
              }
              let body = self.parse_block()
              FuncExpr({
                name: prop_key,
                params,
                return_type,
                body,
                is_generator: false,
              })
            } else if is_ident_key && (self.check(Comma) || self.check(RBrace)) {
              Var(prop_key)
            } else {
              raise ParseError("Expected Colon, got \{self.peek().kind}")
            }
          fields.push((prop_key, value))
        }
      }
      let _ = self.expect(RBrace)
      ObjectLit(fields)
    }
    Function => {
      let func = self.parse_function_expr()
      FuncExpr(func)
    }
    Null => {
      // null literal
      let _ = self.advance()
      NullLit
    }
    _ => raise ParseError("Unexpected token: \{tok.kind}")
  }
}

// ============================================
// statement
// ============================================

///|
// / statement
pub fn Parser::parse_stmt(self : Parser) -> TsStmt raise ParseError {
  let tok = self.peek()
  match tok.kind {
    Var => self.parse_var()
    Let => self.parse_let()
    Const => self.parse_const()
    Return => self.parse_return()
    Throw => self.parse_throw()
    Class => self.parse_class_decl()
    If => self.parse_if()
    Switch => self.parse_switch()
    With => self.parse_with()
    Debugger => self.parse_debugger()
    Do => self.parse_do_while()
    While => self.parse_while()
    For => self.parse_for()
    Try => self.parse_try()
    Function => {
      // internalfunctiondefine: function name() { ... }
      // Let(name, Any, FuncExpr(func))
      let func = self.parse_function()
      Let(func.name, Any, FuncExpr(func))
    }
    Break => {
      let _ = self.advance()
      let label = match self.peek().kind {
        Ident(_) => match self.advance().kind {
          Ident(name) => Some(name)
          _ => None
        }
        _ => None
      }
      self.consume_semicolon()
      Break(label)
    }
    Continue => {
      let _ = self.advance()
      let label = match self.peek().kind {
        Ident(_) => match self.advance().kind {
          Ident(name) => Some(name)
          _ => None
        }
        _ => None
      }
      self.consume_semicolon()
      Continue(label)
    }
    Semicolon => {
      let _ = self.advance()
      Empty
    }
    LBrace => {
      let block = self.parse_block()
      Block(block)
    }
    Ident(_) if self.peek_at(1).kind == Colon => {
      let name = match self.advance().kind {
        Ident(n) => n
        _ => "<label>"
      }
      let _ = self.expect(Colon)
      // statement
      let stmt = self.parse_stmt()
      Label(name, stmt)
    }
    _ =>
      // assignment or expressionstatement
      self.parse_assign_or_expr()
  }
}

///|
// / let statement (type)
fn Parser::parse_let(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Let)
  self.parse_let_like(false)
}

///|
// / const statement (type)
fn Parser::parse_const(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Const)
  self.parse_let_like(true)
}

///|
fn Parser::parse_var(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Var)
  self.parse_let_like(false)
}

///|
fn Parser::parse_let_like(self : Parser, is_const : Bool) -> TsStmt raise ParseError {
  let stmts : Array[TsStmt] = []
  while true {
    let name =
      match self.peek().kind {
        Ident(_) => match self.advance().kind {
          Ident(n) => n
          _ => "<destruct>"
        }
        Yield => {
          let _ = self.advance()
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
        Let => {
          let _ = self.advance()
          "let"
        }
        LBracket | LBrace => self.consume_binding_name()
        k => raise ParseError("Expected identifier, got \{k}")
      }
    // type ()
    let type_ = if self.check(Colon) {
      let _ = self.advance()
      self.parse_type()
    } else {
      Any // type Any
    }
    let init =
      if self.match_(Eq) {
        self.parse_assignment()
      } else {
        if is_const {
          raise ParseError("const declaration requires an initializer")
        } else {
          Var("undefined")
        }
      }
    let stmt =
      if is_const {
        TsStmt::Const(name, type_, init)
      } else {
        TsStmt::Let(name, type_, init)
      }
    stmts.push(stmt)
    if self.match_(Comma) {
      continue
    }
    break
  }
  self.consume_semicolon()
  if stmts.length() == 1 {
    stmts[0]
  } else {
    Block({ stmts, })
  }
}

///|
// / return statement
fn Parser::parse_return(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Return)
  if self.check(Semicolon) {
    let _ = self.advance()
    Return(None)
  } else {
    let expr = self.parse_expr()
    self.consume_semicolon()
    Return(Some(expr))
  }
}

///|
// / throw statement
fn Parser::parse_throw(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Throw)
  let expr = self.parse_expr()
  self.consume_semicolon()
  Throw(expr)
}

///|
// / try/catch/finally statement
fn Parser::parse_try(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Try)
  let try_block = self.parse_block()
  let mut catch_name : String? = None
  let mut catch_block : TsBlock? = None
  if self.match_(Catch) {
    if self.match_(LParen) {
      let name = match self.advance().kind {
        Ident(n) => n
        k => raise ParseError("Expected catch identifier, got \{k}")
      }
      let _ = self.expect(RParen)
      catch_name = Some(name)
    } else {
      catch_name = Some("error")
    }
    catch_block = Some(self.parse_block())
  }
  let mut finally_block : TsBlock? = None
  if self.match_(Finally) {
    finally_block = Some(self.parse_block())
  }
  match (catch_block, finally_block) {
    (None, None) => raise ParseError("try must have catch or finally")
    _ => ()
  }
  Try(try_block, catch_name, catch_block, finally_block)
}

///|
// / if statement
fn Parser::parse_if(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(If)
  let _ = self.expect(LParen)
  let cond = self.parse_expr()
  let _ = self.expect(RParen)
  let then_block = self.parse_block_or_stmt()
  let else_block = if self.match_(Else) {
    if self.check(If) {
      // else if
      { stmts: [self.parse_if()] }
    } else {
      self.parse_block_or_stmt()
    }
  } else {
    { stmts: [] }
  }
  If(cond, then_block, Some(else_block))
}

///|
// / while statement
fn Parser::parse_while(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(While)
  let _ = self.expect(LParen)
  let cond = self.parse_expr()
  let _ = self.expect(RParen)
  let body = self.parse_block_or_stmt()
  While(cond, body)
}

///|
// / do-while statement
fn Parser::parse_do_while(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Do)
  let body = self.parse_block_or_stmt()
  let _ = self.expect(While)
  let _ = self.expect(LParen)
  let cond = self.parse_expr()
  let _ = self.expect(RParen)
  self.consume_semicolon()
  // simple while
  While(cond, body)
}

///|
fn Parser::parse_switch(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Switch)
  let _ = self.expect(LParen)
  let expr = self.parse_expr()
  let _ = self.expect(RParen)
  let _ = self.expect(LBrace)
  let cases : Array[TsSwitchCase] = []
  while not(self.check(RBrace)) {
    let case_test : TsExpr? = if self.match_(Case) {
      Some(self.parse_expr())
    } else if self.match_(Default) {
      None
    } else {
      raise ParseError("Expected case or default in switch")
    }
    let _ = self.expect(Colon)
    let stmts : Array[TsStmt] = []
    while not(self.check(Case)) && not(self.check(Default)) && not(self.check(RBrace)) {
      stmts.push(self.parse_stmt())
    }
    cases.push({ test_expr: case_test, body: { stmts, } })
  }
  let _ = self.expect(RBrace)
  Switch(expr, cases)
}

///|
fn Parser::parse_with(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(With)
  let _ = self.expect(LParen)
  let obj_expr = self.parse_expr()
  let _ = self.expect(RParen)
  let body = self.parse_block_or_stmt()
  With(obj_expr, body)
}

///|
fn Parser::parse_debugger(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Debugger)
  self.consume_semicolon()
  Debugger
}

///|
fn Parser::is_for_of_head(self : Parser) -> Bool {
  let mut i = 0
  let mut paren = 0
  let mut brace = 0
  let mut bracket = 0
  while i < 4096 {
    let tok = self.peek_at(i)
    match tok.kind {
      Eof => return false
      Semicolon =>
        if paren == 0 && brace == 0 && bracket == 0 {
          return false
        }
      RParen =>
        if paren == 0 && brace == 0 && bracket == 0 {
          return false
        } else if paren > 0 {
          paren -= 1
        }
      LParen => paren += 1
      LBrace => brace += 1
      RBrace => if brace > 0 { brace -= 1 }
      LBracket => bracket += 1
      RBracket => if bracket > 0 { bracket -= 1 }
      Of | In =>
        if paren == 0 && brace == 0 && bracket == 0 {
          return true
        }
      _ => ()
    }
    i += 1
  }
  false
}

///|
// / for statement (regularforfor...of)
fn Parser::parse_for(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(For)
  let _ = self.expect(LParen)

  // for...of check: for (var/let/const x of arr)
  if self.check(Let) || self.check(Const) || self.check(Var) {
    let kind = match self.advance().kind {
      Let => TsForOfKind::Let
      Const => TsForOfKind::Const
      Var => TsForOfKind::Var
      _ => TsForOfKind::Var
    }
    let binding = self.parse_binding_pattern()
    // for...of / for...in check
    if self.check(Of) || self.check(In) {
      let is_in = self.check(In)
      let _ = self.advance() // of/in
      let iterable = self.parse_expr()
      let _ = self.expect(RParen)
      let body = self.parse_block_or_stmt()
      // arrayelementtype ( Number)
      if is_in {
        return ForIn(kind, binding, Number, iterable, body)
      }
      return ForOf(kind, binding, Number, iterable, body)
    }
    // regular for (let x: type = init; ...) or for (let x = init; ...)
    let var_name = self.binding_first_name(binding)
    let var_type = if self.check(Colon) {
      let _ = self.advance()
      self.parse_type()
    } else {
      Any // type Any
    }
    let _ = self.expect(Eq)
    let init_expr = self.parse_expr()
    let _ = self.expect(Semicolon)
    let init : TsStmt? = Some(
      match kind {
        TsForOfKind::Const => TsStmt::Const(var_name, var_type, init_expr)
        _ => TsStmt::Let(var_name, var_type, init_expr)
      },
    )
    return self.parse_for_rest(init)
  }

  // init
  let init : TsStmt? = if self.check(Semicolon) {
    let _ = self.advance()
    None
  } else {
    if self.is_for_of_head() {
      let binding = self.parse_assignment_binding_pattern()
      if self.check(Of) || self.check(In) {
        let is_in = self.check(In)
        let _ = self.advance()
        let iterable = self.parse_expr()
        let _ = self.expect(RParen)
        let body = self.parse_block_or_stmt()
        if is_in {
          return ForIn(TsForOfKind::Assign, binding, Number, iterable, body)
        }
        return ForOf(TsForOfKind::Assign, binding, Number, iterable, body)
      }
    }
    let expr = self.parse_expr()
    let stmt : TsStmt =
      if self.match_(Eq) {
        let value = self.parse_expr()
        match expr {
          Var(name) => Assign(name, value)
          IndexAccess(arr, index) => IndexAssign(arr, index, value)
          PropAccess(obj, prop) => PropAssign(obj, prop, value)
          _ => Expr(expr)
        }
      } else if self.match_(PlusEq) {
        let value = self.parse_expr()
        match expr {
          Var(name) => CompoundAssign(name, AddAssign, value)
          _ => Expr(expr)
        }
      } else if self.match_(MinusEq) {
        let value = self.parse_expr()
        match expr {
          Var(name) => CompoundAssign(name, SubAssign, value)
          _ => Expr(expr)
        }
      } else if self.match_(StarEq) {
        let value = self.parse_expr()
        match expr {
          Var(name) => CompoundAssign(name, MulAssign, value)
          _ => Expr(expr)
        }
      } else if self.match_(SlashEq) {
        let value = self.parse_expr()
        match expr {
          Var(name) => CompoundAssign(name, DivAssign, value)
          _ => Expr(expr)
        }
      } else if self.match_(PercentEq) {
        let value = self.parse_expr()
        match expr {
          Var(name) => CompoundAssign(name, ModAssign, value)
          _ => Expr(expr)
        }
      } else if self.match_(AmpEq) {
        let value = self.parse_expr()
        match expr {
          Var(name) => CompoundAssign(name, BitAndAssign, value)
          _ => Expr(expr)
        }
      } else if self.match_(PipeEq) {
        let value = self.parse_expr()
        match expr {
          Var(name) => CompoundAssign(name, BitOrAssign, value)
          _ => Expr(expr)
        }
      } else if self.match_(CaretEq) {
        let value = self.parse_expr()
        match expr {
          Var(name) => CompoundAssign(name, BitXorAssign, value)
          _ => Expr(expr)
        }
      } else if self.match_(LtLtEq) {
        let value = self.parse_expr()
        match expr {
          Var(name) => CompoundAssign(name, ShlAssign, value)
          _ => Expr(expr)
        }
      } else if self.match_(GtGtEq) {
        let value = self.parse_expr()
        match expr {
          Var(name) => CompoundAssign(name, ShrAssign, value)
          _ => Expr(expr)
        }
      } else if self.match_(GtGtGtEq) {
        let value = self.parse_expr()
        match expr {
          Var(name) => CompoundAssign(name, UShrAssign, value)
          _ => Expr(expr)
        }
      } else if self.match_(StarStarEq) {
        let value = self.parse_expr()
        match expr {
          Var(name) => CompoundAssign(name, PowAssign, value)
          _ => Expr(expr)
        }
      } else {
        Expr(expr)
      }
    let _ = self.expect(Semicolon)
    Some(stmt)
  }
  self.parse_for_rest(init)
}

///|
// / forstatement (cond, update, body)
fn Parser::parse_for_rest(
  self : Parser,
  init : TsStmt?,
) -> TsStmt raise ParseError {

  // cond
  let cond : TsExpr? = if self.check(Semicolon) {
    None
  } else {
    Some(self.parse_expr())
  }
  let _ = self.expect(Semicolon)

  // update ()
  let update : TsStmt? = if self.check(RParen) {
    None
  } else {
    let expr = self.parse_expr()
    if self.match_(Eq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(Assign(name, value))
        IndexAccess(arr, index) => Some(IndexAssign(arr, index, value))
        PropAccess(obj, prop) => Some(PropAssign(obj, prop, value))
        _ => raise ParseError("Invalid assignment target in for update")
      }
    } else if self.match_(PlusEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(CompoundAssign(name, AddAssign, value))
        _ => raise ParseError("Invalid compound assignment in for update")
      }
    } else if self.match_(MinusEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(CompoundAssign(name, SubAssign, value))
        _ => raise ParseError("Invalid compound assignment in for update")
      }
    } else if self.match_(StarEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(CompoundAssign(name, MulAssign, value))
        _ => raise ParseError("Invalid compound assignment in for update")
      }
    } else if self.match_(SlashEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(CompoundAssign(name, DivAssign, value))
        _ => raise ParseError("Invalid compound assignment in for update")
      }
    } else if self.match_(PercentEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(CompoundAssign(name, ModAssign, value))
        _ => raise ParseError("Invalid compound assignment in for update")
      }
    } else if self.match_(AmpEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(CompoundAssign(name, BitAndAssign, value))
        _ => raise ParseError("Invalid compound assignment in for update")
      }
    } else if self.match_(PipeEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(CompoundAssign(name, BitOrAssign, value))
        _ => raise ParseError("Invalid compound assignment in for update")
      }
    } else if self.match_(CaretEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(CompoundAssign(name, BitXorAssign, value))
        _ => raise ParseError("Invalid compound assignment in for update")
      }
    } else if self.match_(LtLtEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(CompoundAssign(name, ShlAssign, value))
        _ => raise ParseError("Invalid compound assignment in for update")
      }
    } else if self.match_(GtGtEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(CompoundAssign(name, ShrAssign, value))
        _ => raise ParseError("Invalid compound assignment in for update")
      }
    } else if self.match_(GtGtGtEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(CompoundAssign(name, UShrAssign, value))
        _ => raise ParseError("Invalid compound assignment in for update")
      }
    } else if self.match_(StarStarEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(CompoundAssign(name, PowAssign, value))
        _ => raise ParseError("Invalid compound assignment in for update")
      }
    } else {
      Some(Expr(expr))
    }
  }
  let _ = self.expect(RParen)
  let body = self.parse_block_or_stmt()
  For(init, cond, update, body)
}

///|
// / assignmentexpressionstatement
fn Parser::parse_assign_or_expr(self : Parser) -> TsStmt raise ParseError {
  // expression
  let expr = self.parse_expr()

  // assignmentcheck
  if self.match_(Eq) {
    let value = self.parse_expr()
    self.consume_semicolon()
    match expr {
      Var(name) => Assign(name, value)
      IndexAccess(arr, index) => IndexAssign(arr, index, value)
      PropAccess(obj, prop) => PropAssign(obj, prop, value)
      _ => raise ParseError("Invalid assignment target")
    }
  } else if self.match_(PlusEq) {
    let value = self.parse_expr()
    self.consume_semicolon()
    match expr {
      Var(name) => CompoundAssign(name, AddAssign, value)
      _ => raise ParseError("Invalid compound assignment target")
    }
  } else if self.match_(MinusEq) {
    let value = self.parse_expr()
    self.consume_semicolon()
    match expr {
      Var(name) => CompoundAssign(name, SubAssign, value)
      _ => raise ParseError("Invalid compound assignment target")
    }
  } else if self.match_(StarEq) {
    let value = self.parse_expr()
    self.consume_semicolon()
    match expr {
      Var(name) => CompoundAssign(name, MulAssign, value)
      _ => raise ParseError("Invalid compound assignment target")
    }
  } else if self.match_(SlashEq) {
    let value = self.parse_expr()
    self.consume_semicolon()
    match expr {
      Var(name) => CompoundAssign(name, DivAssign, value)
      _ => raise ParseError("Invalid compound assignment target")
    }
  } else if self.match_(PercentEq) {
    let value = self.parse_expr()
    self.consume_semicolon()
    match expr {
      Var(name) => CompoundAssign(name, ModAssign, value)
      _ => raise ParseError("Invalid compound assignment target")
    }
  } else if self.match_(AmpEq) {
    let value = self.parse_expr()
    self.consume_semicolon()
    match expr {
      Var(name) => CompoundAssign(name, BitAndAssign, value)
      _ => raise ParseError("Invalid compound assignment target")
    }
  } else if self.match_(PipeEq) {
    let value = self.parse_expr()
    self.consume_semicolon()
    match expr {
      Var(name) => CompoundAssign(name, BitOrAssign, value)
      _ => raise ParseError("Invalid compound assignment target")
    }
  } else if self.match_(CaretEq) {
    let value = self.parse_expr()
    self.consume_semicolon()
    match expr {
      Var(name) => CompoundAssign(name, BitXorAssign, value)
      _ => raise ParseError("Invalid compound assignment target")
    }
  } else if self.match_(LtLtEq) {
    let value = self.parse_expr()
    self.consume_semicolon()
    match expr {
      Var(name) => CompoundAssign(name, ShlAssign, value)
      _ => raise ParseError("Invalid compound assignment target")
    }
  } else if self.match_(GtGtEq) {
    let value = self.parse_expr()
    self.consume_semicolon()
    match expr {
      Var(name) => CompoundAssign(name, ShrAssign, value)
      _ => raise ParseError("Invalid compound assignment target")
    }
  } else if self.match_(GtGtGtEq) {
    let value = self.parse_expr()
    self.consume_semicolon()
    match expr {
      Var(name) => CompoundAssign(name, UShrAssign, value)
      _ => raise ParseError("Invalid compound assignment target")
    }
  } else if self.match_(StarStarEq) {
    let value = self.parse_expr()
    self.consume_semicolon()
    match expr {
      Var(name) => CompoundAssign(name, PowAssign, value)
      _ => raise ParseError("Invalid compound assignment target")
    }
  } else {
    if self.match_(Comma) {
      let mut last = self.parse_expr()
      while self.match_(Comma) {
        last = self.parse_expr()
      }
      self.consume_semicolon()
      Expr(last)
    } else {
      self.consume_semicolon()
      Expr(expr)
    }
  }
}

///|
// / block
pub fn Parser::parse_block(self : Parser) -> TsBlock raise ParseError {
  let _ = self.expect(LBrace)
  let stmts : Array[TsStmt] = []
  while not(self.check(RBrace)) && not(self.check(Eof)) {
    stmts.push(self.parse_stmt())
  }
  let _ = self.expect(RBrace)
  { stmts, }
}

///|
fn Parser::skip_until_class_body(self : Parser) -> Unit {
  let mut paren = 0
  let mut bracket = 0
  while not(self.check(LBrace)) && not(self.check(Eof)) {
    match self.advance().kind {
      LParen => paren += 1
      RParen => if paren > 0 { paren -= 1 }
      LBracket => bracket += 1
      RBracket => if bracket > 0 { bracket -= 1 }
      _ => ()
    }
  }
}

///|
///|
fn Parser::scan_class_body_has_static_name(self : Parser) -> Bool raise ParseError {
  if not(self.match_(LBrace)) {
    raise ParseError("Expected LBrace, got \{self.peek().kind}")
  }
  let mut depth = 1
  let mut has_static_name = false
  let mut saw_static = false
  while depth > 0 && not(self.check(Eof)) {
    let tok = self.advance().kind
    match tok {
      LBrace => {
        depth += 1
        if depth == 1 {
          saw_static = false
        }
      }
      RBrace => {
        depth -= 1
        saw_static = false
      }
      Ident(n) =>
        if depth == 1 {
          if saw_static {
            if n == "name" {
              has_static_name = true
            }
            saw_static = false
          } else {
            saw_static = n == "static"
          }
        }
      _ =>
        if depth == 1 {
          saw_static = false
        }
    }
  }
  if depth > 0 {
    raise ParseError("Expected RBrace, got Eof")
  }
  has_static_name
}

///|
fn Parser::parse_class_method_name(self : Parser) -> String raise ParseError {
  if self.match_(LBracket) {
    let key_expr = self.parse_assignment()
    let _ = self.expect(RBracket)
    return self.computed_key_name(key_expr)
  }
  match self.advance().kind {
    Ident(n) => n
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
    Type => "type"
    Let => "let"
    Const => "const"
    Var => "var"
    Class => "class"
    New => "new"
    k => raise ParseError("Expected method name, got \{k}")
  }
}

///|
fn Parser::computed_key_name(
  _self : Parser,
  key_expr : TsExpr,
) -> String {
  match key_expr {
    StringLit(s) => s
    IntLit(i) => i.to_string()
    NumberLit(n) => n.to_string()
    Var(name) => name
    PropAccess(Var("Symbol"), prop) => "@@" + prop
    _ => "<computed>"
  }
}

///|
fn Parser::parse_class_body(
  self : Parser,
) -> (TsFunc?, Array[(Bool, String, TsFunc)]) raise ParseError {
  let _ = self.expect(LBrace)
  let mut ctor : TsFunc? = None
  let methods : Array[(Bool, String, TsFunc)] = []
  while not(self.check(RBrace)) && not(self.check(Eof)) {
    if self.match_(Semicolon) {
      continue
    }
    let mut is_static = false
    let mut has_modifier = true
    while has_modifier {
      has_modifier = false
      match self.peek().kind {
        Ident(n) if n == "static" =>
          if self.peek_at(1).kind != LParen {
            let _ = self.advance()
            is_static = true
            has_modifier = true
          }
        Ident(n) if n == "async" =>
          if self.peek_at(1).kind != LParen {
            let _ = self.advance()
            has_modifier = true
          }
        _ => ()
      }
    }
    let is_generator = self.match_(Star)
    let name = self.parse_class_method_name()
    let _ = self.expect(LParen)
    let params = self.parse_params()
    let _ = self.expect(RParen)
    let return_type = if self.check(Colon) {
      let _ = self.advance()
      self.parse_type()
    } else {
      Any
    }
    let body = self.parse_block()
    let func : TsFunc = { name, params, return_type, body, is_generator }
    if name == "constructor" && not(is_static) {
      ctor = Some(func)
    } else {
      methods.push((is_static, name, func))
    }
  }
  let _ = self.expect(RBrace)
  (ctor, methods)
}

///|
fn Parser::parse_class_stub(self : Parser) -> TsExpr raise ParseError {
  let _ = self.expect(Class)
  let mut class_name = ""
  let _ =
    match self.peek().kind {
      Ident(n) => {
        class_name = n
        self.advance()
      }
      _ => { kind: Eof, pos: 0 }
    }
  if self.match_(Extends) {
    self.skip_until_class_body()
  }
  let has_static_name = self.scan_class_body_has_static_name()
  let fields : Array[(String, TsExpr)] = []
  fields.push(("__class_name", StringLit(class_name)))
  fields.push(("__class_has_name_prop", BoolLit(has_static_name)))
  let proto = ObjectLit([])
  fields.push(("prototype", proto))
  ObjectLit(fields)
}

///|
fn Parser::parse_class_decl(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Class)
  let name = match self.advance().kind {
    Ident(n) => n
    _ => "<class>"
  }
  let mut base : String? = None
  if self.match_(Extends) {
    base = match self.advance().kind {
      Ident(n) => Some(n)
      k => raise ParseError("Expected base class name, got \{k}")
    }
  }
  let (ctor_opt, methods) = self.parse_class_body()
  let stmts : Array[TsStmt] = []

  let ctor_func = match ctor_opt {
    Some(func) => func
    None => {
      let empty_body : TsBlock = { stmts: [] }
      {
        name,
        params: [],
        return_type: Any,
        body: empty_body,
        is_generator: false,
      }
    }
  }
  stmts.push(Let(name, Any, FuncExpr(ctor_func)))

  let proto_expr = PropAccess(Var(name), "prototype")
  match base {
    Some(base_name) => {
      let base_proto = PropAccess(Var(base_name), "prototype")
      stmts.push(PropAssign(Var(name), "__super_ctor", Var(base_name)))
      stmts.push(PropAssign(Var(name), "__super_proto", base_proto))
      stmts.push(PropAssign(proto_expr, "__proto__", base_proto))
    }
    None => ()
  }

  for item in methods {
    let (is_static, method_name, func) = item
    if is_static {
      stmts.push(PropAssign(Var(name), method_name, FuncExpr(func)))
    } else {
      stmts.push(PropAssign(proto_expr, method_name, FuncExpr(func)))
      match base {
        Some(base_name) => {
          let base_proto = PropAccess(Var(base_name), "prototype")
          let method_ref = PropAccess(proto_expr, method_name)
          stmts.push(PropAssign(method_ref, "__super_proto", base_proto))
        }
        None => ()
      }
    }
  }

  if stmts.length() == 1 {
    stmts[0]
  } else {
    Block({ stmts, })
  }
}

///|
// / blockstatement
fn Parser::parse_block_or_stmt(self : Parser) -> TsBlock raise ParseError {
  if self.check(LBrace) {
    self.parse_block()
  } else {
    { stmts: [self.parse_stmt()], }
  }
}

// ============================================
// function
// ============================================

///|
// / parameter
fn Parser::parse_param(self : Parser) -> TsParam raise ParseError {
  let is_rest = self.match_ellipsis()
  let binding = self.parse_binding_pattern()
  let name = self.binding_first_name(binding)
  // type ()
  let type_ = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any // type Any
  }
  // check
  let default : TsExpr? = if self.match_(Eq) {
    Some(self.parse_assignment())
  } else {
    None
  }
  { name, binding: Some(binding), is_rest, type_, default }
}

///|
// / parameter
fn Parser::parse_params(self : Parser) -> Array[TsParam] raise ParseError {
  let params : Array[TsParam] = []
  if not(self.check(RParen)) {
    params.push(self.parse_param())
    while self.match_(Comma) {
      if self.check(RParen) {
        break
      }
      params.push(self.parse_param())
    }
  }
  params
}

///|
// / function
pub fn Parser::parse_function(self : Parser) -> TsFunc raise ParseError {
  let _ = self.expect(Function)
  let is_generator = self.match_(Star)
  let name = match self.advance().kind {
    Ident(n) => n
    k => raise ParseError("Expected function name, got \{k}")
  }
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
  let prev = self.in_generator
  if is_generator {
    self.in_generator = true
  }
  let body = self.parse_block()
  self.in_generator = prev
  { name, params, return_type, body, is_generator }
}

///|
// / functionexpression()
fn Parser::parse_function_expr(self : Parser) -> TsFunc raise ParseError {
  let _ = self.expect(Function)
  let is_generator = self.match_(Star)
  let name = match self.peek().kind {
    Ident(n) => {
      let _ = self.advance()
      n
    }
    _ => "<anon>"
  }
  let _ = self.expect(LParen)
  let params = self.parse_params()
  let _ = self.expect(RParen)
  let return_type = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any
  }
  let prev = self.in_generator
  if is_generator {
    self.in_generator = true
  }
  let body = self.parse_block()
  self.in_generator = prev
  { name, params, return_type, body, is_generator }
}

///|
// / interface
pub fn Parser::parse_interface(self : Parser) -> TsInterface raise ParseError {
  let _ = self.expect(Interface)
  let name = match self.advance().kind {
    Ident(n) => n
    k => raise ParseError("Expected interface name, got \{k}")
  }
  let _ = self.expect(LBrace)
  let fields : Array[(String, TsType)] = []
  while not(self.check(RBrace)) && not(self.check(Eof)) {
    // field: type;
    let field_name = match self.advance().kind {
      Ident(n) => n
      k => raise ParseError("Expected field name, got \{k}")
    }
    let _ = self.expect(Colon)
    let field_type = self.parse_type()
    let _ = self.expect(Semicolon)
    fields.push((field_name, field_type))
  }
  let _ = self.expect(RBrace)
  { name, fields }
}

///|
// / declare function
/// declare function name(params): returnType;
pub fn Parser::parse_import(self : Parser) -> TsImport raise ParseError {
  let _ = self.expect(Declare)
  let _ = self.expect(Function)

  // function
  let name = match self.advance().kind {
    Ident(n) => n
    _ => raise ParseError("Expected function name after 'declare function'")
  }

  // parameter
  let _ = self.expect(LParen)
  let params : Array[(String, TsType)] = []
  while not(self.check(RParen)) {
    let param_name = match self.advance().kind {
      Ident(n) => n
      _ => raise ParseError("Expected parameter name")
    }
    let _ = self.expect(Colon)
    let param_type = self.parse_type()
    params.push((param_name, param_type))
    if self.check(Comma) {
      let _ = self.advance()

    }
  }
  let _ = self.expect(RParen)

  // return valuetype
  let _ = self.expect(Colon)
  let return_type = self.parse_type()


  let _ = self.expect(Semicolon)
  { name, module_: "env", params, return_type }
}

///|
// /
pub fn Parser::parse_module(self : Parser) -> TsModule raise ParseError {
  let funcs : Array[TsFunc] = []
  let interfaces : Array[TsInterface] = []
  let imports : Array[TsImport] = []
  while not(self.check(Eof)) {
    if self.check(Function) {
      funcs.push(self.parse_function())
    } else if self.check(Interface) {
      interfaces.push(self.parse_interface())
    } else if self.check(Declare) {
      imports.push(self.parse_import())
    } else {
      raise ParseError("Expected function, interface, or declare declaration")
    }
  }
  { funcs, interfaces, imports }
}

///|
// / eval : expression1 Some(expr)
pub fn parse_expr_from_source(source : String) -> TsExpr? raise ParseError {
  let parser = Parser::from_source(source)
  let expr = parser.parse_expr()
  if parser.check(Eof) {
    Some(expr)
  } else {
    None
  }
}

///|
// / eval : statementblock
pub fn parse_block_from_source(source : String) -> TsBlock raise ParseError {
  let parser = Parser::from_source(source)
  let stmts : Array[TsStmt] = []
  while not(parser.check(Eof)) {
    stmts.push(parser.parse_stmt())
  }
  { stmts, }
}

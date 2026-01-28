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
  mut temp_index : Int
} derive(Show)

///|
// / create
pub fn Parser::new(tokens : Array[Token]) -> Parser {
  { tokens, pos: 0, in_generator: false, temp_index: 0 }
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
    | Import
    | Export
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

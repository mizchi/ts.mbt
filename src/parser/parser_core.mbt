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
  mut in_strict : Bool
  src : String
} derive(Show)

///|
// / create
pub fn Parser::new(tokens : Array[Token]) -> Parser {
  Parser::new_with_strict(tokens, false)
}

///|
pub fn Parser::new_with_strict(tokens : Array[Token], in_strict : Bool) -> Parser {
  { tokens, pos: 0, in_generator: false, temp_index: 0, in_strict, src: "" }
}

///|
// / create
pub fn Parser::from_source(src : String) -> Parser {
  let lexer = Lexer::new(src)
  let tokens = lexer.tokenize()
  let trimmed = src.trim_start()
  let in_strict =
    trimmed.has_prefix("\"use strict\";") || trimmed.has_prefix("'use strict';")
  { tokens, pos: 0, in_generator: false, temp_index: 0, in_strict, src }
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

///|
fn Parser::has_line_terminator_between_positions(
  self : Parser,
  start_pos : Int,
  end_pos : Int,
) -> Bool {
  if self.src == "" {
    return false
  }
  let mut i = start_pos
  let limit =
    if end_pos <= self.src.length() {
      end_pos
    } else {
      self.src.length()
    }
  while i < limit {
    let ch = self.src[i]
    if ch == '\n' || ch == '\r' {
      return true
    }
    i += 1
  }
  false
}

///|
fn Parser::has_line_terminator_after(self : Parser) -> Bool {
  let next = self.pos + 1
  if next >= self.tokens.length() {
    return false
  }
  let start_pos = self.tokens[self.pos].pos
  let end_pos = self.tokens[next].pos
  self.has_line_terminator_between_positions(start_pos, end_pos)
}

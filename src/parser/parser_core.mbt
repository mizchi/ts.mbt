// TypeScript

///|
// / error
pub(all) suberror ParseError {
  ParseError(String)
} derive(Debug)

///|
// /
pub struct Parser {
  tokens : Array[Token]
  mut pos : Int
  mut pending_gt : Int
  mut pending_gt_pos : Int
  mut in_generator : Bool
  mut in_async : Bool
  mut temp_index : Int
  // Counter assigned to every `unique symbol` occurrence so the type
  // gets a stable per-occurrence tag.
  mut unique_symbol_index : Int
  mut in_strict : Bool
  mut in_function : Bool // for return validation
  mut in_iteration : Bool // for continue validation
  mut in_switch : Bool // for break validation (break works in switch too)
  labels : Array[String] // for labeled break/continue validation
  src : String
  allow_jsx : Bool
  mut class_id : Int // for private field brand generation
  mut current_class_brand : String? // brand ID of current class being parsed
  mut last_runtime_class_decl : @ast.TsClassDecl?
  local_type_param_bounds : Array[(String, @ast.TsType)]
  // Decorator expressions parsed at the statement level that should be
  // attached to the next class declaration. The class parsers drain
  // this list when they begin and clear it on exit.
  pending_decorators : Array[@ast.TsExpr]
  // Per-parameter modifier flags collected by the most recent
  // `parse_params` call: index `i` is `true` when that parameter
  // had a `public` / `private` / `protected` / `readonly` /
  // `override` modifier — i.e. a "parameter property" in a
  // constructor. Class-body parsing reads this back after parsing
  // a constructor signature so it can synthesize the
  // `this.X = X` assignment that TS implicitly does.
  mut last_param_property_flags : Array[Bool]
} derive(Debug)

///|
// / create
pub fn Parser::new(tokens : Array[Token]) -> Parser {
  Parser::new_with_strict(tokens, false)
}

///|
pub fn Parser::new_with_strict(
  tokens : Array[Token],
  in_strict : Bool,
) -> Parser {
  Parser::new_with_strict_and_jsx(tokens, in_strict, true)
}

///|
pub fn Parser::new_with_strict_and_jsx(
  tokens : Array[Token],
  in_strict : Bool,
  allow_jsx : Bool,
) -> Parser {
  {
    tokens,
    pos: 0,
    pending_gt: 0,
    pending_gt_pos: 0,
    in_generator: false,
    in_async: false,
    temp_index: 0,
    unique_symbol_index: 0,
    in_strict,
    in_function: false,
    in_iteration: false,
    in_switch: false,
    labels: [],
    src: "",
    allow_jsx,
    class_id: 0,
    current_class_brand: None,
    last_runtime_class_decl: None,
    local_type_param_bounds: [],
    pending_decorators: [],
    last_param_property_flags: [],
  }
}

///|
// / create
pub fn Parser::from_source(src : String) -> Parser {
  Parser::from_source_with_jsx(src, true)
}

///|
pub fn Parser::from_source_with_jsx(src : String, allow_jsx : Bool) -> Parser {
  let lexer = Lexer::new(src)
  let tokens = lexer.tokenize()
  let trimmed = src.trim_start()
  let in_strict = trimmed.has_prefix("\"use strict\";") ||
    trimmed.has_prefix("'use strict';")
  {
    tokens,
    pos: 0,
    pending_gt: 0,
    pending_gt_pos: 0,
    in_generator: false,
    in_async: false,
    temp_index: 0,
    unique_symbol_index: 0,
    in_strict,
    in_function: false,
    in_iteration: false,
    in_switch: false,
    labels: [],
    src,
    allow_jsx,
    class_id: 0,
    current_class_brand: None,
    last_runtime_class_decl: None,
    local_type_param_bounds: [],
    pending_decorators: [],
    last_param_property_flags: [],
  }
}

///|
// / currentget
fn Parser::peek(self : Parser) -> Token {
  if self.pending_gt > 0 {
    { kind: Gt, pos: self.pending_gt_pos, has_newline_before: false, pure_marked: false }
  } else if self.pos >= self.tokens.length() {
    { kind: Eof, pos: 0, has_newline_before: false, pure_marked: false }
  } else {
    self.tokens[self.pos]
  }
}

///|
// /
fn Parser::advance(self : Parser) -> Token {
  if self.pending_gt > 0 {
    self.pending_gt -= 1
    return { kind: Gt, pos: self.pending_gt_pos, has_newline_before: false, pure_marked: false }
  }
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
  if offset < self.pending_gt {
    return { kind: Gt, pos: self.pending_gt_pos, has_newline_before: false, pure_marked: false }
  }
  let idx = self.pos + offset - self.pending_gt
  if idx >= self.tokens.length() {
    { kind: Eof, pos: 0, has_newline_before: false, pure_marked: false }
  } else {
    self.tokens[idx]
  }
}

///|
// / functioncheck (currentposition `(` )
fn Parser::is_arrow_function(self : Parser) -> Bool {
  let temp = { ..self, pos: self.pos + 1 }
  let params_ok = try {
    let _ = temp.parse_params()
    temp.check(RParen)
  } catch {
    _ => false
  }
  if !params_ok {
    return false
  }
  let _ = temp.advance()
  if temp.check(Arrow) {
    return true
  }
  if !temp.check(Colon) {
    return false
  }
  let _ = temp.advance()
  temp.skip_type_until_arrow()
  temp.check(Arrow)
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
    | Declare
    | Interface
    | Type
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
    | Delete
    | Typeof
    | Regex(_, _) => return
    _ => ()
  }
  // ASI fallback: a line terminator separates the current statement from
  // the next token. This catches cases like `if (...) return -1 \n else
  // ...` where `else` isn't a statement-starting token in the table above
  // but is still a valid continuation of the surrounding construct.
  if self.has_line_terminator_before() {
    return
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
  let limit = if end_pos <= self.src.length() {
    end_pos
  } else {
    self.src.length()
  }
  while i < limit {
    let ch = self.src[i]
    // JavaScript line terminators: LF, CR, LS (U+2028), PS (U+2029)
    if ch == '\n' || ch == '\r' || ch == '\u2028' || ch == '\u2029' {
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
  // O(1) replacement: the next token's `has_newline_before` flag covers
  // exactly the whitespace between the current and next tokens.
  self.tokens[next].has_newline_before
}

///|
/// Check if there's a line terminator between the previous token and current token
fn Parser::has_line_terminator_before(self : Parser) -> Bool {
  if self.pos == 0 || self.pos >= self.tokens.length() {
    return false
  }
  // The lexer already records whether any whitespace before this token
  // contained a line terminator (LF / CR / LS / PS). Use that flag instead
  // of rescanning the source buffer — this function is on the hot path
  // for every `[` (array vs index access), every contextual `as` /
  // `satisfies`, and every ASI-relevant statement boundary.
  self.tokens[self.pos].has_newline_before
}

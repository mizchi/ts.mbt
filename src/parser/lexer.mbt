// TypeScript

///|
// /
pub enum TokenKind {
  // literal
  Number(Double)
  Int(Int)
  LegacyOctal(Int) // legacy octal (e.g., 01, 07) - forbidden in strict mode
  BigInt(String)
  Bool(Bool)
  Str(String) // stringliteral
  Regex(String, String) // /pattern/flags
  // Template literal: (cooked_strings, raw_strings, expr_sources)
  Template(Array[String], Array[String], Array[String])
  Ident(String)
  PrivateIdent(String)
  Function
  Class
  Extends
  Var
  Let
  Const
  Return
  If
  Else
  Switch
  Case
  Default
  With
  Debugger
  Import
  Export
  From
  As
  While
  Do
  For
  Break
  Continue
  Try
  Catch
  Finally
  Throw
  Yield
  Typeof
  Delete

  // type
  NumberType // number
  BooleanType // boolean
  VoidType // void
  IntType // int ()
  StringType // string

  // operator
  Plus // +
  Minus // -
  Star // *
  StarStar // **
  Slash // /
  Percent // %
  Caret // ^
  Amp // &
  Pipe // |
  EqEq // ==
  EqEqEq // ===
  BangEq // !=
  BangEqEq // !==
  Instanceof // instanceof
  Lt // <
  LtLt // <<
  Le // <=
  Gt // >
  GtGt // >>
  GtGtGt // >>>
  Ge // >=
  AmpAmp // &&
  PipePipe // ||
  AmpAmpEq // &&=
  PipePipeEq // ||=
  Bang // !
  Tilde // ~
  Eq // =
  Question // ?
  QuestionQuestion // ??
  QuestionQuestionEq // ??=
  PlusPlus // ++
  MinusMinus // --
  PlusEq // +=
  MinusEq // -=
  StarEq // *=
  StarStarEq // **=
  SlashEq // /=
  PercentEq // %=
  AmpEq // &=
  PipeEq // |=
  CaretEq // ^=
  LtLtEq // <<=
  GtGtEq // >>=
  GtGtGtEq // >>>=
  Arrow // =>
  Ellipsis // ...
  LParen // (
  RParen // )
  LBrace // {
  RBrace // }
  LBracket // [
  RBracket // ]
  Comma // ,
  Colon // :
  Semicolon // ;
  Dot // .

  // (add)
  New // new
  Interface // interface
  Type // type (type alias)
  Of // of (for...of)
  In // in (for...in)
  Declare // declare (externalimport)
  Null // null
  Eof
} derive(Eq, Show)

///|
// /
pub struct Token {
  kind : TokenKind
  pos : Int // position
  has_newline_before : Bool // true if there was a newline before this token
} derive(Show)

///|
fn write_codepoint(buf : StringBuilder, code : Int) -> Unit {
  if code < 0 || code > 0x10ffff {
    buf.write_char('\ufffd')
  } else {
    buf.write_char(code.unsafe_to_char())
  }
}

///|
// /
pub struct Lexer {
  src : String
  mut pos : Int
  mut allow_regex : Bool
  mut pending : Array[Token]
  mut pending_index : Int
  mut newline_before_next : Bool // Set when whitespace skipping encounters a newline
} derive(Show)

///|
// / 161( advance )
fn Lexer::read_hex_digit(self : Lexer) -> Int? {
  match self.peek() {
    Some(c) =>
      if c >= '0' && c <= '9' {
        let _ = self.advance()
        Some(c.to_int() - '0'.to_int())
      } else if c >= 'a' && c <= 'f' {
        let _ = self.advance()
        Some(10 + (c.to_int() - 'a'.to_int()))
      } else if c >= 'A' && c <= 'F' {
        let _ = self.advance()
        Some(10 + (c.to_int() - 'A'.to_int()))
      } else {
        None
      }
    None => None
  }
}

///|
// / create
pub fn Lexer::new(src : String) -> Lexer {
  {
    src,
    pos: 0,
    allow_regex: true,
    pending: [],
    pending_index: 0,
    newline_before_next: false,
  }
}

///|
// / currentstatementget
fn Lexer::peek(self : Lexer) -> Char? {
  if self.pos >= self.src.length() {
    None
  } else {
    Some(self.src[self.pos].to_int().unsafe_to_char())
  }
}

///|
// / statement
fn Lexer::peek_next(self : Lexer) -> Char? {
  if self.pos + 1 >= self.src.length() {
    None
  } else {
    Some(self.src[self.pos + 1].to_int().unsafe_to_char())
  }
}

///|
// / positionget
fn Lexer::peek_byte(self : Lexer, offset : Int) -> Int? {
  let idx = self.pos + offset
  if idx >= self.src.length() || idx < 0 {
    None
  } else {
    Some(self.src[idx].to_int())
  }
}

///|
// / statement
fn Lexer::advance(self : Lexer) -> Char? {
  let c = self.peek()
  if c is Some(_) {
    self.pos += 1
  }
  c
}

///|
// /
fn Lexer::skip_whitespace(self : Lexer) -> Unit {
  self.newline_before_next = false // Reset at start of whitespace skipping
  while true {
    match self.peek_byte(0) {
      Some(0x0B) | Some(0x0C) => {
        self.pos += 1
        continue
      }
      Some(0xA0) => {
        self.pos += 1
        continue
      }
      Some(0x2028) | Some(0x2029) => {
        // Line Separator and Paragraph Separator are line terminators
        self.newline_before_next = true
        self.pos += 1
        continue
      }
      Some(0xC2) if self.peek_byte(1) == Some(0xA0) => {
        self.pos += 2
        continue
      }
      Some(0xE2) if self.peek_byte(1) == Some(0x80) =>
        match self.peek_byte(2) {
          Some(0xA8) | Some(0xA9) => {
            // LS (U+2028) and PS (U+2029) in UTF-8
            self.newline_before_next = true
            self.pos += 3
            continue
          }
          _ => ()
        }
      Some(0xEF) if self.peek_byte(1) == Some(0xBB) &&
        self.peek_byte(2) == Some(0xBF) => {
        self.pos += 3
        continue
      }
      _ => ()
    }
    match self.peek() {
      Some('#') if self.peek_next() == Some('!') => {
        let _ = self.advance()
        let _ = self.advance()
        while true {
          match self.peek() {
            // Line terminators: LF, CR, LS, PS
            Some('\n') | Some('\r') | Some('\u2028') | Some('\u2029') | None =>
              break
            _ => {
              let _ = self.advance()
            }
          }
        }
        // Hashbang is followed by a line terminator
        self.newline_before_next = true
      }
      Some(' ') | Some('\t') => {
        let _ = self.advance()
      }
      Some('\n') | Some('\r') => {
        self.newline_before_next = true
        let _ = self.advance()
      }
      Some('/') =>
        match self.peek_next() {
          Some('/') => {
            let _ = self.advance()
            let _ = self.advance()
            while true {
              match self.peek() {
                // Line terminators: LF, CR, LS, PS
                Some('\n')
                | Some('\r')
                | Some('\u2028')
                | Some('\u2029')
                | None => break
                _ => {
                  let _ = self.advance()
                }
              }
            }
          }
          Some('*') => {
            // block
            let _ = self.advance()
            let _ = self.advance()
            while true {
              match self.peek() {
                None => break
                Some('*') =>
                  match self.peek_next() {
                    Some('/') => {
                      let _ = self.advance()
                      let _ = self.advance()
                      break
                    }
                    _ => {
                      let _ = self.advance()
                    }
                  }
                _ => {
                  let _ = self.advance()
                }
              }
            }
          }
          _ => break
        }
      _ => break
    }
  }
}

///|
// / literal
fn Lexer::scan_number(self : Lexer) -> TokenKind {
  let start = self.pos
  // Radix-prefixed integers: 0x / 0o / 0b
  if self.peek() == Some('0') {
    match self.peek_next() {
      Some('x') | Some('X') => {
        let _ = self.advance()
        let _ = self.advance()
        let mut value = 0
        let mut has_digit = false
        while true {
          match self.peek() {
            Some('_') => {
              let _ = self.advance()
            }
            Some(c) =>
              match c {
                '0' => {
                  let _ = self.advance()
                  value = value * 16 + 0
                  has_digit = true
                }
                '1' => {
                  let _ = self.advance()
                  value = value * 16 + 1
                  has_digit = true
                }
                '2' => {
                  let _ = self.advance()
                  value = value * 16 + 2
                  has_digit = true
                }
                '3' => {
                  let _ = self.advance()
                  value = value * 16 + 3
                  has_digit = true
                }
                '4' => {
                  let _ = self.advance()
                  value = value * 16 + 4
                  has_digit = true
                }
                '5' => {
                  let _ = self.advance()
                  value = value * 16 + 5
                  has_digit = true
                }
                '6' => {
                  let _ = self.advance()
                  value = value * 16 + 6
                  has_digit = true
                }
                '7' => {
                  let _ = self.advance()
                  value = value * 16 + 7
                  has_digit = true
                }
                '8' => {
                  let _ = self.advance()
                  value = value * 16 + 8
                  has_digit = true
                }
                '9' => {
                  let _ = self.advance()
                  value = value * 16 + 9
                  has_digit = true
                }
                'a' | 'A' => {
                  let _ = self.advance()
                  value = value * 16 + 10
                  has_digit = true
                }
                'b' | 'B' => {
                  let _ = self.advance()
                  value = value * 16 + 11
                  has_digit = true
                }
                'c' | 'C' => {
                  let _ = self.advance()
                  value = value * 16 + 12
                  has_digit = true
                }
                'd' | 'D' => {
                  let _ = self.advance()
                  value = value * 16 + 13
                  has_digit = true
                }
                'e' | 'E' => {
                  let _ = self.advance()
                  value = value * 16 + 14
                  has_digit = true
                }
                'f' | 'F' => {
                  let _ = self.advance()
                  value = value * 16 + 15
                  has_digit = true
                }
                _ => break
              }
            None => break
          }
        }
        if not(has_digit) {
          value = 0
        }
        let mut is_bigint = false
        if self.peek() == Some('n') {
          is_bigint = true
          let _ = self.advance()
        }
        if is_bigint {
          return BigInt(value.to_string())
        } else {
          return Int(value)
        }
      }
      Some('b') | Some('B') => {
        let _ = self.advance()
        let _ = self.advance()
        let mut value = 0
        let mut has_digit = false
        while true {
          match self.peek() {
            Some('_') => {
              let _ = self.advance()
            }
            Some('0') => {
              let _ = self.advance()
              value = value * 2
              has_digit = true
            }
            Some('1') => {
              let _ = self.advance()
              value = value * 2 + 1
              has_digit = true
            }
            _ => break
          }
        }
        if not(has_digit) {
          value = 0
        }
        let mut is_bigint = false
        if self.peek() == Some('n') {
          is_bigint = true
          let _ = self.advance()
        }
        if is_bigint {
          return BigInt(value.to_string())
        } else {
          return Int(value)
        }
      }
      Some('o') | Some('O') => {
        let _ = self.advance()
        let _ = self.advance()
        let mut value = 0
        let mut has_digit = false
        while true {
          match self.peek() {
            Some('_') => {
              let _ = self.advance()
            }
            Some('0') => {
              let _ = self.advance()
              value = value * 8 + 0
              has_digit = true
            }
            Some('1') => {
              let _ = self.advance()
              value = value * 8 + 1
              has_digit = true
            }
            Some('2') => {
              let _ = self.advance()
              value = value * 8 + 2
              has_digit = true
            }
            Some('3') => {
              let _ = self.advance()
              value = value * 8 + 3
              has_digit = true
            }
            Some('4') => {
              let _ = self.advance()
              value = value * 8 + 4
              has_digit = true
            }
            Some('5') => {
              let _ = self.advance()
              value = value * 8 + 5
              has_digit = true
            }
            Some('6') => {
              let _ = self.advance()
              value = value * 8 + 6
              has_digit = true
            }
            Some('7') => {
              let _ = self.advance()
              value = value * 8 + 7
              has_digit = true
            }
            _ => break
          }
        }
        if not(has_digit) {
          value = 0
        }
        let mut is_bigint = false
        if self.peek() == Some('n') {
          is_bigint = true
          let _ = self.advance()
        }
        if is_bigint {
          return BigInt(value.to_string())
        } else {
          return Int(value)
        }
      }
      Some(c) if c >= '0' && c <= '9' => {
        // Could be legacy octal (01-07) or non-octal decimal (08, 09, 018, etc.)
        // We need to scan all digits to determine which
        let _ = self.advance() // skip '0'
        let _ = self.advance() // skip first digit (c)
        let mut value = c.to_int() - '0'.to_int()
        let mut is_pure_octal = c >= '0' && c <= '7'
        while true {
          match self.peek() {
            Some(d) if d >= '0' && d <= '9' => {
              let _ = self.advance()
              if d >= '8' {
                is_pure_octal = false
              }
              value = value * 10 + (d.to_int() - '0'.to_int())
            }
            _ => break
          }
        }
        if is_pure_octal {
          // Recalculate as octal
          let mut octal_value = 0
          let mut mult = 1
          let mut temp = value
          while temp > 0 {
            let digit = temp % 10
            octal_value = octal_value + digit * mult
            mult = mult * 8
            temp = temp / 10
          }
          return LegacyOctal(octal_value)
        } else {
          return Int(value)
        }
      }
      _ => ()
    }
  }
  let mut has_dot = false
  let mut has_exp = false
  let mut is_bigint = false
  let mut has_sep = false
  while true {
    match self.peek() {
      Some(c) =>
        if c >= '0' && c <= '9' {
          let _ = self.advance()
        } else if c == '_' {
          has_sep = true
          let _ = self.advance()
        } else if c == '.' && not(has_dot) && not(has_exp) {
          has_dot = true
          let _ = self.advance()
        } else if (c == 'e' || c == 'E') && not(has_exp) {
          has_exp = true
          let _ = self.advance()
          match self.peek() {
            Some('+') | Some('-') => {
              let _ = self.advance()
            }
            _ => ()
          }
        } else {
          break
        }
      None => break
    }
  }
  if self.peek() == Some('n') {
    is_bigint = true
    let _ = self.advance()
  }
  let raw = if is_bigint {
    let end = if self.pos > start { self.pos - 1 } else { self.pos }
    self.src[start:end].to_string() catch {
      _ => ""
    }
  } else {
    self.src[start:self.pos].to_string() catch {
      _ => ""
    }
  }
  let s = if has_sep {
    let cleaned = StringBuilder::new()
    for ch in raw {
      if ch == '_' {
        continue
      }
      cleaned.write_char(ch)
    }
    cleaned.to_string()
  } else {
    raw
  }
  if is_bigint {
    BigInt(s)
  } else if has_dot || has_exp {
    // Double
    try {
      let d = @strconv.parse_double(s)
      Number(d)
    } catch {
      // Overflow to Infinity for very large numbers
      _ => Number(1.0 / 0.0) // Infinity
    }
  } else {
    // Int - but use Double for large numbers to avoid overflow
    // JavaScript numbers are IEEE 754 doubles which can represent integers up to 2^53
    // MoonBit Int is 32-bit signed, so max is 2147483647
    try {
      let d = @strconv.parse_double(s)
      // Check if the value fits in 32-bit signed integer
      if d >= -2147483648.0 && d <= 2147483647.0 && d == d.trunc() {
        Int(d.to_int())
      } else {
        Number(d)
      }
    } catch {
      // Overflow to Infinity for very large integers
      _ => Number(1.0 / 0.0) // Infinity
    }
  }
}

///|
// / /
fn Lexer::scan_ident(self : Lexer) -> TokenKind {
  let buf = StringBuilder::new()
  while true {
    match self.peek() {
      Some(c) =>
        if (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') ||
          c == '_' ||
          c == '$' {
          let _ = self.advance()
          buf.write_char(c)
        } else if c == '\\' {
          let _ = self.advance()
          match self.peek() {
            Some('u') => {
              let _ = self.advance()
              let mut code = 0
              let mut ok = true
              let mut digits = 0
              if self.peek() == Some('{') {
                let _ = self.advance()
                while true {
                  match self.peek() {
                    Some('}') => {
                      let _ = self.advance()
                      break
                    }
                    Some(_) =>
                      match self.read_hex_digit() {
                        Some(d) => {
                          code = code * 16 + d
                          digits = digits + 1
                        }
                        None => {
                          ok = false
                          break
                        }
                      }
                    None => {
                      ok = false
                      break
                    }
                  }
                }
              } else {
                for _ in 0..<4 {
                  match self.read_hex_digit() {
                    Some(d) => {
                      code = code * 16 + d
                      digits = digits + 1
                    }
                    None => {
                      ok = false
                      break
                    }
                  }
                }
              }
              if ok && digits > 0 {
                write_codepoint(buf, code)
              } else {
                buf.write_char('u')
              }
            }
            _ => break
          }
        } else {
          break
        }
      None => break
    }
  }
  let s = buf.to_string()
  if s == "function" {
    Function
  } else if s == "class" {
    Class
  } else if s == "extends" {
    Extends
  } else if s == "var" {
    Var
  } else if s == "let" {
    Let
  } else if s == "const" {
    Const
  } else if s == "return" {
    Return
  } else if s == "if" {
    If
  } else if s == "else" {
    Else
  } else if s == "switch" {
    Switch
  } else if s == "case" {
    Case
  } else if s == "default" {
    Default
  } else if s == "with" {
    With
  } else if s == "debugger" {
    Debugger
  } else if s == "import" {
    Import
  } else if s == "export" {
    Export
  } else if s == "from" {
    From
  } else if s == "as" {
    As
  } else if s == "while" {
    While
  } else if s == "do" {
    Do
  } else if s == "for" {
    For
  } else if s == "break" {
    Break
  } else if s == "continue" {
    Continue
  } else if s == "try" {
    Try
  } else if s == "catch" {
    Catch
  } else if s == "finally" {
    Finally
  } else if s == "throw" {
    Throw
  } else if s == "yield" {
    Yield
  } else if s == "true" {
    Bool(true)
  } else if s == "false" {
    Bool(false)
  } else if s == "typeof" {
    Typeof
  } else if s == "delete" {
    Delete
  } else if s == "null" {
    Null
  } else if s == "number" {
    NumberType
  } else if s == "boolean" {
    BooleanType
  } else if s == "void" {
    VoidType
  } else if s == "int" {
    IntType
  } else if s == "string" {
    StringType
  } else if s == "new" {
    New
  } else if s == "interface" {
    Interface
  } else if s == "type" {
    Type
  } else if s == "of" {
    Of
  } else if s == "in" {
    In
  } else if s == "declare" {
    Declare
  } else if s == "instanceof" {
    Instanceof
  } else {
    Ident(s)
  }
}

///|
fn Lexer::scan_private_ident(self : Lexer) -> TokenKind {
  let buf = StringBuilder::new()
  while true {
    match self.peek() {
      Some(c) =>
        if (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') ||
          c == '_' ||
          c == '$' {
          let _ = self.advance()
          buf.write_char(c)
        } else if c == '\\' {
          let _ = self.advance()
          match self.peek() {
            Some('u') => {
              let _ = self.advance()
              let mut code = 0
              let mut ok = true
              let mut digits = 0
              if self.peek() == Some('{') {
                let _ = self.advance()
                while true {
                  match self.peek() {
                    Some('}') => {
                      let _ = self.advance()
                      break
                    }
                    Some(_) =>
                      match self.read_hex_digit() {
                        Some(d) => {
                          code = code * 16 + d
                          digits = digits + 1
                        }
                        None => {
                          ok = false
                          break
                        }
                      }
                    None => {
                      ok = false
                      break
                    }
                  }
                }
              } else {
                for _ in 0..<4 {
                  match self.read_hex_digit() {
                    Some(d) => {
                      code = code * 16 + d
                      digits = digits + 1
                    }
                    None => {
                      ok = false
                      break
                    }
                  }
                }
              }
              if ok && digits > 0 {
                write_codepoint(buf, code)
              } else {
                buf.write_char('u')
              }
            }
            _ => break
          }
        } else {
          break
        }
      None => break
    }
  }
  let s = buf.to_string()
  PrivateIdent(s)
}

///|
// / stringliteral
fn Lexer::scan_string(self : Lexer, quote : Char) -> TokenKind {
  let buf = StringBuilder::new()
  while true {
    match self.peek() {
      None => break // (errorsimplehandle)
      Some(c) =>
        if c == quote {
          let _ = self.advance()
          break
        } else if c == '\\' {
          let _ = self.advance()
          match self.peek() {
            Some('n') => {
              let _ = self.advance()
              buf.write_char('\n')
            }
            Some('t') => {
              let _ = self.advance()
              buf.write_char('\t')
            }
            Some('r') => {
              let _ = self.advance()
              buf.write_char('\r')
            }
            Some('b') => {
              let _ = self.advance()
              buf.write_char('\u0008'.to_int().unsafe_to_char())
            }
            Some('f') => {
              let _ = self.advance()
              buf.write_char('\u000c'.to_int().unsafe_to_char())
            }
            Some('v') => {
              let _ = self.advance()
              buf.write_char('\u000b'.to_int().unsafe_to_char())
            }
            Some(d) if d >= '0' && d <= '7' => {
              // Legacy octal escape sequence
              let _ = self.advance()
              let first_digit = d.to_int() - '0'.to_int()
              // Check for more octal digits
              match self.peek() {
                Some(d2) if d2 >= '0' && d2 <= '7' => {
                  // Could be 2 or 3 digit octal
                  let second_digit = d2.to_int() - '0'.to_int()
                  if first_digit <= 3 {
                    // ZeroToThree: can be 2 or 3 digit
                    let _ = self.advance()
                    match self.peek() {
                      Some(d3) if d3 >= '0' && d3 <= '7' => {
                        // 3-digit octal: \000 - \377
                        let _ = self.advance()
                        let third_digit = d3.to_int() - '0'.to_int()
                        let code = first_digit * 64 +
                          second_digit * 8 +
                          third_digit
                        buf.write_char(code.unsafe_to_char())
                      }
                      _ => {
                        // 2-digit octal: \00 - \37
                        let code = first_digit * 8 + second_digit
                        buf.write_char(code.unsafe_to_char())
                      }
                    }
                  } else {
                    // FourToSeven: exactly 2 digits
                    let _ = self.advance()
                    let code = first_digit * 8 + second_digit
                    buf.write_char(code.unsafe_to_char())
                  }
                }
                _ =>
                  // Single digit octal: \0 - \7
                  buf.write_char(first_digit.unsafe_to_char())
              }
            }
            Some('x') => {
              let _ = self.advance()
              let mut code = 0
              let mut ok = true
              for _ in 0..<2 {
                match self.read_hex_digit() {
                  Some(d) => code = code * 16 + d
                  None => {
                    ok = false
                    break
                  }
                }
              }
              if ok {
                write_codepoint(buf, code)
              } else {
                buf.write_char('x')
              }
            }
            Some('u') => {
              let _ = self.advance()
              let mut code = 0
              let mut ok = true
              let mut digits = 0
              if self.peek() == Some('{') {
                let _ = self.advance()
                while true {
                  match self.peek() {
                    Some('}') => {
                      let _ = self.advance()
                      break
                    }
                    Some(_) =>
                      match self.read_hex_digit() {
                        Some(d) => {
                          code = code * 16 + d
                          digits = digits + 1
                        }
                        None => {
                          ok = false
                          break
                        }
                      }
                    None => {
                      ok = false
                      break
                    }
                  }
                }
              } else {
                for _ in 0..<4 {
                  match self.read_hex_digit() {
                    Some(d) => {
                      code = code * 16 + d
                      digits = digits + 1
                    }
                    None => {
                      ok = false
                      break
                    }
                  }
                }
              }
              if ok && digits > 0 {
                write_codepoint(buf, code)
              } else {
                buf.write_char('u')
              }
            }
            Some('\\') => {
              let _ = self.advance()
              buf.write_char('\\')
            }
            Some('\'') => {
              let _ = self.advance()
              buf.write_char('\'')
            }
            Some('"') => {
              let _ = self.advance()
              buf.write_char('"')
            }
            // Line continuation: backslash followed by line terminator
            Some('\n') => {
              // \<LF> - skip the newline (empty code unit sequence)
              let _ = self.advance()
            }
            Some('\r') => {
              // \<CR> or \<CR><LF> - skip both (empty code unit sequence)
              let _ = self.advance()
              if self.peek() == Some('\n') {
                let _ = self.advance()
              }
            }
            Some('\u2028') => {
              // \<LS> (U+2028 LINE SEPARATOR) - skip
              let _ = self.advance()
            }
            Some('\u2029') => {
              // \<PS> (U+2029 PARAGRAPH SEPARATOR) - skip
              let _ = self.advance()
            }
            Some(other) => {
              let _ = self.advance()
              buf.write_char(other)
            }
            None => break
          }
        } else {
          let _ = self.advance()
          buf.write_char(c)
        }
    }
  }
  Str(buf.to_string())
}

///|
fn Lexer::scan_template_expr_source(self : Lexer) -> String {
  let start = self.pos
  let mut depth = 1
  while depth > 0 {
    match self.peek() {
      None => break
      Some(c) => {
        let _ = self.advance()
        match c {
          '{' => depth += 1
          '}' => depth -= 1
          '\'' | '"' => self.skip_string_body(c)
          '`' => {
            let _ = self.scan_template()
          }
          _ => ()
        }
      }
    }
  }
  let end = if self.pos > 0 { self.pos - 1 } else { 0 }
  self.src[start:end].to_string() catch {
    _ => ""
  }
}

///|
// Returns (cooked_parts, raw_parts, expr_sources)
fn Lexer::scan_template_parts_with_raw(
  self : Lexer,
) -> (Array[String], Array[String], Array[String]) {
  let cooked_parts : Array[String] = []
  let raw_parts : Array[String] = []
  let exprs : Array[String] = []
  let mut cooked_buf = StringBuilder::new()
  let mut raw_buf = StringBuilder::new()
  while true {
    match self.peek() {
      None => break
      Some(c) =>
        if c == '`' {
          let _ = self.advance()
          break
        } else if c == '$' && self.peek_next() == Some('{') {
          let _ = self.advance()
          let _ = self.advance()
          cooked_parts.push(cooked_buf.to_string())
          raw_parts.push(raw_buf.to_string())
          cooked_buf = StringBuilder::new()
          raw_buf = StringBuilder::new()
          let expr_src = self.scan_template_expr_source()
          exprs.push(expr_src)
        } else if c == '\\' {
          raw_buf.write_char('\\')
          let _ = self.advance()
          match self.peek() {
            Some('n') => {
              let _ = self.advance()
              cooked_buf.write_char('\n')
              raw_buf.write_char('n')
            }
            Some('t') => {
              let _ = self.advance()
              cooked_buf.write_char('\t')
              raw_buf.write_char('t')
            }
            Some('r') => {
              let _ = self.advance()
              cooked_buf.write_char('\r')
              raw_buf.write_char('r')
            }
            Some('b') => {
              let _ = self.advance()
              cooked_buf.write_char('\u0008'.to_int().unsafe_to_char())
              raw_buf.write_char('b')
            }
            Some('f') => {
              let _ = self.advance()
              cooked_buf.write_char('\u000c'.to_int().unsafe_to_char())
              raw_buf.write_char('f')
            }
            Some('v') => {
              let _ = self.advance()
              cooked_buf.write_char('\u000b'.to_int().unsafe_to_char())
              raw_buf.write_char('v')
            }
            Some(d) if d >= '0' && d <= '7' => {
              // Legacy octal escape sequence
              let _ = self.advance()
              raw_buf.write_char(d)
              let first_digit = d.to_int() - '0'.to_int()
              // Check for more octal digits
              match self.peek() {
                Some(d2) if d2 >= '0' && d2 <= '7' => {
                  // Could be 2 or 3 digit octal
                  let second_digit = d2.to_int() - '0'.to_int()
                  if first_digit <= 3 {
                    // ZeroToThree: can be 2 or 3 digit
                    let _ = self.advance()
                    raw_buf.write_char(d2)
                    match self.peek() {
                      Some(d3) if d3 >= '0' && d3 <= '7' => {
                        // 3-digit octal: \000 - \377
                        let _ = self.advance()
                        raw_buf.write_char(d3)
                        let third_digit = d3.to_int() - '0'.to_int()
                        let code = first_digit * 64 +
                          second_digit * 8 +
                          third_digit
                        cooked_buf.write_char(code.unsafe_to_char())
                      }
                      _ => {
                        // 2-digit octal: \00 - \37
                        let code = first_digit * 8 + second_digit
                        cooked_buf.write_char(code.unsafe_to_char())
                      }
                    }
                  } else {
                    // FourToSeven: exactly 2 digits
                    let _ = self.advance()
                    raw_buf.write_char(d2)
                    let code = first_digit * 8 + second_digit
                    cooked_buf.write_char(code.unsafe_to_char())
                  }
                }
                _ =>
                  // Single digit octal: \0 - \7
                  cooked_buf.write_char(first_digit.unsafe_to_char())
              }
            }
            Some('x') => {
              let _ = self.advance()
              raw_buf.write_char('x')
              let mut code = 0
              let mut ok = true
              for _ in 0..<2 {
                match self.read_hex_digit() {
                  Some(d) => {
                    code = code * 16 + d
                    // Add hex char to raw
                    let hex_char = if d < 10 {
                      (d + '0'.to_int()).unsafe_to_char()
                    } else {
                      (d - 10 + 'a'.to_int()).unsafe_to_char()
                    }
                    raw_buf.write_char(hex_char)
                  }
                  None => {
                    ok = false
                    break
                  }
                }
              }
              if ok {
                write_codepoint(cooked_buf, code)
              } else {
                cooked_buf.write_char('x')
              }
            }
            Some('u') => {
              let _ = self.advance()
              raw_buf.write_char('u')
              let mut code = 0
              let mut ok = true
              let mut digits = 0
              if self.peek() == Some('{') {
                let _ = self.advance()
                raw_buf.write_char('{')
                while true {
                  match self.peek() {
                    Some('}') => {
                      let _ = self.advance()
                      raw_buf.write_char('}')
                      break
                    }
                    Some(_) =>
                      match self.read_hex_digit() {
                        Some(d) => {
                          code = code * 16 + d
                          digits = digits + 1
                          let hex_char = if d < 10 {
                            (d + '0'.to_int()).unsafe_to_char()
                          } else {
                            (d - 10 + 'a'.to_int()).unsafe_to_char()
                          }
                          raw_buf.write_char(hex_char)
                        }
                        None => {
                          ok = false
                          break
                        }
                      }
                    None => {
                      ok = false
                      break
                    }
                  }
                }
              } else {
                for _ in 0..<4 {
                  match self.read_hex_digit() {
                    Some(d) => {
                      code = code * 16 + d
                      digits = digits + 1
                      let hex_char = if d < 10 {
                        (d + '0'.to_int()).unsafe_to_char()
                      } else {
                        (d - 10 + 'a'.to_int()).unsafe_to_char()
                      }
                      raw_buf.write_char(hex_char)
                    }
                    None => {
                      ok = false
                      break
                    }
                  }
                }
              }
              if ok && digits > 0 {
                write_codepoint(cooked_buf, code)
              } else {
                cooked_buf.write_char('u')
              }
            }
            Some('\\') => {
              let _ = self.advance()
              cooked_buf.write_char('\\')
              raw_buf.write_char('\\')
            }
            Some('`') => {
              let _ = self.advance()
              cooked_buf.write_char('`')
              raw_buf.write_char('`')
            }
            Some(other) => {
              let _ = self.advance()
              cooked_buf.write_char(other)
              raw_buf.write_char(other)
            }
            None => break
          }
        } else {
          let _ = self.advance()
          cooked_buf.write_char(c)
          raw_buf.write_char(c)
        }
    }
  }
  cooked_parts.push(cooked_buf.to_string())
  raw_parts.push(raw_buf.to_string())
  (cooked_parts, raw_parts, exprs)
}

///|
fn Lexer::enqueue_template_tokens(self : Lexer, pos : Int) -> Unit {
  let has_newline = self.newline_before_next
  let (cooked_parts, raw_parts, exprs) = self.scan_template_parts_with_raw()
  // Create a single Template token containing all parts and expression sources
  let token = {
    kind: Template(cooked_parts, raw_parts, exprs),
    pos,
    has_newline_before: has_newline,
  }
  if self.pending_index >= self.pending.length() {
    self.pending = [token]
    self.pending_index = 0
  } else {
    self.pending.push(token)
  }
}

///|
// / literal (`...`)
fn Lexer::scan_template(self : Lexer) -> TokenKind {
  let buf = StringBuilder::new()
  while true {
    match self.peek() {
      None => break
      Some(c) =>
        if c == '`' {
          let _ = self.advance()
          break
        } else if c == '$' && self.peek_next() == Some('{') {
          let _ = self.advance()
          let _ = self.advance()
          self.skip_template_expr()
        } else if c == '\\' {
          let _ = self.advance()
          match self.peek() {
            Some('n') => {
              let _ = self.advance()
              buf.write_char('\n')
            }
            Some('t') => {
              let _ = self.advance()
              buf.write_char('\t')
            }
            Some('r') => {
              let _ = self.advance()
              buf.write_char('\r')
            }
            Some('b') => {
              let _ = self.advance()
              buf.write_char('\u0008'.to_int().unsafe_to_char())
            }
            Some('f') => {
              let _ = self.advance()
              buf.write_char('\u000c'.to_int().unsafe_to_char())
            }
            Some('v') => {
              let _ = self.advance()
              buf.write_char('\u000b'.to_int().unsafe_to_char())
            }
            Some(d) if d >= '0' && d <= '7' => {
              // Legacy octal escape sequence
              let _ = self.advance()
              let first_digit = d.to_int() - '0'.to_int()
              // Check for more octal digits
              match self.peek() {
                Some(d2) if d2 >= '0' && d2 <= '7' => {
                  // Could be 2 or 3 digit octal
                  let second_digit = d2.to_int() - '0'.to_int()
                  if first_digit <= 3 {
                    // ZeroToThree: can be 2 or 3 digit
                    let _ = self.advance()
                    match self.peek() {
                      Some(d3) if d3 >= '0' && d3 <= '7' => {
                        // 3-digit octal: \000 - \377
                        let _ = self.advance()
                        let third_digit = d3.to_int() - '0'.to_int()
                        let code = first_digit * 64 +
                          second_digit * 8 +
                          third_digit
                        buf.write_char(code.unsafe_to_char())
                      }
                      _ => {
                        // 2-digit octal: \00 - \37
                        let code = first_digit * 8 + second_digit
                        buf.write_char(code.unsafe_to_char())
                      }
                    }
                  } else {
                    // FourToSeven: exactly 2 digits
                    let _ = self.advance()
                    let code = first_digit * 8 + second_digit
                    buf.write_char(code.unsafe_to_char())
                  }
                }
                _ =>
                  // Single digit octal: \0 - \7
                  buf.write_char(first_digit.unsafe_to_char())
              }
            }
            Some('x') => {
              let _ = self.advance()
              let mut code = 0
              let mut ok = true
              for _ in 0..<2 {
                match self.read_hex_digit() {
                  Some(d) => code = code * 16 + d
                  None => {
                    ok = false
                    break
                  }
                }
              }
              if ok {
                write_codepoint(buf, code)
              } else {
                buf.write_char('x')
              }
            }
            Some('u') => {
              let _ = self.advance()
              let mut code = 0
              let mut ok = true
              let mut digits = 0
              if self.peek() == Some('{') {
                let _ = self.advance()
                while true {
                  match self.peek() {
                    Some('}') => {
                      let _ = self.advance()
                      break
                    }
                    Some(_) =>
                      match self.read_hex_digit() {
                        Some(d) => {
                          code = code * 16 + d
                          digits = digits + 1
                        }
                        None => {
                          ok = false
                          break
                        }
                      }
                    None => {
                      ok = false
                      break
                    }
                  }
                }
              } else {
                for _ in 0..<4 {
                  match self.read_hex_digit() {
                    Some(d) => {
                      code = code * 16 + d
                      digits = digits + 1
                    }
                    None => {
                      ok = false
                      break
                    }
                  }
                }
              }
              if ok && digits > 0 {
                write_codepoint(buf, code)
              } else {
                buf.write_char('u')
              }
            }
            Some('\\') => {
              let _ = self.advance()
              buf.write_char('\\')
            }
            Some('`') => {
              let _ = self.advance()
              buf.write_char('`')
            }
            Some(other) => {
              let _ = self.advance()
              buf.write_char(other)
            }
            None => break
          }
        } else {
          let _ = self.advance()
          buf.write_char(c)
        }
    }
  }
  Str(buf.to_string())
}

///|
// / ${ ... }
fn Lexer::skip_template_expr(self : Lexer) -> Unit {
  let mut depth = 1
  while depth > 0 {
    match self.peek() {
      None => break
      Some(c) => {
        let _ = self.advance()
        match c {
          '{' => depth += 1
          '}' => depth -= 1
          '\'' | '"' => self.skip_string_body(c)
          '`' => {
            let _ = self.scan_template()
          }
          _ => ()
        }
      }
    }
  }
}

///|
// / string()
fn Lexer::skip_string_body(self : Lexer, quote : Char) -> Unit {
  while true {
    match self.peek() {
      None => break
      Some(c) => {
        let _ = self.advance()
        if c == quote {
          break
        }
        if c == '\\' {
          let _ = self.advance()
        }
      }
    }
  }
}

///|
// / literal (/pattern/flags)
fn Lexer::scan_regex(self : Lexer) -> TokenKind {
  let buf = StringBuilder::new()
  let mut in_class = false
  let mut escaped = false
  while true {
    match self.peek() {
      None => break
      Some(c) => {
        let _ = self.advance()
        if escaped {
          buf.write_char(c)
          escaped = false
          continue
        }
        if c == '\\' {
          buf.write_char(c)
          escaped = true
          continue
        }
        if c == '[' {
          in_class = true
        } else if c == ']' {
          in_class = false
        }
        if c == '/' && not(in_class) {
          break
        }
        buf.write_char(c)
      }
    }
  }
  let flags = StringBuilder::new()
  while true {
    match self.peek() {
      Some(c) =>
        if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') {
          let _ = self.advance()
          flags.write_char(c)
        } else {
          break
        }
      None => break
    }
  }
  Regex(buf.to_string(), flags.to_string())
}

///|
// / expression
fn token_can_end_expr(kind : TokenKind) -> Bool {
  match kind {
    Number(_)
    | Int(_)
    | BigInt(_)
    | Bool(_)
    | Str(_)
    | Regex(_, _)
    | Ident(_)
    | PrivateIdent(_)
    | Null
    | RParen
    | RBracket
    | RBrace
    | PlusPlus
    | MinusMinus => true
    _ => false
  }
}

///|
// / get
pub fn Lexer::next_token(self : Lexer) -> Token {
  if self.pending_index < self.pending.length() {
    let tok = self.pending[self.pending_index]
    self.pending_index += 1
    if self.pending_index >= self.pending.length() {
      self.pending = []
      self.pending_index = 0
    }
    self.allow_regex = not(token_can_end_expr(tok.kind))
    return tok
  }
  self.skip_whitespace()
  let has_newline = self.newline_before_next
  let pos = self.pos
  match self.advance() {
    None => { kind: Eof, pos, has_newline_before: has_newline }
    Some(c) => {
      let kind : TokenKind = match c {
        '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' => {
          self.pos -= 1
          self.scan_number()
        }
        '#' =>
          match self.peek() {
            Some(c2) =>
              if (c2 >= 'a' && c2 <= 'z') ||
                (c2 >= 'A' && c2 <= 'Z') ||
                c2 == '_' ||
                c2 == '$' ||
                c2 == '\\' {
                self.scan_private_ident()
              } else {
                Ident("#")
              }
            None => Ident("#")
          }
        // /
        'a'
        | 'b'
        | 'c'
        | 'd'
        | 'e'
        | 'f'
        | 'g'
        | 'h'
        | 'i'
        | 'j'
        | 'k'
        | 'l'
        | 'm'
        | 'n'
        | 'o'
        | 'p'
        | 'q'
        | 'r'
        | 's'
        | 't'
        | 'u'
        | 'v'
        | 'w'
        | 'x'
        | 'y'
        | 'z'
        | 'A'
        | 'B'
        | 'C'
        | 'D'
        | 'E'
        | 'F'
        | 'G'
        | 'H'
        | 'I'
        | 'J'
        | 'K'
        | 'L'
        | 'M'
        | 'N'
        | 'O'
        | 'P'
        | 'Q'
        | 'R'
        | 'S'
        | 'T'
        | 'U'
        | 'V'
        | 'W'
        | 'X'
        | 'Y'
        | 'Z'
        | '_'
        | '$' => {
          self.pos -= 1
          self.scan_ident()
        }
        '\\' =>
          match self.peek() {
            Some('u') => {
              self.pos -= 1
              self.scan_ident()
            }
            _ => {
              // invalid start, treat as identifier fallback
              self.pos -= 1
              self.scan_ident()
            }
          }
        // operator
        '+' =>
          match self.peek() {
            Some('+') => {
              let _ = self.advance()
              PlusPlus
            }
            Some('=') => {
              let _ = self.advance()
              PlusEq
            }
            _ => Plus
          }
        '-' =>
          match self.peek() {
            Some('-') => {
              let _ = self.advance()
              MinusMinus
            }
            Some('=') => {
              let _ = self.advance()
              MinusEq
            }
            _ => Minus
          }
        '*' =>
          match self.peek() {
            Some('*') => {
              let _ = self.advance()
              match self.peek() {
                Some('=') => {
                  let _ = self.advance()
                  StarStarEq
                }
                _ => StarStar
              }
            }
            Some('=') => {
              let _ = self.advance()
              StarEq
            }
            _ => Star
          }
        '/' =>
          if self.allow_regex {
            self.scan_regex()
          } else {
            match self.peek() {
              Some('=') => {
                let _ = self.advance()
                SlashEq
              }
              _ => Slash
            }
          }
        '%' =>
          match self.peek() {
            Some('=') => {
              let _ = self.advance()
              PercentEq
            }
            _ => Percent
          }
        '?' =>
          match self.peek() {
            Some('?') => {
              let _ = self.advance()
              match self.peek() {
                Some('=') => {
                  let _ = self.advance()
                  QuestionQuestionEq
                }
                _ => QuestionQuestion
              }
            }
            _ => Question
          }
        '=' =>
          match self.peek() {
            Some('=') =>
              match self.peek_next() {
                Some('=') => {
                  let _ = self.advance()
                  let _ = self.advance()
                  EqEqEq
                }
                _ => {
                  let _ = self.advance()
                  EqEq
                }
              }
            Some('>') => {
              let _ = self.advance()
              Arrow
            }
            _ => Eq
          }
        '!' =>
          match self.peek() {
            Some('=') =>
              match self.peek_next() {
                Some('=') => {
                  let _ = self.advance()
                  let _ = self.advance()
                  BangEqEq
                }
                _ => {
                  let _ = self.advance()
                  BangEq
                }
              }
            _ => Bang
          }
        '~' => Tilde
        '<' =>
          match self.peek() {
            Some('=') => {
              let _ = self.advance()
              Le
            }
            Some('<') => {
              let _ = self.advance()
              match self.peek() {
                Some('=') => {
                  let _ = self.advance()
                  LtLtEq
                }
                _ => LtLt
              }
            }
            _ => Lt
          }
        '>' =>
          match self.peek() {
            Some('=') => {
              let _ = self.advance()
              Ge
            }
            Some('>') => {
              let _ = self.advance()
              match self.peek() {
                Some('>') => {
                  let _ = self.advance()
                  match self.peek() {
                    Some('=') => {
                      let _ = self.advance()
                      GtGtGtEq
                    }
                    _ => GtGtGt
                  }
                }
                Some('=') => {
                  let _ = self.advance()
                  GtGtEq
                }
                _ => GtGt
              }
            }
            _ => Gt
          }
        '&' =>
          match self.peek() {
            Some('&') => {
              let _ = self.advance()
              match self.peek() {
                Some('=') => {
                  let _ = self.advance()
                  AmpAmpEq
                }
                _ => AmpAmp
              }
            }
            Some('=') => {
              let _ = self.advance()
              AmpEq
            }
            _ => Amp
          }
        '|' =>
          match self.peek() {
            Some('|') => {
              let _ = self.advance()
              match self.peek() {
                Some('=') => {
                  let _ = self.advance()
                  PipePipeEq
                }
                _ => PipePipe
              }
            }
            Some('=') => {
              let _ = self.advance()
              PipeEq
            }
            _ => Pipe
          }
        '^' =>
          match self.peek() {
            Some('=') => {
              let _ = self.advance()
              CaretEq
            }
            _ => Caret
          }
        '(' => LParen
        ')' => RParen
        '{' => LBrace
        '}' => RBrace
        '[' => LBracket
        ']' => RBracket
        ',' => Comma
        ':' => Colon
        ';' => Semicolon
        '.' =>
          match self.peek() {
            Some('0'..='9') => {
              self.pos -= 1
              self.scan_number()
            }
            Some('.') =>
              match self.peek_next() {
                Some('.') => {
                  let _ = self.advance()
                  let _ = self.advance()
                  Ellipsis
                }
                _ => Dot
              }
            _ => Dot
          }
        '"' | '\'' => {
          // stringliteral
          let quote = c
          self.scan_string(quote)
        }
        '`' => {
          // literal
          self.enqueue_template_tokens(pos)
          return self.next_token()
        }
        _ => Eof // statement
      }
      self.allow_regex = not(token_can_end_expr(kind))
      { kind, pos, has_newline_before: has_newline }
    }
  }
}

///|
// / get
pub fn Lexer::tokenize(self : Lexer) -> Array[Token] {
  let len = self.src.length()
  let tokens : Array[Token] = if len >= 1024 {
    let cap = len / 2 + 4
    Array::new(capacity=cap)
  } else {
    []
  }
  while true {
    let tok = self.next_token()
    tokens.push(tok)
    if tok.kind == Eof {
      break
    }
  }
  tokens
}

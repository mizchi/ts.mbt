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
  At // @

  // (add)
  New // new
  Interface // interface
  Type // type (type alias)
  Of // of (for...of)
  In // in (for...in)
  Declare // declare (externalimport)
  Null // null
  Eof
} derive(Eq, Debug)

///|
// /
pub struct Token {
  kind : TokenKind
  pos : Int // position
  has_newline_before : Bool // true if there was a newline before this token
} derive(Debug)

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
  // TS1127: count of genuinely-unknown ASCII characters the tokenizer had
  // to skip (a stray `\` not starting a unicode escape, control chars, ...).
  mut invalid_char_count : Int
  // TS1177/TS1178-family: a binary / octal literal ran into a decimal
  // digit outside its radix (`0b1102110`, `0o13334823`). tsc surfaces
  // parser-recovery errors there; one count per offending literal.
  mut invalid_radix_digit_count : Int
  // TS1125: a `\u{...}` / `\uXXXX` escape in a STRING literal with a
  // missing / non-hex digit (`"\u{}"`, `"\u{-DDDD}"`, `"\u{"`).
  // Template literals are NOT counted here — tagged templates accept
  // invalid escapes (ES2018), so the parser decides those.
  mut invalid_unicode_escape_count : Int
  // TS1198: a `\u{...}` escape whose value exceeds 0x10FFFF.
  mut unicode_escape_overflow_count : Int
  // TS1121: a legacy octal integer literal (`01`) — banned in TS.
  mut legacy_octal_literal_count : Int
  // Absolute source positions of invalid `\u` / `\x` escapes inside
  // TEMPLATE literals. Tagged templates accept invalid escapes (ES2018)
  // and taggedness is a parse-time fact, so the lexer only records —
  // the parser counts entries inside each UNTAGGED template's span.
  template_invalid_escape_positions : Array[Int]
  // TS1160: a template literal ran to EOF without its closing backtick.
  mut unterminated_template : Bool
  src : String
  mut pos : Int
  mut allow_regex : Bool
  mut pending : Array[Token]
  mut pending_index : Int
  mut newline_before_next : Bool // Set when whitespace skipping encounters a newline
  // JSDoc / annotation tracking. The lexer skips block comments
  // for parsing purposes, but it also peeks inside each one for a
  // few annotations the rest of the toolchain cares about. When a
  // comment contains the marker, the position of the FOLLOWING
  // non-comment token gets recorded — the parser then asks "was
  // this token preceded by `/* @__PURE__ */`?" without having to
  // re-scan source text.
  mut pending_pure_marker : Bool
  mut pending_internal_marker : Bool
  // Pending JSDoc block waiting to be associated with the next
  // non-comment token. When multiple JSDoc blocks stack up before
  // a declaration we keep the LAST one — that's the convention
  // tsc and IDE tooltips follow.
  mut pending_jsdoc : JsdocBlock?
  pure_marker_positions : Map[Int, Bool]
  internal_marker_positions : Map[Int, Bool]
  // Per-token-position parsed JSDoc block (when a `/** … */`
  // comment immediately preceded the token). Parser consults
  // through `Parser.jsdoc_at_pos`.
  jsdoc_at_pos : Map[Int, JsdocBlock]
} derive(Debug)

///|
fn is_word_like_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c == '$'
}

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
    invalid_char_count: 0,
    invalid_radix_digit_count: 0,
    invalid_unicode_escape_count: 0,
    unicode_escape_overflow_count: 0,
    legacy_octal_literal_count: 0,
    template_invalid_escape_positions: [],
    unterminated_template: false,
    src,
    // Skip a UTF-8/UTF-16 byte-order mark. Without this the BOM reaches
    // the identifier scanner as an unknown character and error recovery
    // silently swallows the first statement of the file.
    pos: if src.length() > 0 && src[0] == '\u{FEFF}' {
      1
    } else {
      0
    },
    allow_regex: true,
    pending: [],
    pending_index: 0,
    newline_before_next: false,
    pending_pure_marker: false,
    pending_internal_marker: false,
    pending_jsdoc: None,
    pure_marker_positions: {},
    internal_marker_positions: {},
    jsdoc_at_pos: {},
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
  let len = self.src.length()
  // Fast path: chomp ASCII whitespace (space, tab, newline, CR, VT, FF)
  // and line-terminator-relevant bytes directly without going through the
  // Option-returning helpers \u2014 this loop is called once per token and was
  // visibly hot on real `.d.ts` inputs.
  while self.pos < len {
    let b = self.src[self.pos].to_int()
    if b == 0x20 || b == 0x09 {
      self.pos += 1
      continue
    }
    if b == 0x0A || b == 0x0D {
      self.newline_before_next = true
      self.pos += 1
      continue
    }
    if b == 0x0B || b == 0x0C || b == 0xA0 {
      self.pos += 1
      continue
    }
    if b == 0x2028 || b == 0x2029 {
      self.newline_before_next = true
      self.pos += 1
      continue
    }
    // Multi-byte UTF-8 sequences for things like NBSP / LS / PS / BOM.
    if b == 0xC2 &&
      self.pos + 1 < len &&
      self.src[self.pos + 1].to_int() == 0xA0 {
      self.pos += 2
      continue
    }
    if b == 0xE2 &&
      self.pos + 2 < len &&
      self.src[self.pos + 1].to_int() == 0x80 {
      let b2 = self.src[self.pos + 2].to_int()
      if b2 == 0xA8 || b2 == 0xA9 {
        self.newline_before_next = true
        self.pos += 3
        continue
      }
    }
    if b == 0xEF &&
      self.pos + 2 < len &&
      self.src[self.pos + 1].to_int() == 0xBB &&
      self.src[self.pos + 2].to_int() == 0xBF {
      self.pos += 3
      continue
    }
    // Anything else is either a comment introducer or the next real token.
    break
  }
  while true {
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
            // block comment. Record the start so we can slice the
            // body when scanning for annotations.
            let comment_start = self.pos
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
            // Capture the full comment span. Plain `/* … */`
            // gets a substring scan (we only care about the
            // inline `@__PURE__` marker); JSDoc `/** … */` goes
            // through the structured parser so individual tags
            // are queryable downstream.
            let comment_text = self.src[comment_start:self.pos]
            // Quick-and-cheap markers — these still drive the
            // existing `pure_marker_positions` /
            // `internal_marker_positions` tables for callers that
            // only need a flag.
            if comment_text.contains("@__PURE__") {
              self.pending_pure_marker = true
            }
            if comment_text.contains("@internal") {
              self.pending_internal_marker = true
            }
            // Structured JSDoc — only fires for `/** … */`. The
            // last block wins when multiple stack up before one
            // declaration.
            if comment_text.has_prefix("/**") {
              match parse_jsdoc_block_view(comment_text) {
                Some(jb) => self.pending_jsdoc = Some(jb)
                None => ()
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
        // Accumulate as `Double` so values above `Int.MAX_VALUE`
        // (such as `0xffffffff`, used widely as a 32-bit-wide bit
        // mask) survive without overflow. JS Numbers are 64-bit
        // floats with 53 bits of integer precision — fits up to
        // `2^53`. BigInt literal storage (`0xffffffff_ffffffffn`)
        // still uses the string path below.
        let mut value : Double = 0.0
        let mut has_digit = false
        let digits = StringBuilder::new()
        while true {
          match self.peek() {
            Some('_') => {
              let _ = self.advance()
            }
            Some(c) =>
              match c {
                '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' => {
                  let _ = self.advance()
                  value = value * 16.0 + (c.to_int() - '0'.to_int()).to_double()
                  digits.write_char(c)
                  has_digit = true
                }
                'a' | 'b' | 'c' | 'd' | 'e' | 'f' => {
                  let _ = self.advance()
                  value = value * 16.0 +
                    (c.to_int() - 'a'.to_int() + 10).to_double()
                  digits.write_char(c)
                  has_digit = true
                }
                'A' | 'B' | 'C' | 'D' | 'E' | 'F' => {
                  let _ = self.advance()
                  value = value * 16.0 +
                    (c.to_int() - 'A'.to_int() + 10).to_double()
                  digits.write_char(c)
                  has_digit = true
                }
                _ => break
              }
            None => break
          }
        }
        if !has_digit {
          value = 0.0
        }
        let mut is_bigint = false
        if self.peek() == Some('n') {
          is_bigint = true
          let _ = self.advance()
        }
        if is_bigint {
          // Decimal-string form so downstream BigInt consumers can
          // parse it without re-implementing the hex reader. For
          // values that exceed `Double` integer precision (>=2^53),
          // fall back to a synthesized `0x…n` form so the BigInt
          // literal stays exact through `BigInt(str)`.
          return if value < 9007199254740992.0 {
            BigInt(value.to_int64().to_string())
          } else {
            BigInt("0x" + digits.to_string() + "n")
          }
        } else {
          // Values that fit in a 31-bit signed Int can still emit
          // as `Int(...)` so downstream passes (which often
          // pattern-match `IntLit(...)`) stay on the fast path.
          if value >= 0.0 && value <= 2147483647.0 && value.floor() == value {
            return Int(value.to_int())
          }
          return Number(value)
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
        match self.peek() {
          Some(c) if c >= '2' && c <= '9' =>
            self.invalid_radix_digit_count = self.invalid_radix_digit_count + 1
          _ => ()
        }
        if !has_digit {
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
        match self.peek() {
          Some(c) if c is ('8' | '9') =>
            self.invalid_radix_digit_count = self.invalid_radix_digit_count + 1
          _ => ()
        }
        if !has_digit {
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
          // TS1121: legacy octal integer literals (`01`) are banned in
          // TypeScript regardless of target (scannerNumericLiteral2/3/8).
          self.legacy_octal_literal_count = self.legacy_octal_literal_count + 1
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
        } else if c == '.' && !has_dot && !has_exp {
          has_dot = true
          let _ = self.advance()
        } else if (c == 'e' || c == 'E') && !has_exp {
          has_exp = true
          let _ = self.advance()
          match self.peek() {
            Some('+') | Some('-') => {
              let _ = self.advance()
            }
            _ => ()
          }
          // TS1124: the exponent needs at least one digit (`1e`, `1e+`
          // — scannerNumericLiteral4/6, scannerES3NumericLiteral4/6).
          match self.peek() {
            Some(d) if d >= '0' && d <= '9' => ()
            _ =>
              self.invalid_radix_digit_count = self.invalid_radix_digit_count +
                1
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
    self.src[start:end].to_owned()
  } else {
    self.src[start:self.pos].to_owned()
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
      let d = @string.parse_double(s)
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
      let d = @string.parse_double(s)
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
  // Fast path: walk over ASCII identifier characters and slice the source
  // once at the end. This avoids per-character `StringBuilder` work, which
  // showed up at the top of the lexer's hot path on real `.d.ts` inputs.
  let start = self.pos
  let len = self.src.length()
  while self.pos < len {
    let b = self.src[self.pos].to_int()
    if (b >= 'a'.to_int() && b <= 'z'.to_int()) ||
      (b >= 'A'.to_int() && b <= 'Z'.to_int()) ||
      (b >= '0'.to_int() && b <= '9'.to_int()) ||
      b == '_'.to_int() ||
      b == '$'.to_int() ||
      // Non-ASCII identifier characters (CJK, accented letters, …). TS uses
      // the Unicode ID_Continue set; we over-approximate with "any code unit
      // >= 0x80" so a unicode-named identifier scans as a single token
      // instead of fragmenting into per-character tokens.
      b >= 0x80 {
      self.pos += 1
    } else {
      break
    }
  }
  // Slow path: source contains a `\uXXXX` / `\u{XXXX}` escape inside the
  // identifier. Fall back to building the unescaped name char by char.
  if self.pos < len && self.src[self.pos].to_int() == '\\'.to_int() {
    return self.scan_ident_with_escapes(start)
  }
  let s = self.src[start:self.pos].to_owned()
  classify_ident_or_keyword(s)
}

///|
fn Lexer::scan_ident_with_escapes(self : Lexer, start : Int) -> TokenKind {
  let buf = StringBuilder::new()
  buf.write_string(self.src[start:self.pos].to_owned())
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
  classify_ident_or_keyword(buf.to_string())
}

///|
/// Map an identifier-looking source slice to the right keyword token (or
/// fall back to a plain `Ident`). Dispatching on the length and first byte
/// first keeps the common identifier case at one or two cheap comparisons
/// instead of the long `if`-chain it used to be.
fn classify_ident_or_keyword(s : String) -> TokenKind {
  let n = s.length()
  if n == 0 {
    return Ident(s)
  }
  let c0 = s[0].to_int()
  match n {
    2 =>
      match c0 {
        c if c == 'a'.to_int() => if s == "as" { As } else { Ident(s) }
        c if c == 'd'.to_int() => if s == "do" { Do } else { Ident(s) }
        c if c == 'i'.to_int() =>
          if s == "if" {
            If
          } else if s == "in" {
            In
          } else {
            Ident(s)
          }
        c if c == 'o'.to_int() => if s == "of" { Of } else { Ident(s) }
        _ => Ident(s)
      }
    3 =>
      match c0 {
        c if c == 'v'.to_int() => if s == "var" { Var } else { Ident(s) }
        c if c == 'l'.to_int() => if s == "let" { Let } else { Ident(s) }
        c if c == 'f'.to_int() => if s == "for" { For } else { Ident(s) }
        c if c == 't'.to_int() => if s == "try" { Try } else { Ident(s) }
        c if c == 'n'.to_int() => if s == "new" { New } else { Ident(s) }
        c if c == 'i'.to_int() => if s == "int" { IntType } else { Ident(s) }
        _ => Ident(s)
      }
    4 =>
      match c0 {
        c if c == 'c'.to_int() => if s == "case" { Case } else { Ident(s) }
        c if c == 'e'.to_int() => if s == "else" { Else } else { Ident(s) }
        c if c == 'f'.to_int() => if s == "from" { From } else { Ident(s) }
        c if c == 'n'.to_int() => if s == "null" { Null } else { Ident(s) }
        c if c == 't'.to_int() =>
          if s == "true" {
            Bool(true)
          } else if s == "type" {
            Type
          } else {
            Ident(s)
          }
        c if c == 'v'.to_int() => if s == "void" { VoidType } else { Ident(s) }
        c if c == 'w'.to_int() => if s == "with" { With } else { Ident(s) }
        _ => Ident(s)
      }
    5 =>
      match c0 {
        c if c == 'b'.to_int() => if s == "break" { Break } else { Ident(s) }
        c if c == 'c'.to_int() =>
          if s == "class" {
            Class
          } else if s == "catch" {
            Catch
          } else if s == "const" {
            Const
          } else {
            Ident(s)
          }
        c if c == 'f'.to_int() =>
          if s == "false" {
            Bool(false)
          } else {
            Ident(s)
          }
        c if c == 't'.to_int() => if s == "throw" { Throw } else { Ident(s) }
        c if c == 'w'.to_int() => if s == "while" { While } else { Ident(s) }
        c if c == 'y'.to_int() => if s == "yield" { Yield } else { Ident(s) }
        _ => Ident(s)
      }
    6 =>
      match c0 {
        c if c == 'r'.to_int() => if s == "return" { Return } else { Ident(s) }
        c if c == 'i'.to_int() => if s == "import" { Import } else { Ident(s) }
        c if c == 'e'.to_int() => if s == "export" { Export } else { Ident(s) }
        c if c == 's'.to_int() =>
          if s == "switch" {
            Switch
          } else if s == "string" {
            StringType
          } else {
            Ident(s)
          }
        c if c == 'd'.to_int() => if s == "delete" { Delete } else { Ident(s) }
        c if c == 't'.to_int() => if s == "typeof" { Typeof } else { Ident(s) }
        c if c == 'n'.to_int() =>
          if s == "number" {
            NumberType
          } else {
            Ident(s)
          }
        _ => Ident(s)
      }
    7 =>
      match c0 {
        c if c == 'd'.to_int() =>
          if s == "default" {
            Default
          } else if s == "declare" {
            Declare
          } else {
            Ident(s)
          }
        c if c == 'e'.to_int() =>
          if s == "extends" {
            Extends
          } else {
            Ident(s)
          }
        c if c == 'f'.to_int() =>
          if s == "finally" {
            Finally
          } else {
            Ident(s)
          }
        c if c == 'b'.to_int() =>
          if s == "boolean" {
            BooleanType
          } else {
            Ident(s)
          }
        _ => Ident(s)
      }
    8 =>
      match c0 {
        c if c == 'f'.to_int() =>
          if s == "function" {
            Function
          } else {
            Ident(s)
          }
        c if c == 'c'.to_int() =>
          if s == "continue" {
            Continue
          } else {
            Ident(s)
          }
        c if c == 'd'.to_int() =>
          if s == "debugger" {
            Debugger
          } else {
            Ident(s)
          }
        _ => Ident(s)
      }
    9 =>
      match c0 {
        c if c == 'i'.to_int() =>
          if s == "interface" {
            Interface
          } else {
            Ident(s)
          }
        _ => Ident(s)
      }
    10 =>
      match c0 {
        c if c == 'i'.to_int() =>
          if s == "instanceof" {
            Instanceof
          } else {
            Ident(s)
          }
        _ => Ident(s)
      }
    _ => Ident(s)
  }
}

///|
fn Lexer::scan_private_ident(self : Lexer) -> TokenKind {
  // Fast path: walk ASCII identifier bytes after the leading `#` and slice
  // the name out of the source. Matches the optimization applied to
  // `scan_ident`.
  let start = self.pos
  let len = self.src.length()
  while self.pos < len {
    let b = self.src[self.pos].to_int()
    if (b >= 'a'.to_int() && b <= 'z'.to_int()) ||
      (b >= 'A'.to_int() && b <= 'Z'.to_int()) ||
      (b >= '0'.to_int() && b <= '9'.to_int()) ||
      b == '_'.to_int() ||
      b == '$'.to_int() {
      self.pos += 1
    } else {
      break
    }
  }
  if self.pos >= len || self.src[self.pos].to_int() != '\\'.to_int() {
    return PrivateIdent(self.src[start:self.pos].to_owned())
  }
  let buf = StringBuilder::new()
  buf.write_string(self.src[start:self.pos].to_owned())
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
  // Fast path: most string literals in real-world `.ts` / `.d.ts` files
  // contain no escapes and no line continuations, so just walk the bytes
  // looking for the closing quote and slice. Bail to the full escape-aware
  // path the moment we hit a backslash, raw line break, or non-ASCII byte.
  let start = self.pos
  let len = self.src.length()
  let quote_int = quote.to_int()
  while self.pos < len {
    let b = self.src[self.pos].to_int()
    if b == quote_int {
      let value = self.src[start:self.pos].to_owned()
      self.pos += 1
      return Str(value)
    }
    if b == '\\'.to_int() ||
      b == '\n'.to_int() ||
      b == '\r'.to_int() ||
      b >= 0x80 {
      break
    }
    self.pos += 1
  }
  let buf = StringBuilder::new()
  buf.write_string(self.src[start:self.pos].to_owned())
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
                // TS1125: `\x` demands exactly two hex digits in a string.
                self.invalid_unicode_escape_count = self.invalid_unicode_escape_count +
                  1
                buf.write_char('x')
              }
            }
            Some('u') => {
              let _ = self.advance()
              let mut code = 0
              let mut ok = true
              let mut digits = 0
              let mut braced = false
              if self.peek() == Some('{') {
                braced = true
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
                // TS1198: a braced escape past the Unicode range. `code`
                // may have wrapped a 32-bit Int on long inputs
                // (`\u{FFFFFFFF}`), so a negative accumulation counts too.
                if braced && (code > 0x10FFFF || code < 0) {
                  self.unicode_escape_overflow_count = self.unicode_escape_overflow_count +
                    1
                  buf.write_char('u')
                } else {
                  write_codepoint(buf, code)
                }
              } else {
                // TS1125: missing / non-hex digits (`\u{}`, `\u{-D}`, `\u{`).
                self.invalid_unicode_escape_count = self.invalid_unicode_escape_count +
                  1
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
  let mut prev_sig : Char? = Some('{')
  while depth > 0 {
    match self.peek() {
      None => break
      Some(c) => {
        let _ = self.advance()
        match c {
          '{' => {
            depth += 1
            prev_sig = Some('{')
          }
          '}' => {
            depth -= 1
            prev_sig = Some('}')
          }
          '\'' | '"' => {
            self.skip_string_body(c)
            prev_sig = Some('s')
          }
          '`' => {
            let _ = self.scan_template()
            prev_sig = Some('s')
          }
          '/' =>
            match self.peek() {
              Some('/') => {
                let _ = self.advance()
                while true {
                  match self.peek() {
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
                let _ = self.advance()
                while true {
                  match self.peek() {
                    None => break
                    Some('*') if self.peek_next() == Some('/') => {
                      let _ = self.advance()
                      let _ = self.advance()
                      break
                    }
                    _ => {
                      let _ = self.advance()
                    }
                  }
                }
              }
              _ =>
                if (match prev_sig {
                    None => true
                    Some(prev) =>
                      prev == '(' ||
                      prev == '[' ||
                      prev == '{' ||
                      prev == ',' ||
                      prev == ':' ||
                      prev == ';' ||
                      prev == '=' ||
                      prev == '!' ||
                      prev == '?' ||
                      prev == '+' ||
                      prev == '-' ||
                      prev == '*' ||
                      prev == '%' ||
                      prev == '^' ||
                      prev == '&' ||
                      prev == '|' ||
                      prev == '<' ||
                      prev == '>'
                  }) {
                  self.skip_regex_body()
                  prev_sig = Some('r')
                } else {
                  prev_sig = Some('/')
                }
            }
          ' ' | '\t' | '\n' | '\r' | '\u2028' | '\u2029' => ()
          _ => prev_sig = Some(c)
        }
      }
    }
  }
  let end = if self.pos > 0 { self.pos - 1 } else { 0 }
  self.src[start:end].to_owned()
}

///|
fn Lexer::skip_regex_body(self : Lexer) -> Unit {
  let mut escaped = false
  let mut in_class = false
  while true {
    match self.peek() {
      None => break
      Some(c) => {
        let _ = self.advance()
        if escaped {
          escaped = false
          continue
        }
        match c {
          '\\' => escaped = true
          '[' => in_class = true
          ']' => in_class = false
          '/' => if !in_class { break }
          _ => ()
        }
      }
    }
  }
  while true {
    match self.peek() {
      Some(c) if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') => {
        let _ = self.advance()
      }
      _ => break
    }
  }
}

///|
/// TS1125 / TS1198: under the `u` / `v` flags, `\u{...}` escapes in a
/// regex body must carry hex digits and stay within 0x0..0x10FFFF
/// (unicodeExtendedEscapesInRegularExpressions07-19). Without the flag,
/// `\u{2}` is a quantified `u` and stays legal.
fn Lexer::validate_regex_unicode_escapes(self : Lexer, bs : String) -> Unit {
  let n = bs.length()
  let mut i = 0
  while i + 2 < n {
    if bs[i].to_int() == '\\'.to_int() &&
      bs[i + 1].to_int() == 'u'.to_int() &&
      bs[i + 2].to_int() == '{'.to_int() {
      let mut j = i + 3
      let mut code = 0
      let mut digits = 0
      let mut ok = true
      while j < n && bs[j].to_int() != '}'.to_int() {
        let ch = bs[j].to_int()
        let d = if ch >= '0'.to_int() && ch <= '9'.to_int() {
          ch - '0'.to_int()
        } else if ch >= 'a'.to_int() && ch <= 'f'.to_int() {
          ch - 'a'.to_int() + 10
        } else if ch >= 'A'.to_int() && ch <= 'F'.to_int() {
          ch - 'A'.to_int() + 10
        } else {
          -1
        }
        if d < 0 {
          ok = false
          break
        }
        if code <= 0x10FFFF {
          code = code * 16 + d
        }
        digits = digits + 1
        j = j + 1
      }
      if j >= n {
        ok = false
      }
      if !ok || digits == 0 {
        self.invalid_unicode_escape_count = self.invalid_unicode_escape_count +
          1
      } else if code > 0x10FFFF {
        self.unicode_escape_overflow_count = self.unicode_escape_overflow_count +
          1
      }
      i = j
    }
    i = i + 1
  }
}

///|
fn Lexer::skip_template_expr(self : Lexer) -> Unit {
  let mut depth = 1
  let mut prev_sig : Char? = Some('{')
  while depth > 0 {
    match self.peek() {
      None => break
      Some(c) => {
        let _ = self.advance()
        match c {
          '{' => {
            depth += 1
            prev_sig = Some('{')
          }
          '}' => {
            depth -= 1
            prev_sig = Some('}')
          }
          '\'' | '"' => {
            self.skip_string_body(c)
            prev_sig = Some('s')
          }
          '`' => {
            let _ = self.scan_template()
            prev_sig = Some('s')
          }
          '/' =>
            match self.peek() {
              Some('/') => {
                let _ = self.advance()
                while true {
                  match self.peek() {
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
                let _ = self.advance()
                while true {
                  match self.peek() {
                    None => break
                    Some('*') if self.peek_next() == Some('/') => {
                      let _ = self.advance()
                      let _ = self.advance()
                      break
                    }
                    _ => {
                      let _ = self.advance()
                    }
                  }
                }
              }
              _ =>
                if (match prev_sig {
                    None => true
                    Some(prev) =>
                      prev == '(' ||
                      prev == '[' ||
                      prev == '{' ||
                      prev == ',' ||
                      prev == ':' ||
                      prev == ';' ||
                      prev == '=' ||
                      prev == '!' ||
                      prev == '?' ||
                      prev == '+' ||
                      prev == '-' ||
                      prev == '*' ||
                      prev == '%' ||
                      prev == '^' ||
                      prev == '&' ||
                      prev == '|' ||
                      prev == '<' ||
                      prev == '>'
                  }) {
                  self.skip_regex_body()
                  prev_sig = Some('r')
                } else {
                  prev_sig = Some('/')
                }
            }
          ' ' | '\t' | '\n' | '\r' | '\u2028' | '\u2029' => ()
          _ => prev_sig = Some(c)
        }
      }
    }
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
      None => {
        // EOF before the closing backtick -- TS1160.
        self.unterminated_template = true
        break
      }
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
                self.template_invalid_escape_positions.push(self.pos)
                cooked_buf.write_char('x')
              }
            }
            Some('u') => {
              let _ = self.advance()
              raw_buf.write_char('u')
              let mut code = 0
              let mut ok = true
              let mut digits = 0
              let mut braced = false
              if self.peek() == Some('{') {
                braced = true
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
                          if code <= 0x10FFFF {
                            code = code * 16 + d
                          }
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
                // Overflow (`\u{110000}`) is recorded like a malformed
                // escape — the untagged-template parse site surfaces it.
                if braced && (code > 0x10FFFF || code < 0) {
                  self.template_invalid_escape_positions.push(self.pos)
                  cooked_buf.write_char('u')
                } else {
                  write_codepoint(cooked_buf, code)
                }
              } else {
                self.template_invalid_escape_positions.push(self.pos)
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
        } else if c == '\r' {
          // ES template cooked values normalize line terminators: a
          // physical CRLF (or lone CR) contributes a single LF
          // (stringLiteralTypesWithTemplateStrings02 relies on the cooked
          // value differing from a `"\r\n"`-escaped string literal).
          let _ = self.advance()
          if self.peek() is Some('\n') {
            let _ = self.advance()
          }
          cooked_buf.write_char('\n')
          raw_buf.write_char('\n')
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

// / string()

///|
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
        if c == '/' && !in_class {
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
  let flag_str = flags.to_string()
  if flag_str.contains("u") || flag_str.contains("v") {
    self.validate_regex_unicode_escapes(buf.to_string())
  }
  Regex(buf.to_string(), flag_str)
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
    // A template literal is a complete expression, so a following `/` is
    // division, not a regex start (`` `a${1}b` / 1 ``).
    | Template(_, _, _)
    | Ident(_)
    | PrivateIdent(_)
    | NumberType
    | BooleanType
    | StringType
    | IntType
    | Type
    | Null
    | RParen
    | RBracket
    // `}` stays here even though a closing brace often ends a BLOCK
    // (after which `/` starts a regex): JSX self-closing tags
    // (`attr={x} />`) and object-literal division depend on the
    // division reading. The statement-position regex case is recovered
    // by the parser re-lexing from source (`Parser::parse_stmt`'s
    // `Slash` arm — parser768531).
    | RBrace
    | PlusPlus
    | MinusMinus => true
    _ => false
  }
}

///|
fn next_allow_regex(current_allow_regex : Bool, kind : TokenKind) -> Bool {
  match kind {
    Bang => current_allow_regex
    _ => !token_can_end_expr(kind)
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
    self.allow_regex = next_allow_regex(self.allow_regex, tok.kind)
    return tok
  }
  self.skip_whitespace()
  let has_newline = self.newline_before_next
  let pos = self.pos
  // Stamp annotation markers onto the upcoming token's position so
  // the parser can look them up after tokenize() finishes.
  if self.pending_pure_marker {
    self.pure_marker_positions[pos] = true
    self.pending_pure_marker = false
  }
  if self.pending_internal_marker {
    self.internal_marker_positions[pos] = true
    self.pending_internal_marker = false
  }
  match self.pending_jsdoc {
    Some(jb) => {
      self.jsdoc_at_pos[pos] = jb
      self.pending_jsdoc = None
    }
    None => ()
  }
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
              // TS1127: a backslash not starting a `\u....` identifier
              // escape is an invalid character. Keep the permissive
              // identifier fallback so parsing continues.
              self.invalid_char_count += 1
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
          if self.allow_regex &&
            !(self.pos >= 2 &&
            self.src[self.pos - 2].to_int().unsafe_to_char() == '<') {
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
        '@' => At
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
        '"' => self.scan_string('"')
        '\'' => {
          let prev = if pos > 0 {
            Some(self.src[pos - 1].to_int().unsafe_to_char())
          } else {
            None
          }
          let next = self.peek()
          let prev_is_word = match prev {
            Some(ch) => is_word_like_char(ch)
            None => false
          }
          let next_is_word = match next {
            Some(ch) => is_word_like_char(ch)
            None => false
          }
          if prev_is_word && next_is_word {
            Ident("'")
          } else {
            self.scan_string('\'')
          }
        }
        '`' => {
          // literal
          self.enqueue_template_tokens(pos)
          return self.next_token()
        }
        _ =>
          // A non-ASCII character starts a unicode identifier (CJK, accented
          // letters, …): back up and scan the whole run as one identifier
          // token rather than emitting a single-character `Ident`, which
          // would fragment `var café = 1` into pieces. ASCII characters that
          // reach here are genuinely unknown and keep the legacy fallback.
          if c.to_int() >= 0x80 {
            self.pos -= 1
            self.scan_ident()
          } else {
            // TS1127: a genuinely unknown ASCII character. A backslash may
            // begin a `\u....` identifier escape (legal TS), so only count
            // one that is *not* followed by `u`; every other ASCII char that
            // reaches this fallback is invalid source.
            let is_escape_start = c == '\\' &&
              (match self.peek() {
                Some('u') => true
                _ => false
              })
            if !is_escape_start {
              self.invalid_char_count += 1
            }
            Ident(c.to_string())
          }
      }
      self.allow_regex = next_allow_regex(self.allow_regex, kind)
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

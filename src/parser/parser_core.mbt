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
  // Ambient context: when true, `export var X;` / `export let X;` /
  // `export const X;` style declarations without initializer are
  // treated as type-only (no runtime emission) — the convention for
  // `.d.ts` parsing and ambient external module bodies. Runtime
  // sources (`.js` / `.ts`) flip this off so the declarations emit
  // a real binding.
  mut in_ambient_module : Bool
  labels : Array[String] // for labeled break/continue validation
  src : String
  allow_jsx : Bool
  mut class_id : Int // for private field brand generation
  // File-level counter for computed-key temp variables (`__class_key_N`).
  // A per-class local counter would reset to 0 for every class in the file,
  // causing duplicate `let __class_key_0` declarations when multiple classes
  // are bundled into a single scope.
  mut class_key_counter : Int
  mut current_class_brand : String? // brand ID of current class being parsed
  mut last_runtime_class_decl : @ast.TsClassDecl?
  // The expression parsed by `parse_class_base_name` when the
  // heritage clause was an expression form (`extends declare(...)` /
  // `extends make(ast)`). Callers drain this immediately after the
  // call to stash it on the resulting `TsClassDecl.base_expr`.
  mut pending_class_base_expr : @ast.TsExpr?
  local_type_param_bounds : Array[(String, @ast.TsType)]
  // Decorator expressions parsed at the statement level that should be
  // attached to the next class declaration. The class parsers drain
  // this list when they begin and clear it on exit.
  pending_decorators : Array[@ast.TsExpr]
  // Stack of "I'm parsing a class constructor's parameter list"
  // scopes. Each scope is a list of parameter names that carried
  // `public` / `private` / `protected` / `readonly` modifiers — TS
  // parameter properties. The class parser pushes a fresh scope
  // before calling `parse_params` for a constructor and pops it
  // afterwards, then emits `this.name = name` for every entry. Each
  // entry pairs the parameter name with whether it carried `readonly`
  // and its accessibility (`"public"` / `"private"` / `"protected"`) so
  // the class builder can materialize a readonly field and record member
  // visibility.
  param_property_scopes : Array[Array[(String, Bool, String)]]
  // Parameter names seen with an accessibility / readonly modifier
  // outside a constructor parameter list (TS2369 misuse), keyed by the
  // parameter's source position so speculative re-parses (arrow
  // lookahead re-runs `parse_param`) collapse to one entry. Surfaced
  // on the resulting `TsModule`.
  collected_param_property_misuses : Map[Int, String]
  // Token-position → "JSDoc `/* @__PURE__ */` annotation seen
  // just before this token". The lexer populates this when it
  // skips a block comment whose contents contain the literal
  // `@__PURE__`. The call-expr parser consults the map to wrap
  // its result in `TsExpr::PureCall(...)`.
  pure_marker_positions : Map[Int, Bool]
  // Same shape for `/** @internal */` JSDoc blocks. The decl
  // parser flags the next declaration's name into
  // `collected_internal_names`, which gets attached to the
  // emitted `TsModuleBlock`. `.d.ts` emit then drops those
  // names from the published surface.
  internal_marker_positions : Map[Int, Bool]
  collected_internal_names : Map[String, Bool]
  // Parsed JSDoc block per next-token position. Populated by the
  // lexer; queried by decl parsers to attach tag info (`@param`,
  // `@returns`, `@deprecated`, …) to the AST.
  jsdoc_at_pos : Map[Int, JsdocBlock]
  // Names with a `@deprecated` tag — fed into the emitted
  // `TsModuleBlock` so `.d.ts` emit can mark them.
  collected_deprecations : Map[String, String]
  // Function names with a `@__PURE__` or `@__NO_SIDE_EFFECTS__`
  // tag. The purity pass treats these as unconditionally pure.
  collected_pure_declarations : Map[String, Bool]
  // Type aliases declared anywhere in the module — `type T = …`,
  // `export type T = …`. Threaded out via `TsModuleBlock` so the
  // bundle can run whole-program type-driven passes.
  collected_type_aliases : Array[@ast.TsTypeAlias]
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
    in_ambient_module: false,
    labels: [],
    src: "",
    allow_jsx,
    class_id: 0,
    class_key_counter: 0,
    current_class_brand: None,
    last_runtime_class_decl: None,
    pending_class_base_expr: None,
    local_type_param_bounds: [],
    pending_decorators: [],
    param_property_scopes: [],
    collected_param_property_misuses: {},
    pure_marker_positions: {},
    internal_marker_positions: {},
    collected_internal_names: {},
    jsdoc_at_pos: {},
    collected_deprecations: {},
    collected_pure_declarations: {},
    collected_type_aliases: [],
  }
}

// (`from_source` below picks up the marker maps from the Lexer
// so the parser can answer "was this token preceded by
// `/* @__PURE__ */` / `/** @internal */`?").

///|
// / create
pub fn Parser::from_source(src : String) -> Parser {
  Parser::from_source_with_jsx(src, true)
}

///|
fn src_has_leading_bom(src : String) -> Bool {
  src.length() > 0 && src[0].to_int() == 0xFEFF
}

///|
pub fn Parser::from_source_with_jsx(
  raw_src : String,
  allow_jsx : Bool,
) -> Parser {
  // Strip a leading UTF-8 BOM (U+FEFF). Left in place it tokenises as
  // part of the first token (e.g. a template literal or identifier),
  // corrupting the first statement; TS/JS toolchains strip it. Done
  // once here so the lexer and the stored `src` (directive scans,
  // string-escape slow path) stay byte-aligned.
  let src = if src_has_leading_bom(raw_src) {
    raw_src.substring(start=1)
  } else {
    raw_src
  }
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
    in_ambient_module: false,
    labels: [],
    src,
    allow_jsx,
    class_id: 0,
    class_key_counter: 0,
    current_class_brand: None,
    last_runtime_class_decl: None,
    pending_class_base_expr: None,
    local_type_param_bounds: [],
    pending_decorators: [],
    param_property_scopes: [],
    collected_param_property_misuses: {},
    pure_marker_positions: lexer.pure_marker_positions,
    internal_marker_positions: lexer.internal_marker_positions,
    collected_internal_names: {},
    jsdoc_at_pos: lexer.jsdoc_at_pos,
    collected_deprecations: {},
    collected_pure_declarations: {},
    collected_type_aliases: [],
  }
}

///|
// / currentget
fn Parser::peek(self : Parser) -> Token {
  if self.pending_gt > 0 {
    { kind: Gt, pos: self.pending_gt_pos, has_newline_before: false }
  } else if self.pos >= self.tokens.length() {
    { kind: Eof, pos: 0, has_newline_before: false }
  } else {
    self.tokens[self.pos]
  }
}

///|
// /
fn Parser::advance(self : Parser) -> Token {
  if self.pending_gt > 0 {
    self.pending_gt -= 1
    return { kind: Gt, pos: self.pending_gt_pos, has_newline_before: false }
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
    return { kind: Gt, pos: self.pending_gt_pos, has_newline_before: false }
  }
  let idx = self.pos + offset - self.pending_gt
  if idx >= self.tokens.length() {
    { kind: Eof, pos: 0, has_newline_before: false }
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

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
  // Explicit type arguments captured by `try_skip_call_type_args` for the
  // call that immediately follows (`foo<number>(x)`). Drained by `parse_call`
  // when it builds the `Call` / `New` / `MethodCall` so the result can be
  // wrapped in `TypeArgs`. Empty when the following call had none.
  mut pending_call_type_args : Array[@ast.TsType]
  // Set by `parse_type_param_names_bounds_and_const_flags` to record whether
  // the type-parameter list it just parsed contained ANY defaulted parameter
  // (`<T = string>`). A generic declaration with no defaulted parameter
  // requires all of its type arguments, so a bare reference to it (`C` with no
  // `<...>`) is TS2314. Read immediately after the call by the class /
  // interface / type-alias parsers.
  mut last_type_params_had_default : Bool
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
  // Parameter properties (`public` / `private` / `protected` / `readonly`)
  // seen on a parameter while *no* constructor scope was active — i.e. on a
  // free function, arrow, non-constructor method, or call / construct
  // signature. TypeScript reports TS2369 for each. `parse_param` appends a
  // location string here; `parse_module` hands the list to the checker.
  param_property_misuses : Array[String]
  // `eval` / `arguments` bound or assigned in strict-mode code. Fed by
  // `parse_binding_ident` / assignment parsing when `in_strict` (prologue /
  // class body) or `directive_strict` (conformance `@alwaysStrict: true` /
  // `@strict: true` header) is active; `parse_module` hands the list to the
  // checker. Empty for well-formed input.
  strict_mode_misuses : Array[String]
  // Decorator groups that preceded a non-class declaration (TS1206).
  invalid_decorator_uses : Array[String]
  // Always-error grammar misuses (complete messages; see TsModule).
  grammar_misuses : Array[String]
  // Local binding names introduced by ES `import` statements (default,
  // namespace, and named/aliased specifiers). The import statements
  // themselves are consumed and discarded, but the *names* must stay
  // visible so unresolved-reference checks treat them as declared.
  imported_binding_names : Array[String]
  // Module specifiers of ES `import` statements (`import ... from "spec"`,
  // `import x = require("spec")`). Consulted by the module-not-found check
  // (TS2307) against in-file ambient module declarations.
  import_module_specs : Array[String]
  // The source carries `@filename:` conformance directives -- a multi-file
  // test concatenated into one parse. Cross-file resolution is out of scope
  // there, so the TS2307 recording is disabled.
  multi_file_source : Bool
  // `(class, base, args)` for every `class C extends B<...>` heritage clause
  // whose type arguments parse cleanly. Lets the checker instantiate the
  // base's generic surface (e.g. index-signature value types) without a
  // TsClassDecl shape change.
  class_base_type_args : Array[(String, String, Array[@ast.TsType])]
  // When set, `parse_type` keeps a bounded type parameter as its `Named`
  // reference instead of inlining the constraint. Used when capturing
  // `extends B<...>` heritage type arguments, where the raw parameter
  // identity is the whole point.
  mut no_bound_inline : Bool
  // The conformance header carries an explicit `@target:` of ES2015 or
  // newer. In that mode tsc reserves `yield` as a function name
  // (TS1212 -- `function yield() {}` under `@target: es6`).
  target_es6_plus : Bool
  // noImplicitAny per the conformance-header directives. Mirrors the
  // checker's strict-flag convention: the tsc-generated baselines for files
  // *without* a directive include the implicit-any family (TS7006 / TS7010 /
  // TS7005 / ...), so the default is `true`; `@strict: false` or
  // `@noImplicitAny: false` opt out, an explicit `@noImplicitAny: true`
  // opts back in over `@strict: false`.
  no_implicit_any : Bool
  // Armed only while parsing a *function declaration's* parameter list --
  // the one position where an unannotated parameter can never be
  // contextually typed, so the implicit-any verdict is reliable.
  mut record_implicit_any_params : Bool
  // Armed while parsing the body of a *class declaration with no heritage
  // clause* -- with neither `extends` nor `implements`, a method parameter
  // has no contextual-typing source, so the implicit-any verdict is
  // reliable for members too. Class *expressions* stay unarmed (their
  // members can be contextually typed from the assignment target).
  mut class_decl_no_heritage : Bool
  // True while parsing a class EXPRESSION body: constructor params stay
  // exempt from the heritage-free noImplicitAny arming (a construct-
  // signature contextual type can supply them), while method params are
  // never contextually typed and keep recording.
  mut in_class_expr_body : Bool
  // Parameter names the source annotated explicitly with `: any`. tsc
  // never reports TS7006 for these, but post-parse `TsParam.type_` can't
  // distinguish a written `any` from a missing annotation — the
  // noImplicitAny recorders consult this set. Keyed by bare name (a
  // same-named unannotated param elsewhere is then exempt too — a safe
  // MISS, never an FP).
  written_any_params : Map[String, Unit]
  // Conformance-header strict directive (`@alwaysStrict: true` / `@strict:
  // true`). Unlike `in_strict` it does NOT change parsing behaviour (octal
  // handling, statement restrictions, ...) -- it only arms the strict-misuse
  // *recording* above, so multi-variant directive files never fail to parse.
  directive_strict : Bool
  // Parameters declared with *both* an optional marker (`x?`) and an
  // initializer (`x = e`) -- always a TS1015 syntax error regardless of
  // position. The `?` is otherwise folded into the parameter type
  // (`x?: T` -> `T | undefined`), indistinguishable from an explicit
  // `x: T | undefined = e` (which is legal), so the conflict must be
  // recorded at parse time where both facts are still separate.
  // `parse_param` appends the parameter name; `parse_module` hands the
  // list to the checker. Empty for well-formed input, so it never costs
  // precision.
  param_optional_initializer_misuses : Array[String]
  // Interface / type-literal members seen with an accessibility modifier
  // (`private` / `public` / `protected`) -- always a TS1070 grammar error.
  // `parse_interface` / the object-type-literal parser append one location
  // string per offending member; the checker surfaces them. Empty for
  // well-formed input, so it never costs precision.
  interface_member_modifier_misuses : Array[String]
  // Class-body structural diagnostics (`duplicate_member_names`, which also
  // carries the `<multiple-ctor-impl>` / `<index-sig-modifier>` /
  // `<abstract-impl>` sentinels) collected for *every* class parsed, including
  // classes nested in function bodies that are lowered away (IIFE desugar) and
  // so never reach `module_.classes`. Each entry is `(class_name, names)`.
  // `parse_class_decl_with_abstract` appends; the checker surfaces them. Empty
  // for well-formed input, so it never costs precision.
  collected_class_dups : Array[(String, Array[String])]
  // String-literal member names (`class C { 'a': T }`) seen while parsing
  // class bodies. Quotedness is erased by the key parser, but
  // strict-property-initialization must exempt literal-named fields --
  // drained per class into `<quoted-member:...>` sentinels.
  quoted_member_names : Array[String]
  // Member names that carried an `override` modifier while parsing class
  // bodies ("i:"/"s:" prefixed for instance/static). Drained per class
  // into `<override-member:...>` sentinels for TS4112/4113/4114.
  override_member_names : Array[String]
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
    pending_call_type_args: [],
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
    last_type_params_had_default: false,
    local_type_param_bounds: [],
    pending_decorators: [],
    param_property_scopes: [],
    param_property_misuses: [],
    strict_mode_misuses: [],
    invalid_decorator_uses: [],
    grammar_misuses: [],
    imported_binding_names: [],
    import_module_specs: [],
    multi_file_source: false,
    class_base_type_args: [],
    no_bound_inline: false,
    target_es6_plus: false,
    no_implicit_any: false,
    record_implicit_any_params: false,
    class_decl_no_heritage: false,
    in_class_expr_body: false,
    written_any_params: {},
    directive_strict: false,
    param_optional_initializer_misuses: [],
    interface_member_modifier_misuses: [],
    collected_class_dups: [],
    quoted_member_names: [],
    override_member_names: [],
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
pub fn Parser::from_source_with_jsx(src : String, allow_jsx : Bool) -> Parser {
  let lexer = Lexer::new(src)
  let tokens = lexer.tokenize()
  let in_strict = detect_use_strict_prologue(src)
  let grammar_misuses : Array[String] = []
  if lexer.invalid_char_count > 0 {
    grammar_misuses.push("invalid character in source")
  }
  if lexer.unterminated_template {
    grammar_misuses.push("unterminated template literal")
  }
  for _i in 0..<lexer.invalid_radix_digit_count {
    grammar_misuses.push("invalid digit in a binary or octal numeric literal")
  }
  // Module-scoped flag marker for the override checks (TS4114 fires only
  // under `@noImplicitOverride: true`); TS4112/TS4113 are unconditional.
  if detect_no_implicit_override(src) {
    grammar_misuses.push("<noimplicitoverride-on>")
  }
  // Marker for the TS2695 comma-operator check, which tsc disables under
  // `@allowUnreachableCode: true`.
  if detect_allow_unreachable_code(src) {
    grammar_misuses.push("<allowunreachable-on>")
  }
  {
    tokens,
    pos: 0,
    pending_gt: 0,
    pending_gt_pos: 0,
    pending_call_type_args: [],
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
    last_type_params_had_default: false,
    local_type_param_bounds: [],
    pending_decorators: [],
    param_property_scopes: [],
    param_property_misuses: [],
    strict_mode_misuses: [],
    invalid_decorator_uses: [],
    grammar_misuses,
    imported_binding_names: [],
    import_module_specs: [],
    multi_file_source: detect_filename_directives(src),
    class_base_type_args: [],
    no_bound_inline: false,
    target_es6_plus: detect_target_es6_plus(src),
    no_implicit_any: detect_no_implicit_any(src),
    record_implicit_any_params: false,
    class_decl_no_heritage: false,
    in_class_expr_body: false,
    written_any_params: {},
    directive_strict: detect_directive_strict(src),
    param_optional_initializer_misuses: [],
    interface_member_modifier_misuses: [],
    collected_class_dups: [],
    quoted_member_names: [],
    override_member_names: [],
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
  // The struct-spread copy shares the recording arrays with `self`, so a
  // speculative `parse_params` here would leak misuse recordings for
  // expressions that merely *look* like parameter lists (`(yield 0)` in a
  // generator, `(eval)` in strict code). Snapshot and roll back.
  let recordings = self.recording_lengths()
  let params_ok = try {
    let _ = temp.parse_params()
    temp.check(RParen)
  } catch {
    _ => false
  }
  self.rollback_recordings(recordings)
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

///|
/// True when the file's first *code* line is a `"use strict"` prologue.
/// Conformance sources routinely put `// @directive` header comments (and a
/// BOM) ahead of the prologue, so leading comment / blank lines are skipped
/// before testing -- `// @target: es5\n"use strict";` is a strict script.
fn detect_use_strict_prologue(src : String) -> Bool {
  let mut in_block_comment = false
  for line in src.split("\n") {
    let mut t = line.trim_start().to_string()
    // Strip a leading BOM the lexer would otherwise hide.
    if t.has_prefix("\u{FEFF}") {
      t = t[1:].to_string().trim_start().to_string()
    }
    if in_block_comment {
      match t.find("*/") {
        Some(i) => {
          in_block_comment = false
          t = t[i + 2:].to_string().trim_start().to_string()
        }
        None => continue
      }
    }
    while t.has_prefix("/*") {
      match t.find("*/") {
        Some(i) => t = t[i + 2:].to_string().trim_start().to_string()
        None => {
          in_block_comment = true
          break
        }
      }
    }
    if in_block_comment {
      continue
    }
    if t == "" || t.has_prefix("//") {
      continue
    }
    return t.has_prefix("\"use strict\"") || t.has_prefix("'use strict'")
  }
  false
}

///|
/// Scan the leading conformance-header directives for an explicit strict
/// opt-in: `@alwaysStrict: <values>` or `@strict: <values>` where the value
/// list contains `true`. Multi-variant directives (`@alwaysStrict: true,
/// false`) count -- at least one tsc variant runs strict, so a strict-mode
/// grammar misuse is an error in that variant's baseline.
fn detect_directive_strict(src : String) -> Bool {
  let head_len = if src.length() < 1024 { src.length() } else { 1024 }
  let head = src[:head_len].to_owned()
  for directive in ["@alwaysStrict:", "@strict:"] {
    match head.find(directive) {
      Some(i) => {
        let rest = head[i + directive.length():].to_owned()
        let line = match rest.find("\n") {
          Some(j) => rest[:j].to_owned()
          None => rest
        }
        if line.contains("true") {
          return true
        }
      }
      None => ()
    }
  }
  false
}

///|
/// Lengths of the parser's misuse-recording arrays, taken before a
/// speculative parse whose side effects must not survive.
fn Parser::recording_lengths(self : Parser) -> (Int, Int, Int, Int) {
  (
    self.grammar_misuses.length(),
    self.strict_mode_misuses.length(),
    self.param_property_misuses.length(),
    self.param_optional_initializer_misuses.length(),
  )
}

///|
/// Drop any misuse recordings pushed since `recording_lengths` was taken.
fn Parser::rollback_recordings(
  self : Parser,
  lens : (Int, Int, Int, Int),
) -> Unit {
  while self.grammar_misuses.length() > lens.0 {
    let _ = self.grammar_misuses.pop()
  }
  while self.strict_mode_misuses.length() > lens.1 {
    let _ = self.strict_mode_misuses.pop()
  }
  while self.param_property_misuses.length() > lens.2 {
    let _ = self.param_property_misuses.pop()
  }
  while self.param_optional_initializer_misuses.length() > lens.3 {
    let _ = self.param_optional_initializer_misuses.pop()
  }
}

///|
/// True when the conformance header names an ES2015+ target
/// (`@target: es6` / `es2015` .. `esnext`), in any position of the
/// comma list.
fn detect_target_es6_plus(src : String) -> Bool {
  let head_len = if src.length() < 1024 { src.length() } else { 1024 }
  let head = src[:head_len].to_owned().to_lower()
  match head.find("@target:") {
    Some(i) => {
      let rest = head[i + "@target:".length():].to_owned()
      let line = match rest.find("\n") {
        Some(j) => rest[:j].to_owned()
        None => rest
      }
      for raw in line.split(",") {
        let tok = raw.trim().to_string()
        if tok == "es6" || tok == "esnext" || tok.has_prefix("es20") {
          return true
        }
      }
      false
    }
    None => false
  }
}

///|
/// noImplicitAny from the conformance header. Default `true` (matching the
/// baselines for directive-less files); `@strict: false` /
/// `@noImplicitAny: false` opt out, explicit `@noImplicitAny: true` wins
/// over `@strict: false`.
fn detect_no_implicit_any(src : String) -> Bool {
  let head_len = if src.length() < 1024 { src.length() } else { 1024 }
  let head = src[:head_len].to_owned()
  if head.contains("@noImplicitAny: true") ||
    head.contains("@noImplicitAny:true") {
    return true
  }
  if head.contains("@noImplicitAny: false") ||
    head.contains("@noImplicitAny:false") {
    return false
  }
  if head.contains("@strict: false") || head.contains("@strict:false") {
    return false
  }
  true
}

///|
/// True when the conformance header enables `@noImplicitOverride`.
/// Default OFF (unlike noImplicitAny): tsc only checks missing `override`
/// modifiers under the explicit flag.
fn detect_no_implicit_override(src : String) -> Bool {
  let head_len = if src.length() < 1024 { src.length() } else { 1024 }
  let head = src[:head_len].to_owned()
  head.contains("@noImplicitOverride: true") ||
  head.contains("@noImplicitOverride:true")
}

///|
/// True when the conformance header enables `@allowUnreachableCode`.
/// tsc gates the TS2695 comma-operator check on this flag being off.
fn detect_allow_unreachable_code(src : String) -> Bool {
  let head_len = if src.length() < 1024 { src.length() } else { 1024 }
  let head = src[:head_len].to_owned()
  head.contains("@allowUnreachableCode: true") ||
  head.contains("@allowUnreachableCode:true")
}

///|
/// True when the source embeds `@filename:` conformance directives (any
/// case variant) -- i.e. a multi-file test concatenated into one parse.
fn detect_filename_directives(src : String) -> Bool {
  src.to_lower().contains("@filename:")
}

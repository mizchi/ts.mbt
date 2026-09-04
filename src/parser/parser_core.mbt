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
  // True while parsing a class STATIC BLOCK body. A static block is
  // neither a function nor module top level, and `in_function` /
  // `in_async` cannot say so: a top-level class's static block leaves
  // `in_function` false (which is what the TS2448 `<sb-read:>` walk
  // relies on), and a class inside an `async` function leaves `in_async`
  // true. Read by the `await using` rules (TS18054).
  mut in_static_block : Bool
  // Whether the declarator just parsed by `parse_var_decl_type` carried
  // a type ANNOTATION. The returned type cannot say: a missing
  // annotation and an explicit `: any` are both `Any`, and TS2493 needs
  // to tell them apart. Read at the top of `parse_var_decl_item`.
  mut last_var_decl_annotated : Bool
  // True while parsing the members of a `const enum`. TS2474 restricts
  // those initializers to constant expressions, and a plain `enum`
  // accepts the same initializer, so the flag is the whole difference.
  mut in_const_enum : Bool
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
  // Companion to `last_type_params_had_default`: the number of leading type
  // parameters WITHOUT a default in the list just parsed (TS requires
  // defaulted parameters to be trailing, so this is the minimum legal
  // type-argument count). `Iterable<T, TReturn = any, TNext = any>` -> 1.
  mut last_type_params_min_required : Int
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
  // `useUnknownInCatchVariables`: an unannotated `catch (e)` binding is
  // `unknown` rather than `any`, so using it without narrowing is
  // TS18046. Follows `strict`, which the conformance baselines treat as
  // ON for a directive-less file (same convention as noImplicitAny).
  unknown_catch_variables : Bool
  // True when the test header carries `@experimentaldecorators: true`
  // (legacy decorators). Parameter decorators are only legal in that
  // mode — under standard (ES) decorators they are TS1206.
  experimental_decorators : Bool
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
  // Source positions of invalid `\u` / `\x` escapes inside template
  // literals (from the lexer). Tagged templates accept invalid escapes
  // (ES2018), so only the UNTAGGED template parse site counts the
  // entries inside its token span.
  template_invalid_escape_positions : Array[Int]
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
  // TS6133: how many times each `#private` NAME is declared in this
  // file (a get/set pair counts twice — two declarations of one member).
  // Compared against the number of `PrivateIdent` tokens carrying it,
  // which is an exact upper bound on declarations + reads.
  private_decl_counts : Map[String, Int]
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
  // Interfaces declared anywhere in the module — `interface I { … }`,
  // `export interface I { … }`, `declare interface I { … }`. Erased at
  // runtime like a type alias, and threaded out the same way: the
  // escape analysis resolves a `const x: I` annotation through this to
  // decide whether `I`'s key set is closed.
  collected_interfaces : Array[@ast.TsInterface]
  // `(field name, declared type)` for every runtime class parsed in
  // this module. See `TsModuleBlock.class_fields`.
  collected_class_fields : Array[(String, @ast.TsType)]
  // Set when the module block parses `export = <expr>`.
  // Names exported with `export type { X }` — no runtime value. See
  // `TsModuleBlock.type_only_exports`.
  collected_type_only_exports : Map[String, Bool]
  mut collected_export_equals : Bool
  // Set by `parse_function` on every call: `true` when the declaration
  // it just parsed had NO body — a TypeScript overload signature or an
  // ambient `declare function`. Both are type-only and must not reach
  // the runtime statement stream; emitting them produced
  // `function f() {}` next to the real implementation, which is a
  // duplicate declaration and a SyntaxError in a module.
  mut last_function_bodiless : Bool
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
    in_static_block: false,
    last_var_decl_annotated: false,
    in_const_enum: false,
    labels: [],
    src: "",
    allow_jsx,
    class_id: 0,
    class_key_counter: 0,
    current_class_brand: None,
    last_runtime_class_decl: None,
    pending_class_base_expr: None,
    last_type_params_had_default: false,
    last_type_params_min_required: 0,
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
    unknown_catch_variables: false,
    experimental_decorators: true,
    record_implicit_any_params: false,
    class_decl_no_heritage: false,
    in_class_expr_body: false,
    written_any_params: {},
    template_invalid_escape_positions: [],
    directive_strict: false,
    param_optional_initializer_misuses: [],
    interface_member_modifier_misuses: [],
    collected_class_dups: [],
    quoted_member_names: [],
    private_decl_counts: {},
    override_member_names: [],
    pure_marker_positions: {},
    internal_marker_positions: {},
    collected_internal_names: {},
    jsdoc_at_pos: {},
    collected_deprecations: {},
    collected_pure_declarations: {},
    collected_type_aliases: [],
    collected_interfaces: [],
    collected_class_fields: [],
    collected_type_only_exports: {},
    collected_export_equals: false,
    last_function_bodiless: false,
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
  // The conformance-header detectors below all scan the same leading
  // window. Slice + lowercase it once — JSX speculation re-enters
  // `from_source_with_jsx` on sub-sources, so per-detector copies used to
  // multiply across every speculative parse.
  let head = source_head(src)
  let head_lower = head.to_lower()
  let grammar_misuses : Array[String] = []
  if lexer.invalid_char_count > 0 {
    grammar_misuses.push("invalid character in source")
  }
  if lexer.unterminated_template {
    grammar_misuses.push("unterminated template literal")
  }
  if lexer.unterminated_block_comment {
    grammar_misuses.push("`*/` expected")
  }
  if lexer.unterminated_regex {
    grammar_misuses.push("unterminated regular expression literal")
  }
  if lexer.unterminated_string {
    grammar_misuses.push("unterminated string literal")
  }
  for _i in 0..<lexer.empty_radix_literal_count {
    grammar_misuses.push("hexadecimal digit expected")
  }
  for _i in 0..<lexer.escaped_keyword_count {
    grammar_misuses.push("keywords cannot contain escape characters")
  }
  for _i in 0..<lexer.unbalanced_regex_group_count {
    grammar_misuses.push("`)` expected in a regular expression literal")
  }
  // Whole-source directive markers, collected in one pass (each used to
  // be its own full-source scan — two of them via lowered copies).
  let (has_ts_suppression, noimplicitthis_off, has_filename_directive) = scan_source_directive_flags(
    src,
  )
  // Marker: the file uses `@ts-ignore` / `@ts-expect-error` suppression
  // comments somewhere. Our issues carry no line positions, so rules
  // whose corpus counter-examples are suppressed lines (the computed-key
  // TS2465/TS1166 family) abstain for the whole file when set.
  if has_ts_suppression {
    grammar_misuses.push("<ts-suppression-present>")
  }
  // TS2683 opt-out: `@noImplicitThis: false` disables the implicit-any
  // `this` diagnostics for the file.
  if noimplicitthis_off {
    grammar_misuses.push("<noimplicitthis-off>")
  }
  for _i in 0..<lexer.invalid_radix_digit_count {
    grammar_misuses.push("invalid digit in a binary or octal numeric literal")
  }
  for _i in 0..<lexer.invalid_unicode_escape_count {
    grammar_misuses.push("hexadecimal digit expected in a unicode escape")
  }
  for _i in 0..<lexer.unicode_escape_overflow_count {
    grammar_misuses.push(
      "an extended unicode escape value must be between 0x0 and 0x10FFFF inclusive",
    )
  }
  for _i in 0..<lexer.legacy_octal_literal_count {
    grammar_misuses.push("octal literals are not allowed")
  }
  for _i in 0..<lexer.leading_zero_decimal_count {
    grammar_misuses.push("decimals with leading zeros are not allowed")
  }
  // Module-scoped flag marker for the override checks (TS4114 fires only
  // under `@noImplicitOverride: true`); TS4112/TS4113 are unconditional.
  if detect_no_implicit_override(head) {
    grammar_misuses.push("<noimplicitoverride-on>")
  }
  // TS4111 fires only under `@noPropertyAccessFromIndexSignature: true`:
  // reaching an index-signature member with dot notation is legal
  // TypeScript by default and an error only when the option asks for the
  // bracket form.
  if detect_no_property_access_from_index_signature(head) {
    grammar_misuses.push("<nopropertyaccessfromindexsignature-on>")
  }
  // TS2318 evidence: lib-set directives that provably remove global types
  // the checker requires. `@noLib: true` removes ALL of them (every ran
  // conformance case carrying it errors — parser509698); an explicit
  // `@lib:` list without a full-year ES2015+ lib (or `es2015.iterable`)
  // lacks `IterableIterator` (needed by generators —
  // generatorReturnTypeFallback.2), and one without `esnext` lacks
  // `Disposable` (needed by `using` — usingDeclarations.9).
  if detect_nolib(head_lower) {
    grammar_misuses.push("<nolib>")
  }
  match detect_lib_list(head_lower) {
    Some(libs) => {
      if !lib_list_grants_iterable(libs) {
        grammar_misuses.push("<lib-lacks-iterable>")
      }
      if !libs.contains("esnext") {
        grammar_misuses.push("<lib-lacks-esnext>")
      }
      if !lib_list_grants_year(libs, 2017) {
        grammar_misuses.push("<lib-lacks-es2017>")
      }
      if !lib_list_grants_year(libs, 2024) {
        grammar_misuses.push("<lib-lacks-es2024>")
      }
    }
    None =>
      // No explicit `@lib:` — the default lib follows the target, so an
      // explicit `@target:` list capped below es2017 also lacks the
      // es2017 surface (useObjectValuesAndEntries3's `@target: es6`).
      match detect_target_list(head_lower) {
        Some(targets) =>
          if !target_list_reaches_es2017(targets) {
            grammar_misuses.push("<lib-lacks-es2017>")
          }
        None => ()
      }
  }
  // TS2854 evidence: a top-level `await using` needs target >= es2017;
  // conformance files list their variant targets in one directive.
  match detect_target_list(head_lower) {
    Some(targets) =>
      if target_list_has_below_es2017(targets) {
        grammar_misuses.push("<target-below-es2017>")
      }
    None => ()
  }
  // TS1346 / TS1347 evidence: a `"use strict"` prologue in a function with
  // a non-simple parameter list is an error only from es2016 up. Below
  // that TypeScript downlevels the default / rest / pattern parameter, so
  // the EMITTED list is simple and the directive is fine — probed at es5,
  // es2015 (both accepted) and es2016 (both codes).
  //
  // A file with NO `@target:` is deliberately left OFF even though tsc
  // 6.0.3 reports both codes for one, because that says the local
  // compiler's default target is es2016 or later and says nothing about
  // TS7's. Guessing wrong there fires on every directive-less file in the
  // corpus, so the abstention costs a MISS where the guess could cost a
  // false positive.
  match detect_target_list(head_lower) {
    Some(targets) =>
      if target_list_reaches_year(targets, 2016) {
        grammar_misuses.push("<target-reaches-es2016>")
      }
    None => ()
  }
  // Decorator-mode marker so checker-side decorator signature rules can
  // pick the runtime invocation arity (legacy = 1 arg, standard = 2).
  let experimental_decorators = detect_experimental_decorators(head_lower)
  if experimental_decorators {
    grammar_misuses.push("<experimental-decorators>")
  }
  // TS2354 evidence: `@importHelpers: true` makes an emit helper an
  // IMPORT from `tslib`, which the single-file checker can never resolve.
  // Only the conformance header spelling sets this, so real-world code
  // (where the option lives in a tsconfig) cannot reach the diagnostic.
  if detect_import_helpers(head) {
    grammar_misuses.push("<import-helpers>")
  }
  // Marker for the TS2695 comma-operator check, which tsc disables under
  // `@allowUnreachableCode: true`.
  if detect_allow_unreachable_code(head) {
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
    in_static_block: false,
    last_var_decl_annotated: false,
    in_const_enum: false,
    labels: [],
    src,
    allow_jsx,
    class_id: 0,
    class_key_counter: 0,
    current_class_brand: None,
    last_runtime_class_decl: None,
    pending_class_base_expr: None,
    last_type_params_had_default: false,
    last_type_params_min_required: 0,
    local_type_param_bounds: [],
    pending_decorators: [],
    param_property_scopes: [],
    param_property_misuses: [],
    strict_mode_misuses: [],
    invalid_decorator_uses: [],
    grammar_misuses,
    imported_binding_names: [],
    import_module_specs: [],
    multi_file_source: has_filename_directive,
    class_base_type_args: [],
    no_bound_inline: false,
    target_es6_plus: detect_target_es6_plus(head_lower),
    no_implicit_any: detect_no_implicit_any(head),
    unknown_catch_variables: detect_unknown_catch_variables(head),
    experimental_decorators,
    template_invalid_escape_positions: lexer.template_invalid_escape_positions,
    record_implicit_any_params: false,
    class_decl_no_heritage: false,
    in_class_expr_body: false,
    written_any_params: {},
    directive_strict: detect_directive_strict(head),
    param_optional_initializer_misuses: [],
    interface_member_modifier_misuses: [],
    collected_class_dups: [],
    quoted_member_names: [],
    private_decl_counts: {},
    override_member_names: [],
    pure_marker_positions: lexer.pure_marker_positions,
    internal_marker_positions: lexer.internal_marker_positions,
    collected_internal_names: {},
    jsdoc_at_pos: lexer.jsdoc_at_pos,
    collected_deprecations: {},
    collected_pure_declarations: {},
    collected_type_aliases: [],
    collected_interfaces: [],
    collected_class_fields: [],
    collected_type_only_exports: {},
    collected_export_equals: false,
    last_function_bodiless: false,
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
  // `is Eof` rather than `!= Eof`: the derived `TokenKind::equal` is an
  // out-of-line call over an enum with payloads, and `advance` runs once
  // per token in the file. A pattern test is a tag compare.
  if !(tok.kind is Eof) {
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
fn detect_directive_strict(head : String) -> Bool {
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
/// Exact match of `needle` against `src` starting at position `i`.
fn matches_at(src : String, i : Int, needle : String) -> Bool {
  let n = needle.length()
  if i + n > src.length() {
    return false
  }
  for j in 0..<n {
    if src[i + j] != needle[j] {
      return false
    }
  }
  true
}

///|
/// ASCII-case-insensitive match of lowercase-ASCII `needle` against
/// `src` starting at position `i` (code-unit compare, A-Z folded).
fn matches_ascii_ci_at(src : String, i : Int, needle : String) -> Bool {
  let n = needle.length()
  if i + n > src.length() {
    return false
  }
  for j in 0..<n {
    let mut c = src[i + j].to_int()
    if c >= 65 && c <= 90 {
      c = c + 32
    }
    if c != needle[j].to_int() {
      return false
    }
  }
  true
}

///|
/// One pass over the whole source collecting every marker that
/// `from_source_with_jsx` needs from arbitrary positions:
///
///   .0  `@ts-ignore` / `@ts-expect-error` (case-sensitive)
///   .1  `@noImplicitThis:` + optional single space + `false`
///       (case-insensitive)
///   .2  `@filename:` (case-insensitive)
///
/// All markers start with `@`, so the scan only inspects positions whose
/// code unit is `@`. Replaces five separate full-source scans, two of
/// which lowered a full mutable copy of the source per call.
fn scan_source_directive_flags(src : String) -> (Bool, Bool, Bool) {
  let mut suppression = false
  let mut noimplicitthis_off = false
  let mut filename = false
  let at_code = '@'.to_int()
  let m = src.length()
  for i in 0..<m {
    if src[i].to_int() != at_code {
      continue
    }
    if !suppression &&
      (
        matches_at(src, i, "@ts-ignore") ||
        matches_at(src, i, "@ts-expect-error")
      ) {
      suppression = true
    }
    if !noimplicitthis_off && matches_ascii_ci_at(src, i, "@noimplicitthis:") {
      let mut j = i + "@noimplicitthis:".length()
      if j < m && src[j].to_int() == ' '.to_int() {
        j += 1
      }
      if matches_ascii_ci_at(src, j, "false") {
        noimplicitthis_off = true
      }
    }
    if !filename && matches_ascii_ci_at(src, i, "@filename:") {
      filename = true
    }
    if suppression && noimplicitthis_off && filename {
      break
    }
  }
  (suppression, noimplicitthis_off, filename)
}

///|
/// The leading window the conformance-header detectors scan: the first
/// 1024 UTF-16 code units of the source, as an owned string. Computed
/// once per `from_source_with_jsx` and threaded through every detector.
fn source_head(src : String) -> String {
  let head_len = if src.length() < 1024 { src.length() } else { 1024 }
  src[:head_len].to_owned()
}

///|
/// True when the conformance header names an ES2015+ target
/// (`@target: es6` / `es2015` .. `esnext`), in any position of the
/// comma list. `head` is the pre-lowered leading window.
fn detect_target_es6_plus(head : String) -> Bool {
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
/// over `@strict: false`. `head` is the (case-preserved) leading window.
fn detect_no_implicit_any(head : String) -> Bool {
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
/// modifiers under the explicit flag. `head` is the case-preserved window.
fn detect_no_implicit_override(head : String) -> Bool {
  head.contains("@noImplicitOverride: true") ||
  head.contains("@noImplicitOverride:true")
}

///|
/// True when the conformance header enables
/// `@noPropertyAccessFromIndexSignature`. `head` is the case-preserved
/// leading window.
fn detect_no_property_access_from_index_signature(head : String) -> Bool {
  head.contains("@noPropertyAccessFromIndexSignature: true") ||
  head.contains("@noPropertyAccessFromIndexSignature:true")
}

///|
/// True when the conformance header enables `@importHelpers`. `head` is
/// the case-preserved leading window.
fn detect_import_helpers(head : String) -> Bool {
  head.contains("@importHelpers: true") || head.contains("@importHelpers:true")
}

///|
/// True when an unannotated `catch (e)` binding is `unknown` rather than
/// `any` (TS18046). Follows `strict`: ON unless explicitly disabled.
///
/// A multi-valued directive (`@useUnknownInCatchVariables: true,false`)
/// counts as ON, because the harness runs each variant and the file has
/// errors if ANY run does — `controlFlowAliasingCatchVariables` is
/// exactly that spelling.
fn detect_unknown_catch_variables(head : String) -> Bool {
  if head.contains("@useUnknownInCatchVariables: true") ||
    head.contains("@useUnknownInCatchVariables:true") {
    return true
  }
  if head.contains("@useUnknownInCatchVariables: false") ||
    head.contains("@useUnknownInCatchVariables:false") {
    return false
  }
  if head.contains("@strict: false") || head.contains("@strict:false") {
    return false
  }
  true
}

///|
/// True when the conformance header enables `@noUnusedLocals`. Default
/// OFF, matching the compiler. `head` is the case-preserved window.
fn detect_no_unused_locals(head : String) -> Bool {
  head.contains("@noUnusedLocals: true") ||
  head.contains("@noUnusedLocals:true")
}

///|
/// True when the conformance header enables `@allowUnreachableCode`.
/// tsc gates the TS2695 comma-operator check on this flag being off.
/// `head` is the case-preserved leading window.
fn detect_allow_unreachable_code(head : String) -> Bool {
  head.contains("@allowUnreachableCode: true") ||
  head.contains("@allowUnreachableCode:true")
}

///|
/// True when the leading test-header directives set `@noLib: true`.
/// `head` is the pre-lowered leading window.
fn detect_nolib(head : String) -> Bool {
  match head.find("@nolib:") {
    Some(idx) => {
      let after = head[idx + "@nolib:".length():].to_owned()
      let line = match after.find("\n") {
        Some(nl) => after[:nl].to_owned()
        None => after
      }
      line.trim().to_owned().has_prefix("true")
    }
    None => false
  }
}

///|
/// The raw (lower-cased, comma-separated) `@lib:` directive value from the
/// test-header comment block, if present. `head` is the pre-lowered window.
fn detect_lib_list(head : String) -> String? {
  match head.find("@lib:") {
    Some(idx) => {
      let after = head[idx + "@lib:".length():].to_owned()
      let line = match after.find("\n") {
        Some(nl) => after[:nl].to_owned()
        None => after
      }
      Some(line.trim().to_owned())
    }
    None => None
  }
}

///|
/// Whether an explicit `@lib:` list provides `IterableIterator`: any
/// full-year ES2015+ lib (`es2015` .. `es2024`, no dot suffix), `es6`,
/// `esnext`, or the targeted `es2015.iterable` / `es2015.generator`
/// slices. `es5` / `es2015.promise` etc. do NOT.
fn lib_list_grants_iterable(libs : String) -> Bool {
  for tok in libs.split(",") {
    let t = tok.to_string().trim().to_owned()
    if t == "es6" ||
      t == "esnext" ||
      t == "es2015.iterable" ||
      t == "es2015.generator" ||
      (t.has_prefix("es20") && !t.contains(".")) {
      return true
    }
  }
  false
}

///|
/// The raw (lower-cased, comma-separated) `@target:` directive value, if
/// present. `head` is the pre-lowered leading window.
fn detect_target_list(head : String) -> String? {
  match head.find("@target:") {
    Some(idx) => {
      let after = head[idx + "@target:".length():].to_owned()
      let line = match after.find("\n") {
        Some(nl) => after[:nl].to_owned()
        None => after
      }
      Some(line.trim().to_owned())
    }
    None => None
  }
}

///|
/// Year number of an `es20NN` token; `es6` maps to 2015, `esnext` to 9999.
/// `None` for anything else (`es5`, `es3`, dotted slices, `dom`, ...).
fn es_token_year(t : String) -> Int? {
  if t == "esnext" {
    return Some(9999)
  }
  if t == "es6" {
    return Some(2015)
  }
  if t.has_prefix("es20") && !t.contains(".") && t.length() == 6 {
    let mut y = 0
    for c in t.substring(start=2) {
      if c < '0' || c > '9' {
        return None
      }
      y = y * 10 + (c.to_int() - '0'.to_int())
    }
    return Some(y)
  }
  None
}

///|
/// Whether an explicit `@lib:` list provides the ES-`year` surface: a
/// full-year lib at or past `year`, `esnext`, or a dotted slice of that
/// exact year (`es2017.object` grants 2017).
fn lib_list_grants_year(libs : String, year : Int) -> Bool {
  for tok in libs.split(",") {
    let t = tok.to_string().trim().to_owned()
    match es_token_year(t) {
      Some(y) => if y >= year { return true }
      None => if t.has_prefix("es" + year.to_string() + ".") { return true }
    }
  }
  false
}

///|
/// True when any token of the `@target:` list names ES-`year` or later.
///
/// The harness runs a comma list once per entry and the file counts as
/// erroring if ANY run errors, so a rule that fires at HIGH targets asks
/// this (does some run reach the year) and a rule that fires at LOW ones
/// asks `target_list_has_below_year`. Parameterised because it was
/// written out twice at 2017 before a third year needed it.
fn target_list_reaches_year(targets : String, year : Int) -> Bool {
  for tok in targets.split(",") {
    let t = tok.to_string().trim().to_owned()
    match es_token_year(t) {
      Some(y) => if y >= year { return true }
      None => ()
    }
  }
  false
}

///|
fn target_list_reaches_es2017(targets : String) -> Bool {
  target_list_reaches_year(targets, 2017)
}

///|
fn target_list_has_below_es2017(targets : String) -> Bool {
  for tok in targets.split(",") {
    let t = tok.to_string().trim().to_owned()
    if t == "es5" || t == "es3" {
      return true
    }
    match es_token_year(t) {
      Some(y) => if y < 2017 { return true }
      None => ()
    }
  }
  false
}

///|
/// `@experimentalDecorators: true` from the pre-lowered leading window.
fn detect_experimental_decorators(head : String) -> Bool {
  match head.find("@experimentaldecorators:") {
    Some(idx) => {
      let after = head[idx + "@experimentaldecorators:".length():].to_owned()
      let line = match after.find("\n") {
        Some(nl) => after[:nl].to_owned()
        None => after
      }
      line.trim().to_owned().has_prefix("true")
    }
    None => false
  }
}

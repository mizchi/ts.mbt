// ============================================
// statement
// ============================================

///|
/// Variable declaration kind
priv enum VarKind {
  Var // function-scoped
  Let // block-scoped
  Const // block-scoped, immutable
}

///|
fn Parser::is_namespace_decl_start(self : Parser) -> Bool {
  match self.peek().kind {
    Ident(name) =>
      match name {
        "global" => self.peek_at(1).kind == LBrace
        "namespace" | "module" =>
          // ASI: TS only treats `namespace` / `module` as a declaration
          // keyword when the name follows on the SAME line
          // (asiPreventsParsingAsNamespace01/02). A newline makes it a
          // plain identifier reference.
          if self.peek_at(1).has_newline_before {
            false
          } else {
            match self.peek_at(1).kind {
              Ident(_) | Str(_) | LBrace => true
              // Primitive type keywords are legal namespace names
              // (`namespace number {}` — parserModuleDeclaration6/7).
              NumberType | StringType | BooleanType | IntType => true
              _ => false
            }
          }
        _ => false
      }
    _ => false
  }
}

///|
/// Record an always-error grammar misuse, unless the file carries an
/// `@ts-ignore` / `@ts-expect-error` suppression comment somewhere.
///
/// `@ts-ignore` suppresses the diagnostic on the FOLLOWING line only, and
/// our issues carry no line positions, so file granularity is the only
/// false-positive-safe reading — the same choice the TS2465 / TS1166 family
/// already makes. The marker is pushed at parser construction, before any
/// statement is parsed, so it is always visible here.
///
/// This is not hypothetical caution: `topLevelVarHoistingCommonJS.ts` is a
/// TS7-ACCEPTED file whose `with (_)` block is preceded by `// @ts-ignore`,
/// and recording the `with` diagnostic unconditionally made it the corpus's
/// only false positive.
fn Parser::record_suppressible_grammar_misuse(
  self : Parser,
  message : String,
) -> Unit {
  if self.grammar_misuses.contains("<ts-suppression-present>") {
    return
  }
  self.grammar_misuses.push(message)
}

///|
/// TS2378 ("A 'get' accessor must return a value") for an OBJECT-LITERAL
/// getter with an empty body — `var v = { get Foo() { } }`.
///
/// `check_getter_returns_value` in the checker already answers this for
/// CLASS getters, with a careful set of abstentions (a `throw`, a loop, a
/// bare `return;`, a return annotation that accepts `undefined`). It reads
/// `module_.classes` and nothing else, so the object-literal spelling was
/// never covered — and its own doc comment names the `parserAccessors`
/// cluster, two of whose files (`parserAccessors3`, `parserES3Accessors3`)
/// are exactly `var v = { get Foo() { } }`.
///
/// Restricted here to the EMPTY body, which is why none of those
/// abstentions need repeating: a body with no statements has no `throw`, no
/// loop and no `return` of either kind. A non-empty object-literal getter
/// abstains rather than duplicating the checker's flow logic — that
/// duplication is the mistake this batch keeps finding. The two accessor
/// parse paths share this helper for the same reason: TS1054 / TS1049 are
/// written out at both of them.
///
/// `had_annotation` is required because the parser stores a MISSING return
/// annotation as `Any`, which is indistinguishable from an explicit
/// `: any` once in the AST — and an explicit `: any` / `: void` /
/// `: undefined` / `: unknown` makes falling off the end well-typed, so tsc
/// raises nothing there.
/// TS1117 ("An object literal cannot have multiple properties with the same
/// name"). Placed where `fields` is complete, which is the one site an
/// object literal is finished at.
///
/// Three shapes deliberately do NOT count as duplicates, and each is legal
/// TypeScript rather than an abstention:
///   - a `get x` / `set x` PAIR, which the parser keys as `@@get:x` and
///     `@@set:x`. Two getters of one name is a duplicate, and comparing the
///     prefixed keys gives that for free;
///   - a SPREAD entry, whose key is a sentinel rather than a name, and
///     which may legally supply a key another entry also writes
///     (`{ ...o, a: 1 }` is the standard override idiom);
///   - a COMPUTED key whose expression we cannot spell, stored as
///     `@@computed:<index>`. Those can never compare equal to each other
///     because the index differs per entry, so they cost nothing here.
/// Any key beginning with `<` or `@@` other than the accessor prefixes is
/// therefore skipped, which is the same sentinel convention
/// `parse_var_like`'s TS2850 check already reads.
///
/// A WELL-KNOWN-SYMBOL computed key is the exception, and it is the one
/// this comment used to record as a deliberate MISS: `{
/// [Symbol.isConcatSpreadable]: 0, [Symbol.isConcatSpreadable]: 1 }`
/// (`symbolProperty36`) IS a duplicate, because `Symbol.isConcatSpreadable`
/// names one specific symbol. The blocker written down here was that only
/// the CLASS key path resolves such a key to a stable `@@<name>`, and
/// renaming the object-literal key would move keys the mangler and the
/// dead-property pass read. That was true of the approach and beside the
/// point: the parser wraps a computed entry's VALUE as
/// `ComputedProp(key_expr, value)`, so the key expression is already here
/// and nothing has to be renamed to compare it. Arbitrary key expressions
/// stay opaque — two calls to the same function may well produce two
/// different symbols — so only the `Symbol.<wk>` shape gets a name.
fn Parser::record_objlit_duplicate_keys(
  self : Parser,
  fields : Array[(String, @ast.TsExpr)],
) -> Unit {
  let seen : Map[String, Unit] = {}
  let reported : Map[String, Unit] = {}
  for f in fields {
    let k = match (f.0.has_prefix("@@computed:"), f.1) {
      (true, ComputedProp(PropAccess(Var("Symbol"), wk), _)) => "@@wk:" + wk
      _ => f.0
    }
    // Sentinel keys (spread, computed, and anything else the parser cannot
    // spell) are not comparable names. The accessor prefixes ARE, and they
    // distinguish a getter from a setter of the same name, which is why
    // they are compared as-is rather than stripped.
    if k.has_prefix("<") ||
      (
        k.has_prefix("@@") &&
        not(k.has_prefix("@@get:")) &&
        not(k.has_prefix("@@set:")) &&
        not(k.has_prefix("@@wk:"))
      ) {
      continue
    }
    if seen.contains(k) && not(reported.contains(k)) {
      reported[k] = ()
      self.grammar_misuses.push(
        "an object literal cannot have multiple properties with the same name",
      )
    }
    seen[k] = ()
  }
}

///|
fn Parser::record_objlit_getter_returns(
  self : Parser,
  is_getter : Bool,
  had_annotation : Bool,
  return_type : @ast.TsType,
  body : @ast.TsBlock,
) -> Unit {
  if not(is_getter) || body.stmts.length() > 0 {
    return
  }
  if had_annotation {
    match return_type {
      Any | Unknown | Void | Undefined | Null => return
      _ => ()
    }
  }
  self.grammar_misuses.push("a `get` accessor must return a value")
}

///|
/// Push a label onto the active-label stack, recording TS1114 ("Duplicate
/// label") when one of that name is already active.
///
/// `self.labels` is already scoped exactly the way the rule is, which is why
/// no new state is needed: it is pushed on entering a labelled statement and
/// popped on leaving it, so two SEQUENTIAL labels of one name never collide
/// (parser_duplicateLabel4 — legal), and every function-body parse site
/// saves, clears and restores the whole stack, so a name re-used inside a
/// nested function does not collide either (parser_duplicateLabel3 — legal).
/// Both of those are TS7-ACCEPTED files, which is what makes this check
/// false-positive-free rather than merely untested.
///
/// A function rather than two copies of the test: labels are entered at two
/// sites (a plain identifier and the non-strict `yield:` spelling), and a
/// rule written at one of two spellings is how `eval++` went unchecked for
/// as long as it did.
fn Parser::enter_label(self : Parser, name : String) -> Unit {
  if self.has_label(name) {
    self.record_suppressible_grammar_misuse("duplicate label `\{name}`")
  }
  // `break` may target ANY label; `continue` only an ITERATION one
  // (TS1115), so the stack has to carry which kind each entry is. It is
  // encoded in the entry rather than kept in a second array on purpose:
  // fourteen sites in three files save, clear and restore `self.labels`
  // around a function body, and a parallel field would have to be threaded
  // through every one of them — which is precisely the "written in several
  // places, updated in some" shape this file keeps recording. A prefix
  // rides along through an opaque copy for free.
  self.labels.push(
    (if self.label_targets_iteration() { "i:" } else { "n:" }) + name,
  )
}

///|
/// Is the cursor — positioned just after a label's `:` — at an ITERATION
/// statement?
///
/// A label chain counts: in `outer: inner: while (c) …` both labels label
/// the `while`, so `continue outer` is legal. The chain is skipped by
/// lookahead rather than by recursion because `enter_label` runs before the
/// labelled statement is parsed, which is the only point where the
/// distinction is still cheap.
fn Parser::label_targets_iteration(self : Parser) -> Bool {
  let mut i = 0
  // `Yield` as well as `Ident`: the non-strict `yield:` spelling is a
  // second way to write a label, and a chain may mix them.
  while self.peek_at(i).kind is (Ident(_) | Yield) &&
        self.peek_at(i + 1).kind is Colon {
    i += 2
  }
  match self.peek_at(i).kind {
    For | While | Do => true
    _ => false
  }
}

///|
/// Is `name` an active label of any kind? Answers `break`'s question.
fn Parser::has_label(self : Parser, name : String) -> Bool {
  self.labels.contains("i:" + name) || self.labels.contains("n:" + name)
}

///|
/// Is `name` an active label on an ITERATION statement? Answers
/// `continue`'s narrower question (TS1115): `target: continue target;`
/// names a live label and still cannot be continued to, because a labelled
/// expression statement is not a loop (`parser_continueTarget1`).
fn Parser::has_iteration_label(self : Parser, name : String) -> Bool {
  self.labels.contains("i:" + name)
}

///|
/// TS2391 ("Function implementation is missing or not immediately following
/// the declaration").
///
/// Called for every function declaration the statement stream produces,
/// with whether it had a body. Several overload signatures may stack above
/// ONE implementation and they must all name the same function, so what
/// has to be true after a bodyless declaration is simply that the NEXT
/// declaration is a function of the same name — either another signature
/// or the implementation.
///
/// That is answered by LOOKAHEAD rather than by carrying a pending-run
/// across statements, and the difference is not stylistic. The first
/// version kept the run on the parser and flushed it whenever
/// `parse_stmt` saw something that was not a function declaration — which
/// fires for the statements INSIDE a nested function body too, because
/// `parse_function` parses the body through the same funnel. So a
/// perfectly legal three-signature set inside another function
/// (`recursiveTypesUsedAsFunctionParameters`, TS7-ACCEPTED) reported the
/// run the moment the implementation's own `return null;` was parsed. A
/// scope-saved field would have had to be threaded through every
/// save/restore site around a function body — the shape this file keeps
/// recording — and the lookahead needs no scope model at all.
///
/// Silent in an ambient context, where a bodyless declaration asserts an
/// implementation exists elsewhere and is the normal spelling — that is
/// the whole content of a `.d.ts`. Silent, too, when the follower is
/// `export` or `declare`: an exported overload set is parsed elsewhere, so
/// the name is not visible from here and abstaining costs a MISS rather
/// than risking a false positive.
fn Parser::note_function_declaration(
  self : Parser,
  name : String,
  bodiless : Bool,
  module_level : Bool,
) -> Unit {
  // TS2394 support: `<fn-impl:NAME>` says this module declares a function
  // IMPLEMENTATION of that name. `TsFunc.body` is not optional, so an
  // overload SIGNATURE and an implementation are indistinguishable
  // downstream — the blocker this repo records for TS2393 / TS2394 — and
  // `bodiless` is exactly the missing fact, available here, at every one
  // of the four sites that pushes a function declaration.
  //
  // `module_level` is true only at the two sites the module / namespace
  // body loop owns, and the marker is pushed nowhere else. That matters
  // because `grammar_misuses` is a FLAT, scope-blind channel: a nested
  // `function f() { }` would otherwise record an implementation for a
  // name that only exists inside another function's body, and the only
  // consumer reads it against `module_.funcs`, which holds this body's
  // OWN declarations. A nested overload set never reaches `funcs` at all,
  // so the restriction gives up nothing.
  //
  // Ambient bodiless declarations are excluded for the same reason as
  // below: in a `declare module` body a bodiless declaration asserts an
  // implementation elsewhere and no local one exists to compare against.
  if module_level && not(bodiless) && not(self.in_ambient_module) {
    self.grammar_misuses.push("<fn-impl:\{name}>")
  }
  if not(bodiless) || self.in_ambient_module {
    return
  }
  // Offset of the follower's NAME token, or `None` when the follower is
  // not a function declaration at all (`}`, `var`, end of file).
  let name_at = match self.peek().kind {
    Export | Declare => return
    Function => if self.peek_at(1).kind is Star { Some(2) } else { Some(1) }
    Ident("async") =>
      if self.peek_at(1).kind is Function {
        if self.peek_at(2).kind is Star {
          Some(3)
        } else {
          Some(2)
        }
      } else {
        None
      }
    _ => None
  }
  let follows = match name_at {
    Some(i) => self.peek_at(i).kind is Ident(n) && n == name
    None => false
  }
  if not(follows) {
    self.record_suppressible_grammar_misuse(
      "function implementation is missing or not immediately following the declaration for `\{name}`",
    )
  }
}

///|
// / statement
pub fn Parser::parse_stmt(self : Parser) -> @ast.TsStmt raise ParseError {
  let tok = self.peek()
  match tok.kind {
    Slash => {
      // A `/` in statement position starts a regex literal; the prelexer
      // classified it as division because the previous token was a
      // block's closing `}` (`{a: 3}` then `/x/` — parser768531). Re-lex
      // the span from the source text with a fresh regex-allowing lexer,
      // overwrite the last covered token slot with the regex token, and
      // reparse so postfix expressions (`/x/.test(s)`) still work.
      let start = tok.pos
      let rest = self.src[start:self.src.length()].to_owned()
      let relexer = Lexer::new(rest)
      let relexed = relexer.next_token()
      match relexed.kind {
        Regex(_, flags) => {
          // TS1499: only `d g i m s u v y` are regular-expression flags
          // (`if (1) /regexp/a.foo()` —
          // parserRegularExpressionDivideAmbiguity3).
          for c in flags {
            if !"dgimsuvy".contains_char(c) {
              self.grammar_misuses.push("unknown regular expression flag")
              break
            }
          }
          let end_pos = start + relexer.pos
          let mut k = self.pos
          while k + 1 < self.tokens.length() && self.tokens[k + 1].pos < end_pos {
            k += 1
          }
          self.tokens[k] = {
            kind: relexed.kind,
            pos: start,
            has_newline_before: tok.has_newline_before,
          }
          self.pos = k
          self.parse_stmt()
        }
        _ => raise ParseError("Unexpected token: Slash")
      }
    }
    At => {
      self.skip_decorator()
      // TS1206: at statement level a decorator can only precede a class
      // declaration (or further decorators / modifiers). Anything else
      // orphans the pending group.
      if self.pending_decorators.length() > 0 {
        let can_take_decorators = match self.peek().kind {
          Class | Export | At | Declare => true
          Ident("abstract") => true
          _ => false
        }
        if !can_take_decorators {
          self.invalid_decorator_uses.push("statement")
          self.pending_decorators.clear()
        }
      }
      self.parse_stmt()
    }
    Var => self.parse_var()
    Let =>
      if self.is_let_identifier_expr_start() {
        self.parse_assign_or_expr()
      } else {
        self.parse_let()
      }
    // `using x = expr;` and `await using x = expr;` (ES2023). Treat as a
    // `let` declaration for parsing — the auto-disposal semantics don't
    // affect the type-level shape.
    Ident("using") if self.is_using_declaration_start() => {
      let kw_pos = self.peek().pos
      let _ = self.advance()
      self.parse_var_like(VarKind::Let, kw_pos, using_kw="using")
    }
    Ident("await") if self.peek_at(1).kind is Ident("using") &&
      self.is_await_using_declaration_start() => {
      let kw_pos = self.peek().pos
      let _ = self.advance() // `await`
      let _ = self.advance() // `using`
      self.parse_var_like(VarKind::Let, kw_pos, using_kw="await using")
    }
    Const =>
      match self.peek_at(1).kind {
        Ident(name) if name == "enum" => {
          // `const enum E { … }` at stmt level. Parse the decl and
          // lower to runtime statements (var + IndexAssigns)
          // wrapped in a `Block` so the caller's `Array[TsStmt]`
          // sees a single stmt. The const-enum is treated like
          // a regular enum for emit purposes — actual inlining at
          // use sites would require call-graph analysis we
          // don't do yet.
          let decl = self.parse_const_enum_decl(false)
          Block({
            stmts: lower_enum_decl_to_runtime_stmts(decl),
            stmt_positions: [],
          })
        }
        _ => self.parse_const()
      }
    Return => self.parse_return()
    Throw => self.parse_throw()
    // A class declared as a STATEMENT — in a function body, a block, an
    // `if` branch. The module-level dispatcher has its own `Class` branch
    // and never reaches here, so this arm sees exactly the positions
    // `TsModule.classes` cannot: `record_local_class` collects them for
    // the checker's class rules, which were silent one scope in.
    Class => {
      let stmt = self.parse_class_decl()
      self.record_local_class()
      stmt
    }
    Ident("abstract") if self.peek_at(1).kind == Class => {
      let _ = self.advance()
      let stmt = self.parse_class_decl_with_abstract(true)
      self.record_local_class()
      stmt
    }
    Interface => {
      // Erased at runtime, collected for the same reason type aliases
      // are: a later pass has to be able to resolve an annotation that
      // names this interface.
      self.collected_interfaces.push(self.parse_interface())
      Empty
    }
    Type if self.peek_at(1).kind is Ident(_) => {
      // `type Foo = …` / `type Foo<…> = …` — type alias decl.
      // Type aliases are erased at runtime; collect them so the
      // checker / bridge passes can still resolve the name.
      // Other follow-ups (`type.foo = …`, `type[i] = …`, `type()`,
      // `type;`) leave `type` as a plain identifier so the
      // expression-statement parser below picks it up.
      self.collected_type_aliases.push(self.parse_type_alias())
      Empty
    }
    _ if self.is_namespace_decl_start() =>
      // `namespace N { … }` declares a runtime object; lower it so the
      // body's exported members exist. Forms the lowering doesn't model
      // (ambient module names, dotted paths, `global { … }`) fall back
      // to the old skip.
      match self.parse_lowered_namespace() {
        Some(lowered) => lowered.stmt
        None => {
          self.skip_declaration_block()
          Empty
        }
      }
    Ident(name) if name == "enum" => {
      // Plain `enum E { … }` at stmt level. Parse + lower inline
      // so the resulting `var E = {}; …` lands in the runtime block.
      let decl = self.parse_enum_decl_after_enum_keyword(false, false)
      Block({
        stmts: lower_enum_decl_to_runtime_stmts(decl),
        stmt_positions: [],
      })
    }
    If => self.parse_if()
    Switch => self.parse_switch()
    With => self.parse_with()
    Debugger => self.parse_debugger()
    Do => self.parse_do_while()
    While => self.parse_while()
    For => self.parse_for()
    Try => self.parse_try()
    Ident("async") if self.peek_at(1).kind == Function &&
      !self.has_line_terminator_after() => {
      let _ = self.advance()
      // `parse_function` reads `in_async` to learn whether the function it
      // is about to parse is async, and saves / restores it around the
      // BODY itself — so this site only has to hand it the answer and put
      // back whatever was there. Clearing it to `false` unconditionally
      // (which is what this did) turned the rest of an enclosing async
      // body non-async the moment it declared a nested `async function`.
      let prev_async = self.in_async
      self.in_async = true
      let func = self.parse_function()
      self.in_async = prev_async
      self.note_function_declaration(
        func.name,
        self.last_function_bodiless,
        false,
      )
      if self.last_function_bodiless {
        Empty
      } else {
        Let(@ast.TsBinding::Ident(func.name), Any, FuncExpr(func))
      }
    }
    Function => {
      // internalfunctiondefine: function name() { ... }
      // Let(name, Any, FuncExpr(func))
      let func = self.parse_function()
      self.note_function_declaration(
        func.name,
        self.last_function_bodiless,
        false,
      )
      // A bodyless declaration is an overload signature or an ambient
      // `declare function`: type-only, and there can be several of them
      // above the one real implementation. Emitting each as
      // `function f() {}` put two or three declarations of one name in
      // the output — a SyntaxError in a module, so nothing loaded.
      // valibot writes its whole public surface as overload sets.
      if self.last_function_bodiless {
        Empty
      } else {
        Let(@ast.TsBinding::Ident(func.name), Any, FuncExpr(func))
      }
    }
    Break => {
      let _ = self.advance()
      // ASI: line terminator after break means no label
      let label = if self.has_line_terminator_before() {
        None
      } else {
        match self.peek().kind {
          Ident(_) =>
            match self.advance().kind {
              Ident(name) => Some(name)
              _ => None
            }
          _ => None
        }
      }
      // Check if break is inside iteration or switch (or has valid label)
      match label {
        None =>
          if !self.in_iteration && !self.in_switch {
            raise ParseError("Illegal break statement")
          }
        Some(name) =>
          // Check if label exists
          if !self.has_label(name) {
            raise ParseError("Undefined label '\{name}'")
          }
      }
      self.consume_semicolon()
      Break(label)
    }
    Continue => {
      let _ = self.advance()
      // ASI: line terminator after continue means no label
      let label = if self.has_line_terminator_before() {
        None
      } else {
        match self.peek().kind {
          Ident(_) =>
            match self.advance().kind {
              Ident(name) => Some(name)
              _ => None
            }
          _ => None
        }
      }
      // Check if continue is inside iteration (or has valid label for an iteration)
      match label {
        None =>
          if !self.in_iteration {
            raise ParseError("Illegal continue statement")
          }
        Some(name) =>
          // TS1115: the label must exist AND must label an iteration
          // statement. An undefined label is a hard parse error (tsc
          // recovers, we reject); a label that exists but is not on a loop
          // is a recorded diagnostic, so the rest of the file still parses.
          if !self.has_label(name) {
            raise ParseError("Undefined label '\{name}'")
          } else if !self.has_iteration_label(name) {
            self.record_suppressible_grammar_misuse(
              "a `continue` statement can only jump to a label of an enclosing iteration statement",
            )
          }
      }
      self.consume_semicolon()
      Continue(label)
    }
    Semicolon => {
      let _ = self.advance()
      // TS1036 evidence: a bare `;` is an EMPTY STATEMENT, and a statement
      // of any kind is illegal in an ambient (`.d.ts`) file — at top level
      // and inside a `declare namespace` body alike. The `;` that
      // separates interface or class members is not a statement and never
      // reaches here.
      //
      // Recorded as a marker rather than added to the statement-kind list
      // in `check_dts_top_level_modifiers`, because the `Empty` this arm
      // returns is indistinguishable there from the `Empty` that an
      // `interface`, a `type` alias, a bodiless `declare function` and a
      // skipped namespace all lower to — putting `Empty` in that list
      // would fire on nearly every real `.d.ts`. Only the `.d.ts` channel
      // consumes the marker, so it is inert in a `.ts` file.
      self.grammar_misuses.push("<empty-stmt>")
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
      // Add label to context for break/continue validation
      self.enter_label(name)
      // statement
      let stmt = self.parse_stmt_no_lexical(false)
      // Remove label from context
      let _ = self.labels.pop()
      Label(name, stmt)
    }
    // yield as label identifier in non-strict mode
    Yield if !self.in_strict && self.peek_at(1).kind == Colon => {
      let _ = self.advance()
      let name = "yield"
      let _ = self.expect(Colon)
      self.enter_label(name)
      let stmt = self.parse_stmt_no_lexical(false)
      let _ = self.labels.pop()
      Label(name, stmt)
    }
    _ =>
      // assignment or expressionstatement
      self.parse_assign_or_expr()
  }
}

///|
// / let statement (type)
fn Parser::parse_let(self : Parser) -> @ast.TsStmt raise ParseError {
  let kw_pos = self.peek().pos
  let _ = self.expect(Let)
  self.parse_var_like(VarKind::Let, kw_pos)
}

///|
// / const statement (type)
fn Parser::parse_const(self : Parser) -> @ast.TsStmt raise ParseError {
  let kw_pos = self.peek().pos
  let _ = self.expect(Const)
  self.parse_var_like(VarKind::Const, kw_pos)
}

///|
fn Parser::parse_var(self : Parser) -> @ast.TsStmt raise ParseError {
  let kw_pos = self.peek().pos
  let _ = self.expect(Var)
  self.parse_var_like(VarKind::Var, kw_pos)
}

///|
/// Where an `await using` declaration is allowed, and the evidence for
/// the rules that need more than the parser knows.
///
/// A no-op for a plain `using`, which has none of these constraints.
///
/// One function rather than a copy at each declaration site, because the
/// TS2854 marker was written at ONE of the two and that is exactly the
/// shape this repo keeps recording: `parse_var_like` handles a top-level
/// `using`, and the block-statement path below handles one inside a
/// block — which is how `awaitUsingDeclarations.2` / `.3` are written, so
/// the marker could never fire for them.
///
/// The three contexts are disjoint and each has its own answer. A static
/// block is checked FIRST because it is neither a function nor module top
/// level, and neither `in_function` nor `in_async` can say so: a
/// top-level class's static block leaves `in_function` false, and a class
/// declared inside an `async` function leaves `in_async` true.
fn Parser::record_await_using_context(self : Parser, using_kw : String) -> Unit {
  if using_kw != "await using" {
    return
  }
  // TS18054.
  if self.in_static_block {
    self.grammar_misuses.push(
      "`await using` statements cannot be used inside a class static block",
    )
    return
  }
  if self.in_function {
    // TS2852.
    if not(self.in_async) {
      self.grammar_misuses.push(
        "`await using` statements are only allowed within async functions and at the top levels of modules",
      )
    }
    return
  }
  // Top level. Evidence for TS2854 (requires `target` >= es2017) and
  // TS2853 (requires the file to BE a module); both need a directive or a
  // whole-file fact the parser does not have here, so they are decided in
  // the checker.
  self.grammar_misuses.push("<top-level-await-using>")
}

///|
fn Parser::parse_var_like(
  self : Parser,
  kind : VarKind,
  kw_pos : Int,
  using_kw? : String = "",
) -> @ast.TsStmt raise ParseError {
  let binding = self.parse_binding_pattern()
  // TS2480: `let` is not allowed as a binding name in `let` / `const`
  // declarations (`let let = 1`). Always an error regardless of mode.
  match (kind, binding) {
    (VarKind::Let | VarKind::Const, @ast.TsBinding::Ident("let")) =>
      self.grammar_misuses.push(
        "`let` is not allowed to be used as a name in `let` or `const` declarations",
      )
    _ => ()
  }
  // Whether the FIRST declarator carries a written type annotation. Even
  // `: any` retypes a destructuring source (`var { a2 }: any = {}` is
  // legal), but the annotation and its absence both reach the checker as
  // `Any`, so the distinction only exists here at the token level.
  let first_decl_annotated = self.check(Colon)
  let type_ = self.parse_var_decl_type()
  let stmts = self.parse_var_decl_list_from(binding, type_, kind)
  // `using` / `await using` grammar constraints (recorded per declarator):
  //   TS1492 — a binding pattern is never allowed;
  //   TS2850/2851 — an object-LITERAL initializer with fully-known plain
  //   keys provably lacks a `[Symbol.dispose]()` / `[Symbol.asyncDispose]()`
  //   method (symbol-keyed / computed / spread entries abstain).
  if using_kw != "" {
    // Marker for the lib-directive TS2318 rule: a `using` declaration
    // requires the `Disposable` global type (usingDeclarations.9).
    self.grammar_misuses.push("<has-using>")
    self.record_await_using_context(using_kw)
    for st in stmts {
      match st {
        Var(b, _, init) | Let(b, _, init) | Const(b, _, init) => {
          match b {
            Array(_) | Object(_) =>
              self.grammar_misuses.push(
                "'\{using_kw}' declarations may not have binding patterns",
              )
            _ => ()
          }
          match init {
            // TS1155: "'using' declarations must be initialized." There is
            // nothing to dispose without an initializer, so unlike `let`
            // the declarator is not optional. `parse_var_decl_list_from`
            // substitutes the `__ts_no_init__` sentinel for a declarator
            // the source left bare, which is how the absence is visible
            // here at all — `Var(b, _, init)` has no `None` case.
            Var("__ts_no_init__") =>
              self.grammar_misuses.push(
                "'\{using_kw}' declarations must be initialized",
              )
            ObjectLit(entries) => {
              let mut keys_plain = true
              for e in entries {
                if e.0.has_prefix("@@") || e.0.has_prefix("<") {
                  keys_plain = false
                }
              }
              if keys_plain {
                self.grammar_misuses.push(
                  "the initializer of a '\{using_kw}' declaration must be an object with a `[Symbol.dispose]()` method, or `null` / `undefined`",
                )
              }
            }
            _ => ()
          }
        }
        _ => ()
      }
    }
  }
  // TS2339: `var { x, y } = {}` — a non-defaulted pattern property that
  // the syntactic object-literal initializer provably lacks. Only the
  // first declarator is judged (later declarators parse their own
  // annotations inside the list). Spread / computed / synthetic entries
  // make the key set unknowable, so the pattern abstains.
  if !first_decl_annotated && stmts.length() >= 1 {
    match stmts[0] {
      Var(Object(ob), _, ObjectLit(entries))
      | Let(Object(ob), _, ObjectLit(entries))
      | Const(Object(ob), _, ObjectLit(entries)) => {
        let keys : Map[String, Bool] = {}
        // A spread of a syntactic object LITERAL keeps the key set
        // knowable — fold its keys in recursively
        // (`const { g } = { ...{ c: 0 }, f: 0 }` — destructuringSpread).
        // Any other spread / computed / synthetic entry abstains.
        fn collect(es : Array[(String, @ast.TsExpr)]) -> Bool {
          for e in es {
            if e.0.has_prefix("@@spread") {
              match e.1 {
                @ast.TsExpr::ObjectLit(inner) =>
                  if !collect(inner) {
                    return false
                  }
                _ => return false
              }
              continue
            }
            if e.0.has_prefix("@@get:") || e.0.has_prefix("@@set:") {
              keys[e.0.substring(start=6)] = true
              continue
            }
            if e.0.has_prefix("<") || e.0.has_prefix("@@") {
              return false
            }
            match e.1 {
              @ast.TsExpr::ComputedProp(_, _) => return false
              _ => ()
            }
            keys[e.0] = true
          }
          true
        }
        let keys_known = collect(entries)
        if keys_known {
          for prop in ob.props {
            if prop.default is None &&
              prop.key_expr is None &&
              !prop.key.has_prefix("<") &&
              !keys.contains(prop.key) {
              self.grammar_misuses.push(
                "property `" +
                prop.key +
                "` does not exist on the object-literal source",
              )
            }
          }
        }
      }
      _ => ()
    }
  }
  // TS1262: `await` used as a top-level declaration name. Only an error
  // when the file is a module; the checker pairs this marker with the
  // module-syntax evidence (`<module-syntax>` / export markers / imports).
  if !self.in_function {
    for stmt in stmts {
      match stmt {
        Var(b, _, _) | Let(b, _, _) | Const(b, _, _) =>
          if binding_contains_await_name(b) {
            self.grammar_misuses.push("<top-await-name>")
          }
        _ => ()
      }
    }
    // TS2448 pairing data: top-level `let` / `const` declarations, in
    // parse order relative to the `<sb-read:…>` markers static blocks
    // record. `var` is hoisted and never in the TDZ, so it is excluded.
    for stmt in stmts {
      match stmt {
        Let(b, _, _) | Const(b, _, _) => {
          let names : Array[String] = []
          sb_binding_names(b, names)
          for n in names {
            self.grammar_misuses.push("<letconst-decl:" + n + ">")
          }
        }
        _ => ()
      }
    }
  }
  // TS7006 (noImplicitAny): an unannotated binding initialized by a
  // callable literal gives the callable's unannotated parameters no
  // contextual type -- they are implicitly `any` (`var x = x => x`).
  // An annotated binding contextually types the parameters and abstains.
  if self.no_implicit_any {
    for stmt in stmts {
      match stmt {
        Var(_, Any, init) | Let(_, Any, init) | Const(_, Any, init) =>
          self.record_uncontextual_callable_params(init)
        _ => ()
      }
    }
  }
  self.consume_semicolon()
  let merged = self.merge_decl_stmts(stmts)
  // If there is a single simple-ident declarator whose initializer is an
  // arrow-function or function-expression, apply JSDoc param/return overlays
  // using the var/let/const keyword position (where the JSDoc block sits).
  apply_jsdoc_var_func_overlay(self.jsdoc_at_pos, merged, kw_pos)
}

///|
/// True when a binding pattern declares an identifier named `await`
/// anywhere in its structure (`var await`, `var {await} = …`,
/// `var [await] = …`). Used by the TS1262 top-level-await-name marker.
fn binding_contains_await_name(binding : @ast.TsBinding) -> Bool {
  match binding {
    Ident(name) => name == "await"
    Array(ab) => {
      for item in ab.items {
        match item {
          Some(elem) =>
            if binding_contains_await_name(elem.binding) {
              return true
            }
          None => ()
        }
      }
      match ab.rest {
        Some(rest) => binding_contains_await_name(rest)
        None => false
      }
    }
    Object(ob) => {
      for prop in ob.props {
        if binding_contains_await_name(prop.binding) {
          return true
        }
      }
      ob.rest is Some("await")
    }
    Target(_) => false
  }
}

///|
/// Record TS7006 for each unannotated, non-rest, non-defaulted simple
/// parameter of an arrow function sitting in a position with no
/// contextual type. Only the DIRECT initializer shape is walked -- an
/// arrow nested in a call argument may receive a contextual type from
/// the callee, so anything deeper abstains.
fn Parser::record_uncontextual_callable_params(
  self : Parser,
  init : @ast.TsExpr,
) -> Unit {
  match init {
    ArrowFunc(params, _, _, _) =>
      for p in params {
        if p.type_ is Any &&
          !self.written_any_params.contains(p.name) &&
          p.default is None &&
          !p.is_rest &&
          p.name != "<param>" &&
          !p.name.has_prefix("<") &&
          (p.binding is None || p.binding is Some(Ident(_))) {
          self.grammar_misuses.push(
            "<noimplicitany>parameter `\{p.name}` implicitly has an `any` type",
          )
        }
      }
    // A template literal's placeholders never receive contextual types
    // (`` var x = `abc${ x => x }def` ``).
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        self.record_uncontextual_callable_params(e)
      }
    _ => ()
  }
}

///|
// / return statement
fn Parser::parse_return(self : Parser) -> @ast.TsStmt raise ParseError {
  // Check if return is inside a function
  if !self.in_function {
    raise ParseError("Illegal return statement")
  }
  let _ = self.expect(Return)
  // ASI: line terminator after return means return undefined
  // After expect(Return), pos points to the next token
  // Use has_line_terminator_before to check if there was a newline after return
  if self.check(Semicolon) ||
    self.check(RBrace) ||
    self.check(Eof) ||
    self.has_line_terminator_before() {
    if self.check(Semicolon) {
      let _ = self.advance()
    }
    Return(None)
  } else {
    let expr = self.parse_expr()
    self.consume_semicolon()
    Return(Some(expr))
  }
}

///|
// / throw statement
fn Parser::parse_throw(self : Parser) -> @ast.TsStmt raise ParseError {
  let _ = self.expect(Throw)
  let expr = self.parse_expr()
  self.consume_semicolon()
  Throw(expr)
}

///|
// / try/catch/finally statement
fn Parser::parse_try(self : Parser) -> @ast.TsStmt raise ParseError {
  let _ = self.expect(Try)
  let try_block = self.parse_block()
  let mut catch_binding : @ast.TsBinding? = None
  let mut catch_block : @ast.TsBlock? = None
  let mut catch_name = ""
  let mut had_annotation = false
  if self.match_(Catch) {
    if self.match_(LParen) {
      let binding = self.parse_binding_pattern()
      had_annotation = self.check(Colon)
      if self.check(Colon) {
        let _ = self.advance()
        let catch_type = self.parse_type()
        // TS1196: "Catch clause variable type annotation must be 'any' or
        // 'unknown' if specified." A `throw` can carry any value, so
        // narrowing the caught binding would be a claim TypeScript will not
        // let you make (`catch (e: Error)` —
        // parserCatchClauseWithTypeAnnotation1). The annotation was parsed
        // and discarded here already; only the check was missing.
        match catch_type {
          Any | Unknown => ()
          _ =>
            self.grammar_misuses.push(
              "catch clause variable type annotation must be `any` or `unknown` if specified",
            )
        }
      }
      let _ = self.expect(RParen)
      catch_binding = Some(binding)
      catch_name = match binding {
        @ast.TsBinding::Ident(n) => n
        _ => ""
      }
    }
    let catch_body_start = self.pos
    catch_block = Some(self.parse_block())
    self.record_unknown_catch_use(catch_name, had_annotation, catch_body_start)
  }
  let mut finally_block : @ast.TsBlock? = None
  if self.match_(Finally) {
    finally_block = Some(self.parse_block())
  }
  match (catch_block, finally_block) {
    (None, None) => raise ParseError("try must have catch or finally")
    _ => ()
  }
  Try(try_block, catch_binding, catch_block, finally_block)
}

///|
/// TS18046 ("'e' is of type 'unknown'"): an unannotated `catch (e)`
/// binding is `unknown` under `useUnknownInCatchVariables`, so touching
/// it without narrowing first is an error — the single most common thing
/// a codebase hits when it turns `strict` on.
///
/// Decided over the catch block's TOKEN range, for the reason the
/// private-member rules give: every mention of the binding must spell
/// its name, so a scan is complete by construction where an expression
/// walker missing one arm would lose findings silently.
///
/// A USE is the name followed by `.`, `[` or `(` — the three ways to
/// touch a value of unknown type. Any of five NARROWING or reassignment
/// spellings anywhere in the block withdraws the report for the whole
/// block: `typeof e`, `e instanceof`, `e as`, `e!`, and an assignment to
/// `e`. That is deliberately coarse — narrowing is flow-sensitive and
/// this is not a flow analysis — so a block that narrows in one branch
/// and not another abstains entirely, costing a MISS rather than
/// inventing a finding. `controlFlowAliasingCatchVariables` is exactly
/// that shape and stays a MISS; the aliased form
/// (`const isE = typeof e === "string"`) is caught by the `typeof e`
/// token, which is why the alias needs no special case.
fn Parser::record_unknown_catch_use(
  self : Parser,
  name : String,
  had_annotation : Bool,
  body_start : Int,
) -> Unit {
  if name == "" || had_annotation || not(self.unknown_catch_variables) {
    return
  }
  let mut used = false
  for i in body_start..<self.pos {
    guard self.tokens[i].kind is Ident(n) else { continue }
    if n != name {
      continue
    }
    let prev = if i > 0 { self.tokens[i - 1].kind } else { Eof }
    let next = if i + 1 < self.tokens.length() {
      self.tokens[i + 1].kind
    } else {
      Eof
    }
    if prev is Typeof {
      return
    }
    match next {
      Instanceof | As | Eq | Bang => return
      Ident("as") => return
      Dot | LBracket | LParen => used = true
      _ => ()
    }
  }
  if used {
    self.grammar_misuses.push(
      "`\{name}` is of type `unknown` — narrow it before use",
    )
  }
}

///|
// / if statement
fn Parser::parse_if(self : Parser) -> @ast.TsStmt raise ParseError {
  let _ = self.expect(If)
  let cond = self.parse_parenthesized_expr()
  let then_block = self.parse_block_or_stmt_no_lexical()
  let else_block : @ast.TsBlock? = if self.match_(Else) {
    if self.check(If) {
      // else if
      Some(@ast.TsBlock::{ stmts: [self.parse_if()], stmt_positions: [] })
    } else {
      Some(self.parse_block_or_stmt_no_lexical())
    }
  } else {
    None
  }
  If(cond, then_block, else_block)
}

///|
// / while statement
fn Parser::parse_while(self : Parser) -> @ast.TsStmt raise ParseError {
  let _ = self.expect(While)
  let cond = self.parse_parenthesized_expr()
  // Set iteration context for body
  let prev_iteration = self.in_iteration
  self.in_iteration = true
  let body = self.parse_block_or_stmt_no_lexical()
  self.in_iteration = prev_iteration
  While(cond, body)
}

///|
// / do-while statement
fn Parser::parse_do_while(self : Parser) -> @ast.TsStmt raise ParseError {
  let _ = self.expect(Do)
  // Set iteration context for body
  let prev_iteration = self.in_iteration
  self.in_iteration = true
  let body = self.parse_block_or_stmt_no_lexical()
  self.in_iteration = prev_iteration
  let _ = self.expect(While)
  let cond = self.parse_parenthesized_expr()
  self.consume_semicolon()
  DoWhile(cond, body)
}

///|
fn Parser::parse_switch(self : Parser) -> @ast.TsStmt raise ParseError {
  let _ = self.expect(Switch)
  let expr = self.parse_parenthesized_expr()
  let _ = self.expect(LBrace)
  // Set switch context for case bodies
  let prev_switch = self.in_switch
  self.in_switch = true
  let cases : Array[@ast.TsSwitchCase] = []
  while !self.check(RBrace) {
    let case_test : @ast.TsExpr? = if self.match_(Case) {
      Some(self.parse_expr())
    } else if self.match_(Default) {
      None
    } else {
      raise ParseError("Expected case or default in switch")
    }
    let _ = self.expect(Colon)
    let stmts : Array[@ast.TsStmt] = []
    let case_stmt_positions : Array[Int] = []
    while !self.check(Case) && !self.check(Default) && !self.check(RBrace) {
      case_stmt_positions.push(self.peek().pos)
      // TS1547 / TS1548: "'using' / 'await using' declarations are not
      // allowed in 'case' or 'default' clauses unless contained within a
      // block." The clause bodies of one `switch` share a scope, so a
      // disposable bound in one clause would outlive it. Checked by
      // peeking at the statement about to be parsed rather than by
      // carrying a flag: a clause body is a statement LIST, so the
      // enclosing-block question is answered by where we are standing,
      // and `case 1: { using x = d; }` reaches `parse_block` instead and
      // is correctly untouched.
      if self.is_using_declaration_start() {
        self.grammar_misuses.push(
          "`using` declarations are not allowed in `case` or `default` clauses unless contained within a block",
        )
      } else if self.is_await_using_declaration_start() {
        self.grammar_misuses.push(
          "`await using` declarations are not allowed in `case` or `default` clauses unless contained within a block",
        )
      }
      stmts.push(self.parse_stmt())
    }
    cases.push({
      test_expr: case_test,
      body: { stmts, stmt_positions: case_stmt_positions },
    })
  }
  self.in_switch = prev_switch
  let _ = self.expect(RBrace)
  Switch(expr, cases)
}

///|
fn Parser::parse_with(self : Parser) -> @ast.TsStmt raise ParseError {
  let _ = self.expect(With)
  // TS1101 ("'with' statements are not allowed in strict mode"). Recorded
  // unconditionally, not gated on strict mode: TypeScript rejects `with`
  // in every configuration — a plain non-strict script gets TS1101 plus
  // TS2410 ("the 'with' statement is not supported"), so there is no
  // reading of any input under which the construct is accepted and the
  // check cannot cost precision. Recorded rather than raised, so the file
  // still parses and the checker surfaces the diagnostic.
  self.record_suppressible_grammar_misuse("`with` statements are not allowed")
  let obj_expr = self.parse_parenthesized_expr()
  let body = self.parse_block_or_stmt_no_lexical()
  With(obj_expr, body)
}

///|
fn Parser::parse_debugger(self : Parser) -> @ast.TsStmt raise ParseError {
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
      Semicolon => if paren == 0 && brace == 0 && bracket == 0 { return false }
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
      Of | In => if paren == 0 && brace == 0 && bracket == 0 { return true }
      _ => ()
    }
    i += 1
  }
  false
}

///|
// / for statement (regularforfor...of)
fn Parser::parse_for(self : Parser) -> @ast.TsStmt raise ParseError {
  let _ = self.expect(For)
  let mut is_await = false
  if self.check(Ident("await")) {
    let _ = self.advance()
    is_await = true
    // TS18038 ("'for await' loops cannot be used inside a class static
    // block"): a static block is not an async context, and unlike the
    // TS2852 / TS18054 `using` family this one needs no other condition —
    // `classStaticBlock23` puts the same loop inside an `async function`
    // to show that the enclosing function does not rescue it.
    if self.in_static_block {
      self.grammar_misuses.push(
        "`for await` loops cannot be used inside a class static block",
      )
    }
  }
  let _ = self.expect(LParen)

  // `for (using x of ...)` — ES2023 disposable binding. Same shape as
  // `for (let x of ...)` for parsing purposes; we tag the binding with
  // `TsForOfKind::Let` since the auto-disposal semantics don't affect the
  // type-level shape the checker cares about.
  let mut using_kw = ""
  let using_declaration = if self.is_using_declaration_start() {
    let _ = self.advance()
    using_kw = "using"
    true
  } else if self.is_await_using_declaration_start() {
    let _ = self.advance() // `await`
    let _ = self.advance() // `using`
    using_kw = "await using"
    true
  } else {
    false
  }
  // for...of check: for (var/let/const x of arr)
  if using_declaration ||
    (self.check(Let) && !self.is_let_for_in_head_ident()) ||
    self.check(Const) ||
    self.check(Var) {
    let kind = if using_declaration {
      @ast.TsForOfKind::Let
    } else {
      match self.advance().kind {
        Let => @ast.TsForOfKind::Let
        Const => @ast.TsForOfKind::Const
        Var => @ast.TsForOfKind::Var
        _ => @ast.TsForOfKind::Var
      }
    }
    let binding = self.parse_binding_pattern()
    // The THIRD `using` declaration site, after `parse_var_like` and the
    // block-statement path — a for-head. `for await (await using x of y)`
    // is the shape `awaitUsingDeclarationsInForOf` / `InForAwaitOf` test,
    // and it needs the same context answer as the other two.
    self.record_await_using_context(using_kw)
    // TS1492: `for (using [a] of ...)` / `for (await using {} of ...)` —
    // a `using` head never takes a binding pattern.
    if using_declaration && binding is (Array(_) | Object(_)) {
      self.grammar_misuses.push(
        "'\{using_kw}' declarations may not have binding patterns",
      )
    }
    // TS2451 for a duplicate name inside a for-head destructuring pattern
    // (`for (let [v, v] of …)`). A `var` head merges and is exempt, the
    // same distinction the declaration site makes.
    self.record_pattern_duplicate_bindings(
      binding,
      kind is (@ast.TsForOfKind::Let | @ast.TsForOfKind::Const),
    )
    // TS2480: `for (let let of ...)` / `for (const let in ...)`.
    match (kind, binding) {
      (
        @ast.TsForOfKind::Let
        | @ast.TsForOfKind::Const,
        @ast.TsBinding::Ident("let"),
      ) =>
        self.grammar_misuses.push(
          "`let` is not allowed to be used as a name in `let` or `const` declarations",
        )
      _ => ()
    }
    let var_type = self.parse_var_decl_type()
    // Read HERE, not at the recorder call below: the iterable expression
    // and the loop body are parsed in between and either can contain a
    // declaration whose own `parse_var_decl_type` overwrites the flag —
    // the same hazard `parse_var_decl_item` records for the declaration
    // site. `var_type is Any` cannot answer this on its own, because an
    // ABSENT annotation and an explicit `: any` are the same `Any`.
    let head_annotated = self.last_var_decl_annotated
    if self.check(Of) || self.check(In) {
      let is_in = self.check(In)
      if is_await && is_in {
        raise ParseError("for-await-of requires 'of'")
      }
      // TS1493 / TS1494: "The left-hand side of a 'for...in' statement
      // cannot be a 'using' / 'await using' declaration." A disposable
      // binding needs a scope that ends deterministically, and `for...in`
      // does not give one — `for (using x of …)`, twenty lines below in
      // the same branch, IS legal, which is why this keys on `is_in` and
      // not on the `using` head alone. The sibling TS1492 (a binding
      // pattern in a `using` head) was already recorded above.
      if is_in && using_declaration {
        self.grammar_misuses.push(
          "the left-hand side of a `for...in` statement cannot be a `\{using_kw}` declaration",
        )
      }
      let _ = self.advance() // of/in
      let iterable = self.parse_expr()
      let _ = self.expect(RParen)
      // Set iteration context for body
      let prev_iteration = self.in_iteration
      self.in_iteration = true
      let body = self.parse_block_or_stmt_no_lexical()
      self.in_iteration = prev_iteration
      self.record_for_head_binding_misuses(
        kind, binding, var_type, head_annotated, iterable, body,
      )
      // Preserve the explicit type annotation on the loop binding when
      // present; `parse_var_decl_type` returns `Any` otherwise.
      if is_in {
        return ForIn(kind, binding, var_type, iterable, body)
      }
      if is_await {
        return ForAwaitOf(kind, binding, var_type, iterable, body)
      }
      return ForOf(kind, binding, var_type, iterable, body)
    }
    // TS1155: a `using` declaration must be initialized. The rule exists
    // at the statement site (`parse_var_like`) and this C-style for-head
    // is a second declaration site it never reached. Note what is LEGAL
    // here, from the baseline rather than from reasoning:
    // `for (using of = null;;)` and `for (using of: null = null;;)` are
    // both fine — a `using` in a C-style for head is allowed, and only
    // the missing initializer is the error (`usingDeclarationsInForOf.4`
    // errors on its third line alone).
    if using_declaration && not(self.check(Eq)) {
      self.grammar_misuses.push(
        "'\{using_kw}' declarations must be initialized",
      )
    }
    let var_kind = match kind {
      @ast.TsForOfKind::Var => VarKind::Var
      @ast.TsForOfKind::Let => VarKind::Let
      @ast.TsForOfKind::Const => VarKind::Const
      @ast.TsForOfKind::Assign => VarKind::Var // shouldn't reach here
    }
    let stmts = self.parse_var_decl_list_from(binding, var_type, var_kind)
    let _ = self.expect(Semicolon)
    let init : @ast.TsStmt? = Some(self.merge_decl_stmts(stmts))
    return self.parse_for_rest(init)
  }

  // init
  let init : @ast.TsStmt? = if self.check(Semicolon) {
    let _ = self.advance()
    None
  } else {
    if self.is_for_of_head() {
      // Whether the left-hand side was written in parentheses. The AST
      // cannot answer: `parse_assignment_binding_pattern` strips them, so
      // `(async)` and `async` both arrive as `Ident("async")` — and they
      // differ (see TS1106 below).
      let lhs_parenthesized = self.check(LParen)
      let binding = self.parse_assignment_binding_pattern()
      if self.check(Of) || self.check(In) {
        let is_in = self.check(In)
        if is_await && is_in {
          raise ParseError("for-await-of requires 'of'")
        }
        // TS1106: the left-hand side of a `for...of` may not be `async`.
        // It is a lookahead restriction rather than a semantic rule — it
        // exists so `for (async of …)` cannot be read as the start of
        // `for await (… of …)` — so even a file where `async` is an
        // ordinary declared variable is an error (`var async; for (async
        // of [1, 2]) {}`, parserForOfStatement22).
        //
        // All three exemptions are cases where that ambiguity cannot
        // arise, and each was a corpus FALSE POSITIVE before it was
        // added, not a case reasoned out in advance:
        //   `for (async in x)`      — a different statement form;
        //   `for await (async of x)` — `await` is already written, so
        //                              there is nothing to confuse it
        //                              with (parserForOfStatement23);
        //   `for ((async) of x)`     — a parenthesized LHS is not the bare
        //                              token the restriction names
        //                              (parserForOfStatement24).
        if not(is_in) &&
          not(is_await) &&
          not(lhs_parenthesized) &&
          binding is @ast.TsBinding::Ident("async") {
          self.grammar_misuses.push(
            "the left-hand side of a `for...of` statement may not be `async`",
          )
        }
        let _ = self.advance()
        let iterable = self.parse_expr()
        let _ = self.expect(RParen)
        // Set iteration context for body
        let prev_iteration = self.in_iteration
        self.in_iteration = true
        let body = self.parse_block_or_stmt_no_lexical()
        self.in_iteration = prev_iteration
        // Assignment-form for-of/in has no declaration site — no type
        // annotation possible; use `Any` so the checker infers from the
        // iterable instead of falling for a placeholder.
        if is_in {
          return ForIn(@ast.TsForOfKind::Assign, binding, Any, iterable, body)
        }
        if is_await {
          return ForAwaitOf(
            @ast.TsForOfKind::Assign,
            binding,
            Any,
            iterable,
            body,
          )
        }
        return ForOf(@ast.TsForOfKind::Assign, binding, Any, iterable, body)
      }
    }
    let expr = self.parse_expr_until_top_level(Semicolon)
    let stmt : @ast.TsStmt = if self.match_(Eq) {
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
    } else if self.match_(AmpAmpEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => CompoundAssign(name, AndAssign, value)
        _ => Expr(expr)
      }
    } else if self.match_(PipePipeEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => CompoundAssign(name, OrAssign, value)
        _ => Expr(expr)
      }
    } else if self.match_(QuestionQuestionEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => CompoundAssign(name, CoalesceAssign, value)
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
  init : @ast.TsStmt?,
) -> @ast.TsStmt raise ParseError {

  // cond
  let cond : @ast.TsExpr? = if self.check(Semicolon) {
    None
  } else {
    Some(self.parse_expr_until_top_level(Semicolon))
  }
  let _ = self.expect(Semicolon)

  // update ()
  let update : @ast.TsStmt? = if self.check(RParen) {
    None
  } else {
    let expr = self.parse_expr_until_top_level(RParen)
    if self.match_(Eq) {
      let value = self.parse_expr()
      let lvalue = strip_lvalue_wrappers(expr)
      match lvalue {
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
  // Set iteration context for body
  let prev_iteration = self.in_iteration
  self.in_iteration = true
  let body = self.parse_block_or_stmt_no_lexical()
  self.in_iteration = prev_iteration
  For(init, cond, update, body)
}

///|
// / assignmentexpressionstatement
fn Parser::parse_assign_or_expr(self : Parser) -> @ast.TsStmt raise ParseError {
  // expression
  let expr = self.parse_expr()

  // assignmentcheck
  if self.match_(Eq) {
    let value = self.parse_expr()
    self.consume_semicolon()
    // Type-only wrappers (`as T`, `satisfies T`, `!`) are transparent for
    // assignment-target purposes — peel them off so the underlying lvalue
    // pattern matches.
    let lvalue = strip_lvalue_wrappers(expr)
    match lvalue {
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
  } else if self.match_(Comma) {
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

///|
// / block
pub fn Parser::parse_block(self : Parser) -> @ast.TsBlock raise ParseError {
  let _ = self.expect(LBrace)
  let stmts : Array[@ast.TsStmt] = []
  let stmt_positions : Array[Int] = []
  let prev_strict = self.in_strict
  let mut in_directive = true
  while !self.check(RBrace) && !self.check(Eof) {
    // `using x = expr` / `await using x = expr` (ES2023). Lower to
    // `const x = expr; try { ...rest } finally { x[Symbol.dispose]?.() }`
    // so the disposal semantics survive in the emitted JS.
    let is_using = self.is_using_declaration_start()
    let is_await_using = if !is_using {
      self.is_await_using_declaration_start()
    } else {
      false
    }
    if is_using || is_await_using {
      let pos = self.peek().pos
      if is_using {
        let _ = self.advance() // `using`
      } else {
        let _ = self.advance() // `await`
        let _ = self.advance() // `using`
      }
      let binding_name = self.parse_binding_ident()
      let has_annotation = self.check(Colon)
      let ty = if has_annotation {
        let _ = self.advance()
        self.parse_type()
      } else {
        @ast.TsType::Any
      }
      let _ = self.expect(Eq)
      let init = self.parse_expr()
      let _ = self.match_(Semicolon)
      let using_kw = if is_await_using { "await using" } else { "using" }
      // Marker for the lib-directive TS2318 rule (`Disposable` global —
      // usingDeclarations.9's block-scoped form lowers here, not through
      // `parse_var_like`).
      self.grammar_misuses.push("<has-using>")
      self.record_await_using_context(using_kw)
      // Later declarators of a multi-declarator `using` land inside the
      // init as a comma chain (`using a = null, [b] = null, c = null`
      // parses `null, ([b] = null), (c = null)`). A destructuring
      // assignment operand is exactly a pattern declarator — TS1492.
      // The FIRST operand is the real initializer: an object LITERAL
      // whose keys are all plain (no symbol-keyed / computed / spread
      // entry) provably lacks `[Symbol.dispose]()` — TS2850/2851.
      fn using_first_operand(e : @ast.TsExpr) -> @ast.TsExpr {
        match e {
          Seq(a, _) => using_first_operand(a)
          _ => e
        }
      }
      fn scan_using_declarators(p : Parser, e : @ast.TsExpr) -> Unit {
        match e {
          Seq(a, b) => {
            scan_using_declarators(p, a)
            scan_using_declarators(p, b)
          }
          AssignPattern(_, _) =>
            p.grammar_misuses.push(
              "'\{using_kw}' declarations may not have binding patterns",
            )
          _ => ()
        }
      }
      scan_using_declarators(self, init)
      // An annotated declaration (`using d: T = {...}`) type-checks the
      // literal against `T` instead — only the unannotated form decides.
      match (has_annotation, using_first_operand(init)) {
        (false, ObjectLit(entries)) => {
          let mut keys_plain = true
          for e in entries {
            if e.0.has_prefix("@@") || e.0.has_prefix("<") {
              keys_plain = false
            }
          }
          if keys_plain {
            self.grammar_misuses.push(
              "the initializer of a '\{using_kw}' declaration must be an object with a `[Symbol.dispose]()` method, or `null` / `undefined`",
            )
          }
        }
        _ => ()
      }
      // Parse the remaining statements in this block into the try body.
      let rest_stmts : Array[@ast.TsStmt] = []
      let rest_positions : Array[Int] = []
      while !self.check(RBrace) && !self.check(Eof) {
        rest_positions.push(self.peek().pos)
        rest_stmts.push(self.parse_stmt())
      }
      // Synthesize `x[Symbol.dispose]?.()` (or Symbol.asyncDispose).
      let dispose_key = if is_await_using { "asyncDispose" } else { "dispose" }
      let dispose_expr = @ast.TsExpr::OptionalChain(
        @ast.TsExpr::CallExpr(
          @ast.TsExpr::IndexAccess(
            @ast.TsExpr::Var(binding_name),
            @ast.TsExpr::PropAccess(@ast.TsExpr::Var("Symbol"), dispose_key),
          ),
          [],
        ),
      )
      let finally_block : @ast.TsBlock = {
        stmts: [@ast.TsStmt::Expr(dispose_expr)],
        stmt_positions: [],
      }
      stmts.push(
        @ast.TsStmt::Const(@ast.TsBinding::Ident(binding_name), ty, init),
      )
      stmts.push(
        @ast.TsStmt::Try(
          { stmts: rest_stmts, stmt_positions: rest_positions },
          None,
          None,
          Some(finally_block),
        ),
      )
      stmt_positions.push(pos)
      stmt_positions.push(pos)
      break
    }
    stmt_positions.push(self.peek().pos)
    let stmt = self.parse_stmt()
    if in_directive {
      match stmt {
        Expr(StringLit("use strict")) => self.in_strict = true
        Expr(StringLit(_)) => ()
        _ => in_directive = false
      }
    }
    stmts.push(stmt)
  }
  let _ = self.expect(RBrace)
  self.in_strict = prev_strict
  { stmts, stmt_positions }
}

///|
fn Parser::parse_block_or_stmt_no_lexical(
  self : Parser,
) -> @ast.TsBlock raise ParseError {
  if self.check(LBrace) {
    self.parse_block()
  } else {
    { stmts: [self.parse_stmt_no_lexical(true)], stmt_positions: [] }
  }
}

///|
fn Parser::is_let_identifier_expr_start(self : Parser) -> Bool {
  if self.in_strict {
    return false
  }
  match self.peek().kind {
    Let => {
      let next = self.peek_at(1).kind
      if next == LBracket {
        return false
      }
      // `let <identifier>` / `let {` is always a lexical declaration — two
      // identifiers can't form an expression, so a line terminator between
      // `let` and the binding name does NOT trigger ASI (`let\nx` declares
      // `x`). Only treat `let` as a free identifier reference when what
      // follows cannot begin a binding.
      if next is Ident(_) || next == LBrace {
        return false
      }
      if next == Semicolon || next == RBrace || next == Eof {
        return true
      }
      self.has_line_terminator_after()
    }
    _ => false
  }
}

///|
/// True when the current token is `using` AND the upcoming pattern
/// (`Ident`, `{`, `[`) makes this an ES2023 `using` declaration rather
/// than a free identifier reference. The spec mandates no line
/// terminator between `using` and the binding pattern.
fn Parser::is_using_declaration_start(self : Parser) -> Bool {
  match self.peek().kind {
    Ident("using") => ()
    _ => return false
  }
  // ASI: a newline between `using` and the next token makes this NOT a
  // `using` declaration — the parser must treat `using` as a reference.
  if self.peek_at(1).has_newline_before {
    return false
  }
  // Accept contextual keywords (`of`, `from`, `as`, `async`) as binding
  // names too — TS allows `using of = ...` etc.
  match self.peek_at(1).kind {
    Ident(_) | LBrace | LBracket | Of | From | As => true
    _ => false
  }
}

///|
/// True when the current two tokens form `await using` and the binding
/// pattern follows on the same line. Same ASI rule as
/// `is_using_declaration_start`.
fn Parser::is_await_using_declaration_start(self : Parser) -> Bool {
  match self.peek().kind {
    Ident("await") => ()
    _ => return false
  }
  match self.peek_at(1).kind {
    Ident("using") => ()
    _ => return false
  }
  if self.peek_at(1).has_newline_before || self.peek_at(2).has_newline_before {
    return false
  }
  match self.peek_at(2).kind {
    Ident(_) | LBrace | LBracket | Of | From | As => true
    _ => false
  }
}

///|
fn Parser::is_let_for_in_head_ident(self : Parser) -> Bool {
  if self.in_strict {
    return false
  }
  if !self.check(Let) {
    return false
  }
  match self.peek_at(1).kind {
    In | Of => true
    _ => false
  }
}

///|
fn Parser::parse_stmt_no_lexical(
  self : Parser,
  allow_function : Bool,
) -> @ast.TsStmt raise ParseError {
  if self.is_disallowed_lexical_stmt_start(allow_function) {
    raise ParseError(
      "Lexical declaration not allowed in single-statement position",
    )
  }
  self.parse_stmt()
}

///|
fn Parser::is_disallowed_lexical_stmt_start(
  self : Parser,
  allow_function : Bool,
) -> Bool {
  match self.peek().kind {
    Let => !self.is_let_identifier_expr_start()
    Const | Class => true
    // TS1156: "'using' / 'await using' declarations can only be declared
    // inside a block." A `using` declaration is lexical exactly like
    // `let` / `const`, so `if (c) using x = d;` is not legal TypeScript.
    // The arm was missing because `using` was added to the parser after
    // this check was written — the same omission shape as the `let` /
    // `const` arms above, which is why it lives here rather than in a
    // second predicate.
    //
    // Both spellings are gated on the same look-ahead the statement
    // parser uses, so a plain identifier REFERENCE named `using`
    // (`if (c) using;`, `while (c) using.foo();`) is untouched — that is
    // legal JavaScript and the reason this cannot be a bare token test.
    Ident("using") => self.is_using_declaration_start()
    Ident("await") if self.peek_at(1).kind is Ident("using") =>
      self.is_await_using_declaration_start()
    Function =>
      if self.peek_at(1).kind == Star {
        true
      } else {
        !allow_function || self.in_strict
      }
    Ident("async") if self.peek_at(1).kind == Function &&
      !self.has_line_terminator_after() => true
    _ => false
  }
}

///|
fn Parser::parse_var_decl_type(self : Parser) -> @ast.TsType raise ParseError {
  if self.match_(Bang) {
    // Definite assignment assertion: let value!: Type;
  }
  if self.check(Colon) {
    let _ = self.advance()
    // Whether the declarator carried an ANNOTATION, which the returned
    // type cannot say: a missing annotation and an explicit `: any` are
    // both `Any`. TS2493 needs the difference — `var [i]: any = []` is
    // legal and `var [c] = []` is not. A "result of the last call" field
    // in the shape of `last_function_bodiless`, read at the top of
    // `parse_var_decl_item`, which is always the next thing to run.
    self.last_var_decl_annotated = true
    self.parse_type()
  } else {
    self.last_var_decl_annotated = false
    Any
  }
}

///|
fn Parser::merge_decl_stmts(
  _self : Parser,
  stmts : Array[@ast.TsStmt],
) -> @ast.TsStmt {
  if stmts.length() == 1 {
    stmts[0]
  } else {
    // `DECL_GROUP_POSITION` marks this as `let a = 1, b = 2` rather than
    // a real block. See the constant's comment: recording it as "no
    // positions" let every later rebuild erase the distinction.
    Block({ stmts, stmt_positions: [@ast.DECL_GROUP_POSITION] })
  }
}

///|
fn Parser::parse_var_decl_list_from(
  self : Parser,
  binding : @ast.TsBinding,
  type_ : @ast.TsType,
  kind : VarKind,
) -> Array[@ast.TsStmt] raise ParseError {
  let stmts : Array[@ast.TsStmt] = []
  stmts.push(self.parse_var_decl_item(binding, type_, kind))
  while self.match_(Comma) {
    let next_binding = self.parse_binding_pattern()
    let next_type = self.parse_var_decl_type()
    stmts.push(self.parse_var_decl_item(next_binding, next_type, kind))
  }
  stmts
}

///|
fn Parser::parse_var_decl_item(
  self : Parser,
  binding : @ast.TsBinding,
  type_ : @ast.TsType,
  kind : VarKind,
) -> @ast.TsStmt raise ParseError {
  // TS2451 for a duplicate name inside ONE destructuring pattern. Placed
  // here rather than at `parse_var_like`'s first declarator because every
  // declarator of a group — `let { a, a } = x, [b, b] = y` — passes through
  // this one function with its `kind`, so no declarator can be missed.
  self.record_pattern_duplicate_bindings(
    binding,
    kind is (VarKind::Let | VarKind::Const),
  )
  // Read BEFORE the initializer is parsed: an initializer can contain a
  // function body with its own declarations, whose `parse_var_decl_type`
  // would overwrite the flag. Reading it here means a nested declaration
  // cannot make this one look annotated.
  let annotated = self.last_var_decl_annotated
  let init_opt = if self.match_(Eq) {
    Some(self.parse_assignment())
  } else {
    None
  }
  let init = match init_opt {
    Some(expr) => expr
    None => {
      if kind is Const {
        raise ParseError("const declaration requires an initializer")
      }
      match binding {
        // Parser-synthesised sentinel for `let x;` / `var x;`
        // (declaration without `=` initializer). Semantically `x` is
        // `undefined` at the binding site, but TS distinguishes
        // "explicitly assigned undefined" (`let x = undefined;`,
        // which is a real assignment) from "no initializer" (TS2454
        // candidate). The checker pattern-matches this exact sentinel
        // name to recover the distinction without an AST-level
        // option-vs-required change. The name is intentionally a
        // double-underscore form that cannot be written by user code
        // because the lexer rejects identifiers starting with `__ts_`.
        @ast.TsBinding::Ident(_) => @ast.TsExpr::Var("__ts_no_init__")
        _ =>
          raise ParseError("Destructuring declaration requires an initializer")
      }
    }
  }
  if not(annotated) {
    self.record_tuple_index_out_of_range(binding, init)
  }
  self.record_self_referential_initializer(binding, init, kind, annotated)
  match kind {
    Var => @ast.TsStmt::Var(binding, type_, init)
    Let => @ast.TsStmt::Let(binding, type_, init)
    Const => @ast.TsStmt::Const(binding, type_, init)
  }
}

///|
/// TS2493 ("Tuple type '[]' of length '0' has no element at index '0'"):
/// an array binding pattern destructuring more positions than the array
/// LITERAL it is initialized from actually has.
///
/// Decidable with no inference because both sides are written out. Every
/// boundary was probed:
///
///   - a position with a DEFAULT is legal (`var [a = 1] = []`), so those
///     are skipped;
///   - a rest element does NOT save the positions before it
///     (`var [d, ...r] = []` still reports index 0), but contributes no
///     position of its own (`var [...r] = []` is legal);
///   - an ELISION counts as a position (`var [, h] = [1]` reports
///     index 1);
///   - a SPREAD in the literal makes its length unknown, so
///     `var [g] = [...xs]` abstains;
///   - `as const` still errors, and our parser drops that wrapper, so the
///     literal is seen and the answer comes out right; `[] as any[]`
///     wraps in `As(...)`, which is not an `ArrayLit`, so it abstains;
///   - nesting is real (`var [[b]] = [[]]` reports at the inner level),
///     so the walk recurses through matching positions.
///
/// The annotation case is handled by the caller: `var [i]: any = []` is
/// legal, and the annotation is the only thing that distinguishes it.
/// Anything other than an array literal on the right abstains, which
/// costs a MISS rather than inventing a finding.
fn Parser::record_tuple_index_out_of_range(
  self : Parser,
  binding : @ast.TsBinding,
  init : @ast.TsExpr,
) -> Unit {
  guard binding is Array(ab) else { return }
  guard init is ArrayLit(items) else { return }
  for it in items {
    if it is Spread(_) {
      return
    }
  }
  for i, elem in ab.items {
    if i >= items.length() {
      // A default supplies the missing element; without one the index
      // does not exist in the tuple.
      let has_default = match elem {
        Some(e) => e.default is Some(_)
        None => false
      }
      if not(has_default) {
        self.grammar_misuses.push(
          "tuple type of length \{items.length()} has no element at index \{i}",
        )
      }
      continue
    }
    match elem {
      Some(e) => self.record_tuple_index_out_of_range(e.binding, items[i])
      None => ()
    }
  }
}

///|
/// Peel `As(...)` / `Satisfies(...)` / `NonNull(...)` wrappers off an
/// expression that is being used as an assignment target. TS treats these
/// as transparent for lvalue purposes (`(x as T) = v`, `x! = v`).
fn strip_lvalue_wrappers(expr : @ast.TsExpr) -> @ast.TsExpr {
  match expr {
    @ast.TsExpr::As(inner, _)
    | @ast.TsExpr::Satisfies(inner, _)
    | @ast.TsExpr::NonNull(inner) => strip_lvalue_wrappers(inner)
    _ => expr
  }
}

///|
/// Apply JSDoc param/return type overlays to a `let`/`const`/`var` declarator
/// whose initializer is an arrow-function or function-expression.  The JSDoc
/// block is looked up by the keyword position (`let`/`const`/`var` token pos)
/// because that is where the comment sits in the source.
fn apply_jsdoc_func_init_overlay(
  jsdoc_at_pos : Map[Int, JsdocBlock],
  kw_pos : Int,
  init : @ast.TsExpr,
) -> @ast.TsExpr {
  match init {
    @ast.TsExpr::ArrowFunc(params, ret, body, is_async) => {
      let p2 = apply_jsdoc_param_overlay(jsdoc_at_pos, kw_pos, params)
      let r2 = apply_jsdoc_return_overlay(jsdoc_at_pos, kw_pos, ret)
      @ast.TsExpr::ArrowFunc(p2, r2, body, is_async)
    }
    @ast.TsExpr::FuncExpr(f) => {
      let p2 = apply_jsdoc_param_overlay(jsdoc_at_pos, kw_pos, f.params)
      let r2 = apply_jsdoc_return_overlay(jsdoc_at_pos, kw_pos, f.return_type)
      @ast.TsExpr::FuncExpr({ ..f, params: p2, return_type: r2 })
    }
    _ => init
  }
}

///|
/// Apply JSDoc param/return type overlays to a `let`/`const`/`var` declarator
/// whose initializer is an arrow-function or function-expression.
fn apply_jsdoc_var_func_overlay(
  jsdoc_at_pos : Map[Int, JsdocBlock],
  stmt : @ast.TsStmt,
  kw_pos : Int,
) -> @ast.TsStmt {
  match stmt {
    @ast.TsStmt::Const(binding, ty, init) =>
      @ast.TsStmt::Const(
        binding,
        ty,
        apply_jsdoc_func_init_overlay(jsdoc_at_pos, kw_pos, init),
      )
    @ast.TsStmt::Let(binding, ty, init) =>
      @ast.TsStmt::Let(
        binding,
        ty,
        apply_jsdoc_func_init_overlay(jsdoc_at_pos, kw_pos, init),
      )
    @ast.TsStmt::Var(binding, ty, init) =>
      @ast.TsStmt::Var(
        binding,
        ty,
        apply_jsdoc_func_init_overlay(jsdoc_at_pos, kw_pos, init),
      )
    _ => stmt
  }
}

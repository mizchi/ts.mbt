// TypeScript → JavaScript transform.
//
// The transform pipeline is staged to support type-aware mangling and
// bundling later, but this initial round is just a faithful TS → JS
// emit: parse a source file, strip type-only declarations and
// annotations, lower the TS-only constructs (`enum`, `namespace`)
// into their JS equivalents, and print the result.
//
//   parse  ─►  TsModuleBlock  ─►  emit (strip + lower)  ─►  JS source
//
// Later phases plug in between `parse` and `emit`:
//
//   parse  ─►  TsModuleBlock  ─►  symbol-graph + mangle  ─►  emit  ─►  JS
//                              └──── bundle (module graph) ─────┘
//
// `transform_source` is the public entrypoint for the parse + emit
// composition. The lower-level `Emitter` is exposed so callers can
// feed a pre-built `TsModuleBlock` (which is what the bundle phase
// produces).

///|
priv struct Emitter {
  buf : StringBuilder
  mut indent : Int
  // When `true`, the emitter inserts whitespace + newlines that make
  // the output diffable. With `false`, indentation/newlines/optional
  // spaces drop out and statement terminators take a "lazy" path so
  // a `;` immediately followed by `}` can be elided.
  pretty : Bool
  // Live byte / line / column counts on the *output*. Tracked so the
  // source-map builder can attribute each emitted statement back to
  // its position in the original source. Updated by `write`, `nl`,
  // and `space`.
  mut out_line : Int
  mut out_col : Int
  // Source-map builder; when `None` the emitter never records
  // mappings (fast path for callers that don't need sourcemaps).
  mut smap : SourceMapBuilder?
  // Line index for the original source, used to convert byte
  // offsets recorded by the parser into `(line, column)` for the
  // mappings. Empty `LineIndex` when sourcemap mode is off.
  mut line_index : LineIndex
  // Pending statement terminator (`;`). In minify mode `semi()`
  // sets this instead of writing the byte right away — the next
  // write either commits it or, for `close_block`, drops it. In
  // pretty mode `semi()` writes through directly and this flag
  // stays false.
  mut pending_semi : Bool
  // Tracks the most recently emitted top-level token kind so we can
  // suppress optional whitespace in minify mode (e.g. drop the
  // space between `return` and a following `{` / `[` / string /
  // template literal).
  mut last_token : LastTok
}

///|
priv enum LastTok {
  Other
  // Most recent text emitted was an identifier or keyword whose
  // next-byte separator depends on the upcoming token (e.g.
  // `return`, `typeof`, `delete`).
  Word
} derive(Eq)

///|
fn Emitter::new(pretty~ : Bool = true) -> Emitter {
  {
    buf: StringBuilder::new(),
    indent: 0,
    pretty,
    out_line: 0,
    out_col: 0,
    smap: None,
    line_index: LineIndex::new(""),
    pending_semi: false,
    last_token: LastTok::Other,
  }
}

///|
fn Emitter::flush_semi(self : Emitter) -> Unit {
  if self.pending_semi {
    self.buf.write_string(";")
    self.out_col = self.out_col + 1
    self.pending_semi = false
  }
}

///|
/// Emit a statement terminator. In pretty mode this writes `;`
/// immediately; in minify mode it parks the `;` so `close_block`
/// can drop it when it's the last byte before `}`.
fn Emitter::semi(self : Emitter) -> Unit {
  if self.pretty {
    self.buf.write_string(";")
    self.out_col = self.out_col + 1
  } else {
    self.pending_semi = true
  }
}

///|
fn Emitter::to_string(self : Emitter) -> String {
  self.buf.to_string()
}

///|
fn Emitter::write(self : Emitter, s : String) -> Unit {
  if self.pending_semi {
    self.flush_semi()
  }
  self.buf.write_string(s)
  self.last_token = LastTok::Other
  // Update the output position counter so the source-map builder can
  // pin emit-side coordinates without reparsing the buffer.
  for c in s {
    if c == '\n' {
      self.out_line = self.out_line + 1
      self.out_col = 0
    } else {
      self.out_col = self.out_col + 1
    }
  }
}

///|
/// Emit a keyword (e.g. `return`, `typeof`, `void`, `delete`) and
/// mark the trailing token-kind so the next call can decide whether
/// an optional whitespace separator is needed in minify mode.
fn Emitter::word(self : Emitter, s : String) -> Unit {
  if self.pending_semi {
    self.flush_semi()
  }
  self.buf.write_string(s)
  for c in s {
    if c == '\n' {
      self.out_line = self.out_line + 1
      self.out_col = 0
    } else {
      self.out_col = self.out_col + 1
    }
  }
  self.last_token = LastTok::Word
}

///|
/// Optional separator between a `Word` token and whatever follows.
/// In pretty mode this is always a space; in minify mode it's a
/// space only when the next character could legally extend the
/// preceding identifier / keyword. `first_byte` is the first byte
/// of the upcoming token (0 if unknown / always-separated).
fn Emitter::sep_after_word(self : Emitter, first_byte : Char) -> Unit {
  if self.pretty {
    self.buf.write_string(" ")
    self.out_col = self.out_col + 1
    return
  }
  // Bytes that can never start an identifier: punctuators that
  // immediately terminate the preceding ident. `{`, `[`, `(`, `"`,
  // `'`, `` ` ``, `/`, digits + dots-on-number are safe to abut.
  let needs_space = match first_byte {
    '{' | '[' | '(' | '"' | '\'' | '`' | '!' | '~' | '+' | '-' => false
    _ => true
  }
  if needs_space {
    self.buf.write_string(" ")
    self.out_col = self.out_col + 1
  }
}

///|
fn Emitter::nl(self : Emitter) -> Unit {
  if self.pretty {
    if self.pending_semi {
      self.flush_semi()
    }
    self.buf.write_string("\n")
    self.out_line = self.out_line + 1
    self.out_col = 0
    for _ in 0..<self.indent {
      self.buf.write_string("  ")
      self.out_col = self.out_col + 2
    }
  } else if self.pending_semi {
    // Minify: a `nl()` between two stmts commits the trailing `;`.
    // Pending stays set until close_block runs (then it's dropped).
    self.flush_semi()
  }
}

///|
fn Emitter::space(self : Emitter) -> Unit {
  if self.pretty {
    self.buf.write_string(" ")
    self.out_col = self.out_col + 1
  }
}

///|
/// Record a source-map segment at the current output position
/// pointing back to `src_pos` in the original source. No-op when
/// the emitter wasn't initialised with a source-map builder.
fn Emitter::mark(self : Emitter, src_pos : Position) -> Unit {
  match self.smap {
    Some(b) =>
      b.add_mapping(self.out_line, self.out_col, src_pos.line, src_pos.column)
    None => ()
  }
}

///|
fn Emitter::open_block(self : Emitter) -> Unit {
  self.write("{")
  self.indent = self.indent + 1
}

///|
fn Emitter::close_block(self : Emitter) -> Unit {
  // The last statement inside the block may have parked a `;` on
  // `pending_semi`. In minify mode that semicolon is redundant
  // before `}` — drop it. In pretty mode `nl()` will flush it
  // first.
  if not(self.pretty) {
    self.pending_semi = false
  }
  self.indent = self.indent - 1
  self.nl()
  self.write("}")
}

///|
/// Public entrypoint: parse `source` as a TS module and emit the
/// equivalent JavaScript. Errors are propagated as strings so callers
/// don't have to thread the parser's `ParseError` type.
pub fn transform_source(source : String) -> Result[String, String] {
  transform_source_with(source, JsxConfig::default())
}

///|
/// Same as `transform_source` but lets callers (e.g. a build tool
/// reading `tsconfig.json`) supply a base `JsxConfig`. File-level
/// `/** @jsxImportSource ... */` / `@jsxRuntime` / `@jsx` / `@jsxFrag`
/// pragmas overlay on top of `base`.
///
/// When the input contains any JSX, the emitted JS starts with an
/// `import { jsx, jsxs, Fragment } from "<import_source>/jsx-runtime"`
/// line (for `runtime == "automatic"`) — only the helpers actually
/// referenced by the lowered output are imported.
pub fn transform_source_with(
  source : String,
  base : JsxConfig,
) -> Result[String, String] {
  match transform_source_full(source, base, with_sourcemap=false) {
    Ok(out) => Ok(out.js)
    Err(e) => Err(e)
  }
}

///|
/// Bundle of the JS source + an optional v3 source-map JSON string.
/// `sourcemap` is `None` when the caller passed `with_sourcemap=false`.
pub(all) struct TransformOutput {
  js : String
  sourcemap : String?
}

///|
/// Full transform entrypoint with explicit sourcemap control.
/// Statement-level source-map mappings are recorded when
/// `with_sourcemap=true`; per-token AST positions land in a follow-up.
///
/// Pass `mangle~=true` to run the identifier-mangling pass on the
/// lowered block before emission (`preserve_top_level=true` so the
/// module's exported surface stays intact). `mangle_properties~=true`
/// additionally renames non-reserved property keys, matching the
/// opt-in property mode of `ManglerConfig`.
pub fn transform_source_full(
  source : String,
  base : JsxConfig,
  with_sourcemap~ : Bool = false,
  source_path~ : String = "input.ts",
  output_path~ : String = "output.js",
  mangle~ : Bool = false,
  mangle_properties~ : Bool = false,
  minify~ : Bool = false,
) -> Result[TransformOutput, String] {
  // Parse via the module-block entry so we can inline `const enum`
  // use sites — the side list `mb.enums` carries the original
  // declarations even though the parser's stmt-level path drops
  // their runtime stmts. Falls back to the plain block parse if
  // the source isn't a module-shaped fragment.
  let (block, positions, enums) = match
    (try? @parser.parse_module_block_from_source(source)) {
    Ok(mb) => (mb.block, mb.block.stmt_positions, mb.enums)
    Err(_) =>
      match (try? @parser.parse_block_from_source_with_positions(source)) {
        Ok(pair) => (pair.0, pair.1, [])
        Err(e) => return Err("parse error: \{e}")
      }
  }
  let cfg = extract_jsx_pragmas(source, base)
  let (lowered_jsx, runtime_refs) = lower_block_with_runtime_imports(cfg, block)
  // Splice runtime enum stmts (regular, non-const) and inline
  // `const enum` use sites with their literal values. Same flow
  // the bundler uses; mirrored here so single-file mode works.
  let lowered = if enums.length() > 0 {
    let enum_stmts = lower_enums(enums)
    let combined : Array[@ast.TsStmt] = []
    for s in enum_stmts {
      combined.push(s)
    }
    for s in lowered_jsx.stmts {
      combined.push(s)
    }
    let with_enums : @ast.TsBlock = { stmts: combined, stmt_positions: [] }
    let table = build_enum_inline_table(enums, include_non_const=true)
    inline_const_enums(with_enums, table)
  } else {
    lowered_jsx
  }
  let mangled = if mangle {
    let mangler_cfg = ManglerConfig::default().with_mangle_properties(
      mangle_properties,
    )
    mangle_block(lowered, mangler_cfg)
  } else {
    lowered
  }
  let e = Emitter::new(pretty=not(minify))
  if with_sourcemap {
    e.smap = Some(SourceMapBuilder::new())
    e.line_index = LineIndex::new(source)
  }
  if cfg.runtime == "automatic" && runtime_refs.length() > 0 {
    e.write("import { ")
    for i, name in runtime_refs {
      if i > 0 {
        e.write(", ")
      }
      e.write(name)
    }
    e.write(" } from \"")
    e.write(cfg.import_source)
    e.write("/jsx-runtime\";")
    e.nl()
  }
  // Source-map positions are tied to the unmangled block — when
  // mangling reorders or drops statements the position array would
  // need to be updated in lockstep. For now, skip per-statement
  // mappings when mangling is on; consumers asking for both should
  // file a follow-up.
  let emit_positions = (not(mangle)) && with_sourcemap
  for i, stmt in mangled.stmts {
    if emit_positions && i < positions.length() {
      let src_pos = e.line_index.position(positions[i])
      e.mark(src_pos)
    }
    emit_stmt(e, stmt)
    e.nl()
  }
  let sm_json : String? = match e.smap {
    Some(b) => Some(b.to_json(source~, source_path~, output_path~))
    None => None
  }
  Ok({ js: e.to_string(), sourcemap: sm_json })
}

///|
fn emit_block(e : Emitter, block : @ast.TsBlock) -> Unit {
  e.open_block()
  for i, stmt in block.stmts {
    e.nl()
    // Record a source-map segment at every statement entry when the
    // parser supplied positions. `stmt_positions` is aligned with
    // `stmts`; synthesized blocks (e.g. class desugar) leave it
    // empty and the emit just skips the mapping.
    match e.smap {
      Some(_) =>
        if i < block.stmt_positions.length() {
          let src_pos = e.line_index.position(block.stmt_positions[i])
          e.mark(src_pos)
        }
      None => ()
    }
    emit_stmt(e, stmt)
  }
  e.close_block()
}

///|
/// Variant for control-flow bodies (`if`, `while`, `for*`). In
/// minify mode, when the body is a single statement and that
/// statement isn't a `Let / Const / Var / function-decl` (whose
/// scope `if (cond) let x = …` would semantically collapse around),
/// emit it without braces. In pretty mode this just delegates to
/// `emit_block` for diffable output.
fn emit_branch_body(e : Emitter, block : @ast.TsBlock) -> Unit {
  if e.pretty || block.stmts.length() != 1 {
    emit_block(e, block)
    return
  }
  let s = block.stmts[0]
  if can_braceless(s) {
    emit_stmt(e, s)
  } else {
    emit_block(e, block)
  }
}

///|
/// Statements that can stand alone as the body of an `if` / `while`
/// / `for` without braces. `let` / `const` are excluded because
/// `if (cond) let x = 1;` is a syntax error: lexical declarations
/// can't be the direct child of a control flow head. `function`
/// declarations have the same restriction.
fn can_braceless(stmt : @ast.TsStmt) -> Bool {
  match stmt {
    Let(_, _, _) | Const(_, _, _) => false
    // A bare `function foo() {…}` (which our emitter lowers from
    // a `Let(Ident, _, FuncExpr)` pair) also can't sit as a single
    // branch body. Detect the pattern.
    Var(_, _, _) =>
      // `var` is function-scoped, hoisting makes it survive — but
      // some engines warn. Leave braces on for now.
      false
    _ => true
  }
}

///|
fn emit_stmt(e : Emitter, stmt : @ast.TsStmt) -> Unit {
  // The parser desugars top-level `function foo() {}` to
  // `Let(Ident("foo"), Any, FuncExpr({name: "foo", …}))`. Detect
  // that shape and emit a real function declaration — that's
  // tighter (`function foo() {}` vs `let foo = function foo() {};`,
  // ~15 bytes per function) and lets us drop the redundant
  // FuncExpr internal name. Hoisting becomes more permissive than
  // `let`, but never less, so this is a safe rewrite.
  match try_emit_function_decl(e, stmt) {
    true => return
    false => ()
  }
  match stmt {
    Var(binding, _ty, init) => {
      e.word("var")
      e.sep_after_word(binding_leading_byte(binding))
      emit_binding(e, binding)
      e.space()
      e.write("=")
      e.space()
      emit_expr(e, init, 0)
      e.semi()
    }
    Let(binding, _ty, init) => {
      e.word("let")
      e.sep_after_word(binding_leading_byte(binding))
      emit_binding(e, binding)
      e.space()
      e.write("=")
      e.space()
      emit_expr(e, init, 0)
      e.semi()
    }
    Const(binding, _ty, init) => {
      // In minify mode, downgrade `const` to `let` — the source
      // already proved no reassignment (it was `const`), so swapping
      // the keyword is semantically inert and saves two bytes per
      // declaration. Pretty mode keeps `const` for human readability.
      if e.pretty {
        e.word("const")
      } else {
        e.word("let")
      }
      e.sep_after_word(binding_leading_byte(binding))
      emit_binding(e, binding)
      e.space()
      e.write("=")
      e.space()
      emit_expr(e, init, 0)
      e.semi()
    }
    Assign(name, expr) => {
      e.write(name)
      e.space()
      e.write("=")
      e.space()
      emit_expr(e, expr, 0)
      e.semi()
    }
    CompoundAssign(name, op, expr) => {
      e.write(name)
      e.space()
      e.write(compound_op_str(op))
      e.space()
      emit_expr(e, expr, 0)
      e.semi()
    }
    IndexAssign(recv, idx, value) => {
      emit_expr(e, recv, 18)
      e.write("[")
      emit_expr(e, idx, 0)
      e.write("]")
      e.space()
      e.write("=")
      e.space()
      emit_expr(e, value, 0)
      e.semi()
    }
    PropAssign(recv, prop, value) => {
      // `@@get:name` / `@@set:name` are internal markers from the
      // class-desugar pass meaning "install a getter/setter on
      // the prototype". Emit them as `Object.defineProperty(...)`
      // so the JS output actually wires up the accessor.
      if prop.has_prefix("@@get:") || prop.has_prefix("@@set:") {
        let accessor = if prop.has_prefix("@@get:") { "get" } else { "set" }
        let real_name = prop.substring(start=6, end=prop.length()).to_string()
        e.write("Object.defineProperty(")
        emit_expr(e, recv, 0)
        e.write(",")
        e.space()
        emit_string_literal(e, real_name)
        e.write(",")
        e.space()
        e.write("{")
        e.write(accessor)
        e.write(":")
        e.space()
        emit_expr(e, value, 0)
        e.write(",")
        e.space()
        e.write("configurable:")
        e.space()
        e.write("true")
        e.write("})")
        e.semi()
      } else {
        emit_expr(e, recv, 18)
        e.write(".")
        e.write(strip_internal_prop_marker(prop))
        e.space()
        e.write("=")
        e.space()
        emit_expr(e, value, 0)
        e.semi()
      }
    }
    Expr(expr) => {
      emit_expr(e, expr, 0)
      e.semi()
    }
    Empty => e.semi()
    Return(opt) =>
      match opt {
        Some(expr) => {
          e.word("return")
          // Optional separator: a Word token followed by a literal
          // / brace / bracket / template can abut without a space.
          let first = expr_leading_byte(expr)
          e.sep_after_word(first)
          emit_expr(e, expr, 0)
          e.semi()
        }
        None => {
          e.write("return")
          e.semi()
        }
      }
    Throw(expr) => {
      e.word("throw")
      let first = expr_leading_byte(expr)
      e.sep_after_word(first)
      emit_expr(e, expr, 0)
      e.semi()
    }
    If(cond, then_b, else_opt) => {
      e.write("if")
      e.space()
      e.write("(")
      emit_expr(e, cond, 0)
      e.write(")")
      e.space()
      emit_branch_body(e, then_b)
      match else_opt {
        Some(else_b) => {
          e.space()
          e.write("else")
          // The `else` keyword may abut its body when the body
          // starts with `{` / `[` / etc. in minify mode.
          if else_b.stmts.length() == 1 && can_braceless(else_b.stmts[0]) {
            e.sep_after_word(stmt_leading_byte(else_b.stmts[0]))
          } else {
            e.space()
          }
          emit_branch_body(e, else_b)
        }
        None => ()
      }
    }
    While(cond, body) => {
      e.write("while")
      e.space()
      e.write("(")
      emit_expr(e, cond, 0)
      e.write(")")
      e.space()
      emit_branch_body(e, body)
    }
    DoWhile(cond, body) => {
      e.write("do")
      e.space()
      emit_branch_body(e, body)
      e.space()
      e.write("while")
      e.space()
      e.write("(")
      emit_expr(e, cond, 0)
      e.write(")")
      e.semi()
    }
    For(init_opt, cond_opt, update_opt, body) => {
      e.write("for")
      e.space()
      e.write("(")
      match init_opt {
        Some(s) => emit_stmt_for_head(e, s)
        None => ()
      }
      e.write(";")
      match cond_opt {
        Some(c) => {
          e.space()
          emit_expr(e, c, 0)
        }
        None => ()
      }
      e.write(";")
      match update_opt {
        Some(s) => {
          e.space()
          emit_stmt_for_head(e, s)
        }
        None => ()
      }
      e.write(")")
      e.space()
      emit_branch_body(e, body)
    }
    ForOf(kind, binding, _ty, iter, body) => {
      e.write("for")
      e.space()
      e.write("(")
      emit_for_of_kind(e, kind)
      emit_binding(e, binding)
      e.write(" of ")
      emit_expr(e, iter, 0)
      e.write(")")
      e.space()
      emit_branch_body(e, body)
    }
    ForAwaitOf(kind, binding, _ty, iter, body) => {
      e.write("for await")
      e.space()
      e.write("(")
      emit_for_of_kind(e, kind)
      emit_binding(e, binding)
      e.write(" of ")
      emit_expr(e, iter, 0)
      e.write(")")
      e.space()
      emit_branch_body(e, body)
    }
    ForIn(kind, binding, _ty, iter, body) => {
      e.write("for")
      e.space()
      e.write("(")
      emit_for_of_kind(e, kind)
      emit_binding(e, binding)
      e.write(" in ")
      emit_expr(e, iter, 0)
      e.write(")")
      e.space()
      emit_branch_body(e, body)
    }
    Switch(scrutinee, cases) => {
      e.write("switch")
      e.space()
      e.write("(")
      emit_expr(e, scrutinee, 0)
      e.write(")")
      e.space()
      e.open_block()
      for case_ in cases {
        e.nl()
        match case_.test_expr {
          Some(t) => {
            e.word("case")
            e.sep_after_word(expr_leading_byte(t))
            emit_expr(e, t, 0)
            e.write(":")
          }
          None => e.write("default:")
        }
        e.indent = e.indent + 1
        for s in case_.body.stmts {
          e.nl()
          emit_stmt(e, s)
        }
        e.indent = e.indent - 1
      }
      e.close_block()
    }
    Try(try_b, catch_bind, catch_b, finally_b) => {
      e.write("try ")
      emit_block(e, try_b)
      match (catch_bind, catch_b) {
        (_, Some(cb)) => {
          e.space()
          e.write("catch")
          match catch_bind {
            Some(b) => {
              e.space()
              e.write("(")
              emit_binding(e, b)
              e.write(")")
            }
            None => ()
          }
          e.space()
          emit_block(e, cb)
        }
        _ => ()
      }
      match finally_b {
        Some(fb) => {
          e.space()
          e.write("finally")
          e.space()
          emit_block(e, fb)
        }
        None => ()
      }
    }
    Break(label) =>
      match label {
        Some(l) => e.write("break " + l + ";")
        None => e.write("break;")
      }
    Continue(label) =>
      match label {
        Some(l) => e.write("continue " + l + ";")
        None => e.write("continue;")
      }
    Block(b) => emit_block(e, b)
    NativeClassStmt(decl, ctor_body) => emit_native_class(e, decl, ctor_body)
    Label(name, inner) => {
      e.write(name + ":")
      e.space()
      emit_stmt(e, inner)
    }
    With(target, body) => {
      e.write("with")
      e.space()
      e.write("(")
      emit_expr(e, target, 0)
      e.write(")")
      e.space()
      emit_block(e, body)
    }
    Debugger => e.write("debugger;")
  }
}

///|
/// Inside the head of a `for(init; cond; update)`, statements emit
/// without a trailing semicolon (the loop syntax supplies the `;`).
///|
/// Guess the first byte the emitter will write for `expr`. Used by
/// `sep_after_word` to decide whether the optional whitespace
/// between a keyword and the next expression is needed in minify
/// mode. Returns a punctuator byte for shapes we know don't extend
/// the preceding word, and `?` (always-needs-space) for everything
/// else.
fn expr_leading_byte(expr : @ast.TsExpr) -> Char {
  match expr {
    ObjectLit(_) | ComputedProp(_, _) => '{'
    ArrayLit(_) => '['
    StringLit(_) => '"'
    TemplateLiteral(_, _) | TaggedTemplate(_, _, _, _) => '`'
    NumberLit(_) | IntLit(_) => '0'
    BigIntLit(_) => '0'
    BoolLit(_) => '?'
    NullLit => '?'
    UnaryOp(op, _) =>
      match op {
        Not => '!'
        BitwiseNot => '~'
        Neg => '-'
        Plus => '+'
        _ => '?'
      }
    Call(_, _) | New(_, _) | Var(_) => '?'
    CallExpr(callee, _) | NewExpr(callee, _) => expr_leading_byte(callee)
    MethodCall(recv, _, _) | PropAccess(recv, _) | IndexAccess(recv, _) =>
      expr_leading_byte(recv)
    ArrowFunc(_, _, _, _) => '('
    FuncExpr(_) => '?'
    _ => '?'
  }
}

///|
///|
/// First byte a top-level statement will emit, for the purpose of
/// deciding whether an `else` keyword must be separated from its
/// braceless body by a space.
fn stmt_leading_byte(stmt : @ast.TsStmt) -> Char {
  match stmt {
    If(_, _, _) => 'i'
    While(_, _) => 'w'
    For(_, _, _, _) | ForOf(_, _, _, _, _) | ForIn(_, _, _, _, _) => 'f'
    DoWhile(_, _) => 'd'
    Switch(_, _) => 's'
    Try(_, _, _, _) => 't'
    Throw(_) => 't'
    Return(_) => 'r'
    Block(_) => '{'
    Expr(e) => expr_leading_byte(e)
    Empty => ';'
    _ => '?'
  }
}

///|
/// First byte the binding emit will write — used by callers to skip
/// the keyword separator when the binding starts with a `{` / `[`
/// destructure pattern.
fn binding_leading_byte(b : @ast.TsBinding) -> Char {
  match b {
    Ident(_) => '?'
    Array(_) => '['
    Object(_) => '{'
    Target(_) => '?'
  }
}

///|
/// Recognize the parser's `for (let i = 0, n = arr.length; …)` lower
/// — a `Block` of same-kind single-ident declarations — and emit
/// the original comma-separated form. Returns `true` when the
/// pattern matched.
fn try_emit_multi_decl_for_head(e : Emitter, stmt : @ast.TsStmt) -> Bool {
  let block = match stmt {
    Block(b) => b
    _ => return false
  }
  if block.stmts.length() < 2 {
    return false
  }
  // All stmts must be the same lexical kind.
  let kind = match block.stmts[0] {
    Var(_, _, _) => "var"
    Let(_, _, _) => "let"
    Const(_, _, _) => "const"
    _ => return false
  }
  for s in block.stmts {
    match s {
      Var(_, _, _) => if kind != "var" { return false }
      Let(_, _, _) => if kind != "let" { return false }
      Const(_, _, _) => if kind != "const" { return false }
      _ => return false
    }
  }
  // Emit `kind name = init, name = init, ...`.
  // Downgrade `const` to `let` in minify mode (see `Const` cases
  // above).
  let emitted_kind = if kind == "const" && not(e.pretty) {
    "let"
  } else {
    kind
  }
  e.word(emitted_kind)
  // The first byte after the kind is the first binding's leading
  // byte (always `?` for identifier-only in our parser path here).
  let first_byte = match block.stmts[0] {
    Var(b, _, _) | Let(b, _, _) | Const(b, _, _) => binding_leading_byte(b)
    _ => '?'
  }
  e.sep_after_word(first_byte)
  for i, s in block.stmts {
    if i > 0 {
      e.write(",")
      e.space()
    }
    match s {
      Var(b, _, init) | Let(b, _, init) | Const(b, _, init) => {
        emit_binding(e, b)
        e.space()
        e.write("=")
        e.space()
        emit_expr(e, init, 0)
      }
      _ => ()
    }
  }
  true
}

///|
fn emit_stmt_for_head(e : Emitter, stmt : @ast.TsStmt) -> Unit {
  // The parser wraps comma-separated decls (`for (let i = 0, n = …;`)
  // in a Block since they parse as multiple statements. JS grammar
  // requires a single declaration with comma-separated binders here,
  // so detect the same-kind-block pattern and unfold it.
  match try_emit_multi_decl_for_head(e, stmt) {
    true => return
    false => ()
  }
  match stmt {
    Var(b, _, init) => {
      e.word("var")
      e.sep_after_word(binding_leading_byte(b))
      emit_binding(e, b)
      e.space()
      e.write("=")
      e.space()
      emit_expr(e, init, 0)
    }
    Let(b, _, init) => {
      e.word("let")
      e.sep_after_word(binding_leading_byte(b))
      emit_binding(e, b)
      e.space()
      e.write("=")
      e.space()
      emit_expr(e, init, 0)
    }
    Const(b, _, init) => {
      if e.pretty {
        e.word("const")
      } else {
        e.word("let")
      }
      e.sep_after_word(binding_leading_byte(b))
      emit_binding(e, b)
      e.space()
      e.write("=")
      e.space()
      emit_expr(e, init, 0)
    }
    Expr(ex) => emit_expr(e, ex, 0)
    Assign(name, ex) => {
      e.write(name)
      e.space()
      e.write("=")
      e.space()
      emit_expr(e, ex, 0)
    }
    CompoundAssign(name, op, ex) => {
      e.write(name)
      e.space()
      e.write(compound_op_str(op))
      e.space()
      emit_expr(e, ex, 0)
    }
    _ => emit_stmt(e, stmt)
  }
}

///|
fn emit_for_of_kind(e : Emitter, kind : @ast.TsForOfKind) -> Unit {
  match kind {
    Var => e.write("var ")
    Let => e.write("let ")
    // Same idea as the statement-level `Const`: in minify mode the
    // loop binder doesn't need to be `const`, since the original
    // source already proved no reassignment.
    Const => if e.pretty { e.write("const ") } else { e.write("let ") }
    Assign => ()
  }
}

///|
fn emit_binding(e : Emitter, binding : @ast.TsBinding) -> Unit {
  match binding {
    Ident(name) => e.write(name)
    Array(ab) => {
      e.write("[")
      for i, elem in ab.items {
        if i > 0 {
          e.write(",")
          e.space()
        }
        match elem {
          Some(be) => {
            emit_binding(e, be.binding)
            match be.default {
              Some(d) => {
                e.space()
                e.write("=")
                e.space()
                emit_expr(e, d, 0)
              }
              None => ()
            }
          }
          None => ()
        }
      }
      match ab.rest {
        Some(rest) => {
          if ab.items.length() > 0 {
            e.write(",")
            e.space()
          }
          e.write("...")
          emit_binding(e, rest)
        }
        None => ()
      }
      e.write("]")
    }
    Object(ob) => {
      e.write("{")
      for i, prop in ob.props {
        if i > 0 {
          e.write(",")
          e.space()
        }
        // Emit `key: alias` only when alias differs from key.
        let written_key = match prop.key_expr {
          Some(ke) => {
            e.write("[")
            emit_expr(e, ke, 0)
            e.write("]")
            true
          }
          None => {
            e.write(prop.key)
            false
          }
        }
        let _ = written_key
        // Distinguish bare `{ key }` shorthand vs. `{ key: alias }`.
        match prop.binding {
          Ident(local) if local == prop.key => ()
          _ => {
            e.write(":")
            e.space()
            emit_binding(e, prop.binding)
          }
        }
        match prop.default {
          Some(d) => {
            e.space()
            e.write("=")
            e.space()
            emit_expr(e, d, 0)
          }
          None => ()
        }
      }
      match ob.rest {
        Some(rest) => {
          if ob.props.length() > 0 {
            e.write(",")
            e.space()
          }
          e.write("...")
          e.write(rest)
        }
        None => ()
      }
      e.write("}")
    }
    Target(expr) => emit_expr(e, expr, 0)
  }
}

// ---------------------------------------------------------------------------
// Expressions — operator-precedence-aware emit. The `parent_prec`
// argument is the precedence level of the surrounding context; when an
// expression's own precedence is *lower*, it must be parenthesised.
// Precedence numbers follow the ECMA-262 grammar:
//   1  comma
//   2  assignment / yield
//   3  conditional ?:
//   4  ??
//   5  ||
//   6  &&
//   7  |
//   8  ^
//   9  &
//   10 ===, !==, ==, !=
//   11 <, <=, >, >=, in, instanceof
//   12 <<, >>, >>>
//   13 +, -
//   14 *, /, %
//   15 **
//   16 unary
//   17 update (++, --)
//   18 call / new / member
//   19 primary
// ---------------------------------------------------------------------------

///|
fn emit_expr(e : Emitter, expr : @ast.TsExpr, parent_prec : Int) -> Unit {
  let own = expr_precedence(expr)
  let needs_paren = own < parent_prec
  if needs_paren {
    e.write("(")
  }
  emit_expr_body(e, expr)
  if needs_paren {
    e.write(")")
  }
}

///|
fn emit_expr_body(e : Emitter, expr : @ast.TsExpr) -> Unit {
  match expr {
    NumberLit(n) => e.write(n.to_string())
    IntLit(n) => e.write(n.to_string())
    BigIntLit(s) => {
      e.write(s)
      e.write("n")
    }
    BoolLit(b) => e.write(if b { "true" } else { "false" })
    StringLit(s) => emit_string_literal(e, s)
    NullLit => e.write("null")
    ArrayHole => ()
    Var(name) => e.write(name)
    BinOp(op, l, r) => {
      let prec = binop_precedence(op)
      emit_expr(e, l, prec)
      e.space()
      e.write(binop_str(op))
      e.space()
      // Right-associative ** uses prec, others prec+1 so left chains.
      let right_prec = match op {
        Pow => prec
        _ => prec + 1
      }
      emit_expr(e, r, right_prec)
    }
    UnaryOp(op, inner) =>
      match op {
        PostInc => {
          emit_expr(e, inner, 17)
          e.write("++")
        }
        PostDec => {
          emit_expr(e, inner, 17)
          e.write("--")
        }
        _ => {
          e.write(unary_op_str(op))
          // `typeof` / `void` / `delete` are word operators; they need
          // a separator before their operand.
          match op {
            Typeof | Void | Delete => e.write(" ")
            _ => ()
          }
          emit_expr(e, inner, 16)
        }
      }
    Call(name, args) => {
      e.write(name)
      emit_args(e, args)
    }
    CallExpr(callee, args) => {
      emit_expr(e, callee, 18)
      emit_args(e, args)
    }
    Cond(cond, then_e, else_e) => {
      emit_expr(e, cond, 4)
      e.space()
      e.write("?")
      e.space()
      emit_expr(e, then_e, 2)
      e.space()
      e.write(":")
      e.space()
      emit_expr(e, else_e, 2)
    }
    ArrayLit(items) => {
      e.write("[")
      for i, item in items {
        if i > 0 {
          e.write(",")
          e.space()
        }
        emit_expr(e, item, 2)
      }
      e.write("]")
    }
    Spread(inner) => {
      e.write("...")
      emit_expr(e, inner, 2)
    }
    ObjectLit(entries) => {
      e.write("{")
      for i, entry in entries {
        if i > 0 {
          e.write(",")
          e.space()
        }
        // JSX-runtime lowering encodes object-spread props as a
        // sentinel `("...", Spread(expr))` entry. Emit those as the
        // `...expr` shorthand instead of `"...": expr`.
        match entry {
          ("...", Spread(inner)) => {
            e.write("...")
            emit_expr(e, inner, 2)
          }
          _ => {
            e.write(entry.0)
            e.write(":")
            e.space()
            emit_expr(e, entry.1, 2)
          }
        }
      }
      e.write("}")
    }
    ComputedProp(key_expr, value_expr) => {
      e.write("[")
      emit_expr(e, key_expr, 0)
      e.write("]:")
      e.space()
      emit_expr(e, value_expr, 2)
    }
    IndexAccess(recv, idx) => {
      emit_expr(e, recv, 18)
      e.write("[")
      emit_expr(e, idx, 0)
      e.write("]")
    }
    PropAccess(recv, name) => {
      emit_expr(e, recv, 18)
      e.write(".")
      e.write(strip_internal_prop_marker(name))
    }
    New(name, args) => {
      e.write("new ")
      e.write(name)
      emit_args(e, args)
    }
    NewExpr(callee, args) => {
      e.write("new ")
      // `new X(args)` requires `X` to be a `MemberExpression`. A
      // call expression / new expression / arrow doesn't match,
      // so wrap it in parens — otherwise `new (a())(b)` would
      // parse as `new a()` followed by `(b)`.
      let needs_paren = match callee {
        Call(_, _) | CallExpr(_, _) | New(_, _) | NewExpr(_, _) => true
        ArrowFunc(_, _, _, _) | FuncExpr(_) => true
        BinOp(_, _, _) | Cond(_, _, _) | Seq(_, _) => true
        UnaryOp(_, _) | AssignExpr(_, _) | CompoundAssignExpr(_, _, _) => true
        _ => false
      }
      if needs_paren {
        e.write("(")
        emit_expr(e, callee, 0)
        e.write(")")
      } else {
        emit_expr(e, callee, 18)
      }
      emit_args(e, args)
    }
    MethodCall(recv, method, args) => {
      emit_expr(e, recv, 18)
      e.write(".")
      e.write(strip_internal_prop_marker(method))
      emit_args(e, args)
    }
    AssignExpr(name, value) => {
      e.write(name)
      e.space()
      e.write("=")
      e.space()
      emit_expr(e, value, 2)
    }
    AssignPattern(binding, value) => {
      emit_binding(e, binding)
      e.space()
      e.write("=")
      e.space()
      emit_expr(e, value, 2)
    }
    CompoundAssignExpr(target, op, value) => {
      emit_expr(e, target, 18)
      e.space()
      e.write(compound_op_str(op))
      e.space()
      emit_expr(e, value, 2)
    }
    PropAssignExpr(recv, prop, value) => {
      emit_expr(e, recv, 18)
      e.write(".")
      e.write(strip_internal_prop_marker(prop))
      e.space()
      e.write("=")
      e.space()
      emit_expr(e, value, 2)
    }
    IndexAssignExpr(recv, idx, value) => {
      emit_expr(e, recv, 18)
      e.write("[")
      emit_expr(e, idx, 0)
      e.write("]")
      e.space()
      e.write("=")
      e.space()
      emit_expr(e, value, 2)
    }
    Seq(a, b) => {
      emit_expr(e, a, 2)
      e.write(",")
      e.space()
      emit_expr(e, b, 2)
    }
    ArrowFunc(params, _ret_ty, body, is_async) => {
      if is_async {
        e.write("async ")
      }
      e.write("(")
      emit_runtime_params(e, params)
      e.write(")")
      e.space()
      e.write("=>")
      e.space()
      match body {
        ArrowExpr(inner) => emit_expr(e, inner, 2)
        ArrowBlock(block) => emit_block(e, block)
      }
    }
    FuncExpr(f) => emit_function_expr(e, f)
    Yield(opt) =>
      match opt {
        Some(inner) => {
          e.write("yield ")
          emit_expr(e, inner, 2)
        }
        None => e.write("yield")
      }
    YieldStar(inner) => {
      e.write("yield* ")
      emit_expr(e, inner, 2)
    }
    Await(inner) => {
      e.write("await ")
      emit_expr(e, inner, 16)
    }
    DynamicImport(spec, opts) => {
      e.write("import(")
      emit_expr(e, spec, 0)
      match opts {
        Some(o) => {
          e.write(",")
          e.space()
          emit_expr(e, o, 0)
        }
        None => ()
      }
      e.write(")")
    }
    ImportMeta => e.write("import.meta")
    TaggedTemplate(tag, parts, _raw, exprs) => {
      emit_expr(e, tag, 18)
      emit_template_literal(e, parts, exprs)
    }
    TemplateLiteral(parts, exprs) => emit_template_literal(e, parts, exprs)
    // TS-only wrappers — strip and emit the inner expression.
    As(inner, _) | Satisfies(inner, _) | NonNull(inner) =>
      emit_expr_body(e, inner)
    OptionalChain(inner) => {
      // The wrapped inner expression encodes the access shape; we
      // restore the `?.` separator here. Each `?.` step in the
      // original source produces one OptionalChain wrap, so
      // nested chains (`obj?.foo?.bar`) get one wrap per step.
      match inner {
        PropAccess(recv, name) => {
          emit_expr(e, recv, 18)
          e.write("?.")
          e.write(strip_internal_prop_marker(name))
        }
        IndexAccess(recv, idx) => {
          emit_expr(e, recv, 18)
          e.write("?.[")
          emit_expr(e, idx, 0)
          e.write("]")
        }
        MethodCall(recv, method, args) => {
          emit_expr(e, recv, 18)
          e.write("?.")
          e.write(strip_internal_prop_marker(method))
          emit_args(e, args)
        }
        Call(name, args) => {
          e.write(name)
          e.write("?.")
          emit_args(e, args)
        }
        CallExpr(callee, args) => {
          emit_expr(e, callee, 18)
          e.write("?.")
          emit_args(e, args)
        }
        _ => emit_expr_body(e, inner)
      }
    }
    JsxElement(tag, attrs, children) =>
      emit_jsx_element(e, tag, attrs, children)
    NativeClassExpr(decl, ctor_body) =>
      emit_native_class(e, decl, ctor_body)
    PureCall(inner) => {
      // Restore the `/* @__PURE__ */` annotation so downstream
      // minifiers (terser, esbuild, rolldown) keep treating the
      // call as droppable when the result is unused. The comment
      // appears immediately before the call body.
      e.write("/* @__PURE__ */ ")
      emit_expr_body(e, inner)
    }
  }
}

///|
fn emit_args(e : Emitter, args : Array[@ast.TsExpr]) -> Unit {
  e.write("(")
  for i, a in args {
    if i > 0 {
      e.write(",")
      e.space()
    }
    emit_expr(e, a, 2)
  }
  e.write(")")
}

///|
fn emit_template_literal(
  e : Emitter,
  parts : Array[String],
  exprs : Array[@ast.TsExpr],
) -> Unit {
  e.write("`")
  for i, part in parts {
    e.write(part)
    if i < exprs.length() {
      e.write("${")
      emit_expr(e, exprs[i], 0)
      e.write("}")
    }
  }
  e.write("`")
}

///|
fn emit_jsx_element(
  e : Emitter,
  tag : String,
  attrs : Array[(String, @ast.TsExpr?)],
  children : Array[@ast.TsExpr],
) -> Unit {
  // Faithful round-trip: emit JSX source-form. A subsequent pass will
  // lower this to `React.createElement(...)` calls; for now we keep
  // the surface intact so callers using `@vitejs/plugin-react` /
  // `esbuild --loader=jsx` can take over.
  if tag == "" {
    // Fragment.
    e.write("<>")
    for child in children {
      emit_jsx_child(e, child)
    }
    e.write("</>")
    return
  }
  e.write("<")
  e.write(tag)
  for entry in attrs {
    let name = entry.0
    e.write(" ")
    if name == "" {
      // Spread.
      match entry.1 {
        Some(value) => {
          e.write("{...")
          emit_expr(e, value, 0)
          e.write("}")
        }
        None => ()
      }
    } else {
      e.write(name)
      match entry.1 {
        Some(StringLit(s)) => {
          e.write("=\"")
          e.write(s)
          e.write("\"")
        }
        Some(value) => {
          e.write("={")
          emit_expr(e, value, 0)
          e.write("}")
        }
        None => ()
      }
    }
  }
  if children.length() == 0 {
    e.write(" />")
    return
  }
  e.write(">")
  for child in children {
    emit_jsx_child(e, child)
  }
  e.write("</")
  e.write(tag)
  e.write(">")
}

///|
fn emit_jsx_child(e : Emitter, child : @ast.TsExpr) -> Unit {
  match child {
    StringLit(s) => e.write(s)
    JsxElement(t, a, c) => emit_jsx_element(e, t, a, c)
    _ => {
      e.write("{")
      emit_expr(e, child, 0)
      e.write("}")
    }
  }
}

///|
///|
/// Recognize the `Let / Const / Var(Ident(N), _, FuncExpr(f))`
/// pattern the parser produces for `function foo() {…}` and emit a
/// real function declaration. Returns `true` when the pattern
/// matched (caller should skip the regular Let / Const / Var path).
///
/// Constraints:
/// - The outer binding name must be a valid JS identifier (the
///   bundle's merged top-level block guarantees this for source-
///   derived names; mangle renames stay alphabetic too).
/// - We emit the outer name as the function declaration's name and
///   drop the FuncExpr internal name. Recursive calls in the body
///   referenced the outer binding by `Var(...)`, which the mangler
///   already kept in sync; the internal name is unreferenced after
///   that pass.
fn try_emit_function_decl(e : Emitter, stmt : @ast.TsStmt) -> Bool {
  let (name, func) = match stmt {
    Let(@ast.TsBinding::Ident(n), _, @ast.TsExpr::FuncExpr(f)) => (n, f)
    Const(@ast.TsBinding::Ident(n), _, @ast.TsExpr::FuncExpr(f)) => (n, f)
    Var(@ast.TsBinding::Ident(n), _, @ast.TsExpr::FuncExpr(f)) => (n, f)
    _ => return false
  }
  if name == "" || not(is_valid_js_ident(name)) {
    return false
  }
  // Async function declarations: emit `async function foo() {…}`.
  if func.is_async {
    e.write("async ")
  }
  e.write("function")
  if func.is_generator {
    e.write("*")
  }
  e.write(" ")
  e.write(name)
  e.write("(")
  emit_runtime_params(e, func.params)
  e.write(")")
  e.space()
  emit_block(e, func.body)
  true
}

///|
fn emit_function_expr(e : Emitter, f : @ast.TsFunc) -> Unit {
  e.write("function")
  if f.is_generator {
    e.write("*")
  }
  // Synthesized class-desugar nodes carry a placeholder `<class>` /
  // `<anon>` name. Those aren't valid JS identifiers, so emit the
  // expression in its anonymous form (`function () {…}`).
  if f.name != "" && is_valid_js_ident(f.name) {
    e.write(" ")
    e.write(f.name)
  }
  e.write("(")
  emit_runtime_params(e, f.params)
  e.write(")")
  e.space()
  emit_block(e, f.body)
  let _ = f.is_async
}

///|
/// Emit the runtime parameter list for a function / arrow / method,
/// filtering out the TypeScript-only `this` annotation parameter.
/// `this` at index 0 has no runtime slot — it's a type annotation
/// for the receiver. Letting it through produces `function f(this)`,
/// which V8 rejects as a syntax error.
fn emit_runtime_params(e : Emitter, params : Array[@ast.TsParam]) -> Unit {
  let mut written = 0
  for p in params {
    if is_this_type_annotation_param(p) {
      continue
    }
    if written > 0 {
      e.write(",")
      e.space()
    }
    written = written + 1
    if p.is_rest {
      e.write("...")
    }
    match p.binding {
      Some(b) => emit_binding(e, b)
      None => e.write(p.name)
    }
    match p.default {
      Some(d) => {
        e.space()
        e.write("=")
        e.space()
        emit_expr(e, d, 2)
      }
      None => ()
    }
  }
}

///|
/// `function f(this: T, ...)` declares the receiver's type, not a
/// runtime argument. JS rejects `this` as a parameter name, so we
/// drop the slot during emit.
fn is_this_type_annotation_param(p : @ast.TsParam) -> Bool {
  if p.is_rest {
    return false
  }
  if p.name != "this" {
    return false
  }
  match p.binding {
    None => true
    Some(@ast.TsBinding::Ident(n)) => n == "this"
    _ => false
  }
}

///|
/// Quick check: is `s` a syntactically valid JS identifier? Used to
/// decide whether to emit a name on a synthesized function
/// expression. We only need a coarse rejector — the parser handles
/// the full Unicode case for real source identifiers.
fn is_valid_js_ident(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let head = s[0]
  let head_ok = (head >= 'a' && head <= 'z') ||
    (head >= 'A' && head <= 'Z') ||
    head == '_' ||
    head == '$'
  if not(head_ok) {
    return false
  }
  for i = 1; i < s.length(); i = i + 1 {
    let c = s[i]
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '$'
    if not(ok) {
      return false
    }
  }
  true
}

///|
/// The class-desugar parser tags method-definition property keys with
/// a synthetic `@@define:` prefix so the checker can distinguish them
/// from plain property assignments. The runtime JS doesn't carry that
/// marker — strip it before emit.
fn strip_internal_prop_marker(name : String) -> String {
  if name.has_prefix("@@define:") {
    name.substring(start=9, end=name.length()).to_string()
  } else {
    name
  }
}

///|
fn emit_string_literal(e : Emitter, s : String) -> Unit {
  e.write("\"")
  for c in s {
    match c {
      '"' => e.write("\\\"")
      '\\' => e.write("\\\\")
      '\n' => e.write("\\n")
      '\r' => e.write("\\r")
      '\t' => e.write("\\t")
      _ => e.write(c.to_string())
    }
  }
  e.write("\"")
}

// ---------------------------------------------------------------------------
// Operator string + precedence tables.
// ---------------------------------------------------------------------------

///|
fn binop_str(op : @ast.TsBinOp) -> String {
  match op {
    Add => "+"
    Sub => "-"
    Mul => "*"
    Div => "/"
    Mod => "%"
    Pow => "**"
    BitAnd => "&"
    BitOr => "|"
    BitXor => "^"
    Shl => "<<"
    Shr => ">>"
    UShr => ">>>"
    BinEq => "==="
    BinNe => "!=="
    AbstractEq => "=="
    AbstractNe => "!="
    BinLt => "<"
    BinLe => "<="
    BinGt => ">"
    BinGe => ">="
    Instanceof => "instanceof"
    In => "in"
    And => "&&"
    Or => "||"
    Coalesce => "??"
  }
}

///|
fn binop_precedence(op : @ast.TsBinOp) -> Int {
  match op {
    Coalesce => 4
    Or => 5
    And => 6
    BitOr => 7
    BitXor => 8
    BitAnd => 9
    BinEq | BinNe | AbstractEq | AbstractNe => 10
    BinLt | BinLe | BinGt | BinGe | Instanceof | In => 11
    Shl | Shr | UShr => 12
    Add | Sub => 13
    Mul | Div | Mod => 14
    Pow => 15
  }
}

///|
fn unary_op_str(op : @ast.TsUnaryOp) -> String {
  match op {
    Neg => "-"
    Not => "!"
    BitwiseNot => "~"
    Plus => "+"
    Typeof => "typeof"
    Void => "void"
    Delete => "delete"
    PreInc => "++"
    PreDec => "--"
    PostInc => "++"
    PostDec => "--"
  }
}

///|
fn compound_op_str(op : @ast.TsCompoundOp) -> String {
  match op {
    AddAssign => "+="
    SubAssign => "-="
    MulAssign => "*="
    DivAssign => "/="
    ModAssign => "%="
    BitAndAssign => "&="
    BitOrAssign => "|="
    BitXorAssign => "^="
    ShlAssign => "<<="
    ShrAssign => ">>="
    UShrAssign => ">>>="
    PowAssign => "**="
    AndAssign => "&&="
    OrAssign => "||="
    CoalesceAssign => "??="
  }
}

///|
fn expr_precedence(expr : @ast.TsExpr) -> Int {
  match expr {
    NumberLit(_)
    | IntLit(_)
    | BigIntLit(_)
    | BoolLit(_)
    | StringLit(_)
    | NullLit
    | ArrayHole
    | Var(_)
    | ArrayLit(_)
    | ObjectLit(_)
    | ImportMeta
    | TemplateLiteral(_, _)
    | JsxElement(_, _, _) => 19
    BinOp(op, _, _) => binop_precedence(op)
    UnaryOp(op, _) =>
      match op {
        PostInc | PostDec => 17
        PreInc | PreDec => 17
        _ => 16
      }
    Call(_, _)
    | CallExpr(_, _)
    | New(_, _)
    | NewExpr(_, _)
    | MethodCall(_, _, _)
    | PropAccess(_, _)
    | IndexAccess(_, _)
    | TaggedTemplate(_, _, _, _) => 18
    Cond(_, _, _) => 3
    AssignExpr(_, _)
    | AssignPattern(_, _)
    | CompoundAssignExpr(_, _, _)
    | PropAssignExpr(_, _, _)
    | IndexAssignExpr(_, _, _)
    | ArrowFunc(_, _, _, _)
    | Yield(_)
    | YieldStar(_) => 2
    Seq(_, _) => 1
    Await(_) => 16
    Spread(_) => 2
    ComputedProp(_, _) => 19
    FuncExpr(_) => 19
    DynamicImport(_, _) => 18
    // Class expressions sit at the same precedence as function
    // expressions — both are primary atoms.
    NativeClassExpr(_, _) => 19
    // `PureCall` is a transparent marker — its precedence equals
    // the wrapped call's so paren-wrapping decisions stay
    // consistent.
    PureCall(inner) => expr_precedence(inner)
    // TS-only wrappers — same precedence as their inner expression.
    As(inner, _) | Satisfies(inner, _) | NonNull(inner) | OptionalChain(inner) =>
      expr_precedence(inner)
  }
}

///|
/// Emit a native `class Name extends Base { … }` declaration. Used
/// when the parser bypassed the IIFE desugar — primarily for
/// `class X extends Y` shapes where the desugar's `super(…)` call
/// would be invalid outside a method body.
fn emit_native_class(
  e : Emitter,
  decl : @ast.TsClassDecl,
  ctor_func : @ast.TsFunc?,
) -> Unit {
  e.word("class")
  if decl.name != "" && is_valid_js_ident(decl.name) {
    e.sep_after_word('A')
    e.write(decl.name)
  }
  if decl.base_names.length() > 0 {
    e.space()
    e.write("extends")
    e.sep_after_word('A')
    e.write(decl.base_names[0])
  }
  e.space()
  e.open_block()
  // Constructor — emit the full TsFunc so rest / default /
  // destructuring params are preserved verbatim.
  match ctor_func {
    Some(func) => {
      e.nl()
      e.write("constructor")
      e.write("(")
      emit_runtime_params(e, func.params)
      e.write(")")
      e.space()
      emit_block(e, func.body)
    }
    None => ()
  }
  // Methods.
  for m in decl.methods {
    e.nl()
    if m.is_static {
      e.word("static")
      e.sep_after_word('A')
    }
    e.write(m.name)
    e.write("(")
    for i, p in m.params {
      if i > 0 {
        e.write(",")
        e.space()
      }
      e.write(p.0)
    }
    e.write(")")
    e.space()
    match m.body {
      Some(b) => emit_block(e, b)
      None => {
        e.write("{")
        e.write("}")
      }
    }
  }
  e.close_block()
}

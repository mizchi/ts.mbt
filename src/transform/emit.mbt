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
fn Emitter::new(pretty? : Bool = true) -> Emitter {
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
  // In minify mode, the emit loop leaves a trailing `;` after the last
  // statement (the final `nl()` flushes `pending_semi`). Strip it — the
  // semicolon is syntactically optional at the end of a script and saves
  // 1 byte per bundle.
  if self.pending_semi {
    // Semi still parked (wasn't flushed by nl()). Nothing to strip.
    return self.buf.to_string()
  }
  let s = self.buf.to_string()
  if not(self.pretty) && s.has_suffix(";") {
    s.substring(end=s.length() - 1).to_string()
  } else {
    s
  }
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
  with_sourcemap? : Bool = false,
  source_path? : String = "input.ts",
  output_path? : String = "output.js",
  mangle? : Bool = false,
  mangle_properties? : Bool = false,
  minify? : Bool = false,
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
  // Constant-fold before mangle so the mangler sees already-simplified
  // expressions (shorter names are assigned to already-reduced code).
  let folded = if minify { fold_block(lowered) } else { lowered }
  // Lift IIFE-lowered classes to native `class` syntax in minify mode.
  // The parser lowers TS classes with getters/setters/statics to IIFEs;
  // re-lifting to class saves ~40+ bytes per class that qualifies.
  let folded = if minify { iife_class_lift_block(folded) } else { folded }
  let mangled = if mangle {
    let mangler_cfg = ManglerConfig::default().with_mangle_properties(
      mangle_properties,
    )
    mangle_block(folded, mangler_cfg)
  } else {
    folded
  }
  // Single-use binding inlining: `const x = expr; f(x)` → `f(expr)`.
  // Runs after mangle so the already-shortened names are inlined,
  // keeping the inline table small.
  let mangled = if minify { inline_block(mangled) } else { mangled }
  let mangled = if minify { peephole_block(mangled) } else { mangled }
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
  let emit_positions = not(mangle) && with_sourcemap
  // In minify mode without source maps, use the merged-decl emitter so
  // `let a=1;let b=2;` collapses to `let a=1,b=2;` at the top level too.
  if not(emit_positions) {
    emit_stmts_merged(e, mangled.stmts)
  } else {
    for i, stmt in mangled.stmts {
      if emit_positions && i < positions.length() {
        let src_pos = e.line_index.position(positions[i])
        e.mark(src_pos)
      }
      emit_stmt(e, stmt)
      e.nl()
    }
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
  let stmts = block.stmts
  let n = stmts.length()
  let mut i = 0
  while i < n {
    let stmt = stmts[i]
    e.nl()
    // Record a source-map segment when positions are available.
    match e.smap {
      Some(_) =>
        if i < block.stmt_positions.length() {
          let src_pos = e.line_index.position(block.stmt_positions[i])
          e.mark(src_pos)
        }
      None => ()
    }
    // In minify mode, merge consecutive same-kind declarations:
    // `let a=1;let b=2;` → `let a=1,b=2;` (saves 4 bytes per merged decl).
    // Only in minify mode to avoid changing pretty output.
    // `const` is treated as `let` in minify mode (matching try_emit_multi_decl_inline).
    if not(e.pretty) {
      let decl_kind : String? = match stmt {
        @ast.TsStmt::Let(_, _, _) => Some("let")
        @ast.TsStmt::Const(_, _, _) => Some("let")
        @ast.TsStmt::Var(_, _, _) => Some("var")
        _ => None
      }
      match decl_kind {
        Some(kind) => {
          // Collect this and all following same-kind declarations into a group.
          let group : Array[@ast.TsStmt] = [stmt]
          let mut j = i + 1
          while j < n {
            let next = stmts[j]
            let next_kind : String? = match next {
              @ast.TsStmt::Let(_, _, _) => Some("let")
              @ast.TsStmt::Const(_, _, _) => Some("let")
              @ast.TsStmt::Var(_, _, _) => Some("var")
              _ => None
            }
            if next_kind == Some(kind) {
              group.push(next)
              j = j + 1
            } else {
              break
            }
          }
          if group.length() > 1 {
            // Emit as merged: `let a=init_a,b=init_b,...;`
            let first_byte = match group[0] {
              @ast.TsStmt::Var(b, _, _)
              | @ast.TsStmt::Let(b, _, _)
              | @ast.TsStmt::Const(b, _, _) => binding_leading_byte(b)
              _ => '?'
            }
            e.word(kind)
            e.sep_after_word(first_byte)
            for k, gs in group {
              if k > 0 {
                e.write(",")
                e.space()
              }
              match gs {
                @ast.TsStmt::Var(b, _, init)
                | @ast.TsStmt::Let(b, _, init)
                | @ast.TsStmt::Const(b, _, init) => {
                  emit_binding(e, b)
                  let is_undef_init = match init {
                    @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, _) => true
                    @ast.TsExpr::Var("undefined") => true
                    _ => false
                  }
                  if not(is_undef_init) {
                    e.space()
                    e.write("=")
                    e.space()
                    emit_expr(e, init, 0)
                  }
                }
                _ => ()
              }
            }
            e.semi()
            i = j
            continue
          }
          emit_stmt(e, stmt)
          i = i + 1
          continue
        }
        None => ()
      }
    }
    emit_stmt(e, stmt)
    i = i + 1
  }
  e.close_block()
}

///|
/// Emit a flat array of statements with the same minify-mode
/// declaration-merging logic used by `emit_block`. Call this for
/// top-level stmt lists (bundle, transform_source_full) so that
/// `let a=1;let b=2;` → `let a=1,b=2;` at the module scope too.
/// In pretty mode every statement is emitted verbatim (no merging).
fn emit_stmts_merged(e : Emitter, stmts : Array[@ast.TsStmt]) -> Unit {
  let n = stmts.length()
  let mut i = 0
  while i < n {
    let stmt = stmts[i]
    e.nl()
    if not(e.pretty) {
      let decl_kind : String? = match stmt {
        @ast.TsStmt::Let(_, _, _) => Some("let")
        @ast.TsStmt::Const(_, _, _) => Some("let")
        @ast.TsStmt::Var(_, _, _) => Some("var")
        _ => None
      }
      match decl_kind {
        Some(kind) => {
          let group : Array[@ast.TsStmt] = [stmt]
          let mut j = i + 1
          while j < n {
            let next = stmts[j]
            let next_kind : String? = match next {
              @ast.TsStmt::Let(_, _, _) => Some("let")
              @ast.TsStmt::Const(_, _, _) => Some("let")
              @ast.TsStmt::Var(_, _, _) => Some("var")
              _ => None
            }
            if next_kind == Some(kind) {
              group.push(next)
              j = j + 1
            } else {
              break
            }
          }
          if group.length() > 1 {
            let first_byte = match group[0] {
              @ast.TsStmt::Var(b, _, _)
              | @ast.TsStmt::Let(b, _, _)
              | @ast.TsStmt::Const(b, _, _) => binding_leading_byte(b)
              _ => '?'
            }
            e.word(kind)
            e.sep_after_word(first_byte)
            for k, gs in group {
              if k > 0 {
                e.write(",")
                e.space()
              }
              match gs {
                @ast.TsStmt::Var(b, _, init)
                | @ast.TsStmt::Let(b, _, init)
                | @ast.TsStmt::Const(b, _, init) => {
                  emit_binding(e, b)
                  let is_undef_init = match init {
                    @ast.TsExpr::UnaryOp(@ast.TsUnaryOp::Void, _) => true
                    @ast.TsExpr::Var("undefined") => true
                    _ => false
                  }
                  if not(is_undef_init) {
                    e.space()
                    e.write("=")
                    e.space()
                    emit_expr(e, init, 0)
                  }
                }
                _ => ()
              }
            }
            e.semi()
            i = j
            continue
          }
          emit_stmt(e, stmt)
          i = i + 1
          continue
        }
        None => ()
      }
    }
    emit_stmt(e, stmt)
    i = i + 1
  }
}

///|
/// Variant for function bodies. In minify mode, drops trailing
/// `return;` / `return undefined;` — the implicit return at end-of-
/// function is semantically identical and saves ~9 bytes per occurrence.
fn emit_func_body(e : Emitter, block : @ast.TsBlock) -> Unit {
  if e.pretty {
    emit_block(e, block)
    return
  }
  // Count how many trailing Return(None)/Empty stmts to skip.
  let stmts = block.stmts
  let mut end = stmts.length()
  while end > 0 {
    match stmts[end - 1] {
      @ast.TsStmt::Return(None) | @ast.TsStmt::Empty => end = end - 1
      _ => break
    }
  }
  // Delegate to emit_block with a truncated view (drops trailing returns).
  // This lets emit_block's consecutive-decl merging apply in function bodies.
  let trimmed : @ast.TsBlock = {
    stmts: stmts.iter().take(end).collect(),
    stmt_positions: block.stmt_positions,
  }
  emit_block(e, trimmed)
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
/// Walk to the end of a block and check whether its terminal stmt
/// is an `if` that would swallow a following `else`. The de-brace
/// optimisation can't apply when that's true — emit must keep the
/// surrounding `{…}` so the `else` binds to the outer `if`.
fn block_ends_in_dangling_if(b : @ast.TsBlock) -> Bool {
  if b.stmts.length() == 0 {
    return false
  }
  stmt_ends_in_dangling_if(b.stmts[b.stmts.length() - 1])
}

///|
fn stmt_ends_in_dangling_if(s : @ast.TsStmt) -> Bool {
  match s {
    // `if (...) X` with no else — swallows a following `else`.
    If(_, _, None) => true
    // `if (...) X else Y` — the recursion follows `else` because
    // that's the branch where a *new* trailing else would attach.
    If(_, _, Some(else_b)) => block_ends_in_dangling_if(else_b)
    // Loop / labelled / with stmts whose body is a single bare-if
    // also re-expose the dangling-else risk on the way out.
    While(_, body) | DoWhile(_, body) => block_ends_in_dangling_if(body)
    For(_, _, _, body) => block_ends_in_dangling_if(body)
    ForOf(_, _, _, _, body)
    | ForAwaitOf(_, _, _, _, body)
    | ForIn(_, _, _, _, body) => block_ends_in_dangling_if(body)
    With(_, body) => block_ends_in_dangling_if(body)
    Label(_, inner) => stmt_ends_in_dangling_if(inner)
    _ => false
  }
}

///|
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
      let is_undef_init = match init {
        UnaryOp(@ast.TsUnaryOp::Void, _) => true
        Var("undefined") => true
        _ => false
      }
      if not(e.pretty) && is_undef_init {
        // Drop `= void 0` — `var x;` is semantically identical.
      } else {
        e.space()
        e.write("=")
        e.space()
        emit_expr(e, init, 0)
      }
      e.semi()
    }
    Let(binding, _ty, init) => {
      e.word("let")
      e.sep_after_word(binding_leading_byte(binding))
      emit_binding(e, binding)
      // In minify mode, `let x = undefined` → `let x` (drops the
      // initializer entirely: `= void 0` is 7 bytes, the implicit
      // `undefined` default costs nothing). Skip the `= void 0`
      // produced by the peephole pass and the raw `Var("undefined")`
      // from the parser for uninitialized declarations.
      let is_undef_init = match init {
        UnaryOp(@ast.TsUnaryOp::Void, _) => true
        Var("undefined") => true
        _ => false
      }
      if not(e.pretty) && is_undef_init {
        // Emit with no initializer — matches `let x;` which the
        // JS engine initialises to `undefined` automatically.
      } else {
        e.space()
        e.write("=")
        e.space()
        emit_expr(e, init, 0)
      }
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
      // In minify mode, `const` is downgraded to `let`, so `= void 0`
      // initializers can be dropped (plain `let x` is equivalent).
      let is_undef_init = match init {
        UnaryOp(@ast.TsUnaryOp::Void, _) => true
        Var("undefined") => true
        _ => false
      }
      if not(e.pretty) && is_undef_init {
        ()
      } else {
        e.space()
        e.write("=")
        e.space()
        emit_expr(e, init, 0)
      }
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
      if expr_stmt_needs_paren(recv) {
        e.write("(")
        emit_expr(e, recv, 0)
        e.write(")")
      } else {
        emit_expr(e, recv, 18)
      }
      // `x["prop"] = v` → `x.prop = v` in minify mode (saves 4 bytes)
      match idx {
        StringLit(k) if not(e.pretty) && is_valid_js_ident(k) => {
          e.write(".")
          e.write(k)
        }
        _ => {
          e.write("[")
          emit_expr(e, idx, 0)
          e.write("]")
        }
      }
      e.space()
      e.write("=")
      e.space()
      emit_expr(e, value, 0)
      e.semi()
    }
    PropAssign(recv, prop, value) =>
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
        // Same statement-start ambiguity as in the `Expr(...)` path:
        // a `FuncExpr` / class / object-literal at the head of a
        // statement parses as the declaration / block form, not as
        // an expression. Wrap the receiver when it starts with one
        // of those.
        if expr_stmt_needs_paren(recv) {
          e.write("(")
          emit_expr(e, recv, 0)
          e.write(")")
        } else {
          emit_expr(e, recv, 18)
        }
        let stripped = strip_internal_prop_marker(prop)
        // Non-ident property names (`"~standard"` / `"a-b"` /
        // `"0"`) require computed-index form — `recv.~standard =
        // …` is a hard parse error. Reserved words (`return` /
        // `for` / …) ARE valid in member-access position post-ES5,
        // so they keep the dotted form.
        if is_valid_js_ident(stripped) {
          e.write(".")
          e.write(stripped)
        } else {
          e.write("[")
          emit_string_literal(e, stripped)
          e.write("]")
        }
        e.space()
        e.write("=")
        e.space()
        emit_expr(e, value, 0)
        e.semi()
      }
    Expr(expr) => {
      // Expression-statement start sentinel: JS parses `function …`
      // / `class …` / `{ … }` at the head of a statement as a
      // declaration / block, NOT as an expression. When an inline
      // pass collapses `let x = function () {…}; x.foo = y` into
      // `(function () {…}).foo = y`, the LHS recv is a FuncExpr —
      // but if we emit it bare we get `function () {…}.foo = y`
      // which the parser rejects. Wrap such expression statements
      // in parens.
      if expr_stmt_needs_paren(expr) {
        e.write("(")
        emit_expr(e, expr, 0)
        e.write(")")
      } else {
        emit_expr(e, expr, 0)
      }
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
      // Dangling-else hazard: when this `if` has an `else` AND the
      // then-body's last stmt is a bare `if` without `else`, the
      // optional minify de-brace turns `if A { if B X } else Y`
      // into `if A if B X else Y` — the else then binds to the
      // INNER if, silently re-routing control flow. TypeScript's
      // `tryParseModifier` (a deeply nested if/else chain inside
      // an outer `if (cond) { if (!try) return; }`) is the
      // textbook case. Force braces on the then-body whenever an
      // else follows AND the body could swallow it.
      let then_needs_braces = match else_opt {
        Some(_) => block_ends_in_dangling_if(then_b)
        None => false
      }
      if then_needs_braces {
        emit_block(e, then_b)
      } else {
        emit_branch_body(e, then_b)
      }
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
      // `while(true){…}` → `for(;;){…}` in minify mode (saves 5 bytes).
      let is_truthy_cond = match cond {
        BoolLit(true) => true
        IntLit(n) => n != 0
        // `!0` is a common minifier substitution for `true`
        UnaryOp(@ast.TsUnaryOp::Not, @ast.TsExpr::IntLit(0)) => true
        _ => false
      }
      if not(e.pretty) && is_truthy_cond {
        e.write("for(;;)")
        e.space()
        emit_branch_body(e, body)
      } else {
        e.write("while")
        e.space()
        e.write("(")
        emit_expr(e, cond, 0)
        e.write(")")
        e.space()
        emit_branch_body(e, body)
      }
    }
    DoWhile(cond, body) => {
      // `do` is a keyword token; the next token must either be
      // separated by a non-ident char (`{` of a block body) or by
      // whitespace, otherwise `do <ident>=…` re-tokenizes as a
      // single identifier (`dogS=…` instead of `do gS=…`).
      e.word("do")
      let body_first = if e.pretty || body.stmts.length() != 1 {
        '{'
      } else if can_braceless(body.stmts[0]) {
        stmt_leading_byte(body.stmts[0])
      } else {
        '{'
      }
      e.sep_after_word(body_first)
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
      emit_for_of_kind(e, kind, binding)
      // The space before `of` is always required (binding ends with
      // ident). Space after `of` can be dropped in minify mode when
      // the iterable starts with a non-ident token.
      e.write(" of")
      e.sep_after_word(expr_leading_byte(iter))
      emit_expr(e, iter, 0)
      e.write(")")
      e.space()
      emit_branch_body(e, body)
    }
    ForAwaitOf(kind, binding, _ty, iter, body) => {
      e.write("for await")
      e.space()
      e.write("(")
      emit_for_of_kind(e, kind, binding)
      e.write(" of")
      e.sep_after_word(expr_leading_byte(iter))
      emit_expr(e, iter, 0)
      e.write(")")
      e.space()
      emit_branch_body(e, body)
    }
    ForIn(kind, binding, _ty, iter, body) => {
      e.write("for")
      e.space()
      e.write("(")
      emit_for_of_kind(e, kind, binding)
      // Same treatment as `of`: space before `in` always needed,
      // space after only when the iterable starts with ident char.
      e.write(" in")
      e.sep_after_word(expr_leading_byte(iter))
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
      // `try{` is valid in minify mode — `{` is never an ident char.
      e.word("try")
      e.sep_after_word('{')
      emit_block(e, try_b)
      match (catch_bind, catch_b) {
        (_, Some(cb)) => {
          e.space()
          e.word("catch")
          match catch_bind {
            Some(b) => {
              // `catch(e)` — space before `(` can be dropped in minify mode.
              e.sep_after_word('(')
              e.write("(")
              emit_binding(e, b)
              e.write(")")
            }
            None => ()
          }
          // `catch{` — `{` doesn't need a leading space.
          e.sep_after_word('{')
          emit_block(e, cb)
        }
        _ => ()
      }
      match finally_b {
        Some(fb) => {
          e.space()
          e.word("finally")
          e.sep_after_word('{')
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
    Block(b) =>
      // Multi-declarator `let a = 1, b = 2;` parses as a `Block`
      // wrapping individual `Let` stmts. Wrapping that in real
      // `{…}` braces would change scope semantics — the bindings
      // become local to a new block instead of staying in the
      // enclosing scope. Detect the same-kind-decls pattern and
      // unwrap inline; non-decl blocks keep their braces.
      if try_emit_multi_decl_inline(e, b) {
        ()
      } else {
        emit_block(e, b)
      }
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
    // In minify mode `BoolLit` emits as `!0`/`!1`; in pretty mode as `true`/`false`.
    BoolLit(_) => '!'
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
    // ArrowFunc's 4th field is `is_async`. When set, the arrow
    // emits as `async (…) => …` — the leading byte is `'a'`, NOT
    // `'('`. Reporting `'('` here lets `sep_after_word` skip the
    // space after `return`/`throw`/`yield`, producing
    // `returnasync (...) => …` which V8 parses as a call to the
    // identifier `returnasync` with `(...)` as arrow params and
    // throws `Malformed arrow function parameter list`.
    ArrowFunc(_, _, _, is_async) => if is_async { 'a' } else { '(' }
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

///|
/// Statement-level variant of `try_emit_multi_decl_for_head`. The
/// parser packs `let a = 1, b = 2;` into a `Block` of two `Let`
/// stmts so the multi-binder shape survives the AST. Re-emitting
/// that block with real `{…}` braces breaks scope; emit it as
/// `let a = 1, b = 2;` instead. Returns true when it handled the
/// block; the caller falls back to `emit_block` otherwise.
fn try_emit_multi_decl_inline(e : Emitter, block : @ast.TsBlock) -> Bool {
  if block.stmts.length() == 0 {
    return false
  }
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
  let emitted_kind = if kind == "const" && not(e.pretty) { "let" } else { kind }
  e.word(emitted_kind)
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
        // In minify mode, `const` is downgraded to `let` (see `emitted_kind`
        // above), so dropping a `= void 0` initializer is safe for all kinds.
        let is_undef_init = match init {
          UnaryOp(@ast.TsUnaryOp::Void, _) => true
          Var("undefined") => true
          _ => false
        }
        if not(e.pretty) && is_undef_init {
          ()
        } else {
          e.space()
          e.write("=")
          e.space()
          emit_expr(e, init, 0)
        }
      }
      _ => ()
    }
  }
  e.semi()
  true
}

///|
fn try_emit_multi_decl_for_head(e : Emitter, stmt : @ast.TsStmt) -> Bool {
  let block = match stmt {
    Block(b) => b
    _ => return false
  }
  if block.stmts.length() == 0 {
    return false
  }
  // All stmts must be the same lexical kind. Even a single-stmt
  // block needs unwrapping — if treeshake / fold removed the other
  // declarations the remaining one must still emit as `let x = …`
  // (not `{ let x = …; }`), otherwise the `for` head re-parses as
  // a block expression and the loop bindings disappear.
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
  let emitted_kind = if kind == "const" && not(e.pretty) { "let" } else { kind }
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
/// Emit the declarator keyword for a for-of/for-in/for-await-of head.
/// Returns the leading byte of the following token (the binding) so
/// callers can decide whether a separator is needed between the keyword
/// and the binding.  `'?'` is returned when no keyword is emitted
/// (the `Assign` kind).
fn emit_for_of_kind(
  e : Emitter,
  kind : @ast.TsForOfKind,
  binding : @ast.TsBinding,
) -> Unit {
  let kw = match kind {
    Var => "var"
    Let => "let"
    // Same idea as the statement-level `Const`: in minify mode the
    // loop binder doesn't need to be `const`, since the original
    // source already proved no reassignment.
    Const => if e.pretty { "const" } else { "let" }
    Assign => {
      emit_binding(e, binding)
      return
    }
  }
  e.word(kw)
  e.sep_after_word(binding_leading_byte(binding))
  emit_binding(e, binding)
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
            // Same quoting rule as object literals: non-identifier
            // keys (`"~standard"`, `"foo-bar"`, etc.) MUST stay
            // quoted or the destructure parses as a bare token.
            emit_object_key(e, prop.key)
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
    NumberLit(n) =>
      if e.pretty {
        // Use JS-valid names for special floating-point values.
        // MoonBit's `to_string()` may return "inf" / "nan" which are
        // NOT valid JS; JavaScript uses the global identifiers instead.
        if n != n {
          e.write("NaN")
        } else if n == 1.0 / 0.0 {
          e.write("Infinity")
        } else if n == -1.0 / 0.0 {
          e.write("-Infinity")
        } else {
          e.write(n.to_string())
        }
      } else {
        e.write(minify_number(n))
      }
    IntLit(n) =>
      if e.pretty {
        e.write(n.to_string())
      } else {
        e.write(minify_number(n.to_double()))
      }
    BigIntLit(s) => {
      e.write(s)
      e.write("n")
    }
    BoolLit(b) =>
      // In minify mode: `true` → `!0` (saves 2 bytes), `false` → `!1` (saves 3 bytes).
      if e.pretty {
        e.write(if b { "true" } else { "false" })
      } else {
        e.write(if b { "!0" } else { "!1" })
      }
    StringLit(s) => emit_string_literal(e, s)
    NullLit => e.write("null")
    ArrayHole => ()
    Var(name) =>
      // In minify mode, emit `undefined` as `void 0` (6 vs 9 bytes).
      if not(e.pretty) && name == "undefined" {
        e.write("void 0")
      } else {
        e.write(name)
      }
    BinOp(op, l, r) => {
      let prec = binop_precedence(op)
      // `??` cannot be mixed with `||` / `&&` without explicit
      // parentheses — even when the precedence numbers suggest no
      // wrap is needed (`??` is precedence 4, `||` is 5, so
      // `a ?? b || c` would normally not wrap `b || c`), JS spec
      // explicitly bans the unparenthesised mix as a SyntaxError.
      // Force parens on either side.
      if coalesce_mix_needs_paren(op, l) {
        e.write("(")
        emit_expr(e, l, 0)
        e.write(")")
      } else {
        emit_expr(e, l, prec)
      }
      // Word operators (`instanceof`, `in`) start with identifier
      // bytes, so the optional-whitespace `space()` we use for
      // punctuator ops would produce illegal output like
      // `xinstanceofy` in minify mode. Force separators on both
      // sides for word ops; `space()` is still correct for `+`,
      // `*`, `===` and the rest.
      let is_word_op = match op {
        Instanceof | In => true
        _ => false
      }
      if is_word_op {
        e.write(" ")
      } else {
        e.space()
      }
      e.write(binop_str(op))
      // Token-boundary protection on the right: avoid `+ +x` →
      // `""++x` (read as `""++ x`, postfix-increment on a literal,
      // SyntaxError) and the same for `- -x`. Inserts a forced
      // space when the binary operator and the right operand's
      // leading operator would merge into `++` / `--`. Same idea
      // for `< <x`, `> >x` — those merge into shift tokens.
      if is_word_op {
        // Word operators end with an ident char; space after is
        // only strictly required when the right operand also starts
        // with an ident char.  Use `sep_after_word` to suppress it
        // in minify mode when the RHS starts with `(`, `[`, etc.
        e.sep_after_word(expr_leading_byte(r))
      } else if right_needs_token_separator(op, r) {
        e.write(" ")
      } else {
        e.space()
      }
      // Right-associative ** uses prec, others prec+1 so left chains.
      let right_prec = match op {
        Pow => prec
        _ => prec + 1
      }
      if coalesce_mix_needs_paren(op, r) {
        e.write("(")
        emit_expr(e, r, 0)
        e.write(")")
      } else {
        emit_expr(e, r, right_prec)
      }
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
            Typeof | Void | Delete => {
              // In minify mode, use `sep_after_word` to avoid the space
              // when the operand starts with a non-identifier char.
              e.sep_after_word(expr_leading_byte(inner))
            }
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
        // sentinel `("...", Spread(expr))` entry. Some parser paths
        // emit `("@@spread:N", expr)` for the same purpose. Both
        // surface as `...expr` shorthand.
        match entry {
          ("...", Spread(inner)) => {
            e.write("...")
            emit_expr(e, inner, 2)
          }
          (key, _) if key.has_prefix("@@spread:") => {
            e.write("...")
            emit_expr(e, entry.1, 2)
          }
          (key, ComputedProp(k_expr, v_expr)) if key.has_prefix("@@computed:") => {
            // The parser tags computed-key entries with this
            // sentinel and stores the actual `[expr]: value` as a
            // `ComputedProp(expr, value)` payload. Emit them as
            // the JS shorthand directly — without this branch the
            // sentinel key would print verbatim and produce a
            // double-colon `"@@computed:0":[expr]:value`.
            e.write("[")
            emit_expr(e, k_expr, 0)
            e.write("]:")
            e.space()
            emit_expr(e, v_expr, 2)
          }
          (key, ComputedProp(k_expr, FuncExpr(f))) if key.has_prefix(
              "@@get:@@computed:",
            ) ||
            key.has_prefix("@@set:@@computed:") => {
            // Computed-key accessor: `get [expr]() {…}` /
            // `set [expr](v) {…}`. Parser stacks the `@@get:` /
            // `@@set:` sentinel on top of the `@@computed:N` key,
            // wrapping the function in a `ComputedProp(k_expr, …)`.
            // Without this branch the emit produced
            // `"@@get:@@computed:N": [expr]: function() {…}` —
            // syntactically invalid object literal.
            let accessor = if key.has_prefix("@@get:") { "get" } else { "set" }
            e.write(accessor)
            e.write(" [")
            emit_expr(e, k_expr, 0)
            e.write("](")
            emit_runtime_params(e, f.params)
            e.write(")")
            e.space()
            emit_func_body(e, f.body)
          }
          (key, FuncExpr(f)) if key.has_prefix("@@get:") ||
            key.has_prefix("@@set:") => {
            // Accessor in object literal: parser tags `get foo() {}`
            // / `set foo(v) {}` with a `@@get:` / `@@set:` sentinel
            // on the property key. Emit the native ES syntax so the
            // accessor actually installs as a getter/setter rather
            // than as a plain string-keyed property.
            let accessor = if key.has_prefix("@@get:") { "get" } else { "set" }
            let real_name = key.substring(start=6, end=key.length()).to_string()
            e.write(accessor)
            e.write(" ")
            emit_object_key(e, real_name)
            e.write("(")
            emit_runtime_params(e, f.params)
            e.write(")")
            e.space()
            emit_func_body(e, f.body)
          }
          (key, FuncExpr(f)) if f.name == key && key != "" => {
            // Method shorthand: `key(args) {...}`. The parser stores
            // method shorthand as `(key, FuncExpr {name: key, ...})`.
            // Re-emitting as the shorthand avoids introducing a
            // named-function-expression self-binding that would
            // shadow rewritten names (e.g. when `core.clone` is
            // rewritten to `clone` and the method itself is named
            // `clone` — the inner reference would loop forever
            // otherwise).
            if f.is_async {
              e.write("async ")
            }
            if f.is_generator {
              e.write("*")
            }
            emit_object_key(e, key)
            e.write("(")
            emit_runtime_params(e, f.params)
            e.write(")")
            e.space()
            emit_func_body(e, f.body)
          }
          _ => {
            // Non-identifier keys (`"Content-Type"`, `"foo bar"`,
            // numeric-looking, etc.) MUST stay quoted — otherwise
            // the emitted `{Content-Type: …}` re-parses as binary
            // minus. Numeric keys can stay unquoted; everything
            // else needs the quotes.
            //
            // In minify mode, when key is a valid identifier and
            // the value is `Var(key)`, emit the ES2015 shorthand
            // `{key}` instead of `{key: key}` (saves 2 bytes).
            let use_shorthand = not(e.pretty) &&
              is_valid_js_ident(entry.0) &&
              (match entry.1 {
                Var(n) => n == entry.0
                _ => false
              })
            if use_shorthand {
              e.write(entry.0)
            } else {
              emit_object_key(e, entry.0)
              e.write(":")
              e.space()
              emit_expr(e, entry.1, 2)
            }
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
      // `expr["prop"]` → `expr.prop` when the key is a valid identifier
      // and we're in minify mode. Saves `["` + `"]` (4 bytes) per access.
      // In pretty mode we preserve the bracket form as written to avoid
      // surprising users who wrote `x["key"]` intentionally.
      match idx {
        StringLit(k) if not(e.pretty) && is_valid_js_ident(k) => {
          e.write(".")
          e.write(k)
        }
        _ => {
          e.write("[")
          emit_expr(e, idx, 0)
          e.write("]")
        }
      }
    }
    PropAccess(recv, name) => {
      emit_expr(e, recv, 18)
      let stripped = strip_internal_prop_marker(name)
      if is_valid_js_ident(stripped) {
        e.write(".")
        e.write(stripped)
      } else {
        e.write("[")
        emit_string_literal(e, stripped)
        e.write("]")
      }
    }
    New(name, args) => {
      // In minify mode, `new RegExp("pat")` → `/pat/` and
      // `new RegExp("pat","flags")` → `/pat/flags` saves bytes.
      let emitted_as_regex = if not(e.pretty) && name == "RegExp" {
        let pat_ok = match args.get(0) {
          Some(StringLit(p)) => regex_literal_safe(p)
          _ => false
        }
        let flags_ok = match args.get(1) {
          None => true
          Some(StringLit(f)) => {
            let mut ok = true
            for c in f {
              match c {
                'g' | 'i' | 'm' | 's' | 'u' | 'y' | 'd' | 'v' => ()
                _ => ok = false
              }
            }
            ok
          }
          _ => false
        }
        if pat_ok && flags_ok {
          let pat = match args[0] { StringLit(p) => p; _ => "" }
          let flags = match args.get(1) { Some(StringLit(f)) => f; _ => "" }
          e.write("/")
          emit_regex_body(e, pat)
          e.write("/")
          e.write(flags)
          true
        } else {
          false
        }
      } else {
        false
      }
      if not(emitted_as_regex) {
        e.write("new ")
        e.write(name)
        // In minify mode, `new Foo` (no parens) is valid when there
        // are no arguments. Saves 2 bytes per zero-arg construction.
        if e.pretty || args.length() > 0 {
          emit_args(e, args)
        }
      }
    }
    NewExpr(callee, args) => {
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
        // `new(callee)` — `(` doesn't start an ident char, so the
        // space after `new` can be dropped in minify mode.
        e.word("new")
        e.sep_after_word('(')
        e.write("(")
        emit_expr(e, callee, 0)
        e.write(")")
      } else {
        e.write("new ")
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
      // `x["prop"] = v` → `x.prop = v` in minify mode (saves 4 bytes)
      match idx {
        StringLit(k) if not(e.pretty) && is_valid_js_ident(k) => {
          e.write(".")
          e.write(k)
        }
        _ => {
          e.write("[")
          emit_expr(e, idx, 0)
          e.write("]")
        }
      }
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
      // In minify mode, a single simple-identifier parameter doesn't
      // need parens: `x=>x` is valid and saves 2 bytes over `(x)=>x`.
      // "Simple" means: not a rest param, not a destructure, no default.
      let bare_name : String? = if e.pretty {
        None
      } else {
        let runtime : Array[@ast.TsParam] = []
        for p in params {
          if not(is_this_type_annotation_param(p)) {
            runtime.push(p)
          }
        }
        if runtime.length() == 1 {
          let p = runtime[0]
          let simple = not(p.is_rest) &&
            (match p.binding {
              None | Some(@ast.TsBinding::Ident(_)) => true
              _ => false
            }) &&
            (match p.default {
              None => true
              _ => false
            })
          if simple { Some(p.name) } else { None }
        } else {
          None
        }
      }
      // Emit `async` keyword, then the params.  In minify mode,
      // `async(x)=>` is valid (saves 1 byte vs `async (x)=>`),
      // but `asyncx=>` is not — so the space is required only
      // when a bare identifier param follows.
      match bare_name {
        Some(name) => {
          if is_async {
            e.write("async ")
          }
          e.write(name)
        }
        None => {
          if is_async {
            e.word("async")
            e.sep_after_word('(')
          }
          e.write("(")
          emit_runtime_params(e, params)
          e.write(")")
        }
      }
      e.space()
      e.write("=>")
      e.space()
      match body {
        ArrowExpr(inner) => {
          // `() => { … }` parses as a block body, not an arrow
          // returning an object literal. Wrap an ObjectLit-shaped
          // expression in parens to keep the JS parser on the
          // expression branch.
          let needs_paren_for_obj = match inner {
            ObjectLit(_) => true
            _ => false
          }
          if needs_paren_for_obj {
            e.write("(")
            emit_expr(e, inner, 0)
            e.write(")")
          } else {
            emit_expr(e, inner, 2)
          }
        }
        ArrowBlock(block) => emit_func_body(e, block)
      }
    }
    FuncExpr(f) => emit_function_expr(e, f)
    Yield(opt) =>
      match opt {
        Some(inner) => {
          e.word("yield")
          e.sep_after_word(expr_leading_byte(inner))
          emit_expr(e, inner, 2)
        }
        None => e.write("yield")
      }
    YieldStar(inner) => {
      // `yield*` ends with `*` (not a word char), so no separator needed.
      e.write("yield*")
      emit_expr(e, inner, 2)
    }
    Await(inner) => {
      e.word("await")
      e.sep_after_word(expr_leading_byte(inner))
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
    OptionalChain(inner) =>
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
          // `recv.method?.(args)` — the `?.` is on the CALL, not on
          // the property access. The parser produces
          // `OptionalChain(MethodCall(...))` only from this source
          // shape, so emit the property access without `?.` and put
          // the `?.` between the property and the call args.
          emit_expr(e, recv, 18)
          e.write(".")
          e.write(strip_internal_prop_marker(method))
          e.write("?.")
          emit_args(e, args)
        }
        Call(name, args) => {
          // `name?.(args)` — optional call on a plain identifier.
          e.write(name)
          e.write("?.")
          emit_args(e, args)
        }
        CallExpr(callee, args) => {
          // `(callee)?.(args)` — optional call on an arbitrary
          // expression. `?.` sits between callee and args.
          emit_expr(e, callee, 18)
          e.write("?.")
          emit_args(e, args)
        }
        _ => emit_expr_body(e, inner)
      }
    JsxElement(tag, attrs, children) =>
      emit_jsx_element(e, tag, attrs, children)
    NativeClassExpr(decl, ctor_body) => emit_native_class(e, decl, ctor_body)
    PureCall(inner) => {
      // In pretty mode, restore the `/* @__PURE__ */` annotation so
      // downstream minifiers keep treating the call as droppable.
      // In minify mode we've already tree-shaken dead code ourselves,
      // so the annotation is unnecessary noise.
      if e.pretty {
        e.write("/* @__PURE__ */ ")
      }
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
    e.write(escape_template_part(part))
    if i < exprs.length() {
      e.write("${")
      emit_expr(e, exprs[i], 0)
      e.write("}")
    }
  }
  e.write("`")
}

///|
/// Re-escape a "cooked" template literal segment so it round-trips
/// safely as JS source. The parser stores parts with escape sequences
/// already decoded (`\\\`` → literal backtick), so unescaped emit
/// produces invalid syntax. Re-escape the three chars that have
/// special meaning inside a template literal: `\\` → `\\\\`, `` ` ``
/// → `\\\``, and `$` immediately before `{` → `\\${`. Other escape
/// forms (`\\n`, `\\u0041`) decoded to their actual characters and
/// stay as-is — JS template literals accept the raw characters.
fn escape_template_part(s : String) -> String {
  let buf = StringBuilder::new()
  let chars = s.to_array()
  let n = chars.length()
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == '\\' {
      buf.write_string("\\\\")
    } else if c == '`' {
      buf.write_string("\\`")
    } else if c == '$' && i + 1 < n && chars[i + 1] == '{' {
      buf.write_string("\\${")
      i = i + 1
    } else {
      buf.write_char(c)
    }
    i = i + 1
  }
  buf.to_string()
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
  // In minify mode, `function*foo(){}` is valid — no space needed
  // between `*` and the identifier. For non-generators `function`
  // is a keyword and needs a separator before the name.
  if e.pretty || not(func.is_generator) {
    e.write(" ")
  }
  e.write(name)
  e.write("(")
  emit_runtime_params(e, func.params)
  e.write(")")
  e.space()
  emit_func_body(e, func.body)
  true
}

///|
fn emit_function_expr(e : Emitter, f : @ast.TsFunc) -> Unit {
  if f.is_async {
    e.write("async ")
  }
  e.write("function")
  if f.is_generator {
    e.write("*")
  }
  // Synthesized class-desugar nodes carry a placeholder `<class>` /
  // `<anon>` name. Those aren't valid JS identifiers, so emit the
  // expression in its anonymous form (`function () {…}`).
  //
  // Reserved keyword names (`with`, `if`, `do`, `return`, …) ARE
  // allowed as object-method shorthand keys, but NOT as function
  // expression names — `function with() {}` is a hard parse error.
  // When the parser captured a method-shorthand key as the
  // function's name and that key is a reserved word, drop the
  // name to keep the emit anonymous.
  //
  // Also drop the name when the body references the same name as
  // a free variable. The named-function-expression binding shadows
  // the outer reference: `X.toJSON = function toJSON() {
  //   return toJSON(this.x);
  // }` recurses forever — the inner `toJSON` resolves to itself,
  // never to the module-level `toJSON` the source intended. This
  // surfaces on every IIFE-lowered class method whose name
  // collides with an imported function (effect's `EffectPrimitive
  // .toJSON` is the textbook case).
  if f.name != "" &&
    is_valid_js_ident(f.name) &&
    not(is_reserved_word(f.name)) &&
    not(func_body_references_name_as_free_var(f, f.name)) {
    // In minify mode, `function*name()` needs no space — `*` is
    // punctuation, not a word token. Non-generators must keep the
    // space: `functionname` would be parsed as one identifier.
    if e.pretty || not(f.is_generator) {
      e.write(" ")
    }
    e.write(f.name)
  }
  e.write("(")
  emit_runtime_params(e, f.params)
  e.write(")")
  e.space()
  emit_func_body(e, f.body)
}

///|
/// Scan a function body for free references to `name`. Stops short
/// at nested function / arrow scopes that shadow the name with a
/// parameter or local binding (those have their own `name` and
/// can't conflict with the outer named-FuncExpr binding). Used by
/// `emit_function_expr` to decide whether emitting the function
/// name would create a self-shadow.
fn func_body_references_name_as_free_var(
  f : @ast.TsFunc,
  name : String,
) -> Bool {
  for p in f.params {
    if p.name == name {
      return false
    }
    match p.binding {
      Some(b) => if binding_introduces_name(b, name) { return false }
      None => ()
    }
  }
  block_references_name(f.body, name)
}

///|
fn binding_introduces_name(b : @ast.TsBinding, name : String) -> Bool {
  match b {
    Ident(n) => n == name
    Array(ab) => {
      for elem in ab.items {
        match elem {
          Some(be) =>
            if binding_introduces_name(be.binding, name) {
              return true
            }
          None => ()
        }
      }
      match ab.rest {
        Some(r) => binding_introduces_name(r, name)
        None => false
      }
    }
    Object(ob) => {
      for prop in ob.props {
        if binding_introduces_name(prop.binding, name) {
          return true
        }
      }
      false
    }
    Target(_) => false
  }
}

///|
fn block_references_name(block : @ast.TsBlock, name : String) -> Bool {
  for s in block.stmts {
    if stmt_references_name(s, name) {
      return true
    }
  }
  false
}

///|
fn stmt_references_name(stmt : @ast.TsStmt, name : String) -> Bool {
  match stmt {
    Var(b, _, e) | Let(b, _, e) | Const(b, _, e) => {
      if binding_introduces_name(b, name) {
        return expr_references_name(e, name)
      }
      expr_references_name(e, name)
    }
    Expr(e) | Throw(e) => expr_references_name(e, name)
    Return(opt) =>
      match opt {
        Some(e) => expr_references_name(e, name)
        None => false
      }
    Assign(n, e) => n == name || expr_references_name(e, name)
    CompoundAssign(n, _, e) => n == name || expr_references_name(e, name)
    IndexAssign(t, idx, v) =>
      expr_references_name(t, name) ||
      expr_references_name(idx, name) ||
      expr_references_name(v, name)
    PropAssign(t, _, v) =>
      expr_references_name(t, name) || expr_references_name(v, name)
    If(c, t, els) => {
      if expr_references_name(c, name) || block_references_name(t, name) {
        return true
      }
      match els {
        Some(b) => block_references_name(b, name)
        None => false
      }
    }
    While(c, b) | DoWhile(c, b) =>
      expr_references_name(c, name) || block_references_name(b, name)
    For(init, cond, update, body) => {
      let init_hit = match init {
        Some(s) => stmt_references_name(s, name)
        None => false
      }
      if init_hit {
        return true
      }
      let cond_hit = match cond {
        Some(c) => expr_references_name(c, name)
        None => false
      }
      if cond_hit {
        return true
      }
      let update_hit = match update {
        Some(s) => stmt_references_name(s, name)
        None => false
      }
      update_hit || block_references_name(body, name)
    }
    ForOf(_, b, _, iter, body)
    | ForAwaitOf(_, b, _, iter, body)
    | ForIn(_, b, _, iter, body) => {
      if binding_introduces_name(b, name) {
        return expr_references_name(iter, name)
      }
      expr_references_name(iter, name) || block_references_name(body, name)
    }
    Try(t, catch_b, catch_body, finally_) => {
      if block_references_name(t, name) {
        return true
      }
      let catch_hits = match catch_body {
        Some(b) => {
          let shadowed = match catch_b {
            Some(bb) => binding_introduces_name(bb, name)
            None => false
          }
          if shadowed {
            false
          } else {
            block_references_name(b, name)
          }
        }
        None => false
      }
      if catch_hits {
        return true
      }
      match finally_ {
        Some(b) => block_references_name(b, name)
        None => false
      }
    }
    Switch(scr, cases) => {
      if expr_references_name(scr, name) {
        return true
      }
      for c in cases {
        if block_references_name(c.body, name) {
          return true
        }
      }
      false
    }
    Block(b) => block_references_name(b, name)
    Label(_, inner) => stmt_references_name(inner, name)
    With(t, b) =>
      expr_references_name(t, name) || block_references_name(b, name)
    NativeClassStmt(_, _) => false
    _ => false
  }
}

///|
fn expr_references_name(e : @ast.TsExpr, name : String) -> Bool {
  match e {
    Var(n) => n == name
    Call(n, args) | New(n, args) => {
      if n == name {
        return true
      }
      for a in args {
        if expr_references_name(a, name) {
          return true
        }
      }
      false
    }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      if expr_references_name(callee, name) {
        return true
      }
      for a in args {
        if expr_references_name(a, name) {
          return true
        }
      }
      false
    }
    MethodCall(recv, _, args) => {
      if expr_references_name(recv, name) {
        return true
      }
      for a in args {
        if expr_references_name(a, name) {
          return true
        }
      }
      false
    }
    PropAccess(recv, _) => expr_references_name(recv, name)
    IndexAccess(recv, idx) =>
      expr_references_name(recv, name) || expr_references_name(idx, name)
    BinOp(_, l, r) | Seq(l, r) =>
      expr_references_name(l, name) || expr_references_name(r, name)
    Cond(c, t, els) =>
      expr_references_name(c, name) ||
      expr_references_name(t, name) ||
      expr_references_name(els, name)
    UnaryOp(_, v)
    | NonNull(v)
    | OptionalChain(v)
    | Await(v)
    | Spread(v)
    | PureCall(v)
    | YieldStar(v) => expr_references_name(v, name)
    Yield(opt) =>
      match opt {
        Some(v) => expr_references_name(v, name)
        None => false
      }
    AssignExpr(n, v) => n == name || expr_references_name(v, name)
    CompoundAssignExpr(t, _, v) =>
      expr_references_name(t, name) || expr_references_name(v, name)
    AssignPattern(_, v) => expr_references_name(v, name)
    PropAssignExpr(recv, _, v) =>
      expr_references_name(recv, name) || expr_references_name(v, name)
    IndexAssignExpr(recv, idx, v) =>
      expr_references_name(recv, name) ||
      expr_references_name(idx, name) ||
      expr_references_name(v, name)
    ComputedProp(k, v) =>
      expr_references_name(k, name) || expr_references_name(v, name)
    ArrayLit(items) => {
      for i in items {
        if expr_references_name(i, name) {
          return true
        }
      }
      false
    }
    ObjectLit(entries) => {
      for ent in entries {
        if expr_references_name(ent.1, name) {
          return true
        }
      }
      false
    }
    FuncExpr(g) => func_body_references_name_as_free_var(g, name)
    ArrowFunc(params, _, body, _) => {
      for p in params {
        if p.name == name {
          return false
        }
        match p.binding {
          Some(b) => if binding_introduces_name(b, name) { return false }
          None => ()
        }
      }
      match body {
        ArrowExpr(ee) => expr_references_name(ee, name)
        ArrowBlock(b) => block_references_name(b, name)
      }
    }
    As(v, _) | Satisfies(v, _) => expr_references_name(v, name)
    TaggedTemplate(tag, _, _, exprs) => {
      if expr_references_name(tag, name) {
        return true
      }
      for ee in exprs {
        if expr_references_name(ee, name) {
          return true
        }
      }
      false
    }
    TemplateLiteral(_, exprs) => {
      for ee in exprs {
        if expr_references_name(ee, name) {
          return true
        }
      }
      false
    }
    DynamicImport(spec, opts) => {
      if expr_references_name(spec, name) {
        return true
      }
      match opts {
        Some(o) => expr_references_name(o, name)
        None => false
      }
    }
    NativeClassExpr(_, _) => false
    _ => false
  }
}

///|
/// Predicate for the `Expr(expr)` statement: returns true when the
/// expression's leading token would make the statement parse as
/// something else (function / class declaration, object-literal
/// destructure, etc.) without surrounding parens.
fn expr_stmt_needs_paren(expr : @ast.TsExpr) -> Bool {
  match expr {
    FuncExpr(_) => true
    ArrowFunc(_, _, _, _) => false
    ObjectLit(_) => true
    NativeClassExpr(_, _) => true
    // `({a, b} = rhs)` / `([a, b] = rhs)` — destructuring assignment
    // at the head of a statement. JS parses a leading `{` as a
    // block and a leading `[` as the start of an array literal /
    // call (which is ambiguous in this position); the assign form
    // must be parenthesised so the parser commits to the
    // expression interpretation.
    AssignPattern(b, _) =>
      match b {
        Object(_) | Array(_) => true
        _ => false
      }
    // Recurse into shapes where the leading token sits inside.
    AssignExpr(_, _) => false
    PropAssignExpr(recv, _, _) => expr_stmt_needs_paren(recv)
    IndexAssignExpr(recv, _, _) => expr_stmt_needs_paren(recv)
    CompoundAssignExpr(recv, _, _) => expr_stmt_needs_paren(recv)
    PropAccess(recv, _) => expr_stmt_needs_paren(recv)
    IndexAccess(recv, _) => expr_stmt_needs_paren(recv)
    CallExpr(callee, _) => expr_stmt_needs_paren(callee)
    MethodCall(recv, _, _) => expr_stmt_needs_paren(recv)
    BinOp(_, l, _) => expr_stmt_needs_paren(l)
    Cond(c, _, _) => expr_stmt_needs_paren(c)
    Seq(l, _) => expr_stmt_needs_paren(l)
    As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner) => expr_stmt_needs_paren(inner)
    _ => false
  }
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

///|
/// Emit an object-literal key. Valid JS identifiers and numeric
/// literals stay unquoted; everything else (`Content-Type`,
/// `foo bar`, empty string, identifiers that happen to be reserved
/// words used as keys are still OK unquoted in modern JS) gets
/// JSON-string quoting so the surrounding object literal stays
/// parseable.
fn emit_object_key(e : Emitter, key : String) -> Unit {
  if is_valid_js_ident(key) || is_numeric_literal_key(key) {
    e.write(key)
  } else {
    e.write("\"")
    e.write(escape_string_literal(key))
    e.write("\"")
  }
}

///|
fn is_numeric_literal_key(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    if not(c >= '0' && c <= '9') {
      return false
    }
  }
  true
}

///|
/// Minimal JSON-style escape for strings emitted as object keys.
/// Covers backslash, double quote, and the control chars JS doesn't
/// accept verbatim inside double-quoted strings.
fn escape_string_literal(s : String) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    if c == '\\' {
      buf.write_string("\\\\")
    } else if c == '"' {
      buf.write_string("\\\"")
    } else if c == '\n' {
      buf.write_string("\\n")
    } else if c == '\r' {
      buf.write_string("\\r")
    } else if c == '\t' {
      buf.write_string("\\t")
    } else {
      buf.write_char(c.to_int().unsafe_to_char())
    }
  }
  buf.to_string()
}

///|
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
  // In minify mode, pick the quote character that requires fewer escapes.
  // Each avoided escape saves 1 byte (the backslash).
  let quote = if not(e.pretty) {
    let mut dq = 0 // double-quote occurrences
    let mut sq = 0 // single-quote occurrences
    for c in s {
      if c == '"' { dq = dq + 1 }
      if c == '\'' { sq = sq + 1 }
    }
    if sq < dq { '\'' } else { '"' }
  } else {
    '"'
  }
  e.write(quote.to_string())
  for c in s {
    if c == quote {
      e.write("\\")
      e.write(c.to_string())
    } else {
      match c {
        '\\' => e.write("\\\\")
        '\n' => e.write("\\n")
        '\r' => e.write("\\r")
        '\t' => e.write("\\t")
        _ => e.write(c.to_string())
      }
    }
  }
  e.write(quote.to_string())
}

// Returns true iff the runtime string value `s` can be safely used as the
// body of a regex literal /s/. Rejects empty patterns (would produce `//`,
// a comment), newlines, NUL bytes, and other control characters.
fn regex_literal_safe(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for c in s {
    // Reject `/`: escaping it as `\/` is unsafe when preceded by `\`
    // (produces `\\/` which closes the regex).  Reject control chars too.
    if c == '/' || c == '\n' || c == '\r' || c.to_int() < 32 {
      return false
    }
  }
  true
}

// Emit the runtime string value `s` as the body of a regex literal.
// Caller must have verified regex_literal_safe(s).
fn emit_regex_body(e : Emitter, s : String) -> Unit {
  for c in s {
    e.write(c.to_string())
  }
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
/// Detect mixed `??` / `||` / `&&` operators that JS forbids
/// without explicit parens. Spec: a `CoalesceExpression` cannot
/// contain a LogicalOR/AND without `()`. The parser preserves
/// source-level parens through structure, but emit-side rewrites
/// (fold / inline / mangle) can produce the bare mix.
/// Detect operator-character merges that would happen if the
/// minifier dropped the optional whitespace between a binary
/// operator and the right operand's leading token. `"" + +x`
/// must keep a space — otherwise `""++x` reads as a postfix
/// increment on the empty string, a SyntaxError. Same for
/// `- -x` / `< <x` / `> >x`.
fn right_needs_token_separator(op : @ast.TsBinOp, right : @ast.TsExpr) -> Bool {
  let right_leader = match right {
    UnaryOp(o, _) =>
      match o {
        Plus | PreInc => '+'
        Neg | PreDec => '-'
        Not => '!'
        BitwiseNot => '~'
        _ => '?'
      }
    _ => '?'
  }
  match op {
    Add => right_leader == '+'
    Sub => right_leader == '-'
    _ => false
  }
}

///|
fn coalesce_mix_needs_paren(op : @ast.TsBinOp, operand : @ast.TsExpr) -> Bool {
  match (op, operand) {
    (Coalesce, BinOp(Or, _, _))
    | (Coalesce, BinOp(And, _, _))
    | (Or, BinOp(Coalesce, _, _))
    | (And, BinOp(Coalesce, _, _)) => true
    _ => false
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
    As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner) => expr_precedence(inner)
  }
}

///|
/// Produce the shortest JS representation of a floating-point number.
/// - Drops leading zero: `0.5` → `.5` (saves 1 byte)
/// - Drops trailing zero: `1.0` → `1` (saves 2 bytes)
/// - Tries exponential when shorter: `1000000.0` → `1e6` (saves bytes)
fn minify_number(n : Double) -> String {
  // Special floating-point values have no numeric literal representation.
  // Minify to the shortest valid JS form instead of the global identifier.
  if n != n { return "0/0" } // NaN (same length, guaranteed valid JS)
  if n == 1.0 / 0.0 { return "1/0" } // Infinity (8 chars → 3)
  if n == -1.0 / 0.0 { return "-1/0" } // -Infinity (9 chars → 4)
  let standard = n.to_string()
  let mut best = standard
  // Drop trailing ".0" (integer-valued doubles): 1.0 → 1
  if standard.has_suffix(".0") {
    let shorter = standard.substring(start=0, end=standard.length() - 2).to_string()
    // Verify lossless round-trip.
    match (try? @strconv.parse_double(shorter)) {
      Ok(back) => if back == n && shorter.length() < best.length() { best = shorter }
      Err(_) => ()
    }
  }
  // Drop leading zero from "0.NNN": 0.5 → .5
  if standard.has_prefix("0.") {
    let shorter = standard.substring(start=1).to_string()
    match (try? @strconv.parse_double(shorter)) {
      Ok(back) => if back == n && shorter.length() < best.length() { best = shorter }
      Err(_) => ()
    }
  }
  // Drop leading zero from "-0.NNN": -0.5 → -.5
  if standard.has_prefix("-0.") {
    let shorter = "-" + standard.substring(start=2).to_string()
    match (try? @strconv.parse_double(shorter)) {
      Ok(back) => if back == n && shorter.length() < best.length() { best = shorter }
      Err(_) => ()
    }
  }
  // Scientific notation for integers with trailing zeros: 1000000 → 1e6.
  // Only worthwhile when the exponent notation is strictly shorter.
  // Cap at MAX_SAFE_INTEGER to avoid Int64 overflow on the conversion.
  let abs_n = if n < 0.0 { -n } else { n }
  if abs_n >= 1000.0 && abs_n <= 9007199254740991.0 && abs_n.to_int64().to_double() == abs_n {
    let int_val = abs_n.to_int64()
    let mut mantissa = int_val
    let mut exp = 0
    while mantissa % 10L == 0L && mantissa > 0L {
      mantissa = mantissa / 10L
      exp = exp + 1
    }
    if exp >= 2 {
      let sci = if n < 0.0 {
        "-" + mantissa.to_string() + "e" + exp.to_string()
      } else {
        mantissa.to_string() + "e" + exp.to_string()
      }
      match (try? @strconv.parse_double(sci)) {
        Ok(back) => if back == n && sci.length() < best.length() { best = sci }
        Err(_) => ()
      }
    }
  }
  best
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
    // `extends` is a word keyword; a forced space, not the
    // optional one — `classextends` / `nameextends` is invalid.
    e.write(" ")
    e.write("extends")
    e.sep_after_word('A')
    // Expression-shaped heritage (`extends declare(args)` /
    // `extends make(ast)` / `extends class {…}`) lives in
    // `base_expr`; `base_names[0]` carries the sentinel
    // `"<expr-base>"`. Print the parsed expression directly so the
    // emit round-trips.
    match decl.base_expr {
      Some(expr) => emit_expr(e, expr, 18)
      None => e.write(decl.base_names[0])
    }
  }
  e.space()
  e.open_block()
  // Constructor — emit the full TsFunc so rest / default /
  // destructuring params are preserved verbatim.
  // In minify mode, a no-arg empty constructor on a base class (no
  // `extends`) is identical to the implicit default constructor — drop
  // it to save bytes. Derived classes must keep even an empty
  // constructor since `constructor(){}` calls `super()` with no args,
  // while the implicit constructor forwards all args to `super`.
  let ctor_is_implicit = match ctor_func {
    Some(func) =>
      not(e.pretty) &&
      decl.base_names.is_empty() &&
      decl.base_expr.is_empty() &&
      func.params.is_empty() &&
      func.body.stmts.is_empty() &&
      not(func.is_async) &&
      not(func.is_generator)
    None => true
  }
  if not(ctor_is_implicit) {
    match ctor_func {
      Some(func) => {
        e.nl()
        e.write("constructor")
        e.write("(")
        emit_runtime_params(e, func.params)
        e.write(")")
        e.space()
        emit_func_body(e, func.body)
      }
      None => ()
    }
  }
  // Methods.
  for m in decl.methods {
    e.nl()
    if m.is_static {
      e.word("static")
      e.sep_after_word('A')
    }
    // `async` / `*` modifiers — without these the emit prints the
    // method as plain sync, and any `await` inside the body becomes
    // a SyntaxError (prettier's `class { async read(task) { …
    // await … } }` was the trigger). Order matches source syntax:
    // `async` first, then `*` (or both for async generators).
    if m.is_async {
      e.word("async")
      e.sep_after_word('A')
    }
    if m.is_generator {
      e.write("*")
    }
    // Accessor methods (`get foo()` / `set foo(v)`) get the keyword
    // prefix; without it the emitted property is a plain method and
    // the runtime never installs the getter/setter — Yjs's
    // `AbstractStruct.deleted` getter, for example, regresses to a
    // throwing stub on every access.
    if m.accessor == "get" {
      e.word("get")
      e.sep_after_word('A')
    } else if m.accessor == "set" {
      e.word("set")
      e.sep_after_word('A')
    }
    match m.key_expr {
      Some(k) => {
        // Computed-key method: `[expr](args) {…}`. Parser stores
        // the expression on `key_expr`; `m.name` is the sentinel
        // `<computed>` and is unused by emit here.
        e.write("[")
        emit_expr(e, k, 0)
        e.write("]")
      }
      None => e.write(m.name)
    }
    e.write("(")
    for i, p in m.params {
      if i > 0 {
        e.write(",")
        e.space()
      }
      e.write(p.0)
      // Default-value initializer (`x = 5`) when the parser captured
      // one — `param_defaults` is positionally aligned with `params`
      // (or shorter when there are no defaults at all). Without this
      // the native-class emitter drops `=140` from babel parser's
      // `parseProgram(t, e=140, s=…)` and the loop end marker never
      // matches, hanging the parser on every input.
      if i < m.param_defaults.length() {
        match m.param_defaults[i] {
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
    e.write(")")
    e.space()
    match m.body {
      Some(b) => emit_func_body(e, b)
      None => {
        e.write("{")
        e.write("}")
      }
    }
  }
  // Static field initializers (ES2022 `static foo = init;`). Parser
  // stashes them on `decl.static_field_inits` for native classes;
  // emit them in source order so the class is self-contained. Non-
  // ident names (`"~standard"` / `"a-b"`) need bracket syntax
  // (`static ["~standard"] = init;`) — `static ~standard = …` is a
  // hard parse error.
  for entry in decl.static_field_inits {
    e.nl()
    e.word("static")
    e.sep_after_word('A')
    if is_valid_js_ident(entry.0) {
      e.write(entry.0)
    } else {
      e.write("[")
      emit_string_literal(e, entry.0)
      e.write("]")
    }
    e.space()
    e.write("=")
    e.space()
    emit_expr(e, entry.1, 2)
    e.semi()
  }
  e.close_block()
}

///|
/// JS reserved-word check used by `emit_function_expr` to suppress
/// the function name when it would re-purpose a keyword as an
/// identifier (`function with() {}` is invalid). The list mirrors
/// the strict-mode reserved set plus the always-reserved keywords
/// from the ES spec.
fn is_reserved_word(s : String) -> Bool {
  match s {
    "break"
    | "case"
    | "catch"
    | "class"
    | "const"
    | "continue"
    | "debugger"
    | "default"
    | "delete"
    | "do"
    | "else"
    | "export"
    | "extends"
    | "false"
    | "finally"
    | "for"
    | "function"
    | "if"
    | "import"
    | "in"
    | "instanceof"
    | "let"
    | "new"
    | "null"
    | "return"
    | "super"
    | "switch"
    | "this"
    | "throw"
    | "true"
    | "try"
    | "typeof"
    | "var"
    | "void"
    | "while"
    | "with"
    | "yield"
    | "enum"
    | "await"
    | "implements"
    | "interface"
    | "package"
    | "private"
    | "protected"
    | "public"
    | "static"
    | "arguments"
    | "eval" => true
    _ => false
  }
}

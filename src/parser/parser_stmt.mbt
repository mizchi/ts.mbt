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
          match self.peek_at(1).kind {
            Ident(_) | Str(_) | LBrace => true
            _ => false
          }
        _ => false
      }
    _ => false
  }
}

///|
// / statement
pub fn Parser::parse_stmt(self : Parser) -> @ast.TsStmt raise ParseError {
  let tok = self.peek()
  match tok.kind {
    At => {
      self.skip_decorator()
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
      self.parse_var_like(VarKind::Let, kw_pos)
    }
    Ident("await") if self.peek_at(1).kind is Ident("using") &&
      self.is_await_using_declaration_start() => {
      let kw_pos = self.peek().pos
      let _ = self.advance() // `await`
      let _ = self.advance() // `using`
      self.parse_var_like(VarKind::Let, kw_pos)
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
    Class => self.parse_class_decl()
    Ident("abstract") if self.peek_at(1).kind == Class => {
      let _ = self.advance()
      self.parse_class_decl_with_abstract(true)
    }
    Interface => {
      let _ = self.parse_interface()
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
    _ if self.is_namespace_decl_start() => {
      self.skip_declaration_block()
      Empty
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
      self.in_async = true
      let func = self.parse_function()
      self.in_async = false
      Let(@ast.TsBinding::Ident(func.name), Any, FuncExpr(func))
    }
    Function => {
      // internalfunctiondefine: function name() { ... }
      // Let(name, Any, FuncExpr(func))
      let func = self.parse_function()
      Let(@ast.TsBinding::Ident(func.name), Any, FuncExpr(func))
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
          if !self.labels.contains(name) {
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
          // Check if label exists (should be an iteration label for continue)
          if !self.labels.contains(name) {
            raise ParseError("Undefined label '\{name}'")
          }
      }
      self.consume_semicolon()
      Continue(label)
    }
    Semicolon => {
      let _ = self.advance()
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
      self.labels.push(name)
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
      self.labels.push(name)
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
fn Parser::parse_var_like(
  self : Parser,
  kind : VarKind,
  kw_pos : Int,
) -> @ast.TsStmt raise ParseError {
  let binding = self.parse_binding_pattern()
  let type_ = self.parse_var_decl_type()
  let stmts = self.parse_var_decl_list_from(binding, type_, kind)
  self.consume_semicolon()
  let merged = self.merge_decl_stmts(stmts)
  // If there is a single simple-ident declarator whose initializer is an
  // arrow-function or function-expression, apply JSDoc param/return overlays
  // using the var/let/const keyword position (where the JSDoc block sits).
  apply_jsdoc_var_func_overlay(self.jsdoc_at_pos, merged, kw_pos)
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
  if self.match_(Catch) {
    if self.match_(LParen) {
      let binding = self.parse_binding_pattern()
      if self.check(Colon) {
        let _ = self.advance()
        let _ = self.parse_type()
      }
      let _ = self.expect(RParen)
      catch_binding = Some(binding)
    }
    catch_block = Some(self.parse_block())
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
  }
  let _ = self.expect(LParen)

  // `for (using x of ...)` — ES2023 disposable binding. Same shape as
  // `for (let x of ...)` for parsing purposes; we tag the binding with
  // `TsForOfKind::Let` since the auto-disposal semantics don't affect the
  // type-level shape the checker cares about.
  let using_declaration = if self.is_using_declaration_start() {
    let _ = self.advance()
    true
  } else if self.is_await_using_declaration_start() {
    let _ = self.advance() // `await`
    let _ = self.advance() // `using`
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
    let var_type = self.parse_var_decl_type()
    if self.check(Of) || self.check(In) {
      let is_in = self.check(In)
      if is_await && is_in {
        raise ParseError("for-await-of requires 'of'")
      }
      let _ = self.advance() // of/in
      let iterable = self.parse_expr()
      let _ = self.expect(RParen)
      // Set iteration context for body
      let prev_iteration = self.in_iteration
      self.in_iteration = true
      let body = self.parse_block_or_stmt_no_lexical()
      self.in_iteration = prev_iteration
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
      let binding = self.parse_assignment_binding_pattern()
      if self.check(Of) || self.check(In) {
        let is_in = self.check(In)
        if is_await && is_in {
          raise ParseError("for-await-of requires 'of'")
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
      let ty = if self.check(Colon) {
        let _ = self.advance()
        self.parse_type()
      } else {
        @ast.TsType::Any
      }
      let _ = self.expect(Eq)
      let init = self.parse_expr()
      let _ = self.match_(Semicolon)
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
    self.parse_type()
  } else {
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
    Block({ stmts, stmt_positions: [] })
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
  match kind {
    Var => @ast.TsStmt::Var(binding, type_, init)
    Let => @ast.TsStmt::Let(binding, type_, init)
    Const => @ast.TsStmt::Const(binding, type_, init)
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

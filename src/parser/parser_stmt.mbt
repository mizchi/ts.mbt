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
// / statement
pub fn Parser::parse_stmt(self : Parser) -> @ast.TsStmt raise ParseError {
  let tok = self.peek()
  match tok.kind {
    Var => self.parse_var()
    Let =>
      if self.is_let_identifier_expr_start() {
        self.parse_assign_or_expr()
      } else {
        self.parse_let()
      }
    Const => self.parse_const()
    Return => self.parse_return()
    Throw => self.parse_throw()
    Class => self.parse_class_decl()
    If => self.parse_if()
    Switch => self.parse_switch()
    With => self.parse_with()
    Debugger => self.parse_debugger()
    Do => self.parse_do_while()
    While => self.parse_while()
    For => self.parse_for()
    Try => self.parse_try()
    Ident("async") if self.peek_at(1).kind == Function && not(self.has_line_terminator_after()) => {
      let _ = self.advance()
      let func = self.parse_function()
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
      let label = match self.peek().kind {
        Ident(_) => match self.advance().kind {
          Ident(name) => Some(name)
          _ => None
        }
        _ => None
      }
      self.consume_semicolon()
      Break(label)
    }
    Continue => {
      let _ = self.advance()
      let label = match self.peek().kind {
        Ident(_) => match self.advance().kind {
          Ident(name) => Some(name)
          _ => None
        }
        _ => None
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
      // statement
      let stmt = self.parse_stmt_no_lexical(false)
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
  let _ = self.expect(Let)
  self.parse_var_like(VarKind::Let)
}

///|
// / const statement (type)
fn Parser::parse_const(self : Parser) -> @ast.TsStmt raise ParseError {
  let _ = self.expect(Const)
  self.parse_var_like(VarKind::Const)
}

///|
fn Parser::parse_var(self : Parser) -> @ast.TsStmt raise ParseError {
  let _ = self.expect(Var)
  self.parse_var_like(VarKind::Var)
}

///|
fn Parser::parse_var_like(self : Parser, kind : VarKind) -> @ast.TsStmt raise ParseError {
  let binding = self.parse_binding_pattern()
  let type_ = self.parse_var_decl_type()
  let stmts = self.parse_var_decl_list_from(binding, type_, kind)
  self.consume_semicolon()
  self.merge_decl_stmts(stmts)
}

///|
// / return statement
fn Parser::parse_return(self : Parser) -> @ast.TsStmt raise ParseError {
  let _ = self.expect(Return)
  if self.check(Semicolon) {
    let _ = self.advance()
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
  let _ = self.expect(LParen)
  let cond = self.parse_expr()
  let _ = self.expect(RParen)
  let then_block = self.parse_block_or_stmt_no_lexical()
  let else_block : @ast.TsBlock? = if self.match_(Else) {
    if self.check(If) {
      // else if
      Some(@ast.TsBlock::{ stmts: [self.parse_if()] })
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
  let _ = self.expect(LParen)
  let cond = self.parse_expr()
  let _ = self.expect(RParen)
  let body = self.parse_block_or_stmt_no_lexical()
  While(cond, body)
}

///|
// / do-while statement
fn Parser::parse_do_while(self : Parser) -> @ast.TsStmt raise ParseError {
  let _ = self.expect(Do)
  let body = self.parse_block_or_stmt_no_lexical()
  let _ = self.expect(While)
  let _ = self.expect(LParen)
  let cond = self.parse_expr()
  let _ = self.expect(RParen)
  self.consume_semicolon()
  DoWhile(cond, body)
}

///|
fn Parser::parse_switch(self : Parser) -> @ast.TsStmt raise ParseError {
  let _ = self.expect(Switch)
  let _ = self.expect(LParen)
  let expr = self.parse_expr()
  let _ = self.expect(RParen)
  let _ = self.expect(LBrace)
  let cases : Array[@ast.TsSwitchCase] = []
  while not(self.check(RBrace)) {
    let case_test : @ast.TsExpr? = if self.match_(Case) {
      Some(self.parse_expr())
    } else if self.match_(Default) {
      None
    } else {
      raise ParseError("Expected case or default in switch")
    }
    let _ = self.expect(Colon)
    let stmts : Array[@ast.TsStmt] = []
    while not(self.check(Case)) && not(self.check(Default)) && not(self.check(RBrace)) {
      stmts.push(self.parse_stmt())
    }
    cases.push({ test_expr: case_test, body: { stmts, } })
  }
  let _ = self.expect(RBrace)
  Switch(expr, cases)
}

///|
fn Parser::parse_with(self : Parser) -> @ast.TsStmt raise ParseError {
  let _ = self.expect(With)
  let _ = self.expect(LParen)
  let obj_expr = self.parse_expr()
  let _ = self.expect(RParen)
  let body = self.parse_block_or_stmt_no_lexical()
  With(obj_expr, body)
}

///|
fn Parser::parse_debugger(self : Parser) -> @ast.TsStmt raise ParseError {
  let _ = self.expect(Debugger)
  self.consume_semicolon()
  Debugger
}

fn Parser::is_for_of_head(self : Parser) -> Bool {
  let mut i = 0
  let mut paren = 0
  let mut brace = 0
  let mut bracket = 0
  while i < 4096 {
    let tok = self.peek_at(i)
    match tok.kind {
      Eof => return false
      Semicolon =>
        if paren == 0 && brace == 0 && bracket == 0 {
          return false
        }
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
      Of | In =>
        if paren == 0 && brace == 0 && bracket == 0 {
          return true
        }
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

  // for...of check: for (var/let/const x of arr)
  if (self.check(Let) && not(self.is_let_for_in_head_ident())) ||
    self.check(Const) ||
    self.check(Var) {
    let kind = match self.advance().kind {
      Let => @ast.TsForOfKind::Let
      Const => @ast.TsForOfKind::Const
      Var => @ast.TsForOfKind::Var
      _ => @ast.TsForOfKind::Var
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
      let body = self.parse_block_or_stmt_no_lexical()
      // arrayelementtype ( Number)
      if is_in {
        return ForIn(kind, binding, Number, iterable, body)
      }
      return ForOf(kind, binding, Number, iterable, body)
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
        let body = self.parse_block_or_stmt_no_lexical()
        if is_in {
          return ForIn(@ast.TsForOfKind::Assign, binding, Number, iterable, body)
        }
        return ForOf(@ast.TsForOfKind::Assign, binding, Number, iterable, body)
      }
    }
    let expr = self.parse_expr()
    let stmt : @ast.TsStmt =
      if self.match_(Eq) {
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
    Some(self.parse_expr())
  }
  let _ = self.expect(Semicolon)

  // update ()
  let update : @ast.TsStmt? = if self.check(RParen) {
    None
  } else {
    let expr = self.parse_expr()
    if self.match_(Eq) {
      let value = self.parse_expr()
      match expr {
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
  let body = self.parse_block_or_stmt_no_lexical()
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
    match expr {
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
  } else {
    if self.match_(Comma) {
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
}

///|
// / block
pub fn Parser::parse_block(self : Parser) -> @ast.TsBlock raise ParseError {
  let _ = self.expect(LBrace)
  let stmts : Array[@ast.TsStmt] = []
  let prev_strict = self.in_strict
  let mut in_directive = true
  while not(self.check(RBrace)) && not(self.check(Eof)) {
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
  { stmts, }
}
///|
fn Parser::parse_block_or_stmt_no_lexical(self : Parser) -> @ast.TsBlock raise ParseError {
  if self.check(LBrace) {
    self.parse_block()
  } else {
    { stmts: [self.parse_stmt_no_lexical(true)], }
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
fn Parser::is_let_for_in_head_ident(self : Parser) -> Bool {
  if self.in_strict {
    return false
  }
  if not(self.check(Let)) {
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
    raise ParseError("Lexical declaration not allowed in single-statement position")
  }
  self.parse_stmt()
}

///|
fn Parser::is_disallowed_lexical_stmt_start(self : Parser, allow_function : Bool) -> Bool {
  match self.peek().kind {
    Let => not(self.is_let_identifier_expr_start())
    Const | Class => true
    Function =>
      if self.peek_at(1).kind == Star {
        true
      } else {
        not(allow_function) || self.in_strict
      }
    Ident("async") if self.peek_at(1).kind == Function && not(self.has_line_terminator_after()) =>
      true
    _ => false
  }
}

///|
fn Parser::parse_var_decl_type(self : Parser) -> @ast.TsType raise ParseError {
  if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any
  }
}

///|
fn Parser::merge_decl_stmts(_self : Parser, stmts : Array[@ast.TsStmt]) -> @ast.TsStmt {
  if stmts.length() == 1 {
    stmts[0]
  } else {
    Block({ stmts, })
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
  let init =
    match init_opt {
      Some(expr) => expr
      None => {
        if kind is Const {
          raise ParseError("const declaration requires an initializer")
        }
        match binding {
          @ast.TsBinding::Ident(_) => @ast.TsExpr::Var("undefined")
          _ => raise ParseError("Destructuring declaration requires an initializer")
        }
      }
    }
  match kind {
    Var => @ast.TsStmt::Var(binding, type_, init)
    Let => @ast.TsStmt::Let(binding, type_, init)
    Const => @ast.TsStmt::Const(binding, type_, init)
  }
}

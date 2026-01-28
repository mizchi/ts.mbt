// ============================================
// statement
// ============================================

///|
// / statement
pub fn Parser::parse_stmt(self : Parser) -> TsStmt raise ParseError {
  let tok = self.peek()
  match tok.kind {
    Var => self.parse_var()
    Let => self.parse_let()
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
    Function => {
      // internalfunctiondefine: function name() { ... }
      // Let(name, Any, FuncExpr(func))
      let func = self.parse_function()
      Let(func.name, Any, FuncExpr(func))
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
      let stmt = self.parse_stmt()
      Label(name, stmt)
    }
    _ =>
      // assignment or expressionstatement
      self.parse_assign_or_expr()
  }
}

///|
// / let statement (type)
fn Parser::parse_let(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Let)
  self.parse_let_like(false)
}

///|
// / const statement (type)
fn Parser::parse_const(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Const)
  self.parse_let_like(true)
}

///|
fn Parser::parse_var(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Var)
  self.parse_let_like(false)
}

///|
fn Parser::parse_let_like(self : Parser, is_const : Bool) -> TsStmt raise ParseError {
  let stmts : Array[TsStmt] = []
  while true {
    let name =
      match self.peek().kind {
        Ident(_) => match self.advance().kind {
          Ident(n) => n
          _ => "<destruct>"
        }
        Yield => {
          let _ = self.advance()
          "yield"
        }
        NumberType => {
          let _ = self.advance()
          "number"
        }
        BooleanType => {
          let _ = self.advance()
          "boolean"
        }
        StringType => {
          let _ = self.advance()
          "string"
        }
        VoidType => {
          let _ = self.advance()
          "void"
        }
        IntType => {
          let _ = self.advance()
          "int"
        }
        Type => {
          let _ = self.advance()
          "type"
        }
        Let => {
          let _ = self.advance()
          "let"
        }
        LBracket | LBrace => self.consume_binding_name()
        k => raise ParseError("Expected identifier, got \{k}")
      }
    // type ()
    let type_ = if self.check(Colon) {
      let _ = self.advance()
      self.parse_type()
    } else {
      Any // type Any
    }
    let init =
      if self.match_(Eq) {
        self.parse_assignment()
      } else {
        if is_const {
          raise ParseError("const declaration requires an initializer")
        } else {
          Var("undefined")
        }
      }
    let stmt =
      if is_const {
        TsStmt::Const(name, type_, init)
      } else {
        TsStmt::Let(name, type_, init)
      }
    stmts.push(stmt)
    if self.match_(Comma) {
      continue
    }
    break
  }
  self.consume_semicolon()
  if stmts.length() == 1 {
    stmts[0]
  } else {
    Block({ stmts, })
  }
}

///|
// / return statement
fn Parser::parse_return(self : Parser) -> TsStmt raise ParseError {
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
fn Parser::parse_throw(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Throw)
  let expr = self.parse_expr()
  self.consume_semicolon()
  Throw(expr)
}

///|
// / try/catch/finally statement
fn Parser::parse_try(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Try)
  let try_block = self.parse_block()
  let mut catch_name : String? = None
  let mut catch_block : TsBlock? = None
  if self.match_(Catch) {
    if self.match_(LParen) {
      let name = match self.advance().kind {
        Ident(n) => n
        k => raise ParseError("Expected catch identifier, got \{k}")
      }
      let _ = self.expect(RParen)
      catch_name = Some(name)
    } else {
      catch_name = Some("error")
    }
    catch_block = Some(self.parse_block())
  }
  let mut finally_block : TsBlock? = None
  if self.match_(Finally) {
    finally_block = Some(self.parse_block())
  }
  match (catch_block, finally_block) {
    (None, None) => raise ParseError("try must have catch or finally")
    _ => ()
  }
  Try(try_block, catch_name, catch_block, finally_block)
}

///|
// / if statement
fn Parser::parse_if(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(If)
  let _ = self.expect(LParen)
  let cond = self.parse_expr()
  let _ = self.expect(RParen)
  let then_block = self.parse_block_or_stmt()
  let else_block = if self.match_(Else) {
    if self.check(If) {
      // else if
      { stmts: [self.parse_if()] }
    } else {
      self.parse_block_or_stmt()
    }
  } else {
    { stmts: [] }
  }
  If(cond, then_block, Some(else_block))
}

///|
// / while statement
fn Parser::parse_while(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(While)
  let _ = self.expect(LParen)
  let cond = self.parse_expr()
  let _ = self.expect(RParen)
  let body = self.parse_block_or_stmt()
  While(cond, body)
}

///|
// / do-while statement
fn Parser::parse_do_while(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Do)
  let body = self.parse_block_or_stmt()
  let _ = self.expect(While)
  let _ = self.expect(LParen)
  let cond = self.parse_expr()
  let _ = self.expect(RParen)
  self.consume_semicolon()
  // simple while
  While(cond, body)
}

///|
fn Parser::parse_switch(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Switch)
  let _ = self.expect(LParen)
  let expr = self.parse_expr()
  let _ = self.expect(RParen)
  let _ = self.expect(LBrace)
  let cases : Array[TsSwitchCase] = []
  while not(self.check(RBrace)) {
    let case_test : TsExpr? = if self.match_(Case) {
      Some(self.parse_expr())
    } else if self.match_(Default) {
      None
    } else {
      raise ParseError("Expected case or default in switch")
    }
    let _ = self.expect(Colon)
    let stmts : Array[TsStmt] = []
    while not(self.check(Case)) && not(self.check(Default)) && not(self.check(RBrace)) {
      stmts.push(self.parse_stmt())
    }
    cases.push({ test_expr: case_test, body: { stmts, } })
  }
  let _ = self.expect(RBrace)
  Switch(expr, cases)
}

///|
fn Parser::parse_with(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(With)
  let _ = self.expect(LParen)
  let obj_expr = self.parse_expr()
  let _ = self.expect(RParen)
  let body = self.parse_block_or_stmt()
  With(obj_expr, body)
}

///|
fn Parser::parse_debugger(self : Parser) -> TsStmt raise ParseError {
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
fn Parser::parse_for(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(For)
  let _ = self.expect(LParen)

  // for...of check: for (var/let/const x of arr)
  if self.check(Let) || self.check(Const) || self.check(Var) {
    let kind = match self.advance().kind {
      Let => TsForOfKind::Let
      Const => TsForOfKind::Const
      Var => TsForOfKind::Var
      _ => TsForOfKind::Var
    }
    let binding = self.parse_binding_pattern()
    // for...of / for...in check
    if self.check(Of) || self.check(In) {
      let is_in = self.check(In)
      let _ = self.advance() // of/in
      let iterable = self.parse_expr()
      let _ = self.expect(RParen)
      let body = self.parse_block_or_stmt()
      // arrayelementtype ( Number)
      if is_in {
        return ForIn(kind, binding, Number, iterable, body)
      }
      return ForOf(kind, binding, Number, iterable, body)
    }
    // regular for (let x: type = init; ...) or for (let x = init; ...)
    let var_name = self.binding_first_name(binding)
    let var_type = if self.check(Colon) {
      let _ = self.advance()
      self.parse_type()
    } else {
      Any // type Any
    }
    let _ = self.expect(Eq)
    let init_expr = self.parse_expr()
    let _ = self.expect(Semicolon)
    let init : TsStmt? = Some(
      match kind {
        TsForOfKind::Const => TsStmt::Const(var_name, var_type, init_expr)
        _ => TsStmt::Let(var_name, var_type, init_expr)
      },
    )
    return self.parse_for_rest(init)
  }

  // init
  let init : TsStmt? = if self.check(Semicolon) {
    let _ = self.advance()
    None
  } else {
    if self.is_for_of_head() {
      let binding = self.parse_assignment_binding_pattern()
      if self.check(Of) || self.check(In) {
        let is_in = self.check(In)
        let _ = self.advance()
        let iterable = self.parse_expr()
        let _ = self.expect(RParen)
        let body = self.parse_block_or_stmt()
        if is_in {
          return ForIn(TsForOfKind::Assign, binding, Number, iterable, body)
        }
        return ForOf(TsForOfKind::Assign, binding, Number, iterable, body)
      }
    }
    let expr = self.parse_expr()
    let stmt : TsStmt =
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
  init : TsStmt?,
) -> TsStmt raise ParseError {

  // cond
  let cond : TsExpr? = if self.check(Semicolon) {
    None
  } else {
    Some(self.parse_expr())
  }
  let _ = self.expect(Semicolon)

  // update ()
  let update : TsStmt? = if self.check(RParen) {
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
  let body = self.parse_block_or_stmt()
  For(init, cond, update, body)
}

///|
// / assignmentexpressionstatement
fn Parser::parse_assign_or_expr(self : Parser) -> TsStmt raise ParseError {
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
pub fn Parser::parse_block(self : Parser) -> TsBlock raise ParseError {
  let _ = self.expect(LBrace)
  let stmts : Array[TsStmt] = []
  while not(self.check(RBrace)) && not(self.check(Eof)) {
    stmts.push(self.parse_stmt())
  }
  let _ = self.expect(RBrace)
  { stmts, }
}
///|
///|
// / blockstatement
fn Parser::parse_block_or_stmt(self : Parser) -> TsBlock raise ParseError {
  if self.check(LBrace) {
    self.parse_block()
  } else {
    { stmts: [self.parse_stmt()], }
  }
}

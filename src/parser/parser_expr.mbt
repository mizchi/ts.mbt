// ============================================
// expression
// ============================================

///|
// / expression (prefer)
pub fn Parser::parse_expr(self : Parser) -> @ast.TsExpr raise ParseError {
  self.parse_comma()
}

///|
// / operator
fn Parser::parse_comma(self : Parser) -> @ast.TsExpr raise ParseError {
  let mut expr = self.parse_assignment()
  while self.match_(Comma) {
    let right = self.parse_assignment()
    expr = Seq(expr, right)
  }
  expr
}

///|
// / assignmentexpression
fn Parser::parse_assignment(self : Parser) -> @ast.TsExpr raise ParseError {
  if (self.check(LBracket) || self.check(LBrace)) &&
    self.is_destructuring_assignment_start() {
    let pattern = self.parse_assignment_binding_pattern()
    let _ = self.expect(Eq)
    let right = self.parse_assignment()
    return AssignPattern(pattern, right)
  }
  let left = self.parse_ternary()
  if self.check(Eq) {
    match left {
      Var(name) => {
        // In strict mode, cannot assign to eval or arguments
        if self.in_strict && (name == "eval" || name == "arguments") {
          raise ParseError("Cannot assign to '\{name}' in strict mode")
        }
        let _ = self.advance()
        let right = self.parse_assignment()
        AssignExpr(name, right)
      }
      PropAccess(obj, prop) => {
        let _ = self.advance()
        let right = self.parse_assignment()
        PropAssignExpr(obj, prop, right)
      }
      IndexAccess(obj, index) => {
        let _ = self.advance()
        let right = self.parse_assignment()
        IndexAssignExpr(obj, index, right)
      }
      _ => left
    }
  } else if self.match_(PlusEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), AddAssign, right)
      PropAccess(obj, prop) =>
        CompoundAssignExpr(PropAccess(obj, prop), AddAssign, right)
      IndexAccess(obj, index) =>
        CompoundAssignExpr(IndexAccess(obj, index), AddAssign, right)
      _ => right
    }
  } else if self.match_(MinusEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), SubAssign, right)
      PropAccess(obj, prop) =>
        CompoundAssignExpr(PropAccess(obj, prop), SubAssign, right)
      IndexAccess(obj, index) =>
        CompoundAssignExpr(IndexAccess(obj, index), SubAssign, right)
      _ => right
    }
  } else if self.match_(StarEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), MulAssign, right)
      PropAccess(obj, prop) =>
        CompoundAssignExpr(PropAccess(obj, prop), MulAssign, right)
      IndexAccess(obj, index) =>
        CompoundAssignExpr(IndexAccess(obj, index), MulAssign, right)
      _ => right
    }
  } else if self.match_(SlashEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), DivAssign, right)
      PropAccess(obj, prop) =>
        CompoundAssignExpr(PropAccess(obj, prop), DivAssign, right)
      IndexAccess(obj, index) =>
        CompoundAssignExpr(IndexAccess(obj, index), DivAssign, right)
      _ => right
    }
  } else if self.match_(PercentEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), ModAssign, right)
      PropAccess(obj, prop) =>
        CompoundAssignExpr(PropAccess(obj, prop), ModAssign, right)
      IndexAccess(obj, index) =>
        CompoundAssignExpr(IndexAccess(obj, index), ModAssign, right)
      _ => right
    }
  } else if self.match_(AmpEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), BitAndAssign, right)
      PropAccess(obj, prop) =>
        CompoundAssignExpr(PropAccess(obj, prop), BitAndAssign, right)
      IndexAccess(obj, index) =>
        CompoundAssignExpr(IndexAccess(obj, index), BitAndAssign, right)
      _ => right
    }
  } else if self.match_(PipeEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), BitOrAssign, right)
      PropAccess(obj, prop) =>
        CompoundAssignExpr(PropAccess(obj, prop), BitOrAssign, right)
      IndexAccess(obj, index) =>
        CompoundAssignExpr(IndexAccess(obj, index), BitOrAssign, right)
      _ => right
    }
  } else if self.match_(CaretEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), BitXorAssign, right)
      PropAccess(obj, prop) =>
        CompoundAssignExpr(PropAccess(obj, prop), BitXorAssign, right)
      IndexAccess(obj, index) =>
        CompoundAssignExpr(IndexAccess(obj, index), BitXorAssign, right)
      _ => right
    }
  } else if self.match_(LtLtEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), ShlAssign, right)
      PropAccess(obj, prop) =>
        CompoundAssignExpr(PropAccess(obj, prop), ShlAssign, right)
      IndexAccess(obj, index) =>
        CompoundAssignExpr(IndexAccess(obj, index), ShlAssign, right)
      _ => right
    }
  } else if self.match_(GtGtEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), ShrAssign, right)
      PropAccess(obj, prop) =>
        CompoundAssignExpr(PropAccess(obj, prop), ShrAssign, right)
      IndexAccess(obj, index) =>
        CompoundAssignExpr(IndexAccess(obj, index), ShrAssign, right)
      _ => right
    }
  } else if self.match_(GtGtGtEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), UShrAssign, right)
      PropAccess(obj, prop) =>
        CompoundAssignExpr(PropAccess(obj, prop), UShrAssign, right)
      IndexAccess(obj, index) =>
        CompoundAssignExpr(IndexAccess(obj, index), UShrAssign, right)
      _ => right
    }
  } else if self.match_(StarStarEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), PowAssign, right)
      PropAccess(obj, prop) =>
        CompoundAssignExpr(PropAccess(obj, prop), PowAssign, right)
      IndexAccess(obj, index) =>
        CompoundAssignExpr(IndexAccess(obj, index), PowAssign, right)
      _ => right
    }
  } else if self.match_(AmpAmpEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), AndAssign, right)
      PropAccess(obj, prop) =>
        CompoundAssignExpr(PropAccess(obj, prop), AndAssign, right)
      IndexAccess(obj, index) =>
        CompoundAssignExpr(IndexAccess(obj, index), AndAssign, right)
      _ => right
    }
  } else if self.match_(PipePipeEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), OrAssign, right)
      PropAccess(obj, prop) =>
        CompoundAssignExpr(PropAccess(obj, prop), OrAssign, right)
      IndexAccess(obj, index) =>
        CompoundAssignExpr(IndexAccess(obj, index), OrAssign, right)
      _ => right
    }
  } else if self.match_(QuestionQuestionEq) {
    let right = self.parse_assignment()
    match left {
      Var(name) => CompoundAssignExpr(Var(name), CoalesceAssign, right)
      PropAccess(obj, prop) =>
        CompoundAssignExpr(PropAccess(obj, prop), CoalesceAssign, right)
      IndexAccess(obj, index) =>
        CompoundAssignExpr(IndexAccess(obj, index), CoalesceAssign, right)
      _ => right
    }
  } else {
    left
  }
}

///|
fn Parser::is_destructuring_assignment_start(self : Parser) -> Bool {
  let saved_pos = self.pos
  let saved_gen = self.in_generator
  let mut ok = false
  try {
    let _ = self.parse_assignment_binding_pattern()
    ok = self.check(Eq)
  } catch {
    _ => ok = false
  }
  self.pos = saved_pos
  self.in_generator = saved_gen
  ok
}

///|
// / operator: cond ? then : else
fn Parser::parse_ternary(self : Parser) -> @ast.TsExpr raise ParseError {
  let cond = self.parse_or()
  if self.match_(Question) {
    let then_expr = self.parse_expr()
    let _ = self.expect(Colon)
    let else_expr = self.parse_expr()
    Cond(cond, then_expr, else_expr)
  } else {
    cond
  }
}

///|
// / || (OR) and ?? (Nullish Coalesce)
fn Parser::parse_or(self : Parser) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_and()
  while self.check(PipePipe) || self.check(QuestionQuestion) {
    if self.match_(PipePipe) {
      let right = self.parse_and()
      left = BinOp(Or, left, right)
    } else if self.match_(QuestionQuestion) {
      let right = self.parse_and()
      left = BinOp(Coalesce, left, right)
    }
  }
  left
}

///|
// / && (AND)
fn Parser::parse_and(self : Parser) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_bit_or()
  while self.match_(AmpAmp) {
    let right = self.parse_bit_or()
    left = BinOp(And, left, right)
  }
  left
}

///|
// / | (OR)
fn Parser::parse_bit_or(self : Parser) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_bit_xor()
  while self.match_(Pipe) {
    let right = self.parse_bit_xor()
    left = BinOp(BitOr, left, right)
  }
  left
}

///|
// / ^ (XOR)
fn Parser::parse_bit_xor(self : Parser) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_bit_and()
  while self.match_(Caret) {
    let right = self.parse_bit_and()
    left = BinOp(BitXor, left, right)
  }
  left
}

///|
// / & (AND)
fn Parser::parse_bit_and(self : Parser) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_equality()
  while self.match_(Amp) {
    let right = self.parse_equality()
    left = BinOp(BitAnd, left, right)
  }
  left
}

///|
// / === !== == != (comparison)
fn Parser::parse_equality(self : Parser) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_comparison()
  while true {
    if self.match_(EqEqEq) {
      let right = self.parse_comparison()
      left = BinOp(BinEq, left, right)
    } else if self.match_(BangEqEq) {
      let right = self.parse_comparison()
      left = BinOp(BinNe, left, right)
    } else if self.match_(EqEq) {
      let right = self.parse_comparison()
      left = BinOp(AbstractEq, left, right)
    } else if self.match_(BangEq) {
      let right = self.parse_comparison()
      left = BinOp(AbstractNe, left, right)
    } else {
      break
    }
  }
  left
}

///|
// / < <= > >= (comparison)
fn Parser::parse_comparison(self : Parser) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_shift()
  while true {
    if self.match_(Lt) {
      let right = self.parse_shift()
      left = BinOp(BinLt, left, right)
    } else if self.match_(Le) {
      let right = self.parse_shift()
      left = BinOp(BinLe, left, right)
    } else if self.match_(Gt) {
      let right = self.parse_shift()
      left = BinOp(BinGt, left, right)
    } else if self.match_(Ge) {
      let right = self.parse_shift()
      left = BinOp(BinGe, left, right)
    } else if self.match_(Instanceof) {
      let right = self.parse_shift()
      left = BinOp(Instanceof, left, right)
    } else if self.match_(In) {
      let right = self.parse_shift()
      left = BinOp(In, left, right)
    } else {
      break
    }
  }
  left
}

///|
// / << >> >>> ()
fn Parser::parse_shift(self : Parser) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_additive()
  while true {
    if self.match_(LtLt) {
      let right = self.parse_additive()
      left = BinOp(Shl, left, right)
    } else if self.match_(GtGt) {
      let right = self.parse_additive()
      left = BinOp(Shr, left, right)
    } else if self.match_(GtGtGt) {
      let right = self.parse_additive()
      left = BinOp(UShr, left, right)
    } else {
      break
    }
  }
  left
}

///|
// / + - ()
fn Parser::parse_additive(self : Parser) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_multiplicative()
  while true {
    if self.match_(Plus) {
      let right = self.parse_multiplicative()
      left = BinOp(Add, left, right)
    } else if self.match_(Minus) {
      let right = self.parse_multiplicative()
      left = BinOp(Sub, left, right)
    } else {
      break
    }
  }
  left
}

///|
// / * / % ()
fn Parser::parse_multiplicative(self : Parser) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_exponent()
  while true {
    if self.match_(Star) {
      let right = self.parse_exponent()
      left = BinOp(Mul, left, right)
    } else if self.match_(Slash) {
      let right = self.parse_exponent()
      left = BinOp(Div, left, right)
    } else if self.match_(Percent) {
      let right = self.parse_exponent()
      left = BinOp(Mod, left, right)
    } else {
      break
    }
  }
  left
}

///|
// / ** ()
fn Parser::parse_exponent(self : Parser) -> @ast.TsExpr raise ParseError {
  let left = self.parse_unary()
  if self.match_(StarStar) {
    let right = self.parse_exponent()
    BinOp(Pow, left, right)
  } else {
    left
  }
}

///|
// / unaryoperator
fn Parser::parse_unary(self : Parser) -> @ast.TsExpr raise ParseError {
  if self.match_(Minus) {
    let operand = self.parse_unary()
    UnaryOp(Neg, operand)
  } else if self.match_(Plus) {
    let operand = self.parse_unary()
    UnaryOp(Plus, operand)
  } else if self.match_(Typeof) {
    let operand = self.parse_unary()
    UnaryOp(Typeof, operand)
  } else if self.match_(Delete) {
    let operand = self.parse_unary()
    UnaryOp(Delete, operand)
  } else if self.match_(VoidType) {
    let operand = self.parse_unary()
    UnaryOp(Void, operand)
  } else if self.match_(Bang) {
    let operand = self.parse_unary()
    UnaryOp(Not, operand)
  } else if self.match_(PlusPlus) {
    // ++x ()
    let operand = self.parse_unary()
    UnaryOp(PreInc, operand)
  } else if self.match_(MinusMinus) {
    // --x ()
    let operand = self.parse_unary()
    UnaryOp(PreDec, operand)
  } else if self.match_(Yield) {
    if self.in_generator {
      if self.match_(Star) {
        let expr = self.parse_assignment()
        YieldStar(expr)
      } else {
        let expr = if self.check(Semicolon) ||
          self.check(Comma) ||
          self.check(RParen) ||
          self.check(RBracket) ||
          self.check(RBrace) {
          None
        } else {
          Some(self.parse_unary())
        }
        Yield(expr)
      }
    } else {
      Var("yield")
    }
  } else if self.peek().kind == Ident("await") {
    // await expression - valid in async functions or top-level await
    let _ = self.advance()
    let expr = self.parse_unary()
    Await(expr)
  } else {
    self.parse_postfix()
  }
}

///|
// / operator (x++, x--)
fn Parser::parse_postfix(self : Parser) -> @ast.TsExpr raise ParseError {
  let mut expr = self.parse_call()
  while true {
    if self.match_(PlusPlus) {
      expr = UnaryOp(PostInc, expr)
    } else if self.match_(MinusMinus) {
      expr = UnaryOp(PostDec, expr)
    } else {
      break
    }
  }
  expr
}

///|
// / function, array, property, method
fn Parser::parse_call(self : Parser) -> @ast.TsExpr raise ParseError {
  let mut expr = self.parse_primary()

  // operatorcheck
  while true {
    if self.check(Question) && self.peek_at(1).kind == Dot {
      let _ = self.advance()
      let _ = self.advance()
      match self.peek().kind {
        LBracket => {
          let _ = self.advance()
          let index = self.parse_expr()
          let _ = self.expect(RBracket)
          expr = IndexAccess(expr, index)
          continue
        }
        LParen => {
          let _ = self.advance()
          let args = self.parse_args()
          let _ = self.expect(RParen)
          match expr {
            Var(name) => expr = Call(name, args)
            PropAccess(receiver, method_name) =>
              expr = MethodCall(receiver, method_name, args)
            _ => expr = CallExpr(expr, args)
          }
          continue
        }
        _ => {
          let prop = match self.advance().kind {
            Ident(name) => name
            PrivateIdent(name) => "#" + name
            Return => "return"
            If => "if"
            Else => "else"
            For => "for"
            While => "while"
            Switch => "switch"
            Case => "case"
            Default => "default"
            With => "with"
            Debugger => "debugger"
            Import => "import"
            Export => "export"
            From => "from"
            As => "as"
            Break => "break"
            Continue => "continue"
            Function => "function"
            Do => "do"
            Try => "try"
            Catch => "catch"
            Finally => "finally"
            Throw => "throw"
            Delete => "delete"
            Yield => "yield"
            Let => "let"
            Const => "const"
            Var => "var"
            New => "new"
            Typeof => "typeof"
            Of => "of"
            In => "in"
            Class => "class"
            Declare => "declare"
            Interface => "interface"
            Instanceof => "instanceof"
            NumberType => "number"
            BooleanType => "boolean"
            StringType => "string"
            VoidType => "void"
            IntType => "int"
            Type => "type"
            Extends => "extends"
            k => raise ParseError("Expected property name, got \{k}")
          }
          expr = PropAccess(expr, prop)
          continue
        }
      }
    }
    if self.match_(LParen) {
      // function or method
      let args = self.parse_args()
      let _ = self.expect(RParen)
      match expr {
        Var(name) => expr = Call(name, args)
        PropAccess(receiver, method_name) =>
          // method: receiver.method(args)
          expr = MethodCall(receiver, method_name, args)
        _ => expr = CallExpr(expr, args)
      }
    } else if self.match_(LBracket) {
      // array
      let index = self.parse_expr()
      let _ = self.expect(RBracket)
      expr = IndexAccess(expr, index)
    } else if self.check(Dot) {
      // property
      let _ = self.advance()
      let prop = match self.advance().kind {
        Ident(name) => name
        PrivateIdent(name) => "#" + name
        Return => "return"
        If => "if"
        Else => "else"
        For => "for"
        While => "while"
        Switch => "switch"
        Case => "case"
        Default => "default"
        With => "with"
        Debugger => "debugger"
        Import => "import"
        Export => "export"
        From => "from"
        As => "as"
        Break => "break"
        Continue => "continue"
        Function => "function"
        Do => "do"
        Try => "try"
        Catch => "catch"
        Finally => "finally"
        Throw => "throw"
        Delete => "delete"
        Yield => "yield"
        Let => "let"
        Const => "const"
        Var => "var"
        New => "new"
        Typeof => "typeof"
        Of => "of"
        In => "in"
        Class => "class"
        Declare => "declare"
        Interface => "interface"
        Instanceof => "instanceof"
        NumberType => "number"
        BooleanType => "boolean"
        StringType => "string"
        VoidType => "void"
        IntType => "int"
        Type => "type"
        Extends => "extends"
        k => raise ParseError("Expected property name, got \{k}")
      }
      expr = PropAccess(expr, prop)
    } else {
      break
    }
  }
  expr
}

///|
// / argument
fn Parser::parse_args(self : Parser) -> Array[@ast.TsExpr] raise ParseError {
  let args : Array[@ast.TsExpr] = []
  if not(self.check(RParen)) {
    if self.match_ellipsis() {
      args.push(Spread(self.parse_assignment()))
    } else {
      args.push(self.parse_assignment())
    }
    while self.match_(Comma) {
      if self.check(RParen) {
        break
      }
      if self.match_ellipsis() {
        args.push(Spread(self.parse_assignment()))
      } else {
        args.push(self.parse_assignment())
      }
    }
  }
  args
}

///|
// / expression (literal, variable, , array, new)
fn Parser::parse_primary(self : Parser) -> @ast.TsExpr raise ParseError {
  let tok = self.peek()
  match tok.kind {
    Class => self.parse_class_stub()
    Number(n) => {
      let _ = self.advance()
      NumberLit(n)
    }
    Int(i) => {
      let _ = self.advance()
      IntLit(i)
    }
    LegacyOctal(i) => {
      if self.in_strict {
        raise ParseError(
          "Octal literals are not allowed in strict mode",
        )
      }
      let _ = self.advance()
      IntLit(i)
    }
    BigInt(s) => {
      let _ = self.advance()
      BigIntLit(s)
    }
    Bool(b) => {
      let _ = self.advance()
      BoolLit(b)
    }
    NumberType => {
      let _ = self.advance()
      Var("number")
    }
    BooleanType => {
      let _ = self.advance()
      Var("boolean")
    }
    StringType => {
      let _ = self.advance()
      Var("string")
    }
    VoidType => {
      let _ = self.advance()
      Var("void")
    }
    IntType => {
      let _ = self.advance()
      Var("int")
    }
    Type => {
      let _ = self.advance()
      Var("type")
    }
    Str(s) => {
      let _ = self.advance()
      StringLit(s)
    }
    Regex(pattern, flags) => {
      let _ = self.advance()
      let args : Array[@ast.TsExpr] = []
      args.push(StringLit(pattern))
      if flags != "" {
        args.push(StringLit(flags))
      }
      New("RegExp", args)
    }
    Ident(name) =>
      if name == "async" &&
        self.peek_at(1).kind == Function &&
        not(self.has_line_terminator_after()) {
        let _ = self.advance()
        self.in_async = true
        let func = self.parse_function_expr()
        self.in_async = false
        @ast.TsExpr::FuncExpr(func)
      } else if name == "async" &&
        not(self.has_line_terminator_after()) &&
        self.is_async_arrow_function() {
        // async arrow function: async (params) => body or async x => body
        let _ = self.advance()
        self.parse_async_arrow_function()
      } else if self.peek_at(1).kind == Arrow {
        let _ = self.advance()
        let _ = self.expect(Arrow)
        let body = if self.check(LBrace) {
          // Save and set function context for arrow block body
          let prev_function = self.in_function
          let prev_iteration = self.in_iteration
          let prev_switch = self.in_switch
          // Save labels and clear for new function scope
          let prev_labels : Array[String] = []
          for label in self.labels {
            prev_labels.push(label)
          }
          self.in_function = true
          self.in_iteration = false
          self.in_switch = false
          while self.labels.length() > 0 {
            let _ = self.labels.pop()

          }
          let block = self.parse_block()
          self.in_function = prev_function
          self.in_iteration = prev_iteration
          self.in_switch = prev_switch
          // Restore labels
          while self.labels.length() > 0 {
            let _ = self.labels.pop()

          }
          for label in prev_labels {
            self.labels.push(label)
          }
          @ast.TsArrowBody::ArrowBlock(block)
        } else {
          let expr = self.parse_assignment()
          ArrowExpr(expr)
        }
        ArrowFunc(
          [
            {
              name,
              binding: Some(@ast.TsBinding::Ident(name)),
              is_rest: false,
              type_: Any,
              default: None,
            },
          ],
          body,
          false,
        )
      } else {
        let _ = self.advance()
        Var(name)
      }
    Let =>
      if self.in_strict {
        raise ParseError("Unexpected token: Let")
      } else {
        let _ = self.advance()
        Var("let")
      }
    PrivateIdent(name) => {
      let _ = self.advance()
      Var("#" + name)
    }
    LParen =>
      // functioncheck
      if self.is_arrow_function() {
        // function: (params) => body
        let _ = self.advance() // (
        let params = self.parse_params()
        let _ = self.expect(RParen)
        let _ = self.expect(Arrow)
        // : blockexpression
        let body = if self.check(LBrace) {
          // Save and set function context for arrow block body
          let prev_function = self.in_function
          let prev_iteration = self.in_iteration
          let prev_switch = self.in_switch
          // Save labels and clear for new function scope
          let prev_labels : Array[String] = []
          for label in self.labels {
            prev_labels.push(label)
          }
          self.in_function = true
          self.in_iteration = false
          self.in_switch = false
          while self.labels.length() > 0 {
            let _ = self.labels.pop()

          }
          let block = self.parse_block()
          self.in_function = prev_function
          self.in_iteration = prev_iteration
          self.in_switch = prev_switch
          // Restore labels
          while self.labels.length() > 0 {
            let _ = self.labels.pop()

          }
          for label in prev_labels {
            self.labels.push(label)
          }
          @ast.TsArrowBody::ArrowBlock(block)
        } else {
          let expr = self.parse_assignment()
          ArrowExpr(expr)
        }
        ArrowFunc(params, body, false)
      } else {
        // regularexpression
        let _ = self.advance()
        let expr = self.parse_expr()
        let _ = self.expect(RParen)
        expr
      }
    LBracket => {
      // arrayliteral: [1, 2, 3]
      let _ = self.advance()
      let elements : Array[@ast.TsExpr] = []
      while not(self.check(RBracket)) {
        if self.match_ellipsis() {
          elements.push(Spread(self.parse_assignment()))
          if self.match_(Comma) {
            if self.check(RBracket) {
              break
            }
            continue
          }
          break
        }
        if self.check(Comma) {
          let _ = self.advance()
          elements.push(ArrayHole)
          continue
        }
        elements.push(self.parse_assignment())
        if self.match_(Comma) {
          if self.check(RBracket) {
            break
          }
          continue
        } else {
          break
        }
      }
      let _ = self.expect(RBracket)
      ArrayLit(elements)
    }
    New => {
      // new expression: new Array<number>(10)
      let _ = self.advance()
      if self.match_(Dot) {
        let prop = match self.advance().kind {
          Ident(n) => n
          Return => "return"
          If => "if"
          Else => "else"
          For => "for"
          While => "while"
          Switch => "switch"
          Case => "case"
          Default => "default"
          With => "with"
          Debugger => "debugger"
          Import => "import"
          Export => "export"
          From => "from"
          As => "as"
          Break => "break"
          Continue => "continue"
          Function => "function"
          Do => "do"
          Try => "try"
          Catch => "catch"
          Finally => "finally"
          Throw => "throw"
          Delete => "delete"
          Yield => "yield"
          Let => "let"
          Const => "const"
          Var => "var"
          New => "new"
          Typeof => "typeof"
          Of => "of"
          In => "in"
          Class => "class"
          Declare => "declare"
          Interface => "interface"
          Instanceof => "instanceof"
          NumberType => "number"
          BooleanType => "boolean"
          StringType => "string"
          VoidType => "void"
          IntType => "int"
          Type => "type"
          Extends => "extends"
          k => raise ParseError("Expected property name, got \{k}")
        }
        return PropAccess(Var("new"), prop)
      }
      let mut type_name = ""
      let mut callee_expr : @ast.TsExpr? = None
      match self.peek().kind {
        Ident(_) => {
          let first = match self.advance().kind {
            Ident(n) => n
            _ => "<call>"
          }
          type_name = first
          let mut expr : @ast.TsExpr = Var(first)
          // allow dotted constructor name: new obj.Type()
          while self.match_(Dot) {
            let part = match self.advance().kind {
              Ident(n) => n
              k => raise ParseError("Expected identifier after '.', got \{k}")
            }
            type_name = type_name + "." + part
            expr = PropAccess(expr, part)
          }
          callee_expr = Some(expr)
          // typeparameter (simpleimplementation)
          if self.match_(Lt) {
            let _ = self.parse_type()
            let _ = self.expect(Gt)

          }
        }
        NumberType => {
          let _ = self.advance()
          type_name = "number"
        }
        BooleanType => {
          let _ = self.advance()
          type_name = "boolean"
        }
        StringType => {
          let _ = self.advance()
          type_name = "string"
        }
        VoidType => {
          let _ = self.advance()
          type_name = "void"
        }
        IntType => {
          let _ = self.advance()
          type_name = "int"
        }
        Type => {
          let _ = self.advance()
          type_name = "type"
        }
        LParen => {
          let _ = self.advance()
          let expr = self.parse_expr()
          let _ = self.expect(RParen)
          callee_expr = Some(expr)
          type_name = "<call>"
        }
        Number(_) | Int(_) | Str(_) | Bool(_) | Null => {
          let expr = self.parse_primary()
          callee_expr = Some(expr)
          type_name = "<call>"
        }
        Function => {
          let func = self.parse_function_expr()
          callee_expr = Some(@ast.TsExpr::FuncExpr(func))
          type_name = "<call>"
        }
        Class => {
          let expr = self.parse_class_stub()
          callee_expr = Some(expr)
          type_name = "<class>"
        }
        New => {
          let expr = self.parse_primary()
          callee_expr = Some(expr)
          type_name = "<call>"
        }
        k => raise ParseError("Expected type name after new, got \{k}")
      }
      // If we can derive a dotted name from the callee expression, prefer it.
      match callee_expr {
        Some(expr) =>
          match expr {
            Var(n) => type_name = n
            PropAccess(Var(obj), prop) => type_name = obj + "." + prop
            _ => ()
          }
        None => ()
      }
      let args = if self.check(LParen) {
        let _ = self.expect(LParen)
        let args = self.parse_args()
        let _ = self.expect(RParen)
        args
      } else {
        []
      }
      match callee_expr {
        Some(expr) =>
          match expr {
            Var(_) => New(type_name, args)
            _ => NewExpr(expr, args)
          }
        None => New(type_name, args)
      }
    }
    LBrace => {
      // objectliteral: { key: value, ... }
      let _ = self.advance()
      let fields : Array[(String, @ast.TsExpr)] = []
      let mut spread_idx = 0
      let mut computed_idx = 0
      if not(self.check(RBrace)) {
        if self.match_ellipsis() {
          let spread_expr = self.parse_assignment()
          fields.push(("@@spread:" + spread_idx.to_string(), spread_expr))
          spread_idx += 1
        } else {
          // field
          let mut is_ident_key = false
          let mut is_computed_key = false
          let mut computed_key_expr : @ast.TsExpr? = None
          let _ = self.match_(Star)
          let key = if self.match_(LBracket) {
            let key_expr = self.parse_assignment()
            let _ = self.expect(RBracket)
            is_computed_key = true
            computed_key_expr = Some(key_expr)
            let idx = computed_idx
            computed_idx += 1
            "@@computed:" + idx.to_string()
          } else {
            match self.advance().kind {
              Ident(n) => {
                is_ident_key = true
                n
              }
              Str(s) => s
              Int(i) => i.to_string()
              Number(n) => n.to_string()
              Yield => "yield"
              Return => "return"
              If => "if"
              Else => "else"
              For => "for"
              While => "while"
              Switch => "switch"
              Case => "case"
              Default => "default"
              With => "with"
              Debugger => "debugger"
              Import => "import"
              Export => "export"
              From => "from"
              As => "as"
              Break => "break"
              Continue => "continue"
              Function => "function"
              Do => "do"
              Try => "try"
              Catch => "catch"
              Finally => "finally"
              Throw => "throw"
              Delete => "delete"
              Let => "let"
              Const => "const"
              Var => "var"
              New => "new"
              Typeof => "typeof"
              Of => "of"
              In => "in"
              Declare => "declare"
              Interface => "interface"
              Class => "class"
              Instanceof => "instanceof"
              NumberType => "number"
              BooleanType => "boolean"
              StringType => "string"
              VoidType => "void"
              IntType => "int"
              Type => "type"
              Extends => "extends"
              k => raise ParseError("Expected property name, got \{k}")
            }
          }
          let mut prop_key = key
          let value = if is_ident_key &&
            (prop_key == "get" || prop_key == "set") &&
            not(self.check(Colon)) &&
            not(self.check(LParen)) &&
            not(self.check(Comma)) &&
            not(self.check(RBrace)) {
            let mut acc_computed_key : @ast.TsExpr? = None
            let acc_key = if self.match_(LBracket) {
              let key_expr = self.parse_assignment()
              let _ = self.expect(RBracket)
              // Store the computed key expression for runtime evaluation
              acc_computed_key = Some(key_expr)
              let idx = computed_idx
              computed_idx += 1
              "@@computed:" + idx.to_string()
            } else {
              match self.advance().kind {
                Ident(n) => n
                Str(s) => s
                Int(i) => i.to_string()
                Number(n) => n.to_string()
                Yield => "yield"
                Return => "return"
                If => "if"
                Else => "else"
                For => "for"
                While => "while"
                Switch => "switch"
                Case => "case"
                Default => "default"
                With => "with"
                Debugger => "debugger"
                Import => "import"
                Export => "export"
                From => "from"
                As => "as"
                Break => "break"
                Continue => "continue"
                Function => "function"
                Do => "do"
                Try => "try"
                Catch => "catch"
                Finally => "finally"
                Throw => "throw"
                Delete => "delete"
                Let => "let"
                Const => "const"
                Var => "var"
                New => "new"
                Typeof => "typeof"
                Of => "of"
                In => "in"
                Declare => "declare"
                Interface => "interface"
                Class => "class"
                Instanceof => "instanceof"
                NumberType => "number"
                BooleanType => "boolean"
                StringType => "string"
                VoidType => "void"
                IntType => "int"
                Type => "type"
                Extends => "extends"
                k => raise ParseError("Expected property name, got \{k}")
              }
            }
            let is_getter = prop_key == "get"
            let func_name = acc_key
            prop_key = if is_getter {
              "@@get:" + acc_key
            } else {
              "@@set:" + acc_key
            }
            // Mark that we need to use the computed key
            is_computed_key = acc_computed_key is Some(_)
            computed_key_expr = acc_computed_key
            let _ = self.expect(LParen)
            let params = self.parse_params()
            let _ = self.expect(RParen)
            let return_type = if self.check(Colon) {
              let _ = self.advance()
              self.parse_type()
            } else {
              Any
            }
            let body = self.parse_block()
            @ast.TsExpr::FuncExpr(@ast.TsFunc::{
              name: func_name,
              params,
              return_type,
              body,
              is_generator: false, is_async: false,
            })
          } else if self.match_(Colon) {
            self.parse_assignment()
          } else if is_ident_key && self.match_(Eq) {
            self.parse_assignment()
          } else if self.check(LParen) {
            let _ = self.expect(LParen)
            let params = self.parse_params()
            let _ = self.expect(RParen)
            let return_type = if self.check(Colon) {
              let _ = self.advance()
              self.parse_type()
            } else {
              Any
            }
            let body = self.parse_block()
            @ast.TsExpr::FuncExpr({
              name: prop_key,
              params,
              return_type,
              body,
              is_generator: false, is_async: false,
            })
          } else if is_ident_key && (self.check(Comma) || self.check(RBrace)) {
            Var(prop_key)
          } else {
            raise ParseError("Expected Colon, got \{self.peek().kind}")
          }
          // Wrap computed keys in ComputedProp
          let final_value = match (is_computed_key, computed_key_expr) {
            (true, Some(key_expr)) => @ast.TsExpr::ComputedProp(key_expr, value)
            _ => value
          }
          fields.push((prop_key, final_value))
        }
        // field
        while self.match_(Comma) {
          if self.check(RBrace) {
            break // trailing comma
          }
          if self.match_ellipsis() {
            let spread_expr = self.parse_assignment()
            fields.push(("@@spread:" + spread_idx.to_string(), spread_expr))
            spread_idx += 1
            continue
          }
          let mut is_ident_key = false
          let mut is_computed_key = false
          let mut computed_key_expr : @ast.TsExpr? = None
          let _ = self.match_(Star)
          let key = if self.match_(LBracket) {
            let key_expr = self.parse_assignment()
            let _ = self.expect(RBracket)
            is_computed_key = true
            computed_key_expr = Some(key_expr)
            let idx = computed_idx
            computed_idx += 1
            "@@computed:" + idx.to_string()
          } else {
            match self.advance().kind {
              Ident(n) => {
                is_ident_key = true
                n
              }
              Str(s) => s
              Int(i) => i.to_string()
              Number(n) => n.to_string()
              Return => "return"
              If => "if"
              Else => "else"
              For => "for"
              While => "while"
              Switch => "switch"
              Case => "case"
              Default => "default"
              With => "with"
              Debugger => "debugger"
              Import => "import"
              Export => "export"
              From => "from"
              As => "as"
              Break => "break"
              Continue => "continue"
              Function => "function"
              Do => "do"
              Try => "try"
              Catch => "catch"
              Finally => "finally"
              Throw => "throw"
              Delete => "delete"
              Yield => "yield"
              Let => "let"
              Const => "const"
              Var => "var"
              New => "new"
              Typeof => "typeof"
              Of => "of"
              In => "in"
              Declare => "declare"
              Interface => "interface"
              Class => "class"
              Instanceof => "instanceof"
              NumberType => "number"
              BooleanType => "boolean"
              StringType => "string"
              VoidType => "void"
              IntType => "int"
              Type => "type"
              Extends => "extends"
              k => raise ParseError("Expected property name, got \{k}")
            }
          }
          let mut prop_key = key
          let value = if is_ident_key &&
            (prop_key == "get" || prop_key == "set") &&
            not(self.check(Colon)) &&
            not(self.check(LParen)) &&
            not(self.check(Comma)) &&
            not(self.check(RBrace)) {
            let mut acc_computed_key : @ast.TsExpr? = None
            let acc_key = if self.match_(LBracket) {
              let key_expr = self.parse_assignment()
              let _ = self.expect(RBracket)
              // Store the computed key expression for runtime evaluation
              acc_computed_key = Some(key_expr)
              let idx = computed_idx
              computed_idx += 1
              "@@computed:" + idx.to_string()
            } else {
              match self.advance().kind {
                Ident(n) => n
                Str(s) => s
                Int(i) => i.to_string()
                Number(n) => n.to_string()
                Return => "return"
                If => "if"
                Else => "else"
                For => "for"
                While => "while"
                Switch => "switch"
                Case => "case"
                Default => "default"
                With => "with"
                Debugger => "debugger"
                Import => "import"
                Export => "export"
                From => "from"
                As => "as"
                Break => "break"
                Continue => "continue"
                Function => "function"
                Do => "do"
                Try => "try"
                Catch => "catch"
                Finally => "finally"
                Throw => "throw"
                Delete => "delete"
                Yield => "yield"
                Let => "let"
                Const => "const"
                Var => "var"
                New => "new"
                Typeof => "typeof"
                Of => "of"
                In => "in"
                Declare => "declare"
                Interface => "interface"
                Class => "class"
                Instanceof => "instanceof"
                NumberType => "number"
                BooleanType => "boolean"
                StringType => "string"
                VoidType => "void"
                IntType => "int"
                Type => "type"
                Extends => "extends"
                k => raise ParseError("Expected property name, got \{k}")
              }
            }
            let is_getter = prop_key == "get"
            let func_name = acc_key
            prop_key = if is_getter {
              "@@get:" + acc_key
            } else {
              "@@set:" + acc_key
            }
            // Mark that we need to use the computed key
            is_computed_key = acc_computed_key is Some(_)
            computed_key_expr = acc_computed_key
            let _ = self.expect(LParen)
            let params = self.parse_params()
            let _ = self.expect(RParen)
            let return_type = if self.check(Colon) {
              let _ = self.advance()
              self.parse_type()
            } else {
              Any
            }
            let body = self.parse_block()
            @ast.TsExpr::FuncExpr(@ast.TsFunc::{
              name: func_name,
              params,
              return_type,
              body,
              is_generator: false, is_async: false,
            })
          } else if self.match_(Colon) {
            self.parse_assignment()
          } else if is_ident_key && self.match_(Eq) {
            self.parse_assignment()
          } else if self.check(LParen) {
            let _ = self.expect(LParen)
            let params = self.parse_params()
            let _ = self.expect(RParen)
            let return_type = if self.check(Colon) {
              let _ = self.advance()
              self.parse_type()
            } else {
              Any
            }
            let body = self.parse_block()
            @ast.TsExpr::FuncExpr({
              name: prop_key,
              params,
              return_type,
              body,
              is_generator: false, is_async: false,
            })
          } else if is_ident_key && (self.check(Comma) || self.check(RBrace)) {
            Var(prop_key)
          } else {
            raise ParseError("Expected Colon, got \{self.peek().kind}")
          }
          // Wrap computed keys in ComputedProp
          let final_value = match (is_computed_key, computed_key_expr) {
            (true, Some(key_expr)) => @ast.TsExpr::ComputedProp(key_expr, value)
            _ => value
          }
          fields.push((prop_key, final_value))
        }
      }
      let _ = self.expect(RBrace)
      ObjectLit(fields)
    }
    Function => {
      let func = self.parse_function_expr()
      @ast.TsExpr::FuncExpr(func)
    }
    Null => {
      // null literal
      let _ = self.advance()
      NullLit
    }
    _ => raise ParseError("Unexpected token: \{tok.kind}")
  }
}

///|
// / Check if this is an async arrow function
fn Parser::is_async_arrow_function(self : Parser) -> Bool {
  // Check for async identifier => ... (single parameter without parens)
  if self.peek_at(1).kind is Ident(_) {
    // Could be: async x => ...
    // Look for => after the identifier
    return self.peek_at(2).kind == Arrow
  }
  // Check for async (params) => ...
  if self.peek_at(1).kind == LParen {
    // Save position and scan to find matching ) and =>
    let save_pos = self.pos
    let _ = self.advance() // consume 'async'
    let _ = self.advance() // consume '('
    let mut paren_depth = 1
    while paren_depth > 0 && not(self.check(Eof)) {
      match self.peek().kind {
        LParen => paren_depth += 1
        RParen => paren_depth -= 1
        _ => ()
      }
      let _ = self.advance()
    }
    let is_arrow = self.check(Arrow) ||
      (self.check(Colon) && {
        // Skip type annotation: (): ReturnType =>
        while not(self.check(Arrow)) && not(self.check(Eof)) {
          let _ = self.advance()
        }
        self.check(Arrow)
      })
    self.pos = save_pos
    return is_arrow
  }
  false
}

///|
// / Parse async arrow function: async (params) => body or async x => body
fn Parser::parse_async_arrow_function(
  self : Parser,
) -> @ast.TsExpr raise ParseError {
  // Check for single parameter without parens: async x => ...
  if self.peek().kind is Ident(_) && self.peek_at(1).kind == Arrow {
    let name = match self.advance().kind {
      Ident(n) => n
      _ => "<anon>"
    }
    let _ = self.expect(Arrow)
    let prev_async = self.in_async
    self.in_async = true
    let body = if self.check(LBrace) {
      let prev_function = self.in_function
      let prev_iteration = self.in_iteration
      let prev_switch = self.in_switch
      let prev_labels : Array[String] = []
      for label in self.labels {
        prev_labels.push(label)
      }
      self.in_function = true
      self.in_iteration = false
      self.in_switch = false
      while self.labels.length() > 0 {
        let _ = self.labels.pop()
      }
      let block = self.parse_block()
      self.in_function = prev_function
      self.in_iteration = prev_iteration
      self.in_switch = prev_switch
      while self.labels.length() > 0 {
        let _ = self.labels.pop()
      }
      for label in prev_labels {
        self.labels.push(label)
      }
      @ast.TsArrowBody::ArrowBlock(block)
    } else {
      let expr = self.parse_assignment()
      ArrowExpr(expr)
    }
    self.in_async = prev_async
    return ArrowFunc(
      [
        {
          name,
          binding: Some(@ast.TsBinding::Ident(name)),
          is_rest: false,
          type_: Any,
          default: None,
        },
      ],
      body,
      true, // is_async = true
    )
  }

  // Parse with parentheses: async (params) => body
  let _ = self.expect(LParen)
  let params = self.parse_params()
  let _ = self.expect(RParen)
  // Skip optional return type annotation
  if self.check(Colon) {
    let _ = self.advance()
    let _ = self.parse_type()
  }
  let _ = self.expect(Arrow)
  let prev_async = self.in_async
  self.in_async = true
  let body = if self.check(LBrace) {
    let prev_function = self.in_function
    let prev_iteration = self.in_iteration
    let prev_switch = self.in_switch
    let prev_labels : Array[String] = []
    for label in self.labels {
      prev_labels.push(label)
    }
    self.in_function = true
    self.in_iteration = false
    self.in_switch = false
    while self.labels.length() > 0 {
      let _ = self.labels.pop()
    }
    let block = self.parse_block()
    self.in_function = prev_function
    self.in_iteration = prev_iteration
    self.in_switch = prev_switch
    while self.labels.length() > 0 {
      let _ = self.labels.pop()
    }
    for label in prev_labels {
      self.labels.push(label)
    }
    @ast.TsArrowBody::ArrowBlock(block)
  } else {
    let expr = self.parse_assignment()
    ArrowExpr(expr)
  }
  self.in_async = prev_async
  ArrowFunc(params, body, true) // is_async = true
}

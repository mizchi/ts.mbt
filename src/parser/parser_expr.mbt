// ============================================
// expression
// ============================================

///|
// / expression (prefer)
pub fn Parser::parse_expr(self : Parser) -> @ast.TsExpr raise ParseError {
  self.parse_comma()
}

///|
fn Parser::parse_asserted_exponent(
  self : Parser,
  left : @ast.TsExpr,
) -> @ast.TsExpr raise ParseError {
  if self.match_(StarStar) {
    let right = self.parse_exponent()
    BinOp(Pow, left, right)
  } else {
    left
  }
}

///|
fn Parser::consume_trailing_assertions(self : Parser) -> Bool raise ParseError {
  // Consume `as` / `satisfies` chain without wrapping. Returns true when at
  // least one assertion was consumed. Prefer `consume_trailing_assertions_wrap`
  // for the parsed expression form so the assertion survives into the AST.
  let mut had_assertion = false
  while self.match_(As) ||
        self.match_ident("as") ||
        self.match_ident("satisfies") {
    had_assertion = true
    let _ = self.parse_type()
  }
  had_assertion
}

///|
/// Consume trailing `as T` / `satisfies T` assertions and return the
/// wrapped expression (`As(...)` / `Satisfies(...)`). The boolean indicates
/// whether anything was consumed so callers can chain further `as`-aware
/// parsing if needed.
fn Parser::consume_trailing_assertions_wrap(
  self : Parser,
  left : @ast.TsExpr,
) -> (Bool, @ast.TsExpr) raise ParseError {
  let mut wrapped = left
  let mut had = false
  while true {
    let is_as = if self.match_(As) || self.match_ident("as") {
      Some(true)
    } else if self.match_ident("satisfies") {
      Some(false)
    } else {
      None
    }
    match is_as {
      Some(true) => {
        had = true
        // `as const` is a const assertion — it freezes the operand's
        // inferred type but leaves the runtime value untouched. Downstream
        // passes (const-value collection, value lowering) expect the raw
        // expression, so do not wrap with `As(...)` in this case.
        if self.check(Const) {
          let _ = self.advance()
        } else {
          let ty = self.parse_type()
          wrapped = @ast.TsExpr::As(wrapped, ty)
        }
      }
      Some(false) => {
        had = true
        let ty = self.parse_type()
        wrapped = @ast.TsExpr::Satisfies(wrapped, ty)
      }
      None => break
    }
  }
  (had, wrapped)
}

///|
fn Parser::parse_asserted_multiplicative(
  self : Parser,
  left : @ast.TsExpr,
) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_asserted_exponent(left)
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
fn Parser::parse_asserted_additive(
  self : Parser,
  left : @ast.TsExpr,
) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_asserted_multiplicative(left)
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
fn Parser::parse_asserted_shift(
  self : Parser,
  left : @ast.TsExpr,
) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_asserted_additive(left)
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
fn Parser::parse_asserted_comparison(
  self : Parser,
  left : @ast.TsExpr,
) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_asserted_shift(left)
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
fn Parser::parse_asserted_equality(
  self : Parser,
  left : @ast.TsExpr,
) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_asserted_comparison(left)
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
fn Parser::parse_asserted_bit_and(
  self : Parser,
  left : @ast.TsExpr,
) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_asserted_equality(left)
  while self.match_(Amp) {
    let right = self.parse_equality()
    left = BinOp(BitAnd, left, right)
  }
  left
}

///|
fn Parser::parse_asserted_bit_xor(
  self : Parser,
  left : @ast.TsExpr,
) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_asserted_bit_and(left)
  while self.match_(Caret) {
    let right = self.parse_bit_and()
    left = BinOp(BitXor, left, right)
  }
  left
}

///|
fn Parser::parse_asserted_bit_or(
  self : Parser,
  left : @ast.TsExpr,
) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_asserted_bit_xor(left)
  while self.match_(Pipe) {
    let right = self.parse_bit_xor()
    left = BinOp(BitOr, left, right)
  }
  left
}

///|
fn Parser::parse_asserted_and(
  self : Parser,
  left : @ast.TsExpr,
) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_asserted_bit_or(left)
  while self.match_(AmpAmp) {
    let right = self.parse_bit_or()
    left = BinOp(And, left, right)
  }
  left
}

///|
fn Parser::parse_asserted_or(
  self : Parser,
  left : @ast.TsExpr,
) -> @ast.TsExpr raise ParseError {
  let mut left = self.parse_asserted_and(left)
  while self.check(PipePipe) || self.check(QuestionQuestion) {
    if self.match_(PipePipe) {
      let right = self.parse_and()
      let (had, wrapped) = self.consume_trailing_assertions_wrap(right)
      let right = if had { self.parse_asserted_and(wrapped) } else { wrapped }
      left = BinOp(Or, left, right)
    } else if self.match_(QuestionQuestion) {
      let right = self.parse_and()
      let (had, wrapped) = self.consume_trailing_assertions_wrap(right)
      let right = if had { self.parse_asserted_and(wrapped) } else { wrapped }
      left = BinOp(Coalesce, left, right)
    }
  }
  left
}

///|
fn Parser::parse_asserted_ternary(
  self : Parser,
  left : @ast.TsExpr,
) -> @ast.TsExpr raise ParseError {
  let cond = self.parse_asserted_or(left)
  if self.match_(Question) {
    let then_expr = self.parse_assignment()
    let _ = self.expect(Colon)
    let else_expr = self.parse_assignment()
    Cond(cond, then_expr, else_expr)
  } else {
    cond
  }
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
  let left0 = self.parse_ternary()
  let (had_assertion, wrapped) = self.consume_trailing_assertions_wrap(left0)
  let left = if had_assertion {
    self.parse_asserted_ternary(wrapped)
  } else {
    wrapped
  }
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
fn Parser::parse_object_method_value(
  self : Parser,
  name : String,
  is_generator : Bool,
  is_async : Bool,
) -> @ast.TsExpr raise ParseError {
  self.skip_type_params()
  let _ = self.expect(LParen)
  let params = self.parse_params()
  let _ = self.expect(RParen)
  let return_type = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any
  }
  let prev_generator = self.in_generator
  let prev_function = self.in_function
  let prev_async = self.in_async
  if is_generator {
    self.in_generator = true
  }
  self.in_function = true
  self.in_async = is_async
  let body = self.parse_block()
  self.in_generator = prev_generator
  self.in_function = prev_function
  self.in_async = prev_async
  @ast.TsExpr::FuncExpr({
    name,
    params,
    return_type,
    body,
    is_generator,
    is_async,
  })
}

///|
fn Parser::parse_object_member_name(
  self : Parser,
  computed_idx : Int,
) -> (String, Bool, @ast.TsExpr?, Int) raise ParseError {
  if self.match_(LBracket) {
    let key_expr = self.parse_assignment()
    let _ = self.expect(RBracket)
    return (
      "@@computed:" + computed_idx.to_string(),
      true,
      Some(key_expr),
      computed_idx + 1,
    )
  }
  match self.peek().kind {
    Str(s) => {
      let _ = self.advance()
      (s, false, None, computed_idx)
    }
    Int(i) => {
      let _ = self.advance()
      (i.to_string(), false, None, computed_idx)
    }
    Number(n) => {
      let _ = self.advance()
      (n.to_string(), false, None, computed_idx)
    }
    _ => (self.parse_binding_ident(), false, None, computed_idx)
  }
}

///|
fn Parser::parse_property_name_token(self : Parser) -> String raise ParseError {
  match self.advance().kind {
    Ident(name) => name
    PrivateIdent(name) => {
      let private_name = "#" + name
      match self.current_class_brand {
        Some(brand) => mangle_private_name(private_name, brand)
        None => private_name
      }
    }
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
    Bool(true) => "true"
    Bool(false) => "false"
    Null => "null"
    k => raise ParseError("Expected property name, got \{k}")
  }
}

///|
fn Parser::parse_single_param_arrow(
  self : Parser,
  name : String,
) -> @ast.TsExpr raise ParseError {
  let _ = self.expect(Arrow)
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
    let then_expr = self.parse_assignment()
    let _ = self.expect(Colon)
    let else_expr = self.parse_assignment()
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
  } else if self.match_(Tilde) {
    let operand = self.parse_unary()
    UnaryOp(BitwiseNot, operand)
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
        // yield takes AssignmentExpression as operand (ES6 14.4)
        // Check for end of yield expression
        let expr = if self.check(Semicolon) ||
          self.check(Comma) ||
          self.check(RParen) ||
          self.check(RBracket) ||
          self.check(RBrace) ||
          self.check(Colon) ||
          self.check(Eof) {
          None
        } else {
          Some(self.parse_assignment())
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
// ES spec: ++ and -- are NOT postfix operators if they appear on a new line
fn Parser::parse_postfix(self : Parser) -> @ast.TsExpr raise ParseError {
  let mut expr = self.parse_call()
  while true {
    let tok = self.peek()
    // ASI: If ++ or -- appears after a line terminator, it's NOT a postfix operator
    if tok.has_newline_before {
      break
    }
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
fn is_instantiation_expr_target(expr : @ast.TsExpr) -> Bool {
  let is_upper_initial = fn(name : String) -> Bool {
    if name.length() == 0 {
      return false
    }
    let c = name[0].to_int().unsafe_to_char()
    c >= 'A' && c <= 'Z'
  }
  match expr {
    Var(name) => is_upper_initial(name)
    PropAccess(_, prop) => is_upper_initial(prop)
    _ => false
  }
}

///|
fn Parser::try_skip_call_type_args(self : Parser, expr : @ast.TsExpr) -> Bool {
  if !self.check(Lt) {
    return false
  }
  let saved_pos = self.pos
  self.skip_type_args()
  if self.check(LParen) {
    return true
  }
  if is_instantiation_expr_target(expr) &&
    (
      self.check(Comma) ||
      self.check(Comma) ||
      self.check(RParen) ||
      self.check(RBracket) ||
      self.check(RBrace) ||
      self.check(Semicolon) ||
      self.check(Colon) ||
      self.check(Dot) ||
      self.check(Question) ||
      self.check(Eof)
    ) {
    return true
  }
  self.pos = saved_pos
  false
}

///|
fn Parser::parse_parenthesized_expr(
  self : Parser,
) -> @ast.TsExpr raise ParseError {
  if self.peek_at(1).kind == Lt {
    let temp = { ..self, pos: self.pos + 1 }
    if temp.is_jsx_element_start() {
      temp.skip_jsx_element()
      if temp.check(RParen) {
        self.pos = temp.pos + 1
        return Var("__jsx__")
      }
    }
  }
  let start = self.pos
  let mut depth = 1
  let mut end_idx = -1
  let mut i = start + 1
  while i < self.tokens.length() {
    match self.tokens[i].kind {
      LParen => depth += 1
      RParen => {
        depth -= 1
        if depth == 0 {
          end_idx = i
          break
        }
      }
      Eof => break
      _ => ()
    }
    i += 1
  }
  if end_idx < 0 {
    raise ParseError("Expected RParen, got Eof")
  }

  let inner_tokens : Array[Token] = []
  for i in (start + 1)..<end_idx {
    inner_tokens.push(self.tokens[i])
  }
  inner_tokens.push({
    kind: Eof,
    pos: self.tokens[end_idx].pos,
    has_newline_before: false,
  })

  let temp = {
    ..Parser::new_with_strict_and_jsx(
      inner_tokens,
      self.in_strict,
      self.allow_jsx,
    ),
    src: self.src,
  }
  temp.in_generator = self.in_generator
  temp.in_async = self.in_async
  temp.in_function = self.in_function
  temp.in_iteration = self.in_iteration
  temp.in_switch = self.in_switch
  temp.class_id = self.class_id
  temp.current_class_brand = self.current_class_brand
  for label in self.labels {
    temp.labels.push(label)
  }

  let expr = temp.parse_expr()
  if !temp.check(Eof) {
    raise ParseError("Expected RParen, got \{temp.peek().kind}")
  }
  self.pos = end_idx + 1
  expr
}

///|
fn Parser::parse_expr_until_top_level(
  self : Parser,
  terminator : TokenKind,
) -> @ast.TsExpr raise ParseError {
  let start = self.pos
  let mut paren_depth = 0
  let mut brace_depth = 0
  let mut bracket_depth = 0
  let mut end_idx = -1
  let mut i = start
  while i < self.tokens.length() {
    let tok = self.tokens[i]
    match tok.kind {
      Eof => break
      k if k == terminator &&
        paren_depth == 0 &&
        brace_depth == 0 &&
        bracket_depth == 0 => {
        end_idx = i
        break
      }
      LParen => paren_depth += 1
      RParen => if paren_depth > 0 { paren_depth -= 1 }
      LBrace => brace_depth += 1
      RBrace => if brace_depth > 0 { brace_depth -= 1 }
      LBracket => bracket_depth += 1
      RBracket => if bracket_depth > 0 { bracket_depth -= 1 }
      _ => ()
    }
    i += 1
  }
  if end_idx < 0 {
    raise ParseError("Expected \{terminator}, got Eof")
  }

  let inner_tokens : Array[Token] = []
  for i in start..<end_idx {
    inner_tokens.push(self.tokens[i])
  }
  inner_tokens.push({
    kind: Eof,
    pos: self.tokens[end_idx].pos,
    has_newline_before: false,
  })

  let temp = {
    ..Parser::new_with_strict_and_jsx(
      inner_tokens,
      self.in_strict,
      self.allow_jsx,
    ),
    src: self.src,
  }
  temp.in_generator = self.in_generator
  temp.in_async = self.in_async
  temp.in_function = self.in_function
  temp.in_iteration = self.in_iteration
  temp.in_switch = self.in_switch
  temp.class_id = self.class_id
  temp.current_class_brand = self.current_class_brand
  for label in self.labels {
    temp.labels.push(label)
  }

  let expr = temp.parse_expr()
  if !temp.check(Eof) {
    raise ParseError("Expected \{terminator}, got \{temp.peek().kind}")
  }
  self.pos = end_idx
  expr
}

///|
fn Parser::is_jsx_element_start(self : Parser) -> Bool {
  if !self.check(Lt) {
    return false
  }
  match self.peek_at(1).kind {
    Ident(_) | Gt => true
    _ => false
  }
}

///|
fn Parser::skip_braced_tokens(self : Parser) -> Unit {
  if !self.check(LBrace) {
    return
  }
  let _ = self.advance()
  let mut depth = 1
  while depth > 0 && !self.check(Eof) {
    match self.peek().kind {
      LBrace => {
        depth += 1
        let _ = self.advance()
      }
      RBrace => {
        depth -= 1
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
fn Parser::skip_jsx_element_tokens(self : Parser) -> Unit {
  let mut depth = 0
  while !self.check(Eof) {
    if self.check(LBrace) {
      self.skip_braced_tokens()
      continue
    }
    if self.check(Lt) {
      let _ = self.advance()
      if self.match_(Slash) {
        while !self.check(Eof) && !self.check(Gt) {
          if self.check(LBrace) {
            self.skip_braced_tokens()
          } else {
            let _ = self.advance()
          }
        }
        let _ = self.match_(Gt)
        if depth > 0 {
          depth -= 1
        }
        if depth == 0 {
          break
        }
        continue
      }
      if self.match_(Gt) {
        depth += 1
        continue
      }
      depth += 1
      while !self.check(Eof) {
        if self.check(LBrace) {
          self.skip_braced_tokens()
        } else if self.check(Slash) && self.peek_at(1).kind == Gt {
          let _ = self.advance()
          let _ = self.advance()
          depth -= 1
          break
        } else if self.match_(Gt) {
          break
        } else {
          let _ = self.advance()
        }
      }
      if depth == 0 {
        break
      }
      continue
    }
    let _ = self.advance()
  }
}

///|
fn Parser::advance_to_source_pos(self : Parser, source_pos : Int) -> Unit {
  while self.pos < self.tokens.length() &&
        self.tokens[self.pos].pos < source_pos {
    self.pos += 1
  }
}

///|
fn Parser::scan_type_assertion_source_end(
  self : Parser,
  start : Int,
) -> Int raise ParseError {
  let mut i = start
  let mut depth = 0
  while i < self.src.length() {
    let ch = self.src[i].to_int().unsafe_to_char()
    if ch == '/' &&
      i + 1 < self.src.length() &&
      self.src[i + 1].to_int().unsafe_to_char() == '/' {
      i = self.skip_source_line_comment(i)
      continue
    } else if ch == '/' &&
      i + 1 < self.src.length() &&
      self.src[i + 1].to_int().unsafe_to_char() == '*' {
      i = self.skip_source_block_comment(i)
      continue
    } else if ch == '"' ||
      ch == '`' ||
      (ch == '\'' && !self.is_source_word_apostrophe(i)) {
      let quote = ch
      i += 1
      while i < self.src.length() {
        let inner = self.src[i].to_int().unsafe_to_char()
        if inner == '\\' {
          i += 2
          continue
        }
        if inner == quote {
          break
        }
        i += 1
      }
    } else if ch == '<' {
      depth += 1
    } else if ch == '>' {
      let is_arrow_close = i > 0 &&
        self.src[i - 1].to_int().unsafe_to_char() == '='
      if !is_arrow_close {
        depth -= 1
        if depth == 0 {
          return i + 1
        }
      }
    }
    i += 1
  }
  raise ParseError("Unterminated type assertion")
}

///|
fn Parser::scan_jsx_source_end(self : Parser, start : Int) -> Int {
  let mut i = start
  let mut depth = 0
  while i < self.src.length() {
    let c = self.src[i].to_int().unsafe_to_char()
    if c == '{' {
      i = self.skip_jsx_braces_in_source(i)
      continue
    }
    if c != '<' {
      i += 1
      continue
    }
    if i + 2 < self.src.length() &&
      self.src[i + 1].to_int().unsafe_to_char() == '/' &&
      self.src[i + 2].to_int().unsafe_to_char() == '>' {
      i += 3
      if depth > 0 {
        depth -= 1
      }
      if depth == 0 {
        break
      }
      continue
    }
    if i + 1 < self.src.length() &&
      self.src[i + 1].to_int().unsafe_to_char() == '>' {
      depth += 1
      i += 2
      continue
    }
    if i + 1 < self.src.length() &&
      self.src[i + 1].to_int().unsafe_to_char() == '/' {
      i += 2
      while i < self.src.length() &&
            self.src[i].to_int().unsafe_to_char() != '>' {
        i += 1
      }
      if i < self.src.length() {
        i += 1
      }
      if depth > 0 {
        depth -= 1
      }
      if depth == 0 {
        break
      }
      continue
    }

    depth += 1
    i += 1
    let mut quote : Char? = None
    while i < self.src.length() {
      let inner = self.src[i].to_int().unsafe_to_char()
      match quote {
        Some(q) => {
          if inner == '\\' {
            i += 2
            continue
          }
          if inner == q {
            quote = None
          }
          i += 1
        }
        None =>
          if inner == '"' || inner == '\'' || inner == '`' {
            quote = Some(inner)
            i += 1
          } else if inner == '{' {
            i = self.skip_jsx_braces_in_source(i)
          } else if inner == '/' &&
            i + 1 < self.src.length() &&
            self.src[i + 1].to_int().unsafe_to_char() == '>' {
            i += 2
            depth -= 1
            break
          } else if inner == '>' {
            i += 1
            break
          } else {
            i += 1
          }
      }
    }
    if depth == 0 {
      break
    }
  }
  i
}

///|
fn Parser::try_skip_parenthesized_jsx_expr(self : Parser) -> Bool {
  if self.src.length() == 0 || !self.check(LParen) {
    return false
  }
  let mut i = self.peek().pos + 1
  while i < self.src.length() {
    let c = self.src[i].to_int().unsafe_to_char()
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      i += 1
    } else {
      break
    }
  }
  if i >= self.src.length() || self.src[i].to_int().unsafe_to_char() != '<' {
    return false
  }
  let jsx_end = self.scan_jsx_source_end(i)
  let mut j = jsx_end
  while j < self.src.length() {
    let c = self.src[j].to_int().unsafe_to_char()
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      j += 1
    } else {
      break
    }
  }
  if j < self.src.length() && self.src[j].to_int().unsafe_to_char() == ')' {
    self.advance_to_source_pos(j + 1)
    return true
  }
  false
}

///|
fn Parser::is_source_word_char(_self : Parser, c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
fn Parser::is_source_word_apostrophe(self : Parser, idx : Int) -> Bool {
  if idx <= 0 || idx + 1 >= self.src.length() {
    return false
  }
  let prev = self.src[idx - 1].to_int().unsafe_to_char()
  let next = self.src[idx + 1].to_int().unsafe_to_char()
  self.is_source_word_char(prev) && self.is_source_word_char(next)
}

///|
fn Parser::skip_source_line_comment(self : Parser, idx : Int) -> Int {
  let mut i = idx + 2
  while i < self.src.length() {
    let c = self.src[i].to_int().unsafe_to_char()
    i += 1
    if c == '\n' || c == '\r' {
      break
    }
  }
  i
}

///|
fn Parser::skip_source_block_comment(self : Parser, idx : Int) -> Int {
  let mut i = idx + 2
  while i + 1 < self.src.length() {
    if self.src[i].to_int().unsafe_to_char() == '*' &&
      self.src[i + 1].to_int().unsafe_to_char() == '/' {
      return i + 2
    }
    i += 1
  }
  self.src.length()
}

///|
fn Parser::skip_jsx_braces_in_source(self : Parser, idx : Int) -> Int {
  let mut i = idx + 1
  let mut depth = 1
  let mut quote : Char? = None
  while i < self.src.length() && depth > 0 {
    let c = self.src[i].to_int().unsafe_to_char()
    match quote {
      Some(q) => {
        if c == '\\' {
          i += 2
          continue
        }
        if c == q {
          quote = None
        }
        i += 1
      }
      None =>
        if c == '/' &&
          i + 1 < self.src.length() &&
          self.src[i + 1].to_int().unsafe_to_char() == '/' {
          i = self.skip_source_line_comment(i)
        } else if c == '/' &&
          i + 1 < self.src.length() &&
          self.src[i + 1].to_int().unsafe_to_char() == '*' {
          i = self.skip_source_block_comment(i)
        } else if c == '"' ||
          c == '`' ||
          (c == '\'' && !self.is_source_word_apostrophe(i)) {
          quote = Some(c)
          i += 1
        } else if c == '{' {
          depth += 1
          i += 1
        } else if c == '}' {
          depth -= 1
          i += 1
        } else {
          i += 1
        }
    }
  }
  i
}

///|
fn Parser::skip_jsx_element(self : Parser) -> Unit {
  if self.src.length() == 0 {
    self.skip_jsx_element_tokens()
    return
  }
  let i = self.scan_jsx_source_end(self.peek().pos)
  self.advance_to_source_pos(i)
}

///|
// / function, array, property, method
fn Parser::parse_call(self : Parser) -> @ast.TsExpr raise ParseError {
  let mut expr = self.parse_primary()
  // Track whether this chain saw any `?.` so we can wrap the outermost
  // result in `OptionalChain(...)` for the checker to widen with
  // `undefined`. The exact position of `?` is lost; what matters for
  // narrowing is that the chain may short-circuit.
  let mut saw_optional_chain = false

  // operatorcheck
  while true {
    if self.match_(Bang) {
      // `x!` — non-null assertion. Wrap so the checker can strip
      // null / undefined at the use site.
      expr = @ast.TsExpr::NonNull(expr)
      continue
    }
    if self.try_skip_call_type_args(expr) {
      continue
    }
    if self.check(Question) && self.peek_at(1).kind == Dot {
      let _ = self.advance()
      let _ = self.advance()
      saw_optional_chain = true
      if self.try_skip_call_type_args(expr) {
        continue
      }
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
          let prop = self.parse_property_name_token()
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
      let prop = self.parse_property_name_token()
      expr = PropAccess(expr, prop)
    } else {
      // Check for tagged template literal
      match self.peek().kind {
        Template(cooked_parts, raw_parts, expr_sources) => {
          let _ = self.advance()
          // Parse expression sources into AST expressions
          let exprs : Array[@ast.TsExpr] = []
          for src in expr_sources {
            let sub_parser = Parser::from_source(src)
            let sub_expr = sub_parser.parse_expr()
            exprs.push(sub_expr)
          }
          // Create tagged template expression
          expr = @ast.TsExpr::TaggedTemplate(
            expr, cooked_parts, raw_parts, exprs,
          )
        }
        _ => break
      }
    }
  }
  if saw_optional_chain {
    @ast.TsExpr::OptionalChain(expr)
  } else {
    expr
  }
}

///|
// / argument
fn Parser::parse_args(self : Parser) -> Array[@ast.TsExpr] raise ParseError {
  let args : Array[@ast.TsExpr] = []
  if !self.check(RParen) {
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
fn Parser::is_generic_arrow_function(self : Parser) -> Bool {
  if !self.check(Lt) {
    return false
  }
  let temp = { ..self }
  temp.skip_type_args()
  if !temp.check(LParen) {
    return false
  }
  temp.is_arrow_function()
}

///|
fn Parser::parse_generic_arrow_function(
  self : Parser,
) -> @ast.TsExpr raise ParseError {
  self.skip_type_args()
  let _ = self.expect(LParen)
  let params = self.parse_params()
  let _ = self.expect(RParen)
  if self.check(Colon) {
    let _ = self.advance()
    self.skip_type_until_arrow()
  }
  let _ = self.expect(Arrow)
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
  ArrowFunc(params, body, false)
}

///|
fn Parser::parse_angle_bracket_type_assertion(
  self : Parser,
) -> @ast.TsExpr raise ParseError {
  if self.src == "" {
    return self.parse_angle_bracket_type_assertion_with_tokens()
  }
  let saved_pos = self.pos
  self.parse_angle_bracket_type_assertion_with_tokens() catch {
    _ => {
      self.pos = saved_pos
      self.parse_angle_bracket_type_assertion_from_source()
    }
  }
}

///|
fn Parser::parse_angle_bracket_type_assertion_from_source(
  self : Parser,
) -> @ast.TsExpr raise ParseError {
  let start_pos = self.peek().pos
  let end_pos = self.scan_type_assertion_source_end(start_pos)
  let type_start = start_pos + 1
  let type_end = if end_pos - 1 <= self.src.length() {
    end_pos - 1
  } else {
    self.src.length()
  }
  if type_start > self.src.length() {
    raise ParseError("Expected Gt, got \{self.peek().kind}")
  }
  if type_end < type_start {
    raise ParseError("Expected Gt, got \{self.peek().kind}")
  }
  let type_src = self.src[type_start:type_end].to_string()
  let type_parser = Parser::from_source_with_jsx(type_src, false)
  let _ = type_parser.parse_type()
  self.advance_to_source_pos(end_pos)
  self.parse_unary()
}

///|
fn Parser::parse_angle_bracket_type_assertion_with_tokens(
  self : Parser,
) -> @ast.TsExpr raise ParseError {
  let _ = self.expect(Lt)
  let _ = self.parse_type()
  if !self.match_(Gt) {
    let prev_kind = if self.pos > 0 {
      self.tokens[self.pos - 1].kind
    } else {
      Eof
    }
    match prev_kind {
      GtGt | GtGtGt => ()
      _ => raise ParseError("Expected Gt, got \{self.peek().kind}")
    }
  }
  self.parse_unary()
}

///|
// / expression (literal, variable, , array, new)
fn Parser::parse_primary(self : Parser) -> @ast.TsExpr raise ParseError {
  let tok = self.peek()
  match tok.kind {
    Class => self.parse_class_stub()
    Lt =>
      if self.is_generic_arrow_function() {
        self.parse_generic_arrow_function()
      } else if !self.allow_jsx {
        self.parse_angle_bracket_type_assertion()
      } else if self.is_jsx_element_start() {
        self.skip_jsx_element()
        Var("__jsx__")
      } else {
        raise ParseError("Unexpected token: Lt")
      }
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
        raise ParseError("Octal literals are not allowed in strict mode")
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
    NumberType =>
      if self.peek_at(1).kind == Arrow {
        let _ = self.advance()
        self.parse_single_param_arrow("number")
      } else {
        let _ = self.advance()
        Var("number")
      }
    BooleanType =>
      if self.peek_at(1).kind == Arrow {
        let _ = self.advance()
        self.parse_single_param_arrow("boolean")
      } else {
        let _ = self.advance()
        Var("boolean")
      }
    StringType =>
      if self.peek_at(1).kind == Arrow {
        let _ = self.advance()
        self.parse_single_param_arrow("string")
      } else {
        let _ = self.advance()
        Var("string")
      }
    VoidType =>
      if self.peek_at(1).kind == Arrow {
        let _ = self.advance()
        self.parse_single_param_arrow("void")
      } else {
        let _ = self.advance()
        Var("void")
      }
    IntType =>
      if self.peek_at(1).kind == Arrow {
        let _ = self.advance()
        self.parse_single_param_arrow("int")
      } else {
        let _ = self.advance()
        Var("int")
      }
    Type =>
      if self.peek_at(1).kind == Arrow {
        let _ = self.advance()
        self.parse_single_param_arrow("type")
      } else {
        let _ = self.advance()
        Var("type")
      }
    From =>
      if self.peek_at(1).kind == Arrow {
        let _ = self.advance()
        self.parse_single_param_arrow("from")
      } else {
        let _ = self.advance()
        Var("from")
      }
    Of =>
      if self.peek_at(1).kind == Arrow {
        let _ = self.advance()
        self.parse_single_param_arrow("of")
      } else {
        let _ = self.advance()
        Var("of")
      }
    In =>
      if self.peek_at(1).kind == Arrow {
        let _ = self.advance()
        self.parse_single_param_arrow("in")
      } else {
        let _ = self.advance()
        Var("in")
      }
    Delete =>
      if self.peek_at(1).kind == Arrow {
        let _ = self.advance()
        self.parse_single_param_arrow("delete")
      } else {
        let _ = self.advance()
        Var("delete")
      }
    Debugger =>
      if self.peek_at(1).kind == Arrow {
        let _ = self.advance()
        self.parse_single_param_arrow("debugger")
      } else {
        let _ = self.advance()
        Var("debugger")
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
    Template(cooked_parts, _, expr_sources) => {
      let _ = self.advance()
      // Parse expression sources into AST expressions
      let exprs : Array[@ast.TsExpr] = []
      for src in expr_sources {
        let sub_parser = Parser::from_source(src)
        let expr = sub_parser.parse_expr()
        exprs.push(expr)
      }
      // For untagged template literals, convert to TemplateLiteral AST node
      @ast.TsExpr::TemplateLiteral(cooked_parts, exprs)
    }
    Ident(name) =>
      if name == "async" &&
        self.peek_at(1).kind == Function &&
        !self.has_line_terminator_after() {
        let _ = self.advance()
        self.in_async = true
        let func = self.parse_function_expr()
        self.in_async = false
        @ast.TsExpr::FuncExpr(func)
      } else if name == "async" &&
        self.peek_at(1).kind == Lt &&
        !self.has_line_terminator_after() &&
        self.is_async_arrow_function() {
        let _ = self.advance()
        self.parse_async_arrow_function()
      } else if name == "async" &&
        !self.has_line_terminator_after() &&
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
    As => {
      let _ = self.advance()
      Var("as")
    }
    PrivateIdent(name) => {
      let _ = self.advance()
      let private_name = "#" + name
      let mangled = match self.current_class_brand {
        Some(brand) => mangle_private_name(private_name, brand)
        None => private_name
      }
      Var(mangled)
    }
    LParen =>
      if self.try_skip_parenthesized_jsx_expr() {
        Var("__jsx__")
        // functioncheck
      } else if self.peek_at(1).kind == Lt {
        let temp = { ..self, pos: self.pos + 1 }
        if temp.is_jsx_element_start() {
          temp.skip_jsx_element()
          if temp.check(RParen) {
            self.pos = temp.pos + 1
            Var("__jsx__")
          } else if self.is_arrow_function() {
            // function: (params) => body
            let _ = self.advance() // (
            let params = self.parse_params()
            let _ = self.expect(RParen)
            if self.check(Colon) {
              let _ = self.advance()
              self.skip_type_until_arrow()
            }
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
            self.parse_parenthesized_expr()
          }
        } else if self.is_arrow_function() {
          // function: (params) => body
          let _ = self.advance() // (
          let params = self.parse_params()
          let _ = self.expect(RParen)
          if self.check(Colon) {
            let _ = self.advance()
            self.skip_type_until_arrow()
          }
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
          self.parse_parenthesized_expr()
        }
      } else if self.is_arrow_function() {
        // function: (params) => body
        let _ = self.advance() // (
        let params = self.parse_params()
        let _ = self.expect(RParen)
        if self.check(Colon) {
          let _ = self.advance()
          self.skip_type_until_arrow()
        }
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
        self.parse_parenthesized_expr()
      }
    LBracket => {
      // arrayliteral: [1, 2, 3]
      let _ = self.advance()
      let elements : Array[@ast.TsExpr] = []
      while !self.check(RBracket) {
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
        let prop = self.parse_property_name_token()
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
              PrivateIdent(name) => {
                let private_name = "#" + name
                match self.current_class_brand {
                  Some(brand) => mangle_private_name(private_name, brand)
                  None => private_name
                }
              }
              // Allow reserved words as property names (e.g., Symbol.for)
              For => "for"
              Return => "return"
              If => "if"
              Else => "else"
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
              k => raise ParseError("Expected identifier after '.', got \{k}")
            }
            type_name = type_name + "." + part
            expr = PropAccess(expr, part)
          }
          callee_expr = Some(expr)
          // typeparameter (simpleimplementation)
          if self.check(Lt) {
            self.skip_type_args()
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
      if !self.check(RBrace) {
        if self.match_ellipsis() {
          let spread_expr = self.parse_assignment()
          fields.push(("@@spread:" + spread_idx.to_string(), spread_expr))
          spread_idx += 1
        } else {
          // field
          let mut is_ident_key = false
          let mut is_shorthand_key = false
          let mut is_computed_key = false
          let mut computed_key_expr : @ast.TsExpr? = None
          let is_generator = self.match_(Star)
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
                is_shorthand_key = true
                n
              }
              Str(s) => s
              Int(i) => i.to_string()
              Number(n) => n.to_string()
              Yield => {
                is_shorthand_key = true
                "yield"
              }
              Return => {
                is_shorthand_key = true
                "return"
              }
              If => {
                is_shorthand_key = true
                "if"
              }
              Else => {
                is_shorthand_key = true
                "else"
              }
              For => {
                is_shorthand_key = true
                "for"
              }
              While => {
                is_shorthand_key = true
                "while"
              }
              Switch => {
                is_shorthand_key = true
                "switch"
              }
              Case => {
                is_shorthand_key = true
                "case"
              }
              Default => {
                is_shorthand_key = true
                "default"
              }
              With => {
                is_shorthand_key = true
                "with"
              }
              Debugger => {
                is_shorthand_key = true
                "debugger"
              }
              Import => {
                is_shorthand_key = true
                "import"
              }
              Export => {
                is_shorthand_key = true
                "export"
              }
              From => {
                is_shorthand_key = true
                "from"
              }
              As => {
                is_shorthand_key = true
                "as"
              }
              Break => {
                is_shorthand_key = true
                "break"
              }
              Continue => {
                is_shorthand_key = true
                "continue"
              }
              Function => {
                is_shorthand_key = true
                "function"
              }
              Do => {
                is_shorthand_key = true
                "do"
              }
              Try => {
                is_shorthand_key = true
                "try"
              }
              Catch => {
                is_shorthand_key = true
                "catch"
              }
              Finally => {
                is_shorthand_key = true
                "finally"
              }
              Throw => {
                is_shorthand_key = true
                "throw"
              }
              Delete => {
                is_shorthand_key = true
                "delete"
              }
              Let => {
                is_shorthand_key = true
                "let"
              }
              Const => {
                is_shorthand_key = true
                "const"
              }
              Var => {
                is_shorthand_key = true
                "var"
              }
              New => {
                is_shorthand_key = true
                "new"
              }
              Typeof => {
                is_shorthand_key = true
                "typeof"
              }
              Of => {
                is_shorthand_key = true
                "of"
              }
              In => {
                is_shorthand_key = true
                "in"
              }
              Declare => {
                is_shorthand_key = true
                "declare"
              }
              Interface => {
                is_shorthand_key = true
                "interface"
              }
              Class => {
                is_shorthand_key = true
                "class"
              }
              Instanceof => {
                is_shorthand_key = true
                "instanceof"
              }
              NumberType => {
                is_shorthand_key = true
                "number"
              }
              BooleanType => {
                is_shorthand_key = true
                "boolean"
              }
              StringType => {
                is_shorthand_key = true
                "string"
              }
              VoidType => {
                is_shorthand_key = true
                "void"
              }
              IntType => {
                is_shorthand_key = true
                "int"
              }
              Bool(true) => {
                is_shorthand_key = true
                "true"
              }
              Bool(false) => {
                is_shorthand_key = true
                "false"
              }
              Null => {
                is_shorthand_key = true
                "null"
              }
              Type => {
                is_shorthand_key = true
                "type"
              }
              Extends => {
                is_shorthand_key = true
                "extends"
              }
              k => raise ParseError("Expected property name, got \{k}")
            }
          }
          let mut prop_key = key
          let value = if is_ident_key &&
            (prop_key == "get" || prop_key == "set") &&
            !self.check(Colon) &&
            !self.check(LParen) &&
            !self.check(Lt) &&
            !self.check(Comma) &&
            !self.check(RBrace) {
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
            let prev_function = self.in_function
            self.in_function = true
            let body = self.parse_block()
            self.in_function = prev_function
            @ast.TsExpr::FuncExpr(@ast.TsFunc::{
              name: func_name,
              params,
              return_type,
              body,
              is_generator: false,
              is_async: false,
            })
          } else if is_ident_key &&
            prop_key == "async" &&
            !self.check(Colon) &&
            !self.check(Comma) &&
            !self.check(RBrace) {
            let async_is_generator = self.match_(Star)
            let (
              async_name,
              async_is_computed,
              async_computed_expr,
              next_computed_idx,
            ) = self.parse_object_member_name(computed_idx)
            prop_key = async_name
            is_computed_key = async_is_computed
            computed_key_expr = async_computed_expr
            computed_idx = next_computed_idx
            self.parse_object_method_value(prop_key, async_is_generator, true)
          } else if self.match_(Colon) {
            self.parse_assignment()
          } else if is_ident_key && self.match_(Eq) {
            self.parse_assignment()
          } else if self.check(LParen) || self.check(Lt) {
            self.parse_object_method_value(prop_key, is_generator, false)
          } else if is_shorthand_key &&
            (self.check(Comma) || self.check(RBrace)) {
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
          let mut is_shorthand_key = false
          let mut is_computed_key = false
          let mut computed_key_expr : @ast.TsExpr? = None
          let is_generator = self.match_(Star)
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
                is_shorthand_key = true
                n
              }
              Str(s) => s
              Int(i) => i.to_string()
              Number(n) => n.to_string()
              Return => {
                is_shorthand_key = true
                "return"
              }
              If => {
                is_shorthand_key = true
                "if"
              }
              Else => {
                is_shorthand_key = true
                "else"
              }
              For => {
                is_shorthand_key = true
                "for"
              }
              While => {
                is_shorthand_key = true
                "while"
              }
              Switch => {
                is_shorthand_key = true
                "switch"
              }
              Case => {
                is_shorthand_key = true
                "case"
              }
              Default => {
                is_shorthand_key = true
                "default"
              }
              With => {
                is_shorthand_key = true
                "with"
              }
              Debugger => {
                is_shorthand_key = true
                "debugger"
              }
              Import => {
                is_shorthand_key = true
                "import"
              }
              Export => {
                is_shorthand_key = true
                "export"
              }
              From => {
                is_shorthand_key = true
                "from"
              }
              As => {
                is_shorthand_key = true
                "as"
              }
              Break => {
                is_shorthand_key = true
                "break"
              }
              Continue => {
                is_shorthand_key = true
                "continue"
              }
              Function => {
                is_shorthand_key = true
                "function"
              }
              Do => {
                is_shorthand_key = true
                "do"
              }
              Try => {
                is_shorthand_key = true
                "try"
              }
              Catch => {
                is_shorthand_key = true
                "catch"
              }
              Finally => {
                is_shorthand_key = true
                "finally"
              }
              Throw => {
                is_shorthand_key = true
                "throw"
              }
              Delete => {
                is_shorthand_key = true
                "delete"
              }
              Yield => {
                is_shorthand_key = true
                "yield"
              }
              Let => {
                is_shorthand_key = true
                "let"
              }
              Const => {
                is_shorthand_key = true
                "const"
              }
              Var => {
                is_shorthand_key = true
                "var"
              }
              New => {
                is_shorthand_key = true
                "new"
              }
              Typeof => {
                is_shorthand_key = true
                "typeof"
              }
              Of => {
                is_shorthand_key = true
                "of"
              }
              In => {
                is_shorthand_key = true
                "in"
              }
              Declare => {
                is_shorthand_key = true
                "declare"
              }
              Interface => {
                is_shorthand_key = true
                "interface"
              }
              Class => {
                is_shorthand_key = true
                "class"
              }
              Instanceof => {
                is_shorthand_key = true
                "instanceof"
              }
              NumberType => {
                is_shorthand_key = true
                "number"
              }
              BooleanType => {
                is_shorthand_key = true
                "boolean"
              }
              StringType => {
                is_shorthand_key = true
                "string"
              }
              VoidType => {
                is_shorthand_key = true
                "void"
              }
              IntType => {
                is_shorthand_key = true
                "int"
              }
              Bool(true) => {
                is_shorthand_key = true
                "true"
              }
              Bool(false) => {
                is_shorthand_key = true
                "false"
              }
              Null => {
                is_shorthand_key = true
                "null"
              }
              Type => {
                is_shorthand_key = true
                "type"
              }
              Extends => {
                is_shorthand_key = true
                "extends"
              }
              k => raise ParseError("Expected property name, got \{k}")
            }
          }
          let mut prop_key = key
          let value = if is_ident_key &&
            (prop_key == "get" || prop_key == "set") &&
            !self.check(Colon) &&
            !self.check(LParen) &&
            !self.check(Lt) &&
            !self.check(Comma) &&
            !self.check(RBrace) {
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
            let prev_function = self.in_function
            self.in_function = true
            let body = self.parse_block()
            self.in_function = prev_function
            @ast.TsExpr::FuncExpr(@ast.TsFunc::{
              name: func_name,
              params,
              return_type,
              body,
              is_generator: false,
              is_async: false,
            })
          } else if is_ident_key &&
            prop_key == "async" &&
            !self.check(Colon) &&
            !self.check(Comma) &&
            !self.check(RBrace) {
            let async_is_generator = self.match_(Star)
            let (
              async_name,
              async_is_computed,
              async_computed_expr,
              next_computed_idx,
            ) = self.parse_object_member_name(computed_idx)
            prop_key = async_name
            is_computed_key = async_is_computed
            computed_key_expr = async_computed_expr
            computed_idx = next_computed_idx
            self.parse_object_method_value(prop_key, async_is_generator, true)
          } else if self.match_(Colon) {
            self.parse_assignment()
          } else if is_ident_key && self.match_(Eq) {
            self.parse_assignment()
          } else if self.check(LParen) || self.check(Lt) {
            self.parse_object_method_value(prop_key, is_generator, false)
          } else if is_shorthand_key &&
            (self.check(Comma) || self.check(RBrace)) {
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
    Import => {
      // dynamic import: import(specifier) or import.meta
      let _ = self.advance()
      if self.match_(Dot) {
        // import.meta
        let prop = match self.advance().kind {
          Ident(n) => n
          k => raise ParseError("Expected identifier after import., got \{k}")
        }
        if prop == "meta" {
          ImportMeta
        } else {
          raise ParseError("Expected 'meta' after import., got '\{prop}'")
        }
      } else {
        // dynamic import: import(specifier)
        let _ = self.expect(LParen)
        let specifier = self.parse_assignment()
        let _ = self.expect(RParen)
        DynamicImport(specifier)
      }
    }
    _ => raise ParseError("Unexpected token: \{tok.kind}")
  }
}

///|
// / Check if this is an async arrow function
fn Parser::is_async_arrow_function(self : Parser) -> Bool {
  // Check for async identifier => ... (single parameter without parens)
  match self.peek_at(1).kind {
    Ident(_)
    | NumberType
    | BooleanType
    | StringType
    | VoidType
    | IntType
    | Type
    | Of
    | In
    | From
    | Delete => return self.peek_at(2).kind == Arrow
    _ => ()
  }
  if self.peek_at(1).kind == Lt {
    let temp = { ..self, pos: self.pos + 1 }
    temp.skip_type_args()
    if !temp.check(LParen) {
      return false
    }
    return temp.is_arrow_function()
  }
  // Check for async (params) => ...
  if self.peek_at(1).kind == LParen {
    let temp = { ..self, pos: self.pos + 2 }
    return try {
      let _ = temp.parse_params()
      if !temp.check(RParen) {
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
    } catch {
      _ => false
    }
  }
  false
}

///|
// / Parse async arrow function: async (params) => body or async x => body
fn Parser::parse_async_arrow_function(
  self : Parser,
) -> @ast.TsExpr raise ParseError {
  // Check for single parameter without parens: async x => ...
  if self.peek_at(1).kind == Arrow {
    let name = match self.peek().kind {
      Ident(_)
      | NumberType
      | BooleanType
      | StringType
      | VoidType
      | IntType
      | Type
      | Of
      | In
      | From
      | Delete => self.parse_binding_ident()
      _ => "<anon>"
    }
    if name != "<anon>" {
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
  }

  if self.check(Lt) {
    self.skip_type_args()
  }
  // Parse with parentheses: async (params) => body
  let _ = self.expect(LParen)
  let params = self.parse_params()
  let _ = self.expect(RParen)
  // Skip optional return type annotation
  if self.check(Colon) {
    let _ = self.advance()
    self.skip_type_until_arrow()
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

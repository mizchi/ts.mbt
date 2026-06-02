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
    // TS lets `as T` / `satisfies T` bind tighter than the equality
    // operators (they sit at unary precedence in the spec), so
    // `"foo" === "bar" as string` is `"foo" === ("bar" as string)`
    // — not `("foo" === "bar") as string`. Consume the trailing
    // assertion on the right operand here so the binary-op AST
    // mirrors that grouping. Without this, our "always-false"
    // overlap diagnostic compares two string literals and reports
    // a false positive on the cast-widened RHS.
    let consume_rhs_assertion = fn(
      right : @ast.TsExpr,
    ) -> @ast.TsExpr raise ParseError {
      let (_, wrapped) = self.consume_trailing_assertions_wrap(right)
      wrapped
    }
    if self.match_(EqEqEq) {
      let right = consume_rhs_assertion(self.parse_comparison())
      left = BinOp(BinEq, left, right)
    } else if self.match_(BangEqEq) {
      let right = consume_rhs_assertion(self.parse_comparison())
      left = BinOp(BinNe, left, right)
    } else if self.match_(EqEq) {
      let right = consume_rhs_assertion(self.parse_comparison())
      left = BinOp(AbstractEq, left, right)
    } else if self.match_(BangEq) {
      let right = consume_rhs_assertion(self.parse_comparison())
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
      // Destructuring assignment whose LHS slipped past
      // `is_destructuring_assignment_start` because the spread / element
      // target wasn't expressible as a simple binding pattern — e.g.
      // `{ ...super.a } = { ... }`. Consume the `=` and wrap as an
      // `AssignPattern` with a `Target(...)` binding so the parser can
      // move on. Downstream passes treat the construct opaquely.
      ObjectLit(_) | ArrayLit(_) => {
        let _ = self.advance()
        let right = self.parse_assignment()
        AssignPattern(@ast.TsBinding::Target(left), right)
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
    type_params: [],
    const_type_params: [],
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
    @ast.TsType::Any,
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
    // `as T` / `satisfies T` sit at unary precedence in the TS spec,
    // so `a === b as T` is `a === (b as T)`. Without consuming the
    // assertion here the AST would wrap the whole equality and our
    // "always-false" overlap diagnostic would compare the un-cast
    // literals (`"foo" === ("bar" as string)`).
    let consume_rhs_assertion = fn(
      right : @ast.TsExpr,
    ) -> @ast.TsExpr raise ParseError {
      let (_, wrapped) = self.consume_trailing_assertions_wrap(right)
      wrapped
    }
    if self.match_(EqEqEq) {
      let right = consume_rhs_assertion(self.parse_comparison())
      left = BinOp(BinEq, left, right)
    } else if self.match_(BangEqEq) {
      let right = consume_rhs_assertion(self.parse_comparison())
      left = BinOp(BinNe, left, right)
    } else if self.match_(EqEq) {
      let right = consume_rhs_assertion(self.parse_comparison())
      left = BinOp(AbstractEq, left, right)
    } else if self.match_(BangEq) {
      let right = consume_rhs_assertion(self.parse_comparison())
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
  // Require a balanced `<...>` — otherwise `S<N;…` happily scans to
  // EOF, the caller treats it as a successful generic-instantiation,
  // and everything after the misread `<` disappears. (Real cases:
  // for-cond `S<N;++S`, ternary `S<N?a:b`.)
  if !self.try_skip_type_args() {
    self.pos = saved_pos
    return false
  }
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
      let jsx_expr = temp.parse_jsx_element_expr()
      if temp.check(RParen) {
        self.pos = temp.pos + 1
        return jsx_expr
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
/// Walk a JSX element starting at source position `start` and return
/// its end position, the (opening-tag) tag name, the attribute list,
/// and any remaining embedded `{expr}` sub-expressions from children
/// / spread positions. Used by `parse_jsx_element_expr` to build a
/// `JsxElement(tag, attrs, embeds)` AST node.
fn Parser::scan_jsx_source_end_with_structure(
  self : Parser,
  start : Int,
) -> (Int, String, Array[(String, @ast.TsExpr?)], Array[@ast.TsExpr]) {
  let (end, embeds) = self.scan_jsx_source_end_with_embeds(start)
  let (tag, attrs, attr_embed_count) = self.parse_jsx_opening_tag(start)
  // The first `attr_embed_count` embeds came from attribute values;
  // the rest are children / spreads.
  let child_embeds : Array[@ast.TsExpr] = []
  let mut i = attr_embed_count
  while i < embeds.length() {
    child_embeds.push(embeds[i])
    i = i + 1
  }
  (end, tag, attrs, child_embeds)
}

///|
/// Parse a JSX opening tag (`<Tag attr="x" foo={bar} {...spread}>` or
/// `<Tag />` / `</Tag>`) starting at source position `start`. Returns
/// the tag name, the attribute list, and the count of embedded
/// `{expr}` values that were consumed inside attribute slots (so the
/// caller can split the flat embed array into attr vs child halves).
/// Falls back to empty results when the opening shape is malformed.
fn Parser::parse_jsx_opening_tag(
  self : Parser,
  start : Int,
) -> (String, Array[(String, @ast.TsExpr?)], Int) {
  let attrs : Array[(String, @ast.TsExpr?)] = []
  let mut attr_embeds = 0
  let mut i = start
  if i >= self.src.length() || self.src[i].to_int().unsafe_to_char() != '<' {
    return ("", attrs, 0)
  }
  i += 1
  // Skip whitespace.
  while i < self.src.length() {
    let c = self.src[i].to_int().unsafe_to_char()
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      i += 1
    } else {
      break
    }
  }
  // Fragment `<>` / closing-element `</…>` — no name.
  if i < self.src.length() &&
    (
      self.src[i].to_int().unsafe_to_char() == '>' ||
      self.src[i].to_int().unsafe_to_char() == '/'
    ) {
    return ("", attrs, 0)
  }
  // Tag name (identifier with optional `.member.access`).
  let tag_start = i
  while i < self.src.length() {
    let c = self.src[i].to_int().unsafe_to_char()
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '$' ||
      c == '.' ||
      c == '-' {
      i += 1
    } else {
      break
    }
  }
  let tag = self.src[tag_start:i].to_owned()
  // Attributes loop.
  while i < self.src.length() {
    let c = self.src[i].to_int().unsafe_to_char()
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      i += 1
      continue
    }
    if c == '>' || c == '/' || c == '<' {
      break
    }
    // `{...expr}` spread attribute — embed counted; no name pair.
    if c == '{' {
      let end = self.skip_jsx_braces_in_source(i)
      if end > i + 1 {
        let inner = self.src[i + 1:end - 1].to_owned()
        let trimmed = inner.trim()
        if trimmed.length() > 0 {
          attr_embeds = attr_embeds + 1
        }
      }
      i = end
      continue
    }
    // Attribute name.
    let name_start = i
    while i < self.src.length() {
      let nc = self.src[i].to_int().unsafe_to_char()
      if (nc >= 'a' && nc <= 'z') ||
        (nc >= 'A' && nc <= 'Z') ||
        (nc >= '0' && nc <= '9') ||
        nc == '_' ||
        nc == '$' ||
        nc == '-' ||
        nc == ':' {
        i += 1
      } else {
        break
      }
    }
    if i == name_start {
      // Couldn't lex a name — break to avoid an infinite loop.
      break
    }
    let attr_name = self.src[name_start:i].to_owned()
    // Skip whitespace.
    while i < self.src.length() {
      let wc = self.src[i].to_int().unsafe_to_char()
      if wc == ' ' || wc == '\t' || wc == '\n' || wc == '\r' {
        i += 1
      } else {
        break
      }
    }
    // Optional value.
    if i < self.src.length() && self.src[i].to_int().unsafe_to_char() == '=' {
      i += 1
      while i < self.src.length() {
        let wc = self.src[i].to_int().unsafe_to_char()
        if wc == ' ' || wc == '\t' || wc == '\n' || wc == '\r' {
          i += 1
        } else {
          break
        }
      }
      if i < self.src.length() {
        let vc = self.src[i].to_int().unsafe_to_char()
        if vc == '{' {
          let end = self.skip_jsx_braces_in_source(i)
          let inner = self.src[i + 1:end - 1].to_owned()
          let trimmed = inner.trim()
          if trimmed.length() > 0 {
            let payload_str = if trimmed.has_prefix("...") {
              trimmed[3:].to_owned().trim().to_owned()
            } else {
              trimmed.to_owned()
            }
            let sub = Parser::from_source_with_jsx(payload_str, self.allow_jsx)
            try sub.parse_expr() catch {
              _ => attrs.push((attr_name, None))
            } noraise {
              e => {
                attrs.push((attr_name, Some(e)))
                attr_embeds = attr_embeds + 1
              }
            }
          } else {
            attrs.push((attr_name, None))
          }
          i = end
        } else if vc == '"' || vc == '\'' {
          let quote = vc
          let str_start = i + 1
          i += 1
          while i < self.src.length() &&
                self.src[i].to_int().unsafe_to_char() != quote {
            i += 1
          }
          let raw = self.src[str_start:i].to_owned()
          attrs.push((attr_name, Some(@ast.TsExpr::StringLit(raw))))
          if i < self.src.length() {
            i += 1
          }
        } else {
          attrs.push((attr_name, None))
        }
      } else {
        attrs.push((attr_name, None))
      }
    } else {
      // Boolean attribute.
      attrs.push((attr_name, None))
    }
  }
  (tag, attrs, attr_embeds)
}

///|
/// Walk a JSX element starting at source position `start` and return
/// both its end position and the embedded `{expr}` sub-expressions
/// (attribute values, child expressions, spread targets). The caller
/// uses the end position to advance the lexer and wraps the embedded
/// expressions in a `JsxElement(...)` AST node so the checker still
/// validates calls / type mismatches inside braces.
fn Parser::scan_jsx_source_end_with_embeds(
  self : Parser,
  start : Int,
) -> (Int, Array[@ast.TsExpr]) {
  let embeds : Array[@ast.TsExpr] = []
  let mut i = start
  let mut depth = 0
  while i < self.src.length() {
    let c = self.src[i].to_int().unsafe_to_char()
    if c == '{' {
      let end = self.skip_jsx_braces_in_source(i)
      // Capture the source between `{` and the matching `}` and try to
      // parse it as a TS expression. Empty braces (`{}`) are ignored.
      if end > i + 1 {
        let inner = self.src[i + 1:end - 1].to_owned()
        let trimmed = inner.trim()
        if trimmed.length() > 0 {
          // Spread-attribute syntax `{...expr}` and child-spread
          // `{...arr}` show up as a leading `...`; strip it before
          // parsing.
          let payload_str = if trimmed.has_prefix("...") {
            trimmed[3:].to_owned().trim().to_owned()
          } else {
            trimmed.to_owned()
          }
          let sub = Parser::from_source_with_jsx(payload_str, self.allow_jsx)
          try sub.parse_expr() catch {
            _ => ()
          } noraise {
            e => embeds.push(e)
          }
        }
      }
      i = end
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
            let end = self.skip_jsx_braces_in_source(i)
            if end > i + 1 {
              let inner_src = self.src[i + 1:end - 1].to_owned()
              let trimmed = inner_src.trim()
              if trimmed.length() > 0 {
                let payload_str = if trimmed.has_prefix("...") {
                  trimmed[3:].to_owned().trim().to_owned()
                } else {
                  trimmed.to_owned()
                }
                let sub = Parser::from_source_with_jsx(
                  payload_str,
                  self.allow_jsx,
                )
                try sub.parse_expr() catch {
                  _ => ()
                } noraise {
                  e => embeds.push(e)
                }
              }
            }
            i = end
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
  (i, embeds)
}

///|
/// Same as `try_skip_parenthesized_jsx_expr` but also returns the
/// embedded `{expr}` sub-expressions extracted from the JSX block.
/// Caller wraps them in `JsxElement(...)`.
fn Parser::try_parse_parenthesized_jsx_expr(
  self : Parser,
) -> (Bool, Array[@ast.TsExpr]) {
  if self.src.length() == 0 || !self.check(LParen) {
    return (false, [])
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
    return (false, [])
  }
  let (jsx_end, embeds) = self.scan_jsx_source_end_with_embeds(i)
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
    return (true, embeds)
  }
  (false, [])
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
/// Returns the embedded `{expr}` sub-expressions so callers can wrap
/// them in a `JsxElement(...)` AST node.
fn Parser::parse_jsx_element_expr(self : Parser) -> @ast.TsExpr {
  if self.src.length() == 0 {
    self.skip_jsx_element_tokens()
    return @ast.TsExpr::JsxElement("", [], [])
  }
  let start = self.peek().pos
  match self.parse_jsx_element_at_source(start) {
    Some((end, element)) => {
      self.advance_to_source_pos(end)
      element
    }
    None => {
      // Fallback: structural parse failed — use the legacy flat
      // scanner so the parser still makes progress.
      let (end, tag, attrs, child_embeds) = self.scan_jsx_source_end_with_structure(
        start,
      )
      self.advance_to_source_pos(end)
      @ast.TsExpr::JsxElement(tag, attrs, child_embeds)
    }
  }
}

///|
/// Recursive-descent JSX element parser. Returns `(end_pos, element)`
/// when parsing succeeds, or `None` if the source at `start` doesn't
/// open with a recognisable JSX element. Used by
/// `parse_jsx_element_expr` to assemble a fully structured
/// `JsxElement` node (tag + attrs + per-child entries) rather than the
/// flat `embeds` list produced by the legacy scanner.
fn Parser::parse_jsx_element_at_source(
  self : Parser,
  start : Int,
) -> (Int, @ast.TsExpr)? {
  if start >= self.src.length() ||
    self.src[start].to_int().unsafe_to_char() != '<' {
    return None
  }
  // Empty fragment `<>` opener.
  let after_open = start + 1
  if after_open < self.src.length() &&
    self.src[after_open].to_int().unsafe_to_char() == '>' {
    let body_start = after_open + 1
    match self.parse_jsx_children(body_start, "") {
      Some((after_body, children)) => {
        // Expect `</>` to close.
        if after_body + 2 < self.src.length() &&
          self.src[after_body].to_int().unsafe_to_char() == '<' &&
          self.src[after_body + 1].to_int().unsafe_to_char() == '/' &&
          self.src[after_body + 2].to_int().unsafe_to_char() == '>' {
          return Some(
            (after_body + 3, @ast.TsExpr::JsxElement("", [], children)),
          )
        }
        None
      }
      None => None
    }
  } else {
    // Named opener — parse the tag header.
    let (header_end, tag, attrs, self_close) = self.parse_jsx_opening_header(
      start,
    )
    if tag == "" {
      return None
    }
    if self_close {
      return Some((header_end, @ast.TsExpr::JsxElement(tag, attrs, [])))
    }
    // Paired element — recurse on children until matching closing tag.
    match self.parse_jsx_children(header_end, tag) {
      Some((after_body, children)) => {
        // Consume `</tag>`.
        let after_close = self.skip_jsx_closing_tag(after_body, tag)
        match after_close {
          Some(end) =>
            Some((end, @ast.TsExpr::JsxElement(tag, attrs, children)))
          None => None
        }
      }
      None => None
    }
  }
}

///|
/// Parse a JSX opening header at `start` — `<Tag attr={…} …>` or
/// `<Tag …/>`. Returns the position right after the closing `>` /
/// `/>`, the tag name, the attribute list, and a `self_close` flag
/// indicating whether the element terminates immediately. An empty
/// tag name signals a malformed shape that the caller should treat
/// as a parse failure.
fn Parser::parse_jsx_opening_header(
  self : Parser,
  start : Int,
) -> (Int, String, Array[(String, @ast.TsExpr?)], Bool) {
  let attrs : Array[(String, @ast.TsExpr?)] = []
  let mut i = start
  if i >= self.src.length() || self.src[i].to_int().unsafe_to_char() != '<' {
    return (i, "", attrs, false)
  }
  i += 1
  while i < self.src.length() {
    let c = self.src[i].to_int().unsafe_to_char()
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      i += 1
    } else {
      break
    }
  }
  if i >= self.src.length() {
    return (i, "", attrs, false)
  }
  let first = self.src[i].to_int().unsafe_to_char()
  if first == '>' || first == '/' {
    return (i, "", attrs, false)
  }
  let name_start = i
  while i < self.src.length() {
    let c = self.src[i].to_int().unsafe_to_char()
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '$' ||
      c == '.' ||
      c == '-' {
      i += 1
    } else {
      break
    }
  }
  let tag = self.src[name_start:i].to_owned()
  let mut self_close = false
  // Explicit generic type arguments `<Box<string> .../>`. Skip the
  // balanced angle brackets so the rest of the attribute loop sees the
  // attribute list. The generic info is dropped — the checker resolves
  // props against the component's parameter type, not the call-site
  // generic.
  if i < self.src.length() && self.src[i].to_int().unsafe_to_char() == '<' {
    let mut depth = 1
    let mut j = i + 1
    while j < self.src.length() && depth > 0 {
      let cc = self.src[j].to_int().unsafe_to_char()
      if cc == '<' {
        depth += 1
      } else if cc == '>' {
        depth -= 1
        if depth == 0 {
          j += 1
          break
        }
      }
      j += 1
    }
    if depth == 0 {
      i = j
    }
  }
  // Attributes.
  while i < self.src.length() {
    let c = self.src[i].to_int().unsafe_to_char()
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      i += 1
      continue
    }
    if c == '>' {
      i += 1
      break
    }
    if c == '/' &&
      i + 1 < self.src.length() &&
      self.src[i + 1].to_int().unsafe_to_char() == '>' {
      self_close = true
      i += 2
      break
    }
    if c == '{' {
      // Spread attribute `{...expr}` — capture as ("", Some(expr)).
      let end = self.skip_jsx_braces_in_source(i)
      if end > i + 1 {
        let inner_src = self.src[i + 1:end - 1].to_owned()
        let trimmed = inner_src.trim()
        if trimmed.length() > 0 && trimmed.has_prefix("...") {
          let payload_str = trimmed[3:].to_owned().trim().to_owned()
          let sub = Parser::from_source_with_jsx(payload_str, self.allow_jsx)
          try sub.parse_expr() catch {
            _ => ()
          } noraise {
            e => attrs.push(("", Some(e)))
          }
        }
      }
      i = end
      continue
    }
    // Attribute name.
    let name_start = i
    while i < self.src.length() {
      let nc = self.src[i].to_int().unsafe_to_char()
      if (nc >= 'a' && nc <= 'z') ||
        (nc >= 'A' && nc <= 'Z') ||
        (nc >= '0' && nc <= '9') ||
        nc == '_' ||
        nc == '$' ||
        nc == '-' ||
        nc == ':' {
        i += 1
      } else {
        break
      }
    }
    if i == name_start {
      break
    }
    let attr_name = self.src[name_start:i].to_owned()
    while i < self.src.length() {
      let wc = self.src[i].to_int().unsafe_to_char()
      if wc == ' ' || wc == '\t' || wc == '\n' || wc == '\r' {
        i += 1
      } else {
        break
      }
    }
    if i < self.src.length() && self.src[i].to_int().unsafe_to_char() == '=' {
      i += 1
      while i < self.src.length() {
        let wc = self.src[i].to_int().unsafe_to_char()
        if wc == ' ' || wc == '\t' || wc == '\n' || wc == '\r' {
          i += 1
        } else {
          break
        }
      }
      if i < self.src.length() {
        let vc = self.src[i].to_int().unsafe_to_char()
        if vc == '{' {
          let end = self.skip_jsx_braces_in_source(i)
          let inner_src = self.src[i + 1:end - 1].to_owned()
          let trimmed = inner_src.trim()
          if trimmed.length() > 0 {
            let payload_str = if trimmed.has_prefix("...") {
              trimmed[3:].to_owned().trim().to_owned()
            } else {
              trimmed.to_owned()
            }
            let sub = Parser::from_source_with_jsx(payload_str, self.allow_jsx)
            try sub.parse_expr() catch {
              _ => attrs.push((attr_name, None))
            } noraise {
              e => attrs.push((attr_name, Some(e)))
            }
          } else {
            attrs.push((attr_name, None))
          }
          i = end
        } else if vc == '"' || vc == '\'' {
          let quote = vc
          let str_start = i + 1
          i += 1
          while i < self.src.length() &&
                self.src[i].to_int().unsafe_to_char() != quote {
            i += 1
          }
          let raw = self.src[str_start:i].to_owned()
          attrs.push((attr_name, Some(@ast.TsExpr::StringLit(raw))))
          if i < self.src.length() {
            i += 1
          }
        } else {
          attrs.push((attr_name, None))
        }
      } else {
        attrs.push((attr_name, None))
      }
    } else {
      attrs.push((attr_name, None))
    }
  }
  (i, tag, attrs, self_close)
}

///|
/// Parse JSX children starting at `start` until we encounter the
/// closing tag matching `closing_tag` (or `</>` when `closing_tag` is
/// empty, indicating a fragment). Returns the position of the closing
/// `<` and the assembled children list. `None` on malformed input.
fn Parser::parse_jsx_children(
  self : Parser,
  start : Int,
  closing_tag : String,
) -> (Int, Array[@ast.TsExpr])? {
  let children : Array[@ast.TsExpr] = []
  let mut i = start
  let mut text_start = i
  let flush_text = fn(end_idx) {
    if end_idx > text_start {
      let raw = self.src[text_start:end_idx].to_owned()
      let trimmed = raw.trim()
      if trimmed.length() > 0 {
        children.push(@ast.TsExpr::StringLit(raw))
      }
    }
  }
  while i < self.src.length() {
    let c = self.src[i].to_int().unsafe_to_char()
    if c == '<' {
      // Closing tag?
      if i + 1 < self.src.length() &&
        self.src[i + 1].to_int().unsafe_to_char() == '/' {
        flush_text(i)
        return Some((i, children))
      }
      // Nested element.
      flush_text(i)
      match self.parse_jsx_element_at_source(i) {
        Some((after, element)) => {
          children.push(element)
          i = after
          text_start = i
        }
        None => return None
      }
      continue
    }
    if c == '{' {
      flush_text(i)
      let end = self.skip_jsx_braces_in_source(i)
      let inner_src = self.src[i + 1:end - 1].to_owned()
      let trimmed = inner_src.trim()
      if trimmed.length() > 0 {
        let payload_str = if trimmed.has_prefix("...") {
          trimmed[3:].to_owned().trim().to_owned()
        } else {
          trimmed.to_owned()
        }
        let sub = Parser::from_source_with_jsx(payload_str, self.allow_jsx)
        try sub.parse_expr() catch {
          _ => ()
        } noraise {
          e => children.push(e)
        }
      }
      i = end
      text_start = i
      continue
    }
    i += 1
  }
  let _ = closing_tag
  // Reached EOF without finding a closing tag — malformed.
  None
}

///|
/// Consume `</tag>` starting at position `start`. Returns the position
/// right after `>` on success, `None` if the source doesn't match.
fn Parser::skip_jsx_closing_tag(
  self : Parser,
  start : Int,
  tag : String,
) -> Int? {
  let mut i = start
  if i + 1 >= self.src.length() ||
    self.src[i].to_int().unsafe_to_char() != '<' ||
    self.src[i + 1].to_int().unsafe_to_char() != '/' {
    return None
  }
  i += 2
  while i < self.src.length() {
    let c = self.src[i].to_int().unsafe_to_char()
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      i += 1
    } else {
      break
    }
  }
  let name_start = i
  while i < self.src.length() {
    let c = self.src[i].to_int().unsafe_to_char()
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '$' ||
      c == '.' ||
      c == '-' {
      i += 1
    } else {
      break
    }
  }
  let closing_name = self.src[name_start:i].to_owned()
  if closing_name != tag {
    return None
  }
  while i < self.src.length() {
    let c = self.src[i].to_int().unsafe_to_char()
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      i += 1
    } else {
      break
    }
  }
  if i < self.src.length() && self.src[i].to_int().unsafe_to_char() == '>' {
    Some(i + 1)
  } else {
    None
  }
}

///|
// / function, array, property, method
fn Parser::parse_call(self : Parser) -> @ast.TsExpr raise ParseError {
  // Capture the start position of the callee BEFORE we parse the
  // primary — that's where the lexer stamped the `@__PURE__`
  // annotation when it was present in the preceding comment.
  let pure_call_pos = self.peek().pos
  let mut expr = self.parse_primary()
  // After this `parse_call` returns, if the call expression
  // started at a marked position, the result wraps in
  // `PureCall(...)`. We only set the wrap when an actual call
  // followed — bare `parse_primary()` results (`x` alone, no
  // `(args)`) shouldn't be tagged pure.
  let mut saw_call_in_chain = false

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
      // `?.<T>(args)` — generic optional call. Consume the type
      // args then fall through to the `LParen` branch so the
      // OptionalChain wrap still happens.
      let _ = self.try_skip_call_type_args(expr)
      // Wrap THIS step in `OptionalChain(...)` so the emitter can
      // restore the `?.` token. Each `?.` in a chain produces one
      // wrap; the inner accessor (`PropAccess` / `IndexAccess` /
      // `Call` / `MethodCall` / `CallExpr`) tells the emitter
      // which form to use.
      match self.peek().kind {
        LBracket => {
          let _ = self.advance()
          let index = self.parse_expr()
          let _ = self.expect(RBracket)
          expr = @ast.TsExpr::OptionalChain(IndexAccess(expr, index))
          continue
        }
        LParen => {
          let _ = self.advance()
          let args = self.parse_args()
          let _ = self.expect(RParen)
          // We only collapse `MethodCall` / `Call` when the
          // previous step has NO `?.` wrapper of its own. When the
          // previous step is already an OptionalChain (e.g.
          // `obj?.method?.()` — the second `?.` ), keep the
          // wrapper intact and fall back to `CallExpr`; otherwise
          // the inner `?.` between `obj` and `method` would be
          // erased.
          let chained : @ast.TsExpr = match expr {
            Var(name) => Call(name, args)
            PropAccess(receiver, method_name) =>
              MethodCall(receiver, method_name, args)
            _ => CallExpr(expr, args)
          }
          expr = @ast.TsExpr::OptionalChain(chained)
          continue
        }
        _ => {
          let prop = self.parse_property_name_token()
          expr = @ast.TsExpr::OptionalChain(PropAccess(expr, prop))
          continue
        }
      }
    }
    if self.match_(LParen) {
      // function or method
      let args = self.parse_args()
      let _ = self.expect(RParen)
      saw_call_in_chain = true
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
          // Parse expression sources into AST expressions. Inherit
          // `current_class_brand` so `#x` accesses in a tagged
          // template inside a class body keep their brand mangling.
          let exprs : Array[@ast.TsExpr] = []
          for src in expr_sources {
            let sub_parser = Parser::from_source(src)
            sub_parser.current_class_brand = self.current_class_brand
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
  // Apply the `@__PURE__` annotation when the lexer flagged the
  // callee's start position AND we actually consumed a call /
  // method-call form. Tagging a non-call (just `x` with no
  // arguments after) would be misleading.
  if saw_call_in_chain && self.pure_marker_positions.contains(pure_call_pos) {
    @ast.TsExpr::PureCall(expr)
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
  let return_type = if self.check(Colon) {
    let _ = self.advance()
    self.parse_arrow_return_type()
  } else {
    @ast.TsType::Any
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
  ArrowFunc(params, return_type, body, false)
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
  let type_src = self.src[type_start:type_end].to_owned()
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
    // Decorated class expression: `(@dec class C { … })`. Consume the
    // decorator list into `pending_decorators`, then parse the class
    // expression — `parse_class_stub` drains the pending decorators onto the
    // resulting declaration via `take_pending_decorators`.
    At => {
      while self.check(At) {
        self.skip_decorator()
      }
      if !self.check(Class) {
        raise ParseError("Expected class after decorator in expression")
      }
      self.parse_class_stub()
    }
    Class => self.parse_class_stub()
    Lt =>
      if self.is_generic_arrow_function() {
        self.parse_generic_arrow_function()
      } else if !self.allow_jsx {
        self.parse_angle_bracket_type_assertion()
      } else if self.is_jsx_element_start() {
        self.parse_jsx_element_expr()
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
    // `declare` is a soft keyword — valid as a regular identifier in
    // expression position (TS's own harness uses it that way).
    Declare =>
      if self.peek_at(1).kind == Arrow {
        let _ = self.advance()
        self.parse_single_param_arrow("declare")
      } else {
        let _ = self.advance()
        Var("declare")
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
      // Parse expression sources into AST expressions. Each `${…}`
      // interpolation is captured as a raw source string by the
      // lexer and parsed here via a fresh sub-parser. The sub-
      // parser needs to inherit context that affects how
      // identifiers / private names are interpreted — most
      // critically `current_class_brand`, so that `#x` inside the
      // template still mangles to the surrounding class's brand.
      // Without this, `\`${this.#x}\`` would emit the original
      // private syntax outside its class body, which Node rejects
      // as "Private field '#x' must be declared in an enclosing
      // class".
      let exprs : Array[@ast.TsExpr] = []
      for src in expr_sources {
        let sub_parser = Parser::from_source(src)
        sub_parser.current_class_brand = self.current_class_brand
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
          @ast.TsType::Any,
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
    As =>
      if self.peek_at(1).kind == Arrow {
        let _ = self.advance()
        self.parse_single_param_arrow("as")
      } else {
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
    LParen => {
      let (paren_jsx, paren_embeds) = self.try_parse_parenthesized_jsx_expr()
      if paren_jsx {
        // Parenthesised-JSX fallback: skip tag / attr extraction since
        // the existing skipper doesn't preserve start-positions. The
        // checker still recurses into the embedded sub-expressions.
        @ast.TsExpr::JsxElement("", [], paren_embeds)
        // functioncheck
      } else if self.peek_at(1).kind == Lt {
        let temp = { ..self, pos: self.pos + 1 }
        if temp.is_jsx_element_start() {
          let jsx_expr = temp.parse_jsx_element_expr()
          if temp.check(RParen) {
            self.pos = temp.pos + 1
            jsx_expr
          } else if self.is_arrow_function() {
            // function: (params) => body
            let _ = self.advance() // (
            let params = self.parse_params()
            let _ = self.expect(RParen)
            let return_type = if self.check(Colon) {
              let _ = self.advance()
              self.parse_arrow_return_type()
            } else {
              @ast.TsType::Any
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
            ArrowFunc(params, return_type, body, false)
          } else {
            self.parse_parenthesized_expr()
          }
        } else if self.is_arrow_function() {
          // function: (params) => body
          let _ = self.advance() // (
          let params = self.parse_params()
          let _ = self.expect(RParen)
          let return_type = if self.check(Colon) {
            let _ = self.advance()
            self.parse_arrow_return_type()
          } else {
            @ast.TsType::Any
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
          ArrowFunc(params, return_type, body, false)
        } else {
          self.parse_parenthesized_expr()
        }
      } else if self.is_arrow_function() {
        // function: (params) => body
        let _ = self.advance() // (
        let params = self.parse_params()
        let _ = self.expect(RParen)
        let return_type = if self.check(Colon) {
          let _ = self.advance()
          self.parse_arrow_return_type()
        } else {
          @ast.TsType::Any
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
        ArrowFunc(params, return_type, body, false)
      } else {
        // regularexpression
        self.parse_parenthesized_expr()
      }
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
              type_params: [],
              params,
              return_type,
              body,
              const_type_params: [],
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
              type_params: [],
              params,
              return_type,
              body,
              const_type_params: [],
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
        // dynamic import: `import(specifier)` or
        // `import(specifier, options)`.
        let _ = self.expect(LParen)
        let specifier = self.parse_assignment()
        let options : @ast.TsExpr? = if self.match_(Comma) {
          if self.check(RParen) {
            None
          } else {
            Some(self.parse_assignment())
          }
        } else {
          None
        }
        let _ = self.expect(RParen)
        DynamicImport(specifier, options)
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
        @ast.TsType::Any,
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
  // Optional return type annotation — captured so the checker can see
  // `(x): x is Foo => …` predicates.
  let return_type = if self.check(Colon) {
    let _ = self.advance()
    self.parse_arrow_return_type()
  } else {
    @ast.TsType::Any
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
  ArrowFunc(params, return_type, body, true) // is_async = true
}

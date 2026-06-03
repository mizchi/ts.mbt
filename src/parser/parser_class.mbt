///|
priv enum ClassKey {
  Name(String)
  Computed(@ast.TsExpr)
}

///|
priv enum ClassElement {
  Method(Bool, ClassKey, String?, @ast.TsFunc)
  // `Field(is_static, key, type, init, is_readonly, has_definite_assertion)`
  // — the `readonly` modifier (`class C { readonly x: T }`) is captured
  // so downstream structural checks can flag `c.x = …` as TS2540; the
  // `has_definite_assertion` flag (`class C { x!: T }`) feeds the
  // strict-property-initialization check (TS2564) in the checker.
  Field(Bool, ClassKey, @ast.TsType, @ast.TsExpr?, Bool, Bool)
  StaticBlock(@ast.TsBlock)
  // Marker for `[k: KeyType]: ValueType` index signatures. The body is
  // skipped (we don't model index access through the class type), but
  // the presence of any index signature opts the class out of strict-
  // property-initialization (TS2564) because every concrete field is
  // implicitly covered by the indexer.
  IndexSig
}

///|
fn class_key_name(key : ClassKey) -> String {
  match key {
    Name(name) => name
    Computed(_) => "<computed>"
  }
}

///|
fn is_public_runtime_class_member_name(name : String) -> Bool {
  !name.has_prefix("#") && !name.contains("__#") && name != "<computed>"
}

///|
fn runtime_class_param_name(param : @ast.TsParam, index : Int) -> String {
  if param.name != "" {
    return param.name
  }
  match param.binding {
    Some(@ast.TsBinding::Ident(name)) => name
    _ => "arg" + index.to_string()
  }
}

///|
fn build_runtime_class_decl(
  name : String,
  type_params : Array[String],
  ctor_opt : @ast.TsFunc?,
  elements : Array[ClassElement],
  is_abstract : Bool,
  private_members : Array[String],
  protected_members : Array[String],
) -> @ast.TsClassDecl {
  let properties : Array[@ast.TsClassPropertyDecl] = []
  let methods : Array[@ast.TsClassMethodDecl] = []
  let instance_field_inits : Array[(String, @ast.TsExpr)] = []
  let constructor_params = match ctor_opt {
    Some(ctor) => {
      let params : Array[(String, @ast.TsType)] = []
      for index, param in ctor.params {
        params.push((runtime_class_param_name(param, index), param.type_))
      }
      Some(params)
    }
    None => None
  }
  for element in elements {
    match element {
      Field(
        is_static,
        Name(field_name),
        field_type,
        init,
        is_readonly,
        has_definite_assertion
      ) =>
        if is_public_runtime_class_member_name(field_name) {
          upsert_class_property(properties, {
            name: field_name,
            type_: field_type,
            is_static,
            is_readonly,
            is_accessor: false,
            has_initializer: init is Some(_),
            has_definite_assertion,
          })
          if !is_static {
            match init {
              Some(expr) => instance_field_inits.push((field_name, expr))
              None => ()
            }
          }
        }
      Method(is_static, Name(method_name), accessor_kind, func) =>
        if is_public_runtime_class_member_name(method_name) {
          // Always record the method (so getters/setters keep their
          // bodies for emit); the `accessor` tag tells the emitter
          // whether to restore `get foo()` / `set foo(v)` syntax.
          let params : Array[(String, @ast.TsType)] = []
          let param_defaults : Array[@ast.TsExpr?] = []
          let param_is_rest : Array[Bool] = []
          for index, param in func.params {
            params.push((runtime_class_param_name(param, index), param.type_))
            param_defaults.push(param.default)
            param_is_rest.push(param.is_rest)
          }
          let accessor_tag = match accessor_kind {
            Some("get") => "get"
            Some("set") => "set"
            _ => ""
          }
          methods.push({
            name: method_name,
            type_params: func.type_params,
            type_param_bounds: [],
            params,
            param_defaults,
            param_is_rest,
            return_type: func.return_type,
            is_static,
            body: if func.body.stmts.length() == 0 {
              None
            } else {
              Some(func.body)
            },
            accessor: accessor_tag,
            key_expr: None,
            is_async: func.is_async,
            is_generator: func.is_generator,
          })
          match accessor_kind {
            Some("get") =>
              upsert_class_property(properties, {
                name: method_name,
                type_: func.return_type,
                is_static,
                is_readonly: true,
                is_accessor: false,
                has_initializer: false,
                has_definite_assertion: false,
              })
            Some("set") => {
              let setter_type = if func.params.length() > 0 {
                func.params[0].type_
              } else {
                @ast.TsType::Any
              }
              upsert_class_property(properties, {
                name: method_name,
                type_: setter_type,
                is_static,
                is_readonly: false,
                is_accessor: false,
                has_initializer: false,
                has_definite_assertion: false,
              })
            }
            _ => ()
          }
        }
      // Computed-key method (`class X { [Sym.iterator]() {…} }` /
      // `[OpCodes.OP_ON_SUCCESS](op) {…}`). Record it on the
      // `methods` list with the sentinel name `<computed>` and the
      // parsed key expression on `key_expr` so emit can restore
      // `[<expr>](…)` inside the class body. Effect's FiberRuntime
      // dispatches `this[cur._op](cur)` on these; dropping them
      // (which the previous code did) made `_op === "OnSuccess"`
      // resolve to `undefined` and runLoop ran forever.
      Method(is_static, Computed(key_expr), accessor_kind, func) => {
        let params : Array[(String, @ast.TsType)] = []
        let param_defaults : Array[@ast.TsExpr?] = []
        let param_is_rest : Array[Bool] = []
        for index, param in func.params {
          params.push((runtime_class_param_name(param, index), param.type_))
          param_defaults.push(param.default)
          param_is_rest.push(param.is_rest)
        }
        let accessor_tag = match accessor_kind {
          Some("get") => "get"
          Some("set") => "set"
          _ => ""
        }
        methods.push({
          name: "<computed>",
          type_params: func.type_params,
          type_param_bounds: [],
          params,
          param_defaults,
          param_is_rest,
          return_type: func.return_type,
          is_static,
          body: if func.body.stmts.length() == 0 {
            None
          } else {
            Some(func.body)
          },
          accessor: accessor_tag,
          key_expr: Some(key_expr),
          is_async: func.is_async,
          is_generator: func.is_generator,
        })
      }
      _ => ()
    }
  }
  // Track index-signature presence so the TS2564 check can opt-out
  // (an indexer implicitly types every concrete field). We don't
  // model index lookups against class instances, so the value is an
  // `Any` -> `Any` placeholder -- only the length matters for the
  // skip predicate.
  let index_signatures : Array[(@ast.TsType, @ast.TsType)] = []
  for element in elements {
    if element is IndexSig {
      index_signatures.push((@ast.TsType::Any, @ast.TsType::Any))
    }
  }
  {
    name,
    type_params,
    base_names: [],
    base_expr: None,
    static_field_inits: [],
    instance_field_inits,
    constructor_params,
    properties,
    methods,
    index_signatures,
    is_abstract,
    is_constructible: !is_abstract,
    // Decorators on runtime classes are attached by the caller via
    // `Parser::take_pending_decorators` after build returns; the
    // builder is parser-agnostic so it leaves the slot empty.
    decorators: [],
    is_declare: false,
    private_members,
    protected_members,
  }
}

///|
fn Parser::take_last_runtime_class_decl(self : Parser) -> @ast.TsClassDecl? {
  let result = self.last_runtime_class_decl
  self.last_runtime_class_decl = None
  result
}

///|
fn has_static_private_elements(elements : Array[ClassElement]) -> Bool {
  for element in elements {
    match element {
      Field(is_static, Name(name), _, _, _, _)
      | Method(is_static, Name(name), _, _) =>
        // Check for static private members
        if is_static && (name.has_prefix("#") || name.contains("__#")) {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
fn has_instance_private_elements(elements : Array[ClassElement]) -> Bool {
  for element in elements {
    match element {
      Field(is_static, Name(name), _, _, _, _)
      | Method(is_static, Name(name), _, _) =>
        // Check for instance (non-static) private members
        if !is_static && (name.has_prefix("#") || name.contains("__#")) {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
fn mangle_private_name(name : String, brand : String) -> String {
  if name.has_prefix("#") {
    // Strip the `#` — keeping it produces an invalid JS
    // identifier (`__brand__#field`). The brand prefix already
    // gives uniqueness for access control; the `#` was only
    // meaningful in the source-level private-field syntax.
    brand + "__" + name[1:].to_owned()
  } else {
    name
  }
}

///|
fn class_key_expr(key : ClassKey) -> @ast.TsExpr {
  match key {
    Name(name) => @ast.TsExpr::StringLit(name)
    Computed(expr) => expr
  }
}

///|
fn Parser::parse_class_base_name(self : Parser) -> String raise ParseError {
  let start = self.pos
  self.pending_class_base_expr = None
  if self.check(LParen) {
    let expr = self.parse_expr()
    self.pending_class_base_expr = Some(expr)
    return "<expr-base>"
  }
  // `class C extends null { ... }` is valid TS — it creates a constructor
  // with `null` as its prototype, used as a no-prototype class.
  if self.check(Null) {
    let _ = self.advance()
    let _ = start
    self.pending_class_base_expr = Some(@ast.TsExpr::Var("null"))
    return "<expr-base>"
  }
  // `class C extends class { ... } { ... }` — anonymous class expression as
  // the base. Delegate to the general expression parser; whatever it
  // produces collapses to the `<expr-base>` marker since we only need the
  // structural signal that an expression-shaped base was consumed.
  if self.check(Class) {
    let expr = self.parse_expr()
    self.pending_class_base_expr = Some(expr)
    let _ = start
    return "<expr-base>"
  }
  // Some contextual keywords (`declare`, `type`, `from`, `as`, `of`,
  // `in`) double as valid identifier names — `class X extends
  // declare(args) {}` in effect's Schema.js is the standard case.
  // Accept them at the heritage clause's leading name slot.
  let lead = match contextual_ident_token_name(self.peek().kind) {
    Some(n) => {
      let _ = self.advance()
      n
    }
    None =>
      match self.advance().kind {
        Ident(n) => n
        k => raise ParseError("Expected base class name, got \{k}")
      }
  }
  let mut full_name = lead
  while self.check(Dot) {
    let _ = self.advance()
    // After `.`, JS allows ANY reserved word as the property name
    // (post-ES5). `class X extends ns.default {…}` / `extends
    // obj.case {…}` is valid. Accept the reserved-word tokens
    // that the method-key parser already recognises.
    match member_access_token_name(self.peek().kind) {
      Some(n) => {
        let _ = self.advance()
        full_name = full_name + "." + n
      }
      None =>
        match self.advance().kind {
          Ident(n) => full_name = full_name + "." + n
          k => raise ParseError("Expected base class name, got \{k}")
        }
    }
  }
  // `class C extends A?.B { ... }` — optional-chain in the heritage clause.
  // Fall through to expression-based parsing.
  let has_optional_chain = self.check(Question) && self.peek_at(1).kind == Dot
  let mut is_expr_base = self.check(LParen) ||
    self.check(LBracket) ||
    has_optional_chain
  if !is_expr_base && self.check(Lt) {
    let saved = self.pos
    self.skip_type_args()
    is_expr_base = self.check(LParen) ||
      self.check(LBracket) ||
      (self.check(Question) && self.peek_at(1).kind == Dot)
    self.pos = saved
  }
  if is_expr_base {
    self.pos = start
    let expr = self.parse_expr()
    self.pending_class_base_expr = Some(expr)
    return "<expr-base>"
  }
  full_name
}

///|
/// the lexer's keyword classification needs to defer to the surface
/// identifier name.
fn contextual_ident_token_name(kind : TokenKind) -> String? {
  match kind {
    Declare => Some("declare")
    Type => Some("type")
    From => Some("from")
    As => Some("as")
    Of => Some("of")
    In => Some("in")
    _ => None
  }
}

///|
/// Token names allowed in member-access position (`obj.<name>`).
/// JS lets any IdentifierName — including reserved words — sit
/// after `.`. Prettier ships `class X extends reader_1.default {…}`
/// as the canonical case. Mirrors the broader keyword set already
/// accepted in `parse_class_method_key`.
fn member_access_token_name(kind : TokenKind) -> String? {
  match kind {
    Declare => Some("declare")
    Type => Some("type")
    From => Some("from")
    As => Some("as")
    Of => Some("of")
    In => Some("in")
    Default => Some("default")
    Return => Some("return")
    If => Some("if")
    Else => Some("else")
    For => Some("for")
    While => Some("while")
    Do => Some("do")
    Break => Some("break")
    Continue => Some("continue")
    Function => Some("function")
    Try => Some("try")
    Catch => Some("catch")
    Finally => Some("finally")
    Throw => Some("throw")
    Yield => Some("yield")
    Let => Some("let")
    Const => Some("const")
    Var => Some("var")
    Class => Some("class")
    New => Some("new")
    Case => Some("case")
    VoidType => Some("void")
    With => Some("with")
    Switch => Some("switch")
    Typeof => Some("typeof")
    Delete => Some("delete")
    Export => Some("export")
    Import => Some("import")
    Debugger => Some("debugger")
    Interface => Some("interface")
    Instanceof => Some("instanceof")
    Extends => Some("extends")
    NumberType => Some("number")
    BooleanType => Some("boolean")
    StringType => Some("string")
    IntType => Some("int")
    Bool(true) => Some("true")
    Bool(false) => Some("false")
    Null => Some("null")
    _ => None
  }
}

///|
fn Parser::parse_class_method_key(self : Parser) -> ClassKey raise ParseError {
  if self.match_(LBracket) {
    let key_expr = self.parse_assignment()
    let _ = self.expect(RBracket)
    return Computed(key_expr)
  }
  let name = match self.advance().kind {
    Ident(n) => n
    PrivateIdent(n) => {
      let private_name = "#" + n
      match self.current_class_brand {
        Some(brand) => mangle_private_name(private_name, brand)
        None => private_name
      }
    }
    Str(s) => s
    Number(n) => "\{n}"
    Int(n) => "\{n}"
    // Reserved words can be used as method names in ES6+
    Return => "return"
    If => "if"
    Else => "else"
    For => "for"
    While => "while"
    Break => "break"
    Continue => "continue"
    Function => "function"
    Try => "try"
    Catch => "catch"
    Finally => "finally"
    Throw => "throw"
    Yield => "yield"
    Type => "type"
    Let => "let"
    Const => "const"
    Var => "var"
    Class => "class"
    New => "new"
    // Additional reserved words allowed as method names
    Default => "default"
    Do => "do"
    In => "in"
    Of => "of"
    Case => "case"
    VoidType => "void"
    With => "with"
    Switch => "switch"
    Typeof => "typeof"
    Delete => "delete"
    Export => "export"
    Import => "import"
    Debugger => "debugger"
    Interface => "interface"
    Instanceof => "instanceof"
    Extends => "extends"
    From => "from"
    As => "as"
    NumberType => "number"
    BooleanType => "boolean"
    StringType => "string"
    IntType => "int"
    Bool(true) => "true"
    Bool(false) => "false"
    Null => "null"
    // Note: static, this, super, true, false, null, get, set, of, async, await
    // are handled as Ident tokens with special names, not separate TokenKind
    k => raise ParseError("Expected method name, got \{k}")
  }
  Name(name)
}

///|
fn Parser::can_consume_class_modifier(self : Parser) -> Bool {
  match self.peek_at(1).kind {
    Colon | LParen | Lt | Eq | Semicolon | RBrace | Question | Bang => false
    _ => true
  }
}

///|
fn Parser::try_skip_class_index_signature(self : Parser) -> Bool {
  if !self.check(LBracket) {
    return false
  }
  let saved_pos = self.pos
  let _ = self.advance()
  let mut depth = 1
  let mut has_index_type_separator = false
  while depth > 0 && !self.check(Eof) {
    match self.peek().kind {
      Colon if depth == 1 => {
        has_index_type_separator = true
        let _ = self.advance()
      }
      LBracket => {
        depth += 1
        let _ = self.advance()
      }
      RBracket => {
        depth -= 1
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
  if !has_index_type_separator {
    self.pos = saved_pos
    return false
  }
  if self.match_(Colon) {
    try {
      let _ = self.parse_type()
    } catch {
      _ => self.skip_until_semicolon()
    }
  }
  if self.check(Semicolon) || self.check(Comma) {
    let _ = self.advance()
  }
  true
}

///|
fn Parser::is_super_call_stmt(_self : Parser, stmt : @ast.TsStmt) -> Bool {
  match stmt {
    Expr(Call("super", _)) => true
    Expr(CallExpr(@ast.TsExpr::Var("super"), _)) => true
    _ => false
  }
}

///|
// Returns true if the block contains a `super(...)` call anywhere (recursively).
fn block_has_super_call(block : @ast.TsBlock) -> Bool {
  block.stmts.iter().any(stmt_has_super_call)
}

///|
fn stmt_has_super_call(stmt : @ast.TsStmt) -> Bool {
  match stmt {
    Expr(e) => expr_has_super_call(e)
    If(_, then_b, else_b) =>
      block_has_super_call(then_b) ||
      (match else_b {
        Some(eb) => block_has_super_call(eb)
        None => false
      })
    Try(b, _, cb, fb) =>
      block_has_super_call(b) ||
      (match cb {
        Some(cb2) => block_has_super_call(cb2)
        None => false
      }) ||
      (match fb {
        Some(fb2) => block_has_super_call(fb2)
        None => false
      })
    Block(b) => block_has_super_call(b)
    Label(_, s) => stmt_has_super_call(s)
    _ => false
  }
}

///|
fn expr_has_super_call(expr : @ast.TsExpr) -> Bool {
  match expr {
    Call("super", _) | CallExpr(@ast.TsExpr::Var("super"), _) => true
    Seq(a, b) => expr_has_super_call(a) || expr_has_super_call(b)
    Cond(c, t, e) =>
      expr_has_super_call(c) || expr_has_super_call(t) || expr_has_super_call(e)
    BinOp(_, a, b) => expr_has_super_call(a) || expr_has_super_call(b)
    _ => false
  }
}

///|
// Inject `assigns` after every `super(...)` call in a block, recursively.
fn inject_assigns_after_super_in_block(
  block : @ast.TsBlock,
  assigns : Array[@ast.TsStmt],
) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    let expanded = inject_assigns_after_super_in_stmt(s, assigns)
    for es in expanded {
      stmts.push(es)
    }
  }
  { stmts, stmt_positions: [] }
}

///|
// Returns a list of statements that replace `stmt`, with `assigns` injected
// after any `super(...)` call (top-level or nested in if/try/block).
fn inject_assigns_after_super_in_stmt(
  stmt : @ast.TsStmt,
  assigns : Array[@ast.TsStmt],
) -> Array[@ast.TsStmt] {
  match stmt {
    Expr(e) if expr_has_super_call(e) => {
      let out = [stmt]
      for a in assigns {
        out.push(a)
      }
      out
    }
    If(cond, then_b, else_b) if stmt_has_super_call(stmt) => {
      let new_then = if block_has_super_call(then_b) {
        inject_assigns_after_super_in_block(then_b, assigns)
      } else {
        then_b
      }
      let new_else = match else_b {
        Some(eb) if block_has_super_call(eb) =>
          Some(inject_assigns_after_super_in_block(eb, assigns))
        x => x
      }
      [If(cond, new_then, new_else)]
    }
    Try(b, handler, cb, fb) if stmt_has_super_call(stmt) => {
      let new_b = if block_has_super_call(b) {
        inject_assigns_after_super_in_block(b, assigns)
      } else {
        b
      }
      let new_cb = match cb {
        Some(cb2) if block_has_super_call(cb2) =>
          Some(inject_assigns_after_super_in_block(cb2, assigns))
        x => x
      }
      let new_fb = match fb {
        Some(fb2) if block_has_super_call(fb2) =>
          Some(inject_assigns_after_super_in_block(fb2, assigns))
        x => x
      }
      [Try(new_b, handler, new_cb, new_fb)]
    }
    Block(b) if block_has_super_call(b) =>
      [Block(inject_assigns_after_super_in_block(b, assigns))]
    Label(lbl, s) if stmt_has_super_call(s) => {
      let expanded = inject_assigns_after_super_in_stmt(s, assigns)
      match expanded {
        [single] => [Label(lbl, single)]
        _ => {
          let out = []
          for es in expanded {
            out.push(es)
          }
          out
        }
      }
    }
    _ => [stmt]
  }
}

///|
// Skip a decorator (`@expr` or `@expr(args)`) precisely, matching only the
// decorator expression itself and not anything that follows it on the same
// line. The grammar we accept:
//   Decorator ::= '@' DecoratorMemberExpression Arguments?
//   DecoratorMemberExpression ::= '(' Expression ')'
//                              | IdentifierReference ('.' IdentifierName)*
fn Parser::skip_decorator(self : Parser) -> Unit {
  try self.parse_decorator_expr() catch {
    _ => ()
  } noraise {
    Some(expr) => self.pending_decorators.push(expr)
    None => ()
  }
}

///|
/// Parse a single `@expr` decorator and return its expression form so
/// the caller can attach it to the next declaration. Mirrors the
/// shape of `skip_decorator` but builds a `TsExpr` instead of
/// discarding tokens. Returns `None` when the `@` isn't followed by a
/// recognized decorator head — keeps the existing permissive
/// recovery.
fn Parser::parse_decorator_expr(self : Parser) -> @ast.TsExpr? raise ParseError {
  let _ = self.match_(At)
  let head : @ast.TsExpr = match self.peek().kind {
    LParen => {
      // `@(expr)` form. Use the standard parenthesized-expression
      // parser so the captured expression is faithful.
      let _ = self.advance()
      let inner = self.parse_assignment()
      let _ = self.expect(RParen)
      inner
    }
    Ident(_) => {
      let name = self.parse_binding_ident()
      let mut expr : @ast.TsExpr = Var(name)
      // Member access chain `@a.b.c`.
      while self.check(Dot) {
        let _ = self.advance()
        match self.peek().kind {
          Ident(prop) => {
            let _ = self.advance()
            expr = PropAccess(expr, prop)
          }
          _ => break
        }
      }
      expr
    }
    _ => return None
  }
  // Optional call form `@a(b, c)`.
  if self.check(LParen) {
    let _ = self.advance()
    let args : Array[@ast.TsExpr] = []
    if !self.check(RParen) {
      args.push(self.parse_assignment())
      while self.match_(Comma) {
        if self.check(RParen) {
          break
        }
        args.push(self.parse_assignment())
      }
    }
    let _ = self.expect(RParen)
    return Some(CallExpr(head, args))
  }
  Some(head)
}

///|
/// Drain any decorators accumulated via `skip_decorator` since the
/// last drain. Class parsers call this just before constructing the
/// `TsClassDecl` so the decorators end up on the right declaration.
fn Parser::take_pending_decorators(self : Parser) -> Array[@ast.TsExpr] {
  let out : Array[@ast.TsExpr] = []
  for d in self.pending_decorators {
    out.push(d)
  }
  self.pending_decorators.clear()
  out
}

///|
fn Parser::inject_instance_field_assigns(
  self : Parser,
  func : @ast.TsFunc,
  assigns : Array[@ast.TsStmt],
  base : String?,
) -> @ast.TsFunc {
  if assigns.length() == 0 {
    return func
  }
  let mut new_stmts : Array[@ast.TsStmt] = []
  let mut inserted = false
  if base is Some(_) {
    for stmt in func.body.stmts {
      new_stmts.push(stmt)
      if !inserted && self.is_super_call_stmt(stmt) {
        for assign in assigns {
          new_stmts.push(assign)
        }
        inserted = true
      }
    }
    if !inserted {
      // No top-level super() found. Try deep injection (super inside if/try).
      // Only fall back to prepending if no super call exists anywhere.
      if block_has_super_call(func.body) {
        new_stmts = inject_assigns_after_super_in_block(func.body, assigns).stmts
      } else {
        let combined : Array[@ast.TsStmt] = []
        for assign in assigns {
          combined.push(assign)
        }
        for stmt in func.body.stmts {
          combined.push(stmt)
        }
        new_stmts = combined
      }
    }
  } else {
    for assign in assigns {
      new_stmts.push(assign)
    }
    for stmt in func.body.stmts {
      new_stmts.push(stmt)
    }
  }
  {
    name: func.name,
    type_params: func.type_params,
    params: func.params,
    return_type: func.return_type,
    body: { stmts: new_stmts, stmt_positions: [] },
    const_type_params: [],
    is_generator: func.is_generator,
    is_async: func.is_async,
  }
}

///|
fn Parser::parse_class_body(
  self : Parser,
) -> (@ast.TsFunc?, Array[ClassElement], Array[String], Array[String]) raise ParseError {
  let _ = self.expect(LBrace)
  // Class body is implicitly strict mode
  let prev_strict = self.in_strict
  self.in_strict = true
  let mut ctor : @ast.TsFunc? = None
  let elements : Array[ClassElement] = []
  // Names declared `private` / `protected`, collected so the class decl
  // can expose member visibility to the checker (TS2341 / TS2445).
  let private_members : Array[String] = []
  let protected_members : Array[String] = []
  while !self.check(RBrace) && !self.check(Eof) {
    while self.check(At) {
      self.skip_decorator()
    }
    if self.match_(Semicolon) {
      continue
    }
    let mut is_static = false
    let mut is_async_method = false
    let mut is_readonly_field = false
    let mut has_modifier = true
    let mut parsed_static_block = false
    let mut visibility = "public"
    while has_modifier {
      has_modifier = false
      match self.peek().kind {
        Ident(n) if n == "static" =>
          if self.can_consume_class_modifier() {
            let _ = self.advance()
            is_static = true
            has_modifier = true
            // Check for static initialization block: static { ... }
            if self.check(LBrace) {
              let block = self.parse_block()
              elements.push(StaticBlock(block))
              parsed_static_block = true
              break // Exit inner loop, then continue outer loop
            }
          }
        Ident(n) if n == "async" =>
          if self.can_consume_class_modifier() {
            let _ = self.advance()
            is_async_method = true
            has_modifier = true
          }
        Ident(n) if n == "readonly" =>
          if self.can_consume_class_modifier() {
            let _ = self.advance()
            is_readonly_field = true
            has_modifier = true
          }
        Ident(n) if n == "public" ||
          n == "private" ||
          n == "protected" ||
          n == "abstract" ||
          n == "override" ||
          n == "declare" ||
          n == "accessor" =>
          if self.can_consume_class_modifier() {
            let _ = self.advance()
            has_modifier = true
            if n == "private" || n == "protected" {
              visibility = n
            }
          }
        Declare => {
          let _ = self.advance()
          has_modifier = true
        }
        _ => ()
      }
    }
    if parsed_static_block {
      continue // Continue to next class element
    }
    if self.try_skip_class_index_signature() {
      elements.push(IndexSig)
      continue
    }
    let mut accessor_kind : String? = None
    match self.peek().kind {
      Ident(n) if (n == "get" || n == "set") &&
        self.peek_at(1).kind != LParen &&
        self.peek_at(1).kind != Lt &&
        self.peek_at(1).kind != Colon &&
        // `class C { get; }` declares an uninitialized field named
        // `get`, not a get-accessor. Same for `set;`, `get = …;`,
        // `set, …`. The accessor form REQUIRES a method body, so
        // anything that looks like a field-decl terminator means
        // we should treat `get` / `set` as an identifier.
        self.peek_at(1).kind != Semicolon &&
        self.peek_at(1).kind != Eq &&
        self.peek_at(1).kind != Comma &&
        self.peek_at(1).kind != RBrace => {
        let _ = self.advance()
        accessor_kind = Some(n)
      }
      _ => ()
    }
    let is_generator = self.match_(Star)
    let key = self.parse_class_method_key()
    let method_name = class_key_name(key)
    if method_name != "<computed>" {
      if visibility == "private" {
        private_members.push(method_name)
      } else if visibility == "protected" {
        protected_members.push(method_name)
      }
    }
    let is_optional = self.match_(Question)
    let has_definite_assertion = self.match_(Bang)
    let mut local_type_param_bound_len = self.local_type_param_bounds.length()
    let mut method_type_param_names : Array[String] = []
    if self.check(Lt) {
      let (names, type_param_bounds) = self.parse_type_param_names_and_bounds()
      method_type_param_names = names
      local_type_param_bound_len = self.push_local_type_param_bounds(
        type_param_bounds,
      )
    }
    let is_getter_without_parens = match accessor_kind {
      Some(kind) => kind == "get" && !self.check(LParen)
      None => false
    }
    if self.check(LParen) || is_getter_without_parens {
      // Push a fresh "parameter property" scope when parsing a
      // constructor — `parse_param` records `public x` / `private y`
      // names there so we can synthesize `this.x = x` afterwards.
      // Non-constructor methods leave the stack untouched (any
      // accidental modifier on a non-ctor param would be a TS
      // error the checker reports later).
      let is_constructor_method = key is Name("constructor")
      if is_constructor_method {
        self.param_property_scopes.push([])
      }
      let params = if self.check(LParen) {
        let _ = self.expect(LParen)
        let params = self.parse_params()
        let _ = self.expect(RParen)
        params
      } else {
        []
      }
      let param_props : Array[(String, Bool, String)] = if is_constructor_method {
        let last = self.param_property_scopes.length() - 1
        let collected = self.param_property_scopes[last]
        let _ = self.param_property_scopes.pop()
        collected
      } else {
        []
      }
      let return_type = if self.check(Colon) {
        let _ = self.advance()
        self.parse_type()
      } else {
        Any
      }
      let body = if self.match_(Semicolon) {
        @ast.TsBlock::{ stmts: [], stmt_positions: [] }
      } else if !self.check(LBrace) {
        // Overload signature with no body and no trailing `;` (relying on
        // ASI) — e.g. `constructor(y: any)` followed on the next line by the
        // implementation `constructor(x: number) {}`. Treat it as a bodyless
        // signature; we don't enforce overload/implementation pairing.
        @ast.TsBlock::{ stmts: [], stmt_positions: [] }
      } else {
        // Save and set function context for method body
        let prev_generator = self.in_generator
        let prev_function = self.in_function
        if is_generator {
          self.in_generator = true
        }
        self.in_function = true
        let body = self.parse_block()
        self.in_generator = prev_generator
        self.in_function = prev_function
        body
      }
      self.restore_local_type_param_bounds(local_type_param_bound_len)
      // Inject `this.name = name` assigns for every parameter
      // property at the TOP of the constructor body — after `super(…)`
      // when there is one. Vanilla TS semantics.
      let body = if param_props.length() > 0 {
        let new_stmts : Array[@ast.TsStmt] = []
        let mut super_inserted = false
        for s in body.stmts {
          new_stmts.push(s)
          if !super_inserted && self.is_super_call_stmt(s) {
            for pp in param_props {
              new_stmts.push(
                PropAssign(
                  @ast.TsExpr::Var("this"),
                  pp.0,
                  @ast.TsExpr::Var(pp.0),
                ),
              )
            }
            super_inserted = true
          }
        }
        if !super_inserted {
          let prepended : Array[@ast.TsStmt] = []
          for pp in param_props {
            prepended.push(
              PropAssign(@ast.TsExpr::Var("this"), pp.0, @ast.TsExpr::Var(pp.0)),
            )
          }
          for s in new_stmts {
            prepended.push(s)
          }
          @ast.TsBlock::{ stmts: prepended, stmt_positions: [] }
        } else {
          @ast.TsBlock::{ stmts: new_stmts, stmt_positions: [] }
        }
      } else {
        body
      }
      let func : @ast.TsFunc = {
        name: method_name,
        type_params: method_type_param_names,
        const_type_params: [],
        params,
        return_type,
        body,
        is_generator,
        is_async: is_async_method,
      }
      if accessor_kind is None && key is Name("constructor") && !is_static {
        ctor = Some(func)
        // Materialize TS "parameter properties" (`constructor(readonly x:
        // T)`) as real instance fields so the checker can see them — this
        // makes `new C(...).x` resolve and lets the readonly assignment
        // check (TS2540) fire. The field carries the `readonly` modifier
        // captured during param parsing; `init` is `None` since the value
        // flows in through the synthesized `this.x = x` assign (the class
        // has a constructor, so TS2564 already skips it).
        for pp in param_props {
          let (pp_name, pp_readonly, pp_visibility) = pp
          let mut pp_type : @ast.TsType = Any
          for p in func.params {
            if p.name == pp_name {
              pp_type = p.type_
              break
            }
          }
          elements.push(
            Field(false, Name(pp_name), pp_type, None, pp_readonly, false),
          )
          // A `private` / `protected` parameter property contributes the
          // same accessibility as a normal member declaration.
          if pp_visibility == "private" {
            private_members.push(pp_name)
          } else if pp_visibility == "protected" {
            protected_members.push(pp_name)
          }
        }
      } else {
        elements.push(Method(is_static, key, accessor_kind, func))
      }
    } else {
      self.restore_local_type_param_bounds(local_type_param_bound_len)
      let field_type = if self.match_(Colon) {
        self.parse_type()
      } else {
        @ast.TsType::Any
      }
      let field_type = if is_optional {
        wrap_optional_ts_type(field_type)
      } else {
        field_type
      }
      let init : @ast.TsExpr? = if self.match_(Eq) {
        Some(self.parse_assignment())
      } else {
        None
      }
      let _ = self.match_(Semicolon)
      elements.push(
        Field(
          is_static, key, field_type, init, is_readonly_field, has_definite_assertion,
        ),
      )
    }
  }
  let _ = self.expect(RBrace)
  self.in_strict = prev_strict
  (ctor, elements, private_members, protected_members)
}

///|
fn Parser::parse_class_stub(self : Parser) -> @ast.TsExpr raise ParseError {
  self.last_runtime_class_decl = None
  let _ = self.expect(Class)
  let mut class_name = ""
  let _ = match self.peek().kind {
    Ident(n) if n != "implements" => {
      class_name = n
      self.advance()
    }
    _ => { kind: Eof, pos: 0, has_newline_before: false }
  }
  let mut class_type_params : Array[String] = []
  let mut class_type_param_bound_len = self.local_type_param_bounds.length()
  if self.check(Lt) {
    let (names, type_param_bounds) = self.parse_type_param_names_and_bounds()
    class_type_params = names
    class_type_param_bound_len = self.push_local_type_param_bounds(
      type_param_bounds,
    )
  }
  let mut base : String? = None
  if self.match_(Extends) {
    base = Some(self.parse_class_base_name())
    if self.check(Lt) {
      self.skip_type_args()
    }
  }
  if self.match_ident("implements") {
    while !self.check(LBrace) && !self.check(Eof) {
      let _ = self.advance()
    }
  }
  // Generate unique brand ID for private fields
  let brand_id = self.class_id
  self.class_id += 1
  let brand = "__private_brand__" + brand_id.to_string()
  let prev_brand = self.current_class_brand
  self.current_class_brand = Some(brand)
  let (ctor_opt, elements, private_members, protected_members) = self.parse_class_body()
  self.current_class_brand = prev_brand
  self.restore_local_type_param_bounds(class_type_param_bound_len)
  // Self-extending classes (`class C extends C {}`) intentionally
  // throw at evaluation time per ES spec; preserve that with a
  // tiny IIFE.
  match base {
    Some(base_name) =>
      if class_name.length() > 0 && base_name == class_name {
        let throw_expr = @ast.TsExpr::Call("ReferenceError", [])
        let throw_body : @ast.TsBlock = {
          stmts: [Throw(throw_expr)],
          stmt_positions: [],
        }
        return CallExpr(
          @ast.TsExpr::FuncExpr(@ast.TsFunc::{
            type_params: [],
            name: "<class>",
            params: [],
            return_type: @ast.TsType::Any,
            body: throw_body,
            const_type_params: [],
            is_generator: false,
            is_async: false,
          }),
          [],
        )
      }
    None => ()
  }
  // Class expression with `extends Base` — produce a native
  // `class … extends … { … }` rather than the IIFE desugar (whose
  // `super(…)` calls would land outside a real class body).
  match base {
    Some(base_name) => {
      let runtime_decl = build_runtime_class_decl(
        class_name, class_type_params, ctor_opt, elements, false, private_members,
        protected_members,
      )
      let pending_base_expr = self.pending_class_base_expr
      self.pending_class_base_expr = None
      let decorated : @ast.TsClassDecl = {
        ..runtime_decl,
        base_names: [base_name],
        base_expr: pending_base_expr,
        decorators: self.take_pending_decorators(),
        is_declare: false,
      }
      self.last_runtime_class_decl = Some(decorated)
      // Add field initializers to the constructor body so `class
      // … extends X { y = 2; constructor() {…} }` doesn't lose
      // its non-static field defaults.
      let field_assigns : Array[@ast.TsStmt] = []
      for element in elements {
        match element {
          Field(is_static, Name(field_name), _, Some(init), _, _) =>
            if !is_static {
              field_assigns.push(
                PropAssign(@ast.TsExpr::Var("this"), field_name, init),
              )
            }
          _ => ()
        }
      }
      let ctor_func : @ast.TsFunc? = match ctor_opt {
        Some(func) =>
          if field_assigns.length() > 0 {
            Some(
              self.inject_instance_field_assigns(
                func,
                field_assigns,
                Some(base_name),
              ),
            )
          } else {
            Some(func)
          }
        None =>
          if field_assigns.length() > 0 {
            let rest_name = "__super_args__"
            let body_stmts : Array[@ast.TsStmt] = [
              Expr(
                Call("super", [@ast.TsExpr::Spread(@ast.TsExpr::Var(rest_name))]),
              ),
            ]
            for a in field_assigns {
              body_stmts.push(a)
            }
            Some(@ast.TsFunc::{
              name: "constructor",
              type_params: [],
              params: [
                {
                  name: rest_name,
                  binding: Some(@ast.TsBinding::Ident(rest_name)),
                  is_rest: true,
                  type_: @ast.TsType::Any,
                  default: None,
                },
              ],
              return_type: @ast.TsType::Any,
              body: { stmts: body_stmts, stmt_positions: [] },
              const_type_params: [],
              is_generator: false,
              is_async: false,
            })
          } else {
            None
          }
      }
      // Static field initializers: stash them on the AST so emit
      // restores them as `static foo = init;` inside the class body
      // (ES2022 native form). Avoids wrapping the class expression
      // in an IIFE or the surrounding stmt in a `Block` — both of
      // which previously broke scope: the IIFE's `this` isn't the
      // class, and the Block trapped the class declaration itself.
      let static_field_inits : Array[(String, @ast.TsExpr)] = []
      let instance_field_inits : Array[(String, @ast.TsExpr)] = []
      for element in elements {
        match element {
          Field(true, Name(static_name), _, Some(init), _, _) =>
            static_field_inits.push((static_name, init))
          Field(false, Name(field_name), _, Some(init), _, _) =>
            if is_public_runtime_class_member_name(field_name) {
              instance_field_inits.push((field_name, init))
            }
          _ => ()
        }
      }
      let decorated_with_statics : @ast.TsClassDecl = {
        ..decorated,
        static_field_inits,
        instance_field_inits,
      }
      return NativeClassExpr(decorated_with_statics, ctor_func)
    }
    None => ()
  }
  // (unused) Legacy synthetic-name + IIFE path retained for context — see
  // commit history; the active path above stashes static fields on the
  // AST and lets emit restore them in-body.
  // `<anon>` was the historical sentinel for "this class expression
  // has no source-level name". The angle brackets aren't valid JS
  // identifier syntax, so the emitter rejects them and writes
  // `let <anon> = …` literally, producing invalid output. Use a
  // legal-but-reserved-looking name instead; the class-desugar IIFE
  // only references it internally, so a stable token is enough.
  let tmp_name = if class_name == "" { "_anon" } else { class_name }
  let runtime_decl = build_runtime_class_decl(
    if class_name == "" {
      "<class>"
    } else {
      class_name
    },
    class_type_params,
    ctor_opt,
    elements,
    false,
    private_members,
    protected_members,
  )
  // Attach any decorators accumulated via `skip_decorator` before this
  // class statement.
  let decorated : @ast.TsClassDecl = {
    name: runtime_decl.name,
    type_params: runtime_decl.type_params,
    base_names: runtime_decl.base_names,
    base_expr: runtime_decl.base_expr,
    static_field_inits: runtime_decl.static_field_inits,
    instance_field_inits: runtime_decl.instance_field_inits,
    constructor_params: runtime_decl.constructor_params,
    properties: runtime_decl.properties,
    methods: runtime_decl.methods,
    index_signatures: runtime_decl.index_signatures,
    is_abstract: runtime_decl.is_abstract,
    is_constructible: runtime_decl.is_constructible,
    decorators: self.take_pending_decorators(),
    is_declare: false,
    private_members: runtime_decl.private_members,
    protected_members: runtime_decl.protected_members,
  }
  self.last_runtime_class_decl = Some(decorated)
  let instance_assigns : Array[@ast.TsStmt] = []
  let has_instance_private = has_instance_private_elements(elements)
  let has_static_private = has_static_private_elements(elements)
  // Add brand marking for instance private field access control
  if has_instance_private {
    instance_assigns.push(
      PropAssign(@ast.TsExpr::Var("this"), brand, @ast.TsExpr::BoolLit(true)),
    )
  }
  let key_temps : Array[String?] = [] // Temp var names for ALL elements' computed keys
  let key_init_stmts : Array[@ast.TsStmt] = [] // Initialization statements for computed keys
  // First pass: collect all computed keys and generate temp variables
  for element in elements {
    match element {
      Field(_, key, _, _, _, _) | Method(_, key, _, _) =>
        match key {
          Name(_) => key_temps.push(None)
          Computed(key_expr) => {
            let temp_name = "__class_key_" + self.class_key_counter.to_string()
            self.class_key_counter += 1
            key_temps.push(Some(temp_name))
            // Generate: let __class_key_N = key_expr;
            key_init_stmts.push(
              Let(@ast.TsBinding::Ident(temp_name), Any, key_expr),
            )
          }
        }
      StaticBlock(_) => key_temps.push(None) // Placeholder to keep indices aligned
      IndexSig => key_temps.push(None)
    }
  }

  // Second pass: generate instance field assignments (for non-static fields)
  for idx, element in elements {
    match element {
      Field(is_static, key, _, init_opt, _, _) =>
        if !is_static {
          let init = match init_opt {
            Some(expr) => expr
            None => @ast.TsExpr::Var("undefined")
          }
          match key {
            Name(field_name) => {
              // Mangle private field names with brand for access control
              let actual_name = mangle_private_name(field_name, brand)
              instance_assigns.push(
                PropAssign(@ast.TsExpr::Var("this"), actual_name, init),
              )
            }
            Computed(_) =>
              match key_temps[idx] {
                Some(temp_name) =>
                  instance_assigns.push(
                    IndexAssign(
                      @ast.TsExpr::Var("this"),
                      @ast.TsExpr::Var(temp_name),
                      init,
                    ),
                  )
                None => ()
              }
          }
        }
      _ => ()
    }
  }
  let stmts : Array[@ast.TsStmt] = []
  // Class body is implicitly strict mode
  stmts.push(Expr(@ast.TsExpr::StringLit("use strict")))
  // Define __super_proto early for static field arrow functions to capture
  let super_proto_expr = match base {
    Some(base_name) => @ast.TsExpr::Var(base_name)
    None => @ast.TsExpr::PropAccess(@ast.TsExpr::Var("Function"), "prototype")
  }
  stmts.push(Let(@ast.TsBinding::Ident("__super_proto"), Any, super_proto_expr))
  // Add computed key initializations first (in order of appearance)
  for stmt in key_init_stmts {
    stmts.push(stmt)
  }
  let ctor_func = match ctor_opt {
    Some(func) => func
    None =>
      match base {
        Some(_) => {
          let rest_name = "__super_args__"
          let rest_param : @ast.TsParam = {
            name: rest_name,
            binding: Some(@ast.TsBinding::Ident(rest_name)),
            is_rest: true,
            type_: Any,
            default: None,
          }
          let empty_body : @ast.TsBlock = {
            stmts: [Expr(Call("super", [@ast.TsExpr::Var(rest_name)]))],
            stmt_positions: [],
          }
          {
            name: tmp_name,
            type_params: [],
            params: [rest_param],
            return_type: Any,
            body: empty_body,
            const_type_params: [],
            is_generator: false,
            is_async: false,
          }
        }
        None => {
          let empty_body : @ast.TsBlock = { stmts: [], stmt_positions: [] }
          {
            name: tmp_name,
            type_params: [],
            params: [],
            return_type: Any,
            body: empty_body,
            const_type_params: [],
            is_generator: false,
            is_async: false,
          }
        }
      }
  }
  let ctor_func = self.inject_instance_field_assigns(
    ctor_func, instance_assigns, base,
  )
  stmts.push(
    Let(@ast.TsBinding::Ident(tmp_name), Any, @ast.TsExpr::FuncExpr(ctor_func)),
  )
  // Add brand to class constructor for static private members
  if has_static_private {
    stmts.push(
      PropAssign(@ast.TsExpr::Var(tmp_name), brand, @ast.TsExpr::BoolLit(true)),
    )
  }
  let proto_expr = @ast.TsExpr::PropAccess(
    @ast.TsExpr::Var(tmp_name),
    "prototype",
  )
  match base {
    Some(base_name) => {
      let base_proto = @ast.TsExpr::PropAccess(
        @ast.TsExpr::Var(base_name),
        "prototype",
      )
      stmts.push(
        PropAssign(
          @ast.TsExpr::Var(tmp_name),
          "__super_ctor",
          @ast.TsExpr::Var(base_name),
        ),
      )
      stmts.push(
        PropAssign(@ast.TsExpr::Var(tmp_name), "__super_proto", base_proto),
      )
      stmts.push(
        PropAssign(
          @ast.TsExpr::Var(tmp_name),
          "__proto__",
          @ast.TsExpr::Var(base_name),
        ),
      )
      stmts.push(PropAssign(proto_expr, "__proto__", base_proto))
    }
    None => {
      // Even without extends, super.xxx in constructor refers to Object.prototype
      let object_proto = @ast.TsExpr::PropAccess(
        @ast.TsExpr::Var("Object"),
        "prototype",
      )
      stmts.push(
        PropAssign(@ast.TsExpr::Var(tmp_name), "__super_proto", object_proto),
      )
    }
  }
  for idx, element in elements {
    match element {
      Method(is_static, key, accessor_kind, func) => {
        let target = if is_static {
          @ast.TsExpr::Var(tmp_name)
        } else {
          proto_expr
        }
        let func_expr = @ast.TsExpr::FuncExpr(func)
        match key {
          Name(method_name) =>
            match accessor_kind {
              Some(kind) => {
                let prop_key = if kind == "get" {
                  "@@get:" + method_name
                } else {
                  "@@set:" + method_name
                }
                // For getter/setter with super, set __super_proto on the function
                let super_proto = if is_static {
                  // Static: super refers to parent class (or Function.prototype)
                  match base {
                    Some(base_name) => @ast.TsExpr::Var(base_name)
                    None =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var("Function"),
                        "prototype",
                      )
                  }
                } else {
                  // Instance: super refers to parent.prototype (or Object.prototype)
                  match base {
                    Some(base_name) =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var(base_name),
                        "prototype",
                      )
                    None =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var("Object"),
                        "prototype",
                      )
                  }
                }
                let accessor_tmp = "__" + kind + "_" + method_name
                stmts.push(
                  Let(@ast.TsBinding::Ident(accessor_tmp), Any, func_expr),
                )
                stmts.push(
                  PropAssign(
                    @ast.TsExpr::Var(accessor_tmp),
                    "__super_proto",
                    super_proto,
                  ),
                )
                stmts.push(
                  PropAssign(target, prop_key, @ast.TsExpr::Var(accessor_tmp)),
                )
              }
              None => {
                // The `@@define:` prefix the desugar used to attach
                // here was unused downstream — neither the checker
                // nor any transform actually inspects it, and the
                // emit-time stripper was a no-op once mangling
                // renamed the prefixed name. Use the raw method
                // name so property-mangling treats it like every
                // other prop and stays consistent across the
                // `prototype.method = …` assignment and any later
                // `prototype.method.something = …` chain.
                let prop_key = method_name
                // Set __super_proto for both instance and static methods
                let super_proto = if is_static {
                  // Static: super refers to parent class (or Function.prototype)
                  match base {
                    Some(base_name) => @ast.TsExpr::Var(base_name)
                    None =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var("Function"),
                        "prototype",
                      )
                  }
                } else {
                  // Instance: super refers to parent.prototype (or Object.prototype)
                  match base {
                    Some(base_name) =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var(base_name),
                        "prototype",
                      )
                    None =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var("Object"),
                        "prototype",
                      )
                  }
                }
                // For private methods, use temp var pattern to avoid brand check issues
                if method_name.contains("__#") {
                  let method_tmp = "__method_" + method_name
                  stmts.push(
                    Let(@ast.TsBinding::Ident(method_tmp), Any, func_expr),
                  )
                  stmts.push(
                    PropAssign(
                      @ast.TsExpr::Var(method_tmp),
                      "__super_proto",
                      super_proto,
                    ),
                  )
                  stmts.push(
                    PropAssign(target, prop_key, @ast.TsExpr::Var(method_tmp)),
                  )
                } else {
                  stmts.push(PropAssign(target, prop_key, func_expr))
                  let method_ref = @ast.TsExpr::PropAccess(target, method_name)
                  stmts.push(
                    PropAssign(method_ref, "__super_proto", super_proto),
                  )
                }
              }
            }
          Computed(_) => {
            // Use the pre-evaluated temp variable for the computed key
            let key_expr = match key_temps[idx] {
              Some(temp_name) => @ast.TsExpr::Var(temp_name)
              None => class_key_expr(key) // Fallback
            }
            let desc = match accessor_kind {
              Some(kind) => {
                let prop_key = if kind == "get" { "get" } else { "set" }
                @ast.TsExpr::ObjectLit([
                  (prop_key, func_expr),
                  ("enumerable", @ast.TsExpr::BoolLit(false)),
                  ("configurable", @ast.TsExpr::BoolLit(true)),
                ])
              }
              None =>
                @ast.TsExpr::ObjectLit([
                  ("value", func_expr),
                  ("writable", @ast.TsExpr::BoolLit(true)),
                  ("enumerable", @ast.TsExpr::BoolLit(false)),
                  ("configurable", @ast.TsExpr::BoolLit(true)),
                ])
            }
            let define_call = @ast.TsExpr::CallExpr(
              @ast.TsExpr::PropAccess(
                @ast.TsExpr::Var("Object"),
                "defineProperty",
              ),
              [target, key_expr, desc],
            )
            stmts.push(Expr(define_call))
          }
        }
      }
      Field(is_static, key, _, init_opt, _, _) => {
        let init = match init_opt {
          Some(expr) => expr
          None => @ast.TsExpr::Var("undefined")
        }
        if is_static {
          match key {
            Name(field_name) =>
              stmts.push(
                PropAssign(@ast.TsExpr::Var(tmp_name), field_name, init),
              )
            Computed(_) => {
              // Use the pre-evaluated temp variable for the computed key
              let key_expr = match key_temps[idx] {
                Some(temp_name) => @ast.TsExpr::Var(temp_name)
                None => class_key_expr(key) // Fallback
              }
              let desc = @ast.TsExpr::ObjectLit([
                ("value", init),
                ("writable", @ast.TsExpr::BoolLit(true)),
                ("enumerable", @ast.TsExpr::BoolLit(true)),
                ("configurable", @ast.TsExpr::BoolLit(true)),
              ])
              let define_call = @ast.TsExpr::CallExpr(
                @ast.TsExpr::PropAccess(
                  @ast.TsExpr::Var("Object"),
                  "defineProperty",
                ),
                [@ast.TsExpr::Var(tmp_name), key_expr, desc],
              )
              stmts.push(Expr(define_call))
            }
          }
        }
        // Note: non-static computed field keys are already handled in instance_assigns
      }
      StaticBlock(block) => {
        // Static initialization blocks run during class definition with `this` bound to the class
        // Generate: (function() { ...block... }).call(ClassName)
        let static_block_func = @ast.TsExpr::FuncExpr(@ast.TsFunc::{
          type_params: [],
          name: "",
          params: [],
          return_type: @ast.TsType::Any,
          body: block,
          const_type_params: [],
          is_generator: false,
          is_async: false,
        })
        let call_method = @ast.TsExpr::PropAccess(static_block_func, "call")
        let call_expr = @ast.TsExpr::CallExpr(call_method, [
          @ast.TsExpr::Var(tmp_name),
        ])
        stmts.push(Expr(call_expr))
      }
      IndexSig => ()
    }
  }
  stmts.push(Return(Some(@ast.TsExpr::Var(tmp_name))))
  CallExpr(
    @ast.TsExpr::FuncExpr(@ast.TsFunc::{
      type_params: [],
      name: "<class>",
      params: [],
      return_type: @ast.TsType::Any,
      body: @ast.TsBlock::{ stmts, stmt_positions: [] },
      const_type_params: [],
      is_generator: false,
      is_async: false,
    }),
    [],
  )
}

///|
fn Parser::parse_class_decl_with_abstract(
  self : Parser,
  is_abstract : Bool,
) -> @ast.TsStmt raise ParseError {
  self.last_runtime_class_decl = None
  let _ = self.expect(Class)
  let name = match self.advance().kind {
    Ident(n) => n
    _ => "<class>"
  }
  let mut class_type_params : Array[String] = []
  let mut class_type_param_bound_len = self.local_type_param_bounds.length()
  if self.check(Lt) {
    let (names, type_param_bounds) = self.parse_type_param_names_and_bounds()
    class_type_params = names
    class_type_param_bound_len = self.push_local_type_param_bounds(
      type_param_bounds,
    )
  }
  let mut base : String? = None
  if self.match_(Extends) {
    base = Some(self.parse_class_base_name())
    if self.check(Lt) {
      self.skip_type_args()
    }
  }
  if self.match_ident("implements") {
    while !self.check(LBrace) && !self.check(Eof) {
      let _ = self.advance()
    }
  }
  // Generate unique brand ID for private fields
  let brand_id = self.class_id
  self.class_id += 1
  let brand = "__private_brand__" + brand_id.to_string()
  let prev_brand = self.current_class_brand
  self.current_class_brand = Some(brand)
  let (ctor_opt, elements, private_members, protected_members) = self.parse_class_body()
  self.current_class_brand = prev_brand
  self.restore_local_type_param_bounds(class_type_param_bound_len)
  let runtime_decl = build_runtime_class_decl(
    name, class_type_params, ctor_opt, elements, is_abstract, private_members, protected_members,
  )
  self.last_runtime_class_decl = Some(runtime_decl)
  // When the class extends another class, the IIFE desugar below
  // produces a `super(…)` call outside a real class body — V8
  // rejects that as a SyntaxError. Bypass the desugar and emit
  // native `class … extends … { … }` instead. Modern engines
  // (Node 12+, ES2015 spec) handle the syntax directly; the IIFE
  // path is only retained for non-extending classes that still
  // round-trip through the original lowering.
  match base {
    Some(base_name) => {
      // Build per-field `this.x = init` assigns for non-static
      // fields with default values; this mirrors what the IIFE
      // path does via `instance_assigns`, but we splice them into
      // the constructor body directly so the class body looks
      // like idiomatic ES2022 syntax.
      let field_assigns : Array[@ast.TsStmt] = []
      for element in elements {
        match element {
          Field(is_static, Name(field_name), _, Some(init), _, _) =>
            if !is_static {
              field_assigns.push(
                PropAssign(@ast.TsExpr::Var("this"), field_name, init),
              )
            }
          _ => ()
        }
      }
      // Inject field assigns AFTER the super() call (or at the
      // start when there's no constructor). `inject_instance_field_assigns`
      // already handles the super-call-aware ordering.
      let merged_ctor = match ctor_opt {
        Some(func) =>
          if field_assigns.length() > 0 {
            self.inject_instance_field_assigns(
              func,
              field_assigns,
              Some(base_name),
            )
          } else {
            func
          }
        None =>
          if field_assigns.length() > 0 {
            // Synthesize a constructor body that forwards `...args`
            // to `super(...)` and then runs the field assigns.
            let rest_name = "__super_args__"
            let body_stmts : Array[@ast.TsStmt] = [
              Expr(
                Call("super", [@ast.TsExpr::Spread(@ast.TsExpr::Var(rest_name))]),
              ),
            ]
            for a in field_assigns {
              body_stmts.push(a)
            }
            @ast.TsFunc::{
              name: "constructor",
              type_params: [],
              params: [
                {
                  name: rest_name,
                  binding: Some(@ast.TsBinding::Ident(rest_name)),
                  is_rest: true,
                  type_: @ast.TsType::Any,
                  default: None,
                },
              ],
              return_type: @ast.TsType::Any,
              body: { stmts: body_stmts, stmt_positions: [] },
              const_type_params: [],
              is_generator: false,
              is_async: false,
            }
          } else {
            // No fields and no constructor — emit class with no
            // constructor; the default does the right thing
            // (`constructor(...args) { super(...args); }`).
            @ast.TsFunc::{
              name: "",
              type_params: [],
              params: [],
              return_type: @ast.TsType::Any,
              body: { stmts: [], stmt_positions: [] },
              const_type_params: [],
              is_generator: false,
              is_async: false,
            }
          }
      }
      let ctor_func : @ast.TsFunc? = if ctor_opt is None &&
        field_assigns.length() == 0 {
        None
      } else {
        Some(merged_ctor)
      }
      let pending_base_expr2 = self.pending_class_base_expr
      self.pending_class_base_expr = None
      let decorated : @ast.TsClassDecl = {
        ..runtime_decl,
        base_names: [base_name],
        base_expr: pending_base_expr2,
        decorators: self.take_pending_decorators(),
        is_declare: false,
      }
      // Static field initializers: stash them on the AST so the
      // emit pass restores them as `static foo = init;` inside the
      // class body. ES2022 classes accept the native form directly,
      // which keeps the class declaration at top-level (a wrapping
      // `Block` would trap the binding in block scope and break
      // forward references from sibling top-level code).
      let static_field_inits : Array[(String, @ast.TsExpr)] = []
      let instance_field_inits : Array[(String, @ast.TsExpr)] = []
      for element in elements {
        match element {
          Field(true, Name(static_name), _, Some(init), _, _) =>
            static_field_inits.push((static_name, init))
          Field(false, Name(field_name), _, Some(init), _, _) =>
            if is_public_runtime_class_member_name(field_name) {
              instance_field_inits.push((field_name, init))
            }
          _ => ()
        }
      }
      let decorated_with_statics : @ast.TsClassDecl = {
        ..decorated,
        static_field_inits,
        instance_field_inits,
      }
      // Re-publish the fully-built decl (with `base_names` / `base_expr` /
      // statics) so `take_last_runtime_class_decl` — used by the module
      // collector — sees the heritage clause. The earlier assignment at the
      // top of this function recorded only the base-less `runtime_decl`.
      self.last_runtime_class_decl = Some(decorated_with_statics)
      return NativeClassStmt(decorated_with_statics, ctor_func)
    }
    None => ()
  }
  let instance_assigns : Array[@ast.TsStmt] = []
  let has_instance_private = has_instance_private_elements(elements)
  let has_static_private = has_static_private_elements(elements)
  // Add brand marking for instance private field access control
  if has_instance_private {
    instance_assigns.push(
      PropAssign(@ast.TsExpr::Var("this"), brand, @ast.TsExpr::BoolLit(true)),
    )
  }
  let key_temps : Array[String?] = [] // Temp var names for ALL elements' computed keys
  let key_init_stmts : Array[@ast.TsStmt] = [] // Initialization statements for computed keys
  // First pass: collect all computed keys and generate temp variables
  for element in elements {
    match element {
      Field(_, key, _, _, _, _) | Method(_, key, _, _) =>
        match key {
          Name(_) => key_temps.push(None)
          Computed(key_expr) => {
            let temp_name = "__class_key_" + self.class_key_counter.to_string()
            self.class_key_counter += 1
            key_temps.push(Some(temp_name))
            // Generate: let __class_key_N = key_expr;
            key_init_stmts.push(
              Let(@ast.TsBinding::Ident(temp_name), Any, key_expr),
            )
          }
        }
      StaticBlock(_) => key_temps.push(None) // Placeholder to keep indices aligned
      IndexSig => key_temps.push(None)
    }
  }

  // Second pass: generate instance field assignments (for non-static fields)
  for idx, element in elements {
    match element {
      Field(is_static, key, _, init_opt, _, _) =>
        if !is_static {
          let init = match init_opt {
            Some(expr) => expr
            None => @ast.TsExpr::Var("undefined")
          }
          match key {
            Name(field_name) => {
              // Mangle private field names with brand for access control
              let actual_name = mangle_private_name(field_name, brand)
              instance_assigns.push(
                PropAssign(@ast.TsExpr::Var("this"), actual_name, init),
              )
            }
            Computed(_) =>
              match key_temps[idx] {
                Some(temp_name) =>
                  instance_assigns.push(
                    IndexAssign(
                      @ast.TsExpr::Var("this"),
                      @ast.TsExpr::Var(temp_name),
                      init,
                    ),
                  )
                None => ()
              }
          }
        }
      _ => ()
    }
  }
  let stmts : Array[@ast.TsStmt] = []
  // Class body is implicitly strict mode
  stmts.push(Expr(@ast.TsExpr::StringLit("use strict")))
  // Define __super_proto early for static field arrow functions to capture
  let super_proto_expr = match base {
    Some(base_name) => @ast.TsExpr::Var(base_name)
    None => @ast.TsExpr::PropAccess(@ast.TsExpr::Var("Function"), "prototype")
  }
  stmts.push(Let(@ast.TsBinding::Ident("__super_proto"), Any, super_proto_expr))
  // Add computed key initializations first (in order of appearance)
  for stmt in key_init_stmts {
    stmts.push(stmt)
  }
  match base {
    Some(base_name) =>
      if base_name == name {
        return Throw(@ast.TsExpr::Call("ReferenceError", []))
      }
    None => ()
  }
  let ctor_func = match ctor_opt {
    Some(func) => func
    None =>
      match base {
        Some(_) => {
          let rest_name = "__super_args__"
          let rest_param : @ast.TsParam = {
            name: rest_name,
            binding: Some(@ast.TsBinding::Ident(rest_name)),
            is_rest: true,
            type_: Any,
            default: None,
          }
          let empty_body : @ast.TsBlock = {
            stmts: [Expr(Call("super", [@ast.TsExpr::Var(rest_name)]))],
            stmt_positions: [],
          }
          {
            name,
            type_params: [],
            params: [rest_param],
            return_type: Any,
            body: empty_body,
            const_type_params: [],
            is_generator: false,
            is_async: false,
          }
        }
        None => {
          let empty_body : @ast.TsBlock = { stmts: [], stmt_positions: [] }
          {
            name,
            type_params: [],
            params: [],
            return_type: Any,
            body: empty_body,
            const_type_params: [],
            is_generator: false,
            is_async: false,
          }
        }
      }
  }
  let ctor_func = self.inject_instance_field_assigns(
    ctor_func, instance_assigns, base,
  )
  stmts.push(
    Let(@ast.TsBinding::Ident(name), Any, @ast.TsExpr::FuncExpr(ctor_func)),
  )
  // Add brand to class constructor for static private members
  if has_static_private {
    stmts.push(
      PropAssign(@ast.TsExpr::Var(name), brand, @ast.TsExpr::BoolLit(true)),
    )
  }
  let proto_expr = @ast.TsExpr::PropAccess(@ast.TsExpr::Var(name), "prototype")
  match base {
    Some(base_name) => {
      let base_proto = @ast.TsExpr::PropAccess(
        @ast.TsExpr::Var(base_name),
        "prototype",
      )
      stmts.push(
        PropAssign(
          @ast.TsExpr::Var(name),
          "__super_ctor",
          @ast.TsExpr::Var(base_name),
        ),
      )
      stmts.push(
        PropAssign(@ast.TsExpr::Var(name), "__super_proto", base_proto),
      )
      stmts.push(
        PropAssign(
          @ast.TsExpr::Var(name),
          "__proto__",
          @ast.TsExpr::Var(base_name),
        ),
      )
      stmts.push(PropAssign(proto_expr, "__proto__", base_proto))
    }
    None => {
      // Even without extends, super.xxx in constructor refers to Object.prototype
      let object_proto = @ast.TsExpr::PropAccess(
        @ast.TsExpr::Var("Object"),
        "prototype",
      )
      stmts.push(
        PropAssign(@ast.TsExpr::Var(name), "__super_proto", object_proto),
      )
    }
  }
  for idx, element in elements {
    match element {
      Method(is_static, key, accessor_kind, func) => {
        let target = if is_static { @ast.TsExpr::Var(name) } else { proto_expr }
        let func_expr = @ast.TsExpr::FuncExpr(func)
        match key {
          Name(method_name) =>
            match accessor_kind {
              Some(kind) => {
                let prop_key = if kind == "get" {
                  "@@get:" + method_name
                } else {
                  "@@set:" + method_name
                }
                // For getter/setter with super, set __super_proto on the function
                let super_proto = if is_static {
                  // Static: super refers to parent class (or Function.prototype)
                  match base {
                    Some(base_name) => @ast.TsExpr::Var(base_name)
                    None =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var("Function"),
                        "prototype",
                      )
                  }
                } else {
                  // Instance: super refers to parent.prototype (or Object.prototype)
                  match base {
                    Some(base_name) =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var(base_name),
                        "prototype",
                      )
                    None =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var("Object"),
                        "prototype",
                      )
                  }
                }
                let accessor_tmp = "__" + kind + "_" + method_name
                stmts.push(
                  Let(@ast.TsBinding::Ident(accessor_tmp), Any, func_expr),
                )
                stmts.push(
                  PropAssign(
                    @ast.TsExpr::Var(accessor_tmp),
                    "__super_proto",
                    super_proto,
                  ),
                )
                stmts.push(
                  PropAssign(target, prop_key, @ast.TsExpr::Var(accessor_tmp)),
                )
              }
              None => {
                // The `@@define:` prefix the desugar used to attach
                // here was unused downstream — neither the checker
                // nor any transform actually inspects it, and the
                // emit-time stripper was a no-op once mangling
                // renamed the prefixed name. Use the raw method
                // name so property-mangling treats it like every
                // other prop and stays consistent across the
                // `prototype.method = …` assignment and any later
                // `prototype.method.something = …` chain.
                let prop_key = method_name
                // Set __super_proto for both instance and static methods
                let super_proto = if is_static {
                  // Static: super refers to parent class (or Function.prototype)
                  match base {
                    Some(base_name) => @ast.TsExpr::Var(base_name)
                    None =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var("Function"),
                        "prototype",
                      )
                  }
                } else {
                  // Instance: super refers to parent.prototype (or Object.prototype)
                  match base {
                    Some(base_name) =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var(base_name),
                        "prototype",
                      )
                    None =>
                      @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var("Object"),
                        "prototype",
                      )
                  }
                }
                // For private methods, use temp var pattern to avoid brand check issues
                if method_name.contains("__#") {
                  let method_tmp = "__method_" + method_name
                  stmts.push(
                    Let(@ast.TsBinding::Ident(method_tmp), Any, func_expr),
                  )
                  stmts.push(
                    PropAssign(
                      @ast.TsExpr::Var(method_tmp),
                      "__super_proto",
                      super_proto,
                    ),
                  )
                  stmts.push(
                    PropAssign(target, prop_key, @ast.TsExpr::Var(method_tmp)),
                  )
                } else {
                  stmts.push(PropAssign(target, prop_key, func_expr))
                  let method_ref = @ast.TsExpr::PropAccess(target, method_name)
                  stmts.push(
                    PropAssign(method_ref, "__super_proto", super_proto),
                  )
                }
              }
            }
          Computed(_) => {
            // Use the pre-evaluated temp variable for the computed key
            let key_expr = match key_temps[idx] {
              Some(temp_name) => @ast.TsExpr::Var(temp_name)
              None => class_key_expr(key) // Fallback
            }
            let desc = match accessor_kind {
              Some(kind) => {
                let prop_key = if kind == "get" { "get" } else { "set" }
                @ast.TsExpr::ObjectLit([
                  (prop_key, func_expr),
                  ("enumerable", @ast.TsExpr::BoolLit(false)),
                  ("configurable", @ast.TsExpr::BoolLit(true)),
                ])
              }
              None =>
                @ast.TsExpr::ObjectLit([
                  ("value", func_expr),
                  ("writable", @ast.TsExpr::BoolLit(true)),
                  ("enumerable", @ast.TsExpr::BoolLit(false)),
                  ("configurable", @ast.TsExpr::BoolLit(true)),
                ])
            }
            let define_call = @ast.TsExpr::CallExpr(
              @ast.TsExpr::PropAccess(
                @ast.TsExpr::Var("Object"),
                "defineProperty",
              ),
              [target, key_expr, desc],
            )
            stmts.push(Expr(define_call))
          }
        }
      }
      Field(is_static, key, _, init_opt, _, _) => {
        let init = match init_opt {
          Some(expr) => expr
          None => @ast.TsExpr::Var("undefined")
        }
        if is_static {
          match key {
            Name(field_name) =>
              stmts.push(PropAssign(@ast.TsExpr::Var(name), field_name, init))
            Computed(_) => {
              // Use the pre-evaluated temp variable for the computed key
              let key_expr = match key_temps[idx] {
                Some(temp_name) => @ast.TsExpr::Var(temp_name)
                None => class_key_expr(key) // Fallback
              }
              let desc = @ast.TsExpr::ObjectLit([
                ("value", init),
                ("writable", @ast.TsExpr::BoolLit(true)),
                ("enumerable", @ast.TsExpr::BoolLit(true)),
                ("configurable", @ast.TsExpr::BoolLit(true)),
              ])
              let define_call = @ast.TsExpr::CallExpr(
                @ast.TsExpr::PropAccess(
                  @ast.TsExpr::Var("Object"),
                  "defineProperty",
                ),
                [@ast.TsExpr::Var(name), key_expr, desc],
              )
              stmts.push(Expr(define_call))
            }
          }
        }
        // Note: non-static computed field keys are already handled in instance_assigns
      }
      StaticBlock(block) => {
        // Static initialization blocks run during class definition with `this` bound to the class
        // Generate: (function() { ...block... }).call(ClassName)
        let static_block_func = @ast.TsExpr::FuncExpr(@ast.TsFunc::{
          type_params: [],
          name: "",
          params: [],
          return_type: @ast.TsType::Any,
          body: block,
          const_type_params: [],
          is_generator: false,
          is_async: false,
        })
        let call_method = @ast.TsExpr::PropAccess(static_block_func, "call")
        let call_expr = @ast.TsExpr::CallExpr(call_method, [
          @ast.TsExpr::Var(name),
        ])
        stmts.push(Expr(call_expr))
      }
      IndexSig => ()
    }
  }
  if stmts.length() == 1 {
    stmts[0]
  } else {
    // Use IIFE pattern to avoid scope issues with let
    // The first statement is always Let(name, ...) which we convert to internal temp
    // Then wrap everything in an IIFE that returns the class
    let internal_stmts : Array[@ast.TsStmt] = []
    for stmt in stmts {
      internal_stmts.push(stmt)
    }
    internal_stmts.push(Return(Some(@ast.TsExpr::Var(name))))
    let iife = @ast.TsExpr::CallExpr(
      @ast.TsExpr::FuncExpr(@ast.TsFunc::{
        type_params: [],
        name: "<class>",
        params: [],
        return_type: @ast.TsType::Any,
        body: @ast.TsBlock::{ stmts: internal_stmts, stmt_positions: [] },
        const_type_params: [],
        is_generator: false,
        is_async: false,
      }),
      [],
    )
    Let(@ast.TsBinding::Ident(name), Any, iife)
  }
}

///|
fn Parser::parse_class_decl(self : Parser) -> @ast.TsStmt raise ParseError {
  self.parse_class_decl_with_abstract(false)
}

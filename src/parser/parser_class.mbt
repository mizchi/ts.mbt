///|
priv enum ClassKey {
  Name(String)
  Computed(@ast.TsExpr)
}

///|
priv enum ClassElement {
  Method(Bool, ClassKey, String?, @ast.TsFunc)
  Field(Bool, ClassKey, @ast.TsType, @ast.TsExpr?)
  StaticBlock(@ast.TsBlock)
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
) -> @ast.TsClassDecl {
  let properties : Array[@ast.TsClassPropertyDecl] = []
  let methods : Array[@ast.TsClassMethodDecl] = []
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
      Field(is_static, Name(field_name), field_type, _) =>
        if is_public_runtime_class_member_name(field_name) {
          upsert_class_property(properties, {
            name: field_name,
            type_: field_type,
            is_static,
            is_readonly: false,
          })
        }
      Method(is_static, Name(method_name), accessor_kind, func) =>
        if is_public_runtime_class_member_name(method_name) {
          match accessor_kind {
            Some("get") =>
              upsert_class_property(properties, {
                name: method_name,
                type_: func.return_type,
                is_static,
                is_readonly: true,
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
              })
            }
            _ => {
              let params : Array[(String, @ast.TsType)] = []
              for index, param in func.params {
                params.push(
                  (runtime_class_param_name(param, index), param.type_),
                )
              }
              methods.push({
                name: method_name,
                type_params: [],
                type_param_bounds: [],
                params,
                return_type: func.return_type,
                is_static,
                body: if func.body.stmts.length() == 0 {
                  None
                } else {
                  Some(func.body)
                },
              })
            }
          }
        }
      _ => ()
    }
  }
  {
    name,
    type_params,
    base_names: [],
    constructor_params,
    properties,
    methods,
    index_signatures: [],
    is_abstract,
    is_constructible: !is_abstract,
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
      Field(is_static, Name(name), _, _)
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
      Field(is_static, Name(name), _, _)
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
    brand + "__" + name
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
  if self.check(LParen) {
    let _ = self.parse_expr()
    return "<expr-base>"
  }
  // `class C extends null { ... }` is valid TS — it creates a constructor
  // with `null` as its prototype, used as a no-prototype class.
  if self.check(Null) {
    let _ = self.advance()
    let _ = start
    return "<expr-base>"
  }
  // `class C extends class { ... } { ... }` — anonymous class expression as
  // the base. Delegate to the general expression parser; whatever it
  // produces collapses to the `<expr-base>` marker since we only need the
  // structural signal that an expression-shaped base was consumed.
  if self.check(Class) {
    let _ = self.parse_expr()
    let _ = start
    return "<expr-base>"
  }
  let mut full_name = match self.advance().kind {
    Ident(n) => n
    k => raise ParseError("Expected base class name, got \{k}")
  }
  while self.check(Dot) {
    let _ = self.advance()
    match self.advance().kind {
      Ident(n) => full_name = full_name + "." + n
      k => raise ParseError("Expected base class name, got \{k}")
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
    let _ = self.parse_expr()
    return "<expr-base>"
  }
  full_name
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
// Skip a decorator (`@expr` or `@expr(args)`) precisely, matching only the
// decorator expression itself and not anything that follows it on the same
// line. The grammar we accept:
//   Decorator ::= '@' DecoratorMemberExpression Arguments?
//   DecoratorMemberExpression ::= '(' Expression ')'
//                              | IdentifierReference ('.' IdentifierName)*
fn Parser::skip_decorator(self : Parser) -> Unit {
  let _ = self.match_(At)
  match self.peek().kind {
    LParen => {
      // Parenthesized expression form: `@(expr)`
      let _ = self.advance()
      let mut depth = 1
      while depth > 0 && !self.check(Eof) {
        match self.peek().kind {
          LParen => depth += 1
          RParen => depth -= 1
          _ => ()
        }
        let _ = self.advance()
      }
    }
    Ident(_) => {
      let _ = self.advance()
      // Member access chain `a.b.c`
      while self.check(Dot) {
        let _ = self.advance()
        match self.peek().kind {
          Ident(_) => {
            let _ = self.advance()
          }
          _ => break
        }
      }
    }
    _ => return
  }
  // Optional call arguments. Decorators may take a single Arguments list
  // (e.g. `@deco(arg1, arg2)`). No type arguments are valid here per TS
  // grammar, so we only consume `(...)`.
  if self.check(LParen) {
    let _ = self.advance()
    let mut paren_depth = 1
    while paren_depth > 0 && !self.check(Eof) {
      match self.peek().kind {
        LParen => paren_depth += 1
        RParen => paren_depth -= 1
        _ => ()
      }
      let _ = self.advance()
    }
  }
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
      let combined : Array[@ast.TsStmt] = []
      for assign in assigns {
        combined.push(assign)
      }
      for stmt in func.body.stmts {
        combined.push(stmt)
      }
      new_stmts = combined
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
    body: { stmts: new_stmts },
    is_generator: func.is_generator,
    is_async: func.is_async,
  }
}

///|
fn Parser::parse_class_body(
  self : Parser,
) -> (@ast.TsFunc?, Array[ClassElement]) raise ParseError {
  let _ = self.expect(LBrace)
  // Class body is implicitly strict mode
  let prev_strict = self.in_strict
  self.in_strict = true
  let mut ctor : @ast.TsFunc? = None
  let elements : Array[ClassElement] = []
  while !self.check(RBrace) && !self.check(Eof) {
    while self.check(At) {
      self.skip_decorator()
    }
    if self.match_(Semicolon) {
      continue
    }
    let mut is_static = false
    let mut is_async_method = false
    let mut has_modifier = true
    let mut parsed_static_block = false
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
        Ident(n) if n == "public" ||
          n == "private" ||
          n == "protected" ||
          n == "readonly" ||
          n == "abstract" ||
          n == "override" ||
          n == "declare" ||
          n == "accessor" =>
          if self.can_consume_class_modifier() {
            let _ = self.advance()
            has_modifier = true
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
      continue
    }
    let mut accessor_kind : String? = None
    match self.peek().kind {
      Ident(n) if (n == "get" || n == "set") &&
        self.peek_at(1).kind != LParen &&
        self.peek_at(1).kind != Lt &&
        self.peek_at(1).kind != Colon => {
        let _ = self.advance()
        accessor_kind = Some(n)
      }
      _ => ()
    }
    let is_generator = self.match_(Star)
    let key = self.parse_class_method_key()
    let method_name = class_key_name(key)
    let is_optional = self.match_(Question)
    let _ = self.match_(Bang)
    let mut local_type_param_bound_len = self.local_type_param_bounds.length()
    if self.check(Lt) {
      let (_, type_param_bounds) = self.parse_type_param_names_and_bounds()
      local_type_param_bound_len = self.push_local_type_param_bounds(
        type_param_bounds,
      )
    }
    let is_getter_without_parens = match accessor_kind {
      Some(kind) => kind == "get" && !self.check(LParen)
      None => false
    }
    if self.check(LParen) || is_getter_without_parens {
      let params = if self.check(LParen) {
        let _ = self.expect(LParen)
        let params = self.parse_params()
        let _ = self.expect(RParen)
        params
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
        @ast.TsBlock::{ stmts: [] }
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
      let func : @ast.TsFunc = {
        name: method_name,
        type_params: [],
        params,
        return_type,
        body,
        is_generator,
        is_async: is_async_method,
      }
      if accessor_kind is None && key is Name("constructor") && !is_static {
        ctor = Some(func)
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
      elements.push(Field(is_static, key, field_type, init))
    }
  }
  let _ = self.expect(RBrace)
  self.in_strict = prev_strict
  (ctor, elements)
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
  let (ctor_opt, elements) = self.parse_class_body()
  self.current_class_brand = prev_brand
  self.restore_local_type_param_bounds(class_type_param_bound_len)
  match base {
    Some(base_name) =>
      if class_name.length() > 0 && base_name == class_name {
        let throw_expr = @ast.TsExpr::Call("ReferenceError", [])
        let throw_body : @ast.TsBlock = { stmts: [Throw(throw_expr)] }
        return CallExpr(
          @ast.TsExpr::FuncExpr(@ast.TsFunc::{
            type_params: [],
            name: "<class>",
            params: [],
            return_type: @ast.TsType::Any,
            body: throw_body,
            is_generator: false,
            is_async: false,
          }),
          [],
        )
      }
    None => ()
  }
  let tmp_name = if class_name == "" { "<anon>" } else { class_name }
  self.last_runtime_class_decl = Some(
    build_runtime_class_decl(
      if class_name == "" {
        "<class>"
      } else {
        class_name
      },
      class_type_params,
      ctor_opt,
      elements,
      false,
    ),
  )
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
  let mut key_index = 0

  // First pass: collect all computed keys and generate temp variables
  for element in elements {
    match element {
      Field(_, key, _, _) | Method(_, key, _, _) =>
        match key {
          Name(_) => key_temps.push(None)
          Computed(key_expr) => {
            let temp_name = "__class_key_" + key_index.to_string()
            key_index += 1
            key_temps.push(Some(temp_name))
            // Generate: let __class_key_N = key_expr;
            key_init_stmts.push(
              Let(@ast.TsBinding::Ident(temp_name), Any, key_expr),
            )
          }
        }
      StaticBlock(_) => key_temps.push(None) // Placeholder to keep indices aligned
    }
  }

  // Second pass: generate instance field assignments (for non-static fields)
  for idx, element in elements {
    match element {
      Field(is_static, key, _, init_opt) =>
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
          }
          {
            name: tmp_name,
            type_params: [],
            params: [rest_param],
            return_type: Any,
            body: empty_body,
            is_generator: false,
            is_async: false,
          }
        }
        None => {
          let empty_body : @ast.TsBlock = { stmts: [] }
          {
            name: tmp_name,
            type_params: [],
            params: [],
            return_type: Any,
            body: empty_body,
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
                let prop_key = "@@define:" + method_name
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
      Field(is_static, key, _, init_opt) => {
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
          is_generator: false,
          is_async: false,
        })
        let call_method = @ast.TsExpr::PropAccess(static_block_func, "call")
        let call_expr = @ast.TsExpr::CallExpr(call_method, [
          @ast.TsExpr::Var(tmp_name),
        ])
        stmts.push(Expr(call_expr))
      }
    }
  }
  stmts.push(Return(Some(@ast.TsExpr::Var(tmp_name))))
  CallExpr(
    @ast.TsExpr::FuncExpr(@ast.TsFunc::{
      type_params: [],
      name: "<class>",
      params: [],
      return_type: @ast.TsType::Any,
      body: @ast.TsBlock::{ stmts, },
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
  let (ctor_opt, elements) = self.parse_class_body()
  self.current_class_brand = prev_brand
  self.restore_local_type_param_bounds(class_type_param_bound_len)
  self.last_runtime_class_decl = Some(
    build_runtime_class_decl(
      name, class_type_params, ctor_opt, elements, is_abstract,
    ),
  )
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
  let mut key_index = 0

  // First pass: collect all computed keys and generate temp variables
  for element in elements {
    match element {
      Field(_, key, _, _) | Method(_, key, _, _) =>
        match key {
          Name(_) => key_temps.push(None)
          Computed(key_expr) => {
            let temp_name = "__class_key_" + key_index.to_string()
            key_index += 1
            key_temps.push(Some(temp_name))
            // Generate: let __class_key_N = key_expr;
            key_init_stmts.push(
              Let(@ast.TsBinding::Ident(temp_name), Any, key_expr),
            )
          }
        }
      StaticBlock(_) => key_temps.push(None) // Placeholder to keep indices aligned
    }
  }

  // Second pass: generate instance field assignments (for non-static fields)
  for idx, element in elements {
    match element {
      Field(is_static, key, _, init_opt) =>
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
          }
          {
            name,
            type_params: [],
            params: [rest_param],
            return_type: Any,
            body: empty_body,
            is_generator: false,
            is_async: false,
          }
        }
        None => {
          let empty_body : @ast.TsBlock = { stmts: [] }
          {
            name,
            type_params: [],
            params: [],
            return_type: Any,
            body: empty_body,
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
                let prop_key = "@@define:" + method_name
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
      Field(is_static, key, _, init_opt) => {
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
          is_generator: false,
          is_async: false,
        })
        let call_method = @ast.TsExpr::PropAccess(static_block_func, "call")
        let call_expr = @ast.TsExpr::CallExpr(call_method, [
          @ast.TsExpr::Var(name),
        ])
        stmts.push(Expr(call_expr))
      }
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
        body: @ast.TsBlock::{ stmts: internal_stmts },
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

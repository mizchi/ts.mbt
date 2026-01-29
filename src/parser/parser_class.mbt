///|
fn Parser::parse_class_method_name(self : Parser) -> String raise ParseError {
  if self.match_(LBracket) {
    let key_expr = self.parse_assignment()
    let _ = self.expect(RBracket)
    return self.computed_key_name(key_expr)
  }
  match self.advance().kind {
    Ident(n) => n
    Str(s) => s
    Number(n) => "\{n}"
    Int(n) => "\{n}"
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
    k => raise ParseError("Expected method name, got \{k}")
  }
}

///|
fn Parser::computed_key_name(
  _self : Parser,
  key_expr : TsExpr,
) -> String {
  match key_expr {
    StringLit(s) => s
    IntLit(i) => i.to_string()
    NumberLit(n) => n.to_string()
    Var(name) => name
    PropAccess(Var("Symbol"), prop) => "@@" + prop
    _ => "<computed>"
  }
}

///|
fn Parser::is_super_call_stmt(_self : Parser, stmt : TsStmt) -> Bool {
  match stmt {
    Expr(Call("super", _)) => true
    Expr(CallExpr(Var("super"), _)) => true
    _ => false
  }
}

///|
fn Parser::make_field_assign_stmt(
  _self : Parser,
  field_name : String,
  init_opt : TsExpr?,
) -> TsStmt {
  let init = match init_opt {
    Some(expr) => expr
    None => Var("undefined")
  }
  PropAssign(Var("this"), field_name, init)
}

///|
fn Parser::inject_instance_fields(
  self : Parser,
  func : TsFunc,
  fields : Array[(Bool, String, TsExpr?)],
  base : String?,
) -> TsFunc {
  let assigns : Array[TsStmt] = []
  for item in fields {
    let (is_static, field_name, init_opt) = item
    if not(is_static) {
      assigns.push(self.make_field_assign_stmt(field_name, init_opt))
    }
  }
  if assigns.length() == 0 {
    return func
  }
  let mut new_stmts : Array[TsStmt] = []
  let mut inserted = false
  if base is Some(_) {
    for stmt in func.body.stmts {
      new_stmts.push(stmt)
      if not(inserted) && self.is_super_call_stmt(stmt) {
        for assign in assigns {
          new_stmts.push(assign)
        }
        inserted = true
      }
    }
    if not(inserted) {
      let combined : Array[TsStmt] = []
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
    params: func.params,
    return_type: func.return_type,
    body: { stmts: new_stmts, },
    is_generator: func.is_generator,
  }
}

///|
fn Parser::parse_class_body(
  self : Parser,
) -> (
  TsFunc?,
  Array[(Bool, String, TsFunc)],
  Array[(Bool, String, TsExpr?)],
) raise ParseError {
  let _ = self.expect(LBrace)
  let mut ctor : TsFunc? = None
  let methods : Array[(Bool, String, TsFunc)] = []
  let fields : Array[(Bool, String, TsExpr?)] = []
  while not(self.check(RBrace)) && not(self.check(Eof)) {
    if self.match_(Semicolon) {
      continue
    }
    let mut is_static = false
    let mut has_modifier = true
    while has_modifier {
      has_modifier = false
      match self.peek().kind {
        Ident(n) if n == "static" =>
          if self.peek_at(1).kind != LParen {
            let _ = self.advance()
            is_static = true
            has_modifier = true
          }
        Ident(n) if n == "async" =>
          if self.peek_at(1).kind != LParen {
            let _ = self.advance()
            has_modifier = true
          }
        _ => ()
      }
    }
    let mut accessor_kind : String? = None
    match self.peek().kind {
      Ident(n) if (n == "get" || n == "set") && self.peek_at(1).kind != LParen => {
        let _ = self.advance()
        accessor_kind = Some(n)
      }
      _ => ()
    }
    let is_generator = self.match_(Star)
    let name = self.parse_class_method_name()
    let method_name =
      match accessor_kind {
        Some("get") => "@@get:" + name
        Some("set") => "@@set:" + name
        _ => name
      }
    if self.check(LParen) {
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
      let func : TsFunc = { name, params, return_type, body, is_generator }
      if method_name == "constructor" && not(is_static) {
        ctor = Some(func)
      } else {
        methods.push((is_static, method_name, func))
      }
    } else {
      if self.match_(Colon) {
        let _ = self.parse_type()
      }
      let init : TsExpr? = if self.match_(Eq) {
        Some(self.parse_assignment())
      } else {
        None
      }
      let _ = self.match_(Semicolon)
      fields.push((is_static, name, init))
    }
  }
  let _ = self.expect(RBrace)
  (ctor, methods, fields)
}

///|
fn Parser::parse_class_stub(self : Parser) -> TsExpr raise ParseError {
  let _ = self.expect(Class)
  let mut class_name = ""
  let _ =
    match self.peek().kind {
      Ident(n) => {
        class_name = n
        self.advance()
      }
      _ => { kind: Eof, pos: 0 }
    }
  let mut base : String? = None
  if self.match_(Extends) {
    base = match self.advance().kind {
      Ident(n) => Some(n)
      k => raise ParseError("Expected base class name, got \{k}")
    }
  }
  let (ctor_opt, methods, fields) = self.parse_class_body()
  let tmp_name = if class_name == "" { "__class__" } else { class_name }
  let stmts : Array[TsStmt] = []
  let ctor_func = match ctor_opt {
    Some(func) => func
    None => {
      match base {
        Some(_) => {
          let rest_name = "__super_args__"
          let rest_param : TsParam = {
            name: rest_name,
            binding: Some(TsBinding::Ident(rest_name)),
            is_rest: true,
            type_: Any,
            default: None,
          }
          let empty_body : TsBlock = { stmts: [Expr(Call("super", [Var(rest_name)]))] }
          {
            name: tmp_name,
            params: [rest_param],
            return_type: Any,
            body: empty_body,
            is_generator: false,
          }
        }
        None => {
          let empty_body : TsBlock = { stmts: [] }
          {
            name: tmp_name,
            params: [],
            return_type: Any,
            body: empty_body,
            is_generator: false,
          }
        }
      }
    }
  }
  let ctor_func = self.inject_instance_fields(ctor_func, fields, base)
  stmts.push(Let(TsBinding::Ident(tmp_name), Any, FuncExpr(ctor_func)))

  let proto_expr = PropAccess(Var(tmp_name), "prototype")
  match base {
    Some(base_name) => {
      let base_proto = PropAccess(Var(base_name), "prototype")
      stmts.push(PropAssign(Var(tmp_name), "__super_ctor", Var(base_name)))
      stmts.push(PropAssign(Var(tmp_name), "__super_proto", base_proto))
      stmts.push(PropAssign(Var(tmp_name), "__proto__", Var(base_name)))
      stmts.push(PropAssign(proto_expr, "__proto__", base_proto))
    }
    None => ()
  }

  for item in methods {
    let (is_static, method_name, func) = item
    if is_static {
      stmts.push(PropAssign(Var(tmp_name), method_name, FuncExpr(func)))
    } else {
      stmts.push(PropAssign(proto_expr, method_name, FuncExpr(func)))
      match base {
        Some(base_name) => {
          let base_proto = PropAccess(Var(base_name), "prototype")
          let method_ref = PropAccess(proto_expr, method_name)
          stmts.push(PropAssign(method_ref, "__super_proto", base_proto))
        }
        None => ()
      }
    }
  }
  for item in fields {
    let (is_static, field_name, init_opt) = item
    if is_static {
      let init = match init_opt {
        Some(expr) => expr
        None => Var("undefined")
      }
      stmts.push(PropAssign(Var(tmp_name), field_name, init))
    }
  }
  stmts.push(Return(Some(Var(tmp_name))))
  CallExpr(
    FuncExpr({
      name: "<class>",
      params: [],
      return_type: Any,
      body: { stmts, },
      is_generator: false,
    }),
    [],
  )
}

///|
fn Parser::parse_class_decl(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Class)
  let name = match self.advance().kind {
    Ident(n) => n
    _ => "<class>"
  }
  let mut base : String? = None
  if self.match_(Extends) {
    base = match self.advance().kind {
      Ident(n) => Some(n)
      k => raise ParseError("Expected base class name, got \{k}")
    }
  }
  let (ctor_opt, methods, fields) = self.parse_class_body()
  let stmts : Array[TsStmt] = []

  let ctor_func = match ctor_opt {
    Some(func) => func
    None => {
      match base {
        Some(_) => {
          let rest_name = "__super_args__"
          let rest_param : TsParam = {
            name: rest_name,
            binding: Some(TsBinding::Ident(rest_name)),
            is_rest: true,
            type_: Any,
            default: None,
          }
          let empty_body : TsBlock = { stmts: [Expr(Call("super", [Var(rest_name)]))] }
          {
            name,
            params: [rest_param],
            return_type: Any,
            body: empty_body,
            is_generator: false,
          }
        }
        None => {
          let empty_body : TsBlock = { stmts: [] }
          {
            name,
            params: [],
            return_type: Any,
            body: empty_body,
            is_generator: false,
          }
        }
      }
    }
  }
  let ctor_func = self.inject_instance_fields(ctor_func, fields, base)
  stmts.push(Let(TsBinding::Ident(name), Any, FuncExpr(ctor_func)))

  let proto_expr = PropAccess(Var(name), "prototype")
  match base {
    Some(base_name) => {
      let base_proto = PropAccess(Var(base_name), "prototype")
      stmts.push(PropAssign(Var(name), "__super_ctor", Var(base_name)))
      stmts.push(PropAssign(Var(name), "__super_proto", base_proto))
      stmts.push(PropAssign(Var(name), "__proto__", Var(base_name)))
      stmts.push(PropAssign(proto_expr, "__proto__", base_proto))
    }
    None => ()
  }

  for item in methods {
    let (is_static, method_name, func) = item
    if is_static {
      stmts.push(PropAssign(Var(name), method_name, FuncExpr(func)))
    } else {
      stmts.push(PropAssign(proto_expr, method_name, FuncExpr(func)))
      match base {
        Some(base_name) => {
          let base_proto = PropAccess(Var(base_name), "prototype")
          let method_ref = PropAccess(proto_expr, method_name)
          stmts.push(PropAssign(method_ref, "__super_proto", base_proto))
        }
        None => ()
      }
    }
  }
  for item in fields {
    let (is_static, field_name, init_opt) = item
    if is_static {
      let init = match init_opt {
        Some(expr) => expr
        None => Var("undefined")
      }
      stmts.push(PropAssign(Var(name), field_name, init))
    }
  }

  if stmts.length() == 1 {
    stmts[0]
  } else {
    Block({ stmts, })
  }
}

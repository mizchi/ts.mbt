///|
priv enum ClassKey {
  Name(String)
  Computed(@ast.TsExpr)
}

///|
priv enum ClassElement {
  Method(Bool, ClassKey, String?, @ast.TsFunc)
  Field(Bool, ClassKey, @ast.TsExpr?)
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
fn class_key_expr(key : ClassKey) -> @ast.TsExpr {
  match key {
    Name(name) => @ast.TsExpr::StringLit(name)
    Computed(expr) => expr
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
    PrivateIdent(n) => "#" + n
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
    // Note: static, this, super, true, false, null, get, set, of, async, await
    // are handled as Ident tokens with special names, not separate TokenKind
    k => raise ParseError("Expected method name, got \{k}")
  }
  Name(name)
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
      if not(inserted) && self.is_super_call_stmt(stmt) {
        for assign in assigns {
          new_stmts.push(assign)
        }
        inserted = true
      }
    }
    if not(inserted) {
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
    params: func.params,
    return_type: func.return_type,
    body: { stmts: new_stmts },
    is_generator: func.is_generator, is_async: func.is_async,
  }
}

///|
fn Parser::parse_class_body(
  self : Parser,
) -> (@ast.TsFunc?, Array[ClassElement]) raise ParseError {
  let _ = self.expect(LBrace)
  let mut ctor : @ast.TsFunc? = None
  let elements : Array[ClassElement] = []
  while not(self.check(RBrace)) && not(self.check(Eof)) {
    if self.match_(Semicolon) {
      continue
    }
    let mut is_static = false
    let mut has_modifier = true
    let mut parsed_static_block = false
    while has_modifier {
      has_modifier = false
      match self.peek().kind {
        Ident(n) if n == "static" =>
          if self.peek_at(1).kind != LParen {
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
          if self.peek_at(1).kind != LParen {
            let _ = self.advance()
            has_modifier = true
          }
        _ => ()
      }
    }
    if parsed_static_block {
      continue // Continue to next class element
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
    let key = self.parse_class_method_key()
    let method_name = class_key_name(key)
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
      let func : @ast.TsFunc = {
        name: method_name,
        params,
        return_type,
        body,
        is_generator,
        is_async: false,
      }
      if accessor_kind is None && key is Name("constructor") && not(is_static) {
        ctor = Some(func)
      } else {
        elements.push(Method(is_static, key, accessor_kind, func))
      }
    } else {
      if self.match_(Colon) {
        let _ = self.parse_type()

      }
      let init : @ast.TsExpr? = if self.match_(Eq) {
        Some(self.parse_assignment())
      } else {
        None
      }
      let _ = self.match_(Semicolon)
      elements.push(Field(is_static, key, init))
    }
  }
  let _ = self.expect(RBrace)
  (ctor, elements)
}

///|
fn Parser::parse_class_stub(self : Parser) -> @ast.TsExpr raise ParseError {
  let _ = self.expect(Class)
  let mut class_name = ""
  let _ = match self.peek().kind {
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
  let (ctor_opt, elements) = self.parse_class_body()
  match base {
    Some(base_name) =>
      if class_name.length() > 0 && base_name == class_name {
        let throw_expr = @ast.TsExpr::Call("ReferenceError", [])
        let throw_body : @ast.TsBlock = { stmts: [Throw(throw_expr)] }
        return CallExpr(
          @ast.TsExpr::FuncExpr(@ast.TsFunc::{
            name: "<class>",
            params: [],
            return_type: @ast.TsType::Any,
            body: throw_body,
            is_generator: false, is_async: false,
          }),
          [],
        )
      }
    None => ()
  }
  let tmp_name = if class_name == "" { "<anon>" } else { class_name }
  let instance_assigns : Array[@ast.TsStmt] = []
  let key_temps : Array[String?] = []  // Temp var names for ALL elements' computed keys
  let key_init_stmts : Array[@ast.TsStmt] = []  // Initialization statements for computed keys
  let mut key_index = 0

  // First pass: collect all computed keys and generate temp variables
  for element in elements {
    match element {
      Field(_, key, _) | Method(_, key, _, _) =>
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
      Field(is_static, key, init_opt) =>
        if not(is_static) {
          let init = match init_opt {
            Some(expr) => expr
            None => @ast.TsExpr::Var("undefined")
          }
          match key {
            Name(field_name) =>
              instance_assigns.push(
                PropAssign(@ast.TsExpr::Var("this"), field_name, init),
              )
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
            params: [rest_param],
            return_type: Any,
            body: empty_body,
            is_generator: false, is_async: false,
          }
        }
        None => {
          let empty_body : @ast.TsBlock = { stmts: [] }
          {
            name: tmp_name,
            params: [],
            return_type: Any,
            body: empty_body,
            is_generator: false, is_async: false,
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
    None => ()
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
                stmts.push(PropAssign(target, prop_key, func_expr))
              }
              None => {
                let prop_key = "@@define:" + method_name
                stmts.push(PropAssign(target, prop_key, func_expr))
                match base {
                  Some(base_name) =>
                    if not(is_static) {
                      let base_proto = @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var(base_name),
                        "prototype",
                      )
                      let method_ref = @ast.TsExpr::PropAccess(
                        proto_expr, method_name,
                      )
                      stmts.push(
                        PropAssign(method_ref, "__super_proto", base_proto),
                      )
                    }
                  None => ()
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
      Field(is_static, key, init_opt) => {
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
          name: "",
          params: [],
          return_type: @ast.TsType::Any,
          body: block,
          is_generator: false, is_async: false,
        })
        let call_method = @ast.TsExpr::PropAccess(static_block_func, "call")
        let call_expr = @ast.TsExpr::CallExpr(call_method, [@ast.TsExpr::Var(tmp_name)])
        stmts.push(Expr(call_expr))
      }
    }
  }
  stmts.push(Return(Some(@ast.TsExpr::Var(tmp_name))))
  CallExpr(
    @ast.TsExpr::FuncExpr(@ast.TsFunc::{
      name: "<class>",
      params: [],
      return_type: @ast.TsType::Any,
      body: @ast.TsBlock::{ stmts, },
      is_generator: false, is_async: false,
    }),
    [],
  )
}

///|
fn Parser::parse_class_decl(self : Parser) -> @ast.TsStmt raise ParseError {
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
  let (ctor_opt, elements) = self.parse_class_body()
  let instance_assigns : Array[@ast.TsStmt] = []
  let key_temps : Array[String?] = []  // Temp var names for ALL elements' computed keys
  let key_init_stmts : Array[@ast.TsStmt] = []  // Initialization statements for computed keys
  let mut key_index = 0

  // First pass: collect all computed keys and generate temp variables
  for element in elements {
    match element {
      Field(_, key, _) | Method(_, key, _, _) =>
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
      Field(is_static, key, init_opt) =>
        if not(is_static) {
          let init = match init_opt {
            Some(expr) => expr
            None => @ast.TsExpr::Var("undefined")
          }
          match key {
            Name(field_name) =>
              instance_assigns.push(
                PropAssign(@ast.TsExpr::Var("this"), field_name, init),
              )
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
            params: [rest_param],
            return_type: Any,
            body: empty_body,
            is_generator: false, is_async: false,
          }
        }
        None => {
          let empty_body : @ast.TsBlock = { stmts: [] }
          {
            name,
            params: [],
            return_type: Any,
            body: empty_body,
            is_generator: false, is_async: false,
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
    None => ()
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
                stmts.push(PropAssign(target, prop_key, func_expr))
              }
              None => {
                let prop_key = "@@define:" + method_name
                stmts.push(PropAssign(target, prop_key, func_expr))
                match base {
                  Some(base_name) =>
                    if not(is_static) {
                      let base_proto = @ast.TsExpr::PropAccess(
                        @ast.TsExpr::Var(base_name),
                        "prototype",
                      )
                      let method_ref = @ast.TsExpr::PropAccess(
                        proto_expr, method_name,
                      )
                      stmts.push(
                        PropAssign(method_ref, "__super_proto", base_proto),
                      )
                    }
                  None => ()
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
      Field(is_static, key, init_opt) => {
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
          name: "",
          params: [],
          return_type: @ast.TsType::Any,
          body: block,
          is_generator: false, is_async: false,
        })
        let call_method = @ast.TsExpr::PropAccess(static_block_func, "call")
        let call_expr = @ast.TsExpr::CallExpr(call_method, [@ast.TsExpr::Var(name)])
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
        name: "<class>",
        params: [],
        return_type: @ast.TsType::Any,
        body: @ast.TsBlock::{ stmts: internal_stmts },
        is_generator: false, is_async: false,
      }),
      [],
    )
    Let(@ast.TsBinding::Ident(name), Any, iife)
  }
}

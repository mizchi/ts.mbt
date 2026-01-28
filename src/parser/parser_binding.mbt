///|
// /
fn Parser::consume_binding_name(self : Parser) -> String raise ParseError {
  let _ = self.advance()
  let mut depth = 1
  let mut name = "<destruct>"
  while depth > 0 {
    let tok = self.advance()
    match tok.kind {
      LBracket | LBrace => depth += 1
      RBracket | RBrace => {
        depth -= 1
        if depth == 0 {
          break
        }
      }
      Ident(n) =>
        if name == "<destruct>" {
          name = n
        }
      Eof => raise ParseError("Unexpected EOF in binding pattern")
      _ => ()
    }
  }
  name
}

///|
// /
fn Parser::parse_binding_ident(self : Parser) -> String raise ParseError {
  match self.peek().kind {
    Ident(_) => match self.advance().kind {
      Ident(n) => n
      _ => "<param>"
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
    Switch => {
      let _ = self.advance()
      "switch"
    }
    Case => {
      let _ = self.advance()
      "case"
    }
    Default => {
      let _ = self.advance()
      "default"
    }
    With => {
      let _ = self.advance()
      "with"
    }
    Debugger => {
      let _ = self.advance()
      "debugger"
    }
    Import => {
      let _ = self.advance()
      "import"
    }
    Export => {
      let _ = self.advance()
      "export"
    }
    From => {
      let _ = self.advance()
      "from"
    }
    As => {
      let _ = self.advance()
      "as"
    }
    k => raise ParseError("Expected identifier, got \{k}")
  }
}

///|
fn Parser::binding_first_name(self : Parser, binding : TsBinding) -> String {
  match binding {
    TsBinding::Ident(n) => n
    TsBinding::Array(arr) => {
      for item in arr.items {
        match item {
          Some(elem) => {
            let name = self.binding_first_name(elem.binding)
            if name != "<destruct>" {
              return name
            }
          }
          None => ()
        }
      }
      match arr.rest {
        Some(rest) => self.binding_first_name(rest)
        None => "<destruct>"
      }
    }
    TsBinding::Object(obj) => {
      for prop in obj.props {
        let name = self.binding_first_name(prop.binding)
        if name != "<destruct>" {
          return name
        }
      }
      match obj.rest {
        Some(name) => name
        None => "<destruct>"
      }
    }
    TsBinding::Target(_) => "<destruct>"
  }
}

///|
fn Parser::parse_binding_element(self : Parser) -> TsBindingElem raise ParseError {
  let binding = self.parse_binding_pattern()
  let default : TsExpr? = if self.match_(Eq) {
    Some(self.parse_assignment())
  } else {
    None
  }
  { binding, default }
}

///|
fn Parser::parse_binding_array(self : Parser) -> TsBinding raise ParseError {
  let _ = self.expect(LBracket)
  let items : Array[TsBindingElem?] = []
  let mut rest : TsBinding? = None
  while not(self.check(RBracket)) {
    if self.match_(Ellipsis) {
      let rest_binding = self.parse_binding_pattern()
      rest = Some(rest_binding)
      if self.match_(Comma) {
        // trailing comma after rest
      }
      break
    }
    if self.match_(Comma) {
      items.push(None)
      continue
    }
    items.push(Some(self.parse_binding_element()))
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
  TsBinding::Array({ items, rest })
}

///|
fn Parser::parse_object_binding_key(self : Parser) -> String raise ParseError {
  match self.advance().kind {
    Ident(n) => n
    Yield => "yield"
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
    Let => "let"
    Const => "const"
    Var => "var"
    New => "new"
    Typeof => "typeof"
    Of => "of"
    In => "in"
    Do => "do"
    Try => "try"
    Switch => "switch"
    Case => "case"
    Default => "default"
    With => "with"
    Debugger => "debugger"
    Import => "import"
    Export => "export"
    From => "from"
    As => "as"
    Catch => "catch"
    Finally => "finally"
    Throw => "throw"
    Delete => "delete"
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
    k => raise ParseError("Expected object binding key, got \{k}")
  }
}

///|
fn Parser::parse_binding_object(self : Parser) -> TsBinding raise ParseError {
  let _ = self.expect(LBrace)
  let props : Array[TsObjectBindingProp] = []
  let mut rest : String? = None
  if not(self.check(RBrace)) {
    while true {
      if self.match_(Ellipsis) {
        let name = self.parse_binding_ident()
        rest = Some(name)
        if self.match_(Comma) {
          // trailing comma
        }
        break
      }
      let (key, key_expr) =
        if self.match_(LBracket) {
          let expr = self.parse_assignment()
          let _ = self.expect(RBracket)
          ("<computed>", Some(expr))
        } else {
          (self.parse_object_binding_key(), None)
        }
      if self.match_(Colon) {
        let elem = self.parse_binding_element()
        props.push({
          key,
          key_expr,
          binding: elem.binding,
          default: elem.default,
        })
      } else {
        match key_expr {
          Some(_) => raise ParseError("Expected Colon, got \{self.peek().kind}")
          None => {
            let mut default : TsExpr? = None
            if self.match_(Eq) {
              default = Some(self.parse_assignment())
            }
            props.push({
              key,
              key_expr: None,
              binding: TsBinding::Ident(key),
              default,
            })
          }
        }
      }
      if self.check(RBrace) {
        break
      }
      let _ = self.expect(Comma)
      if self.check(RBrace) {
        break
      }
    }
  }
  let _ = self.expect(RBrace)
  TsBinding::Object({ props, rest })
}

///|
fn Parser::parse_binding_pattern(self : Parser) -> TsBinding raise ParseError {
  match self.peek().kind {
    LBracket => self.parse_binding_array()
    LBrace => self.parse_binding_object()
    _ => {
      let name = self.parse_binding_ident()
      TsBinding::Ident(name)
    }
  }
}

///|
fn Parser::parse_assignment_target_expr(self : Parser) -> TsExpr raise ParseError {
  let expr = self.parse_ternary()
  match expr {
    Var(_) | PropAccess(_, _) | IndexAccess(_, _) => expr
    _ => raise ParseError("Invalid assignment target")
  }
}

///|
fn Parser::parse_assignment_binding_element(self : Parser) -> TsBindingElem raise ParseError {
  let binding = self.parse_assignment_binding_pattern()
  let default : TsExpr? = if self.match_(Eq) {
    Some(self.parse_assignment())
  } else {
    None
  }
  { binding, default }
}

///|
fn Parser::parse_assignment_binding_array(self : Parser) -> TsBinding raise ParseError {
  let _ = self.expect(LBracket)
  let items : Array[TsBindingElem?] = []
  let mut rest : TsBinding? = None
  while not(self.check(RBracket)) {
    if self.match_(Ellipsis) {
      let rest_binding = self.parse_assignment_binding_pattern()
      rest = Some(rest_binding)
      if self.match_(Comma) {
        // trailing comma after rest
      }
      break
    }
    if self.match_(Comma) {
      items.push(None)
      continue
    }
    items.push(Some(self.parse_assignment_binding_element()))
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
  TsBinding::Array({ items, rest })
}

///|
fn Parser::parse_assignment_binding_object(self : Parser) -> TsBinding raise ParseError {
  let _ = self.expect(LBrace)
  let props : Array[TsObjectBindingProp] = []
  let mut rest : String? = None
  if not(self.check(RBrace)) {
    while true {
      if self.match_(Ellipsis) {
        let name = self.parse_binding_ident()
        rest = Some(name)
        if self.match_(Comma) {
          // trailing comma
        }
        break
      }
      let (key, key_expr) =
        if self.match_(LBracket) {
          let expr = self.parse_assignment()
          let _ = self.expect(RBracket)
          ("<computed>", Some(expr))
        } else {
          (self.parse_object_binding_key(), None)
        }
      if self.match_(Colon) {
        let elem = self.parse_assignment_binding_element()
        props.push({
          key,
          key_expr,
          binding: elem.binding,
          default: elem.default,
        })
      } else {
        match key_expr {
          Some(_) => raise ParseError("Expected Colon, got \{self.peek().kind}")
          None => {
            let mut default : TsExpr? = None
            if self.match_(Eq) {
              default = Some(self.parse_assignment())
            }
            props.push({
              key,
              key_expr: None,
              binding: TsBinding::Ident(key),
              default,
            })
          }
        }
      }
      if self.check(RBrace) {
        break
      }
      let _ = self.expect(Comma)
      if self.check(RBrace) {
        break
      }
    }
  }
  let _ = self.expect(RBrace)
  TsBinding::Object({ props, rest })
}

///|
fn Parser::parse_assignment_binding_pattern(self : Parser) -> TsBinding raise ParseError {
  let saved_pos = self.pos
  let saved_gen = self.in_generator
  let target =
    try {
      Some(self.parse_assignment_target_expr())
    } catch {
      _ => None
    }
  match target {
    Some(expr) =>
      match expr {
        Var(name) => TsBinding::Ident(name)
        _ => TsBinding::Target(expr)
      }
    None => {
      self.pos = saved_pos
      self.in_generator = saved_gen
      match self.peek().kind {
        LBracket => self.parse_assignment_binding_array()
        LBrace => self.parse_assignment_binding_object()
        _ => {
          let name = self.parse_binding_ident()
          TsBinding::Ident(name)
        }
      }
    }
  }
}

///|
// / ...
fn Parser::match_ellipsis(self : Parser) -> Bool {
  self.match_(Ellipsis)
}

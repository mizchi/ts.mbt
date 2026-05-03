// ============================================
// type
// ============================================

///|
/// Check if current token is an identifier
fn Parser::is_ident(self : Parser) -> Bool {
  match self.peek().kind {
    Ident(_) => true
    _ => false
  }
}

///|
fn Parser::parse_paren_or_function_type(
  self : Parser,
) -> @ast.TsType raise ParseError {
  let saved_pos = self.pos
  let _ = self.expect(LParen)
  if self.match_(RParen) {
    if self.match_(Arrow) {
      return Func([], self.parse_type())
    }
    return Any
  }

  let param_types : Array[@ast.TsType] = []
  let mut can_be_function_type = true
  while true {
    let _ = self.match_ellipsis()
    let _ = self.parse_declare_param_name() catch {
      _ => {
        can_be_function_type = false
        break
      }
    }
    let _ = self.match_(Question)
    if !self.match_(Colon) {
      can_be_function_type = false
      break
    }
    param_types.push(self.parse_type())
    if self.match_(Comma) {
      if self.check(RParen) {
        break
      }
      continue
    }
    break
  }
  if can_be_function_type && self.match_(RParen) && self.match_(Arrow) {
    return Func(param_types, self.parse_type())
  }

  self.pos = saved_pos
  let _ = self.expect(LParen)
  let inner = self.parse_type()
  let _ = self.expect(RParen)
  inner
}

///|
fn Parser::parse_tuple_type(self : Parser) -> @ast.TsType raise ParseError {
  let _ = self.expect(LBracket)
  let items : Array[@ast.TsType] = []
  if self.match_(RBracket) {
    return Tuple(items)
  }
  while !self.check(Eof) {
    let _ = self.match_ellipsis()
    match self.peek().kind {
      Ident(_) if self.peek_at(1).kind == Colon => {
        let _ = self.advance()
        let _ = self.expect(Colon)
      }
      Ident(_) if self.peek_at(1).kind == Question &&
        self.peek_at(2).kind == Colon => {
        let _ = self.advance()
        let _ = self.advance()
        let _ = self.expect(Colon)
      }
      _ => ()
    }
    let item_type = self.parse_type()
    items.push(
      if self.match_(Question) {
        wrap_optional_ts_type(item_type)
      } else {
        item_type
      },
    )
    if self.match_(Comma) {
      if self.match_(RBracket) {
        break
      }
      continue
    }
    let _ = self.expect(RBracket)
    break
  }
  Tuple(items)
}

///|
fn mapped_object_key_names(type_ : @ast.TsType) -> Array[String]? {
  match type_ {
    Literal(name) => Some([name])
    Union(items) => {
      let names : Array[String] = []
      for item in items {
        match item {
          Literal(name) => names.push(name)
          _ => return None
        }
      }
      Some(names)
    }
    _ => None
  }
}

///|
fn Parser::try_parse_simple_mapped_object_type_after_lbrace(
  self : Parser,
) -> @ast.TsType? {
  let saved_pos = self.pos
  try {
    let _ = self.match_ident("readonly")
    let _ = self.expect(LBracket)
    if self.is_ident() {
      let _ = self.advance()
    } else {
      self.pos = saved_pos
      return None
    }
    if !(self.match_(In) || self.match_ident("in")) {
      self.pos = saved_pos
      return None
    }
    let keys_type = self.parse_type()
    if self.match_(As) || self.match_ident("as") {
      self.pos = saved_pos
      return None
    }
    let _ = self.expect(RBracket)
    let optional = if self.match_(Question) {
      true
    } else if self.match_(Minus) {
      let _ = self.match_(Question)
      false
    } else {
      false
    }
    let _ = self.expect(Colon)
    let value_type = self.parse_type()
    let _ = self.match_(Semicolon) || self.match_(Comma)
    let _ = self.expect(RBrace)
    let keys = match mapped_object_key_names(keys_type) {
      Some(keys) => keys
      None => {
        self.pos = saved_pos
        return None
      }
    }
    let fields : Array[(@ast.TsType, @ast.TsType)] = []
    let field_type = if optional {
      wrap_optional_ts_type(value_type)
    } else {
      value_type
    }
    for key in keys {
      fields.push((Literal(key), field_type))
    }
    Some(Object(fields))
  } catch {
    _ => {
      self.pos = saved_pos
      None
    }
  }
}

///|
fn Parser::try_parse_simple_object_type(self : Parser) -> @ast.TsType? {
  if !self.check(LBrace) {
    return None
  }
  let saved_pos = self.pos
  let fields : Array[(@ast.TsType, @ast.TsType)] = []
  try {
    let _ = self.expect(LBrace)
    match self.try_parse_simple_mapped_object_type_after_lbrace() {
      Some(type_) => return Some(type_)
      None => ()
    }
    while !self.check(Eof) && !self.check(RBrace) {
      let field_name = match self.advance().kind {
        Ident(name) => name
        _ => {
          self.pos = saved_pos
          return None
        }
      }
      let _ = self.match_(Question)
      let _ = self.expect(Colon)
      fields.push((Literal(field_name), self.parse_type()))
      if self.match_(Semicolon) || self.match_(Comma) {
        continue
      }
      if self.has_line_terminator_before() {
        match self.peek().kind {
          Ident(_) | RBrace => continue
          _ => ()
        }
      }
      if self.check(RBrace) {
        break
      }
      self.pos = saved_pos
      return None
    }
    let _ = self.expect(RBrace)
    Some(Object(fields))
  } catch {
    _ => {
      self.pos = saved_pos
      None
    }
  }
}

///|
fn Parser::try_parse_simple_type_args(self : Parser) -> Array[@ast.TsType]? {
  if !self.check(Lt) {
    return None
  }
  let saved_pos = self.pos
  let args : Array[@ast.TsType] = []
  try {
    let _ = self.expect(Lt)
    while !self.check(Eof) {
      args.push(self.parse_type())
      if self.match_(Comma) {
        continue
      }
      match self.peek().kind {
        Gt => {
          let _ = self.advance()
          return Some(args)
        }
        GtGt => {
          let tok = self.advance()
          self.pending_gt += 1
          self.pending_gt_pos = tok.pos
          return Some(args)
        }
        GtGtGt => {
          let tok = self.advance()
          self.pending_gt += 2
          self.pending_gt_pos = tok.pos
          return Some(args)
        }
        _ => ()
      }
      self.pos = saved_pos
      self.pending_gt = 0
      return None
    }
    self.pos = saved_pos
    self.pending_gt = 0
    None
  } catch {
    _ => {
      self.pos = saved_pos
      self.pending_gt = 0
      None
    }
  }
}

///|
fn Parser::is_qualified_type_name_part(self : Parser, offset : Int) -> Bool {
  match self.peek_at(offset).kind {
    Ident(_)
    | Type
    | Function
    | Class
    | New
    | Import
    | Export
    | From
    | As
    | In
    | Of
    | Extends
    | Typeof
    | Instanceof
    | StringType
    | NumberType
    | BooleanType
    | IntType
    | VoidType
    | Null => true
    _ => false
  }
}

///|
fn Parser::parse_named_type_tail(
  self : Parser,
  first_name : String,
) -> @ast.TsType raise ParseError {
  let mut full_name = first_name
  while self.check(Dot) && self.is_qualified_type_name_part(1) {
    let _ = self.advance()
    let next_name = self.parse_binding_ident()
    full_name = full_name + "." + next_name
  }
  if self.check(Lt) {
    match self.try_parse_simple_type_args() {
      Some(type_args) => Applied(full_name, type_args)
      None => {
        self.skip_type_args()
        Named(full_name)
      }
    }
  } else {
    Named(full_name)
  }
}

///|
fn Parser::local_type_param_bound(self : Parser, name : String) -> @ast.TsType? {
  let mut idx = self.local_type_param_bounds.length()
  while idx > 0 {
    idx -= 1
    let (param_name, bound) = self.local_type_param_bounds[idx]
    if param_name == name {
      return Some(bound)
    }
  }
  None
}

///|
/// Parse a single type (not including union/intersection)
fn Parser::parse_primary_type(self : Parser) -> @ast.TsType raise ParseError {
  let tok = self.peek()
  let base_type : @ast.TsType = match tok.kind {
    Lt => {
      self.skip_type_args()
      if self.check(LParen) {
        match self.parse_paren_or_function_type() {
          Func(_, _) as func_type => func_type
          _ => Any
        }
      } else {
        Any
      }
    }
    NumberType => {
      let _ = self.advance()
      if self.check(Dot) {
        self.parse_named_type_tail("number")
      } else {
        Number
      }
    }
    IntType => {
      let _ = self.advance()
      if self.check(Dot) {
        self.parse_named_type_tail("int")
      } else {
        Int
      }
    }
    BooleanType => {
      let _ = self.advance()
      if self.check(Dot) {
        self.parse_named_type_tail("boolean")
      } else {
        Boolean
      }
    }
    StringType => {
      let _ = self.advance()
      if self.check(Dot) {
        self.parse_named_type_tail("string")
      } else {
        String_
      }
    }
    VoidType => {
      let _ = self.advance()
      if self.check(Dot) {
        self.parse_named_type_tail("void")
      } else {
        Void
      }
    }
    // Template literal type: `bg${ForegroundColorName}`. Falls back to
    // `String_` for non-interpolating templates so the prior conservative
    // behavior is preserved.
    Template(cooked_parts, _, expr_sources) => {
      let _ = self.advance()
      if expr_sources.length() == 0 {
        String_
      } else {
        let type_args : Array[@ast.TsType] = []
        for src in expr_sources {
          let sub_parser = Parser::from_source(src)
          let arg_type = sub_parser.parse_type()
          type_args.push(arg_type)
        }
        TemplateLiteralType(cooked_parts, type_args)
      }
    }
    // Literal types: "foo", 1, true, false
    Str(value) => {
      let _ = self.advance()
      Literal(value)
    }
    Int(value) => {
      let _ = self.advance()
      NumberLiteral(value.to_string())
    }
    Number(value) => {
      let _ = self.advance()
      NumberLiteral(value.to_string())
    }
    BigInt(value) => {
      let _ = self.advance()
      BigIntLiteral(value)
    }
    Bool(value) => {
      let _ = self.advance()
      BooleanLiteral(value)
    }
    // null and undefined literal types
    Null => {
      let _ = self.advance()
      Null
    }
    Ident("any") | Ident("unknown") | Ident("object") | Ident("symbol") => {
      let name = match self.advance().kind {
        Ident(n) => n
        _ => "any"
      }
      if self.check(Dot) {
        self.parse_named_type_tail(name)
      } else {
        Any
      }
    }
    Ident("bigint") => {
      let _ = self.advance()
      BigInt
    }
    Ident("undefined") => {
      let _ = self.advance()
      Undefined
    }
    Ident("null") => {
      let _ = self.advance()
      Null
    }
    Ident("never") => {
      let _ = self.advance()
      Never
    }
    Minus => {
      // Negative number literal: -1
      let _ = self.advance()
      match self.peek().kind {
        Int(value) => {
          let _ = self.advance()
          NumberLiteral("-" + value.to_string())
        }
        Number(value) => {
          let _ = self.advance()
          NumberLiteral("-" + value.to_string())
        }
        BigInt(value) => {
          let _ = self.advance()
          BigIntLiteral("-" + value)
        }
        _ => Any
      }
    }
    // Object type: { key: T; ... }
    LBrace =>
      match self.try_parse_simple_object_type() {
        Some(type_) => type_
        None => {
          self.skip_object_type()
          Any
        }
      }
    // Tuple type: [T, U]
    LBracket => self.parse_tuple_type()
    // Parenthesized type or function type: (T) or (x: T) => U
    LParen => self.parse_paren_or_function_type()
    // typeof T
    Typeof => {
      let _ = self.advance()
      self.skip_typeof_operand()
      Any
    }
    // import("...").Type
    Import => {
      let _ = self.advance()
      if self.check(LParen) {
        let _ = self.advance()
        if self.check(Str("")) {
          let _ = self.advance()
        } else if self.peek().kind is Str(_) {
          let _ = self.advance()
        }
        let _ = self.expect(RParen)
        while self.check(Dot) {
          let _ = self.advance()
          match self.peek().kind {
            Ident(_)
            | NumberType
            | BooleanType
            | StringType
            | VoidType
            | Type
            | New
            | Extends
            | Import
            | Export
            | From
            | As => {
              let _ = self.advance()
            }
            _ => break
          }
        }
        if self.check(Lt) {
          self.skip_type_args()
        }
      }
      Any
    }
    // Constructor type: new (...args: T) => U
    New => {
      let _ = self.advance()
      // Skip type parameters if present
      if self.check(Lt) {
        self.skip_type_args()
      }
      // Skip parameter list
      if self.check(LParen) {
        self.skip_paren_type()
      }
      Any
    }
    // abstract new (...) => T
    Ident("abstract") => {
      let _ = self.advance()
      if self.check(New) {
        let _ = self.advance()
        if self.check(Lt) {
          self.skip_type_args()
        }
        if self.check(LParen) {
          self.skip_paren_type()
        }
      }
      Any
    }
    // Special identifier-like keywords
    Ident("infer") => {
      let _ = self.advance()
      let name = if self.is_ident() { self.parse_binding_ident() } else { "_" }
      // May have extends constraint.
      if self.check(Extends) {
        let _ = self.advance()
        let _ = self.parse_primary_type()
      }
      Applied("__tsmbt_infer", [Named(name)])
    }
    Ident("keyof") => {
      let _ = self.advance()
      let _ = self.parse_primary_type()
      String_
    }
    Ident("readonly") => {
      let _ = self.advance()
      self.parse_primary_type()
    }
    Ident("unique") => {
      // unique symbol
      let _ = self.advance()
      match self.peek().kind {
        Ident("symbol") => {
          let _ = self.advance()
          Symbol
        }
        _ => Any
      }
    }
    Ident("asserts") => {
      // asserts x is T
      let _ = self.advance()
      self.skip_asserts_clause()
      Any
    }
    Const => {
      let _ = self.advance()
      Any
    }
    Function
    | Class
    | From
    | As
    | In
    | Of
    | Extends
    | Return
    | If
    | Else
    | While
    | Do
    | For
    | Switch
    | Case
    | Default
    | Break
    | Continue
    | Try
    | Catch
    | Finally
    | Throw
    | Let
    | Var
    | Declare
    | Delete
    | Debugger
    | Instanceof => {
      let name = self.parse_binding_ident()
      self.parse_named_type_tail(name)
    }
    Type => {
      let _ = self.advance()
      self.parse_named_type_tail("type")
    }
    // Ident or generic type: Foo, Array<T>
    Ident(name) => {
      let _ = self.advance()
      match self.local_type_param_bound(name) {
        Some(bound) => bound
        None => self.parse_named_type_tail(name)
      }
    }
    _ => raise ParseError("Expected type, got \{tok.kind}")
  }
  // Handle postfix type operators
  self.parse_postfix_type(base_type)
}

///|
/// Parse postfix type operators: [], extends, etc.
fn Parser::parse_postfix_type(
  self : Parser,
  base_type : @ast.TsType,
) -> @ast.TsType raise ParseError {
  // Array type: T[] or indexed access T[K]
  if self.check(LBracket) && !self.has_line_terminator_before() {
    let _ = self.advance() // [
    if self.check(RBracket) {
      let _ = self.advance() // ]
      return self.parse_postfix_type(Array(base_type))
    }
    // Indexed access type: T[K]. Try to parse the index as a type so later
    // passes can resolve `T["field"]` etc. against concrete interfaces; if
    // parsing fails for any reason, fall back to the original skip-and-Any
    // behaviour so we don't regress more exotic forms.
    let saved_pos = self.pos
    let key_type = self.parse_type() catch {
      _ => {
        self.pos = saved_pos
        let mut bracket_depth = 1
        while bracket_depth > 0 && !self.check(Eof) {
          match self.peek().kind {
            LBracket => {
              bracket_depth += 1
              let _ = self.advance()
            }
            RBracket => {
              bracket_depth -= 1
              let _ = self.advance()
            }
            _ => {
              let _ = self.advance()
            }
          }
        }
        return self.parse_postfix_type(Any)
      }
    }
    if !self.check(RBracket) {
      // Unexpected token after the index type; bail out to the legacy path.
      let mut bracket_depth = 1
      while bracket_depth > 0 && !self.check(Eof) {
        match self.peek().kind {
          LBracket => {
            bracket_depth += 1
            let _ = self.advance()
          }
          RBracket => {
            bracket_depth -= 1
            let _ = self.advance()
          }
          _ => {
            let _ = self.advance()
          }
        }
      }
      return self.parse_postfix_type(Any)
    }
    let _ = self.advance() // ]
    return self.parse_postfix_type(IndexedAccess(base_type, key_type))
  }
  base_type
}

///|
fn Parser::parse_type_operand(self : Parser) -> @ast.TsType raise ParseError {
  let base = self.parse_primary_type()
  if !self.has_line_terminator_before() && self.match_ident("is") {
    let _ = self.parse_type()
    return Boolean
  }
  base
}

///|
fn Parser::parse_intersection_type(
  self : Parser,
) -> @ast.TsType raise ParseError {
  let items : Array[@ast.TsType] = [self.parse_type_operand()]
  while self.match_(Amp) {
    items.push(self.parse_type_operand())
  }
  if items.length() == 1 {
    items[0]
  } else {
    Intersection(items)
  }
}

///|
fn is_definite_primitive_type(type_ : @ast.TsType) -> Bool {
  match type_ {
    Number
    | Int
    | Boolean
    | String_
    | Void
    | BigInt
    | Symbol
    | Null
    | Undefined => true
    _ => false
  }
}

///|
fn type_extends_simple(source : @ast.TsType, target : @ast.TsType) -> Bool? {
  if source == target {
    return Some(true)
  }
  match target {
    Any => return Some(true)
    Union(items) => {
      let mut saw_unknown = false
      for item in items {
        match type_extends_simple(source, item) {
          Some(true) => return Some(true)
          Some(false) => ()
          None => saw_unknown = true
        }
      }
      return if saw_unknown { None } else { Some(false) }
    }
    _ => ()
  }
  match source {
    Never => return Some(true)
    Union(items) => {
      let mut saw_unknown = false
      for item in items {
        match type_extends_simple(item, target) {
          Some(true) => ()
          Some(false) => return Some(false)
          None => saw_unknown = true
        }
      }
      return if saw_unknown { None } else { Some(true) }
    }
    Int if target == Number => return Some(true)
    _ => ()
  }
  if is_definite_primitive_type(source) && is_definite_primitive_type(target) {
    Some(false)
  } else {
    None
  }
}

///|
fn infer_marker_name(type_ : @ast.TsType) -> String? {
  match type_ {
    Applied("__tsmbt_infer", [Named(name)]) => Some(name)
    _ => None
  }
}

///|
fn bind_inferred_type(
  bindings : Map[String, @ast.TsType],
  name : String,
  type_ : @ast.TsType,
) -> Bool {
  match bindings.get(name) {
    Some(existing) => existing == type_
    None => {
      bindings[name] = type_
      true
    }
  }
}

///|
fn match_infer_pattern(
  source : @ast.TsType,
  pattern : @ast.TsType,
  bindings : Map[String, @ast.TsType],
) -> Bool {
  match infer_marker_name(pattern) {
    Some(name) => return bind_inferred_type(bindings, name, source)
    None => ()
  }
  if source == pattern {
    return true
  }
  match (source, pattern) {
    (_, Any) => true
    (Array(source_inner), Array(pattern_inner)) =>
      match_infer_pattern(source_inner, pattern_inner, bindings)
    (Array(source_inner), Applied("Array", [pattern_inner])) =>
      match_infer_pattern(source_inner, pattern_inner, bindings)
    (Applied("Array", [source_inner]), Array(pattern_inner)) =>
      match_infer_pattern(source_inner, pattern_inner, bindings)
    (Applied(source_name, source_args), Applied(pattern_name, pattern_args)) =>
      if source_name != pattern_name ||
        source_args.length() != pattern_args.length() {
        false
      } else {
        for i in 0..<source_args.length() {
          if !match_infer_pattern(source_args[i], pattern_args[i], bindings) {
            return false
          }
        }
        true
      }
    (Tuple(source_items), Tuple(pattern_items)) =>
      if source_items.length() != pattern_items.length() {
        false
      } else {
        for i in 0..<source_items.length() {
          if !match_infer_pattern(source_items[i], pattern_items[i], bindings) {
            return false
          }
        }
        true
      }
    (Func(source_params, source_ret), Func(pattern_params, pattern_ret)) =>
      if source_params.length() != pattern_params.length() {
        false
      } else {
        for i in 0..<source_params.length() {
          if !match_infer_pattern(source_params[i], pattern_params[i], bindings) {
            return false
          }
        }
        match_infer_pattern(source_ret, pattern_ret, bindings)
      }
    (_, Union(pattern_items)) => {
      for pattern_item in pattern_items {
        let branch_bindings : Map[String, @ast.TsType] = {}
        if match_infer_pattern(source, pattern_item, branch_bindings) {
          for entry in branch_bindings {
            let (name, type_) = entry
            if !bind_inferred_type(bindings, name, type_) {
              return false
            }
          }
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn substitute_inferred_type(
  type_ : @ast.TsType,
  bindings : Map[String, @ast.TsType],
) -> @ast.TsType {
  match infer_marker_name(type_) {
    Some(name) =>
      match bindings.get(name) {
        Some(type_) => return type_
        None => ()
      }
    None => ()
  }
  match type_ {
    Conditional(source, target, true_type, false_type) =>
      Conditional(
        substitute_inferred_type(source, bindings),
        substitute_inferred_type(target, bindings),
        substitute_inferred_type(true_type, bindings),
        substitute_inferred_type(false_type, bindings),
      )
    Named(name) =>
      match bindings.get(name) {
        Some(type_) => type_
        None => type_
      }
    Array(inner) => Array(substitute_inferred_type(inner, bindings))
    Tuple(items) => {
      let out : Array[@ast.TsType] = []
      for item in items {
        out.push(substitute_inferred_type(item, bindings))
      }
      Tuple(out)
    }
    Object(fields) => {
      let out : Array[(@ast.TsType, @ast.TsType)] = []
      for field in fields {
        let (key, value) = field
        out.push(
          (
            substitute_inferred_type(key, bindings),
            substitute_inferred_type(value, bindings),
          ),
        )
      }
      Object(out)
    }
    Func(params, ret) => {
      let out : Array[@ast.TsType] = []
      for param in params {
        out.push(substitute_inferred_type(param, bindings))
      }
      Func(out, substitute_inferred_type(ret, bindings))
    }
    Union(items) => {
      let out : Array[@ast.TsType] = []
      for item in items {
        out.push(substitute_inferred_type(item, bindings))
      }
      Union(out)
    }
    Intersection(items) => {
      let out : Array[@ast.TsType] = []
      for item in items {
        out.push(substitute_inferred_type(item, bindings))
      }
      Intersection(out)
    }
    Applied(name, args) => {
      let out : Array[@ast.TsType] = []
      for arg in args {
        out.push(substitute_inferred_type(arg, bindings))
      }
      Applied(name, out)
    }
    _ => type_
  }
}

///|
fn Parser::parse_conditional_type_tail(
  self : Parser,
  source : @ast.TsType,
) -> @ast.TsType raise ParseError {
  let _ = self.expect(Extends)
  let target = self.parse_intersection_type()
  let _ = self.expect(Question)
  let true_type = self.parse_type()
  let _ = self.expect(Colon)
  let false_type = self.parse_type()
  let infer_bindings : Map[String, @ast.TsType] = {}
  if match_infer_pattern(source, target, infer_bindings) {
    return substitute_inferred_type(true_type, infer_bindings)
  }
  match type_extends_simple(source, target) {
    Some(true) => true_type
    Some(false) => false_type
    None => Conditional(source, target, true_type, false_type)
  }
}

///|
/// Parse full type including union/intersection
fn Parser::parse_type(self : Parser) -> @ast.TsType raise ParseError {
  if self.check(Pipe) {
    let _ = self.advance()
    let items : Array[@ast.TsType] = [self.parse_intersection_type()]
    while self.match_(Pipe) {
      items.push(self.parse_intersection_type())
    }
    return Union(items)
  }
  if self.check(Amp) {
    let _ = self.advance()
    let items : Array[@ast.TsType] = [self.parse_type_operand()]
    while self.match_(Amp) {
      items.push(self.parse_type_operand())
    }
    return Intersection(items)
  }
  let base = self.parse_intersection_type()
  if self.check(Extends) {
    let saved_pos = self.pos
    try {
      return self.parse_conditional_type_tail(base)
    } catch {
      _ => {
        self.pos = saved_pos
        self.skip_conditional_type_tail()
        return Any
      }
    }
  }
  // Union type: T | U
  if self.check(Pipe) {
    let items : Array[@ast.TsType] = [base]
    while self.match_(Pipe) {
      items.push(self.parse_intersection_type())
    }
    if self.check(Extends) {
      let saved_pos = self.pos
      try {
        return self.parse_conditional_type_tail(Union(items))
      } catch {
        _ => {
          self.pos = saved_pos
          self.skip_conditional_type_tail()
          return Any
        }
      }
    }
    return Union(items)
  }
  base
}

///|
fn Parser::skip_conditional_type_segment(
  self : Parser,
  stop_on_question : Bool,
  stop_on_colon : Bool,
) -> Unit {
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut brace_depth = 0
  let mut angle_depth = 0
  let mut conditional_depth = 0
  while !self.check(Eof) {
    let top_level = paren_depth == 0 &&
      bracket_depth == 0 &&
      brace_depth == 0 &&
      angle_depth == 0
    match self.peek().kind {
      Question if top_level && stop_on_question && conditional_depth == 0 =>
        break
      Question if top_level => {
        conditional_depth += 1
        let _ = self.advance()
      }
      Colon if top_level && stop_on_colon && conditional_depth == 0 => break
      Colon if top_level && conditional_depth > 0 => {
        conditional_depth -= 1
        let _ = self.advance()
      }
      Semicolon | Comma | RParen | RBracket | RBrace if top_level &&
        conditional_depth == 0 => break
      Export | Declare | Interface | Type | Function | Class if top_level &&
        conditional_depth == 0 => break
      LParen => {
        paren_depth += 1
        let _ = self.advance()
      }
      RParen => {
        if paren_depth == 0 {
          break
        }
        paren_depth -= 1
        let _ = self.advance()
      }
      LBracket => {
        bracket_depth += 1
        let _ = self.advance()
      }
      RBracket => {
        if bracket_depth == 0 {
          break
        }
        bracket_depth -= 1
        let _ = self.advance()
      }
      LBrace => {
        brace_depth += 1
        let _ = self.advance()
      }
      RBrace => {
        if brace_depth == 0 {
          break
        }
        brace_depth -= 1
        let _ = self.advance()
      }
      Lt => {
        angle_depth += 1
        let _ = self.advance()
      }
      Gt => {
        if angle_depth > 0 {
          angle_depth -= 1
        }
        let _ = self.advance()
      }
      GtGt => {
        angle_depth = if angle_depth >= 2 { angle_depth - 2 } else { 0 }
        let _ = self.advance()
      }
      GtGtGt => {
        angle_depth = if angle_depth >= 3 { angle_depth - 3 } else { 0 }
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
fn Parser::skip_conditional_type_tail(self : Parser) -> Unit {
  let _ = self.advance() // consume extends
  self.skip_conditional_type_segment(true, false)
  if self.match_(Question) {
    self.skip_conditional_type_segment(false, true)
    let _ = self.match_(Colon)
    self.skip_conditional_type_segment(false, true)
  }
}

///|
/// Skip object type: { key: T; ... }
fn Parser::skip_object_type(self : Parser) -> Unit {
  let _ = self.advance() // consume {
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
/// Skip parenthesized type or function type: (T) or (x: T) => U
fn Parser::skip_paren_type(self : Parser) -> Unit raise ParseError {
  let _ = self.advance() // consume (
  let mut depth = 1
  while depth > 0 && !self.check(Eof) {
    match self.peek().kind {
      LParen => {
        depth += 1
        let _ = self.advance()
      }
      RParen => {
        depth -= 1
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
  // Check for arrow function type: => T
  if self.check(Arrow) {
    let _ = self.advance()
    let _ = self.parse_type()
  }
}

///|
/// Skip a type annotation until the top-level arrow of an arrow function.
fn Parser::skip_type_until_arrow(self : Parser) -> Unit {
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut brace_depth = 0
  let mut angle_depth = 0
  while !self.check(Eof) {
    match self.peek().kind {
      Arrow if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => break
      LParen => {
        paren_depth += 1
        let _ = self.advance()
      }
      RParen => {
        if paren_depth == 0 {
          break
        }
        paren_depth -= 1
        let _ = self.advance()
      }
      LBracket => {
        bracket_depth += 1
        let _ = self.advance()
      }
      RBracket => {
        if bracket_depth == 0 {
          break
        }
        bracket_depth -= 1
        let _ = self.advance()
      }
      LBrace => {
        brace_depth += 1
        let _ = self.advance()
      }
      RBrace => {
        if brace_depth == 0 {
          break
        }
        brace_depth -= 1
        let _ = self.advance()
      }
      Lt => {
        angle_depth += 1
        let _ = self.advance()
      }
      Gt => {
        if angle_depth > 0 {
          angle_depth -= 1
        }
        let _ = self.advance()
      }
      GtGt => {
        angle_depth = if angle_depth >= 2 { angle_depth - 2 } else { 0 }
        let _ = self.advance()
      }
      GtGtGt => {
        angle_depth = if angle_depth >= 3 { angle_depth - 3 } else { 0 }
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
/// Skip typeof operand
fn Parser::skip_typeof_operand(self : Parser) -> Unit raise ParseError {
  if self.check(Import) {
    let _ = self.advance()
    if self.check(LParen) {
      self.skip_paren_type()
    }
    while self.check(Dot) {
      let _ = self.advance()
      match self.peek().kind {
        Ident(_)
        | NumberType
        | BooleanType
        | StringType
        | VoidType
        | Type
        | New
        | Extends
        | Import
        | Export
        | From
        | As => {
          let _ = self.advance()
        }
        _ => break
      }
    }
    if self.check(Lt) {
      self.skip_type_args()
    }
    return
  }
  // Skip qualified name: x.y.z
  while self.is_ident() {
    let _ = self.advance()
    if self.check(Dot) {
      let _ = self.advance()
    } else {
      break
    }
  }
  // Skip generic args if present
  if self.check(Lt) {
    self.skip_type_args()
  }
}

///|
/// Skip type arguments: <T, U>
fn Parser::skip_type_args(self : Parser) -> Unit {
  if !self.check(Lt) {
    return
  }
  let _ = self.advance() // consume <
  let mut depth = 1
  while depth > 0 && !self.check(Eof) {
    match self.peek().kind {
      Lt => {
        depth += 1
        let _ = self.advance()
      }
      Gt => {
        depth -= 1
        let _ = self.advance()
      }
      GtGt => {
        // >> counts as two >
        depth -= 2
        let _ = self.advance()
      }
      GtGtGt => {
        // >>> counts as three >
        depth -= 3
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
/// Skip asserts clause: asserts x is T or asserts x
fn Parser::skip_asserts_clause(self : Parser) -> Unit raise ParseError {
  // asserts x
  if self.is_ident() {
    let _ = self.advance()
  }
  // is T
  if self.check(Ident("is")) {
    let _ = self.advance()
    let _ = self.parse_type()
  }
}

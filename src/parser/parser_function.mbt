// ============================================
// function
// ============================================

///|
fn Parser::skip_param_decorators(self : Parser) -> Unit raise ParseError {
  while self.match_(At) {
    let _ = self.parse_binding_ident()
    while self.match_(Dot) {
      let _ = self.parse_binding_ident()
    }
    if self.check(Lt) {
      self.skip_type_args()
    }
    if self.check(LParen) {
      let _ = self.advance()
      let mut paren_depth = 1
      let mut brace_depth = 0
      let mut bracket_depth = 0
      while paren_depth > 0 && !self.check(Eof) {
        match self.peek().kind {
          LParen => {
            paren_depth += 1
            let _ = self.advance()
          }
          RParen => {
            paren_depth -= 1
            let _ = self.advance()
          }
          LBrace => {
            brace_depth += 1
            let _ = self.advance()
          }
          RBrace => {
            if brace_depth > 0 {
              brace_depth -= 1
            }
            let _ = self.advance()
          }
          LBracket => {
            bracket_depth += 1
            let _ = self.advance()
          }
          RBracket => {
            if bracket_depth > 0 {
              bracket_depth -= 1
            }
            let _ = self.advance()
          }
          _ => {
            let _ = self.advance()
          }
        }
      }
    }
  }
}

///|
fn Parser::skip_param_modifiers(self : Parser) -> (Bool, Bool, String) {
  // Returns `(is_parameter_property, is_readonly, visibility)`. The first
  // is `true` when at least one TS-only parameter modifier (`public` /
  // `private` / `protected` / `readonly`) was consumed; `is_readonly` is
  // `true` when `readonly` was among them; `visibility` is the
  // accessibility keyword seen (`"private"` / `"protected"`, else
  // `"public"`). Constructor-parameter callers use these to materialize
  // the corresponding class field with the right readonly / visibility.
  let mut saw_property_modifier = false
  let mut saw_readonly = false
  let mut visibility = "public"
  let mut has_modifier = true
  while has_modifier {
    has_modifier = false
    match self.peek().kind {
      Ident(name) if name == "public" ||
        name == "private" ||
        name == "protected" ||
        name == "readonly" ||
        name == "override" =>
        match self.peek_at(1).kind {
          Ident(_)
          | PrivateIdent(_)
          | LBrace
          | LBracket
          | Yield
          | NumberType
          | BooleanType
          | StringType
          | VoidType
          | IntType
          | Type
          | Of
          | In => {
            // `override` alone isn't a "parameter property"; the
            // other four (public/private/protected/readonly) are.
            if name != "override" {
              saw_property_modifier = true
            }
            if name == "readonly" {
              saw_readonly = true
            }
            if name == "private" || name == "protected" {
              visibility = name
            }
            let _ = self.advance()
            has_modifier = true
          }
          _ => ()
        }
      _ => ()
    }
  }
  (saw_property_modifier, saw_readonly, visibility)
}

///|
fn wrap_optional_ts_type(type_ : @ast.TsType) -> @ast.TsType {
  match type_ {
    @ast.TsType::Undefined | @ast.TsType::Null =>
      @ast.TsType::Union([type_, @ast.TsType::Undefined])
    @ast.TsType::Union(items) => {
      for item in items {
        match item {
          @ast.TsType::Undefined | @ast.TsType::Null => return type_
          _ => ()
        }
      }
      @ast.TsType::Union([type_, @ast.TsType::Undefined])
    }
    _ => @ast.TsType::Union([type_, @ast.TsType::Undefined])
  }
}

///|
// / parameter
fn Parser::parse_param(self : Parser) -> @ast.TsParam raise ParseError {
  self.skip_param_decorators()
  let (is_param_property, is_readonly_param, visibility_param) = self.skip_param_modifiers()
  let is_rest = self.match_ellipsis()
  let binding = self.parse_binding_pattern()
  let name = self.binding_first_name(binding)
  // TS1359: a *parameter* named `await` inside an async function
  // (`async function foo(await) {}`) -- the parameter binds in the async
  // body scope where `await` is reserved. The function *name* is exempt
  // (it binds in the enclosing, non-async scope: `async function await()`
  // is legal), which is why this lives here and not in
  // `parse_binding_ident`.
  if name == "await" && self.in_async {
    self.grammar_misuses.push(
      "`await` cannot be used as a parameter name in an async context",
    )
  }
  // TS1212: a parameter named `yield` inside a *generator* -- reserved in
  // generator grammar (`function * f(yield) {}`).
  if name == "yield" && self.in_generator {
    self.grammar_misuses.push(
      "`yield` cannot be used as a parameter name in a generator",
    )
  }
  // Record the name (with its `readonly`-ness and visibility) so the
  // surrounding constructor parser can synthesize `this.name = name`
  // field assigns and materialize the corresponding class field. Only
  // constructor-param parsing pushes a slot, so non-constructor params
  // are no-ops.
  if is_param_property && self.param_property_scopes.length() > 0 {
    let top = self.param_property_scopes.length() - 1
    self.param_property_scopes[top].push(
      (name, is_readonly_param, visibility_param),
    )
  } else if is_param_property {
    // A parameter property outside a constructor parameter list (free
    // function, arrow, non-constructor method, or call / construct
    // signature). TypeScript permits these modifiers only in a constructor
    // implementation, so this is a TS2369. Record it for the checker; the
    // modifier was already consumed, so parsing otherwise proceeds normally.
    self.param_property_misuses.push(name)
  }
  let is_optional = self.match_(Question)
  // type ()
  let base_type = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any // type Any
  }
  let type_ = if is_optional {
    wrap_optional_ts_type(base_type)
  } else {
    base_type
  }
  // check
  let default : @ast.TsExpr? = if self.match_(Eq) {
    Some(self.parse_assignment())
  } else {
    None
  }
  // TS1015: a parameter cannot be both optional (`x?`) and have an
  // initializer (`x = e`). The `?` is otherwise lost into the parameter
  // type below, so record the conflict here where both facts are visible.
  if is_optional && not(default is None) {
    self.param_optional_initializer_misuses.push(name)
  }
  { name, binding: Some(binding), is_rest, type_, default }
}

///|
// / parameter
fn Parser::parse_params(self : Parser) -> Array[@ast.TsParam] raise ParseError {
  let params : Array[@ast.TsParam] = []
  if !self.check(RParen) {
    params.push(self.parse_param())
    while self.match_(Comma) {
      if self.check(RParen) {
        break
      }
      params.push(self.parse_param())
    }
  }
  // Check for duplicate parameter names
  // In strict mode or with non-simple parameters (default, rest, destructuring),
  // duplicate names are forbidden
  let has_default = params.iter().any(fn(p) { !(p.default is None) })
  let has_rest = params.iter().any(fn(p) { p.is_rest })
  let has_destructuring = params
    .iter()
    .any(fn(p) {
      match p.binding {
        Some(@ast.TsBinding::Array(_)) | Some(@ast.TsBinding::Object(_)) => true
        _ => false
      }
    })
  let is_simple = !has_default && !has_rest && !has_destructuring
  // Collect all bound names
  let all_names : Array[String] = []
  for param in params {
    match param.binding {
      Some(binding) => self.collect_binding_names(binding, all_names)
      None => ()
    }
  }
  // Check for duplicates
  let seen : Map[String, Bool] = {}
  for name in all_names {
    if seen.contains(name) {
      // In strict mode or with non-simple params, duplicates are errors
      if self.in_strict || !is_simple {
        raise ParseError("Duplicate parameter name '\{name}' not allowed")
      }
    }
    seen[name] = true
  }
  params
}

///|
// / function
pub fn Parser::parse_function(self : Parser) -> @ast.TsFunc raise ParseError {
  // Capture the position of `function` so we can look up an
  // attached JSDoc block (for `@param {Type}` / `@returns {Type}`
  // overlay below).
  let func_kw_pos = self.peek().pos
  let _ = self.expect(Function)
  let is_generator = self.match_(Star)
  let is_async = self.in_async
  let name = self.parse_binding_ident()
  // TS1212: a *generator* cannot be named `yield` (`function * yield() {}`)
  // -- inside generator grammar `yield` is a reserved word. A plain
  // function named `yield` is legal in non-strict code and stays silent.
  if is_generator && name == "yield" {
    self.grammar_misuses.push(
      "`yield` cannot be used as the name of a generator function",
    )
  }
  let (type_params, const_type_params, type_param_bounds) = self.parse_type_param_names_bounds_and_const_flags()
  let local_type_param_bound_len = self.push_local_type_param_bounds(
    type_param_bounds,
  )
  let _ = self.expect(LParen)
  let params = self.parse_params()
  let _ = self.expect(RParen)
  // return valuetype ()
  let return_type = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any // type Any
  }
  self.restore_local_type_param_bounds(local_type_param_bound_len)
  if self.check(Semicolon) {
    let _ = self.advance()
    return {
      name,
      type_params,
      const_type_params,
      type_param_bounds,
      params,
      return_type,
      body: { stmts: [], stmt_positions: [] },
      is_generator,
      is_async,
    }
  }
  if !self.check(LBrace) {
    return {
      name,
      type_params,
      const_type_params,
      type_param_bounds,
      params,
      return_type,
      body: { stmts: [], stmt_positions: [] },
      is_generator,
      is_async,
    }
  }
  // Save and set function context (new function scope resets iteration/switch/labels context)
  let prev_generator = self.in_generator
  let prev_async = self.in_async
  let prev_function = self.in_function
  let prev_iteration = self.in_iteration
  let prev_switch = self.in_switch
  // Save labels and clear for new function scope (labels don't cross function boundaries)
  let prev_labels : Array[String] = []
  for label in self.labels {
    prev_labels.push(label)
  }
  if is_generator {
    self.in_generator = true
  }
  self.in_async = false // Reset for nested functions
  self.in_function = true
  self.in_iteration = false
  self.in_switch = false
  // Clear labels for new function scope
  while self.labels.length() > 0 {
    let _ = self.labels.pop()
  }
  let body = self.parse_block()
  self.in_generator = prev_generator
  self.in_async = prev_async
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
  // JSDoc type overlay: when the function lacks explicit type
  // annotations (parameters resolved to `Any` because no `: T`
  // was present, return type fell through to `Any`) AND a JSDoc
  // block precedes the `function` keyword, lift `@param {Type}` /
  // `@returns {Type}` brace contents into the AST so downstream
  // type-driven passes can reason about them.
  let final_params = apply_jsdoc_param_overlay(
    self.jsdoc_at_pos,
    func_kw_pos,
    params,
  )
  let final_return = apply_jsdoc_return_overlay(
    self.jsdoc_at_pos,
    func_kw_pos,
    return_type,
  )
  {
    name,
    type_params,
    const_type_params,
    type_param_bounds,
    params: final_params,
    return_type: final_return,
    body,
    is_generator,
    is_async,
  }
}

///|
fn apply_jsdoc_param_overlay(
  jsdoc_at_pos : Map[Int, JsdocBlock],
  pos : Int,
  params : Array[@ast.TsParam],
) -> Array[@ast.TsParam] {
  let jb = match jsdoc_at_pos.get(pos) {
    Some(b) => b
    None => return params
  }
  // Build a name -> JSDoc-type-string map.
  let by_name : Map[String, String] = {}
  for t in jb.tags {
    match t {
      Param(pname, Some(ty), _) => by_name[pname] = ty
      _ => ()
    }
  }
  if by_name.is_empty() {
    return params
  }
  let out : Array[@ast.TsParam] = []
  for p in params {
    let needs_overlay = match p.type_ {
      Any => true
      _ => false
    }
    if !needs_overlay {
      out.push(p)
      continue
    }
    match by_name.get(p.name) {
      Some(raw) =>
        match try_parse_jsdoc_type(raw) {
          Some(ty) => out.push({ ..p, type_: ty })
          None => out.push(p)
        }
      None => out.push(p)
    }
  }
  out
}

///|
fn apply_jsdoc_return_overlay(
  jsdoc_at_pos : Map[Int, JsdocBlock],
  pos : Int,
  return_type : @ast.TsType,
) -> @ast.TsType {
  match return_type {
    Any => ()
    _ => return return_type
  }
  let jb = match jsdoc_at_pos.get(pos) {
    Some(b) => b
    None => return return_type
  }
  for t in jb.tags {
    match t {
      Returns(Some(ty_str), _) =>
        match try_parse_jsdoc_type(ty_str) {
          Some(ty) => return ty
          None => ()
        }
      _ => ()
    }
  }
  return_type
}

///|
/// Try to lift a JSDoc brace-content string into a `TsType`. Many
/// JSDoc forms are already valid TS (`string`, `number`,
/// `string | number`, `Array<number>`); these parse directly. JSDoc-
/// specific forms (`function(...)`, `Object<K, V>`, `?T`, `*`) get
/// a light textual translation before the parse attempt; anything
/// that still fails resolves to `None` and the AST keeps `Any`.
fn try_parse_jsdoc_type(raw : String) -> @ast.TsType? {
  let translated = translate_jsdoc_type(raw)
  try parse_type_from_source(translated) catch {
    _ => None
  } noraise {
    ty => Some(ty)
  }
}

///|
/// Minimal JSDoc → TS textual translation. Covers the common
/// shapes; unrecognized syntax is left alone (the downstream parse
/// will simply fail and the overlay falls back to `Any`).
fn translate_jsdoc_type(raw : String) -> String {
  let s = raw.trim().to_owned()
  // `*` → `any`
  if s == "*" {
    return "any"
  }
  // `?T` → `T | null` for any type expression.
  if s.has_prefix("?") {
    let inner = s[1:].to_owned().trim().to_owned()
    if inner.length() > 0 {
      return "(\{inner} | null)"
    }
  }
  // `!T` → `T` (strip the non-null marker; TS lacks a 1:1 syntax
  // and `NonNullable<T>` is more invasive than warranted here).
  if s.has_prefix("!") {
    let inner = s[1:].to_owned().trim().to_owned()
    return inner
  }
  // `Object<K, V>` → `Record<K, V>`.
  if s.has_prefix("Object<") {
    return "Record" + s[6:].to_owned()
  }
  // `function(T1, T2): R` → `(_0: T1, _1: T2) => R`
  // `function(): R` → `() => R`
  if s.has_prefix("function(") {
    match translate_jsdoc_function_type(s) {
      Some(ts) => return ts
      None => ()
    }
  }
  s
}

///|
/// Translate `function(P1, P2): R` → `(_0: P1, _1: P2) => R`.
/// Returns `None` when the input doesn't match the expected shape.
fn translate_jsdoc_function_type(s : String) -> String? {
  // Find the closing `)` of the parameter list, respecting nesting.
  let len = s.length()
  // s starts with "function("
  let start = 9 // length of "function("
  let mut depth = 1
  let mut i = start
  while i < len && depth > 0 {
    let c = s[i]
    if c == '(' || c == '<' || c == '[' || c == '{' {
      depth = depth + 1
    } else if c == ')' || c == '>' || c == ']' || c == '}' {
      depth = depth - 1
    }
    if depth > 0 {
      i = i + 1
    }
  }
  if depth != 0 {
    return None
  }
  let params_str = s[start:i].to_owned().trim().to_owned()
  // Everything after `)` — optionally `: ReturnType`.
  let rest = s[i + 1:len].to_owned().trim().to_owned()
  let return_type = if rest.has_prefix(":") {
    rest[1:].to_owned().trim().to_owned()
  } else {
    "any"
  }
  // Split params on top-level `,`.
  let params : Array[String] = []
  if params_str.length() > 0 {
    let mut depth2 = 0
    let mut start2 = 0
    for j in 0..<params_str.length() {
      let c = params_str[j]
      if c == '(' || c == '<' || c == '[' || c == '{' {
        depth2 = depth2 + 1
      } else if c == ')' || c == '>' || c == ']' || c == '}' {
        depth2 = depth2 - 1
      } else if c == ',' && depth2 == 0 {
        params.push(params_str[start2:j].to_owned().trim().to_owned())
        start2 = j + 1
      }
    }
    params.push(params_str[start2:].to_owned().trim().to_owned())
  }
  // Build `(_0: P0, _1: P1, ...) => R`.
  let mut ts_params = ""
  for k, p in params {
    if k > 0 {
      ts_params = ts_params + ", "
    }
    ts_params = ts_params + "_\{k}: \{p}"
  }
  Some("(\{ts_params}) => \{return_type}")
}

///|
// / functionexpression()
fn Parser::parse_function_expr(self : Parser) -> @ast.TsFunc raise ParseError {
  let _ = self.expect(Function)
  let is_generator = self.match_(Star)
  let is_async = self.in_async
  let name = match self.peek().kind {
    Ident(_)
    | Yield
    | NumberType
    | BooleanType
    | StringType
    | VoidType
    | IntType
    | Type
    | Let
    | Switch
    | Case
    | Default
    | With
    | Debugger
    | Import
    | Export
    | From
    | As
    | Of
    | In => self.parse_binding_ident()
    _ => "<anon>"
  }
  let (type_params, const_type_params, type_param_bounds) = self.parse_type_param_names_bounds_and_const_flags()
  let _ = self.expect(LParen)
  let params = self.parse_params()
  let _ = self.expect(RParen)
  let return_type = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any
  }
  // Save and set function context (new function scope resets iteration/switch/labels context)
  let prev_generator = self.in_generator
  let prev_async = self.in_async
  let prev_function = self.in_function
  let prev_iteration = self.in_iteration
  let prev_switch = self.in_switch
  // Save labels and clear for new function scope (labels don't cross function boundaries)
  let prev_labels : Array[String] = []
  for label in self.labels {
    prev_labels.push(label)
  }
  if is_generator {
    self.in_generator = true
  }
  self.in_async = false // Reset for nested functions
  self.in_function = true
  self.in_iteration = false
  self.in_switch = false
  // Clear labels for new function scope
  while self.labels.length() > 0 {
    let _ = self.labels.pop()
  }
  let body = self.parse_block()
  self.in_generator = prev_generator
  self.in_async = prev_async
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
  {
    name,
    type_params,
    const_type_params,
    type_param_bounds,
    params,
    return_type,
    body,
    is_generator,
    is_async,
  }
}

///|
/// Skip generic type parameters <T, U extends Foo, V = Default>
fn Parser::skip_type_params(self : Parser) -> Unit {
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
fn Parser::skip_type_param_tail_until_delim(self : Parser) -> Unit {
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut brace_depth = 0
  let mut angle_depth = 0
  while !self.check(Eof) {
    match self.peek().kind {
      Comma if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => break
      Gt if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => break
      LParen => {
        paren_depth += 1
        let _ = self.advance()
      }
      RParen => {
        if paren_depth > 0 {
          paren_depth -= 1
        }
        let _ = self.advance()
      }
      LBracket => {
        bracket_depth += 1
        let _ = self.advance()
      }
      RBracket => {
        if bracket_depth > 0 {
          bracket_depth -= 1
        }
        let _ = self.advance()
      }
      LBrace => {
        brace_depth += 1
        let _ = self.advance()
      }
      RBrace =>
        if brace_depth > 0 {
          brace_depth -= 1
          let _ = self.advance()
        } else {
          break
        }
      Lt => {
        angle_depth += 1
        let _ = self.advance()
      }
      Gt =>
        if angle_depth > 0 {
          angle_depth -= 1
          let _ = self.advance()
        } else {
          break
        }
      GtGt =>
        if angle_depth >= 2 {
          angle_depth -= 2
          let _ = self.advance()
        } else if angle_depth == 1 {
          let tok = self.advance()
          self.pending_gt += 1
          self.pending_gt_pos = tok.pos
          angle_depth = 0
          break
        } else {
          break
        }
      GtGtGt =>
        if angle_depth >= 3 {
          angle_depth -= 3
          let _ = self.advance()
        } else if angle_depth == 2 {
          let tok = self.advance()
          self.pending_gt += 1
          self.pending_gt_pos = tok.pos
          angle_depth = 0
          break
        } else if angle_depth == 1 {
          let tok = self.advance()
          self.pending_gt += 2
          self.pending_gt_pos = tok.pos
          angle_depth = 0
          break
        } else {
          break
        }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
fn Parser::parse_type_param_names_and_bounds(
  self : Parser,
) -> (Array[String], Array[(String, @ast.TsType)]) {
  let (names, _, bounds) = self.parse_type_param_names_bounds_and_const_flags()
  (names, bounds)
}

///|
/// Like `parse_type_param_names_and_bounds` but also returns a
/// parallel array of `const`-modifier flags (one per parameter).
/// `<const T extends ...>` flips the matching `const_flags` entry to
/// `true`; subsequent generic-inference passes consult this to skip
/// literal widening on `T`.
fn Parser::parse_type_param_names_bounds_and_const_flags(
  self : Parser,
) -> (Array[String], Array[Bool], Array[(String, @ast.TsType)]) {
  let names : Array[String] = []
  let const_flags : Array[Bool] = []
  let bounds : Array[(String, @ast.TsType)] = []
  self.last_type_params_had_default = false
  // Tracked in a local (not the parser field) because parsing a parameter's
  // bound can recursively invoke this function for a nested generic function
  // type and clobber the field; the field is assigned once at the end from
  // this local so the outermost call's value wins.
  let mut had_default = false
  if !self.check(Lt) {
    return (names, const_flags, bounds)
  }
  let _ = self.advance()
  while !self.check(Eof) {
    if self.check(Gt) {
      let _ = self.advance()
      break
    }
    // Optional `const` modifier introduced in TypeScript 5.0:
    // `<const T extends ...>`. Captured per-parameter so the
    // generic-inference pass can keep literal types narrow.
    let is_const = if self.check(Const) {
      let _ = self.advance()
      true
    } else {
      false
    }
    // Variance modifiers `in` / `out` (TypeScript 4.7+):
    // `<out T extends ..., in U, in out V>`. Both keywords are
    // context-sensitive and only act as modifiers when followed by an
    // identifier; they don't affect the erased generic shape, so consume
    // and discard. `in` lexes as the `In` keyword, `out` lexes as a plain
    // identifier.
    let mut consumed_variance = true
    while consumed_variance {
      consumed_variance = false
      if self.check(In) {
        match self.peek_at(1).kind {
          Ident(_) => {
            let _ = self.advance()
            consumed_variance = true
          }
          _ => ()
        }
      }
      match self.peek().kind {
        Ident("out") =>
          match self.peek_at(1).kind {
            Ident(_) => {
              let _ = self.advance()
              consumed_variance = true
            }
            _ => ()
          }
        _ => ()
      }
    }
    let mut name = ""
    if self.is_qualified_type_name_part(0) {
      name = self.parse_binding_ident() catch { _ => "_" }
    } else {
      self.skip_type_param_tail_until_delim()
      if self.check(Comma) {
        let _ = self.advance()
        continue
      }
      if self.check(Gt) {
        let _ = self.advance()
      }
      break
    }
    names.push(name)
    const_flags.push(is_const)
    // Record every type-parameter name seen anywhere (class / interface /
    // alias / function / method / call+construct-signature generics). The
    // TS2314 bare-reference check excludes these names: a bare `Named(X)` that
    // is also a type-parameter name might be an in-scope type parameter rather
    // than a reference to a same-named generic declaration (e.g. `new <Y, Z,
    // A, B>(...)` uses `B` as a type parameter while a class `B<U, V>` also
    // exists), so skipping it keeps the check false-positive-free.
    self.interface_member_modifier_misuses.push("<type-param-name>\{name}")
    if self.match_(Extends) {
      let saved_pos = self.pos
      let saved_pending_gt = self.pending_gt
      let saved_pending_gt_pos = self.pending_gt_pos
      try {
        let bound = self.parse_type()
        bounds.push((name, bound))
      } catch {
        _ => {
          self.pos = saved_pos
          self.pending_gt = saved_pending_gt
          self.pending_gt_pos = saved_pending_gt_pos
          self.skip_type_param_tail_until_delim()
        }
      }
    }
    if self.match_(Eq) {
      had_default = true
      self.skip_type_param_tail_until_delim()
    }
    if self.check(Comma) {
      let _ = self.advance()
      continue
    }
    if self.check(Gt) {
      let _ = self.advance()
      break
    }
  }
  self.last_type_params_had_default = had_default
  (names, const_flags, bounds)
}

///|
fn Parser::push_local_type_param_bounds(
  self : Parser,
  bounds : Array[(String, @ast.TsType)],
) -> Int {
  let old_len = self.local_type_param_bounds.length()
  for bound in bounds {
    self.local_type_param_bounds.push(bound)
  }
  old_len
}

///|
fn Parser::restore_local_type_param_bounds(
  self : Parser,
  old_len : Int,
) -> Unit {
  while self.local_type_param_bounds.length() > old_len {
    let _ = self.local_type_param_bounds.pop()
  }
}

///|
/// Parse the `extends Foo<A>, Bar.Baz, Qux<X, Y>` clause and return both
/// the base names and the per-base type-argument lists. Used by the
/// interface parser so the checker can substitute `<A>` when walking
/// the inheritance chain.
fn Parser::parse_extends_clause_until_body(
  self : Parser,
) -> (Array[String], Array[Array[@ast.TsType]]) {
  let names : Array[String] = []
  let args_per_name : Array[Array[@ast.TsType]] = []
  if !self.check(Extends) {
    return (names, args_per_name)
  }
  let _ = self.advance() // consume extends
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut angle_depth = 0
  let mut expect_name = true
  while !self.check(Eof) {
    match self.peek().kind {
      LBrace if paren_depth == 0 && bracket_depth == 0 && angle_depth == 0 =>
        break
      Ident(name) if expect_name &&
        paren_depth == 0 &&
        bracket_depth == 0 &&
        angle_depth == 0 => {
        let mut full_name = name
        let _ = self.advance()
        while self.check(Dot) {
          match self.peek_at(1).kind {
            Ident(part) => {
              let _ = self.advance()
              let _ = self.advance()
              full_name = full_name + "." + part
            }
            _ => break
          }
        }
        // Capture type arguments if the next token is `<`. Defensive:
        // fall back to the depth-counting skip when parse_type throws
        // (e.g. on malformed input).
        let base_args : Array[@ast.TsType] = []
        if self.check(Lt) && paren_depth == 0 && bracket_depth == 0 {
          let saved = self.pos
          try {
            let _ = self.expect(Lt)
            let first = self.parse_type()
            base_args.push(first)
            while self.match_(Comma) {
              if self.check(Gt) || self.check(GtGt) || self.check(GtGtGt) {
                break
              }
              base_args.push(self.parse_type())
            }
            // Accept `>` / `>>` / `>>>` as the closing token; the parser
            // already handles the `>>`/`>>>` ASR-rewrite for nested
            // type-arg lists.
            if self.match_(Gt) {
              ()
            } else if self.check(GtGt) {
              // Consume one `>` and leave a synthetic `Gt` for the outer
              // context — easiest: advance and let the outer depth
              // counter resync.
              let _ = self.advance()
            } else if self.check(GtGtGt) {
              let _ = self.advance()
            }
          } catch {
            _ => {
              self.pos = saved
              base_args.clear()
            }
          } noraise {
            _ => ()
          }
        }
        names.push(full_name)
        args_per_name.push(base_args)
        expect_name = false
      }
      LParen => {
        paren_depth += 1
        let _ = self.advance()
      }
      RParen => {
        if paren_depth > 0 {
          paren_depth -= 1
        }
        let _ = self.advance()
      }
      LBracket => {
        bracket_depth += 1
        let _ = self.advance()
      }
      RBracket => {
        if bracket_depth > 0 {
          bracket_depth -= 1
        }
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
      Comma => {
        if paren_depth == 0 && bracket_depth == 0 && angle_depth == 0 {
          expect_name = true
        }
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
  (names, args_per_name)
}

///|
// True when an accessibility modifier (`private` / `public` / `protected`) is
// being used as a *modifier* on the next interface / type-literal member — i.e.
// it's one of those keywords AND the following token begins a member name. Such
// a modifier is illegal on a type member (TS1070); the caller records the
// diagnostic, consumes the keyword, and parses the member as usual. Reuses the
// same member-start lookahead as the `readonly` modifier so a property literally
// named `private` (`{ private: string }`) is not misread as a modifier.
fn Parser::can_consume_interface_accessibility_modifier(self : Parser) -> Bool {
  let is_acc = match self.peek().kind {
    Ident(n) => n == "private" || n == "public" || n == "protected"
    _ => false
  }
  if !is_acc {
    return false
  }
  // A modifier must sit on the SAME line as the member it modifies. With a line
  // break after the keyword, ASI splits it into its own property signature
  // (`interface I { protected \n p }` declares members `protected` and `p`,
  // which TS accepts) — so a newline before the next token means this is a
  // member *name*, not a modifier.
  let next = self.peek_at(1)
  if next.has_newline_before {
    return false
  }
  token_starts_interface_member(next.kind)
}

///|
fn Parser::can_consume_interface_readonly_modifier(self : Parser) -> Bool {
  if !self.check(Ident("readonly")) {
    return false
  }
  token_starts_interface_member(self.peek_at(1).kind)
}

///|
// True when `kind` can begin an interface / type-literal member name (a plain
// identifier, string / numeric literal key, index-signature `[`, call / new
// signature, or any of the contextual keywords that double as member names).
fn token_starts_interface_member(kind : TokenKind) -> Bool {
  match kind {
    Ident(_)
    | Str(_)
    | Int(_)
    | Number(_)
    | LBracket
    | New
    | Finally
    | Try
    | Catch
    | Throw
    | Delete
    | Debugger
    | Type
    | In
    | Of
    | For
    | From
    | With
    | Typeof
    | Return
    | If
    | Else
    | While
    | Do
    | Switch
    | Case
    | Default
    | Break
    | Continue
    | Extends
    | Class
    | Function
    | Var
    | Let
    | Const
    | StringType
    | NumberType
    | BooleanType
    | VoidType
    | IntType
    | Import
    | Export
    | As
    | Yield
    | Instanceof
    | Declare => true
    _ => false
  }
}

///|
// / interface
pub fn Parser::parse_interface(
  self : Parser,
) -> @ast.TsInterface raise ParseError {
  let _ = self.expect(Interface)
  let name = match self.advance().kind {
    Ident(n) => n
    k => raise ParseError("Expected interface name, got \{k}")
  }
  let (type_params, const_flags, type_param_bounds) = self.parse_type_param_names_bounds_and_const_flags()
  // TS2314: a generic interface with no defaulted type parameter requires all
  // of its type arguments, so a bare reference (`I` without `<...>`) is an
  // error. Recorded via the shared channel; the checker consults it.
  if type_params.length() > 0 && not(self.last_type_params_had_default) {
    self.interface_member_modifier_misuses.push(
      "<generic-noarg-required>\{name}",
    )
  }
  // TS1277: a `const` modifier on a type parameter is only valid on a
  // function, method, or class. An interface's own type-parameter list is
  // none of those, so `interface I<const T>` is always an error. Record it
  // through the shared interface-misuse channel with a distinct sentinel.
  for i, name_i in type_params {
    if i < const_flags.length() && const_flags[i] {
      self.interface_member_modifier_misuses.push("<const-typeparam>\{name_i}")
    }
  }
  let local_type_param_bound_len = self.push_local_type_param_bounds(
    type_param_bounds,
  )
  let (extends_names, extends_args) = self.parse_extends_clause_until_body()
  let _ = self.expect(LBrace)
  let fields : Array[(String, @ast.TsType)] = []
  let readonly_fields : Array[String] = []
  let index_signatures : Array[(@ast.TsType, @ast.TsType)] = []
  let method_type_params : Array[(String, Array[String])] = []
  while !self.check(RBrace) && !self.check(Eof) {
    // TS1070: an accessibility modifier (`private` / `public` / `protected`)
    // is never valid on an interface member. Record it, consume the keyword,
    // and parse the member as usual (the `readonly` modifier — which IS legal —
    // is handled separately below). `name` is the member it precedes.
    while self.can_consume_interface_accessibility_modifier() {
      let _ = self.advance()
      let member = match self.peek().kind {
        Ident(n) => n
        _ => "<member>"
      }
      self.interface_member_modifier_misuses.push("\{name}.\{member}")
    }
    // Skip readonly modifier
    let mut is_readonly_field = false
    if self.can_consume_interface_readonly_modifier() {
      let _ = self.advance()
      is_readonly_field = true
    }
    // Parse field/method name
    let field_name : String = match self.peek().kind {
      // Call signature: (...): T
      LParen => "<call>"
      // Generic call signature: <T>(...): U
      Lt => {
        self.skip_type_params()
        "<call>"
      }
      // Constructor signature: new(...): T
      New => {
        let _ = self.advance()
        "<new>"
      }
      // Computed property / index signature: [key: T]: U or [Symbol.xxx]: T
      LBracket => {
        let _ = self.advance()
        // An index signature has the canonical form `[<ident>: <type>]: <type>`,
        // distinguished from a computed property like `[Symbol.iterator]` by
        // the `<ident>` immediately followed by `:`. When recognised we parse
        // the key type directly so later passes can lower the signature into
        // `op_get` / `op_set` accessors instead of dropping the field.
        let is_index_sig_start = match self.peek().kind {
          Ident(_) => self.peek_at(1).kind == Colon
          _ => false
        }
        if is_index_sig_start {
          let _ = self.advance() // consume index name (ignored)
          let _ = self.expect(Colon)
          let key_type = self.parse_type()
          let _ = self.expect(RBracket)
          // Optional `?` is not meaningful on index signatures; consume to be
          // forgiving but ignore.
          let _ = self.match_(Question)
          let value_type = if self.check(Colon) {
            let _ = self.advance()
            self.parse_type()
          } else {
            @ast.TsType::Any
          }
          // Stash on a dedicated index_signatures channel so bridge passes
          // can lower the dynamic key/value pair to `op_get`/`op_set`
          // accessors without contaminating the regular named-field walk.
          index_signatures.push((key_type, value_type))
          let _ = is_readonly_field
          if self.check(Semicolon) || self.check(Comma) {
            let _ = self.advance()
          }
          continue
        }
        let mut saw_colon = false
        while !self.check(RBracket) && !self.check(Eof) {
          if self.check(Colon) {
            saw_colon = true
          }
          let _ = self.advance()
        }
        let _ = self.expect(RBracket)
        if saw_colon {
          "<index_signature>"
        } else {
          "<computed>"
        }
      }
      // Regular identifier
      Ident(n) => {
        let _ = self.advance()
        n
      }
      // String literal as field name: "fieldName"
      Str(s) => {
        let _ = self.advance()
        s
      }
      // Number literal as field name: 0, 1, etc. Both `Int` (integers that
      // fit in i32) and `Number` (anything else: `1.0`, `1e9`, etc.) are
      // valid TS property keys.
      Int(n) => {
        let _ = self.advance()
        n.to_string()
      }
      Number(d) => {
        let _ = self.advance()
        d.to_string()
      }
      // Keywords as field names (TypeScript allows this)
      Finally => {
        let _ = self.advance()
        "finally"
      }
      Try => {
        let _ = self.advance()
        "try"
      }
      Catch => {
        let _ = self.advance()
        "catch"
      }
      Throw => {
        let _ = self.advance()
        "throw"
      }
      Delete => {
        let _ = self.advance()
        "delete"
      }
      Debugger => {
        let _ = self.advance()
        "debugger"
      }
      Type => {
        let _ = self.advance()
        "type"
      }
      In => {
        let _ = self.advance()
        "in"
      }
      Of => {
        let _ = self.advance()
        "of"
      }
      For => {
        let _ = self.advance()
        "for"
      }
      From => {
        let _ = self.advance()
        "from"
      }
      With => {
        let _ = self.advance()
        "with"
      }
      Typeof => {
        let _ = self.advance()
        "typeof"
      }
      Return => {
        let _ = self.advance()
        "return"
      }
      If => {
        let _ = self.advance()
        "if"
      }
      Else => {
        let _ = self.advance()
        "else"
      }
      While => {
        let _ = self.advance()
        "while"
      }
      Do => {
        let _ = self.advance()
        "do"
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
      Break => {
        let _ = self.advance()
        "break"
      }
      Continue => {
        let _ = self.advance()
        "continue"
      }
      Extends => {
        let _ = self.advance()
        "extends"
      }
      Class => {
        let _ = self.advance()
        "class"
      }
      Function => {
        let _ = self.advance()
        "function"
      }
      Var => {
        let _ = self.advance()
        "var"
      }
      Let => {
        let _ = self.advance()
        "let"
      }
      Const => {
        let _ = self.advance()
        "const"
      }
      StringType => {
        let _ = self.advance()
        "string"
      }
      NumberType => {
        let _ = self.advance()
        "number"
      }
      BooleanType => {
        let _ = self.advance()
        "boolean"
      }
      VoidType => {
        let _ = self.advance()
        "void"
      }
      IntType => {
        let _ = self.advance()
        "int"
      }
      Import => {
        let _ = self.advance()
        "import"
      }
      Export => {
        let _ = self.advance()
        "export"
      }
      As => {
        let _ = self.advance()
        "as"
      }
      Yield => {
        let _ = self.advance()
        "yield"
      }
      Instanceof => {
        let _ = self.advance()
        "instanceof"
      }
      Declare => {
        let _ = self.advance()
        "declare"
      }
      // Literal-keyword identifiers also stand in as property names.
      Bool(true) => {
        let _ = self.advance()
        "true"
      }
      Bool(false) => {
        let _ = self.advance()
        "false"
      }
      Null => {
        let _ = self.advance()
        "null"
      }
      // Additional reserved words allowed as interface field names —
      // TS accepts every keyword in property-name position.
      Interface => {
        let _ = self.advance()
        "interface"
      }
      k =>
        raise ParseError("Expected field name at \{self.peek().pos}, got \{k}")
    }
    // Capture method-level type parameters `<T>` so the checker can keep
    // a generic method's shadowing type parameter distinct from the
    // interface's own. (Only meaningful for method signatures; harmless
    // on properties, which never carry `<...>`.)
    let (m_type_params, _) = self.parse_type_param_names_and_bounds()
    // Check for optional marker ?
    let is_optional = self.match_(Question)
    // Method signature: name(...): T or name<T>(...): U
    if self.check(LParen) {
      let _ = self.advance()
      let method_params = self.parse_params()
      let _ = self.expect(RParen)
      // TS2371: a parameter initializer (`x = 1`) is only allowed in an
      // implementation signature. An interface method / call signature never
      // has a body, so any default here is an error. Recorded via the shared
      // interface-member-misuse channel with a `<param-init>` sentinel.
      for param in method_params {
        if !(param.default is None) {
          self.interface_member_modifier_misuses.push(
            "<param-init>\{field_name}.\{param.name}",
          )
        }
      }
      // Return type
      let return_type = if self.check(Colon) {
        let _ = self.advance()
        self.parse_type()
      } else {
        @ast.TsType::Void
      }
      let param_types : Array[@ast.TsType] = []
      for param in method_params {
        param_types.push(param.type_)
      }
      let field_type = @ast.TsType::Func(param_types, return_type)
      if field_name != "<index_signature>" {
        fields.push(
          (
            field_name,
            if is_optional {
              wrap_optional_ts_type(field_type)
            } else {
              field_type
            },
          ),
        )
        if m_type_params.length() > 0 {
          method_type_params.push((field_name, m_type_params))
        }
      }
    } else if self.check(Colon) {
      // Property: name: T
      let _ = self.advance()
      let field_type = self.parse_type()
      if field_name != "<index_signature>" {
        fields.push(
          (
            field_name,
            if is_optional {
              wrap_optional_ts_type(field_type)
            } else {
              field_type
            },
          ),
        )
      }
    } else {
      // No type annotation - use Any
      let field_type = @ast.TsType::Any
      if field_name != "<index_signature>" {
        fields.push(
          (
            field_name,
            if is_optional {
              wrap_optional_ts_type(field_type)
            } else {
              field_type
            },
          ),
        )
      }
    }
    if is_readonly_field {
      readonly_fields.push(field_name)
    }
    // Skip trailing semicolon or comma (both optional)
    if self.check(Semicolon) || self.check(Comma) {
      let _ = self.advance()
    }
  }
  let _ = self.expect(RBrace)
  self.restore_local_type_param_bounds(local_type_param_bound_len)
  {
    name,
    type_params,
    type_param_bounds,
    extends_names,
    extends_args,
    fields,
    readonly_fields,
    index_signatures,
    method_type_params,
  }
}

///|
/// Skip until semicolon or end of file, respecting brace/bracket/paren nesting
fn Parser::skip_until_semicolon(self : Parser) -> Unit {
  let mut brace_depth = 0
  let mut bracket_depth = 0
  let mut paren_depth = 0
  while !self.check(Eof) {
    match self.peek().kind {
      Semicolon => {
        if brace_depth == 0 && bracket_depth == 0 && paren_depth == 0 {
          let _ = self.advance()
          return
        }
        let _ = self.advance()
      }
      LBrace => {
        brace_depth += 1
        let _ = self.advance()
      }
      RBrace => {
        brace_depth -= 1
        let _ = self.advance()
      }
      LBracket => {
        bracket_depth += 1
        let _ = self.advance()
      }
      RBracket => {
        bracket_depth -= 1
        let _ = self.advance()
      }
      LParen => {
        paren_depth += 1
        let _ = self.advance()
      }
      RParen => {
        paren_depth -= 1
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
}

///|
fn type_alias_object_fields_to_interface(
  name : String,
  type_params : Array[String],
  type_ : @ast.TsType,
) -> @ast.TsInterface? {
  match type_ {
    @ast.TsType::Object(fields) => {
      let iface_fields : Array[(String, @ast.TsType)] = []
      for field in fields {
        let (key_type, value_type) = field
        match key_type {
          @ast.TsType::Literal(field_name) =>
            iface_fields.push((field_name, value_type))
          _ => return None
        }
      }
      Some({
        name,
        type_params,
        extends_names: [],
        extends_args: [],
        fields: iface_fields,
        readonly_fields: [],
        index_signatures: [],
        type_param_bounds: [],
        method_type_params: [],
      })
    }
    _ => None
  }
}

///|
fn type_alias_to_interface(type_alias : @ast.TsTypeAlias) -> @ast.TsInterface? {
  // The conversion from `type X<T extends Bound> = { ... }` to interface is
  // already lossy on T (the resulting interface is treated structurally,
  // without the generic flowing through bridge synthesis). When the alias has
  // bounds, substitute every reference to a bounded type-param with the bound
  // BEFORE conversion. This recovers concrete shapes at value positions like
  // `form: Record<string, T | T[]>` → `Record<string, FormValue | FormValue[]>`
  // while leaving non-Object aliases (e.g. `DateArg<DateType> = DateType | ...`)
  // untouched, since `type_alias_object_fields_to_interface` only fires on
  // Object bodies.
  let body = if type_alias.type_param_bounds.length() > 0 {
    substitute_alias_param_bounds(
      type_alias.type_,
      type_alias.type_param_bounds,
    )
  } else {
    type_alias.type_
  }
  type_alias_object_fields_to_interface(
    type_alias.name,
    type_alias.type_params,
    body,
  )
}

///|
// Walk `type_` and substitute every `Named(name)` reference whose `name`
// appears in `bounds` with that name's bound. Operates structurally over
// every TsType variant. Used by `type_alias_to_interface` to project a
// generic Object-alias body into a concrete interface body.
fn substitute_alias_param_bounds(
  type_ : @ast.TsType,
  bounds : Array[(String, @ast.TsType)],
) -> @ast.TsType {
  fn lookup_bound(name : String) -> @ast.TsType? {
    for entry in bounds {
      if entry.0 == name {
        return Some(entry.1)
      }
    }
    None
  }

  fn walk(t : @ast.TsType) -> @ast.TsType {
    match t {
      Named(name) =>
        match lookup_bound(name) {
          Some(b) => b
          None => t
        }
      Applied(name, args) => {
        let new_args : Array[@ast.TsType] = []
        for a in args {
          new_args.push(walk(a))
        }
        Applied(name, new_args)
      }
      Array(inner) => Array(walk(inner))
      Tuple(items) => {
        let out : Array[@ast.TsType] = []
        for it in items {
          out.push(walk(it))
        }
        Tuple(out)
      }
      Object(fields) => {
        let out : Array[(@ast.TsType, @ast.TsType)] = []
        for f in fields {
          out.push((walk(f.0), walk(f.1)))
        }
        Object(out)
      }
      Func(params, ret) => {
        let new_params : Array[@ast.TsType] = []
        for p in params {
          new_params.push(walk(p))
        }
        Func(new_params, walk(ret))
      }
      Union(items) => {
        let out : Array[@ast.TsType] = []
        for it in items {
          out.push(walk(it))
        }
        Union(out)
      }
      Intersection(items) => {
        let out : Array[@ast.TsType] = []
        for it in items {
          out.push(walk(it))
        }
        Intersection(out)
      }
      Conditional(c, e, tb, fb) =>
        Conditional(walk(c), walk(e), walk(tb), walk(fb))
      IndexedAccess(base, k) => IndexedAccess(walk(base), walk(k))
      _ => t
    }
  }

  walk(type_)
}

///|
fn Parser::parse_type_alias_after_type_keyword(
  self : Parser,
) -> @ast.TsTypeAlias raise ParseError {
  let name = self.parse_binding_ident()
  // Capture the bounds in the AST so bridge passes can consult them at
  // use sites; do NOT push them as local bindings, because doing so would let
  // `parse_type` substitute `Named(T) → bound` inside the alias body, eagerly
  // erasing the generic shape (e.g. `DateArg<DateType>` would become
  // `Date | ...` and lose precision).
  let (type_params, const_flags, type_param_bounds) = self.parse_type_param_names_bounds_and_const_flags()
  // TS2314: a generic type alias with no defaulted type parameter requires all
  // of its type arguments; a bare reference (`A` without `<...>`) is an error.
  // Read before the alias body is parsed (which could clobber the flag via a
  // nested generic).
  if type_params.length() > 0 && not(self.last_type_params_had_default) {
    self.interface_member_modifier_misuses.push(
      "<generic-noarg-required>\{name}",
    )
  }
  // TS1277: a `const` modifier on a type-alias type parameter is invalid
  // (only functions, methods, and classes allow it). `type T<const U> = …`.
  for i, name_i in type_params {
    if i < const_flags.length() && const_flags[i] {
      self.interface_member_modifier_misuses.push("<const-typeparam>\{name_i}")
    }
  }
  let _ = self.expect(Eq)
  let alias_type = self.parse_type()
  self.consume_semicolon()
  { name, type_params, type_param_bounds, type_: alias_type }
}

///|
fn Parser::parse_type_alias(self : Parser) -> @ast.TsTypeAlias raise ParseError {
  let _ = self.expect(Type)
  self.parse_type_alias_after_type_keyword()
}

///|
/// Skip declaration block (namespace, module, class, enum, etc.)
fn Parser::skip_declaration_block(self : Parser) -> Unit {
  // Skip until we find { or ;
  while !self.check(LBrace) && !self.check(Semicolon) && !self.check(Eof) {
    let _ = self.advance()
  }
  if self.check(Semicolon) {
    let _ = self.advance()
    return
  }
  if self.check(LBrace) {
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
}

///|
// / declare function (without 'declare function' prefix - already consumed)

///|
/// name(params): returnType;
pub fn Parser::parse_declare_function(
  self : Parser,
) -> @ast.TsImport raise ParseError {

  // function
  let name = self.parse_binding_ident()

  let (type_params, type_param_bounds) = self.parse_type_param_names_and_bounds()
  let local_type_param_bound_len = self.push_local_type_param_bounds(
    type_param_bounds,
  )
  // parameter
  let _ = self.expect(LParen)
  let params : Array[(String, @ast.TsType)] = []
  let param_is_rest : Array[Bool] = []
  while !self.check(RParen) && !self.check(Eof) {
    // Handle rest parameter: ...name
    let is_rest = self.match_ellipsis()
    let param_name = self.parse_declare_param_name()
    // Handle optional parameter: name?
    let is_optional = self.match_(Question)
    // Type annotation is optional
    let computed_param_type = if self.check(Colon) {
      let _ = self.advance()
      let parsed = self.parse_type()
      if is_optional {
        wrap_optional_ts_type(parsed)
      } else {
        parsed
      }
    } else if is_optional {
      wrap_optional_ts_type(@ast.TsType::Any)
    } else {
      @ast.TsType::Any
    }
    // TypeScript's `this` parameter at index 0 (`afterAll(this: unknown,
    // fn, timeout)`) types the receiver — there is no runtime arg for
    // it. Drop it so the generated `bridge.js` body doesn't emit
    // `function f(this, ...)`, which Node rejects as a syntax error.
    if !(param_name == "this" && params.length() == 0) {
      params.push((param_name, computed_param_type))
      param_is_rest.push(is_rest)
    }
    if self.check(Comma) {
      let _ = self.advance()
    }
  }
  let _ = self.expect(RParen)

  // return valuetype — annotation is optional (TS treats a missing one as
  // `void` for `declare function`, but we use `Any` so the checker matches
  // the convention used elsewhere for un-annotated functions).
  let return_type = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    @ast.TsType::Any
  }
  self.restore_local_type_param_bounds(local_type_param_bound_len)
  self.consume_semicolon()
  { name, module_: "env", type_params, params, param_is_rest, return_type }
}

///|
fn Parser::parse_declare_param_name(self : Parser) -> String raise ParseError {
  match self.peek().kind {
    Ident(n) => {
      let _ = self.advance()
      n
    }
    StringType => {
      let _ = self.advance()
      "string"
    }
    NumberType => {
      let _ = self.advance()
      "number"
    }
    BooleanType => {
      let _ = self.advance()
      "boolean"
    }
    VoidType => {
      let _ = self.advance()
      "void"
    }
    Type => {
      let _ = self.advance()
      "type"
    }
    New => {
      let _ = self.advance()
      "new"
    }
    Delete => {
      let _ = self.advance()
      "delete"
    }
    Typeof => {
      let _ = self.advance()
      "typeof"
    }
    In => {
      let _ = self.advance()
      "in"
    }
    Of => {
      let _ = self.advance()
      "of"
    }
    From => {
      let _ = self.advance()
      "from"
    }
    As => {
      let _ = self.advance()
      "as"
    }
    LBrace | LBracket => {
      let open_tok = self.peek().kind
      let close_tok : TokenKind = match open_tok {
        LBrace => RBrace
        _ => RBracket
      }
      let _ = self.advance()
      let mut depth = 1
      while depth > 0 && !self.check(Eof) {
        if self.peek().kind == open_tok {
          depth += 1
        } else if self.peek().kind == close_tok {
          depth -= 1
        }
        let _ = self.advance()
      }
      "<destructured>"
    }
    k => raise ParseError("Expected parameter name, got \{k}")
  }
}

///|
fn Parser::parse_declare_values(
  self : Parser,
) -> Array[@ast.TsValueDecl] raise ParseError {
  let values : Array[@ast.TsValueDecl] = []
  let name = self.parse_binding_ident()
  let type_ = self.parse_var_decl_type()
  if self.match_(Eq) {
    let _ = self.parse_expr()
  }
  values.push({ name, type_ })
  while self.match_(Comma) {
    let next_name = self.parse_binding_ident()
    let next_type = self.parse_var_decl_type()
    if self.match_(Eq) {
      let _ = self.parse_expr()
    }
    values.push({ name: next_name, type_: next_type })
  }
  self.consume_semicolon()
  values
}

///|
fn Parser::parse_declare_signature_params(
  self : Parser,
) -> Array[(String, @ast.TsType)] raise ParseError {
  let _ = self.expect(LParen)
  let params : Array[(String, @ast.TsType)] = []
  while !self.check(RParen) && !self.check(Eof) {
    let _ = self.match_ellipsis()
    // A parameter-property modifier (`public` / `private` / `protected` /
    // `readonly`) on a declare-class member signature is always TS2369: these
    // signatures have no implementation. A leading modifier is only a modifier
    // when another identifier (the real parameter name, or a further modifier)
    // follows; otherwise the keyword *is* the parameter name (`readonly: T`).
    let mut saw_param_prop_modifier = false
    while true {
      let is_modifier = match self.peek().kind {
        Ident(m) =>
          (
            m == "public" ||
            m == "private" ||
            m == "protected" ||
            m == "readonly"
          ) &&
          self.peek_at(1).kind is Ident(_)
        _ => false
      }
      if is_modifier {
        let _ = self.advance()
        saw_param_prop_modifier = true
      } else {
        break
      }
    }
    let param_name = self.parse_declare_param_name()
    if saw_param_prop_modifier {
      self.param_property_misuses.push(param_name)
    }
    let is_optional = self.match_(Question)
    let base_param_type = if self.check(Colon) {
      let _ = self.advance()
      self.parse_type()
    } else {
      @ast.TsType::Any
    }
    let param_type = if is_optional {
      wrap_optional_ts_type(base_param_type)
    } else {
      base_param_type
    }
    // TypeScript's `this` parameter (`fn(this: T, x: number): void`) types
    // the receiver and is dropped at the JS boundary — there's no runtime
    // arg for it. Skipping it here keeps the generated `bridge.js` from
    // emitting `function f(this, ...)`, which `node` rejects with a
    // `SyntaxError: Unexpected token 'this'`.
    if !(param_name == "this" && params.length() == 0) {
      params.push((param_name, param_type))
    }
    if self.check(Comma) {
      let _ = self.advance()
    }
  }
  let _ = self.expect(RParen)
  params
}

///|

///|
/// Cheap shape check: confirms the token stream starts with `[ Ident :`,
/// the canonical opening of a TS index signature inside a class /
/// interface body. Returns false for the general computed-name pattern
/// `[expr]: T` so the existing skip path still handles it.
fn Parser::is_index_signature_shape_after_lbracket(self : Parser) -> Bool {
  if !self.check(LBracket) {
    return false
  }
  match (self.peek_at(1).kind, self.peek_at(2).kind) {
    (Ident(_), Colon) => true
    _ => false
  }
}

///|
/// Parse a TS index signature inside a class body: `[name: KeyType]:
/// ValueType`. Returns `None` if the shape doesn't match — callers
/// fall back to the original skip path.
fn Parser::try_parse_class_index_signature(
  self : Parser,
) -> (@ast.TsType, @ast.TsType, String?)? raise ParseError {
  let saved = self.pos
  let _ = self.expect(LBracket)
  match self.peek().kind {
    Ident(_) => {
      let _ = self.advance()
    }
    _ => {
      self.pos = saved
      return None
    }
  }
  if !self.match_(Colon) {
    self.pos = saved
    return None
  }
  let key_type = self.parse_type()
  if !self.match_(RBracket) {
    self.pos = saved
    return None
  }
  if !self.match_(Colon) {
    self.pos = saved
    return None
  }
  // A value that is a *naked bounded type parameter* (`[x: number]: T` with
  // `T extends Base` in scope) is about to be widened to its bound by
  // `parse_type`'s constraint inlining. Capture the parameter name first so
  // derived-class index-signature compatibility (TS2415) can still see the
  // generic slot; the widened value stays in the AST for every other
  // consumer.
  let naked_param : String? = match self.peek().kind {
    Ident(n) if self.local_type_param_bound(n) is Some(_) =>
      match self.peek_at(1).kind {
        Semicolon | RBrace => Some(n)
        _ => None
      }
    _ => None
  }
  let value_type = self.parse_type()
  self.consume_semicolon()
  Some((key_type, value_type, naked_param))
}

///|
fn Parser::parse_declare_class_member_name(
  self : Parser,
) -> String? raise ParseError {
  if self.match_(LBracket) {
    let mut depth = 1
    while depth > 0 && !self.check(Eof) {
      match self.peek().kind {
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
    return None
  }
  let name = match self.advance().kind {
    Ident(n) => n
    PrivateIdent(n) => "#" + n
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
    Declare => "declare"
    Type => "type"
    Let => "let"
    Const => "const"
    Var => "var"
    Class => "class"
    New => "new"
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
    k => raise ParseError("Expected class member name, got \{k}")
  }
  Some(name)
}

///|
fn Parser::parse_declare_class_base_names(
  self : Parser,
) -> (Array[String], Array[String]) {
  let names : Array[String] = []
  let implements_names : Array[String] = []
  let mut paren_depth = 0
  let mut bracket_depth = 0
  let mut brace_depth = 0
  let mut angle_depth = 0
  let mut in_extends = false
  let mut in_implements = false
  let mut expect_name = false
  while !self.check(Eof) {
    match self.peek().kind {
      LBrace if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => break
      Extends if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => {
        in_extends = true
        in_implements = false
        expect_name = true
        let _ = self.advance()
      }
      Ident("implements") if paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => {
        in_extends = false
        in_implements = true
        expect_name = true
        let _ = self.advance()
      }
      Ident(name) if (in_extends || in_implements) &&
        expect_name &&
        paren_depth == 0 &&
        bracket_depth == 0 &&
        brace_depth == 0 &&
        angle_depth == 0 => {
        let mut full_name = name
        let _ = self.advance()
        while self.check(Dot) {
          match self.peek_at(1).kind {
            Ident(part) => {
              let _ = self.advance()
              let _ = self.advance()
              full_name = full_name + "." + part
            }
            _ => break
          }
        }
        if in_implements {
          implements_names.push(full_name)
        } else {
          names.push(full_name)
        }
        expect_name = false
      }
      LParen => {
        paren_depth += 1
        let _ = self.advance()
      }
      RParen => {
        if paren_depth > 0 {
          paren_depth -= 1
        }
        let _ = self.advance()
      }
      LBracket => {
        bracket_depth += 1
        let _ = self.advance()
      }
      RBracket => {
        if bracket_depth > 0 {
          bracket_depth -= 1
        }
        let _ = self.advance()
      }
      LBrace => {
        brace_depth += 1
        let _ = self.advance()
      }
      RBrace => {
        if brace_depth > 0 {
          brace_depth -= 1
        }
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
      Comma => {
        if (in_extends || in_implements) &&
          paren_depth == 0 &&
          bracket_depth == 0 &&
          brace_depth == 0 &&
          angle_depth == 0 {
          expect_name = true
        }
        let _ = self.advance()
      }
      _ => {
        let _ = self.advance()
      }
    }
  }
  (names, implements_names)
}

///|
fn upsert_class_property(
  properties : Array[@ast.TsClassPropertyDecl],
  property : @ast.TsClassPropertyDecl,
) -> Unit {
  for i in 0..<properties.length() {
    let existing = properties[i]
    if existing.name == property.name &&
      existing.is_static == property.is_static {
      let merged_type = match existing.type_ {
        Any => property.type_
        _ => existing.type_
      }
      properties[i] = {
        name: existing.name,
        type_: merged_type,
        is_static: existing.is_static,
        is_readonly: existing.is_readonly && property.is_readonly,
        is_accessor: false,
        has_initializer: false,
        has_definite_assertion: false,
      }
      return
    }
  }
  properties.push(property)
}

///|
fn Parser::parse_declare_class(
  self : Parser,
  is_abstract : Bool,
) -> @ast.TsClassDecl raise ParseError {
  let _ = self.expect(Class)
  let name = self.parse_binding_ident()
  let mut class_type_params : Array[String] = []
  let mut class_type_param_bounds : Array[(String, @ast.TsType)] = []
  let mut class_type_param_bound_len = self.local_type_param_bounds.length()
  if self.check(Lt) {
    let (names, type_param_bounds) = self.parse_type_param_names_and_bounds()
    class_type_params = names
    class_type_param_bounds = type_param_bounds
    // TS2314: a generic `declare class` with no defaulted type parameter
    // requires all of its type arguments on a bare reference. Read the flag
    // before the base / body parse clobbers it via a nested generic.
    if name != "" &&
      names.length() > 0 &&
      not(self.last_type_params_had_default) {
      self.interface_member_modifier_misuses.push(
        "<generic-noarg-required>\{name}",
      )
    }
    class_type_param_bound_len = self.push_local_type_param_bounds(
      type_param_bounds,
    )
  }
  let (base_names, implements_names) = self.parse_declare_class_base_names()
  let _ = self.expect(LBrace)
  let properties : Array[@ast.TsClassPropertyDecl] = []
  let methods : Array[@ast.TsClassMethodDecl] = []
  let private_members : Array[String] = []
  let protected_members : Array[String] = []
  let abstract_members : Array[String] = []
  let index_signatures : Array[(@ast.TsType, @ast.TsType)] = []
  let static_blocks : Array[@ast.TsBlock] = []
  let mut constructor_params : Array[(String, @ast.TsType)]? = None
  let mut saw_public_constructor = false
  let mut saw_nonpublic_constructor = false
  while !self.check(RBrace) && !self.check(Eof) {
    if self.match_(Semicolon) {
      continue
    }
    // Index signature: `[name: KeyType]: ValueType`. Detect before any
    // modifier consumption so the shape isn't lost when the body opens
    // with `[`. Stale-pattern bail-out: revert to the original skip
    // path if the syntax doesn't match.
    if self.check(LBracket) && self.is_index_signature_shape_after_lbracket() {
      match self.try_parse_class_index_signature() {
        Some(sig) => {
          index_signatures.push((sig.0, sig.1))
          continue
        }
        None => ()
      }
    }
    let mut is_static = false
    let mut is_readonly = false
    let mut is_public = true
    let mut visibility = "public"
    let mut is_accessor = false
    let mut is_abstract_member = false
    let mut has_modifier = true
    while has_modifier {
      has_modifier = false
      match self.peek().kind {
        Ident(mod) if mod == "static" ||
          mod == "readonly" ||
          mod == "override" ||
          mod == "abstract" ||
          mod == "declare" ||
          mod == "accessor" ||
          mod == "public" ||
          mod == "private" ||
          mod == "protected" => {
          // A modifier-like keyword followed directly by `:` / `?:` / `(`
          // / `;` is actually being used as a class member name (TS allows
          // reserved words as property names). Stop consuming modifiers
          // so the regular member-name path picks it up. Drizzle uses
          // this for `protected: TValue` brand fields.
          match self.peek_at(1).kind {
            Colon | LParen | Semicolon | Comma | Eq => break
            Question =>
              match self.peek_at(2).kind {
                Colon | LParen | Semicolon | Comma | Eq => break
                _ => ()
              }
            _ => ()
          }
          let _ = self.advance()
          if mod == "static" {
            is_static = true
          }
          if mod == "readonly" {
            is_readonly = true
          }
          if mod == "accessor" {
            is_accessor = true
          }
          if mod == "private" || mod == "protected" {
            is_public = false
            visibility = mod
          }
          if mod == "abstract" {
            is_abstract_member = true
          }
          has_modifier = true
        }
        _ => ()
      }
    }
    // Static initialization block: `static { ... }`. Captured so the
    // checker's definite-assignment pass can see assignments to outer
    // variables (these blocks run at class-definition time).
    if is_static && self.check(LBrace) {
      static_blocks.push(self.parse_block())
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
    let member_name = self.parse_declare_class_member_name()
    match member_name {
      Some(n) => {
        if visibility == "private" {
          private_members.push(n)
        } else if visibility == "protected" {
          protected_members.push(n)
        }
        if is_abstract_member {
          abstract_members.push(n)
        }
      }
      None => ()
    }
    let _ = self.match_(Question)
    // Definite-assignment assertion (`foo!: T`) on a class field. Also
    // tolerate a stray `!` after a method name even though that is not
    // standard syntax, mirroring how the runtime class parser handles it.
    let has_definite_assertion = self.match_(Bang)
    let mut local_type_param_bound_len = self.local_type_param_bounds.length()
    let mut method_type_params : Array[String] = []
    let mut method_type_param_bounds : Array[(String, @ast.TsType)] = []
    if self.check(Lt) {
      let (names, type_param_bounds) = self.parse_type_param_names_and_bounds()
      method_type_params = names
      method_type_param_bounds = type_param_bounds
      local_type_param_bound_len = self.push_local_type_param_bounds(
        type_param_bounds,
      )
    }
    if self.check(LParen) {
      let params = self.parse_declare_signature_params()
      let return_type = if self.check(Colon) {
        let _ = self.advance()
        self.parse_type()
      } else {
        @ast.TsType::Any
      }
      self.restore_local_type_param_bounds(local_type_param_bound_len)
      self.consume_semicolon()
      match member_name {
        Some(member_name) =>
          match accessor_kind {
            Some("get") if is_public =>
              upsert_class_property(properties, {
                name: member_name,
                type_: return_type,
                is_static,
                is_readonly: true,
                is_accessor: false,
                has_initializer: false,
                has_definite_assertion: false,
              })
            Some("set") if is_public => {
              let setter_type = if params.length() > 0 {
                let (_, type_) = params[0]
                type_
              } else {
                @ast.TsType::Any
              }
              upsert_class_property(properties, {
                name: member_name,
                type_: setter_type,
                is_static,
                is_readonly: false,
                is_accessor: false,
                has_initializer: false,
                has_definite_assertion: false,
              })
            }
            _ =>
              if member_name == "constructor" &&
                !is_static &&
                accessor_kind is None {
                if is_public {
                  constructor_params = Some(params)
                  saw_public_constructor = true
                } else {
                  saw_nonpublic_constructor = true
                }
              } else if is_public {
                methods.push({
                  name: member_name,
                  type_params: method_type_params,
                  type_param_bounds: method_type_param_bounds,
                  params,
                  return_type,
                  is_static,
                  // Ambient class declarations (`declare class`) and
                  // interface-style method signatures don't carry a
                  // body — leave it as `None`.
                  body: None,
                  accessor: "",
                  key_expr: None,
                  is_async: false,
                  is_generator: false,
                  param_defaults: [],
                  param_is_rest: [],
                })
              }
          }
        None => ()
      }
      continue
    }
    self.restore_local_type_param_bounds(local_type_param_bound_len)
    let mut property_type = @ast.TsType::Any
    if self.match_(Colon) {
      property_type = self.parse_type()
    }
    let has_initializer = if self.match_(Eq) {
      let _ = self.parse_assignment()
      true
    } else {
      false
    }
    self.consume_semicolon()
    match member_name {
      Some(member_name) if is_public && accessor_kind is None =>
        upsert_class_property(properties, {
          name: member_name,
          type_: property_type,
          is_static,
          is_readonly,
          is_accessor,
          has_initializer,
          has_definite_assertion,
        })
      _ => ()
    }
  }
  let _ = self.expect(RBrace)
  let _ = self.match_(Semicolon)
  let is_constructible = if saw_public_constructor {
    !is_abstract
  } else if saw_nonpublic_constructor {
    false
  } else {
    !is_abstract
  }
  self.restore_local_type_param_bounds(class_type_param_bound_len)
  {
    name,
    type_params: class_type_params,
    type_param_bounds: class_type_param_bounds,
    computed_field_keys: [],
    base_names,
    implements_names,
    base_expr: None,
    static_field_inits: [],
    static_blocks,
    instance_field_inits: [],
    constructor_params,
    // The ambient `declare class` param parser does not surface rest flags;
    // leave empty (rest detection just no-ops for these).
    constructor_param_is_rest: [],
    constructor_param_defaults: [],
    constructor_body: None,
    properties,
    methods,
    index_signatures,
    is_abstract,
    is_constructible,
    decorators: self.take_pending_decorators(),
    is_declare: true,
    private_members,
    protected_members,
    abstract_members,
    duplicate_member_names: [],
  }
}

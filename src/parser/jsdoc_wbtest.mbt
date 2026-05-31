// JSDoc parser white-box tests.

///|
test "jsdoc: plain `/* */` returns None" {
  let r = parse_jsdoc_block("/* not a jsdoc */")
  match r {
    None => ()
    Some(_) => fail("expected None for non-jsdoc block")
  }
}

///|
test "jsdoc: empty `/** */` returns None" {
  let r = parse_jsdoc_block("/** */")
  match r {
    None => ()
    Some(_) => fail("expected None for empty jsdoc")
  }
}

///|
test "jsdoc: description-only block" {
  let r = parse_jsdoc_block("/** Hello world */").unwrap()
  assert_eq(r.description, "Hello world")
  assert_eq(r.tags.length(), 0)
}

///|
test "jsdoc: multiline description with leading stars" {
  let r = parse_jsdoc_block(
    (
      #|/**
      #| * First line.
      #| * Second line.
      #| */
    ),
  ).unwrap()
  assert_true(r.description.contains("First line"))
  assert_true(r.description.contains("Second line"))
}

///|
test "jsdoc: @internal tag" {
  let r = parse_jsdoc_block("/** @internal */").unwrap()
  assert_eq(r.tags.length(), 1)
  match r.tags[0] {
    Internal => ()
    _ => fail("expected Internal")
  }
}

///|
test "jsdoc: @deprecated with message" {
  let r = parse_jsdoc_block("/** @deprecated Use foo instead */").unwrap()
  match r.tags[0] {
    Deprecated(msg) => assert_eq(msg, "Use foo instead")
    _ => fail("expected Deprecated")
  }
}

///|
test "jsdoc: @param with type + name + description" {
  let r = parse_jsdoc_block(
    (
      #|/**
      #| * @param {string} name - The user's name.
      #| */
    ),
  ).unwrap()
  match r.tags[0] {
    Param(name, ty, desc) => {
      assert_eq(name, "name")
      assert_eq(ty, Some("string"))
      assert_eq(desc, "The user's name.")
    }
    _ => fail("expected Param")
  }
}

///|
test "jsdoc: @returns with type" {
  let r = parse_jsdoc_block(
    "/** @returns {boolean} Whether the call succeeded. */",
  ).unwrap()
  match r.tags[0] {
    Returns(ty, desc) => {
      assert_eq(ty, Some("boolean"))
      assert_eq(desc, "Whether the call succeeded.")
    }
    _ => fail("expected Returns")
  }
}

///|
test "jsdoc: @__PURE__ tag" {
  let r = parse_jsdoc_block("/** @__PURE__ */").unwrap()
  match r.tags[0] {
    Pure => ()
    _ => fail("expected Pure")
  }
}

///|
test "jsdoc: @__NO_SIDE_EFFECTS__ tag" {
  let r = parse_jsdoc_block("/** @__NO_SIDE_EFFECTS__ */").unwrap()
  match r.tags[0] {
    NoSideEffects => ()
    _ => fail("expected NoSideEffects")
  }
}

///|
test "jsdoc: mixed tags + description" {
  let r = parse_jsdoc_block(
    (
      #|/**
      #| * Compute the sum.
      #| * @param {number} a
      #| * @param {number} b
      #| * @returns {number}
      #| * @deprecated Use add2 instead.
      #| */
    ),
  ).unwrap()
  assert_true(r.description.contains("Compute the sum"))
  // Tag order is preserved.
  assert_eq(r.tags.length(), 4)
  match r.tags[0] {
    Param(name, ty, _) => {
      assert_eq(name, "a")
      assert_eq(ty, Some("number"))
    }
    _ => fail("expected first tag = Param")
  }
  match r.tags[3] {
    Deprecated(msg) => assert_eq(msg, "Use add2 instead.")
    _ => fail("expected last tag = Deprecated")
  }
}

///|
test "jsdoc: unknown tags fall through to Other" {
  let r = parse_jsdoc_block("/** @version 1.2.3 */").unwrap()
  match r.tags[0] {
    Other(name, content) => {
      assert_eq(name, "version")
      assert_eq(content, "1.2.3")
    }
    _ => fail("expected Other")
  }
}

///|
test "jsdoc: nested braces in type" {
  let r = parse_jsdoc_block("/** @param {{ x: number, y: number }} pt */").unwrap()
  match r.tags[0] {
    Param(name, ty, _) => {
      assert_eq(name, "pt")
      assert_eq(ty, Some("{ x: number, y: number }"))
    }
    _ => fail("expected Param")
  }
}

///|
test "jsdoc: @param / @returns overlay onto untyped JS function" {
  let src = "/**\n" +
    " * @param {number} x\n" +
    " * @param {string} name\n" +
    " * @returns {boolean}\n" +
    " */\n" +
    "function check(x, name) { return name.length > x; }\n"
  let block = parse_block_from_source(src)
  // Function decl parsed as Let(Ident("check"), Any, FuncExpr(f))
  match block.stmts[0] {
    Let(_, _, @ast.TsExpr::FuncExpr(f)) => {
      assert_eq(f.params.length(), 2)
      // First param got `number` from the JSDoc overlay.
      match f.params[0].type_ {
        @ast.TsType::Number => ()
        _ => fail("expected Number for x")
      }
      // Second param got `string`.
      match f.params[1].type_ {
        @ast.TsType::String_ => ()
        _ => fail("expected String_ for name")
      }
      // Return type became `boolean`.
      match f.return_type {
        @ast.TsType::Boolean => ()
        _ => fail("expected Boolean for return")
      }
    }
    _ => fail("expected Let / FuncExpr")
  }
}

///|
test "jsdoc: translate_jsdoc_function_type: function(string): void → arrow type" {
  // `function(string): void` should become `(_0: string) => void`
  // and parse to a valid TsType (FuncType shape).
  let src =
    #|/**
    #| * @param {function(string): void} cb
    #| */
    #|function run(cb) { cb("x"); }
  let block = parse_block_from_source(src)
  match block.stmts[0] {
    Let(_, _, @ast.TsExpr::FuncExpr(f)) =>
      // cb's type should be a function type, not Any.
      match f.params[0].type_ {
        @ast.TsType::Any => fail("expected function type for cb, got Any")
        _ => () // any non-Any type is a win
      }
    _ => fail("expected Let / FuncExpr")
  }
}

///|
test "jsdoc: translate_jsdoc_function_type: function(): boolean → () => boolean" {
  // Zero-parameter JSDoc function type.
  let src =
    #|/**
    #| * @param {function(): boolean} pred
    #| * @returns {string}
    #| */
    #|function applyIf(pred, val) { return pred() ? val : ""; }
  let block = parse_block_from_source(src)
  match block.stmts[0] {
    Let(_, _, @ast.TsExpr::FuncExpr(f)) => {
      match f.params[0].type_ {
        @ast.TsType::Any => fail("expected function type for pred, got Any")
        _ => ()
      }
      match f.return_type {
        @ast.TsType::String_ => ()
        _ => fail("expected String_ for return")
      }
    }
    _ => fail("expected Let / FuncExpr")
  }
}

///|
test "jsdoc: ?Array<string> translates to (Array<string> | null)" {
  let src =
    #|/**
    #| * @param {?Array<string>} tags
    #| * @returns {?number}
    #| */
    #|function process(tags) { return tags ? tags.length : null; }
  let block = parse_block_from_source(src)
  match block.stmts[0] {
    Let(_, _, @ast.TsExpr::FuncExpr(f)) => {
      // tags: Array<string> | null
      match f.params[0].type_ {
        @ast.TsType::Any => fail("expected Array|null for tags, got Any")
        _ => ()
      }
      // return: number | null
      match f.return_type {
        @ast.TsType::Any => fail("expected number|null for return, got Any")
        _ => ()
      }
    }
    _ => fail("expected Let / FuncExpr")
  }
}

///|
test "jsdoc: ?{x:number} translates to ({x:number} | null)" {
  let src =
    #|/**
    #| * @param {?{x: number, y: number}} pt
    #| */
    #|function draw(pt) { }
  let block = parse_block_from_source(src)
  match block.stmts[0] {
    Let(_, _, @ast.TsExpr::FuncExpr(f)) =>
      match f.params[0].type_ {
        @ast.TsType::Any => fail("expected object|null for pt, got Any")
        _ => ()
      }
    _ => fail("expected Let / FuncExpr")
  }
}

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
    #|/**
    #| * First line.
    #| * Second line.
    #| */
    ,
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
    #|/**
    #| * @param {string} name - The user's name.
    #| */
    ,
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
    #|/**
    #| * Compute the sum.
    #| * @param {number} a
    #| * @param {number} b
    #| * @returns {number}
    #| * @deprecated Use add2 instead.
    #| */
    ,
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
  let r = parse_jsdoc_block(
    "/** @param {{ x: number, y: number }} pt */",
  ).unwrap()
  match r.tags[0] {
    Param(name, ty, _) => {
      assert_eq(name, "pt")
      assert_eq(ty, Some("{ x: number, y: number }"))
    }
    _ => fail("expected Param")
  }
}

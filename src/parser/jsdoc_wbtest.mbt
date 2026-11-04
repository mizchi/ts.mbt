// JSDoc parser white-box tests.

///|
using @test {assert_eq}

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

///|
// Issue #26: remaining JSDoc-specific scalar translations and the
// inline-TS-wins rule, complementing the `?T` / function-type cases above.
test "jsdoc: !T strips non-null, Object<K,V> becomes Record, inline TS wins" {
  let src =
    #|/**
    #| * @param {!number} a
    #| * @param {Object<string, number>} b
    #| * @param {string} c
    #| * @returns {!boolean}
    #| */
    #|function f(a, b, c: boolean) { return true; }
  let block = parse_block_from_source(src)
  match block.stmts[0] {
    Let(_, _, @ast.TsExpr::FuncExpr(f)) => {
      // `!number` → number (non-null marker stripped).
      match f.params[0].type_ {
        @ast.TsType::Number => ()
        other => fail("expected Number for a, got \{other}")
      }
      // `Object<string, number>` → Record<string, number>.
      match f.params[1].type_ {
        @ast.TsType::Applied("Record", _) => ()
        other => fail("expected Record for b, got \{other}")
      }
      // Inline `: boolean` annotation wins over the `@param {string} c`.
      match f.params[2].type_ {
        @ast.TsType::Boolean => ()
        other => fail("expected Boolean (inline wins) for c, got \{other}")
      }
      // `!boolean` return → boolean.
      match f.return_type {
        @ast.TsType::Boolean => ()
        other => fail("expected Boolean return, got \{other}")
      }
    }
    _ => fail("expected Let / FuncExpr")
  }
}

///|
test "jsdoc: module block records docs by declaration path" {
  let block = parse_module_block_from_source(
    (
      #|/**
      #| * Make an id.
      #| * @param size How long.
      #| * @returns The id.
      #| */
      #|export declare function nanoid(size?: number): string;
      #|/** Declared without export. */
      #|declare function helper(x: string): void;
      #|/** Options. */
      #|export interface Options {
      #|  /** Base URL. */
      #|  baseUrl: string;
      #|  /** @deprecated use retry */
      #|  retries?: number;
      #|  noDoc: boolean;
      #|}
      #|/** An alias. */
      #|export type Id = string;
      #|export declare function undocumented(): void;
    ),
  )
  assert_eq(
    block.docs.get("nanoid"),
    Some(["Make an id.", "", "- `size`: How long.", "Returns: The id."]),
  )
  assert_eq(block.docs.get("helper"), Some(["Declared without export."]))
  assert_eq(block.docs.get("Options"), Some(["Options."]))
  assert_eq(block.docs.get("Options.baseUrl"), Some(["Base URL."]))
  assert_eq(block.docs.get("Options.retries"), Some(["Deprecated: use retry"]))
  assert_eq(block.docs.get("Id"), Some(["An alias."]))
  // No JSDoc, no entry — never an empty doc.
  assert_eq(block.docs.get("Options.noDoc"), None)
  assert_eq(block.docs.get("undocumented"), None)
}

///|
test "jsdoc: only documentation tags become doc lines" {
  let jb = parse_jsdoc_block(
    "/** Pure helper.\n * @internal\n * @__PURE__\n * @example\n * f(1)\n */",
  ).unwrap()
  assert_eq(jsdoc_doc_lines(jb), [
    "Pure helper.", "", "Example:", "```", "f(1)", "```",
  ])
  // A block of tool markers only has nothing to document.
  let markers = parse_jsdoc_block("/** @internal */").unwrap()
  assert_eq(jsdoc_doc_lines(markers), [])
}

///|
test "jsdoc: a multi-line tag becomes one entry per line" {
  let jb = parse_jsdoc_block(
    "/**\n * Run it.\n * @param mode How it runs:\n * - `a`: first\n * - `b`: second\n */",
  ).unwrap()
  for line in jsdoc_doc_lines(jb) {
    assert_false(line.contains("\n"))
  }
}

///|
test "jsdoc: declarations inside a namespace or declare module body are recorded" {
  // Both bodies are re-parsed by a FRESH parser through a different loop;
  // the declaration parsers record, and the parent absorbs the child's docs.
  let block = parse_module_block_from_source(
    (
      #|declare namespace ns {
      #|  /** A node. */
      #|  interface Node {
      #|    /** Its kind. */
      #|    kind: number;
      #|  }
      #|  /** Make one. */
      #|  function createNode(kind: number): Node;
      #|}
      #|declare module "fsish" {
      #|  /** Read a file. */
      #|  export function readFileSync(path: string): string;
      #|}
    ),
  )
  assert_eq(block.docs.get("Node"), Some(["A node."]))
  assert_eq(block.docs.get("Node.kind"), Some(["Its kind."]))
  assert_eq(block.docs.get("createNode"), Some(["Make one."]))
  assert_eq(block.docs.get("readFileSync"), Some(["Read a file."]))
}

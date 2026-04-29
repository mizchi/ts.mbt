///|
test "parser: emit MoonBit declarations from interface and declare function" {
  let src =
    #|interface Point {
    #|  x: number;
    #|  y: number;
    #|}
    #|
    #|declare function draw(point: Point, labels: string[]): void;
  let actual = emit_moonbit_decl_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let expected =
    #|///|
    #|/// Generated from TypeScript declarations by mizchi/ts/parser.
    #|/// Complex or unsupported TypeScript types are widened to JSValue.
    #|
    #|///|
    #|/// TS interface Point
    #|/// x : Double
    #|/// y : Double
    #|declare pub type Point
    #|
    #|///|
    #|declare pub fn draw(point : Point, labels : Array[String]) -> Unit
  assert_eq(actual, expected)
}

///|
test "parser: emit MoonBit declarations widens unsupported types" {
  let src =
    #|declare function later(
    #|  callback: (value: number) => void,
    #|  promise: Promise<string>,
    #|): Promise<number>;
  let actual = emit_moonbit_decl_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  let expected =
    #|///|
    #|/// Generated from TypeScript declarations by mizchi/ts/parser.
    #|/// Complex or unsupported TypeScript types are widened to JSValue.
    #|
    #|///|
    #|declare pub type JSValue
    #|
    #|///|
    #|declare pub type Promise
    #|
    #|///|
    #|declare pub fn later(callback : JSValue, promise : Promise) -> Promise
  assert_eq(actual, expected)
}

///|
test "parser: emit MoonBit declarations sanitizes parameter names" {
  let src = "declare function useKeywords(in: string, type: number): void;"
  let actual = emit_moonbit_decl_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_true(
    actual.contains(
      "declare pub fn useKeywords(in_ : String, type_ : Double) -> Unit",
    ),
  )
}

///|
test "parser: emit MoonBit declarations sanitizes future reserved parameter names" {
  let src =
    #|interface RuntimeOptions {
    #|  override: boolean;
    #|  method: string;
    #|}
    #|declare function transpose(constructor: unknown): void;
  let actual = emit_moonbit_decl_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_true(actual.contains("/// override : Bool"))
  assert_true(actual.contains("/// method : String"))
  assert_true(
    actual.contains("declare pub fn transpose(constructor_ : JSValue) -> Unit"),
  )
}

///|
test "parser: emit MoonBit declaration type names with leading underscores" {
  let src = "interface _ZodType { value: string; }"
  let actual = emit_moonbit_decl_from_source(src) catch {
    e => {
      fail("Parse error: \{e}")
      return
    }
  }
  assert_true(actual.contains("declare pub type UnderscoreZodType"))
}
